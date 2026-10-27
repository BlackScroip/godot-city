extends SceneTree

const EDITOR = preload("res://scripts/presentation/touch_layout_editor.gd")
var failures: Array[String] = []
var captures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("This test requires rendering")
		quit(1)
		return
	create_timer(45).timeout.connect(func(): quit(2))
	EDITOR.settings_path = "/private/tmp/city-touch-visual-%d.cfg" % Time.get_ticks_usec()
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
	game.save_store = DungeonSaveStore.new("/private/tmp/city-touch-visual-profile-%d.json" % Time.get_ticks_usec())
	canvas.add_child(game)
	game.world.process_mode = Node.PROCESS_MODE_DISABLED
	game.world.set_attack_mode("off")
	game._action("settings", 0, 0)
	for frame in 6: await process_frame
	game._action("customize_controls", 0, 0)
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390), Vector2i(640, 360)]:
		canvas.size = dimensions
		await process_frame
		await process_frame
		game.hud._layout()
		await RenderingServer.frame_post_draw
		var editor: Control = game.hud.touch_editor
		var image := canvas.get_texture().get_image()
		var path := "res://reports/settings-touch-%dx%d.png" % [dimensions.x, dimensions.y]
		image.save_png(path)
		captures.append(path)
		var bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
		for key in [editor.selected_label, editor.size_slider, editor.size_label, editor.reset_button, editor.cancel_button, editor.save_button]:
			if not bounds.encloses(key.get_global_rect()): failures.append("Toolbar control exceeds viewport " + str(dimensions))
		for id in editor.CONTROL_ORDER:
			var center: Vector2 = editor._center(id)
			var diameter: float = editor._diameter(id)
			var area := Rect2(center - Vector2.ONE * diameter * 0.5, Vector2.ONE * diameter)
			if not bounds.encloses(area): failures.append("Touch preview exceeds viewport " + str(dimensions) + " " + id)
			var visible_pixels := 0
			for y in range(int(area.position.y), int(area.end.y)):
				for x in range(int(area.position.x), int(area.end.x)):
					var color := image.get_pixel(x, y)
					if color.r > 0.7 and color.g > 0.7 and color.b > 0.7: visible_pixels += 1
			if visible_pixels < 10: failures.append("Missing source touch artwork " + str(dimensions) + " " + id)
	game.queue_free()
	await process_frame
	canvas.queue_free()
	await process_frame
	print("SETTINGS_TOUCH_VISUAL ", JSON.stringify({"failures": failures, "captures": captures}))
	quit(0 if failures.is_empty() else 1)
