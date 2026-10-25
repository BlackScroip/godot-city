extends SceneTree

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _run() -> void:
	var tally = preload("res://scripts/domain/battle_tally.gd").new()
	var hit = {"source_key": "player", "receiver_key": "enemy:13001:1", "resolved_accepted": true, "resolved_damage": 25.0}
	tally.record(hit, "player")
	tally.advance(2, true)
	check(tally.hits == 1 and tally.damage == 25 and tally.dps() == 12.5, "Settled player damage drives hits, total and battle-time DPS")
	tally.advance(10, false)
	check(tally.elapsed == 2, "Paused and finished fights do not dilute DPS")
	for invalid in [hit.merged({"source_key": "enemy:1"}, true), hit.merged({"receiver_key": "player"}, true), hit.merged({"resolved_damage": 0}, true), hit.merged({"resolved_accepted": false}, true)]:
		tally.record(invalid, "player")
	check(tally.hits == 1 and tally.damage == 25, "Incoming, rejected and zero-health-damage events are excluded")
	tally.reset()
	check(tally.hits == 0 and tally.damage == 0 and tally.dps() == 0, "New room resets the counters without division by zero")
	tally.restore({"hits": 7, "damage": 125, "elapsed": 5})
	check(tally.snapshot() == {"hits": 7, "damage": 125.0, "elapsed": 5.0} and tally.dps() == 25, "Room checkpoint restores settled battle statistics")
	tally.reset()
	var world := DungeonWorld.new()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.presentation.set_process(false)
	world.presentation.audio_enabled = false
	var graphical := DisplayServer.get_name() != "headless"
	var campaign := DungeonCampaign.new()
	campaign.configure()
	campaign.start_practice(1019101, 42)
	var room := campaign.current_room()
	if graphical: world.load_environment(int(room.environment_id))
	var combat := DungeonCombat.new()
	combat.configure()
	world.create_player(combat, 1, room.get("player_start", {}))
	world.spawn_wave(campaign.wave_spawns(1), 0, 42)
	var boss: DungeonActor = world.actors.back()
	for actor in world.actors: actor.suspended = true
	var hud := DungeonHud.new()
	root.add_child(hud)
	world.hud = hud
	hud.set_adventure_mode(true)
	var intro = preload("res://scripts/presentation/boss_intro.gd").new()
	root.add_child(intro)
	intro.set_process(false)
	var camera_before := world.camera.transform
	var action_before: String = boss.combat.current_action
	var clock_before: float = boss.combat.action_elapsed
	var hp_before: float = combat.health
	intro.begin(world, boss, "赤炎狼王·布伽鲁")
	for frame in 130: intro._process(1.0 / 60.0)
	check(intro.active and world.paused and intro.visible, "Boss entry pauses combat and displays presentation")
	check(boss.combat.current_action == action_before and boss.combat.action_elapsed == clock_before and combat.health == hp_before, "Visual entry cannot advance attacks or inflict damage")
	var elapsed_before: float = intro.elapsed
	world._background = true
	intro._process(1.0)
	check(intro.elapsed == elapsed_before, "Backgrounding freezes the entry clock")
	world._background = false
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390)]:
		root.size = dimensions
		await process_frame
		await process_frame
		intro._layout()
		check(Rect2(Vector2.ZERO, Vector2(root.get_visible_rect().size)).encloses(intro.skip.get_global_rect()), "Skip stays in viewport %s" % dimensions)
		if graphical:
			await RenderingServer.frame_post_draw
			var frame: Image = root.get_texture().get_image()
			frame.save_png("res://reports/boss-entry-%dx%d.png" % [dimensions.x, dimensions.y])
			intro._process(0.15)
			await process_frame
			await RenderingServer.frame_post_draw
			check(frame.get_data() != root.get_texture().get_image().get_data(), "Rendered boss pose changes at %s" % dimensions)
	intro.skip.pressed.emit()
	check(not intro.active and not intro.visible and world.camera.transform.is_equal_approx(camera_before), "Skip restores camera and closes overlay")
	intro.begin(world, boss, "赤炎狼王·布伽鲁")
	intro._process(intro.duration + 0.1)
	check(not intro.active and world.camera.transform.is_equal_approx(camera_before), "Natural completion restores the camera")
	tally.record(hit, "player")
	hud.battle_readout.show()
	hud.battle_readout.update_values(tally, boss, "赤炎狼王·布伽鲁")
	check(hud.battle_readout.hits.text == "1" and hud.battle_readout.bar.value == boss.combat.health, "Readout shows live settled hits and boss health")
	if graphical:
		world.camera.position = boss.position + Vector3(0, 14, -12)
		world.camera.look_at(boss.position)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://reports/battle-readout.png")
	for id in [13001, 23001, 33001, 43001, 52001, 52003, 53001]:
		world.spawn_wave([{"enemy_id": id, "position": boss.position + Vector3(20, 0, 0)}], 0, 42)
		var target: DungeonActor = world.actors.back()
		target.suspended = true
		var before_action: String = target.combat.current_action
		var before_time: float = target.combat.action_elapsed
		var before_sounds: int = world.presentation.sound_queue.size()
		intro.begin(world, target, str(id))
		for frame in 130: intro._process(1.0 / 60.0)
		check(target.combat.current_action == before_action and target.combat.action_elapsed == before_time, "Boss %d keeps gameplay timeline unchanged" % id)
		check(world.presentation.sound_queue.size() == before_sounds, "Boss %d does not leave delayed entry audio in battle queue" % id)
		intro.finish()
		check(intro._sounds.is_empty() and intro._voices.is_empty(), "Boss %d skip releases entry audio" % id)
		check(not world.presentation.active.any(func(effect): return effect.get("boss_intro_owner", 0) == intro.get_instance_id()), "Boss %d skip clears only owned entry effects" % id)
		target.queue_free()
		world.actors.erase(target)
		await process_frame
	intro.queue_free()
	hud.queue_free()
	world.queue_free()
	await process_frame
	var report := {"checks": checks, "failures": failures, "passed": failures.is_empty(), "rendered": graphical}
	FileAccess.open("res://reports/battle-presentation.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("BATTLE_PRESENTATION ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
