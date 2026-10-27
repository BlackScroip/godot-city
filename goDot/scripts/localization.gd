class_name DungeonLocale
extends Node

signal locale_changed(locale: String)

const LANGUAGES = [
	{"code": "zh_CN", "name": "简体中文"},
	{"code": "zh_TW", "name": "繁體中文"},
	{"code": "en", "name": "English"},
	{"code": "ja", "name": "日本語"},
	{"code": "ko", "name": "한국어"},
	{"code": "id", "name": "Bahasa Indonesia"},
	{"code": "th", "name": "ภาษาไทย"},
	{"code": "vi", "name": "Tiếng Việt"},
	{"code": "de", "name": "Deutsch"},
	{"code": "fr", "name": "Français"},
	{"code": "pt", "name": "Português"},
	{"code": "es", "name": "Español"},
	{"code": "ru", "name": "Русский"},
]
static var settings_path := "user://language.cfg"
static var _initialized := false
static var _locale := "zh_CN"
static var _messages: Dictionary = {}
static var _keyed: Dictionary = {}
static var _cache: Dictionary = {}
static var _phrases: Dictionary = {}
static var _templates: Array[Dictionary] = []
static var _translation: Translation
static var _placeholders: RegEx
static var _han: RegEx
static var _tags: RegEx
static var _overrides: Dictionary = {}

class DisplayTranslation extends Translation:
	func _get_message(src_message: StringName, _context: StringName) -> StringName:
		return StringName(DungeonLocale._translate(String(src_message)))

func _ready() -> void:
	ensure_initialized()

func _exit_tree() -> void:
	if _translation:
		TranslationServer.remove_translation(_translation)
		_translation = null

static func language_options() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in LANGUAGES: result.append(entry.duplicate())
	return result

static func normalize_locale(value: String) -> String:
	var code := value.replace("-", "_").to_lower()
	if code.begins_with("zh"):
		return "zh_TW" if "hant" in code or code.get_slice("_", 1) in ["tw", "hk", "mo"] else "zh_CN"
	var language := code.get_slice("_", 0)
	if language == "jp": language = "ja"
	if language == "kr": language = "ko"
	if language == "in": language = "id"
	for entry in LANGUAGES:
		if entry.code == language: return language
	return ""

static func ensure_initialized() -> void:
	if _initialized: return
	_initialized = true
	_placeholders = RegEx.create_from_string("%%|%[-+0#]*[0-9]*(?:\\.[0-9]+)?[sdifxXoc]")
	_han = RegEx.create_from_string("[\\x{3400}-\\x{9fff}]")
	_tags = RegEx.create_from_string("<[^>]*>")
	_overrides = _read_json("res://assets/localization/overrides.json")
	var config := ConfigFile.new()
	var selected := OS.get_locale()
	if config.load(settings_path) == OK:
		selected = str(config.get_value("language", "locale", selected))
	var arguments := OS.get_cmdline_args()
	for index in arguments.size():
		if arguments[index] == "--language" and index + 1 < arguments.size(): selected = arguments[index + 1]
		if arguments[index].begins_with("--locale="): selected = arguments[index].trim_prefix("--locale=")
	var normalized := normalize_locale(selected)
	_load_locale(normalized if not normalized.is_empty() else "en")

static func current_locale() -> String:
	ensure_initialized()
	return _locale

