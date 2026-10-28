class_name DungeonEffects
extends RefCounted

const Catalog = preload("res://scripts/domain/catalog.gd")
var _owner: WeakRef
var systems:
	get: return _owner.get_ref()
var diagnostics: Array = []
var _event_depth = 0
var _dispatch_dirty := false
var _publish_changes := false
var _publishing_changes := false
var _active_messages: Dictionary = {}

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
	var description_state = preload("res://scripts/domain/ability_descriptions.gd").new(systems)
	var factor = description_state.effect_factor(row, count)
	for i in range(1, 4):
		_sum(target, row.get("ModifyAttributeType" + str(i), ""), float(row.get("ModifyAttributeValue" + str(i), 0)) * factor)
	if str(row.get("TriggerEventType", "")) in ["", "None"]:
		for buff in Catalog.ids(row.get("ModifyBuff", "")):
			buff_attributes(buff, description_state.capped_buff_layers(buff, factor), target)
		for component in row.get("CombineDataList", []):
			if not component.get("ConditionList", []).is_empty(): continue
			var data = component.get("Data", {})
			var component_count = description_state.component_factor(row, data, count) if bool(row.get("EnableCaculateAttributeSource", false)) else count
			match str(component.get("CombineDataType", "")):
				"NormalModifyRogue": _sum(target, data.get("ModifyAttributeType", ""), float(data.get("ModifyAttributeValue", 0)) * component_count)
				"NormalModifyBuff":
					if str(data.get("TargetType", "")) == "Player" and int(data.get("ModifyBuffChance", 0)) >= 1000:
						for buff in Catalog.ids(data.get("ModifyBuff", "")): buff_attributes(buff, description_state.capped_buff_layers(buff, component_count), target)
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
		if component.get("CombineDataType", "") in ["NormalTrigger", "RecordTrigger"] and component.get("ConditionList", []).is_empty() and str(data.get("TriggerEventType", "")) in ["Init", "Get"]:
			instant(data, next_path)
	for child in Catalog.ids(row.get("ExtraAbilityItemIDList", "")): acquire(child, next_path)
	audit_ability(id)

func instant(row: Dictionary, path: Array = [], factor: int = 1) -> void:
	var run = systems.profile.data.run
	for i in range(1, 4):
		var attr = str(row.get("AddAttribute" + str(i), ""))
		var amount = int(row.get("AddAttributeValue" + str(i), 0)) * factor
		if _empty(attr) or amount == 0: continue
		var id = {"Gold": 101, "MagicPoint": 102, "MineralMat": 103, "FreeCoin": 90002}.get(attr, 0)
		if id != 0:
			if amount > 0:
				systems.grant_material(id, amount)
				_dispatch_dirty = true
			elif systems.spend({str(id): -amount}): _dispatch_dirty = true
		elif attr.begins_with("SelectCharaTalentRemainCount_"):
			systems.queue_character_talent_reward(attr.trim_prefix("SelectCharaTalentRemainCount_"), amount, attr.ends_with("_High"))
			_dispatch_dirty = true
		elif attr.begins_with("SelectLootRemainCount_"):
			systems.queue_loot_reward(attr.trim_prefix("SelectLootRemainCount_"), amount)
			_dispatch_dirty = true
		elif attr == "PlayerMaxHpDownModifyValue":
			preload("res://scripts/domain/room_choices.gd").new(systems).adjust_max_health(amount)
			_dispatch_dirty = true
		elif attr == "SearchPoint":
			var before = systems.search_point_count()
			systems.add_search_points(amount)
			_dispatch_dirty = _dispatch_dirty or before != systems.search_point_count()
		else: _set_counter(attr, int(run.counters.get(attr, 0)) + amount)
	for buff in Catalog.ids(row.get("AddBuff", "")): instant_buff(buff, factor)
	for child in Catalog.ids(row.get("AddAbilityItemId", "")): acquire(child, path)
	var message_data: Dictionary = row.get("TriggerSendMsgData", {})
	var message = str(message_data.get("MsgName", ""))
	if message == "Rogue_ClearMagicPoint":
		_dispatch_dirty = _dispatch_dirty or systems.material(102) != 0
		systems.profile.data.materials["102"] = 0
	elif message == "Rogue_AddNewLootToInventory":
		var choices = Catalog.ids(row.TriggerSendMsgData.get("ArgValue1", "")).filter(func(id): return systems.can_add_loot(id))
		if not choices.is_empty():
			systems.add_loot(choices[systems.next_random(choices.size())], false)
			_dispatch_dirty = true
	elif not message.is_empty() and not dispatch_message(message, message_data): _unknown("Ability message " + message)

