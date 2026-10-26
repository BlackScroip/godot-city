extends RefCounted

const FEEL = preload("res://assets/feel_settings.tres")
var pending: Dictionary = {}
var last_move := Vector3.ZERO
var heavy_held := false
var attack_held := false
var attack_hold_elapsed := 0.0
var hold_consumed := false
var skill_one_held := false
var skill_one_hold_elapsed := 0.0

func attack_button(combat: RefCounted, pressed: bool) -> Dictionary:
	if pressed:
		attack_held = true
		attack_hold_elapsed = 0.0
		hold_consumed = false
		return {"success": true, "status": "held"}
	if not attack_held: return {"success": true, "status": "released"}
	attack_held = false
	attack_hold_elapsed = 0.0
	if hold_consumed:
		hold_consumed = false
		return request(combat, 4, false)
	return request(combat, 0, true)

func cancel_button(combat: RefCounted, slot: int) -> void:
	if slot == 0:
		attack_held = false
		attack_hold_elapsed = 0.0
		hold_consumed = false
		heavy_held = false
		if int(pending.get("slot", -1)) in [0, 4]: pending.clear()
		combat.cancel_held_attack()
	else:
		if slot == 2:
			skill_one_held = false
			skill_one_hold_elapsed = 0.0
		if slot in [2, 3] and (pending.is_empty() or int(pending.slot) == slot): combat.custom_properties.InputSkill = false
		if int(pending.get("slot", -1)) == slot: pending.clear()
		combat.record_input(slot, false)

func advance_hold(combat: RefCounted, delta: float) -> void:
	if skill_one_held:
		skill_one_hold_elapsed += delta
		if skill_one_hold_elapsed + 0.000001 >= FEEL.attack_hold_threshold:
			combat.custom_properties["InputSkill1_LongPress"] = true
	if not attack_held: return
	attack_hold_elapsed += delta
	if attack_hold_elapsed + 0.000001 < FEEL.attack_hold_threshold: return
	# The APK repeats its long-press command, including after a rejected attempt.
	hold_consumed = true
	if not pending.is_empty() and int(pending.slot) not in [0, 4]: return
	request(combat, 4, true)

func manual_attack_active() -> bool:
	return attack_held or heavy_held or not pending.is_empty()

func request(combat: RefCounted, slot: int, pressed: bool) -> Dictionary:
	if slot == 2:
		skill_one_held = pressed
		skill_one_hold_elapsed = 0.0
	if slot == 4 and not pressed:
		heavy_held = false
		if int(pending.get("slot", -1)) == 4: pending.clear()
		combat.request_attack(4, false)
		return {"success": true, "status": "executed"}
	if not pressed:
		combat.request_attack(slot, false)
		return {"success": true, "status": "released"}
	if slot == 4 and combat._current_slot == 4 and combat.busy > 0 and combat.health > 0 and combat.frozen <= 0:
		heavy_held = true
		if int(pending.get("slot", -1)) != 1: pending.clear()
		combat.request_attack(4, true)
		return {"success": true, "status": "executed"}
	var reason = combat.input_block_reason(slot)
	if slot in [2, 3]: combat.custom_properties["LastInputAttackKeyName"] = "skill_%d" % (slot - 1)
	if not reason.is_empty(): return {"success": false, "status": "rejected", "message": reason}
	var previous_skill_input = bool(combat.custom_properties.get("InputSkill", false))
	combat.record_input(slot, true)
	var delay = maxf(float(combat.cooldowns[slot]), combat.input_action_delay(slot))
	if delay > FEEL.input_buffer:
		if slot in [2, 3]: combat.custom_properties.InputSkill = previous_skill_input
		return {"success": false, "status": "rejected", "message": "Action in progress"}
	if not pending.is_empty() and int(pending.slot) == 1 and slot != 1:
		if slot in [2, 3]: combat.custom_properties.InputSkill = previous_skill_input
		return {"success": false, "status": "rejected", "message": "Dodge pending"}
	heavy_held = pressed if slot == 4 else heavy_held
	if slot == 0:
		combat.custom_properties.InputAttack = true
		combat.custom_properties.AttackModeStr = "normal"
	pending = {"slot": slot, "remaining": FEEL.input_buffer, "fresh": true}
	return {"success": true, "status": "buffered"}

func take_ready(combat: RefCounted, delta: float) -> int:
	if pending.is_empty(): return -1
	var slot = int(pending.slot)
	if not combat.input_block_reason(slot).is_empty() or (slot == 4 and not heavy_held):
		pending.clear()
		if slot in [2, 3]: combat.custom_properties.InputSkill = false
		return -1
	if not pending.fresh: pending.remaining -= delta
	pending.fresh = false
	if float(pending.remaining) < -0.00001:
		pending.clear()
		if slot in [2, 3]: combat.custom_properties.InputSkill = false
		return -1
	if float(combat.cooldowns[slot]) <= 0 and combat.input_action_delay(slot) <= 0:
		pending.clear()
		return slot
	return -1

func clear(combat: RefCounted = null) -> void:
	pending.clear()
	heavy_held = false
	attack_held = false
	hold_consumed = false
	attack_hold_elapsed = 0.0
	skill_one_held = false
	skill_one_hold_elapsed = 0.0
	if combat: combat.cancel_held_input()

func dodge_direction(movement: Vector3, facing: Vector3) -> Vector3:
	if movement.length_squared() > 0.0001: return movement.normalized()
	return last_move if last_move.length_squared() > 0.0001 else facing
