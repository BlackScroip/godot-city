extends RefCounted

const Catalog = preload("res://scripts/domain/catalog.gd")
const RECORDS = "room-choice-records"
const SLOTS = "room-partner-skills"
const HP_ADJUSTMENT = "run:hp_fixed_adjustment"
const PARTNER_COMMON_POOL = 30100
const NATIVE_REGION_PRICE = 500
const NATIVE_BUY_PRICE = 200
var _owner: WeakRef
var systems:
	get: return _owner.get_ref()

func _init(owner_systems) -> void:
	_owner = weakref(owner_systems)

static func sacrifice_spawn_eligible(room: Dictionary, elapsed_seconds: float, attrs: Dictionary = {}) -> bool:
	if not is_finite(elapsed_seconds) or elapsed_seconds < 0.0: return false
	if str(room.get("FightType", "")) != "Regular": return false
	if str(room.get("EnemyClass", room.get("flow", room.get("Flow", "")))) != "Boss": return false
	var data: Variant = room.get("FightData", {})
	if not data is Dictionary: return false
	var times: Variant = data.get("BossBattleRankTime", [])
	if not times is Array or times.is_empty() or not (times[0] is int or times[0] is float): return false
	if not is_finite(float(times[0])) or float(times[0]) <= 0.0: return false
	# StartRegularFight scales and truncates each time limit before its strict comparison.
	var multiplier := _f32(1.0 + _f32(_f32(int(attrs.get("BossRatingTimeAddRate", 0))) * _f32(0.001)))
	var limit := int(_f32(_f32(int(times[0])) * multiplier))
	return _f32(elapsed_seconds) < float(limit)

func _records() -> Dictionary:
	var counters: Dictionary = systems.profile.data.run.counters
	if not counters.get(RECORDS) is Dictionary: counters[RECORDS] = {}
	return counters[RECORDS]

func _valid(key: String) -> bool:
	return systems.profile.data.run.active and systems.profile.data.run.health > 0 and not key.is_empty()

func _state(key: String) -> Dictionary:
	var record: Dictionary = _records().get(key, {})
	if record.is_empty(): return systems._fail("选择不存在")
	var result: Dictionary = record.duplicate(true)
	result["success"] = true
	result["key"] = key
	result["slots"] = partner_slots().duplicate(true)
	if str(record.kind) == "sacrifice":
		result["free_refresh"] = _free_sacrifice_refresh(record)
		for option in result.options:
			option["enabled"] = systems.can_add_loot(int(option.id)) and float(systems.profile.data.run.max_health) > int(option.hp_cost)
	return result

func open_sacrifice(key: String, first_node: bool = false) -> Dictionary:
	if not _valid(key): return systems._fail("祭坛不可使用")
	if _records().has(key): return _state(key)
	var options := _sacrifice_options()
	if options.is_empty(): return systems._fail("没有可选物品")
	_records()[key] = {"kind": "sacrifice", "options": options, "taken": 0, "closed": false, "selected": [], "first_node": first_node}
	systems._add(systems.profile.data.run.counters, "SelectLootRemainCount_Reward", 1)
	return _state(key)

func _sacrifice_options(excluded: Array = [], count_override: int = -1) -> Array:
	var attrs: Dictionary = systems.attributes()
	var count := maxi(1, 3 + int(attrs.get("BlessingPlusSelectExtraCount", 0))) if count_override < 0 else count_override
	if count <= 0: return []
	var pool := int(systems.catalog.config.get("AbilityItemLootPoolId_Reward", 20202))
	var choices: Array = systems.roll_pool(pool, count, 0, excluded)
	if choices.is_empty(): choices = systems.roll_pool(int(systems.catalog.config.get("AbilityItemLootGuaranteedPoolId_Reward", 20112)), count, 0, excluded)
	var minimum := 30 + int(attrs.get("SacrificialAltarHpDownMin", 0))
	var maximum := maxi(minimum, 50 + int(attrs.get("SacrificialAltarHpDownMax", 0)))
	var region := maxi(0, int(systems.profile.data.run.region) - 1)
	var paid := int(systems.profile.data.run.counters.get("SacrificialAltarRefreshCount", 0))
	var config: Dictionary = systems.catalog.config
	var multiplier := _f32(1.0 + _f32(int(attrs.get("SacrificialAltarHpDownRate", 0)) * _f32(0.001)))
	multiplier = _f32(multiplier + _f32(region * int(config.get("SacrificialAltarHpDownPerRegionMulti", NATIVE_REGION_PRICE)) * _f32(0.001)))
	multiplier = _f32(multiplier + _f32(paid * int(config.get("SacrificialAltarHpDownPriceIncreasePerBuy", NATIVE_BUY_PRICE)) * _f32(0.001)))
	var options: Array = []
	for id in choices:
		var base: int = minimum + systems.next_random(maximum - minimum + 1)
		options.append({"id": int(id), "hp_cost": maxi(0, int(_f32(base * multiplier))), "locked": false})
	return options

