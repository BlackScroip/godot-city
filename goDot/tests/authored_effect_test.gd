extends SceneTree

const EFFECT = preload("res://scripts/presentation/authored_effect.gd")
var checks := 0
var failures: Array[String] = []

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var render_check = "--render-check" in OS.get_cmdline_user_args()
	var all_effects = "--all-effects" in OS.get_cmdline_user_args()
	if render_check:
		root.size = Vector2i(960, 540)
		var camera = Camera3D.new()
		root.add_child(camera)
		camera.position = Vector3(0, 7, 9)
		camera.look_at(Vector3(0, 0, 1))
		camera.current = true
	var scaled = EFFECT.curve({"scalar": 3.0, "maxCurve": {"m_Curve": [{"time": 0, "value": 0.5}, {"time": 1, "value": 1.0}]}})
	check(is_equal_approx(scaled.sample(1), 3.0), "Source curve multipliers retain authored growth")
	check(EFFECT.scalar_range({"minMaxState": 3, "scalar": 1.5, "minScalar": 2.5}) == Vector2(1.5, 2.5), "Reversed Unity random endpoints preserve both altar lifetimes")
	var custom = EFFECT.custom_stream({"vector1_0": {"scalar": 1.0, "maxCurve": {"m_Curve": [{"time": 0, "value": 1.0, "outSlope": -2.0}, {"time": 1, "value": -1.0, "inSlope": -2.0}]}}}, 1).get_image()
	check(is_equal_approx(custom.get_pixel(0, 0).r, 1.0) and is_equal_approx(custom.get_pixel(custom.get_width() - 1, 0).r, -1.0), "Portal custom stream retains signed lifetime erosion values")
	var motion = EFFECT._integrated_motion({"x": {"scalar": 10.0}, "speedModifier": {"scalar": 0.5}}, 0.4)
	check(absf(motion.curve_x.sample(1) - 2.0) < 0.001, "Velocity module displacement uses lifetime and speed multiplier")
	check(EFFECT._uses_reconstructed_ribbon({"name": "axe_slash", "renderer": {"render_mode": 4}}, {"alpha_from_luminance": true, "blend": "alpha"}), "Broad mesh slash receives translucent reconstruction")
	check(not EFFECT._uses_reconstructed_ribbon({"name": "axe_slash", "renderer": {"render_mode": 0}}, {"alpha_from_luminance": true, "blend": "alpha"}), "Billboard contact flash keeps source opacity")
	check(not EFFECT._uses_reconstructed_ribbon({"name": "axe_slash", "renderer": {"render_mode": 4}}, {"alpha_from_luminance": true, "blend": "add"}), "Source additive slash keeps source blending")
	check(EFFECT._uses_reconstructed_water_shell({"renderer": {"render_mode": 4}}, {"source": "original/mat_fx_23102601_bomb.mat", "blend": "alpha"}), "Water projectile shell remains translucent at contact")
	check(EFFECT._uses_reconstructed_water_shell({"renderer": {"render_mode": 4}}, {"source": "original/mat_fx_23102601_bomblight.mat", "blend": "alpha"}), "Water projectile highlight receives the same shell feather")
	check(not EFFECT._uses_reconstructed_water_shell({"renderer": {"render_mode": 4}}, {"source": "original/mat_fx_smoke.mat", "blend": "alpha"}), "Unrelated mesh materials keep source rendering")
	check(EFFECT._uses_reconstructed_water_splash({"source": "original/mat_fx_23110201_hit_prick.mat", "blend": "alpha"}), "Overlapping water contact spikes retain target visibility")
	check(not EFFECT._uses_reconstructed_water_splash({"source": "original/mat_fx_smoke.mat", "blend": "alpha"}), "Water contact correction excludes smoke")
	_check_shader_dependencies()
	_check_burst_lifecycle()
	_check_delayed_emitter_updates()
	_check_shared_burst_uniforms()
	_check_continuous_particle_tail()
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/combat_presentation/catalog.json"))
	var textures: Dictionary = {}
	for path in catalog.get("texture_sources", {}):
		var full_path = "res://assets/combat_presentation/" + str(path)
		if ResourceLoader.exists(full_path): textures[full_path] = load(full_path)
	var inspected := 0
	var sheets := 0
	var motion_layers := 0
	var split_layers := 0
	for name in catalog.get("effects", {}):
		if not all_effects and not any_word(str(name), ["sword", "axe", "water", "bow", "wand", "explosion", "exp_"]): continue
		var definition: Dictionary = catalog.effects[name]
		if definition.get("layers", []).is_empty(): continue
		for low in [false, true]:
			var effect = EFFECT.new()
			root.add_child(effect)
			effect.configure(definition, low, textures)
			check(effect.emitters.size() <= EFFECT.emitter_budget(definition, low), "%s emitter cap" % name)
			check(effect.particle_count <= (144 if low else 384), "%s particle cap" % name)
			effect.restart()
			effect.advance(0.03, false)
			if render_check:
				await process_frame
				await RenderingServer.frame_post_draw
			for emitter in effect.emitters:
				var particle: CPUParticles3D = emitter.node
				var material: ShaderMaterial = particle.material_override
				check(emitter.uses_clock == _material_uses_clock(material), "%s clock dependency matches configured shader uniforms" % name)
				check(emitter.uses_basis == (material.get_shader_parameter("stretched_billboard") == true or (material.get_shader_parameter("use_motion_curve") == true and material.get_shader_parameter("world_motion") != true)), "%s basis dependency matches configured shader uniforms" % name)
				if material.get_shader_parameter("use_frame_curve"): sheets += 1
				if material.get_shader_parameter("use_motion_curve"): motion_layers += 1
				if particle.split_scale: split_layers += 1
				check(particle.amount > 0, "%s nonempty visible emitter" % name)
			for retained in effect.retained_particles:
				check(retained.uses_clock == _material_uses_clock(retained.node.material_override), "%s retained particle clock dependency matches configured shader uniforms" % name)
			effect.advance(0.03, true)
			for emitter in effect.emitters:
				check(is_zero_approx(emitter.node.speed_scale), "%s local feedback pause" % name)
			effect.stop()
			effect.free()
		inspected += 1
		if not all_effects and inspected >= 90: break
	check(sheets > 0, "Sample includes authored flipbook animation")
	check(motion_layers > 0, "Sample includes source velocity modules")
	check(split_layers > 0, "Sample includes anisotropic particle size")
	var report = {"checks": checks, "failures": failures, "effects": inspected, "sheet_layers": sheets, "motion_layers": motion_layers, "split_scale_layers": split_layers, "render_check": render_check, "all_effects": all_effects}
	print(JSON.stringify(report))
	var file = FileAccess.open("res://reports/authored-effect-tests.json", FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "\t"))
	quit(0 if failures.is_empty() else 1)

