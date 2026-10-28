extends RefCounted

const DATA_PATH := "res://assets/data/monster_hit_rules.json"
const PUSH_MIN_RATIO := 0.10000000149011612
const PUSH_CUTOFF := 0.05000000074505806
static var _catalog: Dictionary = {}
static var _action_states: Dictionary = {}
static var _action_hit_rules: Dictionary = {}
static var _action_speed_events: Dictionary = {}

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
	target.custom_properties.erase("_enemy_hit_clock")
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
					if value != null: multiplier = _float32(multiplier + _float32(float(value) * _float32(0.001)))
				power = int(_float32(power * multiplier))
			power = _float32(power * _float32(1.0 + _float32(source.attribute("PushForceAddRate") * _float32(0.001))))
		var weight := _weight(target)
		var resistance: float = float(target.enemy_hit_rules.PushForceResist) + target.attribute("PushForceResist")
		var effective := _float32(maxf(0.0, _float32(absf(power) - resistance))) * signf(power)
		var direction := push_direction(feedback, hit.get("hit_geometry", {}))
		var motion: Dictionary = target.custom_properties.get("_enemy_hit_motion", {"duration": 0.0, "remaining": 0.0})
		var force := direction * effective
		# Subthreshold weak hits replace force without restarting existing timers.
		motion.force = [force.x, 0.0, force.z]
		motion.facing = [-direction.x, 0.0, -direction.z]
		target.custom_properties["_enemy_hit_motion"] = motion
		if float(feedback.get("UpperPower", 0)) >= weight:
			motion.duration = 0.0
			motion.remaining = 0.0
			target.custom_properties["_enemy_hit_action"] = "hit_2"
		elif _float32(absf(effective) / weight) >= PUSH_MIN_RATIO:
			var logarithm := _float32(log(_float32(1.0 + _float32(absf(effective) / weight))) / log(2.0))
			motion.duration = _float32(_float32(logarithm + 1.0) * PUSH_MIN_RATIO)
			motion.remaining = motion.duration
			target.custom_properties["_enemy_hit_action"] = "hit_1"

static func _weight(target: RefCounted) -> float:
	var value := _float32(float(target.enemy_hit_rules.Weight) + float(action_rules_for(target).get("WeightAddValue", 0)) + target.attribute("Weight"))
	return 100.0 if value == 0.0 else value

static func push_direction(feedback: Dictionary, geometry: Dictionary) -> Vector3:
	var attacker := _vector(geometry.get("attacker_position", []))
	var attackee := _vector(geometry.get("attackee_position", []))
	var direction := Vector3.ZERO
	var mode: Variant = feedback.get("PushMode", "AttackerForward")
	match str(int(mode)) if mode is int or mode is float else str(mode):
		"AttackerForward", "0": direction = _vector(geometry.get("attacker_forward", []))
		"AttackerToAttackeeDir", "1": direction = attackee - attacker
		"AttackEntityForward", "2":
			direction = _vector(geometry.get("entity_forward", []))
			if direction.length_squared() < _float32(1e-10): direction = attackee - attacker
		"AttackEntityToAttackeeDir", "3":
			var point := _vector(geometry.get("entity_position", []))
			direction = attackee - attacker if point.length_squared() < _float32(1e-10) else attackee - point
	direction.y = 0.0
	return direction.normalized() if direction.length() > _float32(0.00001) else Vector3.ZERO

static func motion_delta(target: RefCounted, available_delta: float, advance_clock := false) -> float:
	if available_delta < 0: return 0.0
	var definition: Dictionary = target._action(str(target.enemy.get("group", "")), target.current_action)
	if definition.is_empty(): return available_delta if target.custom_properties.has("_enemy_hit_motion") else 0.0
	var speed := float(target.custom_properties.get("_feel_action_speed", 1.0))
	var clock: Dictionary = target.custom_properties.get("_enemy_hit_clock", {})
	if clock.is_empty() or int(clock.get("sequence", -1)) != target._cast_sequence:
		clock = {"sequence": target._cast_sequence, "elapsed_ms": 0, "rate": 1.0, "next": 0, "active": []}
	elif not advance_clock:
		clock = clock.duplicate(true)
	var local_scale := _float32(speed * float(clock.rate))
	if local_scale <= 0: return 0.0
	# TickAction runs events after quantizing the old scale, then movement reads
	# the resulting scale. New duration events age by the entire step as well.
	var elapsed_ms := int(_float32(_float32(_float32(available_delta) * local_scale) * 1000.0))
	var remaining_ms := maxi(0, roundi(float(definition.duration) * 1000.0) - int(clock.elapsed_ms))
	elapsed_ms = mini(elapsed_ms, remaining_ms)
	clock.elapsed_ms = int(clock.elapsed_ms) + elapsed_ms
	var events := _speed_events(definition)
	while int(clock.next) < events.size() and int(events[int(clock.next)].start_ms) <= int(clock.elapsed_ms):
		var event: Dictionary = events[int(clock.next)]
		if target._conditions(event.conditions, bool(event.all_required)):
			clock.rate = event.rate
			clock.active.append({"index": int(clock.next), "elapsed_ms": 0})
		clock.next = int(clock.next) + 1
	for active in clock.active.duplicate():
		var index := int(active.index)
		if index < 0 or index >= events.size():
			clock.active.erase(active)
			continue
		active.elapsed_ms = int(active.elapsed_ms) + elapsed_ms
		if int(active.elapsed_ms) > int(events[index].duration_ms):
			clock.active.erase(active)
			clock.rate = 1.0
	if advance_clock: target.custom_properties["_enemy_hit_clock"] = clock
	local_scale = _float32(speed * float(clock.rate))
	if local_scale <= 0 or not target.custom_properties.has("_enemy_hit_motion"): return 0.0
	return _float32(_float32(elapsed_ms * _float32(0.001)) / local_scale)

