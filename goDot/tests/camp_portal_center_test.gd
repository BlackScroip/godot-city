extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var canvas := SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var game = load("res://scenes/main.tscn").instantiate()
	game.save_store = DungeonSaveStore.new("/private/tmp/camp-portal-center-%d.json" % Time.get_ticks_usec())
	canvas.add_child(game)
	await process_frame
	while game.startup_loading: await process_frame
	game.hud.close_page()
	game.set_process(false)
	game.audio.stop()
	game.world.set_physics_process(false)
	game.world._background = false
	game.world.paused = false
	game.hud.update_combat(game.world.player.combat, true)
	game.world.player.position = Vector3(29.72984, 0.1, 78.39)
	var fx = game.world.environment_root.get_node("CampEffects")
	if fx.north_portal_surfaces.size() != 5: failures.append("North portal must restore all five APK mesh materials")
	var definitions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/environment_effects/camp_north_portal_materials.json")).materials
	for material in fx.north_portal_surfaces:
		var source: Dictionary = definitions[material.resource_name]
		if material.get_shader_parameter("shape1_scroll") != Vector2(source.source_floats._ShapeXSpeed, source.source_floats._ShapeYSpeed):
			failures.append("Source UV scroll changed")
	for size in [Vector2i(1600, 900), Vector2i(844, 390)]:
		canvas.size = size
		for i in 20: await process_frame
		game.world._background = false
		game.world.paused = false
		fx.set_process(false)
		for material in fx.north_portal_surfaces: material.set_shader_parameter("clock", 0.0)
		await process_frame
		await RenderingServer.frame_post_draw
		var before := canvas.get_texture().get_image()
		for material in fx.north_portal_surfaces: material.set_shader_parameter("clock", 2.0)
		await process_frame
		await RenderingServer.frame_post_draw
		var after := canvas.get_texture().get_image()
		after.save_png("res://reports/camp-north-portal-%dx%d.png" % [size.x, size.y])
		var center := canvas.get_camera_3d().unproject_position(Vector3(29.72984, 2.13, 82.39))
		var changed := 0
		var radius := int(size.y * 0.12)
		for y in range(maxi(0, int(center.y) - radius), mini(size.y, int(center.y) + radius)):
			for x in range(maxi(0, int(center.x) - radius), mini(size.x, int(center.x) + radius)):
				var difference := before.get_pixel(x, y) - after.get_pixel(x, y)
				if absf(difference.r) + absf(difference.g) + absf(difference.b) > 0.06: changed += 1
		print("NORTH_PORTAL_MOTION_PIXELS ", size, " ", changed)
		if changed < 20: failures.append("Portal center remains static at " + str(size))
	fx.set_process(true)
	game.world._background = false
	game.world.paused = false
	var clock_before: float = fx.clock
	fx._process(0.1)
	if fx.clock <= clock_before: failures.append("Portal animation clock does not advance")
	game.world.paused = true
	clock_before = fx.clock
	fx._process(0.1)
	if fx.clock != clock_before: failures.append("Portal animation does not pause")
	game.queue_free()
	await process_frame
	print("CAMP_PORTAL_CENTER ", JSON.stringify({"failures": failures}))
	quit(0 if failures.is_empty() else 1)