func instant_buff(id: int, layers: int = 1) -> void:
	var buff = systems.catalog.find("Buffs", id)
	if buff.is_empty():
		_unknown("Missing instant buff " + str(id))
		return
	var data = buff.get("BuffData", {})
	var settings = data.get("BuffSettingDataList", [])
	var level = settings[0] if not settings.is_empty() else {}
	var run = systems.profile.data.run
	var before_health = float(run.health)
	var before_armor = float(run.armor)
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
			_dispatch_dirty = true
			if id == 70101061: run.counters["node-persistent-buff:70101061"] = mini(layers, maxi(1, int(data.get("MaxLayerNum", 1))))
	_dispatch_dirty = _dispatch_dirty or before_health != float(run.health) or before_armor != float(run.armor)

func dispatch(event: String, param1: String = "", param2: String = "", param3: String = "") -> void:
	if not systems.profile.data.run.active: return
	if systems.get("extra_challenges") != null:
		systems.extra_challenges.record_event(event, param1, param2, param3)
	if not _begin_dispatch(): return
	var sources = _event_sources()
	for id in sources:
		var ability = systems.catalog.find("AbilityItems", int(id))
		if str(ability.get("TriggerEventType", "")) == "RogueEventType" and _event_matches(ability.get("RogueEventTriggerData", {}), event, param1, param2, param3):
			for application in int(sources[id]): instant(ability)
		for index in ability.get("CombineDataList", []).size():
			var component = ability.CombineDataList[index]
			var data = component.get("Data", {})
			if str(data.get("TriggerEventType", "")) != "RogueEventType" or not _event_matches(data.get("RogueEventTriggerData", {}), event, param1, param2, param3): continue
			var amount = int(param3) if event == "ChangeResCount" and param3.is_valid_int() else 1
			_trigger_component(component, "effect:" + str(id) + ":" + str(index), int(sources[id]), amount)
	_end_dispatch()

func dispatch_message(message: String, context: Dictionary = {}) -> bool:
	if not systems.profile.data.run.active or message.is_empty(): return false
	if _active_messages.has(message): return true
	if not _begin_dispatch(true): return false
	_active_messages[message] = true
	var matched := false
	var amount = _message_record_amount(context)
	var sources = _event_sources()
	for id in sources:
		var ability = systems.catalog.find("AbilityItems", int(id))
		if str(ability.get("TriggerEventType", "")) == "Message" and str(ability.get("MessageName", "")) == message:
			matched = true
			for application in int(sources[id]): instant(ability)
		for index in ability.get("CombineDataList", []).size():
			var component = ability.CombineDataList[index]
			var data = component.get("Data", {})
			if str(data.get("TriggerEventType", "")) != "Message" or str(data.get("MessageName", "")) != message: continue
			matched = true
			if component.get("CombineDataType", "") == "RecordTrigger" and amount == null: continue
			_trigger_component(component, "effect:" + str(id) + ":" + str(index), int(sources[id]), int(amount) if amount != null else 1)
	_end_dispatch()
	_active_messages.erase(message)
	return matched

func _message_record_amount(context: Dictionary):
	for key in ["Arg1", "MsgArg1", "argument"]:
		if context.has(key): return int(str(context[key])) if str(context[key]).is_valid_int() else null
	for index in range(1, 4):
		if str(context.get("ArgName" + str(index), "")) == "Arg1":
			var value = str(context.get("ArgValue" + str(index), ""))
			return int(value) if value.is_valid_int() else null
	return 1

func _begin_dispatch(publish_changes := false) -> bool:
	if _event_depth >= 16:
		_unknown("Ability event recursion exceeds 16")
		return false
	if _event_depth == 0:
		_dispatch_dirty = false
		_publish_changes = false
	_publish_changes = _publish_changes or publish_changes
	_event_depth += 1
	return true

func _end_dispatch() -> void:
	_event_depth -= 1
	if _event_depth > 0 or not _publish_changes or not _dispatch_dirty or _publishing_changes: return
	_publishing_changes = true
	systems._done()
	_publishing_changes = false

func _event_sources() -> Dictionary:
	var sources = {}
	var roots = systems.ability_sources()
	for id in roots: _append_event_source(int(id), int(roots[id]), sources)
	return sources

func _trigger_component(component: Dictionary, key: String, count: int, amount: int) -> void:
	var kind = str(component.get("CombineDataType", ""))
	if kind == "StateChange": return
	if kind not in ["NormalTrigger", "RecordTrigger"]:
		_unknown("Event component " + kind + " " + key)
		return
	var data: Dictionary = component.get("Data", {})
	var counters: Dictionary = systems.profile.data.run.counters
	if kind == "RecordTrigger":
		_record_trigger(component, key, amount)
		return
	var now = int(counters.get("effect_clock_ms", 0))
	var used = int(counters.get(key + ":used", 0))
	var maximum = int(data.get("MaxEffectCount", -1))
	if now < int(counters.get(key + ":next", 0)) or (maximum >= 0 and used >= maximum): return
	if not _conditions(component.get("ConditionList", []), key): return
	var probability = float(data.get("TriggerPercent", 1.0))
	if probability < 1.0 and systems.next_random(1000000) >= int(clampf(probability, 0, 1) * 1000000): return
	_set_counter(key + ":used", used + 1)
	_set_counter(key + ":next", now + maxi(0, int(float(data.get("TimeInternal", 0)) * 1000)))
	instant(data)
	_apply_trigger_buffs(data, count, false)

