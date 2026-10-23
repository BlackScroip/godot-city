extends SceneTree

var game: Node
var canvas: SubViewport
var failures: Array[String] = []
var captures: Array = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	game = load("res://scenes/main.tscn").instantiate()
	game.save_store = DungeonSaveStore.new("/private/tmp/environment-effects-visual-%d.json" % Time.get_ticks_usec())
	canvas.add_child(game)
	await process_frame
	game.hud.close_page()
	game.world.set_physics_process(false)
	game.set_process(false)
	game.audio.stop()
	game.world.player.position = Vector3(27, 0.1, 80)
	for i in 35: await process_frame
	await capture("waterfall-desktop")
	game.world.player.position = Vector3(31, 0.2, 29.8)
	game.world.ground_loot.spawn_altar(Vector3(32.4, 0.2, 30.5), "visual-test")
	for i in 60: await process_frame
	await capture("altar-desktop")
	var controller = game.world.environment_root.get_node("EnvironmentEffects")
	var entry: Dictionary = game.world.ground_loot.entries.back()
	if not entry.has("effect_binding") or not is_instance_valid(entry.effect_binding.effect):
		failures.append("Runtime altar has no live particle effect")
	else:
		var effect = entry.effect_binding.effect
		await RenderingServer.frame_post_draw
		var shown = canvas.get_texture().get_image()
		controller.set_process(false)
		effect.hide()
		await process_frame
		await RenderingServer.frame_post_draw
		var hidden = canvas.get_texture().get_image()
		var changed := 0
		for y in range(0, shown.get_height(), 2):
			for x in range(0, shown.get_width(), 2):
				var a = shown.get_pixel(x, y)
				var b = hidden.get_pixel(x, y)
				if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.08: changed += 1
		print("ALTAR_EFFECT_CHANGED_PIXELS ", changed)
		if changed < 20: failures.append("Altar particles have no visible pixel contribution")
		effect.show()
		controller.set_process(true)
	canvas.size = Vector2i(844, 390)
	for i in 20: await process_frame
	await capture("altar-phone")
	game.world.ground_loot.remove_altar("visual-test")
	await process_frame
	if is_instance_valid(entry.get("effect_anchor")): failures.append("Consumed altar retains effect anchor")
	var report := {"passed": failures.is_empty(), "failures": failures, "captures": captures}
	FileAccess.open("res://reports/environment-effects-visual-tests.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("ENVIRONMENT_EFFECTS_VISUAL ", JSON.stringify(report))
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := canvas.get_texture().get_image()
	var path := "res://reports/environment-effects-" + label + ".png"
	image.save_png(path)
	captures.append(path)
