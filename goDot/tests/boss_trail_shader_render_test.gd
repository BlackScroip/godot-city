extends SceneTree

const BossTrail = preload("res://scripts/presentation/boss_embedded_trail.gd")
const DRAGON_MATERIAL := "CAB-e355e6b0d05ab47d2012d0e8ccc2b413:-7520495672365228611"
const REFERENCE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
uniform sampler2D fade_map : hint_default_white;
uniform bool multiply_vertex_alpha = false;
void fragment() {
	float q = clamp(1.0 - COLOR.a + 0.25, 0.0, 1.0);
	float threshold = texture(fade_map, UV).r + 1.0 - 2.0 * q;
	float transition = max((1.0 - pow(1.0 - q, 5.0)) * 0.193, 0.01);
	ALBEDO = vec3(1.0);
	ALPHA = smoothstep(0.0, transition, threshold) * (multiply_vertex_alpha ? COLOR.a : 1.0);
}
"""

var failures: Array[String] = []
var checks := 0
var rows: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _texture(color: Color) -> ImageTexture:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)

func _source(material_id: String) -> Dictionary:
	return {
		"source": material_id, "shader": "AllIn1Vfx/AllIn1VfxSRPBatch",
		"texture": "test://white", "keywords": ["FADE_ON", "SHAPE1SHAPECOLOR_ON"],
		"source_floats": {"_Alpha": 1.0, "_FadeAmount": 0.25, "_FadePower": 1.0, "_FadeTransition": 0.193},
		"textures": [{"property": "_MainTex", "texture": "test://white"}, {"property": "_FadeTex", "texture": "test://fade"}]
	}

func _view(material: ShaderMaterial, alpha: float) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(96, 96)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(0, 0, 4)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.5
	camera.current = true
	var quad := ImmediateMesh.new()
	quad.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	for vertex in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		quad.surface_set_color(Color(1, 1, 1, alpha))
		quad.surface_set_uv((vertex + Vector2.ONE) * 0.5)
		quad.surface_add_vertex(Vector3(vertex.x, vertex.y, 0))
	quad.surface_end()
	var instance := MeshInstance3D.new()
	instance.mesh = quad
	viewport.add_child(instance)
	return viewport

func _pixel(viewport: SubViewport) -> Color:
	return viewport.get_texture().get_image().get_pixel(48, 48)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("BOSS_TRAIL_SHADER_RENDER requires a graphical renderer")
		quit(1)
		return
	var owner := Node3D.new()
	root.add_child(owner)
	var fade := _texture(Color(0.55, 0.55, 0.55, 1))
	var textures := {"test://white": _texture(Color.WHITE), "test://fade": fade}
	var source := {"source_file_id": "synthetic-trail"}
	var dragon := BossTrail.new()
	dragon.configure(owner, source, _source(DRAGON_MATERIAL), textures, false)
	var ordinary := BossTrail.new()
	ordinary.configure(owner, source, _source("another-material"), textures, false)
	check(dragon._material.get_shader_parameter("source_fade_vertex_alpha") == true, "Dragon material enables vertex-alpha erosion")
	check(dragon._material.get_shader_parameter("source_fade_vertex_alpha_only") == true, "Dragon material does not multiply alpha twice")
	check(ordinary._material.get_shader_parameter("source_fade_vertex_alpha_only") != true, "Other materials retain ordinary alpha behavior")
	ordinary._material.set_shader_parameter("source_fade_vertex_alpha", true)
	var reference_shader := Shader.new()
	reference_shader.code = REFERENCE_SHADER
	var reference := ShaderMaterial.new()
	reference.shader = reference_shader
	reference.set_shader_parameter("fade_map", fade)
	var reference_multiplied := reference.duplicate() as ShaderMaterial
	reference_multiplied.set_shader_parameter("multiply_vertex_alpha", true)
	var cases: Array[Dictionary] = []
	for alpha in [0.0, 0.55, 1.0]:
		cases.append({"alpha": alpha, "dragon": _view(dragon._material, alpha), "reference": _view(reference, alpha),
			"ordinary": _view(ordinary._material, alpha), "reference_multiplied": _view(reference_multiplied, alpha)})
	for frame in 5: await process_frame
	await RenderingServer.frame_post_draw
	for item in cases:
		var actual := _pixel(item.dragon)
		var expected := _pixel(item.reference)
		var normal := _pixel(item.ordinary)
		var expected_normal := _pixel(item.reference_multiplied)
		check(absf(actual.a - expected.a) < 0.03 and absf(actual.r - expected.r) < 0.03, "Dragon fade matches source formula at vertex alpha %s" % item.alpha)
		check(absf(normal.a - expected_normal.a) < 0.03 and absf(normal.r - expected_normal.r) < 0.03, "Ordinary opacity retains vertex alpha at %s" % item.alpha)
		if is_equal_approx(item.alpha, 0.55):
			check(expected.a > 0.1 and expected.a - expected_normal.a > 0.1, "Intermediate alpha distinguishes the two shader variants")
		rows.append({"vertex_alpha": item.alpha, "dragon": actual, "reference": expected, "ordinary": normal, "reference_multiplied": expected_normal})
		for key in ["dragon", "reference", "ordinary", "reference_multiplied"]: item[key].free()
	owner.free()
	print("BOSS_TRAIL_SHADER_RENDER ", JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures, "rows": rows,
		"scope": "Synthetic Godot GPU comparison against the APK-derived fade formula; not an original APK runtime comparison."}))
	quit(0 if failures.is_empty() else 1)