func _record_trigger(component: Dictionary, key: String, amount: int) -> void:
	var data: Dictionary = component.get("Data", {})
	var counters: Dictionary = systems.profile.data.run.counters
	var threshold = maxi(1, int(data.get("TriggerPercent", 1)))
	var record = int(counters.get(key + ":record", _legacy_record(data, key, threshold)))
	record = amount if bool(data.get("IsNewValCoverOldVal", false)) else record + amount
	_set_counter(key + ":record", record)
	var layers = int(record / threshold)
	var maximum_layer = int(data.get("MaxLayer", -1))
	_set_counter(key + ":layers", mini(layers, maximum_layer) if maximum_layer >= 0 else layers)
	var used = int(counters.get(key + ":used", 0))
	var maximum = int(data.get("MaxEffectCount", -1))
	var factor = mini(layers, maxi(0, maximum - used)) if maximum > 0 else mini(layers, maximum_layer) if maximum_layer >= 0 else layers
	if factor <= 0 or not _conditions(component.get("ConditionList", []), key): return
	var has_action = not _empty(data.get("TriggerSendMsgData", {}).get("MsgName", ""))
	for index in range(1, 4): has_action = has_action or not _empty(data.get("AddAttribute" + str(index), ""))
	# Native RecordTrigger consumes only full thresholds and records one execution.
	if has_action and bool(data.get("RecordValSetZero", false)):
		record = maxi(0, record - factor * threshold)
		_set_counter(key + ":record", record)
		layers = int(record / threshold)
		_set_counter(key + ":layers", mini(layers, maximum_layer) if maximum_layer >= 0 else layers)
	if has_action and maximum > 0: _set_counter(key + ":used", used + 1)
	instant(data, [], factor)
	_apply_trigger_buffs(data, factor, true)

func _legacy_record(data: Dictionary, key: String, threshold: int) -> int:
	var counters: Dictionary = systems.profile.data.run.counters
	if bool(data.get("RecordValSetZero", false)): return 0
	var layers = int(counters.get(key + ":layers", 0))
	for buff in Catalog.ids(data.get("ModifyBuff", "")):
		layers = maxi(layers, int(counters.get("rogue-event-buff:" + str(buff), 0)))
	return layers * threshold

func _apply_trigger_buffs(data: Dictionary, layers: int, absolute: bool) -> void:
	var counters: Dictionary = systems.profile.data.run.counters
	for buff in Catalog.ids(data.get("ModifyBuff", "")):
		var row = systems.catalog.find("Buffs", buff)
		if row.get("BuffType", "") == "EBT_NumericalBuff":
			var maximum = int(row.get("BuffData", {}).get("MaxLayerNum", 1))
			var key = "rogue-event-buff:" + str(buff)
			var value = layers if absolute else int(counters.get(key, 0)) + layers
			_set_counter(key, mini(maximum, value) if maximum > 0 else value)
		else: instant_buff(buff, layers)

func _set_counter(key: String, value: int) -> void:
	var counters: Dictionary = systems.profile.data.run.counters
	if int(counters.get(key, 0)) != value: _dispatch_dirty = true
	counters[key] = value

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
		if event == "ChangeResCount" and pair[0] == "Param3" and expected == "0": continue
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
			_set_counter(record_key, int(systems.profile.data.run.counters.get(record_key, 0)) + 1)
			var value = int(systems.profile.data.run.counters[record_key])
			if value < int(condition.get("MinValue", 0)) or value > int(condition.get("MaxValue", 2147483647)): return false
		elif kind == "Random":
			if systems.next_random(1000) >= int(condition.get("Value", 0)): return false
		elif kind == "NormalValue":
			var attr = str(condition.get("RogueAttribute", ""))
			var value = float(systems.material(102)) if attr == "MagicPoint" else float(systems.attributes().get(attr, 0))
			var target = float(condition.get("Value", 0))
			match str(condition.get("ConditionType", "")):
				"ECT_GreaterEqual":
					if value < target: return false
				"ECT_LessEqual":
					if value > target: return false
				"ECT_Equal":
					if value != target: return false
				_: return false
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
			if str(condition.get("ConditionType", "")) not in ["RecordValue", "NormalValue", "Random"]: _unknown("Ability " + str(id) + " condition " + str(condition.get("ConditionType", "")))
