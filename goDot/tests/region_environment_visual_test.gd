extends SceneTree

const SCENES := [1061101, 1069101, 1070001, 1070101, 1079101]
var failures: Array[String] = []
var rows: Array = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Region visual test requires graphical rendering")
		quit(2)
		return
	for action in ["move_left", "move_right", "move_up", "move_down"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	var canvas := SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.own_world_3d = true
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var display := TextureRect.new()
	display.texture = canvas.get_texture()
	display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	root.add_child(display)
	var world := DungeonWorld.new()
	canvas.add_child(world)
	var combat := preload("res://scripts/domain/combat.gd").new()
	combat.configure()
	for id in SCENES:
		world.load_environment(id)
		world.create_player(combat, 1)
		for frame in 30: await process_frame
		world.snap_camera()
		await RenderingServer.frame_post_draw
		var image := canvas.get_texture().get_image()
		var path := "res://reports/region-environment-%s.png" % id
		image.save_png(path)
		var colors: Dictionary = {}
		for y in range(0, image.get_height(), 12):
			for x in range(0, image.get_width(), 12): colors[image.get_pixel(x, y).to_rgba32()] = true
		if colors.size() < 150: failures.append(str(id) + " rendered frame lacks scene variation")
		var player_screen := world.camera.unproject_position(world.player.global_position + Vector3.UP)
		if not Rect2(Vector2.ZERO, canvas.size).has_point(player_screen): failures.append(str(id) + " source player spawn is outside camera frame")
		var terrain_count := 0
		var unbound_terrain := 0
		for node in world.environment_root.find_children("*", "MeshInstance3D", true, false):
			for surface in node.mesh.get_surface_count():
				var material = node.get_active_material(surface)
				if material.resource_name.begins_with("UnityTerrain/"): terrain_count += 1
				elif "Splatmap" in material.resource_name: unbound_terrain += 1
		if terrain_count == 0 or unbound_terrain > 0: failures.append(str(id) + " terrain source layers are not bound")
		rows.append({"id": id, "capture": path, "unique_pixel_samples": colors.size(),
			"player_source_position": world.environment_entry.player_start, "player_runtime_position": [world.player.position.x, world.player.position.y, world.player.position.z],
			"player_screen": [player_screen.x, player_screen.y], "camera_position": [world.camera.position.x, world.camera.position.y, world.camera.position.z],
			"terrain_materials": terrain_count, "unbound_terrain_materials": unbound_terrain})
		world.release_environment()
		await process_frame
	world.queue_free()
	await process_frame
	var report := {"passed": failures.is_empty(), "failures": failures, "scenes": rows}
	FileAccess.open("res://reports/region-environment-visual-test.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("REGION ENVIRONMENT VISUAL ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
