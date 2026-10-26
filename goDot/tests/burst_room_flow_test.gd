extends SceneTree

var game: Node
var checks := 0
var failures: Array[String] = []
var save_path := "/private/tmp/burst-room-flow-%d.json" % Time.get_ticks_usec()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func make_game() -> Node:
	var result = load("res://scenes/main.tscn").instantiate()
	result.save_store = DungeonSaveStore.new(save_path)
	root.add_child(result)
	result.set_process(false)
	result.world.set_process(false)
	result.world.set_physics_process(false)
	result.world.presentation.audio_enabled = false
	result.world.auto_attack_enabled = false
	result.audio.stop()
	return result

func wait_transition() -> void:
	game.world.set_process(true)
	var deadline := Time.get_ticks_msec() + 60000
	while game._transitioning and Time.get_ticks_msec() < deadline: await process_frame
	check(not game._transitioning, "Room transition finishes")
	game.world.set_process(false)
	game.world.set_physics_process(false)
	game.hud.close_page()

func _run() -> void:
	create_timer(120).timeout.connect(func(): quit(2))
	game = make_game()
	check(game.systems.begin_run(20261026, 1, 100, 0).success, "Adventure starts")
	var room_id := 0
	for node in game.campaign.database.Nodes:
		if str(node.get("Flow", "")) == "Shop":
			room_id = int(node.Id)
			break
	game.campaign.start_practice(room_id, 20261026)
	game._load_room()
	await wait_transition()
	check(game.world.player.combat.energy[3] == 0, "First room starts with empty ultimate")
	game.world.player.combat.energy[3] = 37
	game.world.player.combat.cooldowns[3] = 2.5
	game._load_room()
	await wait_transition()
	check(game.world.player.combat.energy[3] == 37, "Room creation preserves partial SP")
	check(game.world.player.combat.cooldowns[3] == 2.5, "Room creation preserves remaining cooldown")
	game.campaign.state.phase = "route"
	check(game._save(true), "Route checkpoint writes successfully")
	check(game.profile.data.run.counters["player:skill_resources"].energy[3] == 37, "Route early return still captures resources")
	game.queue_free()
	await process_frame
	game = make_game()
	check(game.profile.data.run.active and game.campaign.state.phase == "route", "Saved route restores through main initialization")
	check(game.world._camp_camera and game.world.player.combat.energy[3] == 37, "Route restoration keeps carried SP in temporary camp")
	check(game.world.player.combat.cooldowns[3] == 2.5, "Route restoration keeps carried cooldown")
	game.campaign.start_practice(room_id, 20261027)
	game._load_room()
	await wait_transition()
	check(game.world.player.combat.energy[3] == 37 and game.world.player.combat.cooldowns[3] == 2.5, "Leaving restored route transfers resources into next room")
	game.world.player.combat.energy[3] = 64
	check(game._save(true), "In-room checkpoint writes successfully")
	game.queue_free()
	await process_frame
	game = make_game()
	await wait_transition()
	check(not game.world._camp_camera and game.world.player.combat.energy[3] == 64, "In-room restart restores battle SP")
	game.queue_free()
	await process_frame
	var report := {"checks": checks, "failures": failures, "passed": failures.is_empty()}
	FileAccess.open("res://reports/burst-room-flow-test.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("BURST_ROOM_FLOW_TEST ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
