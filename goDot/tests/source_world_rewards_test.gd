extends SceneTree

var checks := 0
var failures: Array[String] = []
var canvas: SubViewport
var game: Node

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _run() -> void:
	canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	game = load("res://scenes/main.tscn").instantiate()
	game.save_store = DungeonSaveStore.new("/private/tmp/source-world-%d.json" % Time.get_ticks_usec())
	canvas.add_child(game)
	game.set_process(false)
	game.world.set_process(false)
	game.world.set_physics_process(false)
	game.world.presentation.audio_enabled = false
	game.audio.stop()
	game.hud.close_page()
	game.systems.begin_run(73912, 1, 100)
	game.campaign.start_practice(1010101, 73912)
	game._room_key = "source-world-integration"
	game.world.load_environment(1010101)
	game.world.create_player(game._new_combat(), 1)
	game.world.auto_attack_enabled = false
	game.world.paused = false
	await physics_frame
	await physics_frame
	await _test_source_breakables()
	await _test_camera()
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "display": DisplayServer.get_name(), "scope": "Actual imported room, source sword/bow collision and zero-HP-damage tenacity, rewards, persistence, player action camera hooks and rendered images. APK source evidence only; no APK runtime capture."}
	FileAccess.open("res://reports/source-world-rewards.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("SOURCE_WORLD_REWARDS ", JSON.stringify(report))
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _prop(config_id: String) -> Dictionary:
	for item in game.world.interactions._items.values():
		if str(item.binding.get("ConfigId", "")) == config_id and item.state.enabled and not item.state.broken and is_instance_valid(item.visual): return item
	return {}

func _action(id: String) -> Dictionary:
	return game.world.player.combat._action("ActGroup_playerchara", id)

func _hit(id: String, emission: String) -> Dictionary:
	var action := _action(id)
	var player: DungeonActor = game.world.player
	player.combat._start(action, 0)
	for event in player.combat.drain_events(): game.world._consume(player, event)
	return {"definition": action.hits[0].duplicate(true), "damage": 0.0, "source_key": "player", "sequence": player.combat._cast_sequence, "emission": emission}

func _test_source_breakables() -> void:
	var world: DungeonWorld = game.world
	var pot := _prop("10003")
	check(not pot.is_empty(), "Imported forest room has a real source pot")
	if pot.is_empty(): return
	check(float(pot.state.hp) == 50.0, "Actual pot starts at APK durability50")
	var point: Vector3 = world.interactions._world_position(pot.position)
	world.player.position = point - Vector3.BACK * 1.3 + Vector3.UP * 0.05
	world.player.face_direction(Vector3.BACK)
	world.snap_camera()
	await _capture("source-props-before")
	var hit := _hit("sword_atk1", "source-pot-sword")
	world._consume(world.player, {"type": "hit"}.merged(hit))
	world._tick_projectiles(1.0 / 60.0)
	check(pot.state.broken and not pot.visual.visible, "Real source sword attack breaks and hides pot despite zero HP damage")
	for body in pot.bodies:
		check(body.node.collision_layer == 0 and body.node.collision_mask == 0, "Broken pot source collision is disabled")
	var gold := 0
	for entry in world.ground_loot.entries:
		if entry.get("material", false) and int(entry.id) == 101:
			gold += int(entry.amount)
			check(entry.visual.texture != null, "Pot ground gold has its material image")
	var broken_pots := 0
	for item in world.interactions._items.values():
		if str(item.binding.get("ConfigId", "")) == "10003" and item.state.broken: broken_pots += 1
	check(gold >= broken_pots and gold <= broken_pots * 3, "Each pot hit by source sword volume emits one to three ground coins")
	var entries_before: int = world.ground_loot.entries.size()
	world._tick_projectiles(1.0 / 60.0)
	game._claim_destroyable(world.interactions._context(pot))
	check(world.ground_loot.entries.size() == entries_before, "Projectile frames and repeated reward dispatch cannot duplicate pot loot")
	var gold_before := int(game.systems.material(101))
	for frame in 180: world.ground_loot.advance_collection(1.0 / 60.0, world.player.position, game.systems)
	check(int(game.systems.material(101)) == gold_before + gold, "Broken pot coins animate into player and credit automatically")
	await _capture("source-props-after")
	world.projectiles.clear()
	var mineral := _prop("10017")
	check(not mineral.is_empty(), "Imported room has an exact source gathering mineral")
	if mineral.is_empty(): return
	var material_before := int(game.systems.material(10101))
	point = world.interactions._world_position(mineral.position)
	world.player.position = point - Vector3.BACK * 2.0 + Vector3.UP * 0.05
	world.player.face_direction(Vector3.BACK)
	world.snap_camera()
	for shot in 1:
		var bow := _hit("bow_atk1", "source-mineral-arrow:%d" % shot)
		world._consume(world.player, {"type": "hit"}.merged(bow))
		for frame in 20: world._tick_projectiles(1.0 / 60.0)
	check(mineral.state.broken, "Real source bow projectile reaches and breaks gathering mineral")
	check(int(game.systems.material(10101)) == material_before + 1, "Gathering credits corresponding source material directly once")
	check(not world.find_children("GatheredMaterial*", "Node3D", false, false).is_empty(), "Direct gathering displays floating material image feedback")
	game._claim_destroyable(world.interactions._context(mineral))
	check(int(game.systems.material(10101)) == material_before + 1, "Duplicate gathering reward does not add another material")
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(world.interactions.snapshot()))
	check(world.interactions.restore(snapshot), "Broken source environment survives JSON restore")
	check(not pot.visual.visible and not mineral.visual.visible, "Restored broken models remain absent")
	var lode := _prop("70001")
	check(not lode.is_empty(), "Actual room includes an APK gold ore lode")
	if not lode.is_empty():
		point = world.interactions._world_position(lode.position)
		world.player.position = point - Vector3.BACK * 2.0 + Vector3.UP * 0.05
		world.player.face_direction(Vector3.BACK)
		world.ground_loot.clear()
		for shot in 3:
			var arrow := _hit("bow_atk1", "source-gold-lode:%d" % shot)
			world._consume(world.player, {"type": "hit"}.merged(arrow))
			for frame in 20: world._tick_projectiles(1.0 / 60.0)
			check(float(lode.state.hp) == maxf(0.0, 150.0 - 60.0 * (shot + 1)), "Gold lode takes one source60-tenacity hit per new arrow")
		check(lode.state.broken and not lode.visual.visible, "Gold ore disappears only after its source150 durability is depleted")
		var lode_gold := 0
		for entry in world.ground_loot.entries:
			if entry.get("material", false) and int(entry.id) == 101: lode_gold += int(entry.amount)
		check(lode_gold >= 40 and lode_gold <= 60, "Broken gold ore emits its source40 to60 coins")
	var no_feedback := {"definition": {"raw": "{}"}, "damage": 999999.0}
	check(world._environment_tenacities(no_feedback).is_empty(), "HP damage never substitutes for absent environment tenacity")
	var multi := _action("bow_dogeatk_v2")
	check(world._environment_tenacities({"definition": multi.hits[3]}) == [30, 60, 90], "Original multi-HitAction attack preserves cumulative environment callback values")

