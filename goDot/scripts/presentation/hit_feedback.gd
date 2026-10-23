extends RefCounted

# Retain source units: StopFrameWeight is not a duration in seconds.
static func normalize(definition: Dictionary) -> Dictionary:
	var raw: Variant = definition.get("raw", definition)
	if raw is String: raw = JSON.parse_string(raw)
	if not raw is Dictionary: raw = {}
	var result := {"camera_shakes": [], "hit_stops": [], "hit_actions": [], "material_flash": false, "material_flashes": [], "hit_sounds": [], "hit_effects": [], "unknown": []}
	var entries: Variant = raw.get("FeedbackList", [])
	if not entries is Array: return result
	for entry in entries:
		if not entry is Dictionary: continue
		var original: Dictionary = entry.duplicate(true)
		match str(entry.get("FeedbackType", "")):
			"EHT_CameraShake":
				result.camera_shakes.append({"duration": float(entry.get("Duration", 0)), "intensity": float(entry.get("ShakeIntensity", 0)), "times": int(entry.get("ShakeTimes", 0)), "is_delay": bool(entry.get("IsDelay", false)), "delay": float(entry.get("DelayTime", 0)), "disable_x": bool(entry.get("DisableX", false)), "disable_y": bool(entry.get("DisableY", false)), "raw": original})
			"EHT_HitStopFrame":
				result.hit_stops.append({"weight": float(entry.get("StopFrameWeight", 0)), "self_affected_ratio": float(entry.get("SelfAffectedRatio", 1)), "raw": original})
			"EHT_HitAction":
				result.hit_actions.append({"push_power": float(entry.get("PushPower", 0)), "push_modifier": str(entry.get("PushPowerModifyPropertyName", "")), "upper_power": float(entry.get("UpperPower", 0)), "acc_tenacity": float(entry.get("AccTenacity", 0)), "from_attacker": bool(entry.get("AttackDirIsFromAttackerOrHitPoint", false)), "attacker_forward": bool(entry.get("AttackDirIsAttackerForwardOrHitPointDir", false)), "push_mode": str(entry.get("PushMode", "")), "model_shake": bool(entry.get("IsApplyModelShakeEffect", false)), "raw": original})
			"EHT_HitModifyMaterial":
				result.material_flash = true
				result.material_flashes.append(original)
			"EHT_HitSound": result.hit_sounds.append(original)
			"EHT_HitEffect": result.hit_effects.append(original)
			_: result.unknown.append(original)
	return result
