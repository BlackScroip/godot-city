extends SceneTree

const SourceMaterial = preload("res://scripts/presentation/recovered_effect_material.gd")
const TEXTURE_KEY := "test://rgba-shape"
const BACKGROUND := Vector3(0.25, 0.18, 0.10)
const OPAQUE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec3 background;
void fragment() { ALBEDO = background; }
"""
const REFERENCE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D input_texture : source_color, filter_nearest;
uniform vec3 background;
void fragment() {
	vec4 sample_value = texture(input_texture, UV);
	ALBEDO = background + sample_value.rgb * sample_value.a * COLOR.a;
}
"""

var checks := 0
var failures: Array[String] = []
var rows: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func _texture(alpha: float) -> ImageTexture:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.70, 0.50, 0.30, alpha))
	return ImageTexture.create_from_image(image)

func _material(shader_code: String) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = shader_code
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("background", BACKGROUND)
	return material

func _quad(viewport: SubViewport, material: ShaderMaterial, vertex_alpha: float, z: float) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	for vertex in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		mesh.surface_set_color(Color(1, 1, 1, vertex_alpha))
		mesh.surface_set_uv((vertex + Vector2.ONE) * 0.5)
		mesh.surface_add_vertex(Vector3(vertex.x, vertex.y, z))
	mesh.surface_end()
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	viewport.add_child(instance)

func _view(foreground: ShaderMaterial, vertex_alpha: float) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(64, 64)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(0, 0, 4)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.5
	camera.current = true
	_quad(viewport, _material(OPAQUE_SHADER), 1.0, -0.5)
	if foreground != null: _quad(viewport, foreground, vertex_alpha, 0.0)
	return viewport

func _difference(a: Color, b: Color) -> float:
	return maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("BOSS_SRP_ADDITIVE_RENDER requires a graphical renderer")
		quit(1)
		return
	var cases := []
	for values in [[0.0, 1.0], [1.0, 0.0], [0.25, 0.4], [0.55, 0.7], [1.0, 1.0]]:
		var texture := _texture(values[0])
		var source := {"shader": "AllIn1Vfx/AllIn1VfxSRPBatch", "blend": "alpha", "source_floats": {"_SrcMode": 1, "_DstMode": 1, "_Alpha": 1}, "textures": [{"property": "_MainTex", "texture": TEXTURE_KEY}]}
		var actual: ShaderMaterial = SourceMaterial.create(source, {TEXTURE_KEY: texture})
		var reference := _material(REFERENCE_SHADER)
		reference.set_shader_parameter("input_texture", texture)
		var legacy_source: Dictionary = source.duplicate(true)
		legacy_source.source_floats["_DstMode"] = 0
		var legacy: ShaderMaterial = SourceMaterial.create(legacy_source, {TEXTURE_KEY: texture})
		cases.append({"texture_alpha": values[0], "vertex_alpha": values[1], "actual": _view(actual, values[1]), "reference": _view(reference, values[1]), "legacy": _view(legacy, values[1])})
	var background := _view(null, 1.0)
	for frame in 5: await process_frame
	await RenderingServer.frame_post_draw
	var background_pixel := background.get_texture().get_image().get_pixel(32, 32)
	check(background_pixel.r > 0.05 and background_pixel.g > 0.05 and background_pixel.b > 0.05, "Test background is nonblack in every channel")
	for item in cases:
		var actual: Color = item.actual.get_texture().get_image().get_pixel(32, 32)
		var reference: Color = item.reference.get_texture().get_image().get_pixel(32, 32)
		var legacy: Color = item.legacy.get_texture().get_image().get_pixel(32, 32)
		var error := _difference(actual, reference)
		check(error < 0.025, "One/One reference matches GPU add for texture alpha %.2f and vertex alpha %.2f (error %.4f)" % [item.texture_alpha, item.vertex_alpha, error])
		if is_zero_approx(item.texture_alpha * item.vertex_alpha):
			check(_difference(actual, background_pixel) < 0.025, "Zero texture or vertex alpha leaves the nonblack background unchanged")
		else:
			check(_difference(actual, background_pixel) > 0.01, "Nonzero alpha adds visible source light")
			check(_difference(actual, legacy) > 0.01, "Nonblack background distinguishes additive from legacy alpha blending")
		rows.append({"texture_alpha": item.texture_alpha, "vertex_alpha": item.vertex_alpha, "actual": actual, "reference": reference, "legacy": legacy, "max_rgb_error": error})
		for key in ["actual", "reference", "legacy"]: item[key].free()
	background.free()
	print("BOSS_SRP_ADDITIVE_RENDER ", JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures, "background": background_pixel, "cases": rows, "scope": "Synthetic unlit source_shapes RGBA texture on a nonblack opaque background. Reference approximates APK One/One by adding texture RGB premultiplied by texture and vertex alpha; Godot blend_add receives unpremultiplied RGB and the same combined alpha. Both use Godot's source_color conversion and renderer; this is not an APK image or full shader equivalence test."}))
	quit(0 if failures.is_empty() else 1)