func choose_sacrifice(key: String, id: int) -> Dictionary:
	if not _valid(key): return systems._fail("祭坛不可使用")
	var record: Dictionary = _records().get(key, {})
	if record.is_empty() or record.get("closed", false) or str(record.kind) != "sacrifice": return systems._fail("净化已结束")
	for option in record.options:
		if int(option.id) != id: continue
		var cost := int(option.hp_cost)
		if float(systems.profile.data.run.max_health) <= cost: return systems._fail("生命值不足，无法继续净化")
		if not systems.can_add_loot(id): return systems._fail("物品不可领取")
		adjust_max_health(-cost)
		var result: Dictionary = systems.add_loot(id, false)
		if not result.success:
			adjust_max_health(cost)
			return result
		record.options.erase(option)
		record.selected.append(id)
		record.taken = int(record.taken) + 1
		return systems._done("净化完成", id)
	return systems._fail("物品不在祭坛候选中")

func _commit_sacrifice_buys(record: Dictionary) -> void:
	systems._add(systems.profile.data.run.counters, "SacrificialAltarRefreshCount", int(record.taken))
	record.taken = 0

func _free_sacrifice_refresh(record: Dictionary) -> bool:
	return bool(record.get("first_node", false)) and int(systems.profile.data.run.region) == 1 and int(systems.attributes().get("FreeRefreshInFirstRoom", 0)) > 0

func toggle_sacrifice_lock(key: String, id: int) -> Dictionary:
	if not systems.is_loot_lock_unlocked(): return systems._fail("尚未解锁遗物锁定")
	var record: Dictionary = _records().get(key, {})
	if not _valid(key) or record.is_empty() or record.get("closed", false) or str(record.kind) != "sacrifice": return systems._fail("净化已结束")
	for option in record.options:
		if int(option.id) != id: continue
		option.locked = not bool(option.get("locked", false))
		return systems._done("物品已锁定" if option.locked else "物品已解锁", id)
	return systems._fail("物品不在祭坛候选中")

func refresh_sacrifice(key: String) -> Dictionary:
	if not _valid(key): return systems._fail("祭坛不可使用")
	var record: Dictionary = _records().get(key, {})
	if record.is_empty() or record.get("closed", false) or str(record.kind) != "sacrifice": return systems._fail("净化已结束")
	var free := _free_sacrifice_refresh(record)
	if not free and int(systems.profile.data.run.counters.get("SelectRefreshTime", 0)) <= 0: return systems._fail("重选次数不足")
	_commit_sacrifice_buys(record)
	var locked: Array = record.options.filter(func(option): return bool(option.get("locked", false)))
	var exclusions: Array = record.selected.duplicate()
	exclusions.append_array(locked.map(func(option): return int(option.id)))
	var count := maxi(1, 3 + int(systems.attributes().get("BlessingPlusSelectExtraCount", 0)))
	var fresh: Array = _sacrifice_options(exclusions, maxi(0, count - locked.size()))
	var next: Array = []
	for old in record.options:
		if bool(old.get("locked", false)): next.append(old)
		elif not fresh.is_empty(): next.append(fresh.pop_front())
	next.append_array(fresh)
	record.options = next
	if not free: systems._add(systems.profile.data.run.counters, "SelectRefreshTime", -1)
	return systems._done("祭坛已重选")

func finish_sacrifice(key: String) -> Dictionary:
	var record: Dictionary = _records().get(key, {})
	if not _valid(key) or record.is_empty() or record.get("closed", false) or str(record.kind) != "sacrifice": return systems._fail("净化已结束")
	_commit_sacrifice_buys(record)
	record.closed = true
	systems._add(systems.profile.data.run.counters, "SelectLootRemainCount_Reward", -1)
	return systems._done("净化结束")

func adjust_max_health(amount: int) -> void:
	var run: Dictionary = systems.profile.data.run
	systems._add(run.counters, HP_ADJUSTMENT, amount)
	run.max_health = maxf(1, float(run.max_health) + amount)
	run.health = minf(float(run.health), float(run.max_health))

func partner_slots() -> Array:
	var counters: Dictionary = systems.profile.data.run.counters
	return counters.get(SLOTS, []) if counters.get(SLOTS, []) is Array else []

func open_partner(key: String) -> Dictionary:
	if not _valid(key): return systems._fail("伙伴技能不可选择")
	if _records().has(key): return _state(key)
	var options := _partner_options()
	if options.is_empty(): return systems._fail("可用伙伴技能不足，请先解锁伙伴")
	_records()[key] = {"kind": "partner", "options": options, "closed": false}
	return _state(key)

