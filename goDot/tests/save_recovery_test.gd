extends SceneTree

const Profile = preload("res://scripts/domain/profile.gd")
const Store = preload("res://scripts/save_store.gd")
var failures: Array[String] = []
var assertions := 0
var path := ""

func _initialize() -> void:
	path = "user://save-recovery-%d.json" % Time.get_ticks_usec()
	var healthy = Profile.new().data
	healthy.materials["101"] = 321
	var corruptions: Array[Dictionary] = []
	var broken = healthy.duplicate(true)
	broken.erase("claimed_tasks")
	corruptions.append(broken)
	broken = healthy.duplicate(true)
	broken.run.erase("route")
	corruptions.append(broken)
	broken = healthy.duplicate(true)
	broken.run.rewards = "invalid"
	corruptions.append(broken)
	broken = healthy.duplicate(true)
	broken.run.health = -1
	corruptions.append(broken)
	broken = healthy.duplicate(true)
	broken.run.health = "invalid"
	corruptions.append(broken)
	broken = healthy.duplicate(true)
	broken.run.rewards = [{"key": "invalid", "choices": [null]}]
	corruptions.append(broken)
	broken = healthy.duplicate(true)
	broken.claimed_tasks = [{}]
	corruptions.append(broken)
	broken = healthy.duplicate(true)
	broken.run.battle = []
	corruptions.append(broken)
	var store = Store.new(path)
	for index in corruptions.size():
		_write(path, corruptions[index])
		_write(path + ".bak", healthy)
		var loaded = store.load_profile()
		_check(not loaded.is_empty() and loaded.materials["101"] == 321, "Corruption %d restores backup" % index)
		_check("备份" in store.warning, "Corruption %d reports recovery" % index)
	_write(path, {"version": 1})
	_write(path + ".bak", {"version": 1})
	_check(store.load_profile().is_empty(), "Two invalid saves return no profile")
	_check(not store.warning.is_empty(), "Invalid saves explain failure")
	var live = healthy.duplicate(true)
	live.run = Profile.new_run(17, 1, 35.0)
	live.run.active = true
	live.run.max_health = 100.0
	live.run.armor = 8.0
	live.run.rewards = [{"key": "reward-1", "choices": [101, 102]}]
	live.claimed_tasks = [1, 2]
	_write(path, live)
	var restored = store.load_profile()
	_check(restored.run.health == 35.0 and restored.run.armor == 8.0, "Healthy active run preserves vitals")
	_check(restored.claimed_tasks[0] is int and restored.run.rewards[0].choices[0] is int, "JSON IDs normalize before use")
	_check(store.warning.is_empty(), "Successful main load clears stale warning")
	_check(store.save(live), "Valid profile passes write verification")
	var before = FileAccess.get_file_as_string(path)
	_check(not store.save(corruptions[0]), "Invalid write rejected")
	_check(FileAccess.get_file_as_string(path) == before, "Rejected write preserves main save")
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	print("SAVE RECOVERY TEST: %d assertions, %d failures" % [assertions, failures.size()])
	for failure in failures: printerr(failure)
	quit(0 if failures.is_empty() else 1)

func _write(destination: String, value: Dictionary) -> void:
	var file = FileAccess.open(destination, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()

func _check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message)
