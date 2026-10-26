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

func _run() -> void:
	var original_locale := DungeonLocale.current_locale()
	var original_path := DungeonLocale.settings_path
	DungeonLocale.settings_path = "user://locale-test-%d.cfg" % Time.get_ticks_usec()
	check(DungeonLocale.language_options().size() == 13, "Thirteen languages are available")
	for pair in [["zh-Hans-CN", "zh_CN"], ["zh_Hant_HK", "zh_TW"], ["ja_JP", "ja"], ["in_ID", "id"], ["pt_BR", "pt"], ["es_MX", "es"]]:
		check(DungeonLocale.normalize_locale(pair[0]) == pair[1], "Regional locale: " + pair[0])
	check(not DungeonLocale.set_locale("unsupported_language", false), "Unsupported selection is rejected")
	for entry in DungeonLocale.language_options():
		var started := Time.get_ticks_msec()
		check(DungeonLocale.set_locale(entry.code, false), "Select " + entry.code)
		check(TranslationServer.get_locale() == entry.code, "Engine locale " + entry.code)
		var start := DungeonLocale.text("开始游戏")
		check(not start.is_empty(), "Start label exists " + entry.code)
		if entry.code != "zh_CN": check(start != "开始游戏", "Start label translated " + entry.code)
		check(TranslationServer.translate("开始游戏") == start, "Native control translation " + entry.code)
		var difficulty := DungeonLocale.text("难度 %d") % 12
		check(DungeonLocale.text("难度 12") == difficulty, "Formatted difficulty " + entry.code)
		var resource := DungeonLocale.text("累计获得 %d · 累计消耗 %d") % [123, 45]
		check(DungeonLocale.text("累计获得 123 · 累计消耗 45") == resource, "Two dynamic values " + entry.code)
		check(DungeonLocale.text("42 / 100") == "42 / 100", "Numbers unchanged " + entry.code)
		var semantic := DungeonCatalog.clean("<#specinfo=gongjili>")
		check(not semantic.is_empty() and not semantic.contains("<"), "Semantic term " + entry.code)
		print("LOCALIZATION_LOCALE ", entry.code, " ", Time.get_ticks_msec() - started, "ms ", start)
	check(DungeonLocale.set_locale("ko", true), "Persist selected language")
	var config := ConfigFile.new()
	check(config.load(DungeonLocale.settings_path) == OK and config.get_value("language", "locale", "") == "ko", "Selected language stored separately from profile")
	DirAccess.remove_absolute(DungeonLocale.settings_path)
	DungeonLocale.settings_path = original_path
	DungeonLocale.set_locale(original_locale, false)
	for path in ["res://assets/fonts/default.otf", "res://assets/fonts/default.ttf"]:
		var font := load(path) as Font
		var coverage: Dictionary = {}
		for sample: String in ["繁體中文", "日本語", "한국어", "ภาษาไทย", "Tiếng Việt", "Русский"]:
			var supported := true
			for character in sample:
				if not font.has_char(character.unicode_at(0)): supported = false
			coverage[sample] = supported
		print("LOCALIZATION_FONT ", path, " ", JSON.stringify(coverage))
	print("LOCALIZATION_TEST ", JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
