class_name DungeonCatalog
extends RefCounted

var tables: Dictionary = {}
var config: Dictionary = {}
var errors: Array = []
var _indices: Dictionary = {}
static var _display_terms: Dictionary = {}

func load_all() -> bool:
	tables.clear()
	_indices.clear()
	errors.clear()
	var manifest = _read("manifest")
	if not manifest is Dictionary:
		return false
	for table in manifest.get("tables", {}):
		var value = _read(table)
		if table == "RogueConfigData":
			config = value if value is Dictionary else {}
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
	var text = str(value).replace("<br>", "\n").replace("<br/>", "\n")
	if _display_terms.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/DisplayTerms.json"))
		if parsed is Dictionary: _display_terms = parsed
	var regex = RegEx.new()
	regex.compile("<#specinfo=[\"']?([^>\"']+)[\"']?>")
	for matched in regex.search_all(text):
		var key = matched.get_string(1)
		text = text.replace(matched.get_string(), str(_display_terms.get("specinfo", {}).get(key, "【术语：" + key + "】")))
	# Inline localization carries authored fallback text; keep it when present.
	regex.compile("(?s)<#LocalizationId=[\"']?([^>\"']+)[\"']?>(.*?)</LocalizationId>")
	for matched in regex.search_all(text):
		var fallback = matched.get_string(2)
		var key = matched.get_string(1)
		text = text.replace(matched.get_string(), fallback if not fallback.is_empty() else str(_display_terms.get("localization", {}).get(key, "【文本：" + key + "】")))
	regex.compile("<#LocalizationId=[\"']?([^>\"']+)[\"']?>")
	for matched in regex.search_all(text):
		var key = matched.get_string(1)
		text = text.replace(matched.get_string(), str(_display_terms.get("localization", {}).get(key, "【文本：" + key + "】")))
	regex.compile("<#([^>]+)>")
	for matched in regex.search_all(text): text = text.replace(matched.get_string(), "【" + matched.get_string(1) + "】")
	regex.compile("<[^>]*>")
	return regex.sub(text, "", true)

static func ids(value) -> Array:
	if value is Array:
		return value.map(func(x): return int(x))
	var result = []
	for token in str(value).replace("|", ",").split(",", false):
		if token.strip_edges().is_valid_int():
			result.append(int(token))
	return result
