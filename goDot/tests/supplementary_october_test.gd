extends SceneTree

const Catalog = preload("res://scripts/domain/catalog.gd")
const Profile = preload("res://scripts/domain/profile.gd")
const Systems = preload("res://scripts/domain/systems.gd")
const Combat = preload("res://scripts/domain/combat.gd")
var catalog = Catalog.new()
var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _initialize() -> void:
	check(catalog.load_all(), "Complete source catalog loads")
	_import_closure()
	_acquisition()
	_rock_gameplay()
	_ice_gameplay()
	_funnel_phases()
	_battle_scale_admission()
	print("SUPPLEMENTARY_OCTOBER ", JSON.stringify({"checks": checks, "failures": failures}))
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _actor(character: int = 1) -> Combat:
	var actor = Combat.new()
	actor.configure(null, null, character)
	actor.statuses.clear()
	actor.drain_events()
	return actor

func _systems() -> Systems:
	var systems = Systems.new(catalog, Profile.new())
	check(systems.begin_run(271828, 1, 100).success, "Actual source run begins")
	return systems

func _bind(actor: Combat, systems: Systems) -> Array:
	var binding: Dictionary = systems.progression_buff_bindings()
	actor.set_progression_buffs(binding.roots, binding.externally_counted_numeric_ids)
	return actor.drain_events()

func _events(events: Array, type: String, id: String = "") -> Array:
	return events.filter(func(event): return event.type == type and (id.is_empty() or str(event.get("id", event.get("summon_id", ""))) == id))

func _weights(systems: Systems, pool: int = 30301) -> Dictionary:
	var weights: Dictionary = {}
	for row in systems._pool_candidates(pool): weights[int(row.id)] = float(row.weight)
	return weights

func _import_closure() -> void:
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://reports/supplementary-october-import.json"))
	check(report.apk_sha256 == "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505" and report.loot_ids.size() == 26, "Supplementary import identifies all 26 source loot roots")
	var actor = _actor()
	for id in report.loot_ids:
		var row: Dictionary = catalog.find("LootData", int(id))
		check(not row.is_empty() and int(row.ability_item_id) == int(id) and not catalog.find("AbilityItems", int(id)).is_empty(), "Source loot and ability resolve %s" % id)
	for id in report.added_ids.ItemPoolSubData: check(not catalog.find("ItemPoolSubData", int(id)).is_empty(), "Source pool row resolves %s" % id)
	for id in report.required.buff: check(actor._buff_index.has(str(id)) and not catalog.find("Buffs", int(id)).is_empty(), "Source buff dependency resolves %s" % id)
	for id in report.required.summon: check(actor._summon_index.has(str(id)), "Source summon dependency resolves %s" % id)
	for id in report.required.damage: check(not actor._damage_data(int(id)).is_empty(), "Source damage dependency resolves %s" % id)

