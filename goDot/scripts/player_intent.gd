extends RefCounted

const FEEL = preload("res://assets/feel_settings.tres")
var pending: Dictionary = {}
var last_move := Vector3.ZERO
var heavy_held := false

func request(combat: RefCounted, slot: int, pressed: bool) -> Dictionary:
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
	if not reason.is_empty(): return {"success": false, "status": "rejected", "message": reason}
	var delay = maxf(float(combat.cooldowns[slot]), combat.input_action_delay(slot))
	if delay > FEEL.input_buffer:
		return {"success": false, "status": "rejected", "message": "Action in progress"}
	if not pending.is_empty() and int(pending.slot) == 1 and slot != 1:
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
		return -1
	if not pending.fresh: pending.remaining -= delta
	pending.fresh = false
	if float(pending.remaining) < -0.00001:
		pending.clear()
		return -1
	if float(combat.cooldowns[slot]) <= 0 and combat.input_action_delay(slot) <= 0:
		pending.clear()
		return slot
	return -1

func clear(combat: RefCounted = null) -> void:
	pending.clear()
	heavy_held = false
	if combat: combat.cancel_held_input()

func dodge_direction(movement: Vector3, facing: Vector3) -> Vector3:
	if movement.length_squared() > 0.0001: return movement.normalized()
	return last_move if last_move.length_squared() > 0.0001 else facing
