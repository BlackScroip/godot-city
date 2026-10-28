extends RefCounted

const Original = preload("res://scripts/presentation/hit_feedback.gd")

static func collect(hit: Dictionary, source: RefCounted = null) -> Dictionary:
	var profile: Dictionary = hit.get("profile", {})
	var feedback: Dictionary = profile.get("source_feedback", {})
	if feedback.is_empty(): feedback = Original.read(hit.get("definition", {}))
	var result := {"effects": [], "sounds": [], "camera_shakes": feedback.camera_shakes, "hit_stops": feedback.hit_stops, "hit_actions": feedback.hit_actions, "material_flashes": feedback.material_flashes}
	var owner: Variant = source if source != null else hit.get("source")
	var summon_id := str(hit.get("summon_id", ""))
	if owner is RefCounted and not summon_id.is_empty():
		var summons: Dictionary = owner.get("_summon_index")
		var summon: Dictionary = summons.get(summon_id, {}).get("raw_data", {})
		for field in ["HitEffect", "HitEffect_UnitCenter"]:
			var name := str(summon.get(field, ""))
			if not name.is_empty(): result.effects.append({"name": name, "scale": Vector3.ONE, "rotation": Vector3.ZERO, "unit_center": field == "HitEffect_UnitCenter", "raw": {field: name}})
		var sound := str(summon.get("HitSound", ""))
		if not sound.is_empty(): result.sounds.append(sound)
	for effect in feedback.hit_effects:
		var name := str(effect.get("Effect", ""))
		if name.is_empty(): continue
		var scale := _vector(effect.get("EffectScale", {}))
		if scale.is_zero_approx(): scale = Vector3.ONE
		result.effects.append({"name": name, "scale": scale, "rotation": _vector(effect.get("EffectOffsetRotate", {})), "unit_center": false, "raw": effect.duplicate(true)})
	for sound in feedback.hit_sounds:
		var name := str(sound.get("HitSoundDef", {}).get("SoundName", ""))
		if not name.is_empty(): result.sounds.append(name)
	return result

static func present(presentation: Node, source: Node3D, target: Node3D, hit: Dictionary, point: Vector3) -> void:
	var plan := collect(hit, source.get("combat"))
	if bool(hit.get("resolved_accepted", true)) and target.has_method("start_source_model_shake"):
		for action in plan.hit_actions:
			if bool(action.get("model_shake", false)):
				target.start_source_model_shake()
				break
	for effect in plan.effects:
		var position: Vector3 = target.impact_anchor(target.position + Vector3.UP * 0.65) if effect.unit_center else point
		var before: int = presentation.spawned
		presentation._summon_style(source, effect.name, position, effect.scale, true)
		if presentation.spawned > before:
			presentation.active.back().root.rotation += effect.rotation * PI / 180.0
	for name in plan.sounds:
		presentation.play_sound(name, point, source, -1, 1.0, 1.0, false)

static func _vector(value: Dictionary) -> Vector3:
	return Vector3(float(value.get("x", 0)), float(value.get("y", 0)), float(value.get("z", 0)))
