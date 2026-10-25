extends SceneTree

const FACTORY = preload("res://scripts/presentation/recovered_effect_material.gd")
var viewport: SubViewport
var quad: MeshInstance3D
var checks := 0
var failures: Array[String] = []
var samples: Array = []
var textures: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _texture(key: String, color: Color) -> String:
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(color)
	textures[key] = ImageTexture.create_from_image(image)
	return key

func _source(key: String, keywords: Array = []) -> Dictionary:
	return {"shader": "AllIn1Vfx/Test", "blend": "alpha", "keywords": keywords,
		"source_floats": {"_Alpha": 1.0}, "source_colors": {},
		"textures": [{"property": "_MainTex", "texture": key, "scale": {"x": 1, "y": 1}, "offset": {"x": 0, "y": 0}}]}

func _map(source: Dictionary, property: String, key: String) -> void:
	source.textures.append({"property": property, "texture": key, "scale": {"x": 1, "y": 1}, "offset": {"x": 0, "y": 0}})

func _pixel(source: Dictionary, clock := 0.0, uniforms: Dictionary = {}) -> Color:
	var material := FACTORY.create(source, textures)
	material.set_shader_parameter("clock", clock)
	for key in uniforms: material.set_shader_parameter(key, uniforms[key])
	quad.material_override = material
	for frame in 3: await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image().get_pixel(32, 32)

