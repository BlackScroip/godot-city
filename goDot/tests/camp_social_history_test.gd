extends SceneTree

var checks := 0
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var catalog := DungeonCatalog.new()
	check(catalog.load_all(), "catalog")
	var profile := DungeonProfile.new()
	var systems := DungeonSystems.new(catalog, profile)
	var social = preload("res://scripts/domain/camp_social.gd").new(systems)
	var history = preload("res://scripts/domain/camp_history.gd").new(systems)
	check(history.records().is_empty() and history.capture(false).is_empty(), "old saves never fabricate history")
	check(social.visitor_choices(1, 1, func(_max): return 0).is_empty(), "level one has no visitors")
	for level in [2, 3]:
		var visitors: Array = social.visitor_choices(level, 1, func(_max): return 0)
		check(visitors.size() == level, "source seat capacity " + str(level))
		var ids: Array = []
		for visitor in visitors:
			check(int(visitor.character_id) != 1 and int(visitor.character_id) not in ids, "visitors exclude current and duplicate characters")
			ids.append(int(visitor.character_id))
	check(social.visitor_choices(2, 1, func(_max): return 51).is_empty(), "level two threshold50 excludes51")
	check(social.visitor_choices(3, 1, func(_max): return 76).is_empty(), "level three threshold75 excludes76")
	check(social.visitor_choices(2, 1, func(limit): return 50 if limit == 101 else 0).size() == 2, "visitor threshold inclusive")
	check(social.visitor_npc_id(8) == 7, "source eighth character reuses seventh camp NPC prefab")
	systems.grant_material(106, 2)
	check(not social.gift_status(1000).success, "gifting obeys source NPC unlock condition")
	check(not systems.give_npc_gift(1000).success and systems.material(106) == 2, "direct gift cannot bypass dialogue completion")
	systems.begin_run(817, 1, 100)
	check(not social.golden_apple_appears("a", "a", 1, {}, func(_max): return 0), "guild gate blocks apple")
	profile.data.buildings["2"] = 2
	check(social.golden_apple_appears("b", "b", 1, {}, func(_max): return 50), "source base threshold50 inclusive")
	check(not social.golden_apple_appears("b", "c", 1, {}, func(_max): return 0), "one generated apple per region")
	check(social.golden_apple_appears("b", "b", 1, {}, func(_max): return 1000), "restoring decision does not reroll")
	check(not social.golden_apple_appears("c", "c", 2, {}, func(_max): return 76, 2), "source per-level chance25 boundary")
	check(social.golden_apple_appears("d", "d", 2, {}, func(_max): return 75, 2), "next area chance75 inclusive")
	var drops: Array = preload("res://scripts/domain/breakable_rewards.gd").new(systems).destroyable("70003")
	check(drops.size() == 2 and drops[0].id == 106 and drops[0].amount == 1 and drops[0].direct, "apple goes directly to permanent wallet")
	check(drops[1].counter == "EatGoldAppleCount", "apple also records run amount")
	profile.data.run.counters["run:elapsed"] = 124.5
	profile.data.run.counters["run:kills"] = 12
	profile.data.run.materials["106"] = 1
	profile.data.run.route = {"visited": [1, 2]}
	var before := systems.material(106)
	var first: Dictionary = history.capture(false, "retreat")
	check(first.id == 1 and first.reason == "retreat", "retreat captures a terminal snapshot")
	check(history.capture(false, "retreat").is_empty() and history.records().size() == 1, "duplicate terminal capture is idempotent")
	profile.data.run.materials["106"] = 20
	check(int(history.detail(1).materials["106"]) == 1, "history owns a deep snapshot")
	check(systems.material(106) == before, "history never grants rewards")
	systems.end_run(false)
	check(history.overview().losses == 1 and float(history.overview().recorded_seconds) == 124.5, "overview combines existing lifetime statistics and recorded playtime")
	var restored := DungeonProfile.new()
	check(restored.restore(JSON.parse_string(JSON.stringify(profile.data))), "history survives profile restore")
	var bad: Dictionary = profile.data.duplicate(true)
	bad.run_history[0].elapsed = -1
	check(not preload("res://scripts/domain/camp_history.gd").validate(bad), "invalid history fails validation")
	bad = profile.data.duplicate(true)
	bad.run_history[0].id = 1.5
	check(not preload("res://scripts/domain/camp_history.gd").validate(bad), "fractional history identity rejected")
	check(not preload("res://scripts/domain/camp_history.gd").validate({"run": {"history_recorded": 1}}), "history commit flag must be boolean")
	var region_record := {"route": {"layers": [{"region": 1, "module_index": 0, "selected_id": 1, "complete": true}, {"region": 1, "module_index": 0, "selected_id": 2, "complete": false}, {"region": 2, "module_index": 1, "selected_id": 0, "complete": false}]}}
	check(history.region_summary(region_record) == [{"region": 1, "module_index": 0, "rooms": 1, "entered": 2}], "regional history excludes unvisited layers")
	var report := {"checks": checks, "failures": failures, "passed": failures.is_empty()}
	FileAccess.open("res://reports/camp-social-history-test.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("CAMP_SOCIAL_HISTORY_TEST ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
