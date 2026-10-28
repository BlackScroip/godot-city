extends SceneTree

const REPORT_PATH := "res://reports/adventure-complete-rules-20261028.json"
const SOURCE_PATH := "res://assets/data/AdvantureEventData.json"
const MATERIAL_IDS := [101, 102, 103, 90002]
const COUNTER_KEYS := ["SearchPoint", "SearchPointMax", "RevivalRemainCount", "SelectRefreshTime"]

var checks := 0
var failures: Array[String] = []
var catalog := DungeonCatalog.new()
var source: Array = []
var raw: Dictionary = {}
var cases: Array = []
var coverage := {"templates": 0, "enabled_templates": 0, "select_options": 0, "blocked_placeholder_options": 0, "gamble_stages": 0, "gamble_successes": 0, "gamble_failures": 0, "gamble_exits": 0, "unreachable_native_failures": [], "synthetic_failure_branches": 0, "complete_gamble_paths": 0, "condition_boundaries": 0}

class EventSystems extends DungeonSystems:
	var gamble_roll := 0
	var gamble_draws: Array = []
	var delivered: Array = []

	func next_random(maximum: int) -> int:
		var value := super.next_random(maximum)
		if maximum == 101:
			gamble_draws.append({"maximum": maximum, "magic": material(102), "max_health": float(profile.data.run.max_health)})
			return gamble_roll
		return value

	func add_loot(id: int, notify: bool = true) -> Dictionary:
		var result := super.add_loot(id, notify)
		delivered.append({"id": id, "success": bool(result.success)})
		return result

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	check(catalog.load_all(), "APK catalog loads")
	source = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_PATH))
	for table in ["AbilityItems", "LootData", "Buffs", "DamageValues"]:
		raw[table] = {}
		for row in JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/" + table + ".json")):
			var id := int(row.get("ID", row.get("Id", row.get("id", 0))))
			raw[table][id] = row
	check(source.size() == 71, "Reference APK contains 71 event templates")
	check(source.filter(func(row): return row.IsEnable).size() == 61, "Reference APK enables 61 event templates")
	_test_generation()
	for row in source:
		coverage.templates += 1
		if row.IsEnable: coverage.enabled_templates += 1
		if row.RuleType == "SelectType":
			for index in row.TypeData.OptionList.size():
				coverage.select_options += 1
				_exercise(row, index, "select")
				_test_gate(row, index)
		else:
			for index in row.TypeData.GambleOptionList.size():
				coverage.gamble_stages += 1
				_exercise(row, index, "success")
				var option: Dictionary = row.TypeData.GambleOptionList[index]
				if int(option.Gamble_SuccessChance) < 100:
					_exercise(row, index, "failure")
				else:
					coverage.unreachable_native_failures.append(int(option.GambleOptionDataID))
					_test_synthetic_failure(row, index)
				_exercise(row, index, "exit")
				_test_gate(row, index)
			_test_complete_path(row)
	_test_probability_boundaries()
	_test_loot_exchanges()
	_test_reentrant_resource_spent()
	_test_reentrant_acknowledgement()
	var report := {"checks": checks, "passed": failures.is_empty(), "failures": failures, "coverage": coverage, "source_table_sha256": FileAccess.get_sha256(SOURCE_PATH), "source_apk_sha256": "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505", "scope": "Extracted APK configuration plus local Godot domain execution; no original APK runtime claim", "cases": cases}
	var output := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify(report, "\t") + "\n")
		output.close()
	else:
		check(false, "Could not write event test report")
	print("ADVENTURE_COMPLETE_RULES_TEST ", JSON.stringify({"checks": checks, "passed": failures.is_empty(), "failure_count": failures.size(), "failures": failures.slice(0, 30), "coverage": coverage, "report": REPORT_PATH}))
	quit(0 if failures.is_empty() else 1)

func fresh() -> EventSystems:
	var systems := EventSystems.new(catalog, DungeonProfile.new())
	systems.begin_run(602810, 1, 500)
	systems.profile.data.materials["102"] = 10000
	systems.profile.data.run.health = 100.0
	systems.profile.data.run.armor = 7.0
	systems.profile.data.run.counters.SearchPoint = 1
	return systems

