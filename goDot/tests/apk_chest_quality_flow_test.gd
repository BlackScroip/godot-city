extends SceneTree

var checks := 0
var failures: Array[String] = []
var game: Node

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func chests() -> Array:
	return game.world.interactions._items.values().filter(func(item): return str(item.marker.get("Type", "")) == "EEUT_AbilityItemTreasureBox" and int(item.data.get("TreasureId", 0)) == 1)

func load_room(id: int, resume := false) -> void:
	if not resume: check(game.campaign.start_practice(id, 42).success, "Practice fixture starts " + str(id))
	game._load_room(resume)
	game.world.set_physics_process(false)
	game.world.set_process(true)
	var deadline := Time.get_ticks_msec() + 60000
	while game._transitioning and Time.get_ticks_msec() < deadline: await process_frame
	check(not game._transitioning, "Room fixture finishes loading")
	game.world.set_process(false)
	game.world.set_physics_process(false)
	game.world.auto_attack_enabled = false
	game.world.presentation.audio_enabled = false
	game.set_process(false)

func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.save_store = DungeonSaveStore.new("/private/tmp/city-apk-chest-%d.json" % Time.get_ticks_usec())
	root.add_child(game)
	game.set_process(false)
	game.systems.begin_run(42, 1, 100, 0)
	for enemy_class in ["Elite", "Boss", "FinalBoss"]:
		var fixtures: Array = game.campaign.database.Nodes.filter(func(node): return node.FightType == "Regular" and (bool(node.FinalBoss) if enemy_class == "FinalBoss" else str(node.EnemyClass) == enemy_class and not bool(node.FinalBoss)))
		check(not fixtures.is_empty(), "Source completion fixture exists " + enemy_class)
		if fixtures.is_empty(): continue
		await load_room(int(fixtures[0].Id))
		var boxes := chests()
		check(not boxes.is_empty(), "Source room has a completion chest marker")
		for box in boxes:
			check(box.data.TreasureType == {"Elite": "Unusual", "Boss": "Curse", "FinalBoss": "Curse_Final"}[enemy_class], "Loaded completion box has source rank quality " + enemy_class)
	var dodge: Array = game.campaign.database.Nodes.filter(func(node): return node.FightType == "DodgeBattle")
	await load_room(int(dodge[0].Id))
	game.world.received_hits = 9
	game.campaign.state.waves_cleared = game.campaign.state.wave_count
	game.world.room_stage = "rewards"
	game._finish_room()
	check(game.campaign.state.phase == "reward", "Failed challenge still completes room objective")
	game.world.room_stage = "open"
	game.world.sync_room_gates()
	for box in chests(): check(not box.state.enabled, "Failed challenge does not regain a box when exit opens")
	game._build_save_snapshot()
	await load_room(int(dodge[0].Id), true)
	for box in chests(): check(not box.state.enabled, "Failed challenge box remains absent after checkpoint reload")
	await load_room(int(dodge[0].Id))
	game.world.received_hits = 0
	game.campaign.state.waves_cleared = game.campaign.state.wave_count
	game.world.room_stage = "rewards"
	game._finish_room()
	for box in chests(): check(box.state.enabled and box.data.TreasureType == "Unusual", "Best challenge gives unusual without luxury unlock")
	var treasures: Array = game.campaign.database.Nodes.filter(func(node): return node.Flow == "Treasure")
	check(treasures.size() == 16 and treasures.all(func(node): return node.get("TreasureBoxType", "") == "Normal"), "Imported treasure-only qualities match all sixteen packaged nodes")
	await load_room(int(treasures[0].Id))
	game.campaign.resolve_action()
	game._finish_room()
	check(game.world.ground_loot.entries.is_empty(), "Completing treasure room does not award a duplicate loose chest batch")
	var boxes := chests()
	check(not boxes.is_empty(), "Treasure room retains its physical reward chest")
	if not boxes.is_empty():
		check(game.world.interactions.interact(str(boxes[0].id)).success, "Treasure room box opens")
		check(not game.world.ground_loot.entries.is_empty(), "Opening treasure box produces actual ground rewards")
		var count: int = game.world.ground_loot.entries.size()
		check(not game.world.interactions.interact(str(boxes[0].id)).success and game.world.ground_loot.entries.size() == count, "Treasure reward cannot be claimed twice")
	await load_room(1010701)
	var ambient: Array = game.world.interactions._items.values().filter(func(item): return str(item.marker.get("Type", "")) == "EEUT_AbilityItemTreasureBox" and int(item.data.get("TreasureId", 0)) == 2)
	check(not ambient.is_empty(), "Source fixture includes an authored environment chest")
	game.world.interactions.set_completion_chest_quality("Curse")
	for box in ambient: check(box.data.TreasureType == "Unusual", "Completion quality leaves authored environment chest quality intact")
	game.queue_free()
	await process_frame
	print("APK_CHEST_QUALITY_FLOW_TEST ", JSON.stringify({"checks": checks, "passed": failures.is_empty(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)