func any_word(value: String, words: Array) -> bool:
	for word in words:
		if word in value: return true
	return false

func _material_uses_clock(material: ShaderMaterial) -> bool:
	if material.get_shader_parameter("source_shapes") != true: return false
	for index in range(1, 4):
		if index > 1 and material.get_shader_parameter("use_shape%d" % index) != true: continue
		var prefix := "shape%d" % index
		if material.get_shader_parameter(prefix + "_scroll") != Vector2.ZERO: return true
		var rotation: Vector2 = material.get_shader_parameter(prefix + "_rotation")
		if rotation.y != 0: return true
		if float(material.get_shader_parameter(prefix + "_distort_amount")) != 0 and material.get_shader_parameter(prefix + "_distort_scroll") != Vector2.ZERO: return true
	if float(material.get_shader_parameter("source_distort_amount")) != 0 and material.get_shader_parameter("source_distort_scroll") != Vector2.ZERO: return true
	return material.get_shader_parameter("use_source_fade") == true and material.get_shader_parameter("source_fade_scroll") != Vector2.ZERO

func _check_shader_dependencies() -> void:
	var source := {"shader": "AllIn1Vfx/Particle", "source_floats": {}, "keywords": []}
	check(not EFFECT._uses_shader_clock(source), "Static source material does not need a changing clock")
	source.source_floats["_ShapeXSpeed"] = 0.5
	check(EFFECT._uses_shader_clock(source), "Primary source scroll depends on the clock")
	source.source_floats.clear()
	source.source_floats["_Shape2XSpeed"] = 0.5
	check(not EFFECT._uses_shader_clock(source), "Disabled secondary shapes do not use the clock")
	source.keywords = ["SHAPE2_ON"]
	check(EFFECT._uses_shader_clock(source), "Enabled secondary shapes retain clock animation")
	source.source_floats = {"_ShapeRotationSpeed": 2.0}
	source.keywords = ["SHAPE1ROTATE_ON"]
	check(EFFECT._uses_shader_clock(source), "Source shape rotation retains clock animation")
	source.source_floats = {"_ShapeDistortAmount": 1.0, "_ShapeDistortYSpeed": 0.5}
	source.keywords = ["SHAPE1DISTORT_ON"]
	check(EFFECT._uses_shader_clock(source), "Source shape distortion retains clock animation")
	source.source_floats = {"_DistortAmount": 1.0, "_DistortTexXSpeed": 0.5}
	source.keywords = ["DISTORT_ON"]
	check(EFFECT._uses_shader_clock(source), "Global distortion retains clock animation")
	source.source_floats = {"_FadeScrollYSpeed": 0.5}
	source.keywords = ["FADE_ON"]
	check(EFFECT._uses_shader_clock(source), "Fade scrolling retains clock animation")

	var layer := {"name": "uniforms", "duration": 1.0, "initial": {"startLifetime": {"scalar": 1.0}}, "materials": [{"shader": "AllIn1Vfx/Particle", "source_floats": {"_ShapeXSpeed": 1.0}, "keywords": [], "blend": "alpha"}], "emission": {"m_Bursts": [{"countCurve": {"scalar": 1.0}}]}, "modules": {"VelocityModule": {"inWorldSpace": false, "x": {"scalar": 1.0}}}}
	var effect := EFFECT.new()
	root.add_child(effect)
	effect.configure({"layers": [layer]}, false, {})
	effect.restart()
	effect.rotation.y = 0.5
	effect.advance(0.1, false)
	effect.advance(0.1, false)
	var emitter: Dictionary = effect.emitters[0]
	var material: ShaderMaterial = emitter.node.material_override
	check(emitter.uses_clock and emitter.uses_basis, "Animated local motion updates both clock and emitter basis")
	check(is_equal_approx(float(material.get_shader_parameter("clock")), 0.1), "Animated shader clock follows effect age")
	check(material.get_shader_parameter("emitter_basis").is_equal_approx(emitter.node.global_basis), "Local particle motion follows transformed emitter basis")
	effect.advance(0.5, true)
	check(is_equal_approx(float(material.get_shader_parameter("clock")), 0.1), "Paused effect does not advance its animated shader clock")
	var clone = effect.instantiate_effect()
	root.add_child(clone)
	check(clone.emitters[0].uses_clock and clone.emitters[0].uses_basis, "Pooled effect clones retain shader dependency flags")
	clone.free()
	effect.free()