func _acquisition() -> void:
	var systems = _systems()
	var initial := _weights(systems)
	check(initial.get(20255, 0) == 6 and initial.get(20265, 0) == 6 and not initial.has(20256) and not initial.has(20266), "Initial source pool offers only base rock and ice at weight six")
	for line in [[20255, 20256, 20257, "50205091", "50205092", "50205093"], [20265, 20266, 20267, "50205081", "50205082", "50205083"]]:
		var run = _systems()
		var actor = _actor()
		for tier in 3:
			var id := int(line[tier])
			check(run.add_loot(id).success, "Actual spirit acquisition succeeds %d" % id)
			var emitted := _bind(actor, run)
			check(_events(emitted, "summon", str(line[tier + 3])).size() == 1, "Acquisition creates exact source companion %d" % id)
			if tier > 0: check(not run.profile.data.run.inventory.has(str(line[tier - 1])), "Source upgrade removes prior tier %d" % id)
			check(not run.can_add_loot(id), "Source max count forbids duplicate %d" % id)
			if tier < 2: check(_weights(run).get(int(line[tier + 1]), 0) == (4 if tier == 0 else 1), "Source upgrade pool retains authored weight %d" % id)
		check(not run.can_add_loot(int(line[0])) and not run.can_add_loot(int(line[1])), "Final spirit rejects lower tiers")
	var talent = _systems()
	talent.profile.data.talents["219"] = 1
	var talented := _weights(talent)
	check(not talented.has(20255) and not talented.has(20265) and talented.get(20256, 0) == 4 and talented.get(20266, 0) == 4, "Source talent gate replaces base offers with tier two through Or gate")
	for row in [[20320, 20212, 20265, 20266, 20267, "50205076"], [20330, 20232, 20265, 20266, 20267, "50205077"], [20340, 20242, 20255, 20256, 20257, "50205079"], [20350, 20222, 20255, 20256, 20257, "50205078"]]:
		var run = _systems()
		var before: Dictionary = run.profile.data.duplicate(true)
		check(not run.add_loot(int(row[0])).success and run.profile.data == before, "Locked fusion grant is atomic %s" % row[0])
		# The other component is itself a final spirit, acquired through its source upgrades.
		run.set_record("loot-region:" + str(int(row[1]) - 1), 2)
		for id in range(int(row[1]) - 2, int(row[1]) + 1): check(run.add_loot(id).success, "Fusion first component upgrades %d" % id)
		for index in range(2, 5): check(run.add_loot(int(row[index])).success, "Fusion second component upgrades %s" % row[index])
		check(not run.can_add_loot(int(row[0])), "Fusion remains locked until source fourth-region requirement %s" % row[0])
		run.set_record("max-region", 4)
		check(_weights(run).get(int(row[0]), 0) == 100 and run.add_loot(int(row[0])).success, "Source fusion becomes available with exact ingredients and weight100 %s" % row[0])
		check(not run.profile.data.run.inventory.has(str(row[1])) and not run.profile.data.run.inventory.has(str(row[4])), "Fusion consumes exact two source ingredients %s" % row[0])
		var actor = _actor()
		check(_events(_bind(actor, run), "summon", str(row[5])).size() == 1, "Fusion creates exact source companion %s" % row[0])
		check(not run.can_add_loot(int(row[1])) and not run.can_add_loot(int(row[4])) and not run.can_add_loot(int(row[0])), "Fusion rejects components and duplicate output %s" % row[0])

func _rock_gameplay() -> void:
	for row in [["50202550", 35.0], ["50202560", 24.0], ["50202570", 24.0]]:
		var actor = _actor()
		actor.add_buff(str(row[0]))
		actor.drain_events()
		for index in 20: actor.notify_gameplay("move", {"moving": false, "distance": 0.0, "delta": 1.0})
		check(_events(actor.drain_events(), "summon", "502025510").is_empty(), "Stationary time cannot trigger distance spirit %s" % row[0])
		actor.notify_gameplay("move", {"moving": true, "distance": float(row[1]) - 0.1, "delta": 1.0})
		check(_events(actor.drain_events(), "summon", "502025510").is_empty(), "Rock waits for complete source distance %s" % row[0])
		var saved := actor.snapshot()
		var restored = _actor()
		check(restored.restore(JSON.parse_string(JSON.stringify(saved))), "Rock distance survives serialization %s" % row[0])
		restored.notify_gameplay("move", {"moving": true, "distance": 0.11, "delta": 0.1})
		check(_events(restored.drain_events(), "summon", "502025510").size() == 1, "Rock emits earthquake at native distance threshold %s" % row[0])
		restored.tick(0.0)
		var hits := _events(restored.drain_events(), "hit", "502025510")
		check(hits.size() == 1 and int(hits[0].definition.damageId) == 502025000 and float(hits[0].definition.multiplier) == 3.0, "Earthquake emits real source three-times damage %s" % row[0])
		if not hits.is_empty():
			var target := Combat.new()
			target.configure_enemy(11001)
			target.statuses.clear()
			var hp: float = target.health
			check(target.receive(hits[0]) > 0 and target.health < hp and target.buff_layers("800511") > 0, "Earthquake damages enemy and applies source combat modifier %s" % row[0])
		restored.notify_gameplay("move", {"moving": true, "distance": 1.0, "delta": 0.1})
		check(_events(restored.drain_events(), "summon", "502025510").is_empty(), "Distance counter resets after one earthquake %s" % row[0])

