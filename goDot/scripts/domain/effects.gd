class_name DungeonEffects
extends RefCounted

const Catalog = preload("res://scripts/domain/catalog.gd")
var _owner: WeakRef
var systems:
	get: return _owner.get_ref()
var diagnostics: Array = []
var _event_depth = 0

func _init(owner_systems) -> void:
	_owner = weakref(owner_systems)

func _unknown(text: String) -> void:
	if not diagnostics.has(text): diagnostics.append(text)
	systems.diagnose(text)

func _empty(value) -> bool:
	return str(value) in ["", "None"]

func _sum(target: Dictionary, key, amount: float) -> void:
	if not _empty(key): target[str(key)] = float(target.get(str(key), 0.0)) + amount

func ability_attributes(id: int, count: int, target: Dictionary, path: Array = []) -> void:
	if path.has(id): return
	var row = systems.catalog.find("AbilityItems", id)
	if row.is_empty():
		_unknown("Missing ability " + str(id))
		return
	var next_path = path.duplicate()
	next_path.append(id)
	for i in range(1, 4):
		_sum(target, row.get("ModifyAttributeType" + str(i), ""), float(row.get("ModifyAttributeValue" + str(i), 0)) * count)
	if str(row.get("TriggerEventType", "")) in ["", "None"]:
		for buff in Catalog.ids(row.get("ModifyBuff", "")):
			buff_attributes(buff, count, target)
		for component in row.get("CombineDataList", []):
			if not component.get("ConditionList", []).is_empty(): continue
			var data = component.get("Data", {})
			match str(component.get("CombineDataType", "")):
				"NormalModifyRogue": _sum(target, data.get("ModifyAttributeType", ""), float(data.get("ModifyAttributeValue", 0)) * count)
				"NormalModifyBuff":
					if str(data.get("TargetType", "")) == "Player" and int(data.get("ModifyBuffChance", 0)) >= 1000:
						for buff in Catalog.ids(data.get("ModifyBuff", "")): buff_attributes(buff, count, target)
	for child in Catalog.ids(row.get("ExtraAbilityItemIDList", "")):
		ability_attributes(child, count, target, next_path)

func buff_attributes(id: int, count: int, target: Dictionary) -> void:
	var buff = systems.catalog.find("Buffs", id)
	if buff.is_empty():
		_unknown("Missing buff " + str(id))
		return
	var settings = buff.get("BuffData", {}).get("BuffSettingDataList", [])
	if str(buff.get("BuffType", "")) != "EBT_NumericalBuff" or settings.is_empty(): return
	for value in settings[0].get("BuffDataList", []):
		_sum(target, value.get("Attr", ""), float(value.get("AddValue", 0)) * count)

func acquire(id: int, path: Array = []) -> void:
	if path.has(id): return
	var row = systems.catalog.find("AbilityItems", id)
	if row.is_empty():
		_unknown("Missing acquired ability " + str(id))
		return
	var next_path = path.duplicate()
	next_path.append(id)
	if str(row.get("TriggerEventType", "")) in ["Init", "Get"]: instant(row, next_path)
	for component in row.get("CombineDataList", []):
		var data = component.get("Data", {})
		if component.get("CombineDataType", "") == "RecordTrigger" and component.get("ConditionList", []).is_empty() and str(data.get("TriggerEventType", "")) in ["Init", "Get"] and float(data.get("TriggerPercent", 0)) >= 1.0:
			instant(data, next_path)
	for child in Catalog.ids(row.get("ExtraAbilityItemIDList", "")): acquire(child, next_path)
	audit_ability(id)