func state(systems: EventSystems, row: Dictionary, index: int = 0) -> Dictionary:
	var result := {"key": "event-audit", "event_id": int(row.Id), "step": index if row.RuleType == "GambleType" else 0, "finished": false, "result": ""}
	systems.profile.data.run.events.append(result)
	return result

func clone(systems: EventSystems, label: String) -> EventSystems:
	var profile := DungeonProfile.new()
	check(profile.restore(JSON.parse_string(_snapshot(systems))), label + ": JSON profile restores")
	var restored := EventSystems.new(catalog, profile)
	restored.gamble_roll = systems.gamble_roll
	check(_snapshot(restored) == _snapshot(systems), label + ": JSON preserves complete persisted state")
	return restored

func _snapshot(systems: EventSystems) -> String:
	# JSON restores whole numbers as floats; compare their canonical persisted values.
	return JSON.stringify(JSON.parse_string(JSON.stringify(systems.profile.data)))

func _prepare(systems: EventSystems, gate: Dictionary) -> bool:
	var kind := int(gate.get("unlock_condition_type", 0))
	var id := int(gate.get("unlock_param1", 0))
	var low := int(gate.get("unlock_param2", 0))
	var high := int(gate.get("unlock_param3", 0))
	if kind == 1000:
		if id <= 0: return false
		for loot in raw.LootData.values():
			if int(loot.ability_item_id) == id:
				systems.profile.data.run.inventory[str(int(loot.id))] = 1
				return true
		check(false, "Missing held-ability fixture for " + str(id))
		return false
	if kind == 1010: systems.profile.data.materials[str({1: 101, 2: 102, 3: 103}.get(id, id))] = maxi(10000, low)
	if kind == 9101:
		systems.profile.data.run.max_health = clampf(500.0, low, high)
		systems.profile.data.run.health = minf(100.0, float(systems.profile.data.run.max_health))
	if kind == 9102:
		if id == 8000: systems.profile.data.materials["102"] = clampi(10000, low, high)
		if id == 8013: systems.profile.data.run.counters.SearchPoint = low
	return true

func _tokens(expression) -> Array:
	var result: Array = []
	var parser := RegEx.new()
	parser.compile("([0-9]+)(?::([0-9]+))?")
	for found in parser.search_all(str(expression)):
		var count := 1 if found.get_string(2).is_empty() else int(found.get_string(2))
		for index in count: result.append(int(found.get_string(1)))
	return result

func _ledger(systems: EventSystems) -> Dictionary:
	var run: Dictionary = systems.profile.data.run
	var counters := {}
	var materials := {}
	for key in COUNTER_KEYS: counters[key] = int(run.counters.get(key, 0))
	for id in MATERIAL_IDS: materials[id] = systems.material(id)
	return {"materials": materials, "health": float(run.health), "max_health": float(run.max_health), "armor": float(run.armor), "counters": counters, "inventory": run.inventory.duplicate(true), "touched_loot": [], "removed_loot": [], "delivered": [], "resource_events": [], "reward_qualities": run.rewards.map(func(reward): return str(reward.quality)), "talent_qualities": run.get("talent_rewards", []).map(func(reward): return {"quality": str(reward.quality), "max_level": bool(reward.max_level)})}

