extends SceneTree

var failures: Array[String] = []
var captures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("This test requires rendering")
		quit(1)
		return
	var canvas := SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var display := TextureRect.new()
	display.texture = canvas.get_texture()
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(display)
	var game = load("res://scripts/main.gd").new()
	game.save_store = DungeonSaveStore.new("/private/tmp/city-skill-controls-render-%d.json" % Time.get_ticks_usec())
	canvas.add_child(game)
	game.world.process_mode = Node.PROCESS_MODE_DISABLED
	game.world.set_attack_mode("off")
	game.hud.close_page()
	game.hud.skill.disconnect(game._skill)
	for frame in 8: await process_frame
	for key in game.hud.skill_buttons + [game.hud.attack_mode_button]:
		key.set_process(false)
		key.ready_orbit.set_process(false)
	var combat = game.world.player.combat
	for slot in range(5): combat.energy[slot] = combat.skill_capacity(slot)
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390), Vector2i(2460, 1080)]:
		canvas.size = dimensions
		await process_frame
		await process_frame
		game.hud._layout()
		combat.cooldowns[2] = 0.001
		combat.energy[2] = combat.skill_cost(2) - 4.8
		game.hud.update_combat(combat, false)
		var label = "%dx%d" % [dimensions.x, dimensions.y]
		var normal: Image = await capture(canvas, label + "-idle")
		var key: DungeonTouchButton = game.hud.skill_buttons[0]
		var dodge: DungeonTouchButton = game.hud.skill_buttons[1]
		var ultimate: DungeonTouchButton = game.hud.skill_buttons[3]
		var event := InputEventScreenTouch.new()
		event.index = 5
		event.pressed = true
		event.position = key.get_global_transform_with_canvas() * (key.size * 0.5)
		key._input(event)
		key._advance_feedback(0.1)
		event.index = 6
		event.position = dodge.get_global_transform_with_canvas() * (dodge.size * 0.5)
		dodge._input(event)
		dodge._advance_feedback(0.1)
		event.index = 7
		event.position = ultimate.get_global_transform_with_canvas() * (ultimate.size * 0.5)
		ultimate._input(event)
		ultimate._advance_feedback(0.1)
		var pressed: Image = await capture(canvas, label + "-pressed")
		var area = Rect2i(key.get_global_rect())
		var changed := 0
		var art_pixels := 0
		var outer_changes := 0
		var inverse = key.get_global_transform_with_canvas().affine_inverse()
		var art_bounds = Rect2(key.size * 0.1, key.size * 0.8)
		for y in range(area.position.y, area.end.y):
			for x in range(area.position.x, area.end.x):
				var before = normal.get_pixel(x, y)
				var after = pressed.get_pixel(x, y)
				if Vector3(before.r - after.r, before.g - after.g, before.b - after.b).length() > 0.18: changed += 1
				if not art_bounds.has_point(inverse * Vector2(x + 0.5, y + 0.5)) and Vector3(before.r - after.r, before.g - after.g, before.b - after.b).length() > 0.03: outer_changes += 1
				if after.r > 0.7 and after.g > 0.7 and after.b > 0.7: art_pixels += 1
		if changed < 100 or art_pixels < 40: failures.append("Missing visible press feedback or artwork at " + label)
		if outer_changes > 0: failures.append("Press changed the outer frame at " + label + ": " + str(outer_changes))
		for button in [key, dodge, ultimate]:
			button.release()
			button._advance_feedback(0.12)
		await capture(canvas, label + "-rebound")
		for button in [key, dodge, ultimate]: button._advance_feedback(0.1)
		combat.cooldowns[2] = 0.0
		combat.energy[2] = combat.skill_cost(2) - 2.4
		game.hud.update_combat(combat, false)
		key.charging = true
		key.charge_fraction = 0.65
		key.queue_redraw()
		await capture(canvas, label + "-charging")
		key.charging = false
		key.queue_redraw()
		event.index = 8
		event.pressed = true
		event.position = key.get_global_transform_with_canvas() * (key.size * 0.5)
		key._input(event)
		event.pressed = false
		key._input(event)
		key._advance_feedback(0.04)
		await capture(canvas, label + "-tap")
		key._advance_feedback(0.3)
	var report = {"failures": failures, "captures": captures, "main_processing": game.is_processing(), "renderer": RenderingServer.get_video_adapter_name()}
	FileAccess.open("res://reports/skill-controls-visual.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("SKILL_CONTROLS_VISUAL ", JSON.stringify(report))
	game.queue_free()
	await process_frame
	canvas.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func capture(canvas: SubViewport, label: String) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var image = canvas.get_texture().get_image()
	var path = "res://reports/skill-controls-%s.png" % label
	image.save_png(path)
	captures.append(path)
	return image