func _test_camera() -> void:
	var world: DungeonWorld = game.world
	var player: DungeonActor = world.player
	player.position = DungeonWorld.vector(world.environment_entry.player_start) + Vector3.UP * 0.05
	world.snap_camera()
	var baseline := world._camera_offset.length()
	var action := _action("axe_liedichongjibo_derivative")
	player.combat._start(action, 2)
	for event in player.combat.drain_events(): world._consume(player, event)
	check(world.camera_closeup.target_offset == -1.0, "Player action start enters source first camera window immediately")
	world._process(1.0 / 60.0)
	check(is_equal_approx(world.camera.position.distance_to(world._camera_focus), baseline - 0.1), "World camera distance follows source per-rendered-frame smoothing")
	world.paused = true
	var frozen: float = world.camera_closeup.distance_offset
	world._process(1.0)
	check(world.camera_closeup.distance_offset == frozen, "Gameplay pause freezes active zoom")
	world.paused = false
	player.combat.action_elapsed = 0.717 / float(player.combat.custom_properties._feel_action_speed)
	world._process(1.0 / 60.0)
	check(world.camera_closeup.target_offset == -3.0, "World hook advances to source second window at717ms")
	for frame in 35: world._process(1.0 / 60.0)
	check(world.camera.position.distance_to(world._camera_focus) < baseline - 2.8, "Actual camera moves close during authored window")
	await _capture("source-camera-close")
	player.combat.action_elapsed = 1.217 / float(player.combat.custom_properties._feel_action_speed)
	world._process(1.0 / 60.0)
	check(world.camera_closeup.target_offset == 0.0, "Original window exit restores camera target")
	world._consume(player, {"type": "action_cancelled", "sequence": player.combat._cast_sequence})
	for frame in 50: world._process(1.0 / 60.0)
	check(world.camera.position.distance_to(world._camera_focus) > baseline - 0.02, "Cancelled action smoothly returns to ordinary camera distance")
	await _capture("source-camera-normal")
	world.begin_outcome_camera("sys_dead")
	world.tick_outcome_camera(0.5, 1.0 / 60.0)
	check(world.camera_closeup.target_offset == -4.0, "Paused outcome path drives original death zoom")
	world.begin_outcome_camera("revival")
	world.tick_outcome_camera(0.5, 1.0 / 60.0)
	check(world.camera_closeup.target_offset == -3.0, "Revival uses its own source camera window")
	world.end_outcome_camera()
	check(world.camera_closeup.target_offset == 0.0, "Outcome completion releases camera ownership")
	var fov := world.camera.fov
	world.load_environment(1010101)
	check(world.camera_closeup.distance_offset == 0.0 and world.camera.fov == fov, "Room transition clears camera state without changing source FOV")

func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390)]:
		canvas.size = dimensions
		game._process(0.0)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var image := canvas.get_texture().get_image()
		var colors: Dictionary = {}
		for x in range(0, image.get_width(), 40):
			for y in range(0, image.get_height(), 40): colors[image.get_pixel(x, y).to_html()] = true
		check(colors.size() > 20, "Rendered %s at%s has nonblank game pixels" % [label, dimensions])
		image.save_png("res://reports/%s-%dx%d.png" % [label, dimensions.x, dimensions.y])
