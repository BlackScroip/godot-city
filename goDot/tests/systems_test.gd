extends SceneTree

const Catalog = preload("res://scripts/domain/catalog.gd")
const Profile = preload("res://scripts/domain/profile.gd")
const Systems = preload("res://scripts/domain/systems.gd")
const Combat = preload("res://scripts/domain/combat.gd")
var catalog
var profile
var systems
var assertions = 0
var failures: Array = []
var now = 10000
var task_coverage: Dictionary = {}
var group_coverage: Dictionary = {}
var event_coverage: Dictionary = {}
var curse_coverage: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func check(value, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)
		printerr("FAIL ", message)

func _run() -> void:
	catalog = Catalog.new()
	check(catalog.load_all(), "all self-contained data loads")
	profile = Profile.new()
	systems = Systems.new(catalog, profile)
	systems.utc_now = func(): return now
	check(systems.material(101) == 100 and profile.data.character_levels == {"1": 1}, "fresh profile has 100 gold and character one")
	check(catalog.rows("AchieveData").size() == 68 and catalog.rows("SubAchieveData").size() == 271, "new APK achievement and commission catalogs")
	var before = JSON.stringify(profile.data)
	check(not systems.upgrade_global_talent(102).success and JSON.stringify(profile.data) == before, "failed prerequisites preserve profile")
	for row in catalog.rows("SubAchieveData"):
		var status = systems.task_status(int(row.id))
		check(status.has("current") and status.has("required") and status.has("available") and status.has("claimed"), "task progress query " + str(int(row.id)))
	check(systems.begin_run(13579, 1, 500).success, "begin real run")
	for row in catalog.rows("MaterialData"): systems.grant_material(Catalog.row_id(row), 1000000)
	for row in catalog.rows("EnemyData"):
		var id = Catalog.row_id(row)
		for i in 50: systems.record_kill(id, 100)
		if row.get("enemy_rate", "") == "Boss": systems.record_boss_rating(id, 3)
	for visit in 100:
		for region in range(1, 6):
			var key = "test-route-" + str(visit) + "-" + str(region)
			systems.complete_node(key, region * 1000000, region, true)
			systems.claim_node_materials(key, region, true)
	_claim_all()
	systems.set_record("shop:invested", 100000)
	systems.set_record("shop:level", 10)
	for id in [101, 102, 103, 90002]: systems.spend({str(id): 10000})
	for pass_index in 4:
		for row in catalog.rows("LootData"): systems.add_loot(Catalog.row_id(row), false)
	_claim_all()
	check(systems.end_run(true).success, "finish adventure")
	_prepare_facilities(systems)
	for attempt in 8:
		for row in catalog.rows("CharData"):
			if row.available_state != "Normal": continue
			var id = Catalog.row_id(row)
			systems.unlock_character(id)
			for level in 6: systems.upgrade_character(id)
		for row in catalog.rows("TalentTreeData"):
			for level in 4: systems.upgrade_global_talent(Catalog.row_id(row))
		for row in catalog.rows("WeaponData"):
			for level in 5: systems.upgrade_weapon(Catalog.row_id(row))
		for row in catalog.rows("Buildings"):
			for level in 3: systems.upgrade_building(Catalog.row_id(row))
		for row in catalog.rows("MonsterPartnerData"):
			var id = Catalog.row_id(row)
			systems.unlock_partner(id)
			for level in 3: systems.upgrade_partner(id)
		for row in catalog.rows("NPCData"):
			for gift in 12: systems.give_npc_gift(Catalog.row_id(row))
		for row in catalog.rows("NPCFunctionData"):
			if row.get("func_msg_name", "") == "": systems.execute_npc_function(Catalog.row_id(row))
		for row in catalog.rows("CatMealData"):
			for level in range(1, 4): systems.research_meal(Catalog.row_id(row))
		for row in catalog.rows("MonsterWorkData"):
			for level in 4: systems.upgrade_work(Catalog.row_id(row))
		for dispatch_index in 12:
			for row in catalog.rows("MonsterWorkData"):
				systems.start_work(Catalog.row_id(row), 11001)
				now += 864000
				systems.collect_work(Catalog.row_id(row))
				systems.stop_work(Catalog.row_id(row))
		_claim_all()
		var character = attempt % 7 + 1
		check(systems.begin_run(20000 + attempt, character, 500).success, "progression run starts " + str(attempt))
		for row in catalog.rows("MaterialData"): systems.grant_material(Catalog.row_id(row), 100000)
		for row in catalog.rows("LootData"): systems.add_loot(Catalog.row_id(row), false)
		for region in range(1, 6): systems.complete_node("late-" + str(attempt) + "-" + str(region), region * 1000000, region, true)
		_claim_all()
		systems.end_run(attempt % 2 == 0)
	check(systems.begin_run(99999, 1, 500).success, "final run retains per-run material task progress")
	for row in catalog.rows("MaterialData"): systems.grant_material(Catalog.row_id(row), 100000)
	for row in catalog.rows("LootData"): systems.add_loot(Catalog.row_id(row), false)
	_claim_all()
	var unclaimed = []
	for row in catalog.rows("SubAchieveData"):
		if not profile.data.claimed_tasks.has(int(row.id)): unclaimed.append({"id": int(row.id), "name": row.name, "group": int(row.group_id), "status": systems.task_status(int(row.id))})
	check(profile.data.claimed_tasks.size() == 271, "all 271 tasks reached through public gameplay operations")
	check(profile.data.claimed_achievements.size() == 68, "all 68 achievement groups reached and rewarded")
	_test_events()
	_test_transactions()
	_test_purification()
	_test_effects()
	_test_combat_progression()
	_test_growth_drops()
	_test_offline_mall()
	_test_rogue_event_producers()
	_test_dispatch_costs()
	var snapshot = JSON.parse_string(JSON.stringify(profile.data))
	var restored = Profile.new()
	check(restored.restore(snapshot), "profile round trip validates")
	check(restored.data.claimed_tasks.size() == profile.data.claimed_tasks.size(), "all task claims survive reload")
	var resumed = Systems.new(catalog, restored)
	check(systems.next_random(100000) == resumed.next_random(100000), "random stream continues after save")
	for id in restored.data.claimed_tasks:
		var resources = JSON.stringify(restored.data.materials)
		check(not resumed.claim_task(int(id)).success and resources == JSON.stringify(restored.data.materials), "task cannot pay twice after reload " + str(int(id)))
	for id in restored.data.claimed_achievements:
		var resources = JSON.stringify(restored.data.materials)
		check(not resumed.claim_achievement(int(id)).success and resources == JSON.stringify(restored.data.materials), "group cannot pay twice after reload " + str(int(id)))
	var report = {"success": failures.is_empty(), "assertions": assertions, "failures": failures, "tasks_claimed": profile.data.claimed_tasks.size(), "groups_claimed": profile.data.claimed_achievements.size(), "task_ids": task_coverage.keys(), "group_ids": group_coverage.keys(), "event_template_choices": event_coverage, "purification_ids": curse_coverage.keys(), "unclaimed": unclaimed, "diagnostics": systems.diagnostics, "method": "Accelerated domain simulation using public resource, kill, room, growth, dispatch, NPC and transaction APIs; no direct achievement flags or completed-condition injection. This does not validate world collisions, natural economy duration, every event branch or original APK parity."}
	DirAccess.make_dir_recursive_absolute("res://reports")
	var output = FileAccess.open("res://reports/systems-tests.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t"))
	output.close()
	print("SYSTEMS ", assertions, " assertions, ", failures.size(), " failures; tasks ", profile.data.claimed_tasks.size(), "/271, groups ", profile.data.claimed_achievements.size(), "/68")
	quit(0 if failures.is_empty() else 1)

