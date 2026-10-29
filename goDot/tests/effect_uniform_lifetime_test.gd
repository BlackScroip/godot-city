extends SceneTree

const Effect = preload("res://scripts/presentation/authored_effect.gd")
const TEXTURE_KEY := "test://uniform-lifetime"
const STEP := 1.0 / 60.0

var checks := 0
var failures: Array[String] = []
var texture: ImageTexture

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _source() -> Dictionary:
	return {"name": "mat_fx_25011001_slash_fog.mat", "shader": "AllIn1Vfx/Particle", "source_floats": {"_ShapeXSpeed": 0.3}, "source_colors": {}, "keywords": [], "blend": "alpha", "texture": TEXTURE_KEY, "textures": [{"property": "_MainTex", "texture": TEXTURE_KEY}]}

func _layer() -> Dictionary:
	return {"name": "lifetime", "duration": 0.3, "renderer": {"enabled": true, "render_mode": 0}, "initial": {"maxNumParticles": 8, "startLifetime": {"scalar": 0.5}, "startSize": {"scalar": 1.8}, "startColor": {"maxColor": {"r": 1.0, "g": 1.0, "b": 1.0, "a": 1.0}}}, "materials": [_source()], "emission": {"rateOverTime": {"scalar": 12.0}}, "modules": {"VelocityModule": {"inWorldSpace": false, "x": {"scalar": 0.4}, "speedModifier": {"scalar": 1.0}}}}

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
	effect.configure({"layers": [layer]}, false, {TEXTURE_KEY: texture})
	effect.restart()
	return {"viewport": viewport, "effect": effect}

func _check_continuous_tail() -> void:
	var actual := _setup_view(_layer())
	var legacy := _setup_view(_layer())
	var emitter: Dictionary = actual.effect.emitters[0]
	check(not emitter.node.one_shot and emitter.uses_clock and emitter.uses_basis and emitter.ground_fade, "Fixture continuously emits animated local-space particles with ground fading")
	for frame in 31:
		actual.effect.advance(STEP, false)
		legacy.effect.advance(STEP, false)
		await process_frame
	check(not emitter.node.emitting and actual.effect.age < float(emitter.uniform_end), "Continuous emission stops before the final particle lifetime ends")
	for entry in [actual, legacy]:
		entry.effect.position.y = 0.25
		entry.effect.rotation.y = 0.75
	var before_age: float = actual.effect.age
	actual.effect.advance(STEP, false)
	legacy.effect.advance(STEP, false)
	var material: ShaderMaterial = emitter.node.material_override
	check(is_equal_approx(float(material.get_shader_parameter("clock")), before_age), "Live trailing particles retain shader clock updates")
	check(material.get_shader_parameter("emitter_basis").is_equal_approx(emitter.node.global_basis), "Live trailing particles retain rotated emitter basis")
	check(is_equal_approx(float(material.get_shader_parameter("ground_level")), actual.effect.global_position.y - 0.08), "Live trailing particles retain moving ground level")
	var legacy_emitter: Dictionary = legacy.effect.emitters[0]
	legacy_emitter.node.material_override.set_shader_parameter("clock", before_age)
	legacy_emitter.node.material_override.set_shader_parameter("emitter_basis", legacy_emitter.node.global_basis)
	legacy_emitter.node.material_override.set_shader_parameter("ground_level", legacy.effect.global_position.y - 0.08)
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
	check(visible_pixels > 30, "Trailing particles remain visible after emission stops")
	check(changed_channels == 0, "Visible trailing particles match the original unconditional uniform updates")
	print("EFFECT_UNIFORM_TAIL ", JSON.stringify({"visible_pixels": visible_pixels, "changed_channels": changed_channels, "age": actual.effect.age, "uniform_end": emitter.uniform_end}))
	actual.viewport.free()
	legacy.viewport.free()

func _check_shared_bursts() -> void:
	var layer := _layer()
	layer.duration = 0.3
	layer.initial.startLifetime.scalar = 0.3
	layer.emission = {"m_Bursts": [{"countCurve": {"scalar": 1.0}, "cycleCount": 3, "repeatInterval": 0.25}]}
	var template := Effect.new()
	root.add_child(template)
	template.configure({"source": "res://26071801_fx_enemy_mojiehua_attack3_duyejidang.prefab", "layers": [layer]}, false, {TEXTURE_KEY: texture})
	var effect = template.instantiate_effect()
	root.add_child(effect)
	effect.restart()
	check(effect.emitters.size() == 3, "The authored burst timeline has three emitters")
	if effect.emitters.size() == 3:
		var leader: Dictionary = effect.emitters[0]
		var material: ShaderMaterial = leader.node.material_override
		check(is_same(material, effect.emitters[1].node.material_override) and is_same(material, effect.emitters[2].node.material_override), "Related bursts share uniforms within one effect instance")
		check(not leader.get("uniform_follower", false) and effect.emitters[1].uniform_follower and effect.emitters[2].uniform_follower, "The earliest burst owns shared uniform updates")
		check(is_equal_approx(float(leader.uniform_end), 0.8), "The shared update covers the last burst's complete particle lifetime")
		for delta in [0.05, 0.2, 0.25, 0.2]: effect.advance(delta, false)
		effect.rotation.y = 0.75
		effect.position.y = 0.25
		effect.advance(0.05, false)
		check(is_equal_approx(float(material.get_shader_parameter("clock")), 0.7), "Shared clock updates during the final burst")
		check(material.get_shader_parameter("emitter_basis").is_equal_approx(leader.node.global_basis), "Shared burst basis follows the effect")
		check(is_equal_approx(float(material.get_shader_parameter("ground_level")), effect.global_position.y - 0.08), "Shared burst ground level follows the effect")
		effect.advance(0.1, false)
		check(is_equal_approx(float(material.get_shader_parameter("clock")), 0.75), "Shared clock updates before the final burst expires")
		effect.advance(0.1, false)
		check(is_equal_approx(float(material.get_shader_parameter("clock")), 0.75), "Shared clock stops updating after all bursts expire")
	effect.free()
	template.free()

func _run() -> void:
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			image.set_pixel(x, y, Color(float(x) / 31.0, float(y) / 31.0, 0.3 + 0.6 * float((x + y) % 2), 1.0))
	texture = ImageTexture.create_from_image(image)
	await _check_continuous_tail()
	_check_shared_bursts()
	print("EFFECT_UNIFORM_LIFETIME ", JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
