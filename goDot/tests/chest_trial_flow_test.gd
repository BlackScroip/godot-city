extends SceneTree

var game: Node
var assertions := 0
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)
		printerr(message)

func _initialize() -> void:
	_run.call_deferred()

func _wait_loading() -> void:
	game.world.set_physics_process(false)
	game.world.set_process(true)
	var deadline = Time.get_ticks_msec() + 60000
	while game._transitioning and Time.get_ticks_msec() < deadline: await process_frame
	check(not game._transitioning, "Trial assets finish preparation")
	game.set_process(false)
	game.world.set_process(false)
	game.world.set_physics_process(false)
	game.world.presentation.audio_enabled = false
	game.world.auto_attack_enabled = false
	game.world.paused = false
	game.world.player.invulnerability = 10000

func _run() -> void:
	create_timer(100).timeout.connect(func(): quit(2))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_store = DungeonSaveStore.new("/private/tmp/city-trial-flow-%d.json" % Time.get_ticks_usec())
	root.add_child(game)
	game.set_process(false)
	game.systems.begin_run(143, 1, 100, 0)
	for id in [1061101, 1070701]:
		game.campaign.start_practice(id, 143)
		game._load_room()
		await _wait_loading()
		var chests: Array = game.world.interactions._items.values().filter(func(item): return item.data.has("TrialChestIndex"))
		check(chests.size() == 3, "Trial creates exactly three interactive boxes")
		for index in 3:
			var chest: Dictionary = chests.filter(func(item): return int(item.data.TrialChestIndex) == index)[0]
			check(chest.state.enabled and not chest.state.opened and chest.data.TreasureType == ["Normal", "Unusual", "Luxury"][index], "Each chest has its native quality")
		check(game.world.interactions._items.values().any(func(item): return item.marker.Type == "EEUT_StageChangeDoor" and item.state.enabled), "Unopened trial allows leaving")
		await _capture_trial(id, chests)
		var selected: Dictionary = chests.filter(func(item): return int(item.data.TrialChestIndex) == 1)[0]
		check(game.world.interactions.interact(str(selected.id)).success, "Opening center box starts actual trial")
		await _wait_loading()
		check(game.world.room_stage == "trial" and game.campaign.trial_status().active, "Trial locks room while actions run")
		check(game.world.interactions._items.values().all(func(item): return item.marker.Type != "EEUT_StageChangeDoor" or not item.state.enabled), "Trial closes exits")
		check(chests.filter(func(item): return item.state.enabled).size() == 1, "Unselected boxes disappear")
		check(is_instance_valid(game.world.trial_room.turret) and game.world.actors.size() == 1 and game.world.trial_room.turret.collision_layer == 0, "Invisible phantom has no normal enemy or collision identity")
		check(game.world.trial_room.turret.combat.current_action == game.campaign.trial_status().action, "Runtime executes recovered first action")
		if id == 1061101:
			game.world.player.position = game.world.trial_room.center + Vector3.UP * 0.05
			game.world.player.invulnerability = 0
			# Isolate the recovered damage coefficient from shared defense mitigation.
			game.world.player.combat.defense = 0
			var health = game.world.player.combat.health
			game.world._physics_process(0.1)
			check(is_equal_approx(game.world.player.combat.health, health) and not game.world.trial_room._areas.is_empty(), "APK first bombard preserves its warning delay before damage")
			for step in 13: game.world._physics_process(0.1)
			check(is_equal_approx(game.world.player.combat.health, health - 5), "APK trial trap applies its exact fixed five damage at the authored point")
			game.world.player.invulnerability = 10000
		for step in 10: game.world._physics_process(0.1)
		game._build_save_snapshot()
		var checkpoint: Dictionary = game.profile.data.run.battle.transients.chest_trial.duplicate(true)
		var remaining = float(game.campaign.trial_status().remaining)
		game._load_room(true)
		await _wait_loading()
		check(is_equal_approx(float(game.campaign.trial_status().remaining), remaining), "Reload preserves exact wave timer")
		check(is_equal_approx(game.world.trial_room.turret.combat._clock, float(checkpoint.turret.clock)), "Reload restores turret timeline")
		for step in 800:
			if game.campaign.state.phase == "reward": break
			game.world._physics_process(0.1)
		check(game.campaign.state.phase == "reward" and game.world.room_stage == "open", "Surviving all waves claims reward and reopens route exit")
		check(game.campaign.trial_status().reward_claimed and not game.world.ground_loot.entries.is_empty(), "Trial drops the selected chest reward")
		var count = game.world.ground_loot.entries.size()
		game._finish_chest_trial()
		check(game.world.ground_loot.entries.size() == count, "Duplicate completion cannot drop twice")
	game.campaign.start_practice(1061101, 143)
	game.profile.data.run.inventory["22122"] = 1
	game._load_room()
	await _wait_loading()
	game._start_chest_trial(2)
	check(game.campaign.state.phase == "reward" and game.campaign.trial_status().skipped and not is_instance_valid(game.world.trial_room.turret), "Skip relic completes chosen chest without spawning hazards")
	print("CHEST_TRIAL_FLOW ", JSON.stringify({"passed": failures.is_empty(), "assertions": assertions, "failures": failures}))
	game.systems.decorations = null
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _capture_trial(scene_id: int, chests: Array) -> void:
	if DisplayServer.get_name() == "headless": return
	game._process(0)
	var center: Vector3 = game.world.trial_room.center
	game.world.player.position = center + Vector3(0, 0.05, 4)
	game.world.camera.position = center + game.world._camera_offset
	game.world.camera.look_at(center + Vector3.UP * 0.4)
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390)]:
		root.size = dimensions
		for frame in 8: await process_frame
		for chest in chests:
			check(is_instance_valid(chest.visual) and chest.visual.is_visible_in_tree(), "Trial chest has a visible source scene mesh")
			check(root.get_visible_rect().has_point(game.world.camera.unproject_position(chest.visual.global_position)), "Trial chest is framed at %s" % dimensions)
		await RenderingServer.frame_post_draw
		var picture = root.get_texture().get_image()
		check(not picture.is_empty(), "Trial scene renders pixels")
		check(picture.get_size() == dimensions, "Trial capture uses requested desktop or mobile dimensions")
		picture.save_png("res://reports/chest-trial-%d-%dx%d.png" % [scene_id, dimensions.x, dimensions.y])
