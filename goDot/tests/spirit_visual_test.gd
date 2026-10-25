extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(60).timeout.connect(func(): quit(2))
	var canvas := SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var game = load("res://scenes/main.tscn").instantiate()
	game.save_store = DungeonSaveStore.new("res://reports/spirit-visual-profile-%d.json" % Time.get_ticks_usec())
	canvas.add_child(game)
	await process_frame
	game._primary()
	game._action("select_region", 2, 0)
	while game._loading or game._transitioning: await process_frame
	game.hud.close_page()
	var granted: Array = []
	for id in [20210, 20211, 20220, 20230, 20260]:
		granted.append({"id": id, "success": game.systems.add_loot(id).success})
	game._apply_growth()
	game.world.auto_attack_enabled = false
	game.world.camera.size = 12
	for frame in 120: await physics_frame
	game.world.set_physics_process(false)
	game.set_process(false)
	for frame in 10: await process_frame
	await RenderingServer.frame_post_draw
	var capture: Image = canvas.get_texture().get_image()
	var colors: Dictionary = {}
	for y in range(0, capture.get_height(), 20):
		for x in range(0, capture.get_width(), 20): colors[capture.get_pixel(x, y).to_html()] = true
	var result := capture.save_png("res://reports/spirit-followers.png")
	for frame in 12: game.world.spirit_followers.advance(1.0 / 60.0, game.world.player)
	await process_frame
	await RenderingServer.frame_post_draw
	var animated: Image = canvas.get_texture().get_image()
	animated.save_png("res://reports/spirit-followers-animated.png")
	var motion_visible := capture.get_data() != animated.get_data()
	var count: int = game.world.spirit_followers.entries.size()
	print(JSON.stringify({"granted": granted, "companions": count, "sample_colors": colors.size(), "saved": result == OK, "motion_visible": motion_visible, "position": str(game.world.player.position)}))
	game.queue_free()
	await process_frame
	quit(0 if count >= 2 and colors.size() > 50 and result == OK and motion_visible else 1)
