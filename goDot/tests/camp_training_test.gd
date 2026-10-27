extends SceneTree

var failures: Array[String] = []
var checks := 0
var canvas: SubViewport
var render_check := false

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _run() -> void:
	render_check = "--render-check" in OS.get_cmdline_user_args()
	canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var game = load("res://scenes/main.tscn").instantiate()
	game.save_store = DungeonSaveStore.new("/tmp/camp-training-%d.json" % Time.get_ticks_usec())
	canvas.add_child(game)
	while not game.initialized: await process_frame
	game.set_process(false)
	var world: DungeonWorld = game.world
	world.set_process(false)
	world.set_physics_process(false)
	world._background = false
	world.paused = false
	game._close_page()
	game.profile.data.buildings["3"] = 1
	world.refresh_camp_progression()
	check(not world.camp_training_status().available and world.camp_training.dummies.is_empty(), "Training remains locked without smith stage two")
	check(not world.start_camp_training().success, "Locked training cannot start")
	game.profile.data.buildings["3"] = 2
	world.refresh_camp_progression()
	await process_frame
	await physics_frame
	check(world.camp_training_status().available and world.camp_training.dummies.size() == 3, "Smith stage two restores all three source training dummies")
	check(not world.camp_facility("training").is_empty(), "The source training position is reachable as its own facility")
	for index in world.camp_training.dummies.size():
		var dummy: DungeonActor = world.camp_training.dummies[index]
		var anchor: Node3D = world._camp_focus_node("EnvPosChecker_Smith_ScareCrow_" + str(index + 1))
		check(dummy.global_position.is_equal_approx(anchor.global_position), "Dummy uses its exact recovered source anchor: " + str(index))
		check(dummy.visual_loaded and dummy.animation != null and dummy.animation_aliases.has("damage"), "Source scarecrow model and hit animation are present: " + str(index))
		check(dummy.combat.max_health == 100000 and dummy.combat.defense == 0, "Source generator HP is retained with explicit zero-defense training baseline")
	check(world.use_skill(0).success, "Manual attacks are available outside a training session")
	world.clear_input()
	check(game.hud.skill_cluster.visible and not game.hud.skill_by_slot[0].disabled, "Camp combat controls are usable outside a training session")
	world.player.dead = true
	check(not world.start_camp_training().success, "A defeated player cannot start practice")
	world.player.dead = false
	world.player.position = Vector3(100, 0, 100)
	check(world.start_camp_training().get("reason", "") == "out_of_range", "Training refuses to start outside its area")
	var dummy: DungeonActor = world.camp_training.dummies[0]
	world.player.position = dummy.position + Vector3.FORWARD * 1.65
	world.player.position.y = 0.05
	world.player.previous_position = world.player.position
	world.player.face_direction(dummy.position - world.player.position)
	world.player.reset_physics_interpolation()
	world.snap_camera()
	await physics_frame
	var original: RefCounted = world.player.combat
	var original_rng: int = original._random_state
	var original_resources: Dictionary = original.skill_resource_snapshot().duplicate(true)
	var wallet_before: Dictionary = game.profile.data.materials.duplicate(true)
	var stats_before: Dictionary = game.profile.data.stats.duplicate(true)
	var run_before: Dictionary = game.profile.data.run.duplicate(true)
	var reported_impacts: Array = []
	var deaths: Array = []
	var player_deaths: Array = []
	world.impact_confirmed.connect(func(hit): reported_impacts.append(hit))
	world.enemy_defeated.connect(func(id): deaths.append(id))
	world.player_defeated.connect(func(): player_deaths.append(true))
	check(world.start_camp_training().success, "Training starts at the source practice area")
	game._process(0.0)
	check(game.hud.skill_cluster.visible and not game.hud.skill_by_slot[0].disabled, "Active training restores usable combat controls inside camp")
	var training: RefCounted = world.player.combat
	var impact_callback: Callable = world._on_impact.bind(world.player)
	check(world.player.combat != original and world.player.combat._random_state == 90010, "Training owns a separate combat instance and RNG")
	check(world._actor_by_key("player") == world.player and training.actor_key == "player" and not original.impact_confirmed.is_connected(impact_callback), "Training preserves actor lookup and disconnects the inactive combat's world callback")
	check(not game.profile.data.run.active and not world.fighting, "Practice leaves adventure and encounter flags unchanged")
	world.set_attack_mode("normal")
	for frame in 150:
		world._physics_process(1.0 / 60.0)
		if frame % 10 == 0: await physics_frame
	var state := world.camp_training_status()
	check(state.hits > 0 and state.total_damage > 0 and state.dps > 0, "Real attack timelines contact the source dummy and accumulate damage/DPS")
	check(world.camp_training.dummies.all(func(target): return not target.dead and target.combat.health > 0), "Training targets stay alive after accepted hits")
	check(reported_impacts.is_empty() and deaths.is_empty(), "Training contacts do not emit adventure damage or monster-death events")
	check(game.profile.data.materials == wallet_before and game.profile.data.stats == stats_before and game.profile.data.run == run_before, "Practice never changes wallet, permanent records or adventure state")
	check(original._random_state == original_rng and original.skill_resource_snapshot() == original_resources, "The original player RNG and skill resources remain untouched during practice")
	var elapsed: float = state.elapsed
	world.paused = true
	world._physics_process(1.0)
	check(is_equal_approx(world.camp_training_status().elapsed, elapsed), "Menu pause also pauses practice timing")
	world.paused = false
	if render_check:
		for dimensions in [Vector2i(1600, 900), Vector2i(844, 390), Vector2i(2460, 1080)]:
			canvas.size = dimensions
			game.hud._layout()
			game.hud.update_combat(world.player.combat, false)
			game.hud.title_label.hide()
			game.camp_training_readout.update_state(world.camp_training_status(), false)
			world.snap_camera()
			for frame in 4: await process_frame
			await RenderingServer.frame_post_draw
			var frame := canvas.get_texture().get_image()
			check(not frame.is_empty(), "Training render exists at " + str(dimensions))
			check(frame.save_png("res://reports/camp-training-%dx%d.png" % [dimensions.x, dimensions.y]) == OK, "Training render saves at " + str(dimensions))
		world._background = false
	check(world.reset_camp_training().success and world.camp_training_status().hits == 0 and world.camp_training_status().total_damage == 0, "Practice statistics reset without ending the session")
	check(world.end_camp_training().success and not world.camp_training_status().active, "Explicit finish ends practice")
	game._process(0.0)
	check(game.hud.skill_cluster.visible and not game.hud.skill_by_slot[0].disabled, "Finishing training keeps camp combat controls usable")
	check(world.player.combat == original and original._random_state == original_rng and original.skill_resource_snapshot() == original_resources, "Finishing restores the exact original player combat and resources")
	check(world._actor_by_key("player") == world.player and original.impact_confirmed.is_connected(impact_callback) and not training.impact_confirmed.is_connected(impact_callback), "Only the restored combat retains the world impact callback after finishing")
	check(world.projectiles.is_empty() and world.pending_attack_entities.is_empty() and world.active_attack_entities.is_empty() and world.summon_units.is_empty(), "Finishing clears all practice attack transients")
	check(world._numbers.is_empty() and world._camera_impulses.is_empty() and world._seen_impacts.is_empty() and world._source_stop_hits.is_empty(), "Finishing clears damage numbers, camera feedback and hit de-duplication state")
	check(world.start_camp_training().success, "A fresh practice session can start after finishing")
	for frame in 100: world._physics_process(1.0 / 60.0)
	check(world.camp_training_status().hits > 0, "An immediate new session accepts repeated attack sequences without stale de-duplication")
	var received_before: int = world.received_hits
	world._apply_hit(dummy, world.player, {"damage": 1000000000.0, "attack_collision": false, "emission": "training:player-exhausted", "definition": {}})
	check(not world.camp_training.active and world.camp_training.last_reason == "player_exhausted" and world.player.combat == original, "Lethal training damage exits practice and restores the original combat")
	check(not world.player.dead and not world.player.suspended and world.player.collision_layer == 2 and world.player.collision_mask == 5 and world.player.visible and world.player.visual.visible, "Exhaustion leaves the restored player alive, visible and collidable")
	check(world.player.action_time == 0 and world.player.action_motion.is_empty() and world.player.dodge_elapsed < 0 and world.player.velocity == Vector3.ZERO, "Exhaustion clears action, dodge and movement state")
	check(player_deaths.is_empty() and reported_impacts.is_empty() and deaths.is_empty() and world.received_hits == received_before, "Training exhaustion never triggers defeat, adventure damage or permanent hit counters")
	check(game.profile.data.materials == wallet_before and game.profile.data.stats == stats_before and game.profile.data.run == run_before, "Lethal training damage also preserves all persistent state")
	check(world.start_camp_training().success, "Training can restart immediately after exhaustion")
	world.player.position = Vector3(100, 0, 100)
	world._physics_process(1.0 / 60.0)
	check(not world.camp_training_status().active and world.camp_training_status().last_reason == "left_range" and world.player.combat == original, "Leaving the training area restores the original combat automatically")
	world.load_environment(10000, true)
	check(world.camp_training.dummies.is_empty() and not world.camp_training.active, "Changing scene removes all practice targets and session state")
	game.queue_free()
	await process_frame
	canvas.queue_free()
	await process_frame
	var output := FileAccess.open("res://reports/camp-training-tests.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks": checks, "failures": failures, "rendered": render_check}, "\t"))
	print("Camp training: %d checks; failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)
