extends SceneTree

const Subject = preload("res://scripts/presentation/chest_smoke_velocity.gd")
const AuthoredEffect = preload("res://scripts/presentation/authored_effect.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func _run() -> void:
	var evidence: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://reports/chest-smoke-velocity-native-20261028.json"))
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/environment_effects/chest_catalog.json"))
	var definition: Dictionary = source.effects["24050602_fx_env_treasureboxcurseopen"]
	var layer: Dictionary = definition.layers.filter(func(item): return item.name == Subject.SOURCE_LAYER)[0]
	var limit := AuthoredEffect.value_curve(layer.modules.ClampVelocityModule.magnitude)
	check(is_equal_approx(Subject.limited_speed(5.0, 1.0, 0.1, 1.0 / 30.0), 4.6), "native 30 Hz damping coefficient")
	check(is_equal_approx(Subject.limited_speed(5.0, 1.0, 0.1, 1.0 / 60.0), 4.7947331922), "native 60 Hz damping coefficient")
	check(Subject.limited_speed(0.5, 1.0, 0.1, 0.5) == 0.5, "limit does not accelerate slower particles")
	check(Subject.limited_speed(5.0, 1.0, 0.0, 0.5) == 5.0, "zero dampen preserves speed")
	check(Subject.limited_speed(5.0, 1.0, 1.0, 0.5) == 1.0, "full dampen clamps speed")
	var max_error := 0.0
	for fixture in evidence.fixtures:
		var curve := Subject.velocity_curve(fixture.initial_speed, fixture.duration, limit, layer.modules.ClampVelocityModule.dampen)
		for sample in fixture.samples:
			max_error = maxf(max_error, absf(curve.sample(sample.time / fixture.duration) - float(sample.speed)))
	check(max_error < 0.00002, "all source equation reference samples match (error %.9f)" % max_error)
	var textures: Dictionary = {}
	for path in definition.textures:
		if ResourceLoader.exists(path): textures[path] = load(path)
	for low_quality in [false, true]:
		var template = AuthoredEffect.new()
		root.add_child(template)
		template.configure(definition, low_quality, textures)
		var smoke: Array = template.emitters.filter(func(emitter): return emitter.node.has_meta(Subject.SOURCE_META))
		check(smoke.size() == 30, "source smoke burst keeps 30 particles")
		var sum := 0
		var names: Dictionary = {}
		for emitter in template.emitters:
			sum += int(emitter.node.amount)
			names[emitter.node.get_parent().get_meta("source_layer")] = true
		check(sum == template.particle_count, "runtime splitting preserves particle budget")
		check(names.size() == 6, "six source render layers survive logical emitter budget")
		check(names.has("24050602_treasureboxcurseopen_floorlgow"), "later floor glow survives smoke splitting")
		var instance = template.instantiate_effect()
		root.add_child(instance)
		instance.restart()
		var split_count := 0
		for emitter in instance.emitters:
			var particle: CPUParticles3D = emitter.node
			if not particle.has_meta(Subject.SOURCE_META): continue
			split_count += 1
			check(particle.amount == 1 and particle.lifetime_randomness == 0.0, "each smoke particle owns its lifetime")
			check(particle.lifetime >= 0.6 and particle.lifetime <= 1.200001, "source lifetime range survives restart")
			check(particle.initial_velocity_min >= 3.0 and particle.initial_velocity_max <= 7.0, "source speed range survives restart")
			check(particle.scale_amount_min == 2.0 and particle.scale_amount_max == 3.0, "source smoke size unchanged")
			check(is_equal_approx(particle.color.a, 0.7803921699523926), "source smoke opacity unchanged")
			var motion := particle.get_param_curve(CPUParticles3D.PARAM_INITIAL_LINEAR_VELOCITY)
			check(motion != null and motion.sample(1.0) < particle.initial_velocity_min, "rendered CPUParticles consumes source limit curve")
		check(split_count == 30, "instanced effect retains all limited smoke particles")
		instance.advance(1.0 / 60.0, false)
		instance.advance(1.0 / 60.0, true)
		check(instance.emitters.all(func(emitter): return is_zero_approx(emitter.node.speed_scale)), "all split particles pause with the effect")
		instance.stop()
		check(instance.emitters.all(func(emitter): return not emitter.node.emitting), "all split particles stop with the effect")
		instance.free()
		template.free()
	var result := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "max_reference_error": max_error}
	print("CHEST_SMOKE_VELOCITY " + JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