static func compact_number(value: float) -> String:
	ensure_initialized()
	if not is_finite(value): return "0"
	var magnitude := absf(value)
	if magnitude < 10000: return str(int(value))
	var units: Array
	match _locale:
		"zh_CN": units = [[10000.0, "万"], [100000000.0, "亿"]]
		"zh_TW": units = [[10000.0, "萬"], [100000000.0, "億"]]
		"ja": units = [[10000.0, "万"], [100000000.0, "億"]]
		"ko": units = [[10000.0, "만"], [100000000.0, "억"]]
		"id": units = [[1000.0, "rb"], [1000000.0, "jt"], [1000000000.0, "M"]]
		"th": units = [[1000.0, "พัน"], [1000000.0, "ล้าน"], [1000000000.0, "พันล้าน"]]
		"vi": units = [[1000.0, "K"], [1000000.0, "Tr"], [1000000000.0, " Tỷ"]]
		"de": units = [[1000.0, " Tsd."], [1000000.0, " Mio."], [1000000000.0, " Mrd."]]
		"fr": units = [[1000.0, "k"], [1000000.0, "M"], [1000000000.0, "Md"]]
		"pt", "es": units = [[1000.0, " mil"], [1000000.0, "M"], [1000000000.0, " mil M"]]
		"ru": units = [[1000.0, " тыс."], [1000000.0, " млн"], [1000000000.0, " млрд"]]
		_: units = [[1000.0, "K"], [1000000.0, "M"], [1000000000.0, "B"]]
	var selected: Array = units[0]
	for unit: Array in units:
		if magnitude >= float(unit[0]): selected = unit
	var number := "%.1f" % (value / float(selected[0]))
	if _locale in ["id", "vi", "de", "fr", "pt", "es", "ru"]: number = number.replace(".", ",")
	return number + str(selected[1])

static func set_locale(code: String, persist := true) -> bool:
	ensure_initialized()
	var normalized := normalize_locale(code)
	if normalized.is_empty(): return false
	if persist:
		var config := ConfigFile.new()
		config.set_value("language", "locale", normalized)
		if config.save(settings_path) != OK: return false
	if normalized == _locale: return true
	_load_locale(normalized)
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		var singleton := tree.root.get_node_or_null("Locale")
		if singleton: singleton.locale_changed.emit(_locale)
	return true

static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

static func _load_locale(code: String) -> void:
	_locale = code
	_cache.clear()
	_phrases.clear()
	_templates.clear()
	_messages = _read_json("res://assets/localization/original/" + code + ".json")
	_messages.merge(_read_json("res://assets/localization/supplemental/" + code + ".json"), true)
	var override_index: int = _overrides.get("locales", []).find(code)
	if override_index >= 0:
		for source in _overrides.get("messages", {}):
			var translations: Array = _overrides.messages[source]
			if override_index < translations.size(): _messages[source] = str(translations[override_index])
	_keyed = _read_json("res://assets/localization/original/keyed_" + code + ".json")
	# Controls keep their source text. This also translates values formatted before assignment.
	var aliases: Dictionary = {}
	for source: String in _messages:
		var target := str(_messages[source])
		if target.is_empty(): continue
		var plain_source := _plain(source)
		var plain_target := _plain(target)
		if plain_source != source and not plain_source.is_empty(): aliases[plain_source] = plain_target
		_add_line_aliases(plain_source, plain_target, aliases)
		var source_parts := plain_source.split("|")
		var target_parts := plain_target.split("|")
		if source_parts.size() > 1 and source_parts.size() == target_parts.size():
			for index in source_parts.size():
				_add_line_aliases(source_parts[index], target_parts[index], aliases)
	_messages.merge(aliases, false)
	for source: String in _messages:
		var target := str(_messages[source])
		if source == target or target.is_empty() or _han.search(source) == null: continue
		if _placeholders.search(source) != null:
			_add_template(source, target)
		elif source.length() <= 160 and not source.contains("<"):
			var first := source.substr(0, 1)
			if not _phrases.has(first): _phrases[first] = []
			_phrases[first].append(source)
	for first in _phrases:
		_phrases[first].sort_custom(func(a: String, b: String): return a.length() > b.length())
	_templates.sort_custom(func(a: Dictionary, b: Dictionary): return a.weight > b.weight)
	if _translation: TranslationServer.remove_translation(_translation)
	_translation = DisplayTranslation.new()
	_translation.locale = code
	TranslationServer.add_translation(_translation)
	TranslationServer.set_locale(code)

static func _plain(value: String) -> String:
	return _tags.sub(value.replace("<br>", "\n").replace("<br/>", "\n").replace("<br />", "\n"), "", true)

