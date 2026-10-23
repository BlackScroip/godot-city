class_name DungeonSaveStore
extends RefCounted

const SAVE_PATH = "user://dungeon-profile-v1.json"
const MAX_BYTES = 16 * 1024 * 1024
var warning := ""
var path: String

func _init(storage_path: String = SAVE_PATH) -> void:
	path = storage_path

func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES:
		warning = "存档不可读取或超出大小限制"
		return {}
	var parser = JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		warning = "存档格式损坏，正在尝试备份"
		return {}
	var data: Dictionary = parser.data
	if int(data.get("version", 0)) != 1 or not data.get("run") is Dictionary:
		warning = "存档版本或结构不兼容"
		return {}
	for key in ["materials", "stats", "character_levels"]:
		if not data.get(key) is Dictionary:
			return {}
		for value in data[key].values():
			if not (value is float or value is int) or value < 0:
				return {}
	return data

func load_profile() -> Dictionary:
	for candidate in [path, path + ".bak"]:
		var data = _read(candidate)
		if not data.is_empty():
			return data
	return {}

func save(data: Dictionary) -> bool:
	data["saved_utc"] = int(Time.get_unix_time_from_system())
	var temporary = path + ".tmp"
	var file = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		warning = "无法写入存档：%s" % error_string(FileAccess.get_open_error())
		return false
	file.store_string(JSON.stringify(data))
	file.flush()
	file.close()
	if _read(temporary).is_empty():
		warning = "写入校验失败，已保留原存档"
		return false
	var directory = DirAccess.open(path.get_base_dir())
	if directory == null:
		warning = "存档目录无法打开"
		return false
	if FileAccess.file_exists(path):
		if not _read(path).is_empty():
			if FileAccess.file_exists(path + ".bak"):
				directory.remove(path + ".bak")
			if directory.copy(path, path + ".bak") != OK:
				warning = "无法创建备份，已保留原存档"
				return false
	var result = directory.rename(temporary, path)
	if result != OK:
		warning = "存档替换失败：%s" % error_string(result)
	return result == OK
