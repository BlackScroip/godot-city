extends RefCounted

const INDEX_PATH := "res://assets/combat_presentation/runtime/catalog.json"
const SOURCE_PATH := "res://assets/combat_presentation/catalog.json"
const EFFECT_CACHE_CAPACITY := 128
const MATERIAL_CACHE_CAPACITY := 512
static var _catalog: Dictionary = {}
static var _effect_bytes := PackedByteArray()
static var _material_bytes := PackedByteArray()
static var _ranges: Dictionary = {}
static var _effects: Dictionary = {}
static var _materials: Dictionary = {}
static var _effect_keys: Array[String] = []
static var _material_keys: Array[String] = []
static var _effect_cursor := 0
static var _material_cursor := 0
static var descriptor_io_reads := 0
static var effect_parses := 0
static var material_parses := 0

static func load_catalog() -> Dictionary:
	if not _catalog.is_empty(): return _catalog
	if FileAccess.file_exists(INDEX_PATH):
		descriptor_io_reads += 1
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(INDEX_PATH))
		if parsed is Dictionary:
			var manifest: Dictionary = parsed.get("_runtime_descriptors", {})
			if int(manifest.get("schema", 0)) == 1:
				var effects_path = str(manifest.get("effects_path", ""))
				var materials_path = str(manifest.get("materials_path", ""))
				if FileAccess.file_exists(effects_path) and FileAccess.file_exists(materials_path):
					descriptor_io_reads += 2
					_effect_bytes = FileAccess.get_file_as_bytes(effects_path)
					_material_bytes = FileAccess.get_file_as_bytes(materials_path)
					if not _effect_bytes.is_empty() and not _material_bytes.is_empty():
						_catalog = parsed
						_ranges = manifest
						return _catalog
	# Source-only checkouts and older packages retain the original eager API.
	_effect_bytes.clear()
	_material_bytes.clear()
	descriptor_io_reads += 1
	var fallback = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_PATH))
	_catalog = fallback if fallback is Dictionary else {}
	return _catalog

static func resolve(definition: Dictionary) -> Dictionary:
	var key = str(definition.get("_runtime_descriptor", ""))
	return effect(key) if not key.is_empty() else definition

static func effect(key: String) -> Dictionary:
	if _catalog.is_empty(): load_catalog()
	if _effects.has(key): return _effects[key]
	if _ranges.is_empty(): return _catalog.get("effects", {}).get(key, {})
	var span: Array = _ranges.get("effects", {}).get(key, [])
	if span.size() != 2: return {}
	var parsed = JSON.parse_string(_effect_bytes.slice(int(span[0]), int(span[0]) + int(span[1])).get_string_from_utf8())
	if not parsed is Dictionary: return {}
	effect_parses += 1
	if _effect_keys.size() >= EFFECT_CACHE_CAPACITY:
		_effects.erase(_effect_keys[_effect_cursor])
		_effect_keys[_effect_cursor] = key
		_effect_cursor = (_effect_cursor + 1) % EFFECT_CACHE_CAPACITY
	else:
		_effect_keys.append(key)
	_effects[key] = parsed
	return parsed

static func handles_materials(path: String) -> bool:
	if _catalog.is_empty(): load_catalog()
	return not _ranges.is_empty() and path == str(_ranges.get("material_library", ""))

static func materials_for(definition: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for layer in definition.get("layers", []):
		for value in layer.get("materials", []):
			var key = str(value.get("reference", ""))
			if not key.is_empty() and not result.has(key): result[key] = material(key)
	return result

static func material(key: String) -> Dictionary:
	if _materials.has(key): return _materials[key]
	var span: Array = _ranges.get("materials", {}).get(key, [])
	if span.size() != 2: return {}
	var parsed = JSON.parse_string(_material_bytes.slice(int(span[0]), int(span[0]) + int(span[1])).get_string_from_utf8())
	if not parsed is Dictionary: return {}
	material_parses += 1
	if _material_keys.size() >= MATERIAL_CACHE_CAPACITY:
		_materials.erase(_material_keys[_material_cursor])
		_material_keys[_material_cursor] = key
		_material_cursor = (_material_cursor + 1) % MATERIAL_CACHE_CAPACITY
	else:
		_material_keys.append(key)
	_materials[key] = parsed
	return parsed

static func stats() -> Dictionary:
	return {"descriptor_io_reads": descriptor_io_reads, "effect_parses": effect_parses, "material_parses": material_parses, "cached_effects": _effects.size(), "cached_materials": _materials.size(), "archive_bytes": _effect_bytes.size() + _material_bytes.size()}