static func _add_line_aliases(source: String, target: String, aliases: Dictionary) -> void:
	var trimmed_source := source.strip_edges()
	var trimmed_target := target.strip_edges()
	if not trimmed_source.is_empty() and not trimmed_target.is_empty():
		aliases[trimmed_source] = trimmed_target
	var source_lines := source.split("\n")
	var target_lines := target.split("\n")
	if source_lines.size() <= 1 or source_lines.size() != target_lines.size(): return
	# Dynamic menu rows append lines and select individual building/weapon tiers.
	for index in source_lines.size():
		var source_line := source_lines[index].strip_edges()
		var target_line := target_lines[index].strip_edges()
		if not source_line.is_empty() and not target_line.is_empty():
			aliases[source_line] = target_line

static func _escape_regex(value: String) -> String:
	var result := ""
	for character in value:
		if character in "\\.^$|?*+()[]{}": result += "\\"
		result += character
	return result

static func _add_template(source: String, target: String) -> void:
	var pattern := "(?s)^"
	var offset := 0
	var count := 0
	var weight := source.length()
	var source_tokens: Array[String] = []
	for matched in _placeholders.search_all(source):
		pattern += _escape_regex(source.substr(offset, matched.get_start() - offset))
		var token := matched.get_string()
		if token == "%%": pattern += "%"
		else:
			match token.right(1):
				"s": pattern += "(.*?)"
				"c": pattern += "(.)"
				"x", "X": pattern += "([0-9a-fA-F ]+)"
				"o": pattern += "([0-7 ]+)"
				_: pattern += "([-+0-9. ]+)"
			count += 1
			weight -= token.length()
		source_tokens.append(token)
		offset = matched.get_end()
	pattern += _escape_regex(source.substr(offset)) + "$"
	var target_count := 0
	var target_tokens: Array[String] = []
	for matched in _placeholders.search_all(target):
		if matched.get_string() != "%%": target_count += 1
		target_tokens.append(matched.get_string())
	if count == 0 or count != target_count or source_tokens != target_tokens: return
	var regex := RegEx.new()
	if regex.compile(pattern) == OK: _templates.append({"regex": regex, "target": target, "weight": weight})

static func text(source: String) -> String:
	ensure_initialized()
	return _translate(source)

static func keyed(key: String, fallback := "") -> String:
	ensure_initialized()
	if _locale == "zh_CN": return fallback
	# Inline fallback text may already be translated with its surrounding sentence.
	if not fallback.is_empty(): return text(fallback)
	return str(_keyed.get(key, ""))

static func _translate(source: String) -> String:
	if _locale == "zh_CN" or source.is_empty(): return source
	if _cache.has(source): return _cache[source]
	var result := _translate_uncached(source)
	if _cache.size() >= 8192: _cache.clear()
	_cache[source] = result
	return result

static func _translate_uncached(source: String) -> String:
	if _han.search(source) == null: return source
	if _messages.has(source) and not str(_messages[source]).is_empty(): return str(_messages[source])
	for entry in _templates:
		var matched: RegExMatch = entry.regex.search(source)
		if matched == null: continue
		var target: String = entry.target
		var result := ""
		var offset := 0
		var index := 1
		for token in _placeholders.search_all(target):
			result += target.substr(offset, token.get_start() - offset)
			if token.get_string() == "%%": result += "%"
			else:
				result += _translate(matched.get_string(index))
				index += 1
			offset = token.get_end()
		return result + target.substr(offset)
	if source.contains("\n"):
		var lines := PackedStringArray()
		for line in source.split("\n"): lines.append(_translate(line))
		return "\n".join(lines)
	# Names and short labels are often joined with counters or other localized fields.
	var result := ""
	var cursor := 0
	var untranslated := false
	while cursor < source.length():
		var found := false
		for phrase: String in _phrases.get(source.substr(cursor, 1), []):
			if source.substr(cursor, phrase.length()) != phrase: continue
			result += str(_messages[phrase])
			cursor += phrase.length()
			found = true
			break
		if not found:
			var character := source.substr(cursor, 1)
			if _han.search(character) != null: untranslated = true
			result += character
			cursor += 1
	return source if untranslated else result
