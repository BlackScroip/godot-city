extends SceneTree

var game: Node
var canvas: SubViewport
var checks := 0
var failures: Array[String] = []
var captures: Array[Dictionary] = []
var save_path := "/private/tmp/currency-pickup-flow-%d.json" % Time.get_ticks_usec()

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func make_game() -> Node:
	var result = load("res://scenes/main.tscn").instantiate()
	result.save_store = DungeonSaveStore.new(save_path)
	canvas.add_child(result)
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
	check(not game._transitioning, "Actual room transition finishes")
	game.world.set_process(false)
	game.world.set_physics_process(false)
	game.world.fighting = false
	game.world.paused = false
	game.world.player.set_process(false)
	game.world.player.set_physics_process(false)
	game.hud.close_page()
	game.world.snap_camera()
	for frame in 2: await physics_frame

func pending(id: int) -> int:
	var result := 0
	for entry in game.world.ground_loot.entries:
		if bool(entry.material) and int(entry.id) == id: result += int(entry.amount)
	return result

func step(seconds: float) -> void:
	for frame in int(round(seconds * 60.0)):
		game.world._physics_process(1.0 / 60.0)
	game._process(0)

func _run() -> void:
	create_timer(150).timeout.connect(func(): quit(2))
	canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	game = make_game()
	check(game.systems.begin_run(20261026, 1, 100, 0).success, "Currency fixture starts an actual run")
	var room_id := 0
	for node in game.campaign.database.Nodes:
		if str(node.get("Flow", "")) == "Shop":
			room_id = int(node.Id)
			break
	check(room_id > 0, "Original merchant room exists")
	game.campaign.start_practice(room_id, 20261026)
	game._load_room()
	await wait_transition()
	var drops = game.world.ground_loot
	drops.clear()
	var point: Vector3 = game.world.player.position
	var gold: int = game.systems.material(101)
	var magic: int = game.systems.material(102)
	var gold_record: int = game.systems.stat("get:101")
	var magic_record: int = game.systems.stat("get:102")
	for id in [70001, 70002]:
		game._claim_destroyable({"config_id": str(id), "marker_id": "currency-flow-" + str(id), "position": point})
	var expected_gold := pending(101)
	var expected_magic := pending(102)
	check(expected_gold > 0 and expected_magic > 0, "Actual gold and magic mines emit both currency types")
	check(game.systems.material(101) == gold and game.systems.material(102) == magic, "Mines grant neither currency before arrival")
	var entry_count: int = drops.entries.size()
	check(entry_count > 2 and entry_count <= 11, "Mine rewards split into bounded source currency portions")
	check(drops.nearest(point).is_empty(), "Neither currency asks for the manual pickup command")
	game._claim_destroyable({"config_id": "70002", "marker_id": "currency-flow-70002", "position": point})
	check(pending(102) == expected_magic, "Repeated mine callback cannot duplicate pending orbs")
	step(0.3)
	check(game.systems.material(101) == gold and game.systems.material(102) == magic, "Scatter animation keeps balances unchanged")
	check(drops.entries.any(func(entry): return (entry.position as Vector3).distance_to(point) > 0.1), "Source jump moves currency outward from its spawn point")
	check(drops.entries.any(func(entry): return entry.visual.position.y > point.y + 0.5), "Source scatter visibly rises above the floor")
	var paused_state: Array = drops.snapshot().duplicate(true)
	game.world.paused = true
	step(1.0)
	check(drops.snapshot() == paused_state, "Pause freezes scatter and pickup progression")
	game.world.paused = false
	game.world._background = true
	step(1.0)
	check(drops.snapshot() == paused_state, "Background freezes scatter and pickup progression")
	game.world._background = false
	check(game._save(true), "Mid-scatter checkpoint writes successfully")
	game.queue_free()
	await process_frame
	game = make_game()
	await wait_transition()
	drops = game.world.ground_loot
	check(drops.entries.size() == entry_count, "Restoring pending portions does not split them again")
	check(pending(101) == expected_gold and pending(102) == expected_magic, "Checkpoint retains every pending coin and orb")
	check(game.systems.material(101) == gold and game.systems.material(102) == magic, "Restart grants no pending portion early")
	step(4.0)
	check(pending(101) == 0 and pending(102) == 0, "Actual world ticks attract and consume both currencies")
	check(game.systems.material(101) == gold + expected_gold, "Coins arrive in the persistent gold balance exactly once")
	check(game.systems.material(102) == magic + expected_magic, "Orbs arrive in the shop magic balance exactly once")
	check(game.systems.stat("get:101") == gold_record + expected_gold, "Gold collection records the original full amount")
	check(game.systems.stat("get:102") == magic_record + expected_magic, "Orb collection records the original full amount")
	check(int(game.profile.data.run.materials.get("101", 0)) == expected_gold, "Run receipt includes all attracted coins")
	check(int(game.profile.data.run.materials.get("102", 0)) == expected_magic, "Run receipt includes all attracted orbs")
	check(game.hud.counter_values[0].text.begins_with(str(gold + expected_gold)), "Battle HUD refreshes the gold balance")
	check(game.hud.counter_values[1].text.begins_with(str(magic + expected_magic)), "Battle HUD refreshes the shop orb balance")
	step(2.0)
	check(game.systems.material(101) == gold + expected_gold and game.systems.material(102) == magic + expected_magic, "Further world ticks cannot grant collected currencies again")
	check(game._save(true), "Collected balances write successfully")
	game.queue_free()
	await process_frame
	game = make_game()
	await wait_transition()
	check(pending(101) == 0 and pending(102) == 0, "Restart retains consumed ground state")
	check(game.systems.material(101) == gold + expected_gold and game.systems.material(102) == magic + expected_magic, "Restart preserves exactly one full currency grant")
	if DisplayServer.get_name() != "headless": await capture_flight()
	var report := {"checks": checks, "failures": failures, "passed": failures.is_empty(), "captures": captures, "renderer": DisplayServer.get_name()}
	FileAccess.open("res://reports/currency-pickup-flow-tests.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t") + "\n")
	print("CURRENCY_PICKUP_FLOW_TEST ", JSON.stringify(report))
	game.queue_free()
	canvas.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func capture_flight() -> void:
	var drops = game.world.ground_loot
	var side: Vector3 = game.world.camera.global_basis.x
	side.y = 0
	side = side.normalized()
	var forward := side.cross(Vector3.UP).normalized()
	# Keep the fixture on the shop entrance floor; a navigation map may be empty after reload.
	var point: Vector3 = game.world.player.position - side * 2.0 - forward * 3.0
	game.world.player.position = point
	game.world.player.previous_position = point
	game.world.player.reset_physics_interpolation()
	game.world.snap_camera()
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390)]:
		canvas.size = dimensions
		drops.clear()
		var gold: int = game.systems.material(101)
		var magic: int = game.systems.material(102)
		drops.spawn(101, point - forward * 1.5 - side * 0.6, 99, true)
		drops.spawn(102, point - forward * 1.5 + side * 0.6, 13, true)
		check(drops.entries.size() == 11, "Native 99 gold / 13 orbs create eleven portions")
		var initial: Dictionary = {}
		for entry in drops.entries: initial[entry.visual.get_instance_id()] = entry.visual.position
		for phase in [{"name": "scatter", "duration": 0.3}, {"name": "landed", "duration": 0.6}, {"name": "attract", "duration": 0.3}]:
			step(float(phase.duration))
			for frame in 3: await process_frame
			await RenderingServer.frame_post_draw
			var screenshot := canvas.get_texture().get_image()
			check(not screenshot.is_empty() and screenshot.get_size() == dimensions, "Actual animated currency capture has viewport pixels")
			var colors: Dictionary = {}
			for y in range(int(dimensions.y * 0.2), int(dimensions.y * 0.75), 11):
				for x in range(int(dimensions.x * 0.25), int(dimensions.x * 0.75), 11): colors[screenshot.get_pixel(x, y).to_rgba32()] = true
			check(colors.size() > 80, "Animated currency capture has nonblank scene pixels")
			if phase.name == "scatter":
				var moving := 0
				for entry in drops.entries:
					if entry.visual.position.distance_to(initial[entry.visual.get_instance_id()]) > 0.1: moving += 1
				check(moving >= 9, "Currency portions visibly move during the source jump")
			var path := "res://reports/currency-%s-%dx%d.png" % [phase.name, dimensions.x, dimensions.y]
			screenshot.save_png(path)
			captures.append({"phase": phase.name, "viewport": [dimensions.x, dimensions.y], "pending_gold": pending(101), "pending_magic": pending(102), "path": path})
		step(3.0)
		check(game.systems.material(101) == gold + 99 and game.systems.material(102) == magic + 13, "Rendered currency portions finish with conserved balances")
