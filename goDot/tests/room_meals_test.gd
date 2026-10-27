extends SceneTree

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	var catalog = load("res://scripts/domain/catalog.gd").new()
	_check(catalog.load_all(), "source catalog loads")
	var profile = load("res://scripts/domain/profile.gd").new()
	var systems = load("res://scripts/domain/systems.gd").new(catalog, profile)
	var shop = load("res://scripts/domain/room_meals.gd").new(systems)
	profile.data.buildings["7"] = 3
	var dishes: Array = []
	for row in catalog.rows("CatMealData"):
		var eligible := true
		for gate in DungeonCatalog.ids(row.get("UnlockDataId", "")):
			if gate > 0 and not systems.is_unlocked(gate): eligible = false
		if eligible: dishes.append(int(row.Id))
	_check(dishes.size() >= 4, "source has enough unlocked recipes")
	if dishes.size() < 4:
		quit(1)
		return
	for id in dishes: profile.data.recipes[str(id)] = 1
	for id in dishes:
		var price: Dictionary = systems._meal_price(catalog.find("CatMealData", id), 1)
		for resource in price: profile.data.materials[str(resource)] = 100000
	_check(not shop.buy(dishes[0]).success, "room shop cannot purchase outside a run")
	systems.begin_run(7524, 1, 100)
	_check(not systems.buy_meal(dishes[0]).success, "ordinary camp action remains unavailable during a run")
	var first: Dictionary = shop.meal_status(dishes[0])
	var before: int = systems.material(101)
	var materials_before: Dictionary = profile.data.materials.duplicate()
	_check(shop.buy(dishes[0]).success, "room shop buys a researched dish during a run")
	_check(systems.material(101) == before - int(first.price.get("101", 0)), "shop charges source permanent gold")
	for resource in first.price:
		_check(systems.material(int(resource)) == int(materials_before[resource]) - int(first.price[resource]), "shop charges exact source ingredient or gold: " + str(resource))
	_check(systems.purchased_meals().has(str(dishes[0])) and profile.data.meal_purchased, "purchase joins existing effect storage and sets region recook flag")
	_check(shop.buy(dishes[0]).success, "ordinary shop permits another purchase in the same region")
	_check(systems.purchased_meals().size() == 1, "same recipe updates its purchased level without stacking entries")
	_check(not shop.buy(dishes[0], 2).success, "shop rejects unresearched recipe levels")
	_check(shop.select_meal(dishes[0]).success and shop.select_meal(dishes[1]).success and shop.select_meal(dishes[2]).success, "level-three restaurant permits three selected dishes")
	_check(not shop.select_meal(dishes[3]).success, "shop enforces the source three-dish order limit")
	var order: Dictionary = profile.data.meal_selection.duplicate()
	_check(shop.buy().success and systems.purchased_meals().size() == 3, "full order merges all purchased dishes")
	_check(profile.data.meal_selection.is_empty() and profile.data.last_meals == order, "purchase clears selection and preserves the last order")
	profile.data.buildings["7"] = 2
	_check(not shop.order_status(order).can_buy, "lower restaurant level limits an order to two dishes")
	var wallet: Dictionary = profile.data.materials.duplicate()
	_check(not shop.order_status({"9999999": 1}).can_buy and not shop.buy(9999999).success, "unknown dishes fail without spending")
	_check(profile.data.materials == wallet, "failed purchase preserves all materials")
	profile.data.materials["101"] = 0
	_check(not shop.buy(dishes[0]).success, "insufficient permanent gold blocks the order")
	systems.clear_invalid_meals("CompleteRegion")
	for key in systems.purchased_meals():
		_check(int(catalog.find("CatMealData", int(key)).get("EffectType", 1)) != 1, "region completion removes source region-lifetime effects")
	_check(not profile.data.meal_purchased and profile.data.last_meals == order, "region completion reopens recook and retains last order")
	systems.clear_invalid_meals("CompleteRun")
	_check(systems.purchased_meals().is_empty(), "run completion clears purchased meal effects")
	if failures.is_empty(): print("room_meals_test PASS: %d checks" % checks)
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
