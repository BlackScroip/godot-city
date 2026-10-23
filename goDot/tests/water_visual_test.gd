extends SceneTree

const RECOVERED = preload("res://scripts/presentation/recovered_environment.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(960, 540)
	var scene := Node3D.new()
	root.add_child(scene)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 12, 10)
	scene.add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 14
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-65, 15, 0)
	scene.add_child(light)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/environment_recovered/water_materials.json"))
	var index := 0
	for label: String in data:
		var mesh := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(2.8, 2.8)
		mesh.mesh = plane
		var source := StandardMaterial3D.new()
		source.resource_name = label
		mesh.material_override = RECOVERED.material(source)
		mesh.position = Vector3((index % 4) * 3.1 - 4.65, 0, (index / 4) * 3.3 - 1.65)
		scene.add_child(mesh)
		index += 1
	RECOVERED.advance_water(scene, 0.01)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var before := root.get_texture().get_image()
	before.save_png("res://reports/water-motion-before.png")
	RECOVERED.advance_water(scene, 1.0)
	await process_frame
	await RenderingServer.frame_post_draw
	var after := root.get_texture().get_image()
	after.save_png("res://reports/water-motion-after.png")
	var changed := 0
	for y in range(0, before.get_height(), 3):
		for x in range(0, before.get_width(), 3):
			if before.get_pixel(x, y) != after.get_pixel(x, y): changed += 1
	print(JSON.stringify({"changed_sampled_pixels": changed, "passed": changed > 100}))
	quit(0 if changed > 100 else 1)