func _check_pixel(label: String, actual: Color, unblended: Color) -> void:
	# Compatibility blends into transparent black in display space; readback is
	# premultiplied RGB. Alpha is independent of the source_color conversions.
	var expected := Color(unblended.r * unblended.a, unblended.g * unblended.a, unblended.b * unblended.a, unblended.a)
	var error := maxf(maxf(absf(actual.r - expected.r), absf(actual.g - expected.g)), maxf(absf(actual.b - expected.b), absf(actual.a - expected.a)))
	checks += 1
	if error > 0.035: failures.append(label + ": " + str(actual) + " expected " + str(expected))
	samples.append({"case": label, "actual": [actual.r, actual.g, actual.b, actual.a], "expected": [expected.r, expected.g, expected.b, expected.a], "max_error": error})

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("GPU readback requires a graphical Compatibility run")
		quit(2)
		return
	viewport = SubViewport.new()
	viewport.size = Vector2i(64, 64)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0, 0, 0, 0)
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.environment.ambient_light_energy = 0
	viewport.add_child(environment)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2
	camera.position = Vector3(0, 0, 2)
	viewport.add_child(camera)
	quad = MeshInstance3D.new()
	quad.mesh = QuadMesh.new()
	quad.mesh.size = Vector2(2, 2)
	viewport.add_child(quad)
	var main_key := _texture("synthetic:main", Color(0.25, 0.75, 0.5, 0.8))
	var white_key := _texture("synthetic:white", Color.WHITE)
	_check_pixel("static COLOR defaults to white", await _pixel(_source(white_key)), Color.WHITE)
	_check_pixel("RGBA uses sample RGB and alpha", await _pixel(_source(main_key)), Color(0.25, 0.75, 0.5, 0.8))
	var red := _source(main_key, ["SHAPE1SHAPECOLOR_ON"])
	red.source_colors["_ShapeColor"] = {"r": 1, "g": 0.5, "b": 0.25, "a": 0.1}
	_check_pixel("shape-color takes red opacity, ignores texture green and color alpha", await _pixel(red), Color(1, 0.5, 0.25, 0.25))
	var product := _source(_texture("synthetic:first", Color(0.5, 0.5, 0.5, 1)), ["SHAPE1SHAPECOLOR_ON", "SHAPE2SHAPECOLOR_ON", "SHAPE2_ON"])
	_map(product, "_Shape2Tex", _texture("synthetic:second", Color(0.5, 0.8, 1, 1)))
	product.source_colors["_ShapeColor"] = {"r": 0.5, "g": 0.5, "b": 0.5, "a": 1}
	product.source_colors["_Shape2Color"] = {"r": 1, "g": 1, "b": 1, "a": 1}
	product.source_floats.merge({"_ShapeColorWeight": 0.5, "_Shape2ColorWeight": 1.5, "_ShapeAlphaWeight": 0.1, "_Shape2AlphaWeight": 0.1})
	_check_pixel("Shape2 multiplies RGBA and color weights, no separate alpha weight", await _pixel(product), Color(0.375, 0.375, 0.375, 0.1875))
	var masked := _source(white_key, ["MASK_ON"])
	_map(masked, "_MaskTex", _texture("synthetic:mask", Color(0.8, 1, 1, 0.3)))
	_check_pixel("MASK min red alpha", await _pixel(masked), Color(1, 1, 1, 0.3))
	masked.source_floats["_MaskPow"] = 2
	_check_pixel("MASK power after min", await _pixel(masked), Color(1, 1, 1, 0.09))
	var first_mask := product.duplicate(true)
	first_mask.keywords.append("SHAPE1MASK_ON")
	_map(first_mask, "_Shape1MaskTex", _texture("synthetic:first-mask", Color(0.5, 0.2, 0.1, 0.1)))
	_check_pixel("Shape1Mask interpolates product back to first RGBA", await _pixel(first_mask), Color(0.4375, 0.4375, 0.4375, 0.34375))
	var stripes := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	for y in 8:
		for x in 8: stripes.set_pixel(x, y, Color.WHITE if x < 4 else Color.BLACK)
	textures["synthetic:scroll"] = ImageTexture.create_from_image(stripes)
	var scroll := _source("synthetic:scroll", ["SHAPE1SHAPECOLOR_ON"])
	scroll.textures[0].offset.x = -0.25
	scroll.source_floats["_ShapeXSpeed"] = 0.5
	var before := await _pixel(scroll, 0)
	var after := await _pixel(scroll, 1)
	_check_pixel("scroll initial white texels", before, Color.WHITE)
	_check_pixel("scroll reaches black texels", after, Color(1, 1, 1, 0))
	checks += 1
	if absf(before.a - after.a) < 0.8: failures.append("Scroll does not visibly change pixels")
	var contrast := _source(main_key, ["SHAPE1SHAPECOLOR_ON", "SHAPE2SHAPECOLOR_ON", "SHAPE2_ON", "SHAPE2CONTRAST_ON"])
	_map(contrast, "_Shape2Tex", _texture("synthetic:contrast", Color(0.9, 0.1, 0.1, 1)))
	contrast.source_colors.merge({"_ShapeColor": {"r": 0.8, "g": 0.8, "b": 0.8, "a": 1}, "_Shape2Color": {"r": 0.9, "g": 0.9, "b": 0.9, "a": 1}})
	contrast.source_floats.merge({"_Shape2Contrast": 4.0, "_Shape2Brightness": 0.0, "_Shape2ColorWeight": 0.5})
	_check_pixel("Contrast modifies red alpha only and clamps after weighted product", await _pixel(contrast), Color(0.36, 0.36, 0.36, 0.2625))
	var wrap := _source("synthetic:scroll", ["SHAPE1SHAPECOLOR_ON"])
	wrap.textures[0].offset.x = 0.75
	wrap.textures[0]["wrap"] = {"x": 1, "y": 1}
	_check_pixel("Clamp beyond edge samples black edge", await _pixel(wrap), Color(1, 1, 1, 0))
	wrap.textures[0].wrap = {"x": 0, "y": 0}
	_check_pixel("Repeat beyond edge samples next white tile", await _pixel(wrap), Color.WHITE)
	wrap.textures[0].wrap = {"x": 1, "y": 1}
	wrap.textures[0].offset.x = 0
	wrap.source_floats["_ShapeXSpeed"] = -0.2
	_check_pixel("Negative scroll preserves signed fmod under clamp", await _pixel(wrap, 1), Color.WHITE)
	var fade := _source(_texture("synthetic:fade-main", Color(0.2, 0.2, 0.2, 0.8)), ["FADE_ON", "FADEBURN_ON"])
	_map(fade, "_FadeTex", _texture("synthetic:fade", Color(0.6, 0.1, 0.1, 1)))
	_map(fade, "_FadeBurnTex", _texture("synthetic:burn", Color(0.4, 0.2, 0.1, 1)))
	fade.source_colors["_FadeBurnColor"] = {"r": 1, "g": 1, "b": 1, "a": 1}
	fade.source_floats.merge({"_FadeAmount": -0.25, "_FadePower": 1, "_FadeTransition": 0.25, "_FadeBurnWidth": 0.2, "_FadeBurnGlow": 2})
	var transition := (1.0 - pow(0.25, 5)) * 0.25
	var fade_alpha := smoothstep(0, transition, 0.1)
	var edge := fade_alpha - smoothstep(0, transition + 0.2, 0.1)
	var expected_fade := Color(0.2 + 0.4 * edge * 2 * 0.8, 0.2 + 0.2 * edge * 2 * 0.8, 0.2 + 0.1 * edge * 2 * 0.8, fade_alpha * 0.8)
	_check_pixel("Source fade alpha and burn RGB match compiled formula", await _pixel(fade), expected_fade)
	var custom_image := Image.create(2, 1, false, Image.FORMAT_RGBAF)
	custom_image.fill(Color(0, 0.2, 0, 0))
	var custom0 := ImageTexture.create_from_image(custom_image)
	fade.keywords.append("ALPHAFADEINPUTSTREAM_ON")
	fade.source_floats._FadeAmount = -0.05
	_check_pixel("Custom1 y curve supplies fade input", await _pixel(fade, 0, {"use_custom_stream0": true, "custom_stream0": custom0}), expected_fade)
	_check_pixel("Fade without custom input closes at source threshold", await _pixel(fade), Color(0, 0, 0, 0))
	var offset := _source("synthetic:scroll", ["SHAPE1SHAPECOLOR_ON", "OFFSETSTREAM_ON"])
	offset.textures[0].offset.x = -0.25
	offset.source_floats["_OffsetSh1"] = 1
	custom_image.fill(Color(0.5, 0, 0, 0))
	var custom1 := ImageTexture.create_from_image(custom_image)
	_check_pixel("Custom2 x stream moves UV to black half", await _pixel(offset, 0, {"use_custom_stream1": true, "custom_stream1": custom1}), Color(1, 1, 1, 0))
	_check_pixel("Disabled Custom2 leaves source UV intact", await _pixel(offset), Color.WHITE)
	var horizontal := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	for y in 8:
		for x in 8: horizontal.set_pixel(x, y, Color.WHITE if y < 4 else Color.BLACK)
	textures["synthetic:horizontal"] = ImageTexture.create_from_image(horizontal)
	offset.textures[0].texture = "synthetic:horizontal"
	offset.textures[0].offset = {"x": 0, "y": -0.25}
	custom_image.fill(Color(0, 0.5, 0, 0))
	custom1 = ImageTexture.create_from_image(custom_image)
	_check_pixel("Custom2 y stream moves UV independently", await _pixel(offset, 0, {"use_custom_stream1": true, "custom_stream1": custom1}), Color(1, 1, 1, 0))
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "samples": samples, "renderer": RenderingServer.get_current_rendering_method(), "tolerance": 0.035, "original_apk_runtime": false}
	var output := FileAccess.open("res://reports/recovered-environment-shader-tests.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t"))
	print("RECOVERED ENVIRONMENT SHADER ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
