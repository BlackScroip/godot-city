class_name DungeonCatalog
extends RefCounted

var tables: Dictionary = {}
var config: Dictionary = {}
var configurations: Dictionary = {}
var errors: Array = []
var _indices: Dictionary = {}
static var _display_terms: Dictionary = {}
static var _cleanup_regexes: Array[RegEx] = []

func load_all() -> bool:
	tables.clear()
	configurations.clear()
	_indices.clear()
	errors.clear()
	var manifest = _read("manifest")
	if not manifest is Dictionary:
		return false
	for table in manifest.get("tables", {}):
		var value = _read(table)
		if table == "EnemyNumericalConfigData" and value is Array and value.size() == 1:
			value = value[0]
		if table == "RogueConfigData":
			config = value if value is Dictionary else {}
		elif table == "EnemyNumericalConfigData" and value is Dictionary:
			configurations[table] = value
		elif value is Array:
			tables[table] = value
			var index = {}
			for row in value:
				index[str(row_id(row))] = row
			_indices[table] = index
		else:
			errors.append("Invalid table: " + table)
	var buildings = config.get("MainCityDevelopDataList", []).duplicate(true)
	for i in buildings.size():
		buildings[i]["id"] = i
	tables["Buildings"] = buildings
	_indices["Buildings"] = {}
	for row in buildings:
		_indices["Buildings"][str(row.id)] = row
	return errors.is_empty() and not config.is_empty()

func _read(table: String):
	var filename = "res://assets/data/" + table + ".json"
	if not FileAccess.file_exists(filename):
		errors.append("Missing data: " + table)
		return null
	var parser = JSON.new()
	if parser.parse(FileAccess.get_file_as_string(filename)) != OK:
		errors.append("Invalid JSON: " + table)
		return null
	return parser.data

func rows(table: String) -> Array:
	return tables.get(table, [])

func find(table: String, id) -> Dictionary:
	return _indices.get(table, {}).get(str(int(id)), {})

static func row_id(row: Dictionary) -> int:
	for key in ["id", "Id", "ID", "GoodsId", "DetailsId"]:
		if row.has(key):
			return int(row[key])
	return 0

static func row_name(row: Dictionary) -> String:
	for key in ["name", "Name", "title", "GoodsName"]:
		if row.has(key):
			return str(row[key])
	return str(row_id(row))

static func description(row: Dictionary) -> String:
	for key in ["description", "Description", "effect_description", "unlock_desc"]:
		if row.has(key):
			return str(row[key])
	return ""

static func clean(value: Variant) -> String:
	var text = DungeonLocale.text(str(value))
	if not text.contains("<"): return text
	text = text.replace("<br>", "\n").replace("<br/>", "\n")
	if _display_terms.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/DisplayTerms.json"))
		if parsed is Dictionary: _display_terms = parsed
	if _cleanup_regexes.is_empty():
		for pattern in ["<#specinfo=[\"']?([^>\"']+)[\"']?>", "(?s)<#LocalizationId=[\"']?([^>\"']+)[\"']?>(.*?)</LocalizationId>", "<#LocalizationId=[\"']?([^>\"']+)[\"']?>", "<#([^>]+)>", "<[^>]*>"]:
			var regex = RegEx.new()
			regex.compile(pattern)
			_cleanup_regexes.append(regex)
	for matched in _cleanup_regexes[0].search_all(text):
		var key = matched.get_string(1)
		var fallback = str(_display_terms.get("specinfo", {}).get(key, "【术语：" + key + "】"))
		text = text.replace(matched.get_string(), DungeonLocale.keyed("<#specinfo=" + key + ">", fallback))
	# Inline localization carries authored fallback text; keep it when present.
	for matched in _cleanup_regexes[1].search_all(text):
		var fallback = matched.get_string(2)
		var key = matched.get_string(1)
		if fallback.is_empty(): fallback = str(_display_terms.get("localization", {}).get(key, "【文本：" + key + "】"))
		text = text.replace(matched.get_string(), DungeonLocale.keyed(key, fallback))
	for matched in _cleanup_regexes[2].search_all(text):
		var key = matched.get_string(1)
		text = text.replace(matched.get_string(), DungeonLocale.keyed(key, str(_display_terms.get("localization", {}).get(key, "【文本：" + key + "】"))))
	for matched in _cleanup_regexes[3].search_all(text): text = text.replace(matched.get_string(), "【" + matched.get_string(1) + "】")
	return _cleanup_regexes[4].sub(text, "", true)

static func ids(value) -> Array:
	if value is Array:
		return value.map(func(x): return int(x))
	var result = []
	for token in str(value).replace("|", ",").split(",", false):
		if token.strip_edges().is_valid_int():
			result.append(int(token))
	return result
