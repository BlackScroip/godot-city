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
			check(effect.emitters.size() <= (8 if low else 18), "%s emitter cap" % name)
			check(effect.particle_count <= (144 if low else 384), "%s particle cap" % name)
			effect.restart()
			effect.advance(0.03, false)
			if render_check:
				await process_frame
				await RenderingServer.frame_post_draw
			for emitter in effect.emitters:
				var particle: CPUParticles3D = emitter.node
				var material: ShaderMaterial = particle.material_override
				if material.get_shader_parameter("use_frame_curve"): sheets += 1
				if material.get_shader_parameter("use_motion_curve"): motion_layers += 1
				if particle.split_scale: split_layers += 1
				check(particle.amount > 0, "%s nonempty visible emitter" % name)
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
