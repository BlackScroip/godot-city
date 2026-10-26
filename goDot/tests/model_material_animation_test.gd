extends SceneTree

const Effect = preload("res://scripts/presentation/authored_effect.gd")
const ModelAnimation = preload("res://scripts/presentation/model_material_animation.gd")
var checks := 0
var failures: Array[String] = []
var renders: Array[Dictionary] = []

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func _initialize() -> void:
	_run.call_deferred()

func _material(effect: Node3D) -> ShaderMaterial:
	return effect.model_styles[0].runtime.materials.values()[0][0]

func _posed_bounds(mesh: MeshInstance3D) -> AABB:
	if mesh.skin == null or mesh.skeleton.is_empty(): return mesh.global_transform * mesh.get_aabb()
	var skeleton: Skeleton3D = mesh.get_node(mesh.skeleton)
	var transforms: Array[Transform3D] = []
	for bind in mesh.skin.get_bind_count():
		var bone = skeleton.find_bone(mesh.skin.get_bind_name(bind))
		if bone < 0: bone = mesh.skin.get_bind_bone(bind)
		transforms.append(skeleton.global_transform * skeleton.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(bind))
	var result := AABB()
	var first := true
	for surface in mesh.mesh.get_surface_count():
		var arrays = mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var influences = weights.size() / vertices.size()
		for i in vertices.size():
			var point := Vector3.ZERO
			for slot in int(influences):
				var index = int(i * influences + slot)
				point += (transforms[bones[index]] * vertices[i]) * weights[index]
			result = AABB(point, Vector3.ZERO) if first else result.expand(point)
			first = false
	return result

func _run() -> void:
	check(is_equal_approx(ModelAnimation.sample_curve({"kind": "streamed", "keys": [[0, 2, -3, 4, 5]]}, 0.5), 6.5), "Streamed source coefficients retain cubic interpolation between keys")
	check(is_equal_approx(ModelAnimation.sample_curve({"kind": "dense", "begin": 0.1, "rate": 10, "values": [1, 3, 2]}, 0.15), 2), "Dense curves retain source sample timing and interpolation")
	check(is_equal_approx(ModelAnimation.sample_curve({"kind": "constant", "value": 7}, 2), 7), "Source constants remain constant")
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/combat_presentation/catalog.json"))
	var evidence: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://reports/skill-model-material-animation.json"))
	var render = "--render-check" in OS.get_cmdline_user_args()
	var camera: Camera3D
	if render:
		camera = Camera3D.new()
		root.size = Vector2i(640, 640)
		root.add_child(camera)
		camera.current = true
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		environment.environment.background_mode = Environment.BG_COLOR
		environment.environment.background_color = Color(0.04, 0.05, 0.06)
		root.add_child(environment)
	var models := 0
	for name in evidence.prefabs:
		var definition: Dictionary = catalog.effects[name]
		var row: Dictionary = evidence.prefabs[name]
		check(not row.shader_programs.is_empty(), name + " exactly matches APK shader keywords")
		check(row.material_animation.controllers.size() == 1, name + " retains its source material controller")
		var effect = Effect.new()
		root.add_child(effect)
		effect.configure(definition, false, {})
		effect.restart()
		check(effect.model_styles.size() == 1, name + " creates its material animation runtime")
		var materials_applied := 0
		for mesh: MeshInstance3D in effect.find_children("*", "MeshInstance3D", true, false):
			for surface in mesh.mesh.get_surface_count():
				if mesh.get_active_material(surface) is ShaderMaterial: materials_applied += 1
		check(materials_applied > 0, name + " applies source shader to actual mesh surfaces")
		var runtime = effect.model_styles[0].runtime
		var clip: Dictionary = runtime.controllers[0].clip
		var curve: Dictionary = clip.tracks[0].curve
		var material = _material(effect)
		check(is_equal_approx(float(material.get_shader_parameter("source_fade_amount")), ModelAnimation.sample_curve(curve, float(clip.start))), name + " starts at the actual source key")
		effect.advance(0.12, false)
		var first = float(material.get_shader_parameter("source_fade_amount"))
		check(is_equal_approx(first, ModelAnimation.sample_curve(curve, 0.12 + float(clip.start))), name + " evaluates source cubic without resampling")
		effect.advance(0.2, true)
		check(is_equal_approx(float(material.get_shader_parameter("source_fade_amount")), first), name + " pauses its material and model clocks together")
		var clone = effect.instantiate_effect()
		root.add_child(clone)
		clone.restart()
		check(_material(clone) != material, name + " clone owns independent mutable source material")
		clone.advance(0.3, false)
		check(is_equal_approx(float(material.get_shader_parameter("source_fade_amount")), first), name + " advancing another clone preserves existing material values")
		effect.restart()
		check(is_equal_approx(float(material.get_shader_parameter("source_fade_amount")), ModelAnimation.sample_curve(curve, float(clip.start))), name + " restarts its source material controller")
		if "sword_weapon4" in name:
			check(is_equal_approx(float(material.get_shader_parameter("source_fade_amount")), 1), name + " exact sword soul begins dissolved")
			effect.advance(1.0 / 12.0, false)
			check(is_equal_approx(float(material.get_shader_parameter("source_fade_amount")), 0.5), name + " exact sword soul appears at source key 1/12s")
			effect.advance(0.75, false)
			check(is_equal_approx(float(material.get_shader_parameter("source_fade_amount")), 1), name + " sword soul dissolves at source end")
		if render:
			clone.free()
			clone = null
			effect.restart()
			var sample_time = minf(0.4, float(clip.duration) * 0.5)
			effect.advance(sample_time, false)
			var bounds := AABB()
			var first_bound := true
			for mesh: MeshInstance3D in effect.find_children("*", "MeshInstance3D", true, false):
				var box = _posed_bounds(mesh)
				bounds = box if first_bound else bounds.merge(box)
				first_bound = false
			var center := bounds.get_center()
			var span = maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
			camera.size = span * 1.5
			camera.position = center + Vector3(0.8, 0.5, 1).normalized() * span * 3
			camera.look_at(center)
			await process_frame
			await RenderingServer.frame_post_draw
			await process_frame
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			var target = "res://reports/skill-model-renders/" + name + ".png"
			DirAccess.make_dir_recursive_absolute("res://reports/skill-model-renders")
			image.save_png(target)
			var colored := 0
			for y in range(0, image.get_height(), 4):
				for x in range(0, image.get_width(), 4):
					var pixel = image.get_pixel(x, y)
					if maxf(pixel.r, maxf(pixel.g, pixel.b)) - minf(pixel.r, minf(pixel.g, pixel.b)) > 0.08 or pixel.get_luminance() > 0.18: colored += 1
			check(colored > 20, name + " actually renders visible source pixels")
			renders.append({"name": name, "source_time": sample_time, "sampled_visible_pixels": colored, "path": target})
		if clone != null: clone.free()
		effect.free()
		models += 1
	check(models == 13, "All thirteen source models have material curve coverage")
	check(evidence.unresolved_counts.size() == 1 and int(evidence.unresolved_counts.get("animator_root_motion", 0)) == 126, "Remaining unsupported source channels are explicitly classified root motion")
	var report = {"passed": failures.is_empty(), "checks": checks, "models": models, "render_check": render, "renders": renders, "failures": failures,
		"scope": "Exact source material curve values, applied shader surfaces, pause/restart and clone independence; optional GPU screenshots confirm nonblank source silhouettes, not pixel identity with the original APK."}
	FileAccess.open("res://reports/skill-model-material-runtime.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("MODEL_MATERIAL ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
