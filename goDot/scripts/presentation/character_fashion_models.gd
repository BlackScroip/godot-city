extends RefCounted

const CATALOG := "res://assets/characters/fashions/catalog.json"
static var _models: Dictionary = {}

static func path_for(fashion_id: int) -> String:
	if _models.is_empty() and FileAccess.file_exists(CATALOG):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
		if data is Dictionary: _models = data.get("models", {})
	var path := str(_models.get(str(fashion_id), {}).get("path", ""))
	return path if not path.is_empty() and ResourceLoader.exists(path) else ""