func instant(row: Dictionary, path: Array = []) -> void:
	var run = systems.profile.data.run
	for i in range(1, 4):
		var attr = str(row.get("AddAttribute" + str(i), ""))
		var amount = int(row.get("AddAttributeValue" + str(i), 0))
		var id = {"Gold": 101, "MagicPoint": 102, "MineralMat": 103, "FreeCoin": 90002}.get(attr, 0)
		if id != 0:
			if amount > 0: systems.grant_material(id, amount)
			elif amount < 0: systems.spend({str(id): -amount})
		elif attr.begins_with("SelectCharaTalentRemainCount_"):
			systems.queue_character_talent_reward(attr.trim_prefix("SelectCharaTalentRemainCount_"), amount, attr.ends_with("_High"))
		elif attr.begins_with("SelectLootRemainCount_"):
			systems.queue_loot_reward(attr.trim_prefix("SelectLootRemainCount_"), amount)
		elif attr == "PlayerMaxHpDownModifyValue":
			run.max_health = maxf(1, float(run.max_health) + amount)
			run.health = minf(float(run.health), float(run.max_health))
		elif attr == "SearchPoint": systems.add_search_points(amount)
		elif not _empty(attr):
			systems._add(run.counters, attr, amount)
	for buff in Catalog.ids(row.get("AddBuff", "")): instant_buff(buff)
	for child in Catalog.ids(row.get("AddAbilityItemId", "")): acquire(child, path)
	var message = str(row.get("TriggerSendMsgData", {}).get("MsgName", ""))
	if message == "Rogue_ClearMagicPoint": systems.profile.data.materials["102"] = 0
	elif message == "Rogue_AddNewLootToInventory":
		var choices = Catalog.ids(row.TriggerSendMsgData.get("ArgValue1", "")).filter(func(id): return systems.can_add_loot(id))
		if not choices.is_empty(): systems.add_loot(choices[systems.next_random(choices.size())], false)
	elif not message.is_empty(): _unknown("Ability message " + message)

func instant_buff(id: int, layers: int = 1) -> void:
	var buff = systems.catalog.find("Buffs", id)
	if buff.is_empty():
		_unknown("Missing instant buff " + str(id))
		return
	var data = buff.get("BuffData", {})
	var settings = data.get("BuffSettingDataList", [])
	var level = settings[0] if not settings.is_empty() else {}
	var run = systems.profile.data.run
	match str(buff.get("BuffType", "")):
		"EBT_SpecialBuffHP":
			var damage = systems.catalog.find("DamageValues", int(level.get("DamageDefId", 0)))
			var heal = float(damage.get("DamageFixValue", 0)) if damage.get("DamageType", "") == "Heal" else 0.0
			if damage.get("DamageType", "") == "Heal":
				for suffix in ["", "2"]:
					var attr = str(damage.get("DamageAttribType" + suffix, ""))
					var basis = float(run.max_health) if attr == "MaxHp" else float(run.health) if attr in ["CurHp", "Hp"] else 0.0
					heal += basis * float(damage.get("DamageMulValue" + suffix, 0)) / 1000.0
			if data.get("ChangeMode", "") != "DamageDef": heal += float(run.max_health) * float(level.get("MaxHpPercentChange", 0)) / 1000.0
			run.health = clampf(float(run.health) + heal * layers, 0, float(run.max_health))
		"EBT_SpecialBuffArmor":
			run.armor = maxf(0, float(run.armor) + (float(level.get("FixValueChange", 0)) + float(run.max_health) * float(level.get("MaxHpPercentChange", 0)) / 1000.0) * layers)
		_:
			# Host consumes battle buffs; the queue is part of the same saved transaction.
			var pending = run.counters.get("combat_buff_queue", [])
			pending.append({"id": str(id), "layers": layers})
			run.counters["combat_buff_queue"] = pending
			if id == 70101061: run.counters["node-persistent-buff:70101061"] = mini(layers, maxi(1, int(data.get("MaxLayerNum", 1))))