func _partner_options() -> Array:
	var candidates: Array = []
	var equipped: Array = partner_slots().map(func(slot): return int(slot.id))
	for row in systems.catalog.rows("MonsterPartnerData"):
		if systems.rank(systems.profile.data.partners, row.id) <= 0 or str(row.get("attack_id", "")).is_empty() or row.get("is_admin_only", false): continue
		if not equipped.has(int(row.id)): candidates.append(int(row.id))
	if candidates.size() < 2:
		candidates.clear()
		for row in systems.catalog.rows("MonsterPartnerData"):
			if systems.rank(systems.profile.data.partners, row.id) > 0 and not str(row.get("attack_id", "")).is_empty() and not row.get("is_admin_only", false): candidates.append(int(row.id))
	if candidates.size() < 2: return []
	var options: Array = []
	for slot_index in partner_slots().size():
		var slot: Dictionary = partner_slots()[slot_index]
		if int(slot.level) < 3:
			var option := _partner_option(int(slot.id), int(slot.level) + 1, "upgrade")
			option["slot"] = slot_index
			options.append(option)
	for i in 2:
		var index: int = systems.next_random(candidates.size())
		var id := int(candidates[index])
		candidates.remove_at(index)
		options.append(_partner_option(id, _new_partner_level(id), "new"))
	for id in systems.roll_pool(PARTNER_COMMON_POOL, 2):
		options.append({"id": int(id), "mode": "loot", "level": 1, "name": systems.loot_name(int(id)), "description": systems.loot_description(int(id)), "icon": "loot:" + str(id)})
	return options

func _new_partner_level(id: int) -> int:
	var count := int(systems.profile.data.run.counters.get("CurMonsterPartnerSkillSelectCout", 0))
	var row: Dictionary = systems.catalog.find("MonsterPartnerData", id)
	var rate := str(systems.catalog.find("EnemyData", int(row.get("enemy_id", id))).get("enemy_rate", ""))
	var thresholds: Array = {"Normal": [3, 6], "Elite": [4, 8], "Boss": [5, 10]}.get(rate, [2147483647, 2147483647])
	return 3 if count >= int(thresholds[1]) else 2 if count >= int(thresholds[0]) else 1

func _partner_option(id: int, level: int, mode: String) -> Dictionary:
	var source: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/partner_skills.json"))
	for skill in source.get("skills", []) if source is Dictionary else []:
		if int(skill.id) != id: continue
		var descriptions: PackedStringArray = str(skill.description).split("|")
		return {"id": id, "mode": mode, "level": level, "name": str(skill.name) + " Lv.%d" % level, "description": descriptions[clampi(level - 1, 0, descriptions.size() - 1)], "icon": str(skill.icon)}
	return {"id": id, "mode": mode, "level": level, "name": str(id), "description": "", "icon": "menu_character"}

func choose_partner(key: String, option_index: int, slot_index: int = 0) -> Dictionary:
	if not _valid(key): return systems._fail("伙伴技能不可选择")
	var record: Dictionary = _records().get(key, {})
	if record.is_empty() or record.get("closed", false) or str(record.kind) != "partner": return systems._fail("选择已完成")
	if option_index < 0 or option_index >= record.options.size(): return systems._fail("不在伙伴技能候选中")
	var option: Dictionary = record.options[option_index]
	var id := int(option.id)
	if str(option.mode) == "loot":
		var result: Dictionary = systems.add_loot(id, false)
		if not result.success: return result
	else:
		var slots: Array = partner_slots()
		if str(option.mode) == "upgrade":
			slot_index = int(option.get("slot", -1))
			if slot_index < 0 or slot_index >= slots.size() or int(slots[slot_index].id) != id or int(slots[slot_index].level) + 1 != int(option.level): return systems._fail("伙伴技能状态已变化")
		elif slots.size() < 2:
			slot_index = slots.size()
			slots.append({})
		elif slot_index < 0 or slot_index >= 2: return systems._fail("请选择替换的技能")
		slots[slot_index] = {"id": id, "level": int(option.level)}
		systems.profile.data.run.counters[SLOTS] = slots
	record.closed = true
	systems._add(systems.profile.data.run.counters, "CurMonsterPartnerSkillSelectCout", 1)
	return systems._done("已选择伙伴技能" if str(option.mode) != "loot" else systems.loot_name(id), id)

func extra_attributes() -> Dictionary:
	var result: Dictionary = {"HpAddFixed": int(systems.profile.data.run.counters.get(HP_ADJUSTMENT, 0))}
	for buff in extra_buff_ids(): systems.effects.buff_attributes(int(buff), 1, result)
	return result

func extra_buff_ids() -> Array:
	var result: Array = []
	for slot in partner_slots():
		var row: Dictionary = systems.catalog.find("MonsterPartnerData", int(slot.id))
		var levels := str(row.get("passive_buff_id_lv_array", "")).split("|")
		var level := int(slot.level)
		if level > 0 and level <= levels.size(): result.append_array(Catalog.ids(levels[level - 1]))
	return result.filter(func(id): return int(id) > 0)

static func _f32(value: float) -> float:
	return PackedFloat32Array([value])[0]