# Expectations read authored ability/loot fields independently of event execution.
func _expect_ability(expected: Dictionary, id: int) -> void:
	var ability: Dictionary = raw.AbilityItems.get(id, {})
	check(not ability.is_empty(), "Authored event ability exists: " + str(id))
	for slot in range(1, 4):
		var field := str(ability.get("AddAttribute" + str(slot), "None"))
		var amount := int(ability.get("AddAttributeValue" + str(slot), 0))
		if field in ["", "None"]: continue
		var material_id := int({"Gold": 101, "MagicPoint": 102, "MineralMat": 103, "FreeCoin": 90002}.get(field, 0))
		if material_id > 0:
			expected.materials[material_id] += amount
			if amount != 0: expected.resource_events.append({"type": "resource_gained" if amount > 0 else "resource_spent", "id": material_id, "amount": absi(amount)})
		elif field == "PlayerMaxHpDownModifyValue":
			expected.max_health = maxf(1.0, float(expected.max_health) + amount)
			expected.health = minf(float(expected.health), float(expected.max_health))
		elif field.begins_with("SelectLootRemainCount_"):
			for index in amount: expected.reward_qualities.append(field.trim_prefix("SelectLootRemainCount_"))
		elif field.begins_with("SelectCharaTalentRemainCount_"):
			var quality := field.trim_prefix("SelectCharaTalentRemainCount_")
			for index in amount: expected.talent_qualities.append({"quality": quality, "max_level": quality == "High"})
		elif field == "SearchPoint":
			expected.counters.SearchPoint = clampi(int(expected.counters.SearchPoint) + amount, 0, 3 + int(expected.counters.SearchPointMax))
		elif expected.counters.has(field):
			expected.counters[field] += amount
		else:
			check(false, "Unmodeled authored event attribute: " + field)
	for buff_id in _tokens(ability.get("AddBuff", "")):
		var buff: Dictionary = raw.Buffs[buff_id]
		var setting: Dictionary = buff.BuffData.BuffSettingDataList[0]
		if buff.BuffType == "EBT_SpecialBuffHP":
			var damage: Dictionary = raw.DamageValues[int(setting.DamageDefId)]
			check(damage.DamageType == "Heal" and int(damage.DamageMulValue) == 0 and int(damage.DamageMulValue2) == 0, "Event heal fixture uses authored fixed healing")
			expected.health = minf(float(expected.max_health), float(expected.health) + float(damage.DamageFixValue))
		elif buff.BuffType == "EBT_SpecialBuffArmor":
			expected.armor += float(setting.FixValueChange) + float(expected.max_health) * float(setting.MaxHpPercentChange) / 1000.0
		else:
			check(false, "Unmodeled authored event buff: " + str(buff_id))
	check(str(ability.get("AddAbilityItemId", "")).is_empty(), "Instant event fixture has no nested acquired ability: " + str(id))
	check(str(ability.get("TriggerSendMsgData", {}).get("MsgName", "")).is_empty(), "Instant event fixture has no unmodeled message: " + str(id))

func _expect_rewards(expected: Dictionary, abilities, loot) -> void:
	for id in _tokens(abilities): _expect_ability(expected, id)
	for id in _tokens(loot):
		var row: Dictionary = raw.LootData[id]
		var ability: Dictionary = raw.AbilityItems[int(row.ability_item_id)]
		var held := int(expected.inventory.get(str(id), 0))
		var accepted := held < maxi(1, int(ability.get("MaxHaveCount", 1)))
		expected.delivered.append({"id": id, "success": accepted})
		if not expected.touched_loot.has(id): expected.touched_loot.append(id)
		if not accepted: continue
		for previous in _tokens(ability.get("RejectIdArray", "")):
			if expected.inventory.has(str(previous)):
				expected.removed_loot.append(previous)
				expected.inventory.erase(str(previous))
		var instant := str(ability.get("TriggerEventType", "")) in ["Init", "Get"]
		if not (instant and ability.get("IsTriggerFinishCost", false)): expected.inventory[str(id)] = held + 1
		if instant: _expect_ability(expected, int(row.ability_item_id))

func _assert_ledger(systems: EventSystems, expected: Dictionary, label: String) -> void:
	var run: Dictionary = systems.profile.data.run
	for id in MATERIAL_IDS: check(systems.material(id) == int(expected.materials[id]), label + ": exact resource balance " + str(id))
	for field in ["health", "max_health", "armor"]: check(is_equal_approx(float(run[field]), float(expected[field])), label + ": exact " + field)
	for key in COUNTER_KEYS: check(int(run.counters.get(key, 0)) == int(expected.counters[key]), label + ": exact counter " + key)
	for id in expected.touched_loot:
		check(int(run.inventory.get(str(id), 0)) == int(expected.inventory.get(str(id), 0)), label + ": exact inventory reward count " + str(id))
		check(systems.profile.data.discovered_loot.has(id), label + ": reward is discovered " + str(id))
	for id in expected.removed_loot: check(int(run.inventory.get(str(id), 0)) == 0, label + ": exchanged predecessor is removed " + str(id))
	check(systems.delivered == expected.delivered, label + ": every authored loot grant succeeds up to its source cap")
	check(run.rewards.map(func(reward): return str(reward.quality)) == expected.reward_qualities, label + ": exact loot-choice reward count and quality")
	check(run.get("talent_rewards", []).map(func(reward): return {"quality": str(reward.quality), "max_level": bool(reward.max_level)}) == expected.talent_qualities, label + ": exact talent-choice reward count and quality")
	for reward in run.rewards: check(not reward.choices.is_empty() and reward.choices.size() == int(reward.candidate_count), label + ": reward candidates are materialized")
	check(systems.diagnostics.is_empty(), label + ": no unimplemented effect diagnostic")

