extends SceneTree

var failures: Array[String] = []
var checks := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("LOCALIZATION FAILURE: " + message)

func _initialize() -> void:
	_run.call_deferred()

func _disable_system_fallback(font: Font) -> void:
	if font is FontFile: font.allow_system_fallback = false
	if font is FontVariation and font.base_font: _disable_system_fallback(font.base_font)
	for fallback in font.fallbacks: _disable_system_fallback(fallback)

func _run() -> void:
	var original_locale := DungeonLocale.current_locale()
	var original_path := DungeonLocale.settings_path
	DungeonLocale.settings_path = "user://locale-test-%d.cfg" % Time.get_ticks_usec()
	check(DungeonLocale.language_options().size() == 13, "Thirteen languages are available")
	for pair in [["zh-Hans-CN", "zh_CN"], ["zh_Hant_HK", "zh_TW"], ["ja_JP", "ja"], ["in_ID", "id"], ["pt_BR", "pt"], ["es_MX", "es"]]:
		check(DungeonLocale.normalize_locale(pair[0]) == pair[1], "Regional locale: " + pair[0])
	check(not DungeonLocale.set_locale("unsupported_language", false), "Unsupported selection is rejected")
	var rich := RichTextLabel.new()
	rich.bbcode_enabled = true
	root.add_child(rich)
	var compact_samples := {"zh_CN": "1.5万", "zh_TW": "1.5萬", "en": "15.0K", "ja": "1.5万", "ko": "1.5만", "id": "15,0rb", "th": "15.0พัน", "vi": "15,0K", "de": "15,0 Tsd.", "fr": "15,0k", "pt": "15,0 mil", "es": "15,0 mil", "ru": "15,0 тыс."}
	for entry in DungeonLocale.language_options():
		var started := Time.get_ticks_msec()
		check(DungeonLocale.set_locale(entry.code, false), "Select " + entry.code)
		check(TranslationServer.get_locale() == entry.code, "Engine locale " + entry.code)
		var start := DungeonLocale.text("开始游戏")
		check(not start.is_empty(), "Start label exists " + entry.code)
		if entry.code != "zh_CN": check(start != "开始游戏", "Start label translated " + entry.code)
		check(TranslationServer.translate("开始游戏") == start, "Native control translation " + entry.code)
		rich.text = ""
		rich.text = "[b]开始游戏[/b]"
		check(rich.get_parsed_text() == start, "Rich text translation preserves formatting " + entry.code)
		var difficulty := DungeonLocale.text("难度 %d") % 12
		check(DungeonLocale.text("难度 12") == difficulty, "Formatted difficulty " + entry.code)
		var resource := DungeonLocale.text("累计获得 %d · 累计消耗 %d") % [123, 45]
		check(DungeonLocale.text("累计获得 123 · 累计消耗 45") == resource, "Two dynamic values " + entry.code)
		check(DungeonLocale.text("42 / 100") == "42 / 100", "Numbers unchanged " + entry.code)
		check(DungeonLocale.compact_number(9999) == "9999", "Small values retain their magnitude " + entry.code)
		check(DungeonLocale.compact_number(15000) == compact_samples[entry.code], "Large values use the correct locale unit and scale " + entry.code)
		var semantic := DungeonCatalog.clean("<#specinfo=gongjili>")
		check(not semantic.is_empty() and not semantic.contains("<"), "Semantic term " + entry.code)
		print("LOCALIZATION_LOCALE ", entry.code, " ", Time.get_ticks_msec() - started, "ms ", start)
	DungeonLocale.set_locale("en", false)
	check(DungeonLocale.text("常驻委托栏") == "Permanent Quest Board", "Building stages translate after splitting their authored names")
	check(DungeonLocale.text("魔物石坛") == "Monster Altar", "Building stage aliases translate inside unlock requirements")
	check(DungeonLocale.text("合计：") == "Total:", "Appended labels retain their translation without the leading newline")
	var training_source := "命中 %d 次 · 总伤害 %.0f\n训练 %.1f 秒 · 每秒伤害 %.1f · 最高单次 %.0f"
	var training_values := [7, 125.0, 4.5, 27.8, 52.0]
	var training := (training_source % training_values) + "\n开始游戏"
	check(DungeonLocale.text(training) == (DungeonLocale.text(training_source) % training_values) + "\n" + DungeonLocale.text("开始游戏"), "Multiline formatted copy translates when other lines are appended")
	var dispatch := DungeonLocale.text("开始游戏\n每次产出：金币 ×4\n耗时 10 分钟 · 领取消耗：金币\n今日剩余 8 / 10 次\n合计：")
	check(RegEx.create_from_string("[\\x{3400}-\\x{9fff}]").search(dispatch) == null and dispatch.contains("8 / 10"), "Dispatch templates translate individual lines and preserve counters")
	rich.free()
	check(DungeonLocale.set_locale("ko", true), "Persist selected language")
	var config := ConfigFile.new()
	check(config.load(DungeonLocale.settings_path) == OK and config.get_value("language", "locale", "") == "ko", "Selected language stored separately from profile")
	DirAccess.remove_absolute(DungeonLocale.settings_path)
	DungeonLocale.settings_path = original_path
	DungeonLocale.set_locale(original_locale, false)
	var font := DungeonStyle.multilingual_font()
	_disable_system_fallback(font)
	var coverage: Dictionary = {}
	for sample: String in ["简体中文", "繁體中文", "English", "日本語", "한국어", "Bahasa Indonesia", "ภาษาไทย", "Tiếng Việt", "Deutsch", "Français", "Português", "Español", "Русский"]:
		var supported := true
		for character in sample:
			if not font.has_char(character.unicode_at(0)): supported = false
		coverage[sample] = supported
		check(supported, "Bundled fonts cover " + sample + " without system fonts")
	print("LOCALIZATION_FONT ", JSON.stringify(coverage))
	print("LOCALIZATION_TEST ", JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
