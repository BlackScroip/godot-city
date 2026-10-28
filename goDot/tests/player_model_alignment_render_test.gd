extends SceneTree

var checks := 0
var failures: Array[String] = []
var actor: DungeonActor
var camera: Camera3D
var canvas: SubViewport

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _run() -> void:
	check(DisplayServer.get_name() != "headless", "Movement rendering requires a graphics device")
	if not failures.is_empty():
		_finish()
		return
	canvas = SubViewport.new()
	canvas.size = Vector2i(1280, 800)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var stage := Node3D.new()
	canvas.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("33413d")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.8
	stage.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -35, 0)
	stage.add_child(light)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(100, 1, 100)
	shape.shape = floor_shape
	shape.position.y = -0.5
	floor_body.add_child(shape)
	stage.add_child(floor_body)
	actor = DungeonActor.new()
	actor.is_player = true
	actor.actor_id = 1
	stage.add_child(actor)
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/catalog.json"))
	actor.set_visual("res://assets/characters/fashions/fashion_1001.glb", catalog.characters["1"])
	actor.set_process(false)
	actor.set_physics_process(false)
	actor.equip_weapon(catalog.weapons["101"].path)
	DungeonWorldStyle.apply_models(actor)
	var marker := MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.30
	ring.outer_radius = 0.35
	marker.mesh = ring
	marker.position.y = 0.025
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("f0d64a")
	marker.material_override = material
	actor.add_child(marker)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.1
	stage.add_child(camera)
	var skeleton: Skeleton3D = actor.visual.find_children("*", "Skeleton3D", true, false)[0]
	var root_bone := skeleton.find_bone("root")
	var samples: Array[Dictionary] = []
	for direction in [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT, Vector3.ZERO]:
		actor.desired_velocity = direction * 4.0
		var maximum := 0.0
		for step in 38:
			await physics_frame
			actor._physics_process(1.0 / 60)
			actor._process(1.0 / 60)
			camera.position = actor.position + Vector3(2.5, 3.5, -5.0)
			camera.look_at(actor.position + Vector3.UP * 0.65)
			var point := skeleton.global_transform * skeleton.get_bone_global_pose(root_bone).origin
			var offset := point - actor.global_position
			maximum = maxf(maximum, Vector2(offset.x, offset.z).length())
		check(maximum < 0.0001, "Rendered movement keeps the source animation root centered through " + str(direction))
		await RenderingServer.frame_post_draw
		var capture := canvas.get_texture().get_image()
		var colors := {}
		for y in range(150, 650, 8):
			for x in range(250, 1030, 8):
				colors[capture.get_pixel(x, y).to_rgba32()] = true
		check(colors.size() > 100, "Source skin, attached weapon and ground marker have rendered pixels")
		var index := samples.size()
		var filename := "res://reports/player-walking-aligned-%d-1280x800.png" % index
		capture.save_png(filename)
		samples.append({"direction": var_to_str(direction), "maximum_horizontal_offset": maximum, "colors": colors.size(), "screenshot": filename})
	FileAccess.open("res://reports/player-model-alignment-render-20261028.json", FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures, "samples": samples}, "\t"))
	canvas.queue_free()
	await process_frame
	_finish()

func _finish() -> void:
	print("PLAYER_MODEL_ALIGNMENT_RENDER: %d checks, %d failures" % [checks, failures.size()])
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