func _exercise(row: Dictionary, index: int, mode: String, synthetic: bool = false) -> void:
	var gamble: bool = row.RuleType == "GambleType"
	var options: Array = row.TypeData.GambleOptionList if gamble else row.TypeData.OptionList
	var option: Dictionary = options[index]
	var choice := -1 if mode == "exit" else int(option.GambleOptionDataID if gamble else option.OptionDataId)
	var label := "%d/%d/%s%s" % [int(row.Id), index, mode, "/synthetic" if synthetic else ""]
	var start_checks := checks
	var start_failures := failures.size()
	var systems := fresh()
	var allowed := _prepare(systems, option.get("UnlockData", {}))
	var encounter := state(systems, row, index)
	var saved := _snapshot(systems)
	var view := systems.event_view(encounter)
	check(_snapshot(systems) == saved, label + ": opening event has no state or RNG effects")
	var expected_choices: Array = [int(option.GambleOptionDataID), -1] if gamble else options.map(func(value): return int(value.OptionDataId))
	check(view.choices.map(func(value): return int(value.id)) == expected_choices, label + ": exact visible source choices")
	check(not systems.resolve_event("event-audit", 99999999).success and _snapshot(systems) == saved, label + ": unknown choice is immutable")
	check(not systems.acknowledge_event("event-audit").success and _snapshot(systems) == saved, label + ": unfinished event cannot be acknowledged")
	if not allowed and mode != "exit":
		coverage.blocked_placeholder_options += 1
		check(not row.IsEnable, label + ": placeholder requirement appears only in a disabled APK template")
		check(not view.choices[index].enabled, label + ": placeholder cannot be selected")
		check(not systems.resolve_event("event-audit", choice).success and _snapshot(systems) == saved, label + ": placeholder fails without payment or rewards")
		clone(systems, label)
		cases.append({"event": int(row.Id), "enabled": bool(row.IsEnable), "option": choice, "mode": mode, "unreachable_placeholder": true, "checks": checks - start_checks, "passed": failures.size() == start_failures})
		return
	if gamble and mode != "exit": systems.gamble_roll = int(option.Gamble_SuccessChance) if mode == "success" else int(option.Gamble_SuccessChance) + 1
	var restored := clone(systems, label + " before choice")
	check(restored.event_for_node(1010101, 999, "event-audit") == view, label + ": JSON resumes the same occurrence and choice stage")
	var expected := _ledger(systems)
	var cost_expected := expected.duplicate(true)
	if mode != "exit":
		var payment = option.get("Gamble_NeedAbilityItemId" if gamble else "NeedAbilityItemId", "")
		_expect_rewards(expected, payment, "")
		_expect_rewards(cost_expected, payment, "")
	var reward_prefix := "Gamble_End" if mode == "exit" else "Gamble_Success" if mode == "success" else "Gamble_Failure" if mode == "failure" else ""
	_expect_rewards(expected, option.get(reward_prefix + "AddAbilityItemId", ""), option.get(reward_prefix + "AddRogueLootItemId", ""))
	var notifications: Array = []
	var resource_events: Array = []
	var observe_changed := func(): notifications.append(_snapshot(systems))
	var observe_resource := func(event):
		if str(event.type) in ["resource_spent", "resource_gained"]: resource_events.append(event.duplicate(true))
	systems.changed.connect(observe_changed)
	systems.gameplay_event.connect(observe_resource)
	check(systems.resolve_event("event-audit", choice).success, label + ": authored action resolves")
	check(restored.resolve_event("event-audit", choice).success, label + ": restored action resolves")
	systems.changed.disconnect(observe_changed)
	systems.gameplay_event.disconnect(observe_resource)
	_assert_ledger(systems, expected, label)
	check(resource_events == expected.resource_events, label + ": exact payment/reward resource notifications")
	check(notifications == [_snapshot(systems)], label + ": one fully committed save notification")
	check(_snapshot(restored) == _snapshot(systems), label + ": restored action has identical reward and RNG result")
	var finished := true
	var expected_story := str(option.get("EndGambleText", "")) if mode == "exit" else str(option.get("OptionSelectFinishText", ""))
	var expected_response := "继续冒险" if mode == "exit" else str(option.get("ResponseText", "继续冒险"))
	if gamble and mode != "exit":
		var rule := str(row.TypeData.GambleType)
		finished = index == options.size() - 1 or (mode == "success" and rule == "Guaranteed") or (mode == "failure" and rule == "Promotion")
		expected_story = str(option.get("Gameble_SuccessText" if mode == "success" else "Gamble_FailureText", ""))
		expected_response = str(row.TypeData.get("WinToLeaveText" if mode == "success" else "FailToLeaveText", "继续冒险"))
		check(systems.gamble_draws == [{"maximum": 101, "magic": int(cost_expected.materials[102]), "max_health": float(cost_expected.max_health)}], label + ": native 0..100 draw occurs after complete payment")
		check(int(encounter.step) == index + 1, label + ": outcome advances exactly one stage")
		if not synthetic: coverage["gamble_successes" if mode == "success" else "gamble_failures"] += 1
	elif mode == "exit":
		coverage.gamble_exits += 1
		check(int(encounter.step) == index and systems.gamble_draws.is_empty(), label + ": voluntary exit neither wagers nor rolls")
	else:
		check(int(encounter.step) == 0 and systems.gamble_draws.is_empty(), label + ": ordinary choice does not gamble")
	check(bool(encounter.finished) == finished, label + ": source rule determines continuation")
	check(str(encounter.result_story) == expected_story and str(encounter.response) == expected_response, label + ": authored outcome story and response remain separate")
	var after := _snapshot(systems)
	check(not systems.resolve_event("event-audit", choice).success and _snapshot(systems) == after, label + ": repeated completed or previous-stage choice is immutable")
	var after_restore := clone(systems, label + " after choice")
	var restored_view := after_restore.event_for_node(1010101, 1, "event-audit")
	check(restored_view == systems.event_view(encounter), label + ": outcome and continuation survive reopening")
	if finished:
		check(restored_view.choices.is_empty(), label + ": finished event exposes no payable choices")
		check(systems.acknowledge_event("event-audit").success, label + ": completed outcome can be acknowledged")
		after = _snapshot(systems)
		check(not systems.acknowledge_event("event-audit").success and _snapshot(systems) == after, label + ": repeated acknowledgement is immutable")
		var acknowledged := clone(systems, label + " acknowledged")
		check(acknowledged.event_for_node(1, 5, "event-audit").acknowledged, label + ": acknowledgement survives reload")
		check(not acknowledged.resolve_event("event-audit", choice).success and _snapshot(acknowledged) == after, label + ": acknowledged reload cannot pay or grant twice")
	else:
		check(int(restored_view.step) == index + 1 and int(restored_view.choices[0].id) == int(options[index + 1].GambleOptionDataID), label + ": continuation offers only the next source stage")
		check(not systems.acknowledge_event("event-audit").success and _snapshot(systems) == after, label + ": continuing gamble cannot be closed as completed")
	cases.append({"event": int(row.Id), "enabled": bool(row.IsEnable), "option": choice, "stage": index, "mode": mode, "synthetic": synthetic, "finished": finished, "checks": checks - start_checks, "passed": failures.size() == start_failures})

