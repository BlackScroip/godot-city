extends SceneTree

var checks := 0
var failures: Array[String] = []
var catalog: DungeonCatalog

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	catalog = DungeonCatalog.new()
	check(catalog.load_all(), "source catalog loads")
	_test_building()
	_test_character()
	_test_work()
	_test_meal()
	_test_npc()
	_test_tokens()
	_test_mall()
	_test_material_box()
	print("CAMP_TRANSACTION_TEST ", JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)

func _fresh() -> DungeonSystems:
	var systems := DungeonSystems.new(catalog, DungeonProfile.new())
	systems.profile.data.materials = {"101": 100000, "501": 1000, "503": 1000, "108": 10000, "10101": 1000, "10102": 1000, "10201": 1000, "10202": 1000}
	return systems

func _observe(systems: DungeonSystems, action: Callable) -> Dictionary:
	var observed := {"attempted": false, "repeat": false, "cross": false, "spend": false, "snapshot": {}, "changes": 0, "changed_reentry": false}
	var listener = func(event: Dictionary):
		if observed.attempted or event.type not in ["resource_spent", "resource_gained"]: return
		observed.attempted = true
		observed.snapshot = systems.profile.data.duplicate(true)
		observed.repeat = bool(action.call().success)
		observed.cross = bool(systems.begin_run(181, 1, 100).success)
		observed.spend = systems.spend({"101": 1})
	var changed_listener = func():
		observed.changes += 1
		observed.changed_reentry = bool(systems.select_character(1).success)
	systems.gameplay_event.connect(listener)
	systems.changed.connect(changed_listener)
	var result: Dictionary = action.call()
	systems.gameplay_event.disconnect(listener)
	systems.changed.disconnect(changed_listener)
	check(result.success and observed.attempted, "outer operation commits and publishes its resource events")
	check(not observed.repeat and not observed.cross and not observed.spend, "resource listeners cannot repeat, start an adventure, or spend during commit")
	check(observed.changes == 1, "one completed transaction publishes one profile change")
	check(not observed.changed_reentry, "profile-change callbacks cannot open another camp transaction")
	check(DungeonProfile.new().restore(JSON.parse_string(JSON.stringify(observed.snapshot))), "resource observers receive a restorable committed snapshot")
	return observed

func _test_building() -> void:
	var s := _fresh()
	var seen := _observe(s, s.upgrade_building.bind(3))
	check(int(seen.snapshot.buildings.get("3", 0)) == 1, "building ownership exists before payment notification")
	check(s.material(101) == 99700 and s.rank(s.profile.data.buildings, 3) == 1 and s.stat("building:upgraded") == 1, "construction commits one configured stage and payment")
	check(s.upgrade_building(3).success, "next independent construction works after notifications finish")

func _test_character() -> void:
	var s := _fresh()
	var seen := _observe(s, s.upgrade_character.bind(1))
	check(int(seen.snapshot.character_levels["1"]) == 2, "character growth precedes its resource notification")
	check(s.material(501) == 999 and s.rank(s.profile.data.character_levels, 1) == 2 and s.stat("character:upgraded") == 1, "one voucher buys exactly one character level")

func _test_work() -> void:
	var s := _fresh()
	s.profile.data.buildings["6"] = 2
	s.set_record("region:2", 1)
	var clock := {"now": 100000}
	s.utc_now = func(): return clock.now
	check(s.start_work(107).success, "voucher dispatch starts")
	clock.now += 1200
	var seen := _observe(s, s.collect_work.bind(107))
	check(int(seen.snapshot.stats.get("work:finished", 0)) == 1 and int(seen.snapshot.materials["501"]) == 1003, "work payment notification sees the completed payout and consumed progress")
	check(s.material(101) == 99950 and s.material(501) == 1003 and s.work_status(107).completed_quantity == 0, "dispatch consumes exactly one stored output and fee")
	check(s.stat("adventure:get:501") == 0 and not s.profile.data.run.active, "camp dispatch cannot be reclassified as adventure earnings")

func _test_meal() -> void:
	var s := _fresh()
	s.profile.data.buildings["7"] = 1
	var seen := _observe(s, s.research_meal.bind(70101100))
	check(int(seen.snapshot.recipes.get("70101100", 0)) == 1 and seen.snapshot.meal_selection == {"70101100": 1}, "recipe and temporary meal order precede payment events")
	check(s.material(101) == 99650 and s.material(10101) == 998 and s.material(10102) == 998 and s.stat("meal:research") == 1, "recipe research charges once")
	s = _fresh()
	s.profile.data.buildings["7"] = 1
	s.research_meal(70101100)
	seen = _observe(s, s.buy_meal)
	check(seen.snapshot.get("purchased_meals", {}) == {"70101100": 1} and seen.snapshot.get("meal_purchased", false), "paid meal snapshot includes regional purchase marker")
	check(s.material(101) == 99300 and s.material(10101) == 996 and s.material(10102) == 996, "meal purchase charges the order once")

func _test_npc() -> void:
	var s := _fresh()
	var seen := _observe(s, s.execute_npc_function.bind(100201))
	check(int(seen.snapshot.stats.get("npc:reward:100201", 0)) == 1 and int(seen.snapshot.stats.get("npc:finished:100201", 0)) == 1, "one-time NPC completion and reward flags precede reward notification")
	check(s.material(10101) == 1003 and s.stat("npc:executions:100201") == 1, "one-time NPC reward cannot be duplicated")
	check(not s.execute_npc_function(100201).success, "one-time NPC option remains consumed after notification")

func _test_tokens() -> void:
	var s := _fresh()
	s.profile.data.buildings["2"] = 1
	var token := int(s.relationship_tokens.ids()[0])
	s.set_record("token:" + str(token), 3)
	var seen := _observe(s, s.relationship_tokens.upgrade.bind(token))
	check(int(seen.snapshot.stats.get("token:" + str(token), 0)) == 4, "direct token module publishes the committed level")
	check(s.material(108) == 9700 and s.stat("token:" + str(token)) == 4, "direct token calls share the camp transaction boundary")

func _test_mall() -> void:
	var s := _fresh()
	s.profile.data.materials["90002"] = 1000
	var quote := s.offer_quote(20001)
	var seen := _observe(s, s.buy_mall.bind(20001))
	check(int(seen.snapshot.stats.get(str(quote.purchase), 0)) == 1 and int(seen.snapshot.materials["501"]) == 1010, "mall payment observers receive purchase count and the full bundle")
	check(s.material(90002) == 880 and s.material(501) == 1010 and s.stat(str(quote.purchase)) == 1, "mall bundle commits one charge and purchase")

func _test_material_box() -> void:
	var s := _fresh()
	s.profile.data.materials["801"] = 3
	var seen := _observe(s, s.open_material_box.bind(801))
	check(int(seen.snapshot.stats.get("box:801:opened", 0)) == 1 and int(seen.snapshot.materials["501"]) == 1005, "box payment observers receive the completed guaranteed reward and opening count")
	check(s.material(801) == 2 and s.material(501) == 1005 and s.stat("box:801:opened") == 1 and int(s.profile.data.run.random_step) == 1, "material box consumes one box and one random draw")
