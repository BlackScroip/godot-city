class_name DungeonSaveStore
extends RefCounted

const SAVE_PATH = "user://dungeon-profile-v1.json"
const MAX_BYTES = 16 * 1024 * 1024
var warning := ""
var path: String
var _writer: Thread
var _pending: Dictionary = {}
var requested_version := 0
var committed_version := 0
var last_write_ms := 0.0
var last_request_ms := 0.0
var last_failed := false

func request_save(data: Dictionary) -> void:
	var before := Time.get_ticks_usec()
	requested_version += 1
	# Only this isolated copy crosses the thread boundary.
	_pending = {"version": requested_version, "data": data.duplicate(true)}
	poll()
	last_request_ms = (Time.get_ticks_usec() - before) / 1000.0

func poll() -> void:
	if _writer != null and not _writer.is_alive(): _collect()
	if _writer == null and not _pending.is_empty():
		var job := _pending
		_pending = {}
		_writer = Thread.new()
		var result := _writer.start(_write_job.bind(path, job))
		if result != OK:
			_writer = null
			last_failed = true
			warning = "无法启动存档任务：%s" % error_string(result)

static func _write_job(destination: String, job: Dictionary) -> Dictionary:
	var worker := DungeonSaveStore.new(destination)
	var before := Time.get_ticks_usec()
	var success := worker._save_sync(job.data)
	return {"version": job.version, "success": success, "warning": worker.warning, "ms": (Time.get_ticks_usec() - before) / 1000.0}

func _collect() -> void:
	var result: Dictionary = _writer.wait_to_finish()
	_writer = null
	last_write_ms = result.ms
	last_failed = not result.success
	warning = result.warning
	if result.success: committed_version = int(result.version)

func flush() -> bool:
	while _writer != null or not _pending.is_empty():
		if _writer != null: _collect()
		poll()
	return not last_failed

func is_saving() -> bool:
	return _writer != null or not _pending.is_empty()

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
	var profile = preload("res://scripts/domain/profile.gd").new()
	if not profile.restore(data):
		warning = "存档版本或结构不兼容"
		return {}
	return profile.data

func load_profile() -> Dictionary:
	warning = ""
	for candidate in [path, path + ".bak"]:
		var data = _read(candidate)
		if not data.is_empty():
			if candidate != path: warning = "主存档不可用，已恢复备份进度"
			return data
	return {}

func save(data: Dictionary) -> bool:
	flush()
	requested_version += 1
	last_failed = not _save_sync(data)
	if not last_failed: committed_version = requested_version
	return not last_failed

func _save_sync(data: Dictionary) -> bool:
	warning = ""
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
