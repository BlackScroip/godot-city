extends SceneTree

var checks := 0
var failures: Array[String] = []
var catalog := DungeonCatalog.new()
var instances: Array = []

class TestSystems extends DungeonSystems:
	func next_random(_maximum: int) -> int:
		return 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	check(catalog.load_all(), "Catalog loads")
	_event_layers()
	_message_layers()
	_reward_records()
	_source_message_chain()
	_state_changes()
	_record_restore()
	for instance in instances: instance.decorations = null
	print("BACKPACK_RECORD_RUNTIME_TEST ", JSON.stringify({"checks": checks, "passed": failures.is_empty(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func fresh(ids: Array = []):
	var systems := TestSystems.new(catalog, DungeonProfile.new())
	instances.append(systems)
	systems.profile.data.run.active = true
	for id in ids: systems.profile.data.run.inventory[str(id)] = 1
	return systems

func _record_component(id: int) -> Dictionary:
	var components = catalog.find("AbilityItems", id).get("CombineDataList", [])
	for index in components.size():
		if components[index].get("CombineDataType", "") == "RecordTrigger":
			return {"index": index, "data": components[index].Data}
	return {}

func _event_layers() -> void:
	for id in [20119, 20120, 20151, 20166, 20405, 20409, 20410, 21171, 22012, 22072]:
		var systems = fresh([id])
		var component = _record_component(id)
		var data = component.data
		var threshold = maxi(1, int(data.TriggerPercent))
		var key = "effect:%d:%d" % [id, component.index]
		var buff = DungeonCatalog.ids(data.ModifyBuff)[0]
		var counters = systems.profile.data.run.counters
		_emit_record_events(systems, data.RogueEventTriggerData, threshold - 1)
		check(int(counters.get(key + ":layers", 0)) == 0 and int(counters.get("rogue-event-buff:" + str(buff), 0)) == 0, "%d waits for its full threshold" % id)
		_emit_record_events(systems, data.RogueEventTriggerData, 1)
		check(int(counters.get(key + ":record", 0)) == threshold and int(counters.get(key + ":layers", 0)) == 1, "%d records one layer at its threshold" % id)
		check(int(counters.get("rogue-event-buff:" + str(buff), 0)) == 1, "%d applies the first numerical layer" % id)
		if threshold > 1:
			_emit_record_events(systems, data.RogueEventTriggerData, 1)
			check(int(counters.get("rogue-event-buff:" + str(buff), 0)) == 1, "%d does not add another buff before the next threshold" % id)
		var maximum = int(data.MaxLayer)
		if maximum > 0:
			_emit_record_events(systems, data.RogueEventTriggerData, (maximum + 1) * threshold)
			var buff_max = int(catalog.find("Buffs", buff).BuffData.MaxLayerNum)
			check(int(counters.get(key + ":layers", 0)) == maximum and int(counters.get("rogue-event-buff:" + str(buff), 0)) == mini(maximum, buff_max), "%d caps the display and applied layers" % id)
	var pottery = fresh([20405])
	for index in 20: pottery.effects.dispatch("DestroyDestroyableObject", "10004")
	check(int(pottery.profile.data.run.counters.get("effect:20405:1:record", 0)) == 0, "Pottery hunter ignores a different object config")
	var essence = fresh([22012])
	essence.grant_material(102, 125)
	check(int(essence.profile.data.run.counters.get("effect:22012:1:record", 0)) == 125 and int(essence.profile.data.run.counters.get("effect:22012:1:layers", 0)) == 2, "Bulk essence uses the actual resource amount and preserves a partial threshold")
	essence.effects.dispatch("ChangeResCount", "102", "1", "100")
	check(int(essence.profile.data.run.counters.get("effect:22012:1:record", 0)) == 125, "Essence gained trigger excludes spending")

func _emit_record_events(systems, trigger: Dictionary, amount: int) -> void:
	if amount <= 0: return
	var event = str(trigger.EventType)
	var p1 = str(trigger.get("Param1", ""))
	var p2 = str(trigger.get("Param2", ""))
	var p3 = str(trigger.get("Param3", ""))
	if p1 in ["", "-1"]: p1 = "0"
	if event == "ChangeResCount": systems.effects.dispatch(event, p1, p2, str(amount))
	else:
		for index in amount: systems.effects.dispatch(event, p1, p2, p3)

func _message_layers() -> void:
	for id in [20432, 20582, 20583]:
		var systems = fresh([id])
		var component = _record_component(id)
		var data = component.data
		var key = "effect:%d:%d" % [id, component.index]
		var message = str(data.MessageName)
		check(systems.effects.dispatch_message(message), "%d recognizes its source message" % id)
		check(int(systems.profile.data.run.counters.get(key + ":record", 0)) == 1, "%d defaults missing Arg1 to one" % id)
		systems.effects.dispatch_message(message, {"Arg1": "3"})
		systems.effects.dispatch_message(message, {"MsgArg1": "2"})
		systems.effects.dispatch_message(message, {"ArgName2": "Arg1", "ArgValue2": "4"})
		check(int(systems.profile.data.run.counters.get(key + ":record", 0)) == 10, "%d accepts source and runtime message argument forms" % id)
		systems.effects.dispatch_message(message, {"Arg1": "invalid"})
		check(int(systems.profile.data.run.counters.get(key + ":record", 0)) == 10, "%d rejects an invalid numeric Arg1" % id)
		if int(data.MaxLayer) > 0:
			systems.effects.dispatch_message(message, {"Arg1": "1000"})
			check(int(systems.profile.data.run.counters.get(key + ":layers", 0)) == int(data.MaxLayer), "%d enforces its source layer cap" % id)
	var systems = fresh([20432])
	var changes = [0]
	var callback = func():
		changes[0] += 1
		systems.effects.dispatch_message("Rogue_MonsterPartnerSkillUsed")
	systems.changed.connect(callback)
	systems.effects.dispatch_message("Rogue_MonsterPartnerSkillUsed")
	check(changes[0] == 1 and int(systems.profile.data.run.counters.get("effect:20432:0:record", 0)) == 1, "Message changes publish once and do not recursively count the same message")
	check(not systems.effects.dispatch_message("UnknownBackpackTestMessage"), "Unknown source messages remain unhandled")
	check(changes[0] == 1, "An unknown message does not publish a change")
	systems.changed.disconnect(callback)
	var cover = catalog.find("AbilityItems", 20119).duplicate(true)
	cover.ID = "993021"
	cover.CombineDataList[0].Data.TriggerEventType = "Message"
	cover.CombineDataList[0].Data.MessageName = "BackpackCoverFixture"
	cover.CombineDataList[0].Data.IsNewValCoverOldVal = true
	catalog.tables.AbilityItems.append(cover)
	catalog._indices.AbilityItems["993021"] = cover
	var loot = {"id": 993021, "ability_item_id": 993021, "loot_type": "ordinary", "unlock_data_id": 0}
	catalog.tables.LootData.append(loot)
	catalog._indices.LootData["993021"] = loot
	var replacement = fresh([993021])
	replacement.effects.dispatch_message("BackpackCoverFixture", {"Arg1": "50"})
	replacement.effects.dispatch_message("BackpackCoverFixture", {"Arg1": "25"})
	check(int(replacement.profile.data.run.counters.get("effect:993021:0:record", 0)) == 25 and int(replacement.profile.data.run.counters.get("rogue-event-buff:50201190", 0)) == 1, "Cover mode replaces the record and sets its absolute buff layer")

func _reward_records() -> void:
	for id in [20584, 23024]:
		var systems = fresh([id])
		var data = _record_component(id).data
		var key = "effect:%d:0" % id
		var threshold = int(data.TriggerPercent)
		var counters = systems.profile.data.run.counters
		for index in threshold - 1: systems.effects.dispatch_message(str(data.MessageName))
		check(int(counters.get("FreePurchaseAttempts", 0)) == 0, "%d waits for its reward threshold" % id)
		systems.effects.dispatch_message(str(data.MessageName))
		check(int(counters.get("FreePurchaseAttempts", 0)) == 1 and int(counters.get(key + ":used", 0)) == 1 and int(counters.get(key + ":record", 0)) == 0, "%d awards one purchase and consumes exactly one full threshold" % id)
		for activation in 10:
			for index in threshold: systems.effects.dispatch_message(str(data.MessageName))
		check(int(counters.get("FreePurchaseAttempts", 0)) == 10 and int(counters.get(key + ":used", 0)) == 10, "%d stops reward executions at its ten-use cap" % id)
		check(systems.effects.dispatch_message(str(data.MessageName)), "%d remains recognized after reaching the cap" % id)
	var bulk = fresh([20584])
	bulk.effects.dispatch_message("MonsterTrigger_20581", {"Arg1": "125"})
	var counters = bulk.profile.data.run.counters
	check(int(counters.get("FreePurchaseAttempts", 0)) == 2 and int(counters.get("effect:20584:0:used", 0)) == 1 and int(counters.get("effect:20584:0:record", 0)) == 25, "Bulk records scale the reward, preserve remainder, and count one native execution")
	bulk.effects.dispatch_message("MonsterTrigger_20581", {"argument": "25"})
	check(int(counters.get("FreePurchaseAttempts", 0)) == 3 and int(counters.get("effect:20584:0:used", 0)) == 2 and int(counters.get("effect:20584:0:record", 0)) == 0, "The saved remainder contributes to the following reward")

func _source_message_chain() -> void:
	var systems = fresh([23023, 23024])
	check(systems.add_loot(23021, false).success and systems.material(102) == 500, "Otherworld blade acquisition grants its authored five hundred essence")
	check(systems.effects.dispatch_message("Start_23021") and systems.material(102) == 500, "Blade spends ten and plant refunds ten through the emitted source message")
	check(int(systems.profile.data.run.counters.get("effect:23024:0:record", 0)) == 1, "Blade output reaches the vase record listener")
	systems.effects.dispatch_message("Start_23021")
	check(int(systems.profile.data.run.counters.get("effect:23024:0:record", 0)) == 1, "Blade cooldown blocks an immediate repeat")
	for index in 24:
		systems.effects.advance(2)
		systems.effects.dispatch_message("Start_23021")
	check(int(systems.profile.data.run.counters.get("FreePurchaseAttempts", 0)) == 1 and int(systems.profile.data.run.counters.get("effect:23024:0:used", 0)) == 1, "Twenty-five real blade activations award the vase purchase")
	systems.profile.data.materials["102"] = 499
	systems.effects.advance(2)
	systems.effects.dispatch_message("Start_23021")
	check(systems.material(102) == 499 and int(systems.profile.data.run.counters.get("effect:23024:0:record", 0)) == 0, "Blade condition stops activation below five hundred essence")

func _state_changes() -> void:
	var ordinary = [20138, 20162, 20406, 20415, 20417, 20422]
	var ids = ordinary.duplicate()
	for id in range(22011, 22202, 10): ids.append(id)
	for id in ids:
		var systems = fresh()
		check(systems.add_loot(id, false).success, "%d can be acquired before progress tracking" % id)
		var rule = systems.loot_state_change_rule(id)
		var condition = rule.ConditionList[0].Condition
		var trigger = condition.RogueEventTriggerData
		var threshold = int(condition.MinValue)
		var target = int(rule.Data.AfterAbilityItemLootId)
		systems.record_purification_event(str(trigger.EventType), str(trigger.Param1), threshold - 1, str(trigger.Param2), false)
		check(systems.rank(systems.profile.data.run.inventory, id) == 1 and systems.rank(systems.profile.data.run.inventory, target) == 0, "%d stays unchanged below its source threshold" % id)
		systems.record_purification_event(str(trigger.EventType), str(trigger.Param1), 1, str(trigger.Param2), false)
		check(systems.rank(systems.profile.data.run.inventory, id) == 0 and systems.rank(systems.profile.data.run.inventory, target) == 1, "%d transforms at the exact source threshold" % id)
		if ordinary.has(id): check(systems.purification_target(id) == 0, "%d ordinary upgrade stays outside the curse-only altar API" % id)
	var essence = fresh([20162, 20406, 20415, 20422])
	essence.grant_material(102, 999)
	check(essence.rank(essence.profile.data.run.inventory, 20162) == 1, "Real resource adapter retains the thousand-essence item below threshold")
	essence.grant_material(102, 1)
	check(essence.rank(essence.profile.data.run.inventory, 20163) == 1, "Real resource adapter completes the thousand-essence upgrade")
	essence.grant_material(102, 9000)
	check(essence.rank(essence.profile.data.run.inventory, 20407) == 1 and essence.rank(essence.profile.data.run.inventory, 20416) == 1 and essence.rank(essence.profile.data.run.inventory, 20423) == 1, "Real resource adapter completes all three ten-thousand-essence upgrades")
	var rooms = fresh([20417])
	rooms.record_node_entry_effects("other", "2", false)
	rooms.record_node_entry_effects("shop-one", "3", false)
	check(rooms.rank(rooms.profile.data.run.inventory, 20417) == 1, "Room upgrade excludes other node kinds")
	rooms.record_node_entry_effects("shop-one", "3", false)
	check(rooms.rank(rooms.profile.data.run.inventory, 20417) == 1, "Duplicate room entry cannot advance upgrade progress")
	rooms.record_node_entry_effects("shop-two", "3", false)
	check(rooms.rank(rooms.profile.data.run.inventory, 20418) == 1, "Second matching room entry completes the ordinary upgrade")
	var kills = fresh([20138])
	for index in 99: kills.record_kill(11001)
	check(kills.rank(kills.profile.data.run.inventory, 20138) == 1, "Real kill adapter retains the seed before one hundred kills")
	kills.record_kill(11001)
	check(kills.rank(kills.profile.data.run.inventory, 20139) == 1, "Real kill adapter completes the seed upgrade at one hundred kills")
	var conflict = fresh([20162, 20163])
	conflict.grant_material(102, 1000)
	check(conflict.rank(conflict.profile.data.run.inventory, 20162) == 1 and conflict.rank(conflict.profile.data.run.inventory, 20163) == 1, "A blocked upgrade restores its source item")

func _record_restore() -> void:
	var systems = fresh([20119, 20584, 20406])
	for index in 24: systems.effects.dispatch("KillEnemy", "0")
	systems.effects.dispatch_message("MonsterTrigger_20581", {"Arg1": "125"})
	systems.grant_material(102, 9999)
	var profile := DungeonProfile.new()
	check(profile.restore(JSON.parse_string(JSON.stringify(systems.profile.data))), "Record and ordinary-progress state survives JSON restore")
	var restored := TestSystems.new(catalog, profile)
	instances.append(restored)
	restored.effects.dispatch("KillEnemy", "0")
	restored.effects.dispatch_message("MonsterTrigger_20581", {"Arg1": "25"})
	restored.grant_material(102, 1)
	check(int(profile.data.run.counters.get("effect:20119:0:layers", 0)) == 1 and int(profile.data.run.counters.get("rogue-event-buff:50201190", 0)) == 1, "Restored kill progress crosses the next layer threshold")
	check(int(profile.data.run.counters.get("FreePurchaseAttempts", 0)) == 3 and int(profile.data.run.counters.get("effect:20584:0:used", 0)) == 2, "Restored reward progress retains remainder and execution count")
	check(restored.rank(profile.data.run.inventory, 20407) == 1, "Restored ordinary progress completes its upgrade")
	var legacy = fresh([20119])
	legacy.profile.data.run.counters["rogue-event-buff:50201190"] = 3
	legacy.effects.dispatch("KillEnemy", "0")
	check(int(legacy.profile.data.run.counters.get("effect:20119:0:record", 0)) == 76 and int(legacy.profile.data.run.counters.get("effect:20119:0:layers", 0)) == 3, "Old saves retain their granted layers when introducing a raw record counter")
