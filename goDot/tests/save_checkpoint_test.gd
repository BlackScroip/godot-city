extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var path := "user://checkpoint-test-%d.json" % Time.get_ticks_usec()
	var game = load("res://scripts/main.gd").new()
	game.save_store = DungeonSaveStore.new(path)
	root.add_child(game)
	game.set_process(false)
	game.world.set_physics_process(false)
	var failures: Array[String] = []
	game.profile.data.materials["101"] = 1234
	game._save()
	game._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	if int(game.save_store.load_profile().get("materials", {}).get("101", -1)) != 1234:
		failures.append("Background checkpoint must persist latest queued state")
	game.profile.data.materials["101"] = 5678
	game._save()
	game._action("quit", 0, 0)
	if int(game.save_store.load_profile().get("materials", {}).get("101", -1)) != 5678:
		failures.append("Quit command must persist latest queued state before exit")
	game.free()
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	print("SAVE_CHECKPOINT ", JSON.stringify({"checks": 2, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
