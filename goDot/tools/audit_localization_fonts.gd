extends SceneTree

var font: FontFile

func _initialize() -> void:
	font = FontFile.new()
	font.data = FileAccess.get_file_as_bytes("res://assets/fonts/default.otf")
	font.allow_system_fallback = false
	var korean := FontFile.new()
	korean.data = FileAccess.get_file_as_bytes("res://assets/fonts/NotoSansKR.ttf")
	korean.allow_system_fallback = false
	var korean_regular := FontVariation.new()
	korean_regular.base_font = korean
	korean_regular.variation_opentype = {"wght": 400.0}
	var thai := FontFile.new()
	thai.data = FileAccess.get_file_as_bytes("res://assets/fonts/NotoSansThai.ttf")
	thai.allow_system_fallback = false
	font.fallbacks = [korean_regular, thai]
	var failures := {}
	var report := {
		"allow_system_fallback": false,
		"fonts": ["default.otf", "NotoSansKR.ttf", "NotoSansThai.ttf"],
		"korean_weight": 400,
		"locales": {},
	}
	var sources: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/localization/sources.json"))
	var overrides: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/localization/overrides.json"))
	var selected := OS.get_cmdline_user_args()
	for locale in ["zh_CN", "zh_TW", "en", "ja", "ko", "id", "th", "vi", "de", "fr", "pt", "es", "ru"]:
		if not selected.is_empty() and locale not in selected:
			continue
		var characters := {}
		var messages := {}
		for directory in ["original", "supplemental"]:
			var path: String = "res://assets/localization/" + directory + "/" + locale + ".json"
			if FileAccess.file_exists(path):
				var values: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
				if values is Dictionary:
					messages.merge(values, true)
		var locale_index: int = overrides.get("locales", []).find(locale)
		if locale_index >= 0:
			for source: String in overrides.get("messages", {}):
				var targets: Array = overrides.messages[source]
				messages[source] = str(targets[locale_index])
				_collect(messages[source], characters)
		for source: String in sources:
			_collect(source if locale == "zh_CN" else str(messages.get(source, "")), characters)
		var keyed_path: String = "res://assets/localization/original/keyed_" + locale + ".json"
		if FileAccess.file_exists(keyed_path):
			var keyed: Variant = JSON.parse_string(FileAccess.get_file_as_string(keyed_path))
			if keyed is Dictionary:
				for value in keyed.values():
					_collect(str(value), characters)
		var missing: Array[String] = []
		for codepoint: int in characters:
			if not font.has_char(codepoint):
				missing.append("U+%04X %s" % [codepoint, String.chr(codepoint)])
		if not missing.is_empty():
			failures[locale] = missing
		report.locales[locale] = {"codepoints": characters.size(), "missing": missing}
		print(JSON.stringify({"locale": locale, "codepoints": characters.size(), "missing": missing}))
	var report_file := FileAccess.open("res://assets/localization/font_report.json", FileAccess.WRITE)
	if report_file == null:
		push_error("Could not write localization font report")
		quit(1)
		return
	report_file.store_string(JSON.stringify(report, "\t") + "\n")
	report_file.close()
	print("ALL_CATALOG_FONT_FAILURES=", JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)

func _collect(value: String, characters: Dictionary) -> void:
	var markup := RegEx.new()
	markup.compile("<[^>]*>|\\[[^\\]\\n]*(?:=|/)[^\\]\\n]*\\]")
	value = markup.sub(value, "", true)
	for index in value.length():
		var codepoint := value.unicode_at(index)
		if codepoint < 32 or codepoint in [0x200b, 0x200c, 0x200d, 0x2060, 0xfeff]:
			continue
		characters[codepoint] = true