func _claim_all() -> void:
	for attempt in 65:
		var progress = false
		for row in catalog.rows("SubAchieveData"):
			var id = int(row.id)
			if profile.data.claimed_tasks.has(id): continue
			if systems.claim_task(id).success:
				task_coverage[id] = true
				check(not systems.claim_task(id).success, "task one-time reward " + str(id))
				progress = true
		for row in catalog.rows("AchieveData"):
			var id = int(row.id)
			if profile.data.claimed_achievements.has(id): continue
			if systems.claim_achievement(id).success:
				group_coverage[id] = true
				check(not systems.claim_achievement(id).success, "group one-time reward " + str(id))
				progress = true
		if not progress: break

func _test_dispatch_costs() -> void:
	var p = Profile.new()
	var s = Systems.new(catalog, p)
	var clock = {"utc": 100000}
	s.utc_now = func(): return clock.utc
	_prepare_facilities(s)
	s.begin_run(98123, 1, 500)
	for region in range(1, 6): s.complete_node("dispatch-unlock-" + str(region), region * 1000000, region, true)
	for kill_index in 10: s.record_kill(11001, 1)
	s.end_run(true)
	s.unlock_partner(11001)
	for row in catalog.rows("MaterialData"): s.grant_material(Catalog.row_id(row), 100000)
	for row in catalog.rows("MonsterWorkData"):
		var id = int(row.id)
		var starts = str(row.start_cost_materials).split("|")
		var upgrades = str(row.level_up_need_materials).split("|")
		var gold = str(row.level_up_need_gold).split("|")
		var rewards = str(row.finish_get_materials).split("|")
		for level in 3:
			clock.utc += 86400
			var expected = Systems.costs(starts[level] if level < starts.size() else "")
			var before = p.data.materials.duplicate(true)
			check(s.start_work(id, 11001).success, "dispatch starts at configured level " + str(id) + ":" + str(level))
			for material_id in before:
				check(int(before[material_id]) == s.material(int(material_id)), "dispatch starts without charging claim materials " + str(id) + ":" + str(level) + ":" + material_id)
			check(s.equip_partner(11001).success and not s.start_work(id).success, "work does not reserve a battle partner and duplicate orders are rejected " + str(id))
			s.unequip_partner(11001)
			clock.utc += int(row.cost_time) * 60 - 1
			var early = JSON.stringify(p.data)
			check(not s.collect_work(id).success and JSON.stringify(p.data) == early, "dispatch rejects one second early without mutation " + str(id))
			clock.utc += 1
			var material_id = int(row.materia_id)
			var previous = s.material(material_id)
			check(s.collect_work(id).success and s.material(material_id) - previous == int(rewards[level]) - int(expected.get(str(material_id), 0)), "dispatch exact net payout after per-output claim cost " + str(id) + ":" + str(level))
			var claimed = JSON.stringify(p.data)
			check(not s.collect_work(id).success and JSON.stringify(p.data) == claimed, "dispatch reward cannot repeat " + str(id))
			check(s.stop_work(id).success, "dispatch can return partner after collection " + str(id))
			claimed = JSON.stringify(p.data)
			if level == 2:
				check(not s.upgrade_work(id).success and JSON.stringify(p.data) == claimed, "dispatch maximum level rejected without spending " + str(id))
				continue
			expected = Systems.costs(upgrades[level] if level < upgrades.size() else "")
			expected["101"] = int(expected.get("101", 0)) + int(gold[level])
			before = p.data.materials.duplicate(true)
			check(s.upgrade_work(id).success, "dispatch upgrade succeeds " + str(id) + ":" + str(level))
			for resource_id in before:
				check(int(before[resource_id]) - s.material(int(resource_id)) == int(expected.get(resource_id, 0)), "dispatch exact single-level upgrade cost " + str(id) + ":" + str(level) + ":" + resource_id)

