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
	await verify_water_motion()
	canvas.size = Vector2i(1200, 900)
	for i in 10: await process_frame
	await capture("waterfall-4x3")
	canvas.size = Vector2i(1600, 900)
	var combat = game.world.player.combat
	var character_id = game.world.player.actor_id
	game.world.load_environment(1010101)
	game.world.create_player(combat, character_id)
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

func verify_water_motion() -> void:
	var scene = game.world.environment_root
	var materials: Array = scene.get_meta("water_materials", [])
	if materials.is_empty():
		failures.append("No animated water materials")
		return
	game.process_mode = Node.PROCESS_MODE_DISABLED
	await process_frame
	await RenderingServer.frame_post_draw
	var before = canvas.get_texture().get_image()
	var elapsed = float(materials[0].get_shader_parameter("elapsed"))
	preload("res://scripts/presentation/recovered_environment.gd").advance_water(scene, 1.5)
	if float(materials[0].get_shader_parameter("elapsed")) <= elapsed:
		failures.append("Water shader clock did not advance")
	await process_frame
	await RenderingServer.frame_post_draw
	var after = canvas.get_texture().get_image()
	var changed := 0
	for y in range(0, before.get_height(), 4):
		for x in range(0, before.get_width(), 4):
			var a = before.get_pixel(x, y)
			var b = after.get_pixel(x, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.03: changed += 1
	if changed < 100: failures.append("Water motion not visible in rendered pixels")
	print("WATER MOTION changed samples=", changed)
	game.process_mode = Node.PROCESS_MODE_INHERIT
