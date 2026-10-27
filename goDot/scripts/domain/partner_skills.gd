extends RefCounted

const RoomChoices = preload("res://scripts/domain/room_choices.gd")
const BATTLE = "room-partner-battle"
const SP = "MonsterPartnerSp"
const DATA = "res://assets/data/partner_skills.json"
static var _skills: Dictionary = {}
var _owner: WeakRef
var systems:
	get: return _owner.get_ref()

func _init(owner_systems) -> void:
	_owner = weakref(owner_systems)
	if _skills.is_empty():
		var source: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA))
		if source is Dictionary:
			for row in source.get("skills", []): _skills[int(row.id)] = row

func definition(id: int, level: int = 1) -> Dictionary:
	var row: Dictionary = _skills.get(id, {}).duplicate(true)
	if row.is_empty(): return row
	var parts: PackedStringArray = str(row.description).split("|")
	row.description = parts[clampi(level - 1, 0, parts.size() - 1)]
	row.level = level
	return row

func _battle() -> Dictionary:
	var counters: Dictionary = systems.profile.data.run.counters
	if not counters.get(BATTLE) is Dictionary: counters[BATTLE] = {"slots": []}
	var battle: Dictionary = counters[BATTLE]
	var old: Array = battle.get("slots", [])
	var current: Array = []
	var choices: Array = RoomChoices.new(systems).partner_slots()
	for index in choices.size():
		var chosen: Dictionary = choices[index]
		var slot: Dictionary = old[index] if index < old.size() else {}
		if int(slot.get("id", 0)) != int(chosen.id) or int(slot.get("level", 0)) != int(chosen.level):
			slot = {"id": int(chosen.id), "level": int(chosen.level), "remaining": float(definition(int(chosen.id), int(chosen.level)).get("cooldown", 0))}
		current.append(slot)
	battle.slots = current
	return battle

func max_sp() -> float:
	return maxf(0, 75.0 + float(systems.attributes().get("MonsterPartnerMaxSp", 0)))

func state(combat = null) -> Dictionary:
	var battle := _battle()
	var counters: Dictionary = systems.profile.data.run.counters
	var maximum := max_sp()
	var sp := clampf(float(counters.get(SP, 0)), 0, maximum)
	counters[SP] = sp
	var slots: Array = []
	for stored in battle.slots:
		var slot := definition(int(stored.id), int(stored.level))
		if slot.is_empty(): continue
		slot.remaining = maxf(0, float(stored.remaining))
		slot.ready = sp >= float(slot.cost) and float(slot.remaining) <= 0
		if combat != null:
			slot.ready = slot.ready and combat.health > 0 and combat.frozen <= 0 and combat.input_action_delay(5 + slots.size()) <= 0
		slots.append(slot)
	return {"sp": sp, "max_sp": maximum, "slots": slots}

func tick(combat, delta: float, enemy_in_range: bool) -> void:
	if delta <= 0 or not systems.profile.data.run.active or combat == null or combat.health <= 0: return
	var battle := _battle()
	for slot in battle.slots: slot.remaining = maxf(0, float(slot.remaining) - delta)
	if not enemy_in_range: return
	var attributes: Dictionary = systems.attributes()
	var speed := 1000.0 + float(attributes.get("MonsterPartnerSpChargeSpeed", 0))
	var gain := (4.0 * speed / (3.0 * speed + 5000.0)) if speed > 0 else 0.0
	gain *= 1.0 + float(attributes.get("MonsterPartnerSpChargeLinearRate", 0)) / 1000.0
	var counters: Dictionary = systems.profile.data.run.counters
	counters[SP] = clampf(float(counters.get(SP, 0)) + gain * delta, 0, max_sp())

func charge(settings: Dictionary) -> void:
	var counters: Dictionary = systems.profile.data.run.counters
	var amount := float(settings.get("ChargeCount", 0)) / 1000.0 + 25.0 * float(settings.get("ChargePercent", 0)) / 1000.0
	counters[SP] = clampf(float(counters.get(SP, 0)) + amount, 0, max_sp())
	for slot in _battle().slots:
		var maximum := float(definition(int(slot.id), int(slot.level)).get("cooldown", 0))
		var reduction := float(settings.get("ReduceCooldown", 0)) / 1000.0 + maximum * float(settings.get("ReduceCooldownPercent", 0)) / 1000.0
		slot.remaining = maxf(0, float(slot.remaining) - reduction)

func request(combat, index: int) -> Dictionary:
	if combat == null or not systems.profile.data.run.active or combat.health <= 0: return systems._fail("伙伴技能不可使用")
	var current := state(combat)
	if index < 0 or index >= current.slots.size(): return systems._fail("未装备伙伴技能")
	var skill: Dictionary = current.slots[index]
	if not bool(skill.ready): return systems._fail("能量不足、冷却中或动作未结束")
	var action: Dictionary = combat._action("ActGroup_playerchara", str(skill.action))
	if action.is_empty(): return systems._fail("伙伴技能动作缺失")
	systems.profile.data.run.counters[SP] = float(current.sp) - float(skill.cost)
	_battle().slots[index].remaining = float(skill.cooldown)
	combat.cancel_held_input()
	combat._start(action, 5 + index)
	return {"success": true, "message": str(skill.name), "id": int(skill.id)}