func _test_events() -> void:
	for row in catalog.rows("AdvantureEventData"):
		var p = Profile.new()
		var s = Systems.new(catalog, p)
		s.begin_run(1000 + Catalog.row_id(row), 1, 500)
		s.grant_material(102, 100000)
		var encounter = {"key": "event", "event_id": Catalog.row_id(row), "step": 0, "finished": false, "result": ""}
		p.data.run.events.append(encounter)
		var view = s.event_view(encounter)
		var available = view.choices.filter(func(x): return x.enabled and int(x.id) != -1)
		if available.is_empty(): available = view.choices.filter(func(x): return x.enabled)
		var success = not available.is_empty() and s.resolve_event("event", int(available[0].id)).success
		check(success, "event template executes " + str(Catalog.row_id(row)))
		if success: event_coverage[str(Catalog.row_id(row))] = int(available[0].id)

func _test_transactions() -> void:
	var p = Profile.new()
	var s = Systems.new(catalog, p)
	_prepare_facilities(s)
	check(not s.open_camp_treasure_boxes(1).success, "camp boxes enforce NPC prerequisite")
	check(s.execute_npc_function(140101).success, "camp first conversation")
	s.grant_material(101, 500000)
	var before = s.material(101)
	check(s.open_camp_treasure_boxes(1).success and s.material(101) == before - 1000, "original box cost and transaction")
	check(not s.open_camp_treasure_boxes(2).success, "invalid draw count rejected")
	s.begin_run(333, 1, 100)
	check(s.execute_npc_function(101001).success, "NPC support generated")
	var support = s.npc_support_offer(101001)
	check(not support.is_empty() and support.offers.size() == 3, "three persistent support candidates")
	if not support.is_empty():
		var id = int(support.offers[0].loot_id)
		check(s.claim_npc_support(101001, id).success and not s.claim_npc_support(101001, id).success, "NPC support claims once")
	s.grant_material(102, 100000)
	var offering = s.get_gem_offering()
	check(not offering.is_empty(), "gem quote generated")
	if not offering.is_empty():
		var key = str(offering.key)
		check(s.buy_gem_offering(key).success and not s.buy_gem_offering(key).success, "gem quote cannot be replayed")
	var choices = s.create_loot_reward(10001, "room-reward")
	check(not choices.is_empty() and choices == s.create_loot_reward(10001, "room-reward"), "reward choices persist without reroll")
	if not choices.is_empty(): check(s.choose_loot_reward("room-reward", choices[0]).success and not s.choose_loot_reward("room-reward", choices[0]).success, "reward selects once")

