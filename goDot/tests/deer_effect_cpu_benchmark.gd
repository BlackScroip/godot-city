extends SceneTree

const Descriptors = preload("res://scripts/presentation/effect_descriptors.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _arg(name: String, fallback: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--" + name + "="): return argument.get_slice("=", 1)
	return fallback

func _run() -> void:
	var implementation_path := _arg("implementation", "res://scripts/presentation/authored_effect.gd")
	var implementation = load(implementation_path)
	var frames := maxi(120, int(_arg("frames", "600")))
	var catalog_hash := FileAccess.get_sha256(Descriptors.INDEX_PATH)
	var descriptor_hash := FileAccess.get_sha256("res://assets/combat_presentation/runtime/effects.json")
	var catalog := Descriptors.load_catalog()
	var rows: Array = []
	for low in [false, true]:
		var effects: Array = []
		var names: Array[String] = []
		var emitter_count := 0
		for key in catalog.effects:
			if "jiaolu" not in key: continue
			var effect = implementation.new()
			root.add_child(effect)
			effect.configure(Descriptors.resolve(catalog.effects[key]), low, {})
			if effect.emitters.is_empty() and effect.retained_particles.is_empty():
				effect.free()
				continue
			effects.append(effect)
			names.append(key)
			emitter_count += effect.emitters.size()
		var trace: Array[String] = []
		var duration_usec := 0
		for frame in frames:
			if frame % 120 == 0:
				for effect in effects: effect.restart()
			if frame % 120 == 95:
				for effect in effects: effect.stop()
			var paused := frame % 70 >= 60
			var rate := 0.5 if frame % 40 < 20 else 1.0
			var start := Time.get_ticks_usec()
			for effect in effects: effect.advance(1.0 / 60.0, paused, rate)
			duration_usec += Time.get_ticks_usec() - start
			var state: Array = []
			for effect in effects:
				var particles: Array = []
				for emitter in effect.emitters:
					var clock: Variant = null
					if emitter.node.material_override is ShaderMaterial:
						clock = emitter.node.material_override.get_shader_parameter("clock")
					particles.append([emitter.started, emitter.node.emitting, emitter.node.speed_scale,
						emitter.get("next_burst", null), clock])
				for retained in effect.retained_particles:
					particles.append([retained.node.visible, retained.node.material_override.get_shader_parameter("clock")])
				state.append([effect.age, effect.visible, particles])
			trace.append(JSON.stringify(state))
		rows.append({"low_quality": low, "effect_names": names, "emitters": emitter_count,
			"frames": frames, "update_ms": duration_usec / 1000.0,
			"state_sha256": "\n".join(trace).sha256_text()})
		if effects.is_empty() or emitter_count == 0: failures.append("Missing deer particle fixtures")
		for effect in effects: effect.free()
	var baseline_path := _arg("compare", "")
	if not baseline_path.is_empty():
		var baseline = JSON.parse_string(FileAccess.get_file_as_string(baseline_path))
		if not baseline is Dictionary or baseline.get("rows", []).size() != rows.size():
			failures.append("Invalid baseline")
		else:
			if baseline.get("catalog_sha256", catalog_hash) != catalog_hash or baseline.get("descriptor_sha256", descriptor_hash) != descriptor_hash:
				failures.append("Baseline uses different effect resources")
			for index in rows.size():
				if rows[index].state_sha256 != baseline.rows[index].state_sha256:
					failures.append("Particle scheduling changed in quality mode " + str(rows[index].low_quality))
	var report := {"passed": failures.is_empty(), "failures": failures, "rows": rows,
		"implementation_sha256": FileAccess.get_sha256(implementation_path),
		"catalog_sha256": catalog_hash, "descriptor_sha256": descriptor_hash,
		"scope": "Headless CPU update cost for recovered deer effects; state trace includes pauses, playback speed, stop and pooled restarts. Excludes GPU rendering, device FPS and particle positions."}
	FileAccess.open(_arg("output", "/private/tmp/deer-effect-cpu.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("DEER_EFFECT_CPU ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