func _check_burst_lifecycle() -> void:
	var layer := {
		"duration": 0.3, "looping": true, "simulation_speed": 2.0,
		"start_delay": {"scalar": 0.1}, "initial": {"startLifetime": {"scalar": 0.05}},
		"materials": [{"blend": "alpha"}],
		"emission": {"rateOverTime": {"scalar": 0.0}, "m_Bursts": [
			{"time": 0.0, "countCurve": {"scalar": 1.0}, "cycleCount": 2, "repeatInterval": 0.1}
		]}
	}
	var effect := EFFECT.new()
	root.add_child(effect)
	effect.configure({"layers": [layer]}, false, {})
	check(effect.emitters.size() == 2, "Each authored burst retains its own schedule")
	effect.restart()
	effect.advance(0.04, false)
	check(not effect.emitters[0].started, "Looping bursts respect scaled start delay")
	effect.advance(0.02, false)
	check(effect.emitters[0].started and not effect.emitters[1].started, "Looping bursts retain scaled cycle offsets")
	effect.advance(0.05, false)
	check(effect.emitters[1].started, "Later burst starts at its own offset")
	for emitter in effect.emitters: emitter.node.emitting = false
	effect.advance(0.5, true)
	check(is_equal_approx(effect.age, 0.11) and not effect.emitters[0].node.emitting, "Pause freezes looping burst schedule")
	effect.advance(0.1, false)
	check(effect.emitters[0].node.emitting and not effect.emitters[1].node.emitting, "Only the due burst repeats at source duration divided by simulation speed")
	effect.advance(0.05, false)
	check(effect.emitters[1].node.emitting, "Later bursts repeat with their original offset")
	effect.advance(1.0, false)
	for emitter in effect.emitters:
		check(float(emitter.next_burst) > effect.age, "Long steps skip elapsed burst cycles without a catch-up backlog")
	effect.restart()
	effect.advance(0.06, false)
	check(is_equal_approx(effect.emitters[0].next_burst, 0.2), "Restart resets looping burst schedule")
	effect.free()
	layer.looping = false
	effect = EFFECT.new()
	root.add_child(effect)
	effect.configure({"layers": [layer]}, false, {})
	effect.restart()
	effect.advance(0.11, false)
	effect.advance(0.5, false)
	for emitter in effect.emitters:
		check(not emitter.loop and not emitter.has("next_burst") and not emitter.node.emitting, "One-shot combat bursts expire without scheduling another cycle")
	effect.advance(1.0, false)
	for emitter in effect.emitters:
		check(not emitter.node.emitting, "Expired one-shot combat bursts stay stopped")
	effect.free()

