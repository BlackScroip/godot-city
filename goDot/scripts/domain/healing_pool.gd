class_name DungeonHealingPool
extends RefCounted

const BUTTON_KEY := "EnvUnit_MonoData_BtnDisplayName_Spring"
const USED_TIP_KEY := "RogueNodeEvent_SpringRoom_DrinkTip"
const BASE_RECOVERY_RATIO := 300.0

func drink(counters: Dictionary, room_key: String, max_health: float, health: float, recovery_ratio: float = BASE_RECOVERY_RATIO) -> Dictionary:
	if room_key.is_empty() or not is_finite(max_health) or max_health <= 0 or not is_finite(health) or not is_finite(recovery_ratio):
		return {"success": false, "reason": "invalid_state"}
	var key := "rest:" + room_key
	if bool(counters.get(key, false)):
		return {"success": false, "reason": "already_used", "tip_key": USED_TIP_KEY}
	# The native CombatResult healing branch truncates float32 healing before ChangeHP.
	var ratio32 := _float32(_float32(recovery_ratio) / _float32(1000.0))
	var amount := maxf(0.0, float(int(_float32(ratio32 * _float32(max_health)))))
	counters[key] = true
	return {"success": true, "amount": amount, "health": clampf(health + amount, 0.0, max_health), "used": true}

func is_used(counters: Dictionary, room_key: String) -> bool:
	return bool(counters.get("rest:" + room_key, false))

func reward_plan(attributes: Dictionary, red_roll: int, green_roll: int) -> Array[int]:
	var loot: Array[int] = []
	var purse_level := int(float(attributes.get("DrinkSpringGetPurseLv", 0)))
	if purse_level in [1, 2, 3]: loot.append(11000 + purse_level)
	if red_roll >= 1 and red_roll <= 1000 and red_roll <= int(float(attributes.get("DrinkSpringGetRedgemLv", 0))): loot.append(10000)
	if green_roll >= 1 and green_roll <= 1000 and green_roll <= int(float(attributes.get("DrinkSpringGetGreengemLv", 0))): loot.append(10010)
	return loot

func _float32(value: float) -> float:
	return PackedFloat32Array([value])[0]
