extends RefCounted

const DATA_PATH := "res://assets/data/monster_hit_rules.json"
static var _catalog: Dictionary = {}
static var _action_states: Dictionary = {}
static var _action_hit_rules: Dictionary = {}

static func rules_for(id: int) -> Dictionary:
	if _catalog.is_empty():
		var data = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if data is Dictionary:
			_catalog = data.get("enemies", {})
			_action_states = data.get("action_states", {})
			_action_hit_rules = data.get("action_hit_rules", {})
	return _catalog.get(str(id), {})

static func action_rules_for(target: RefCounted) -> Dictionary:
	return _action_hit_rules.get(str(target.enemy.get("group", "")) + "/" + str(target.current_action), {})

static func action_started(target: RefCounted, definition: Dictionary) -> void:
	if int(_action_states.get(str(definition.get("key", "")), -1)) == 6:
		target.custom_properties["_enemy_hit_action"] = ""

static func matches(target: RefCounted, flags: int) -> bool:
	var index := ["hit_1", "hit_2", "hitfly", "hitdown"].find(str(target.custom_properties.get("_enemy_hit_action", "")))
	return index >= 0 and (flags & (1 << index)) != 0

static func condition_flags(condition: Dictionary) -> int:
	var flags := 0
	var names := ["Behit_BackLow", "Behit_BackHigh", "Behit_Fly", "Behit_Down"]
	for index in names.size():
		if bool(condition.get(names[index], false)): flags |= 1 << index
	return flags

static func apply(target: RefCounted, hit: Dictionary) -> void:
	if target.enemy_hit_rules.is_empty() or target.health <= 0 or not target.can_receive_attack(): return
	if target.invincible > 0 or target._dodge_time > 0 or target._block_time > 0 or armored(target): return
	var raw: Variant = hit.get("definition", {}).get("raw", {})
	if raw is String: raw = target._read_raw_json(raw)
	if not raw is Dictionary: return
	for feedback in raw.get("FeedbackList", []):
		if feedback.get("FeedbackType", "") != "EHT_HitAction": continue
		add_tenacity(target, float(feedback.get("AccTenacity", 0)))
		if not is_weak(target): continue
		var power := float(feedback.get("PushPower", 0))
		var modifier := str(feedback.get("PushPowerModifyPropertyName", ""))
		var source: Variant = hit.get("source")
		if source is RefCounted:
			if not modifier.is_empty():
				var multiplier := 1.0
				for name in modifier.split("|", false):
					var value: Variant = source.property_value(name)
					if value != null: multiplier += float(value) * 0.001
				power = int(power * multiplier)
			power *= 1.0 + source.attribute("PushForceAddRate") * 0.001
		var weight: float = float(target.enemy_hit_rules.Weight) + float(action_rules_for(target).get("WeightAddValue", 0)) + target.attribute("Weight")
		if weight == 0: weight = 100.0
		var resistance: float = float(target.enemy_hit_rules.PushForceResist) + target.attribute("PushForceResist")
		var effective := maxf(0.0, absf(power) - resistance)
		if float(feedback.get("UpperPower", 0)) >= weight:
			target.custom_properties["_enemy_hit_action"] = "hit_2"
		elif _float32(effective / weight) >= 0.10000000149011612:
			target.custom_properties["_enemy_hit_action"] = "hit_1"

static func state_for(target: RefCounted) -> Dictionary:
	if not target.custom_properties.has("_enemy_hit_reaction"):
		target.custom_properties["_enemy_hit_reaction"] = {"accumulated": 0.0, "weak": false, "weak_elapsed": 0.0}
	return target.custom_properties._enemy_hit_reaction

static func armored(target: RefCounted) -> bool:
	for key in ["SuperArmor", "IsSuperArmor", "HyperArmor", "IgnoreHitAction"]:
		if bool(target.custom_properties.get(key, false)): return true
	return false

static func add_tenacity(target: RefCounted, amount: float) -> bool:
	if target.enemy.is_empty() or target.enemy_hit_rules.is_empty(): return false
	if target.health <= 0 or target.invincible > 0 or target.shield > 0 or target.armor > 0 or armored(target): return false
	var state := state_for(target)
	if state.weak: return false
	# RoleUnit.AddAccTenacity adds the rate term, rather than scaling the hit.
	state.accumulated = _float32(float(state.accumulated) + _float32(amount + target.attribute("TenacityAccAddRate") * 0.001))
	var limit: float = float(target.enemy_hit_rules.BaseTenacity) + float(action_rules_for(target).get("StableValue", 0)) + target.attribute("BaseTenacity")
	if state.accumulated < limit: return false
	state.accumulated = 0.0
	state.weak_elapsed = 0.0
	state.weak = true
	return true

static func tick(target: RefCounted, delta: float) -> void:
	if target.enemy_hit_rules.is_empty() or not target.custom_properties.has("_enemy_hit_reaction"): return
	var state := state_for(target)
	if state.weak:
		state.weak_elapsed = _float32(float(state.weak_elapsed) + _float32(delta))
		if state.weak_elapsed >= float(target.enemy_hit_rules.BaseWeakTime) + target.attribute("BaseWeakTime"):
			state.weak = false
			state.weak_elapsed = 0.0
			state.accumulated = 0.0
	elif float(state.accumulated) > 0:
		var recovery: float = float(target.enemy_hit_rules.BaseTenacityAccReduce) + target.attribute("BaseTenacityRecover")
		state.accumulated = maxf(0.0, _float32(float(state.accumulated) - recovery * _float32(delta)))

static func is_weak(target: RefCounted) -> bool:
	return bool(target.custom_properties.get("_enemy_hit_reaction", {}).get("weak", false))

static func restore_state(target: RefCounted) -> void:
	var state: Variant = target.custom_properties.get("_enemy_hit_reaction")
	if state == null: return
	if not state is Dictionary:
		target.custom_properties.erase("_enemy_hit_reaction")
		return
	for field in ["accumulated", "weak_elapsed"]:
		var value := float(state.get(field, 0))
		state[field] = _float32(maxf(0, value)) if is_finite(value) else 0.0
	state.weak = bool(state.get("weak", false))

static func _float32(value: float) -> float:
	return PackedFloat32Array([value])[0]