func _test_purification() -> void:
	var count = 0
	for row in catalog.rows("LootData"):
		if row.get("loot_type", "") != "诅咒遗物": continue
		var p = Profile.new()
		var s = Systems.new(catalog, p)
		s.begin_run(880, 1, 500)
		var id = Catalog.row_id(row)
		var rule = s.purification_rule(id)
		var wrapper = rule.ConditionList[0]
		var condition = wrapper.Condition
		var trigger = condition.RogueEventTriggerData
		s.record_purification_event(str(trigger.EventType), str(trigger.Param1), int(condition.MinValue), str(trigger.Param2), false)
		check(s.add_loot(id).success and not s.purify_loot(id).success, "curse ignores earlier history " + str(id))
		s.record_purification_event(str(trigger.EventType), str(trigger.Param1), int(condition.MinValue), str(trigger.Param2), false)
		check(s.rank(p.data.run.inventory, id) == 0 and s.rank(p.data.run.inventory, s.purification_target(id)) == 1, "curse original condition transforms " + str(id))
		if s.rank(p.data.run.inventory, s.purification_target(id)) == 1: curse_coverage[id] = true
		count += 1
	check(count == 20, "all twenty curse rules")

func _test_effects() -> void:
	var p = Profile.new()
	var s = Systems.new(catalog, p)
	s.begin_run(445, 1, 100)
	check(s.add_loot(10000).success and float(s.attributes().get("BaseAtk", 0)) >= 5, "original numeric loot applies")
	p.data.run.health = 10
	check(s.add_loot(10100).success and p.data.run.health == 35, "original HP buff healing")
	s.effects.acquire(12101)
	check(s.revival_count() > 0, "revival gem acquisition")
	p.data.run.health = 0
	check(s.revive_player().success and p.data.run.health > 0, "revival consumes count and restores health")

func _bind_progression(actor, state) -> void:
	actor.set_external_attributes(state.attributes())
	var bindings = state.progression_buff_bindings()
	actor.set_progression_buffs(bindings.roots, bindings.externally_counted_numeric_ids)

