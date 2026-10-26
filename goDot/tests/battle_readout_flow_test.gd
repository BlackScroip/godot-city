extends SceneTree

var failures: Array[String] = []
var checks := 0
var captures: Array[String] = []
var game: Node
var canvas: SubViewport

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _run() -> void:
	create_timer(90).timeout.connect(func(): quit(2))
	canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	game = load("res://scenes/main.tscn").instantiate()
	game.save_store = DungeonSaveStore.new("/private/tmp/city-battle-readout-%d.json" % Time.get_ticks_usec())
	canvas.add_child(game)
	game.set_process(false)
	game.world.set_physics_process(false)
	game.world.presentation.audio_enabled = false
	game.world.set_attack_mode("off")
	game.audio.stop()
	check(game.systems.begin_run(20261026, 1, 100, 0).success, "Fixture starts an actual adventure")
	game.campaign.start_practice(1010101, 20261026)
	game._load_room()
	var deadline := Time.get_ticks_msec() + 60000
	while game._transitioning and Time.get_ticks_msec() < deadline: await process_frame
	check(not game._transitioning, "Battle room finishes loading")
	game.set_process(false)
	game.world.process_mode = Node.PROCESS_MODE_DISABLED
	game.world.fighting = false
	game.world.paused = false
	game.hud.close_page()
	game._process(0.0)
	for button in game.hud.skill_buttons: button.set_process(false)
	var readout = game.hud.battle_readout
	check(readout.visible and not readout.stats.visible, "Actual room entry hides only statistics while retaining the combat overlay")
	var hit := {"source_key": str(game.world.player.combat.actor_key), "receiver_key": "enemy:11001:1", "resolved_accepted": true, "resolved_damage": 25.0}
	game._record_run_impact(hit)
	game._update_battle_presentation(0.5)
	check(readout.stats.visible and readout.hits.text == "1" and is_equal_approx(game.battle_tally.combo_remaining, 1.5), "Settled game event reveals statistics and advances countdown after combat")
	game.hud.show_page("Pause", [], "list", {})
	game.world.paused = true
	game._update_battle_presentation(10.0)
	check(not readout.visible and game.battle_tally.combo_remaining == 1.5, "Modal suppresses readout and freezes combo time")
	game.hud.close_page()
	game.world.paused = false
	game.world._background = true
	game._update_battle_presentation(10.0)
	check(game.battle_tally.combo_remaining == 1.5, "Background game does not consume combo time")
	game.world._background = false
	game.world.simulation_scale = 0.5
	game._update_battle_presentation(1.0)
	check(game.battle_tally.combo_remaining == 1.0, "Countdown follows the actual simulation speed")
	game.world.simulation_scale = 1.0
	game._update_battle_presentation(1.0)
	game._update_battle_presentation(0.3)
	check(not readout.stats.visible and game.profile.data.run.counters["run:damage"] == 25, "Last kill times out without changing adventure settlement damage")
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390), Vector2i(2460, 1080)]:
		canvas.size = dimensions
		for frame in 3: await process_frame
		game.hud._layout()
		game.hud.update_combat(game.world.player.combat, false)
		readout._layout()
		check(not game.hud.camp_button.visible and not game.hud.status_label.visible, "Adventure frame suppresses camp-only controls at %s" % dimensions)
		game.battle_tally.reset()
		game._update_battle_presentation(0.0)
		var idle: Image = await _capture("%dx%d-idle" % [dimensions.x, dimensions.y])
		for count in 35: game._record_run_impact(hit)
		game._update_battle_presentation(0.1)
		var active: Image = await _capture("%dx%d-active" % [dimensions.x, dimensions.y])
		check(readout.stats.visible and readout.stage == 3 and readout.hits.text == "35", "Actual event stream reaches Excellent at %s" % dimensions)
		if active != null:
			check(_changed_pixels(idle, active, readout.stats.get_global_rect()) > 100, "Readout has visible rendered pixels at %s" % dimensions)
		game._update_battle_presentation(1.9)
		game._update_battle_presentation(0.15)
		await _capture("%dx%d-fading" % [dimensions.x, dimensions.y])
		game._update_battle_presentation(0.15)
		var hidden: Image = await _capture("%dx%d-hidden" % [dimensions.x, dimensions.y])
		check(not readout.stats.visible, "Actual readout completely hides at %s" % dimensions)
		if hidden != null:
			check(_changed_pixels(idle, hidden, readout.stats.get_global_rect()) == 0, "Hidden statistics leave no stale rendered pixels at %s" % dimensions)
	game._record_run_impact(hit)
	game._update_battle_presentation(0.1)
	game.profile.data.run.active = false
	game._update_battle_presentation(0.0)
	check(not readout.visible, "Returning to camp suppresses the complete combat overlay")
	var report := {"checks": checks, "passed": failures.is_empty(), "failures": failures,
		"rendered": DisplayServer.get_name() != "headless", "captures": captures}
	FileAccess.open("res://reports/battle-readout-flow.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("BATTLE_READOUT_FLOW ", JSON.stringify(report))
	game.systems.decorations = null
	game.queue_free()
	await process_frame
	canvas.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _capture(label: String) -> Image:
	if DisplayServer.get_name() == "headless": return null
	await process_frame
	await RenderingServer.frame_post_draw
	var image := canvas.get_texture().get_image()
	var path := "res://reports/battle-readout-%s.png" % label
	image.save_png(path)
	captures.append(path)
	return image

func _changed_pixels(before: Image, after: Image, bounds: Rect2) -> int:
	var area := Rect2i(bounds).intersection(Rect2i(Vector2i.ZERO, after.get_size()))
	var changed := 0
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			if before.get_pixel(x, y) != after.get_pixel(x, y): changed += 1
	return changed