func _test_synthetic_failure(row: Dictionary, index: int) -> void:
	var fixture := row.duplicate(true)
	fixture.TypeData.GambleOptionList[index].Gamble_SuccessChance = 99
	var original: Dictionary = catalog._indices.AdvantureEventData[str(int(row.Id))]
	catalog._indices.AdvantureEventData[str(int(row.Id))] = fixture
	coverage.synthetic_failure_branches += 1
	_exercise(fixture, index, "failure", true)
	catalog._indices.AdvantureEventData[str(int(row.Id))] = original

func _test_gate(row: Dictionary, index: int) -> void:
	var gamble: bool = row.RuleType == "GambleType"
	var option: Dictionary = (row.TypeData.GambleOptionList if gamble else row.TypeData.OptionList)[index]
	var gate: Dictionary = option.get("UnlockData", {})
	var kind := int(gate.get("unlock_condition_type", 0))
	if kind == 0: return
	var values: Array = []
	var low := int(gate.get("unlock_param2", 0))
	var high := int(gate.get("unlock_param3", 0))
	if kind == 1000:
		values = [{"value": 0, "allowed": false}]
	elif kind == 1010:
		values = [{"value": low - 1, "allowed": false}, {"value": low, "allowed": true}]
	else:
		values = [{"value": low - 1, "allowed": false}, {"value": low, "allowed": true}, {"value": high, "allowed": true}, {"value": high + 1, "allowed": false}]
	for boundary in values:
		coverage.condition_boundaries += 1
		var systems := fresh()
		var encounter := state(systems, row, index)
		var id := int(gate.get("unlock_param1", 0))
		if kind == 1010: systems.profile.data.materials[str({1: 101, 2: 102, 3: 103}.get(id, id))] = int(boundary.value)
		if kind == 9101: systems.profile.data.run.max_health = float(boundary.value)
		if kind == 9102 and id == 8000: systems.profile.data.materials["102"] = int(boundary.value)
		if kind == 9102 and id == 8013: systems.profile.data.run.counters.SearchPoint = int(boundary.value)
		var choice := int(option.GambleOptionDataID if gamble else option.OptionDataId)
		var label := "%d/%d/gate/%d" % [int(row.Id), choice, int(boundary.value)]
		var saved := _snapshot(systems)
		var view := systems.event_view(encounter)
		var entry: Dictionary = view.choices.filter(func(value): return int(value.id) == choice)[0]
		check(bool(entry.enabled) == bool(boundary.allowed), label + ": authored threshold is inclusive")
		if not boundary.allowed:
			check(not systems.resolve_event("event-audit", choice).success, label + ": rejected requirement cannot execute")
			check(_snapshot(systems) == saved, label + ": rejected requirement changes no resource, reward, RNG, or progress")