func _test_combat_progression() -> void:
	var p = Profile.new()
	var s = Systems.new(catalog, p)
	_prepare_facilities(s)
	var actor = Combat.new()
	check(actor.configure(null, null, 1).success, "progression uses actual combat catalog")
	_bind_progression(actor, s)
	check(is_equal_approx(actor.effective_attack_power(), 85.0 * 1.05) and actor.max_health == 100, "starting weapon applies exactly five percent in combat")
	s.grant_material(501, 1000)
	s.grant_material(503, 1000)
	s.grant_material(103, 1000)
	check(s.upgrade_character(1).success, "character growth transaction")
	_bind_progression(actor, s)
	check(is_equal_approx(actor.effective_attack_power(), 102.0 * 1.05) and actor.max_health == 120 and is_equal_approx(actor.attribute("BaseDef"), 14), "level two increases actual combat attack defense and HP by twenty percent")
	check(s.upgrade_weapon(101).success, "weapon second rank transaction")
	_bind_progression(actor, s)
	check(is_equal_approx(actor.effective_attack_power(), 102.0 * 1.15) and actor.buff_layers("191100") == 0, "weapon rank replaces earlier numeric root")
	check(s.upgrade_weapon(102).success, "alternate weapon unlock uses character level")
	p.data.selected_weapon = 102
	_bind_progression(actor, s)
	check(is_equal_approx(actor.effective_attack_power(), 102.0) and actor.max_health == 100 and actor.attribute("AttackSpeedRate") == 200, "weapon switch changes actual combat attack HP and speed")
	p.data.selected_weapon = 101
	_bind_progression(actor, s)
	check(is_equal_approx(actor.effective_attack_power(), 102.0 * 1.15) and actor.max_health == 120 and actor.attribute("AttackSpeedRate") == 0 and actor.buff_layers("192100") == 0, "switching back removes previous weapon effects")
	for level in 3: s.upgrade_weapon(101)
	_bind_progression(actor, s)
	check(is_equal_approx(actor.effective_attack_power(), 102.0 * 1.75) and actor.buff_layers("191401") > 0, "rank five binds original weapon conditional children")
	_bind_progression(actor, s)
	check(is_equal_approx(actor.effective_attack_power(), 102.0 * 1.75), "repeated progression binding does not stack growth or weapon")
	s.grant_material(502, 10)
	check(s.unlock_character(2).success, "second character recruitment transaction")
	p.data.selected_character = 2
	check(s.selected_weapon_buffs() == [291100], "incompatible selected weapon falls back to owned character default")

func _prepare_facilities(state) -> void:
	state.grant_material(101, 100000)
	while state.stat("runs") < 5:
		state.begin_run(4500 + state.stat("runs"), 1, 100)
		state.end_run(false)
	for row in catalog.rows("Buildings"):
		for stage in int(row.max_level): state.upgrade_building(int(row.id))

func _test_growth_drops() -> void:
	var p = Profile.new()
	var s = Systems.new(catalog, p)
	s.begin_run(668, 1, 100)
	check(not s.claim_node_materials("growth-room", 5, true).success, "room delivery requires a completed room")
	s.grant_material(103, 4)
	s.grant_material(10501, 2)
	var snapshot = JSON.stringify(p.data.materials)
	s.complete_node("growth-room", 5050000, 5, true, "2")
	check(s.claim_node_materials("growth-room", 5, true).success and JSON.stringify(p.data.materials) == snapshot, "boss completion preserves pickups without an invented growth bundle")
	check(s.material(501) == 0 and s.material(502) == 0 and s.material(504) == 0 and not p.data.materials.has("10502"), "room completion invents no vouchers, recruitment tokens, awakening rewards or absent materials")
	check(not s.claim_node_materials("growth-room", 5, true).success and JSON.stringify(p.data.materials) == snapshot, "room delivery cannot repeat")
	var restored = Profile.new()
	check(restored.restore(JSON.parse_string(JSON.stringify(p.data))), "room delivery save restores")
	var resumed = Systems.new(catalog, restored)
	var restored_materials = JSON.stringify(restored.data.materials)
	check(not resumed.claim_node_materials("growth-room", 5, true).success and JSON.stringify(restored.data.materials) == restored_materials, "recorded delivery survives reload without another payout")

