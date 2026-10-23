extends RefCounted

const FEEL = preload("res://assets/feel_settings.tres")
const Original = preload("res://scripts/presentation/hit_feedback.gd")

static func raw(hit: Dictionary) -> Dictionary:
	var value: Variant = hit.get("definition", {}).get("raw", {})
	if value is String: value = JSON.parse_string(value)
	return value if value is Dictionary else {}

static func ranged(hit: Dictionary) -> bool:
	if hit.has("ranged"): return bool(hit.ranged)
	if not str(hit.get("summon_id", "")).is_empty(): return true
	var definition = raw(hit)
	if str(definition.get("EmitProperty", {}).get("PosType", "")) == "EEPT_TargetPos": return true
	var origin = hit.get("origin", {})
	if origin is Dictionary and str(origin.get("OriginType", "")) == "targetPosAndSelfDir": return true
	var motion = str(definition.get("MotionAnimatorType", ""))
	return bool(hit.get("projectile", false)) or (not motion.is_empty() and motion not in ["EMAT_FollowOwner", "EMAT_RotateOwner", "EMAT_Fixed", "EMAT_None"])

static func resolve(hit: Dictionary, source: RefCounted = null) -> Dictionary:
	var action = str(hit.get("action", ""))
	var category = str(hit.get("impact_category", "light"))
	if int(hit.get("slot", 0)) == 4: category = "heavy"
	var original = Original.normalize(hit.get("definition", {}))
	for stop in original.hit_stops:
		if float(stop.weight) >= 0.25: category = "heavy"
	var override: Dictionary = FEEL.action_overrides.get(action, {}).duplicate()
	override.merge(FEEL.summon_overrides.get(str(hit.get("summon_id", "")), {}), true)
	category = str(override.get("category", category))
	if bool(hit.get("continuous", false)): category = "continuous"
	var finisher = source != null and not source.fighter.is_empty() and source.fighter.get("combo", []).size() > 0 and action == str(source.fighter.combo.back())
	var upgraded = category == "light" and (finisher or bool(hit.get("resolved_critical", false)))
	if upgraded: category = "heavy"
	if float(hit.get("resolved_damage", 0)) <= 0 and float(hit.get("resolved_absorbed", 0)) > 0: category = "shield"
	var profile: Dictionary = FEEL.impact_profiles.get(category, FEEL.impact_profiles.light).duplicate()
	profile.merge(override, true)
	profile["category"] = category
	profile["ranged"] = ranged(hit)
	profile["finisher"] = finisher
	profile["critical"] = bool(hit.get("resolved_critical", false))
	if profile.critical and category in ["heavy", "explosion"] and not upgraded:
		profile["stop"] = float(profile.stop) * 1.25
	profile["stop"] = minf(FEEL.hit_stop_limit, float(profile.stop))
	return profile

static func instance_id(hit: Dictionary) -> String:
	return "%s:%s:%s:%s" % [hit.get("source_key", "environment"), hit.get("sequence", 0), hit.get("emission", 0), hit.get("summon_id", hit.get("id", ""))]

static func reaction_scale(target: RefCounted) -> float:
	if target.enemy.get("rank", "") == "Boss" or super_armor(target): return 0.0
	return 0.5 if target.enemy.get("rank", "") == "Elite" else 1.0

static func super_armor(target: RefCounted) -> bool:
	for key in ["SuperArmor", "IsSuperArmor", "HyperArmor", "IgnoreHitAction"]:
		if bool(target.custom_properties.get(key, false)): return true
	return false
