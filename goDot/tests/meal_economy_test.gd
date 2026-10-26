extends SceneTree

const A = 70101000
const B = 70101020
const C = 70101100
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		push_error("MEAL FAIL: " + message)
		quit(1)
		assert(value, message)

func check_charge(before: Dictionary, after: Dictionary, price: Dictionary) -> void:
	for key in before:
		check(int(before[key]) - int(after.get(key, 0)) == int(price.get(key, 0)), "exact charge for " + str(key))

func run() -> void:
	var catalog = DungeonCatalog.new()
	check(catalog.load_all(), "load shipped catalog")
	check(load("res://scripts/menus.gd") is Script, "meal menu script parses")
	check(load("res://scripts/main.gd") is Script, "meal action dispatch script parses")
	var profile = DungeonProfile.new()
	var systems = DungeonSystems.new(catalog, profile)
	var resources = [101, 10101, 10102, 10201, 10202, 10301, 10302, 10401, 10402]
	for id in resources: systems.grant_material(id, 100000)
	var wallet = profile.data.materials.duplicate(true)
	check(not systems.research_meal(C).success, "research requires restaurant")
	check(not systems.buy_meal(A).success, "purchase requires restaurant")
	check(profile.data.materials == wallet, "locked actions charge nothing")
	profile.data.buildings["7"] = 1
	check(not systems.buy_meal(C).success, "unresearched dish cannot be purchased")
	check(profile.data.materials == wallet, "unresearched purchase is atomic")
	check(systems.meal_status(C).research_price == {"10101": 2, "10102": 2, "101": 350}, "rank-one research price")
	check(systems.research_meal(C).success, "research new dish")
	check_charge(wallet, profile.data.materials, {"10101": 2, "10102": 2, "101": 350})
	check(systems.rank(profile.data.recipes, C) == 1 and systems.stat("meal:research") == 1, "research advances one rank")
	check(profile.data.meal_selection == {str(C): 1} and profile.data.last_meals == {str(C): 1}, "new research selects the new dish and persists temporary order")
	check(systems.meal_order_status(true).can_ad, "research alone can prepare a researched temporary order for ad recook")
	wallet = profile.data.materials.duplicate(true)
	check(systems.research_meal(A).success, "upgrade known recipe")
	check_charge(wallet, profile.data.materials, {"10201": 1, "10202": 1, "101": 100})
	check(systems.rank(profile.data.recipes, A) == 2 and systems.stat("meal:upgraded") == 1, "upgrade records independently")
	check(profile.data.meal_selection == {str(A): 2} and profile.data.last_meals == {str(A): 2}, "research replaces prior selection with new rank")
	check(systems.purchased_meals().is_empty(), "research grants no meal buff")
	check(systems.select_meal(A).success, "select researched rank")
	check(systems.select_meal(A, 2).success and profile.data.meal_selection.size() == 1, "replace same dish rank in one slot")
	check(profile.data.last_meals == {str(A): 2}, "selection updates same temporary order used by recook")
	check(systems.select_meal(B).success, "select second dish")
	check(not systems.select_meal(C).success and systems.meal_order_limit() == 2, "restaurant rank one has two slots")
	profile.data.buildings["7"] = 3
	check(systems.select_meal(C).success and systems.meal_order_limit() == 3, "restaurant rank three has three slots")
	var order = {str(A): 2, str(B): 1, str(C): 1}
	var price = {"101": 600, "10101": 2, "10102": 4, "10201": 1, "10202": 1}
	check(systems.meal_order_status().price == price, "aggregate material quantities and gold")
	check(profile.data.meal_selection == order, "cart retains all dish ranks")
	var restored = DungeonProfile.new()
	check(restored.restore(JSON.parse_string(JSON.stringify(profile.data))), "restore cart from JSON")
	check(restored.data.meal_selection == order, "cart ranks survive save")
	profile.data.materials["10102"] = 3
	wallet = profile.data.materials.duplicate(true)
	check(not systems.buy_meal().success, "shared ingredient shortage rejects whole cart")
	check(profile.data.materials == wallet and profile.data.meal_selection == order, "failed ingredient payment preserves wallet and cart")
	profile.data.materials["10102"] = 100000
	profile.data.materials["101"] = 0
	wallet = profile.data.materials.duplicate(true)
	check(not systems.buy_meal().success, "gold shortage rejects whole cart")
	check(profile.data.materials == wallet and profile.data.meal_selection == order, "failed gold payment preserves wallet and cart")
	profile.data.materials["101"] = 100000
	wallet = profile.data.materials.duplicate(true)
	var recipes = profile.data.recipes.duplicate(true)
	check(systems.buy_meal().success, "purchase full cart")
	check_charge(wallet, profile.data.materials, price)
	check(profile.data.recipes == recipes, "payment does not research recipes")
	check(systems.purchased_meals() == order and profile.data.last_meals == order, "complete purchase retains full order")
	check(profile.data.meal_selection.is_empty() and profile.data.meal_purchased, "paid cart clears selection and marks region")
	var sources = systems.ability_sources()
	for ability in [70101002, 70101021, 70101101]: check(systems.rank(sources, ability) == 1, "activate one copy of meal ability " + str(ability))
	check(restored.restore(JSON.parse_string(JSON.stringify(profile.data))), "restore paid order from JSON")
	check(restored.data.purchased_meals == order and restored.data.last_meals == order and restored.data.meal_purchased, "purchased and last order survive save")
	check(not systems.recook_meal().success, "same-region quick recook is blocked")
	check(systems.begin_run(12345, 1, 100.0).success, "start adventure with purchased meals")
	check(systems.purchased_meals() == order, "starting adventure retains meals")
	check(not systems.buy_meal(A).success and not systems.research_meal(A).success, "normal purchase and research require camp")
	check(systems.complete_node("meal-r1-n1", 1, 1, false).success, "complete ordinary room")
	check(systems.purchased_meals() == order, "ordinary room retains meals")
	check(systems.complete_node("meal-r1-boss", 2, 1, true).success, "complete region")
	check(systems.purchased_meals().is_empty() and not profile.data.meal_purchased, "EffectType one expires at region completion")
	check(profile.data.last_meals == order, "region expiration retains last order")
	var ads = preload("res://scripts/domain/ad_rewards.gd").new(systems)
	var ad_context = {"kind": "meal", "id": 70101110, "level": 99}
	wallet = profile.data.materials.duplicate(true)
	check(ads.claim(ad_context, "meal-ad-one", true).success, "ad restores last full order during adventure")
	check(profile.data.materials == wallet and systems.purchased_meals() == order, "ad has no charge and cannot replace last order from context")
	check(not ads.claim(ad_context, "meal-ad-one", true).success, "receipt is consumed once")
	check(not ads.claim(ad_context, "meal-ad-two", true).success, "same-region repeat ad is blocked")
	check(not systems.complete_node("meal-r1-boss", 2, 1, true).success, "duplicate region occurrence is rejected")
	check(systems.purchased_meals() == order, "duplicate region completion does not expire recooked meals")
	check(systems.complete_node("meal-r2-boss", 3, 2, true).success, "next region completes")
	wallet = profile.data.materials.duplicate(true)
	check(systems.recook_meal().success, "gold recook is available in next region")
	check_charge(wallet, profile.data.materials, price)
	check(systems.purchased_meals() == order and profile.data.recipes == recipes, "gold recook restores full order without research")
	check(systems.end_run(false).success, "finish adventure")
	check(systems.purchased_meals().is_empty() and not profile.data.meal_purchased and profile.data.last_meals == order, "run end clears buffs and preserves last order")
	for index in 2:
		check(ads.claim(ad_context, "meal-skip-" + str(index), true).success, "remaining free skip " + str(index))
		systems.clear_invalid_meals("CompleteRegion")
	check(ads.free_skips() == 0 and not ads.claim(ad_context, "meal-skip-limit", true).success, "daily free skips capped independently of meal order")
	check(profile.validate(), "meal state remains valid")
	var invalid = profile.data.duplicate(true)
	invalid.last_meals[str(A)] = 1.5
	check(not restored.restore(invalid), "reject fractional meal rank")
	invalid = profile.data.duplicate(true)
	invalid.meal_purchased = 1
	check(not restored.restore(invalid), "reject non-boolean purchase marker")
	var legacy_profile = DungeonProfile.new()
	legacy_profile.data.buildings["7"] = 1
	legacy_profile.data.selected_meal = A
	legacy_profile.data.meal_rank = 1
	var legacy = DungeonSystems.new(catalog, legacy_profile)
	check(legacy.rank(legacy.ability_sources(), 70101001) == 1, "legacy one-dish buff remains effective")
	legacy.clear_invalid_meals("CompleteRegion")
	check(legacy_profile.data.last_meals == {str(A): 1} and legacy.meal_order_status(true).can_ad, "legacy regional expiration preserves recook order")
	profile.data.last_meals = {"99999999": 1, str(A): 99, str(C): 1}
	profile.data.recipes.erase(str(C))
	check(systems.meal_order_status(true).meals == {str(A): 2}, "recook skips missing and unresearched dishes and clamps rank to research")
	profile.data.last_meals = order.duplicate()
	profile.data.recipes = recipes.duplicate()
	profile.data.buildings["7"] = 1
	check(systems.meal_order_status(true).count == 2, "restored recook order obeys current restaurant capacity")
	profile.data.buildings["7"] = 3
	for id in [A, B, C]: check(systems.buy_meal(id).success, "normal paid order can merge purchased dish " + str(id))
	check(systems.research_meal(70101110).success and systems.buy_meal(70101110).success, "purchase another dish in a later cart")
	check(systems.purchased_meals().size() == 4 and profile.validate(), "selection capacity does not cap cumulative purchased dictionary")
	var row = catalog.find("CatMealData", A)
	var old_gold = row.NeedGold
	var old_materials = row.NeedMaterials
	row.NeedGold = "10|20"
	row.NeedMaterials = "10101:1;10102:2"
	check(systems._meal_price(row, 3) == {"10102": 2, "101": 20}, "short cost arrays repeat final entry")
	row.NeedGold = old_gold
	row.NeedMaterials = old_materials
	systems.decorations = null
	legacy.decorations = null
	print("MEAL ECONOMY PASS: %d checks; independent research/payment, cart limits, atomic full-order charges, abilities, JSON saves, regional expiry, paid/ad recook, receipt deduplication, legacy saves" % checks)
	quit(0)