func _test_offline_mall() -> void:
	var p = Profile.new()
	var s = Systems.new(catalog, p)
	s.grant_material(101, 10000000)
	s.grant_material(90002, 1000000)
	var seen = {}
	for row in catalog.rows("MallTradeData"):
		var id = Catalog.row_id(row)
		if seen.has(id): continue
		seen[id] = true
		var effective = catalog.find("MallTradeData", id)
		if not effective.Enable:
			check(not s.buy_offer(id).success, "original disabled mall item stays unavailable " + str(id))
			continue
		var quote = s.offer_quote(id)
		check(quote.success and quote.price > 0, "every enabled mall offer has explicit nonzero price " + str(id))
		if not quote.success: continue
		var before = s.material(int(quote.currency))
		var same_currency_reward = 0
		for option in quote.rewards:
			if option.ids == [int(quote.currency)]: same_currency_reward += int(option.amount)
		check(s.buy_offer(id).success and s.material(int(quote.currency)) == before - int(quote.price) + same_currency_reward, "mall deducts quoted currency and applies bundle " + str(id))
		if int(effective.GoodsNum) == 1: check(not s.buy_offer(id).success, "mall enforces original purchase limit " + str(id))
	for row in catalog.rows("ShopTreasureBoxData"):
		var id = Catalog.row_id(row)
		s.grant_material(id, 1)
		var before = s.material(id)
		var guaranteed_before = {}
		for material_id in Systems.costs(row.guaranteed_id): guaranteed_before[material_id] = s.material(int(material_id))
		check(s.open_material_box(id).success and s.material(id) == before - 1, "box consumes held item " + str(id))
		for material_id in guaranteed_before: check(s.material(int(material_id)) >= int(guaranteed_before[material_id]) + int(Systems.costs(row.guaranteed_id)[material_id]), "box grants configured guarantee " + str(id))
	var fresh = Profile.new()
	var rejected = Systems.new(catalog, fresh)
	var snapshot = JSON.stringify(fresh.data)
	check(not rejected.buy_offer(2006).success and not rejected.open_material_box(803).success and JSON.stringify(fresh.data) == snapshot, "unfunded offline mall and box operations preserve state")

func _test_rogue_event_producers() -> void:
	var p = Profile.new()
	var s = Systems.new(catalog, p)
	s.begin_run(824, 1, 500)
	check(s.add_loot(20149).success, "merchant ledger acquired")
	check(s.record_node_entry_effects("merchant-entry", "1").success and s.material(102) == 200, "top-level original shop-entry resource trigger")
	check(not s.record_node_entry_effects("merchant-entry", "1").success and s.material(102) == 200, "same node entry cannot fire resource trigger twice")
	check(s.add_loot(20126).success and s.add_loot(20176).success, "node armor and healing relics acquired")
	p.data.run.health = 10
	check(s.record_node_entry_effects("combat-entry", "2").success and p.data.run.armor == 30 and p.data.run.health == 35, "top-level fight armor and wildcard node healing use original buff values")
	check(s.add_loot(20408).success, "free purchase relic acquired")
	var shop = s.get_room_shop("free-shop", 1)
	check(not shop.offers.is_empty() and int(p.data.run.counters.get("FreePurchaseAttempts", 0)) == 1, "new shop event grants one free purchase")
	s.spend({"102": s.material(102)})
	if not shop.offers.is_empty(): check(s.buy_room_offer("free-shop", int(shop.offers[0].loot_id)).success and int(p.data.run.counters.get("FreePurchaseAttempts", 0)) == 0, "free purchase consumes attempt without requiring magic")
	s.get_room_shop("free-shop", 1)
	check(int(p.data.run.counters.get("FreePurchaseAttempts", 0)) == 0, "reopening existing shop cannot duplicate free purchase")
