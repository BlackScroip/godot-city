extends SceneTree

var checks := 0
var failures: Array[String] = []
var catalog := DungeonCatalog.new()

class EventSystems extends DungeonSystems:
	var roll := 0
	var last_random_maximum := 0
	var magic_at_last_random := 0
	var extra_options := 0
	func next_random(maximum: int) -> int:
		last_random_maximum = maximum
		magic_at_last_random = material(102)
		return clampi(roll, 0, maximum - 1)
	func attributes(character: int = 0) -> Dictionary:
		var values = super.attributes(character)
		values["BlessingPlusSelectExtraCount"] = extra_options
		values["SelectLootExtraOption"] = 5
		return values

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func fresh(seed_value: int = 901) -> EventSystems:
	var systems := EventSystems.new(catalog, DungeonProfile.new())
	systems.begin_run(seed_value, 1, 500)
	systems.profile.data.materials["102"] = 1000
	return systems

func encounter(systems, id: int, key: String = "event") -> Dictionary:
	var value = {"key": key, "event_id": id, "step": 0, "finished": false, "result": ""}
	systems.profile.data.run.events.append(value)
	return value

func _initialize() -> void:
	check(catalog.load_all(), "APK catalog loads")
	check(catalog.rows("AdvantureEventData").size() == 71, "Supplied APK contains 71 event templates")
	for id in [53, 54, 56, 57, 58, 114]: check(not catalog.find("AdvantureEventData", id).is_empty(), "New APK event is installed: " + str(id))
	_test_generation()
	_test_conditions_and_payment()
	_test_gambling()
	_test_counted_rewards()
	_test_old_day_rewards()
	print("ADVENTURE_EVENT_RULES_TEST ", JSON.stringify({"checks": checks, "passed": failures.is_empty(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func _test_generation() -> void:
	var original = catalog.tables.AdvantureEventData
	var template = original[0].duplicate(true)
	template.Id = 990001
	template.EventGenerateData = {"NodeLevel": 0, "SpecifyRoomID": 0, "MaxAppearTime": 2, "AppearChance": 0, "AddAppearChanceList": "21114:1000"}
	var second = template.duplicate(true)
	second.Id = 990002
	second.EventGenerateData = {"NodeLevel": 0, "SpecifyRoomID": 777, "MaxAppearTime": 2, "AppearChance": 100, "AddAppearChanceList": ""}
	var special = second.duplicate(true)
	special.Id = 990003
	special.EventType = "Spacial"
	var region = second.duplicate(true)
	region.Id = 990004
	region.EventGenerateData.NodeLevel = 6
	var disabled = second.duplicate(true)
	disabled.Id = 990005
	disabled.IsEnable = false
	catalog.tables.AdvantureEventData = [template, second, special, region, disabled]
	for row in catalog.tables.AdvantureEventData: catalog._indices.AdvantureEventData[str(row.Id)] = row
	var systems = fresh()
	check(systems.event_area_level(1070101) == 7, "Source node maps to its APK area instead of run progress")
	var candidates = systems.event_candidates(888)
	check(candidates.size() == 1 and int(candidates[0].row.Id) == 990002, "Zero base weights, disabled, special and other-region events stay excluded")
	check(int(candidates[0].weight) == 100, "Specified room gives no exclusion outside its target room")
	check(int(systems.event_candidates(777)[0].weight) == 100100, "Specified room adds native 100000 weight")
	check(systems.event_candidates(888, true).size() == 1 and int(systems.event_candidates(888, true)[0].row.Id) == 990003, "Special marker uses only special event templates")
	systems.profile.data.run.inventory["21114"] = 1
	candidates = systems.event_candidates(888)
	check(candidates.size() == 2 and int(candidates[0].weight) == 1000, "Held ability activates additive appearance weight")
	systems.profile.data.run.region = 3
	systems.profile.data.run.area_level = 6
	check(systems.event_candidates(888).size() == 3, "Region-specific templates use source area rather than third-stage progress")
	catalog.tables.AdvantureEventData = [second]
	var first = systems.event_for_node(888, 901, "marker:a")
	check(not first.is_empty(), "First marker generates a saved event")
	check(systems.event_for_node(888, 123, "marker:a").event_id == first.event_id and systems.profile.data.run.events.size() == 1, "Reopening a marker reuses its event without counting another appearance")
	check(not systems.event_for_node(888, 901, "marker:b").is_empty(), "Second marker uses the second permitted appearance")
	check(systems.event_for_node(888, 901, "marker:c").is_empty(), "MaxAppearTime prevents a third event even while earlier events remain unfinished")
	catalog.tables.AdvantureEventData = original
	for row in [template, second, special, region, disabled]: catalog._indices.AdvantureEventData.erase(str(row.Id))

func _test_conditions_and_payment() -> void:
	var systems = fresh()
	check(systems._event_condition({"unlock_condition_type": 9101, "unlock_param1": 1, "unlock_param2": 500, "unlock_param3": 500}), "Max-health condition includes both endpoints")
	check(not systems._event_condition({"unlock_condition_type": 9101, "unlock_param1": 1, "unlock_param2": 501, "unlock_param3": 9999}), "Max-health condition rejects insufficient maximum")
	check(not systems._event_condition({"unlock_condition_type": 9101, "unlock_param1": 1, "unlock_param2": 0, "unlock_param3": 0}), "Zero upper bound is an actual native bound")
	check(systems._event_condition({"unlock_condition_type": 1010, "unlock_param1": 2, "unlock_param2": 1000}), "Magic holding condition uses currency alias")
	systems.profile.data.run.counters.SearchPoint = 2
	check(systems._event_condition({"unlock_condition_type": 9102, "unlock_param1": 8013, "unlock_param2": 2, "unlock_param3": 999}), "Search-point condition reads the adventure resource")
	var paid_row: Dictionary = {}
	var paid_option: Dictionary = {}
	for row in catalog.rows("AdvantureEventData"):
		for option in row.TypeData.get("OptionList", []):
			if str(option.get("NeedAbilityItemId", "")) == "530101":
				paid_row = row
				paid_option = option
	check(not paid_row.is_empty(), "APK has a maximum-health payment option")
	systems.profile.data.run.inventory["20122"] = 1
	var before_attributes = float(systems.attributes().get("HpAddFixed", 0))
	encounter(systems, int(paid_row.Id))
	check(systems.resolve_event("event", int(paid_option.OptionDataId)).success, "Maximum-health payment option executes")
	check(is_equal_approx(float(systems.profile.data.run.max_health), 450), "NeedAbilityItemId actually pays 50 maximum health")
	check(is_equal_approx(float(systems.attributes().get("HpAddFixed", 0)) - before_attributes, -50), "Health payment persists in combat growth attributes")
	var saved = JSON.stringify(systems.profile.data)
	check(not systems.resolve_event("event", int(paid_option.OptionDataId)).success and JSON.stringify(systems.profile.data) == saved, "Completed health payment cannot charge or grant twice")
	var gambling = fresh()
	encounter(gambling, 102)
	check(gambling.resolve_event("event", 1021).success and gambling.material(102) == 900, "Gambling applies its 100 magic payment exactly once")
	check(gambling.magic_at_last_random == 900, "Gambling pays its need ability before drawing the outcome")
	var poor = fresh()
	poor.profile.data.materials["102"] = 99
	encounter(poor, 102)
	saved = JSON.stringify(poor.profile.data)
	check(not poor.resolve_event("event", 1021).success and JSON.stringify(poor.profile.data) == saved, "Failed unlock condition leaves currency, progress and rewards unchanged")

func _test_gambling() -> void:
	var guaranteed = fresh()
	var state = encounter(guaranteed, 101)
	guaranteed.roll = 100
	check(guaranteed.resolve_event("event", 1011).success and not state.finished and int(state.step) == 1, "Guaranteed failure advances to the second wager")
	guaranteed.roll = 0
	check(guaranteed.resolve_event("event", 1012).success and state.finished, "Guaranteed success ends the event")
	var promotion = fresh()
	state = encounter(promotion, 112)
	check(promotion.resolve_event("event", 1121).success and not state.finished and int(state.step) == 1, "Promotion success continues instead of closing the copier")
	check(promotion.material(102) == 900, "First copier stage spends 100 magic")
	var saved_profile := DungeonProfile.new()
	check(saved_profile.restore(JSON.parse_string(JSON.stringify(promotion.profile.data))), "Active gambling progress restores from JSON")
	var resumed := EventSystems.new(catalog, saved_profile)
	var resumed_view = resumed.event_for_node(1, 999, "event")
	check(int(resumed_view.step) == 1 and int(resumed_view.choices[0].id) == 1122, "Saved marker resumes at its exact next stage")
	check(resumed.resolve_event("event", -1).success and resumed.material(102) == 1100, "Leaving copier stage two awards its authored 200 magic")
	var after = JSON.stringify(resumed.profile.data)
	check(not resumed.resolve_event("event", -1).success and JSON.stringify(resumed.profile.data) == after, "Leaving reward is claimed once across saved reentry")
	var failed = fresh()
	state = encounter(failed, 112)
	failed.roll = 100
	check(failed.resolve_event("event", 1121).success and state.finished, "Promotion failure ends immediately")
	var roulette = fresh()
	state = encounter(roulette, 110)
	check(roulette.resolve_event("event", 1101).success and not state.finished and int(state.step) == 1, "Roulette success proceeds to stage two")
	roulette.roll = 100
	check(roulette.resolve_event("event", 1102).success and not state.finished and int(state.step) == 2, "Roulette failure proceeds to stage three")
	check(roulette.resolve_event("event", 1103).success and state.finished, "Roulette closes after the final stage")
	var original = catalog._indices.AdvantureEventData["112"]
	var modified = original.duplicate(true)
	modified.TypeData.GambleOptionList[0].Gamble_SuccessChance = 0
	catalog._indices.AdvantureEventData["112"] = modified
	var boundary = fresh()
	state = encounter(boundary, 112)
	check(boundary.resolve_event("event", 1121).success and not state.finished and boundary.last_random_maximum == 101, "Native random zero succeeds at zero chance with Range(0,101)")
	boundary = fresh()
	state = encounter(boundary, 112)
	boundary.roll = 1
	check(boundary.resolve_event("event", 1121).success and state.finished, "Random one fails at zero chance")
	modified.TypeData.GambleOptionList[0].Gamble_SuccessChance = 100
	boundary = fresh()
	state = encounter(boundary, 112)
	boundary.roll = 100
	check(boundary.resolve_event("event", 1121).success and not state.finished, "Native upper random endpoint succeeds at 100 chance")
	catalog._indices.AdvantureEventData["112"] = original

func _test_counted_rewards() -> void:
	var systems = fresh()
	encounter(systems, 53)
	var snapshots: Array = []
	var capture = func(): snapshots.append(systems.rank(systems.profile.data.run.inventory, 10002))
	systems.changed.connect(capture)
	check(systems.resolve_event("event", 531).success and systems.rank(systems.profile.data.run.inventory, 10002) == 3, "New APK red-gem event grants its configured quantity of three")
	check(snapshots == [3], "Counted event rewards publish one complete save transaction")
	systems.changed.disconnect(capture)
	var before = systems.material(102)
	systems._event_rewards("534001:2", "")
	check(systems.material(102) == before + 100, "Ability reward parser honors explicit quantities")
	check(int(catalog.find("AbilityItems", 10100).MaxHaveCount) == 999 and int(catalog.find("AbilityItems", 10102).MaxHaveCount) == 999, "APK consumable holding limits are installed")
	var gem_weight = catalog.find("AbilityItems", 20193)
	check(gem_weight.ModifyAttributeType1 == "GemExtraWeightRare2AddPercent" and int(gem_weight.ModifyAttributeValue1) == -100, "APK event gem-weight ability is installed")

func _test_old_day_rewards() -> void:
	var systems = fresh()
	systems.extra_options = 2
	var pool_before = catalog.config.get("AbilityItemLootPoolId_OldDay", 0)
	catalog._indices.ItemPoolData["990100"] = {"id": 990100, "sub_data_id_list": "990101"}
	catalog._indices.ItemPoolSubData["990101"] = {"id": 990101, "item_id_list_str": "20100,20101,20102,20103,20104,20105,20106,20107", "weight_list_str": "100", "unlock_data_id_list_str": ""}
	catalog.config.AbilityItemLootPoolId_OldDay = 990100
	systems.queue_loot_reward("OldDay", 2)
	check(systems.profile.data.run.rewards.size() == 2, "Two OldDay choice counts queue two selections")
	var reward = systems.profile.data.run.rewards[0]
	check(int(reward.candidate_count) == 5 and reward.choices.size() == 5, "OldDay uses three plus BlessingPlusSelectExtraCount; the legacy SelectLootExtraOption is not read")
	systems.extra_options = 0
	systems.profile.data.run.counters.SelectRefreshTime = 1
	check(systems.refresh_loot_reward(str(reward.key)).success and reward.choices.size() == 5, "Refresh preserves the saved reward candidate count")
	var key = str(reward.key)
	check(systems.choose_loot_reward(key, int(reward.choices[0])).success, "OldDay selection grants its chosen relic")
	var saved = JSON.stringify(systems.profile.data)
	check(not systems.choose_loot_reward(key, int(reward.choices[0])).success and JSON.stringify(systems.profile.data) == saved, "OldDay selection cannot be claimed twice")
	catalog.config.AbilityItemLootPoolId_OldDay = pool_before
	catalog._indices.ItemPoolData.erase("990100")
	catalog._indices.ItemPoolSubData.erase("990101")