func dispatch(event: String, param1: String = "", param2: String = "", param3: String = "") -> void:
	if not systems.profile.data.run.active: return
	if _event_depth >= 16:
		_unknown("Ability event recursion exceeds 16")
		return
	_event_depth += 1
	var sources = {}
	var roots = systems.ability_sources()
	for id in roots: _append_event_source(int(id), int(roots[id]), sources)
	for id in sources:
		var ability = systems.catalog.find("AbilityItems", int(id))
		if str(ability.get("TriggerEventType", "")) == "RogueEventType" and _event_matches(ability.get("RogueEventTriggerData", {}), event, param1, param2, param3):
			for application in int(sources[id]): instant(ability)
		for index in ability.get("CombineDataList", []).size():
			var component = ability.CombineDataList[index]
			var data = component.get("Data", {})
			var trigger = data.get("RogueEventTriggerData", {})
			if str(data.get("TriggerEventType", "")) != "RogueEventType" or not _event_matches(trigger, event, param1, param2, param3): continue
			if component.get("CombineDataType", "") == "StateChange": continue
			var key = "effect:" + str(id) + ":" + str(index)
			var counters = systems.profile.data.run.counters
			var now = int(counters.get("effect_clock_ms", 0))
			if now < int(counters.get(key + ":next", 0)): continue
			var used = int(counters.get(key + ":used", 0))
			var maximum = int(data.get("MaxEffectCount", -1))
			if (maximum > 0 if component.get("CombineDataType", "") == "RecordTrigger" else maximum >= 0) and used >= maximum: continue
			if not _conditions(component.get("ConditionList", []), key): continue
			var probability = float(data.get("TriggerPercent", 1.0))
			if systems.next_random(1000000) >= int(clampf(probability, 0, 1) * 1000000): continue
			if component.get("CombineDataType", "") in ["NormalTrigger", "RecordTrigger"]:
				instant(data)
				for buff in Catalog.ids(data.get("ModifyBuff", "")):
					var row = systems.catalog.find("Buffs", buff)
					if row.get("BuffType", "") == "EBT_NumericalBuff":
						var maximum_layers = maxi(1, int(row.get("BuffData", {}).get("MaxLayerNum", 1)))
						var counter = "rogue-event-buff:" + str(buff)
						counters[counter] = mini(maximum_layers, int(counters.get(counter, 0)) + int(sources[id]))
					else: instant_buff(buff, int(sources[id]))
				counters[key + ":used"] = used + 1
				counters[key + ":next"] = now + maxi(0, int(float(data.get("TimeInternal", 0)) * 1000))
			else: _unknown("Event component " + str(component.get("CombineDataType", "")) + " ability " + str(id))
	_event_depth -= 1

func _append_event_source(id: int, count: int, target: Dictionary, path: Array = []) -> void:
	if path.has(id): return
	target[str(id)] = int(target.get(str(id), 0)) + count
	var next_path = path.duplicate()
	next_path.append(id)
	for child in Catalog.ids(systems.catalog.find("AbilityItems", id).get("ExtraAbilityItemIDList", "")): _append_event_source(child, count, target, next_path)

func _event_matches(trigger: Dictionary, event: String, param1: String, param2: String, param3: String) -> bool:
	if str(trigger.get("EventType", "")) != event: return false
	for pair in [["Param1", param1], ["Param2", param2], ["Param3", param3]]:
		var expected = str(trigger.get(pair[0], ""))
		if expected in ["", "-1", pair[1]]: continue
		if event == "ChangeResCount" and pair[0] == "Param1" and expected.is_valid_int() and systems._alias(int(expected)) == int(pair[1]): continue
		if expected == "0" and event in ["EnterNode", "EnterNewNormalShop", "CompleteRegion", "StartNewRun", "CharaRevive"]: continue
		return false
	return true

func advance(seconds: float) -> void:
	var counters = systems.profile.data.run.counters
	counters["effect_clock_ms"] = int(counters.get("effect_clock_ms", 0)) + int(maxf(0, seconds) * 1000)

func _conditions(conditions: Array, key: String) -> bool:
	for index in conditions.size():
		var wrapper = conditions[index]
		var kind = str(wrapper.get("ConditionType", ""))
		var condition = wrapper.get("Condition", {})
		if kind == "RecordValue":
			var record_key = key + ":condition:" + str(index)
			systems._add(systems.profile.data.run.counters, record_key, 1)
			var value = int(systems.profile.data.run.counters[record_key])
			if value < int(condition.get("MinValue", 0)) or value > int(condition.get("MaxValue", 2147483647)): return false
		else:
			_unknown("Uninterpreted ability condition " + kind)
			return false
	return true

func audit_ability(id: int) -> void:
	var ability = systems.catalog.find("AbilityItems", id)
	for component in ability.get("CombineDataList", []):
		var kind = str(component.get("CombineDataType", ""))
		if kind not in ["NormalModifyRogue", "NormalModifyBuff", "NormalTrigger", "RecordTrigger", "StateChange"]:
			_unknown("Uninterpreted ability " + str(id) + " component " + kind)
		for condition in component.get("ConditionList", []):
			if str(condition.get("ConditionType", "")) != "RecordValue": _unknown("Ability " + str(id) + " condition " + str(condition.get("ConditionType", "")))
