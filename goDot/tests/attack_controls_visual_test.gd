extends SceneTree

var failures: Array[String] = []
var captures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("This test requires rendering")
		quit(1)
		return
	var canvas := SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var game = load("res://scripts/main.gd").new()
	game.save_store = DungeonSaveStore.new("user://controls-visual-test.json")
	canvas.add_child(game)
	game.set_process(false)
	game.world.set_physics_process(false)
	game.world.set_attack_mode("off")
	game.hud.close_page()
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390)]:
		canvas.size = dimensions
		await process_frame
		game.hud._layout()
		for mode in ["normal", "heavy", "off"]:
			game._action("auto_attack_mode", mode, 0)
			if game.hud.attack_mode != mode or game.world.auto_attack_mode != mode: failures.append("Mode sync " + mode)
			for key in game.hud.skill_buttons + [game.hud.attack_mode_button]:
				if not Rect2(Vector2.ZERO, game.hud.root.size).encloses(key.get_global_rect()): failures.append("Control outside viewport " + str(dimensions))
			await _capture(canvas, "%dx%d-%s" % [dimensions.x, dimensions.y, mode])
		game.world.player.combat.configure(null, null, 7)
		game.world.use_skill(0, true)
		var requested = game.world.intent.take_ready(game.world.player.combat, 0)
		if requested >= 0: game.world.player.combat.request_attack(requested)
		for frame in 240:
			game.world._tick_player_input(1.0 / 60)
			game.world.player.combat.tick(1.0 / 60)
			game.world.player.combat.drain_events()
			game.hud.update_combat(game.world.player.combat, false)
			game.hud.update_intent(game.world.intent)
			if game.world.player.combat.charging and game.world.player.combat.charge_elapsed > 0.6:
				await _capture(canvas, "%dx%d-hold" % [dimensions.x, dimensions.y])
				break
		game.world.use_skill(0, false)
		game.world.clear_input()
	game.queue_free()
	await process_frame
	canvas.queue_free()
	await process_frame
	print("ATTACK_CONTROLS_VISUAL ", JSON.stringify({"failures": failures, "captures": captures}))
	quit(0 if failures.is_empty() else 1)

func _capture(canvas: SubViewport, name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var path = "res://reports/attack-controls-%s.png" % name
	canvas.get_texture().get_image().save_png(path)
	captures.append(path)