func _test_generation() -> void:
	for row in source:
		var systems := fresh()
		var rule: Dictionary = row.EventGenerateData
		systems.profile.data.run.area_level = maxi(1, int(rule.NodeLevel))
		for id in _tokens(str(rule.get("AddAppearChanceList", "")).replace(":", "|")):
			if raw.LootData.has(id): systems.profile.data.run.inventory[str(id)] = 1
		var node := int(rule.SpecifyRoomID) if int(rule.SpecifyRoomID) > 0 else 99000000
		var candidates := systems.event_candidates(node, str(row.EventType) == "Spacial")
		var included := candidates.any(func(entry): return int(entry.row.Id) == int(row.Id))
		var expected := bool(row.IsEnable) and (int(rule.AppearChance) > 0 or not str(rule.AddAppearChanceList).is_empty() or int(rule.SpecifyRoomID) == node)
		check(included == expected, str(row.Id) + ": generation honors enabled flag, source region, marker type and weights")
		var opposite := systems.event_candidates(node, str(row.EventType) != "Spacial")
		check(not opposite.any(func(entry): return int(entry.row.Id) == int(row.Id)), str(row.Id) + ": normal and special markers remain separate")
		if row.IsEnable and included:
			for index in maxi(1, int(rule.MaxAppearTime)):
				systems.profile.data.run.events.append({"key": "used-" + str(index), "event_id": int(row.Id), "step": 0, "finished": true, "result": ""})
			check(not systems.event_candidates(node, str(row.EventType) == "Spacial").any(func(entry): return int(entry.row.Id) == int(row.Id)), str(row.Id) + ": source appearance limit prevents another occurrence")

