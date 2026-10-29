extends SceneTree

const Effect = preload("res://scripts/presentation/authored_effect.gd")
const TEXTURE_KEY := "test://uniform-pattern"

var checks := 0
var failures: Array[String] = []
var texture: ImageTexture

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _setup_view(layer: Dictionary) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(192, 192)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(0, 0, 4)
	camera.current = true
	var effect = Effect.new()
	viewport.add_child(effect)
	effect.rotation.y = 0.45
	effect.configure({"layers": [layer]}, false, {TEXTURE_KEY: texture})
	effect.restart()
	return {"viewport": viewport, "effect": effect}

func _layer(kind: String) -> Dictionary:
	var source := {"shader": "AllIn1Vfx/Particle", "source_floats": {}, "source_colors": {}, "keywords": [], "blend": "alpha", "texture": TEXTURE_KEY, "textures": [{"property": "_MainTex", "texture": TEXTURE_KEY}]}
	if kind == "animated":
		source.source_floats = {"_ShapeXSpeed": 0.3, "_ShapeRotationSpeed": 0.5}
		source.keywords = ["SHAPE1ROTATE_ON"]
	var layer := {"name": kind, "duration": 3.0, "renderer": {"enabled": true, "render_mode": 0}, "initial": {"maxNumParticles": 1, "startLifetime": {"scalar": 3.0}, "startSize": {"scalar": 1.8}, "startColor": {"maxColor": {"r": 1.0, "g": 1.0, "b": 1.0, "a": 1.0}}}, "materials": [source], "emission": {"m_Bursts": [{"countCurve": {"scalar": 1.0}}]}}
	if kind in ["static", "animated"]:
		layer["ring_buffer_mode"] = 1
	elif kind == "local_motion":
		layer["modules"] = {"VelocityModule": {"inWorldSpace": false, "x": {"scalar": 0.4}, "speedModifier": {"scalar": 1.0}}}
	elif kind == "world_motion":
		layer["modules"] = {"VelocityModule": {"inWorldSpace": true, "x": {"scalar": 0.4}, "speedModifier": {"scalar": 1.0}}}
	return layer

func _compare(kind: String) -> void:
	var actual := _setup_view(_layer(kind))
	var legacy := _setup_view(_layer(kind))
	for entry in [actual, legacy]:
		entry.effect.advance(0.2, false)
		entry.effect.advance(0.2, false)
	# The previous path wrote these uniforms unconditionally on every update.
	for emitter in legacy.effect.emitters:
		var material: ShaderMaterial = emitter.node.material_override
		material.set_shader_parameter("clock", 0.2)
		material.set_shader_parameter("emitter_basis", emitter.node.global_basis)
	for retained in legacy.effect.retained_particles:
		retained.node.material_override.set_shader_parameter("clock", legacy.effect.age)
	for frame in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var first: Image = actual.viewport.get_texture().get_image()
	var second: Image = legacy.viewport.get_texture().get_image()
	var a := first.get_data()
	var b := second.get_data()
	var visible_pixels := 0
	var changed_channels := 0
	for index in a.size():
		if index % 4 == 3 and a[index] > 8: visible_pixels += 1
		if absi(int(a[index]) - int(b[index])) > 2: changed_channels += 1
	check(visible_pixels > 30, "%s renders a visible test effect" % kind)
	check(changed_channels == 0, "%s matches unconditional uniform updates (%d differing channels)" % [kind, changed_channels])
	print("EFFECT_UNIFORM_RENDER_CASE ", JSON.stringify({"case": kind, "visible_pixels": visible_pixels, "changed_channels": changed_channels}))
	actual.viewport.free()
	legacy.viewport.free()

func _run() -> void:
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			image.set_pixel(x, y, Color(float(x) / 31.0, float(y) / 31.0, 0.3 + 0.6 * float((x + y) % 2), 1.0))
	texture = ImageTexture.create_from_image(image)
	for kind in ["static", "animated", "local_motion", "world_motion"]:
		await _compare(kind)
	print("EFFECT_UNIFORM_RENDER ", JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