func _ice_gameplay() -> void:
	for row in [["50202650", 30.0, "502026501", 4], ["50202660", 20.0, "502026502", 5], ["50202670", 15.0, "502026503", 6]]:
		var actor = _actor()
		actor.add_buff(str(row[0]))
		actor.drain_events()
		actor.notify_gameplay("action_start", {"slot": 3, "action": "source_main_skill"})
		check(_events(actor.drain_events(), "summon", str(row[2])).is_empty(), "Ice initially waits for source cooldown %s" % row[0])
		actor.tick(float(row[1]) - 0.05)
		actor.drain_events()
		actor.notify_gameplay("action_start", {"slot": 3, "action": "source_main_skill"})
		check(_events(actor.drain_events(), "summon", str(row[2])).is_empty(), "Ice cannot trigger before cooldown %s" % row[0])
		actor.tick(0.06)
		actor.drain_events()
		actor.notify_gameplay("action_start", {"slot": 0, "action": "source_normal_attack"})
		check(_events(actor.drain_events(), "summon", str(row[2])).is_empty(), "Normal attack cannot consume main-skill trigger %s" % row[0])
		actor.notify_gameplay("action_start", {"slot": 3, "action": "source_main_skill"})
		check(_events(actor.drain_events(), "summon", str(row[2])).size() == 1, "Main skill emits source ice carrier after cooldown %s" % row[0])
		actor.tick(0.0)
		var hits := _events(actor.drain_events(), "hit", str(row[2]))
		check(hits.size() == int(row[3]), "Ice carrier retains source emission count %s" % row[0])
		check(actor.diagnostics.is_empty(), "Source ice trigger has no missing dependencies %s" % row[0])

func _funnel_phases() -> void:
	var actor = _actor(6)
	actor._spawn_summon("600012", actor._clock, "orb_satk_start", 4, 2.0, 0, {"OriginType": "currentselfpos"}, "source-target")
	var spawned := _events(actor.drain_events(), "summon", "600012")
	actor.tick(0.0)
	var entered := actor.drain_events()
	var phases := _events(entered, "summon_trigger_effect", "600012")
	check(phases.size() == 1 and phases[0].phase == "NoDelay" and _events(entered, "hit", "600012").is_empty(), "Source orb NoDelay occurs before its delayed hit")
	if not phases.is_empty():
		check(phases[0].definition == actor._summon_index["600012"].raw_data and phases[0].origin._summon_token == spawned[0].origin._summon_token and phases[0].target_key == "source-target", "Source phase retains exact definition, world origin token and target")
	actor.tick(0.05)
	check(_events(actor.drain_events(), "hit", "600012").is_empty(), "Authored 100ms trigger delay cannot hit at50ms")
	var restored = _actor(6)
	check(restored.restore(JSON.parse_string(JSON.stringify(actor.snapshot()))), "Pending funnel delay survives serialization")
	restored._cancel_sequence(restored._cast_sequence, true)
	restored.tick(0.051)
	var completed := restored.drain_events()
	check(_events(completed, "hit", "600012").size() == 1 and _events(completed, "summon_trigger_effect").is_empty(), "Spawned delayed payload survives action cancellation without replaying NoDelay")
	var stone = _actor()
	stone._spawn_summon("44300185", stone._clock, "attack", 0)
	stone.drain_events()
	stone.tick(0.0)
	var delay := _events(stone.drain_events(), "summon_trigger_effect", "44300185")
	check(delay.size() == 1 and delay[0].phase == "Delay", "Nondamaging stone source still emits its exact Delay phase")
	var fast = _actor()
	fast._spawn_summon("502025510", fast._clock, "distance", 0)
	check(fast._pending.size() == 1 and fast._pending[0].has("hit"), "Empty phase and zero delay source retains direct lightweight hit scheduling")
	fast.drain_events()
	actor.drain_events()

