extends RefCounted

const FEEL = preload("res://assets/feel_settings.tres")
const Original = preload("res://scripts/presentation/hit_feedback.gd")
static var _source_heavy_actions: Dictionary = {}

static func is_source_wolf(hit: Dictionary, source: RefCounted = null) -> bool:
	var owner: Variant = source if source != null else hit.get("source")
	if not owner is RefCounted: return false
	var enemy: Variant = owner.get("enemy")
	return enemy is Dictionary and int(enemy.get("id", 0)) == 13001

static func is_source_heavy(hit: Dictionary, source: RefCounted = null) -> bool:
	var owner: Variant = source if source != null else hit.get("source")
	var player_owned := false
	if owner is RefCounted:
		var fighter: Variant = owner.get("fighter")
		var enemy: Variant = owner.get("enemy")
		player_owned = fighter is Dictionary and not fighter.is_empty() and enemy is Dictionary and enemy.is_empty()
	else:
		player_owned = bool(hit.get("source_player", false)) or str(hit.get("source_key", "")) == "player"
	if not player_owned: return false
	# Emitted lineage survives action changes, projectile travel and summon delay.
	if bool(hit.get("source_heavy", false)) or int(hit.get("slot", -1)) == 4: return true
	var origin: Variant = hit.get("origin", {})
	if origin is Dictionary and bool(origin.get("_source_heavy", false)): return true
	if _source_heavy_actions.is_empty():
		if owner is RefCounted:
			var catalog: Variant = owner.get("_heavy_catalog")
			if catalog is Dictionary: _source_heavy_actions = catalog.get("actions", {})
	return _source_heavy_actions.has(str(hit.get("action", "")))

static func raw(hit: Dictionary) -> Dictionary:
	return Original.raw({"raw": hit.get("definition", {}).get("raw", {})})

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
	if is_source_heavy(hit, source):
		return {"source_only": true, "source_heavy": true, "category": "source", "stop": 0.0, "shake": 0.0, "amplitude": 0.0, "distance": 0.0, "travel": 0.0, "stagger": 0.0, "flash": 0.0, "scale": 1.0, "gain": 1.0, "ranged": ranged(hit), "finisher": false, "critical": bool(hit.get("resolved_critical", false)), "source_feedback": Original.read(hit.get("definition", {}))}
	var action = str(hit.get("action", ""))
	var category = str(hit.get("impact_category", "light"))
	if int(hit.get("slot", 0)) == 4: category = "heavy"
	var original = Original.read(hit.get("definition", {}))
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
	if is_source_wolf(hit, source):
		# Preserve the existing movement profile while presentation uses the APK feedback.
		profile["source_only"] = true
		profile["source_feedback"] = original
	return profile

static func instance_id(hit: Dictionary) -> String:
	return "%s:%s:%s:%s" % [hit.get("source_key", "environment"), _identity_number(hit.get("sequence", 0)), _identity_number(hit.get("emission", 0)), hit.get("summon_id", hit.get("id", ""))]

static func _identity_number(value: Variant) -> String:
	# JSON restores integer counters as floats; their attack identity is unchanged.
	if value is float and is_finite(value) and value == floor(value): return str(int(value))
	return str(value)

static func reaction_scale(target: RefCounted) -> float:
	if target.enemy.get("rank", "") == "Boss" or super_armor(target): return 0.0
	return 0.5 if target.enemy.get("rank", "") == "Elite" else 1.0

static func super_armor(target: RefCounted) -> bool:
	for key in ["SuperArmor", "IsSuperArmor", "HyperArmor", "IgnoreHitAction"]:
		if bool(target.custom_properties.get(key, false)): return true
	return false
