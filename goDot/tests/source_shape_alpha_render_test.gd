extends SceneTree

const SourceMaterial = preload("res://scripts/presentation/recovered_effect_material.gd")
var failures: Array[String] = []
var checks := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(640, 640)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.03, 0.04, 0.05)
	root.add_child(environment)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.5
	camera.position.z = 2
	camera.current = true
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/spirit_followers/catalog.json"))
	var source: Dictionary = {}
	var cases: Array[Dictionary] = []
	for layer in catalog.effects.summonunit_sprite_fire_1.layers:
		if layer.name == "23120601_buff_fragment": source = layer.materials[0]
		if layer.name == "23120601_buff_fire": cases.append(layer.materials[0])
	check(is_equal_approx(float(source.source_floats._ShapeBrightness), 0.7), "Regression uses the exact APK fire-fragment brightness")
	check("SHAPE1CONTRAST_ON" in source.keywords and not "SHAPE1SHAPECOLOR_ON" in source.keywords, "Regression uses source RGBA contrast variant")
	cases.push_front(source)
	var library: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/combat_presentation/materials.json"))
	for value in library.values():
		if value.name in ["mat_fx_24010801_hit_flash", "mat_fx_24010801_hit_scratch", "mat_fx_24080101_explode_fragment", "mat_fx_23101901_smash_stone", "mat_fx_23112901_accumulation_flash"]: cases.append(value)
	var quad := MeshInstance3D.new()
	quad.mesh = QuadMesh.new()
	quad.mesh.size = Vector2(2, 2)
	root.add_child(quad)
	var method = RenderingServer.get_current_rendering_method()
	var results: Array[Dictionary] = []
	for candidate in cases:
		var material = SourceMaterial.create(candidate, {})
		# Isolate the source shape stage from the independent source erosion stage.
		material.set_shader_parameter("use_source_fade", false)
		material.set_shader_parameter("use_source_burn", false)
		quad.material_override = material
		await process_frame
		await RenderingServer.frame_post_draw
		await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var background = image.get_pixel(20, 20)
		var source_texture: Texture2D = load(str(candidate.texture))
		var texture_image := source_texture.get_image()
		if texture_image.is_compressed(): texture_image.decompress()
		for point in [Vector2i(80, 80), Vector2i(560, 80), Vector2i(80, 560), Vector2i(560, 560)]:
			var uv = (Vector2(point) - Vector2(64, 64)) / 512.0
			var texel = texture_image.get_pixel(int(uv.x * texture_image.get_width()), int(uv.y * texture_image.get_height()))
			var source_alpha = texel.r if "SHAPE1SHAPECOLOR_ON" in candidate.keywords else texel.a
			if source_alpha > 0.001: continue
			var actual = image.get_pixelv(point)
			check(Vector3(actual.r, actual.g, actual.b).distance_to(Vector3(background.r, background.g, background.b)) < 0.02, str(candidate.name) + " preserves transparent source corner " + str(point))
		var visible := 0
		for y in range(100, 540, 4):
			for x in range(100, 540, 4):
				if image.get_pixel(x, y).get_luminance() > background.get_luminance() + 0.08: visible += 1
		check(visible > 100, str(candidate.name) + " retains nonblank source pixels")
		var target = "res://reports/source-shape-alpha-" + method + "-" + str(candidate.name) + ".png"
		image.save_png(target)
		results.append({"material": candidate.name, "visible_samples": visible, "screenshot": target})
	var report = {"passed": failures.is_empty(), "checks": checks, "failures": failures, "rendering_method": method, "rendering_driver": RenderingServer.get_current_rendering_driver_name(),
		"source_material": source.source, "materials": results,
		"scope": "GPU regression of exact source RGBA brightness/contrast transparency; erosion disabled to isolate shape alpha."}
	FileAccess.open("res://reports/source-shape-alpha-" + method + ".json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("SOURCE_SHAPE_ALPHA ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