func _orb() -> Combat:
	var actor = Combat.new()
	actor.configure(null, null, 6)
	actor.add_buff("600100", 20)
	actor._start(actor._action("ActGroup_playerchara", "orb_satk_start"), 4)
	actor.drain_events()
	return actor

func _battle_scale_admission() -> void:
	var fixture = _actor()
	fixture._start({"id": "battle_scale_expiry_fixture", "speed": 1.0, "duration": 1.0, "hits": [], "events": [{"type": "EET_BattleTimeScaleModify", "time": 0.1, "duration": 0.2, "enabled": true, "raw": '{"ModifyBattleTimeScale":0.5}'}]}, 4)
	fixture.tick(0.4)
	var expiry := _events(fixture.drain_events(), "battle_time_scale")
	check(expiry.size() == 2 and absf(float(expiry[0].clock) - 0.1) < 0.00001 and absf(float(expiry[1].clock) - 0.3) < 0.00001, "Uninterrupted battle scale exits at its exact authored end in a coarse tick")
	for hz in [30, 60, 120]:
		var actor := _orb()
		var phases: Array = []
		for frame in hz / 3:
			actor.tick(1.0 / hz)
			phases.append_array(_events(actor.drain_events(), "battle_time_scale"))
		check(phases.size() == 2 and phases[0].phase == "Enter" and phases[1].phase == "Exit", "Source battle scale admits and exits once at %dHz" % hz)
		if phases.size() == 2:
			check(absf(float(phases[0].clock) - 0.417 / 4.0) < 0.00001 and absf(float(phases[1].clock) - 0.817 / 4.0) < 0.00001, "Battle scale enters at authored boundary and exits on source shoot transition at %dHz" % hz)
			check(float(phases[0].window.scale) == 0.25 and float(phases[0].window.duration) == 0.416 and phases[0].window.index >= 0 and phases[0].window.definition.ModifyBattleTimeScale == 0.25, "Battle scale admission carries exact source payload and event index")
	var actor := _orb()
	actor.tick(0.11)
	actor.drain_events()
	actor.add_buff("600100", -20)
	check(actor.battle_time_scale_windows().size() == 1, "Removing entry buff cannot revoke admitted global window")
	var restored = _actor(6)
	var restore_ok := restored.restore(JSON.parse_string(JSON.stringify(actor.snapshot())))
	check(restore_ok and JSON.stringify(restored.battle_time_scale_windows()) == JSON.stringify(JSON.parse_string(JSON.stringify(actor.battle_time_scale_windows()))), "Admitted global window survives exact save restore")
	restored._cancel_sequence(restored._cast_sequence)
	check(restored.battle_time_scale_windows().is_empty() and _events(restored.drain_events(), "battle_time_scale").size() == 1, "Action cancellation unregisters admitted source window")
	actor.health = 0
	actor.tick(0.01)
	check(actor.battle_time_scale_windows().is_empty() and _events(actor.drain_events(), "battle_time_scale").size() == 1, "Death unregisters admitted source window")
	var failed = _actor(6)
	failed._start(failed._action("ActGroup_playerchara", "orb_satk_start"), 4)
	failed.tick(0.22)
	failed.add_buff("600100", 20)
	failed.tick(0.05)
	check(failed.battle_time_scale_windows().is_empty() and _events(failed.drain_events(), "battle_time_scale").is_empty(), "Failed source entry cannot become admitted after its boundary")