func _check_delayed_emitter_updates() -> void:
	var layer := {"name": "delayed", "duration": 1.0, "start_delay": {"scalar": 1.0}, "initial": {"startLifetime": {"scalar": 0.5}}, "materials": [{"shader": "AllIn1Vfx/Particle", "source_floats": {"_ShapeXSpeed": 1.0}, "keywords": [], "blend": "alpha"}], "emission": {"m_Bursts": [{"countCurve": {"scalar": 1.0}}]}, "modules": {"VelocityModule": {"inWorldSpace": false, "x": {"scalar": 1.0}}}}
	var effect := EFFECT.new()
	root.add_child(effect)
	effect.configure({"layers": [layer]}, false, {})
	effect.restart()
	var emitter: Dictionary = effect.emitters[0]
	effect.advance(0.4, false)
	check(not emitter.started and not emitter.has("last_basis"), "Delayed particles skip shader updates before their first burst")
	effect.advance(0.6, true)
	check(not emitter.started and is_zero_approx(emitter.node.speed_scale), "Delayed particles still pause while waiting")
	effect.rotation.y = 0.5
	effect.advance(0.61, false)
	check(emitter.started and is_equal_approx(emitter.node.speed_scale, 1.0), "Delayed particles resume and start at their original time")
	check(emitter.last_basis.is_equal_approx(emitter.node.global_basis), "Delayed particles synchronize their latest transform before emission")
	check(is_equal_approx(float(emitter.node.material_override.get_shader_parameter("clock")), 0.4), "Delayed particles synchronize the animated clock before emission")
	effect.advance(2.0, false)
	var last_basis: Basis = emitter.last_basis
	effect.rotation.y = 0.8
	effect.advance(0.1, false)
	check(emitter.last_basis.is_equal_approx(last_basis), "Expired one-shot particles stop updating shader transforms")
	effect.free()

func _check_shared_burst_uniforms() -> void:
	var layer := {"name": "26091901_fall_particle", "duration": 1.0, "initial": {"startLifetime": {"scalar": 1.0}}, "materials": [{"shader": "AllIn1Vfx/Particle", "source_floats": {"_ShapeXSpeed": 1.0}, "keywords": [], "blend": "alpha"}], "emission": {"m_Bursts": [{"countCurve": {"scalar": 1.0}, "cycleCount": 3, "repeatInterval": 0.5}]}, "modules": {"VelocityModule": {"inWorldSpace": false, "x": {"scalar": 1.0}}}}
	var source := "26091901_fx_enemy_dilong_roartostone_fall.prefab"
	var effect := EFFECT.new()
	root.add_child(effect)
	effect.configure({"source": source, "layers": [layer]}, false, {})
	var clone := effect.instantiate_effect()
	root.add_child(clone)
	check(effect.emitters.size() == 3 and clone.emitters.size() == 3, "Overlapping source bursts retain separate particle emitters")
	var material: ShaderMaterial = effect.emitters[0].node.material_override
	var clone_material: ShaderMaterial = clone.emitters[0].node.material_override
	check(material == effect.emitters[1].node.material_override and clone_material == clone.emitters[1].node.material_override, "Related bursts share one mutable material within an effect instance")
	check(material != clone_material, "Separate pooled effects retain independent material state")
	effect.restart()
	clone.restart()
	var clone_clock: Variant = clone_material.get_shader_parameter("clock")
	effect.advance(1.1, false)
	effect.rotation.y = 0.5
	effect.advance(0.1, false)
	check(material.get_shader_parameter("emitter_basis").is_equal_approx(effect.emitters[1].node.global_basis), "Shared basis keeps updating after the first burst expires")
	check(is_equal_approx(float(material.get_shader_parameter("clock")), 1.1), "Shared clock keeps updating while later bursts are alive")
	check(clone_material.get_shader_parameter("clock") == clone_clock, "Advancing an effect does not change its clone's shared uniforms")
	clone.free()
	effect.free()

func _check_continuous_particle_tail() -> void:
	var layer := {"name": "continuous", "duration": 0.5, "initial": {"startLifetime": {"scalar": 1.0}}, "materials": [{"shader": "AllIn1Vfx/Particle", "source_floats": {"_ShapeXSpeed": 1.0}, "keywords": [], "blend": "alpha"}], "emission": {"rateOverTime": {"scalar": 5.0}}, "modules": {"VelocityModule": {"inWorldSpace": false, "x": {"scalar": 1.0}}}}
	var effect := EFFECT.new()
	root.add_child(effect)
	effect.configure({"layers": [layer]}, false, {})
	effect.restart()
	var emitter: Dictionary = effect.emitters[0]
	effect.advance(1.1, false)
	check(not emitter.node.emitting, "Continuous effect ends emission at its duration")
	effect.rotation.y = 0.5
	effect.advance(0.1, false)
	check(emitter.last_basis.is_equal_approx(emitter.node.global_basis), "Continuous effect updates still-alive particles after emission stops")
	check(is_equal_approx(float(emitter.node.material_override.get_shader_parameter("clock")), 1.1), "Continuous effect animates shader throughout its particle tail")
	effect.advance(1.0, false)
	var last_basis: Basis = emitter.last_basis
	effect.rotation.y = 0.8
	effect.advance(0.1, false)
	check(emitter.last_basis.is_equal_approx(last_basis), "Continuous effect stops shader updates after the particle tail ends")
	effect.free()