func _test_complete_path(row: Dictionary) -> void:
	var systems := fresh()
	var encounter := state(systems, row)
	var options: Array = row.TypeData.GambleOptionList
	var rule := str(row.TypeData.GambleType)
	_prepare(systems, options[0].get("UnlockData", {}))
	for index in options.size():
		var option: Dictionary = options[index]
		systems.gamble_roll = int(option.Gamble_SuccessChance) + 1 if rule == "Guaranteed" else 0
		systems.delivered.clear()
		var expected := _ledger(systems)
		_expect_rewards(expected, option.get("Gamble_NeedAbilityItemId", ""), "")
		var outcome := "Failure" if rule == "Guaranteed" else "Success"
		_expect_rewards(expected, option.get("Gamble_" + outcome + "AddAbilityItemId", ""), option.get("Gamble_" + outcome + "AddRogueLootItemId", ""))
		var restored := clone(systems, "%d/path/%d" % [int(row.Id), index])
		var before := restored.event_for_node(1010101, 42, "event-audit")
		check(int(before.step) == index and int(before.choices[0].id) == int(option.GambleOptionDataID), str(row.Id) + ": full path reload selects exact next stage")
		check(systems.resolve_event("event-audit", int(option.GambleOptionDataID)).success, str(row.Id) + ": full path stage executes")
		_assert_ledger(systems, expected, "%d/path/%d" % [int(row.Id), index])
		check(restored.resolve_event("event-audit", int(option.GambleOptionDataID)).success and _snapshot(restored) == _snapshot(systems), str(row.Id) + ": full path reload outcome matches")
		check(bool(encounter.finished) == (index == options.size() - 1), str(row.Id) + ": full path continues until its authored final stage")
	coverage.complete_gamble_paths += 1

func _test_probability_boundaries() -> void:
	var original: Dictionary = catalog._indices.AdvantureEventData["112"]
	for pair in [{"chance": 0, "roll": 0, "finishes": false}, {"chance": 0, "roll": 1, "finishes": true}, {"chance": 100, "roll": 100, "finishes": false}]:
		var fixture := original.duplicate(true)
		fixture.TypeData.GambleOptionList[0].Gamble_SuccessChance = int(pair.chance)
		catalog._indices.AdvantureEventData["112"] = fixture
		var systems := fresh()
		var encounter := state(systems, fixture)
		systems.gamble_roll = int(pair.roll)
		check(systems.resolve_event("event-audit", 1121).success and bool(encounter.finished) == bool(pair.finishes), "Native probability boundary chance=%d draw=%d" % [int(pair.chance), int(pair.roll)])
	catalog._indices.AdvantureEventData["112"] = original

func _test_reentrant_resource_spent() -> void:
	var systems := fresh()
	var row: Dictionary = source.filter(func(value): return int(value.Id) == 112)[0]
	var encounter := state(systems, row)
	var attempts: Array = []
	var saved_observations: Array = []
	var changes: Array = []
	var observe_resource := func(event):
		if event.type != "resource_spent": return
		saved_observations.append(_snapshot(systems))
		attempts.append(systems.resolve_event("event-audit", 1121))
		attempts.append(systems.resolve_event("event-audit", 1122))
		attempts.append(systems.resolve_event("event-audit", -1))
	var observe_changed := func(): changes.append(_snapshot(systems))
	systems.gameplay_event.connect(observe_resource)
	systems.changed.connect(observe_changed)
	check(systems.resolve_event("event-audit", 1121).success, "Reentrant resource_spent: outer paid wager succeeds")
	systems.gameplay_event.disconnect(observe_resource)
	systems.changed.disconnect(observe_changed)
	check(attempts.size() == 3 and attempts.all(func(value): return not value.success), "Reentrant resource_spent: current choice, next choice, and exit are all rejected")
	check(systems.material(102) == 9900 and int(encounter.step) == 1 and not encounter.finished, "Reentrant resource_spent: one payment and one stage only")
	check(systems.gamble_draws.size() == 1, "Reentrant resource_spent: one random outcome only")
	check(saved_observations == [_snapshot(systems)] and changes == saved_observations, "Reentrant resource_spent: all observers see the committed event and wallet")
	var restored := clone(systems, "Reentrant resource_spent")
	check(int(restored.event_for_node(1010101, 1, "event-audit").step) == 1, "Reentrant resource_spent: observer snapshot remains resumable")

