extends SceneTree

var game: Node
var canvas: SubViewport
var failures: Array[String] = []
var captures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.mesh_lod_threshold = 0.0
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var display = TextureRect.new()
	display.texture = canvas.get_texture()
	display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	root.add_child(display)
	game = load("res://scenes/main.tscn").instantiate()
	game.save_store = DungeonSaveStore.new("res://reports/environment-style-profile-%d.json" % Time.get_ticks_usec())
	canvas.add_child(game)
	await process_frame
	var counts: Dictionary = {}
	for mesh in game.world.environment_root.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var material = mesh.get_active_material(surface)
			if "grass_tree_stump" in material.resource_name.to_lower():
				print("GRASS_MATERIAL ", mesh.name, " alpha=", material.transparency, " cutoff=", material.alpha_scissor_threshold, " tint=", material.albedo_color, " texture=", material.albedo_texture.resource_path, " uv=", material.uv1_scale, " ", material.uv1_offset)
			if material and (material.resource_name.begins_with("UnityPaint/") or material.resource_name.begins_with("UnityTerrain/")):
				var kind = DungeonWorldStyle._surface_kind(material.resource_name)
				counts[kind] = int(counts.get(kind, 0)) + 1
	for kind in [0, 1, 2, 3, 4, 5]:
		if int(counts.get(kind, 0)) == 0: failures.append("Missing environment material category " + str(kind))
	game.world.player.position = Vector3(31, 0.2, 29.8)
	for i in 40: await process_frame
	await capture("camp")
	var entrances = game.world.environment_root.find_children("*Portal*Entrance*", "Node3D", true, false)
	for node in entrances:
		print("ENTRANCE ", node.name, " ", node.global_position)
	var waterfalls = game.world.environment_root.find_children("*", "MeshInstance3D", true, false)
	for mesh in waterfalls:
		for surface in mesh.mesh.get_surface_count():
			var material = mesh.get_active_material(surface)
			if material and "waterfall" in material.resource_name.to_lower():
				print("WATERFALL ", mesh.name, " ", mesh.global_position, " bounds=", mesh.get_aabb())
	game.world.player.position = Vector3(27.0, 0.1, 80.0)
	for i in 40: await process_frame
	await capture("waterfall")
	canvas.size = Vector2i(1200, 900)
	for i in 10: await process_frame
	await capture("waterfall-4x3")
	canvas.size = Vector2i(1600, 900)
	game._smoke_begin()
	for i in 50: await process_frame
	await capture("forest-battle")
	var report = {"passed": failures.is_empty(), "failures": failures, "materials": counts, "captures": captures}
	FileAccess.open("res://reports/environment-style-tests.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("ENVIRONMENT STYLE ", JSON.stringify(report))
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var picture = canvas.get_texture().get_image()
	var path = "res://reports/environment-" + label + ".png"
	picture.save_png(path)
	captures.append(path)
