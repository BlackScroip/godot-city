extends RefCounted

const CACHE_CAPACITY := 2048
static var _cache: Dictionary = {}
static var _cache_keys: Array[String] = []
static var _cache_cursor := 0

# Retain source units: StopFrameWeight is not a duration in seconds.
static func normalize(definition: Dictionary) -> Dictionary:
	var value: Variant = definition.get("raw", definition)
	if value is String: return read(definition).duplicate(true)
	return _normalize(value if value is Dictionary else {})

# Internal readers share immutable payloads. Dictionary inputs may change between calls.
static func read(definition: Dictionary) -> Dictionary:
	var value: Variant = definition.get("raw", definition)
	if value is String:
		var entry := _cached(value)
		if not entry.has("feedback"):
			entry["feedback"] = _normalize(entry.raw)
			_freeze(entry.feedback)
		return entry.feedback
	var result := _normalize(value if value is Dictionary else {})
	_freeze(result)
	return result

static func raw(definition: Dictionary) -> Dictionary:
	var value: Variant = definition.get("raw", definition)
	if value is String: return _cached(value).raw
	var result: Dictionary = value.duplicate(true) if value is Dictionary else {}
	_freeze(result)
	return result

static func _cached(encoded: String) -> Dictionary:
	if _cache.has(encoded): return _cache[encoded]
	var parsed: Variant = JSON.parse_string(encoded)
	var entry := {"raw": parsed if parsed is Dictionary else {}}
	_freeze(entry.raw)
	if _cache_keys.size() < CACHE_CAPACITY:
		_cache_keys.append(encoded)
	else:
		_cache.erase(_cache_keys[_cache_cursor])
		_cache_keys[_cache_cursor] = encoded
		_cache_cursor = (_cache_cursor + 1) % CACHE_CAPACITY
	_cache[encoded] = entry
	return entry

static func _freeze(value: Variant) -> void:
	if value is Dictionary:
		for child in value.values(): _freeze(child)
		value.make_read_only()
	elif value is Array:
		for child in value: _freeze(child)
		value.make_read_only()

static func _normalize(raw: Dictionary) -> Dictionary:
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