func _test_loot_exchanges() -> void:
	for pair in [{"event": 40, "option": 401, "old": 20122, "new": 20123}, {"event": 47, "option": 471, "old": 20170, "new": 20171}]:
		var systems := fresh()
		var row: Dictionary = source.filter(func(value): return int(value.Id) == int(pair.event))[0]
		var encounter := state(systems, row)
		systems.profile.data.run.inventory[str(pair.old)] = 1
		var saved := _snapshot(systems)
		check(not systems.can_add_loot(int(pair.new)), "Exchange: general acquisition still enforces rejected predecessor " + str(pair.old))
		check(not systems.add_loot(int(pair.new)).success and _snapshot(systems) == saved, "Exchange: ordinary acquisition cannot remove a conflicting item")
		check(systems.resolve_event("event-audit", int(pair.option)).success, "Exchange: event grants authored replacement " + str(pair.new))
		check(encounter.finished and systems.rank(systems.profile.data.run.inventory, int(pair.old)) == 0 and systems.rank(systems.profile.data.run.inventory, int(pair.new)) == 1, "Exchange: one old item is consumed and one new item is held")
		var restored := clone(systems, "Exchange " + str(pair.event))
		check(restored.rank(restored.profile.data.run.inventory, int(pair.old)) == 0 and restored.rank(restored.profile.data.run.inventory, int(pair.new)) == 1, "Exchange: replacement survives JSON restore")
		var capped := fresh()
		capped.profile.data.run.inventory[str(pair.old)] = 1
		capped.profile.data.run.inventory[str(pair.new)] = int(raw.AbilityItems[int(pair.new)].MaxHaveCount)
		saved = _snapshot(capped)
		capped._event_rewards("", str(pair.new))
		check(_snapshot(capped) == saved, "Exchange: a failed capped reward restores the predecessor")

func _test_reentrant_acknowledgement() -> void:
	var systems := fresh()
	var row: Dictionary = source.filter(func(value): return int(value.Id) == 3)[0]
	var encounter := state(systems, row)
	var attempts: Array = []
	var snapshots: Array = []
	var resource_observer := func(event):
		if event.type != "resource_spent": return
		snapshots.append(_snapshot(systems))
		attempts.append(systems.acknowledge_event("event-audit"))
	systems.gameplay_event.connect(resource_observer)
	check(systems.resolve_event("event-audit", 32).success, "Acknowledge reentry: paid selection finishes")
	systems.gameplay_event.disconnect(resource_observer)
	check(encounter.finished and not encounter.get("acknowledged", false), "Acknowledge reentry: payment callback cannot dismiss the committed result")
	check(attempts.size() == 1 and not attempts[0].success and snapshots == [_snapshot(systems)], "Acknowledge reentry: no nested acknowledgement or intermediate save")
	var other := encounter.duplicate(true)
	other.key = "other-finished-event"
	systems.profile.data.run.events.append(other)
	attempts.clear()
	var acknowledgement_observer := func():
		attempts.append(systems.acknowledge_event("event-audit"))
		attempts.append(systems.acknowledge_event("other-finished-event"))
	systems.changed.connect(acknowledgement_observer)
	check(systems.acknowledge_event("event-audit").success, "Acknowledge reentry: player confirms the result once")
	systems.changed.disconnect(acknowledgement_observer)
	check(attempts.size() == 2 and attempts.all(func(value): return not value.success), "Acknowledge reentry: changed callback cannot confirm either event recursively")
	check(encounter.acknowledged and not other.get("acknowledged", false), "Acknowledge reentry: only explicitly confirmed event changes")
	check(systems.acknowledge_event("other-finished-event").success, "Acknowledge reentry: subsequent independent confirmation remains available")