static func _speed_events(definition: Dictionary) -> Array:
	var key := str(definition.get("key", ""))
	var cached: Dictionary = _action_speed_events.get(key, {})
	if not cached.is_empty() and is_same(cached.definition, definition): return cached.events
	var events: Array[Dictionary] = []
	for command in definition.get("events", []):
		if not command.get("enabled", false) or command.get("type", "") != "EET_ActionSpeedScale" or float(command.get("duration", 0)) <= 0: continue
		var raw: Variant = JSON.parse_string(str(command.get("raw", "{}")))
		if not raw is Dictionary: continue
		events.append({"start_ms": roundi(float(command.get("time", 0)) * 1000.0), "duration_ms": roundi(float(command.duration) * 1000.0), "rate": _float32(float(raw.get("ScaleSpeed", 1))), "conditions": command.get("conditions", []), "all_required": command.get("all", true), "order": events.size()})
	events.sort_custom(func(a, b): return int(a.order) < int(b.order) if int(a.start_ms) == int(b.start_ms) else int(a.start_ms) < int(b.start_ms))
	_action_speed_events[key] = {"definition": definition, "events": events}
	return events

static func advance_motion(target: RefCounted, delta: float) -> Vector3:
	var motion: Dictionary = target.custom_properties.get("_enemy_hit_motion", {})
	if motion.is_empty() or delta <= 0: return Vector3.ZERO
	if target.health <= 0:
		clear_motion(target)
		return Vector3.ZERO
	var remaining := float(motion.remaining)
	var duration := float(motion.duration)
	if remaining <= PUSH_CUTOFF or duration <= 0:
		motion.force = [0.0, 0.0, 0.0]
		motion.duration = 0.0
		motion.remaining = 0.0
		return Vector3.ZERO
	var force := _vector(motion.force)
	var weight := _weight(target)
	var step := _float32(delta)
	var displacement := Vector3.ZERO
	# ProcessHitAndUpMove samples speed before decrementing the timer, including
	# its final overshooting step. The caller supplies the source motion clock.
	for axis in [0, 2]:
		var speed := _float32(_float32(force[axis] / weight) / duration)
		speed = _float32(_float32(remaining * _float32(speed + speed)) / duration)
		displacement[axis] = _float32(speed * step)
	motion.remaining = _float32(remaining - step)
	if motion.remaining < 0:
		motion.force = [0.0, 0.0, 0.0]
		motion.duration = 0.0
		motion.remaining = 0.0
	return displacement

static func take_facing(target: RefCounted) -> Vector3:
	var motion: Dictionary = target.custom_properties.get("_enemy_hit_motion", {})
	var direction := _vector(motion.get("facing", []))
	motion.erase("facing")
	return direction

static func clear_motion(target: RefCounted) -> void:
	target.custom_properties.erase("_enemy_hit_motion")

static func _vector(value: Variant) -> Vector3:
	if value is Vector3: return value if value.is_finite() else Vector3.ZERO
	if not value is Array or value.size() != 3: return Vector3.ZERO
	var result := Vector3(float(value[0]), float(value[1]), float(value[2]))
	return result if result.is_finite() else Vector3.ZERO

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
	var clock: Variant = target.custom_properties.get("_enemy_hit_clock")
	if clock != null:
		if not clock is Dictionary or not clock.get("active", []) is Array or not is_finite(float(clock.get("rate", 1))):
			target.custom_properties.erase("_enemy_hit_clock")
		else:
			clock.sequence = int(clock.get("sequence", -1))
			clock.elapsed_ms = maxi(0, int(clock.get("elapsed_ms", 0)))
			clock.rate = _float32(float(clock.get("rate", 1)))
			clock.next = maxi(0, int(clock.get("next", 0)))
			clock.active = clock.get("active", []).filter(func(entry): return entry is Dictionary and entry.has("index") and entry.has("elapsed_ms"))
			for active in clock.active:
				active.index = int(active.index)
				active.elapsed_ms = maxi(0, int(active.elapsed_ms))
	var motion: Variant = target.custom_properties.get("_enemy_hit_motion")
	if motion != null:
		if not motion is Dictionary:
			clear_motion(target)
		else:
			for field in ["duration", "remaining"]:
				var value := float(motion.get(field, 0.0))
				motion[field] = _float32(maxf(0.0, value)) if is_finite(value) else 0.0
			for field in ["force", "facing"]:
				if field == "facing" and not motion.has(field): continue
				var value := _vector(motion.get(field, []))
				motion[field] = [value.x, value.y, value.z]
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
