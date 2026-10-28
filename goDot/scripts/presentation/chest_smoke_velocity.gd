extends RefCounted

const SOURCE_LAYER := "24050602_treasureboxcurseopen_smoke"
const SOURCE_META := "chest_smoke_velocity"
const SAMPLE_HZ := 60.0

static func handles(layer: Dictionary) -> bool:
	if str(layer.get("name", "")) != SOURCE_LAYER: return false
	var module: Dictionary = layer.get("modules", {}).get("ClampVelocityModule", {})
	return bool(module.get("enabled", false)) and not bool(module.get("separateAxis", false)) and is_zero_approx(float(module.get("drag", {}).get("scalar", 0)))

static func limited_speed(speed: float, limit: float, dampen: float, delta: float) -> float:
	if speed <= limit or dampen <= 0.0: return speed
	# APK libunity.so VA 0x1044548-0x10445c4 and 0x1044b10-0x1044b30.
	return lerpf(speed, limit, 1.0 - pow(1.0 - clampf(dampen, 0.0, 1.0), absf(delta) * 30.0))

static func velocity_curve(speed: float, duration: float, limit: Curve, dampen: float) -> Curve:
	var result := Curve.new()
	result.min_value = 0.0
	result.max_value = maxf(speed, 1.0)
	result.add_point(Vector2(0.0, speed), 0.0, 0.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	var elapsed := 0.0
	for index in range(1, ceili(duration * SAMPLE_HZ) + 1):
		var next := minf(float(index) / SAMPLE_HZ, duration)
		speed = limited_speed(speed, maxf(0.0, limit.sample(next / duration)), dampen, next - elapsed)
		result.add_point(Vector2(next / duration, speed), 0.0, 0.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
		elapsed = next
	return result

static func split_burst(particle: CPUParticles3D, layer: Dictionary, limit: Curve) -> Array[CPUParticles3D]:
	if not handles(layer): return [particle]
	var initial: Dictionary = layer.initial
	var module: Dictionary = layer.modules.ClampVelocityModule
	var settings := {
		"speed": Vector2(float(initial.startSpeed.minScalar), float(initial.startSpeed.scalar)),
		"lifetime": Vector2(float(initial.startLifetime.minScalar), float(initial.startLifetime.scalar)),
		"limit": limit,
		"dampen": float(module.dampen)
	}
	var result: Array[CPUParticles3D] = []
	var count := particle.amount
	for index in count:
		var instance: CPUParticles3D = particle if index == 0 else particle.duplicate(0)
		if index > 0: particle.get_parent().add_child(instance)
		instance.amount = 1
		instance.lifetime_randomness = 0.0
		instance.fixed_fps = int(SAMPLE_HZ)
		instance.set_meta(SOURCE_META, settings)
		restart_particle(instance)
		result.append(instance)
	return result

static func restart_particle(particle: CPUParticles3D) -> void:
	if not particle.has_meta(SOURCE_META): return
	var settings: Dictionary = particle.get_meta(SOURCE_META)
	var speed := randf_range(settings.speed.x, settings.speed.y)
	particle.lifetime = randf_range(settings.lifetime.x, settings.lifetime.y)
	particle.initial_velocity_min = speed
	particle.initial_velocity_max = speed
	# One particle per native emitter lets the curve use its own sampled lifetime.
	particle.set_param_curve(CPUParticles3D.PARAM_INITIAL_LINEAR_VELOCITY, velocity_curve(speed, particle.lifetime, settings.limit, settings.dampen))
