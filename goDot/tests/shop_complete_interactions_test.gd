extends SceneTree

const ROOM_MEALS = preload("res://scripts/domain/room_meals.gd")
var catalog = DungeonCatalog.new()
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("SHOP COMPLETE: " + message)

func fresh():
	var systems = DungeonSystems.new(catalog, DungeonProfile.new())
	systems.begin_run(20261028, 1, 100)
	systems.grant_material(102, 100000)
	return systems

func _run() -> void:
	check(catalog.load_all(), "source catalog loads")
	_test_room_purchase()
	_test_room_investment()
	_test_room_refresh()
	_test_room_meals()
	_test_gem_instances()
	_test_gem_payment()
	_test_gem_effects()
	await _test_room_page()
	print(JSON.stringify({"suite": "shop_complete_interactions", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func _test_room_purchase() -> void:
	var systems = fresh()
	var shop: Dictionary = systems.get_room_shop("purchase")
	var offer: Dictionary = shop.offers[3]
	var before: int = systems.material(102)
	var price: int = int(offer.price)
	var nested: Array = []
	var snapshots: Array = []
	var callback = func(event):
		if event.type != "resource_spent" or int(event.id) != 102: return
		snapshots.append(systems.profile.data.duplicate(true))
		if nested.is_empty():
			nested.append({})
			nested[0] = systems.buy_room_offer("purchase", int(offer.loot_id))
	systems.gameplay_event.connect(callback)
	check(systems.buy_room_offer("purchase", int(offer.loot_id)).success, "room purchase succeeds")
	check(nested.size() == 1 and not nested[0].success, "room purchase cannot reenter its own payment callback")
	check(systems.material(102) == before - price and offer.sold, "room purchase pays once and sells once")
	check(snapshots.size() == 1 and snapshots[0].run.shops[0].offers[3].sold, "payment observers see committed stock")
	check(int(snapshots[0].run.inventory.get(str(offer.loot_id), 0)) == 1, "payment observers see the awarded relic")
	systems.gameplay_event.disconnect(callback)
	var seal: Dictionary = systems.shop_seal_quote(int(offer.loot_id))
	var nested_seal: Array = []
	var seal_callback = func(event):
		if event.type != "resource_gained" or int(event.id) != 102 or not nested_seal.is_empty(): return
		nested_seal.append({})
		nested_seal[0] = systems.seal_room_loot("purchase", int(offer.loot_id))
	systems.gameplay_event.connect(seal_callback)
	check(systems.seal_room_loot("purchase", int(offer.loot_id)).success, "seal succeeds")
	check(nested_seal.size() == 1 and not nested_seal[0].success, "seal payout cannot reenter")
	check(systems.material(102) == before - price + int(seal.magic), "seal pays once")
	systems.gameplay_event.disconnect(seal_callback)

func _test_room_investment() -> void:
	var systems = fresh()
	systems.get_room_shop("investment")
	var status: Dictionary = systems.room_shop_status("investment")
	var before: int = systems.material(102)
	var nested: Array = []
	var observed: Array = []
	var callback = func(event):
		if event.type != "resource_spent" or int(event.id) != 102: return
		observed.append(systems.stat("shop:invested"))
		if nested.is_empty():
			nested.append({})
			nested[0] = systems.invest_shop()
	systems.gameplay_event.connect(callback)
	check(systems.invest_shop().success, "investment succeeds")
	check(nested.size() == 1 and not nested[0].success, "investment cannot reenter payment callback")
	check(observed == [int(status.deposit)] and systems.material(102) == before - int(status.deposit), "investment progress and payment commit together")
	systems.gameplay_event.disconnect(callback)

func _test_room_refresh() -> void:
	var systems = fresh()
	systems.set_record("shop:level", 6)
	var shop: Dictionary = systems.get_room_shop("refresh")
	var nested: Array = []
	var callback = func():
		if nested.is_empty():
			nested.append({})
			nested[0] = systems.refresh_room_shop("refresh")
	systems.changed.connect(callback)
	check(systems.refresh_room_shop("refresh").success, "room refresh succeeds")
	check(int(shop.refreshes) == 1 and nested.size() == 1 and not nested[0].success, "refresh callback cannot consume another refresh")
	systems.changed.disconnect(callback)

func _test_room_meals() -> void:
	var systems = fresh()
	systems.profile.data.buildings["7"] = 3
	var meals = ROOM_MEALS.new(systems)
	var id := 70101000
	var price: Dictionary = systems._meal_price(catalog.find("CatMealData", id), 1)
	for resource in price: systems.profile.data.materials[str(resource)] = 100000
	var before: Dictionary = systems.profile.data.materials.duplicate()
	var nested: Array = []
	var observed: Array = []
	var callback = func(event):
		if event.type != "resource_spent": return
		observed.append(systems.purchased_meals().duplicate())
		if nested.is_empty():
			nested.append({})
			nested[0] = meals.buy(id)
	systems.gameplay_event.connect(callback)
	check(meals.buy(id).success, "room food purchase succeeds")
	check(nested.size() == 1 and not nested[0].success, "food payment callback cannot order twice")
	check(not observed.is_empty() and observed[0].has(str(id)), "food payment observers see purchased buff")
	for resource in price: check(systems.material(int(resource)) == int(before[str(resource)]) - int(price[resource]), "food charges ingredient once: " + str(resource))
	systems.gameplay_event.disconnect(callback)

func _test_gem_instances() -> void:
	var systems = fresh()
	for region in range(1, 8):
		systems.profile.data.run.region = region
		var key := "room:%d:marker:803" % region
		var before_rng: int = systems.profile.data.run.random_step
		var status: Dictionary = systems.gem_offering_status(key)
		check(status.can_buy and status.remaining == 1 and int(status.price) == region * 100, "source regional gem price: " + str(region))
		check(systems.profile.data.run.random_step == before_rng and status.offer.offers.is_empty(), "opening merchant does not roll or reveal reward: " + str(region))
		var result: Dictionary = systems.buy_gem_offering(str(status.key), false)
		check(result.success and result.drops.size() == 1, "source base gem reward count: " + str(region))
		check(not systems.buy_gem_offering(str(status.key), false).success and not systems.gem_offering_status(key).can_buy, "each merchant is consumed once: " + str(region))
		check(systems.profile.data.run.inventory.is_empty(), "world drop mode leaves acquisition to ground pickup: " + str(region))
		var reopened: Dictionary = systems.get_gem_offering(key)
		check(reopened.used and reopened.offers.size() == 1, "merchant reentry retains consumed reward: " + str(region))
	var restored_profile = DungeonProfile.new()
	check(restored_profile.restore(JSON.parse_string(JSON.stringify(systems.profile.data))), "merchant state survives valid JSON checkpoint")
	var restored = DungeonSystems.new(catalog, restored_profile)
	check(restored.gem_offering_status("room:7:marker:803").used, "restored merchant cannot pay again")
	check(restored.gem_offering_status("room:7:marker:804").can_buy, "a different merchant in the same region remains available")

func _test_gem_payment() -> void:
	var systems = fresh()
	systems.profile.data.materials["102"] = 0
	var status: Dictionary = systems.gem_offering_status("free")
	var before_rng: int = systems.profile.data.run.random_step
	check(not status.can_buy and not systems.buy_gem_offering(status.key).success, "unfunded gem trade fails")
	check(not status.offer.used and systems.profile.data.run.random_step == before_rng, "failed gem trade keeps state and RNG")
	systems.profile.data.run.counters["GemShopFreeCostCount"] = 1
	check(systems.gem_offering_status("free").free, "free offering overrides missing magic")
	check(systems.buy_gem_offering(status.key).success and systems.material(102) == 0, "free offering delivers without payment")
	check(int(systems.profile.data.run.counters.GemShopFreeCostCount) == 0 and not systems.gem_offering_status("another").can_buy, "free offering allowance consumes once")
	systems.grant_material(102, 1000)
	status = systems.gem_offering_status("atomic")
	var nested: Array = []
	var snapshots: Array = []
	var callback = func(event):
		if event.type != "resource_spent" or int(event.id) != 102: return
		snapshots.append(status.offer.duplicate(true))
		if nested.is_empty():
			nested.append({})
			nested[0] = systems.buy_gem_offering(status.key)
	systems.gameplay_event.connect(callback)
	check(systems.buy_gem_offering(status.key).success, "paid offering succeeds")
	check(nested.size() == 1 and not nested[0].success and systems.material(102) == 900, "gem resource callback cannot buy twice")
	check(snapshots.size() == 1 and snapshots[0].used and snapshots[0].offers.size() == 1, "gem payment observers see committed reward ledger")
	systems.gameplay_event.disconnect(callback)

func _test_gem_effects() -> void:
	var systems = fresh()
	systems.profile.data.run.inventory["21183"] = 1
	var status: Dictionary = systems.gem_offering_status("rod")
	check(systems.buy_gem_offering(status.key).drops.size() == 2, "source fishing rod grants an additional gem")
	var candidates: Array = systems._gem_offering_candidates({"GemShopManDropChanceAddRate_GreenGem": -1000, "GemShopManDropChanceAddRate_BlueGem": -1000})
	check(not candidates.is_empty() and candidates.all(func(entry): return catalog.find("LootData", int(entry.id)).loot_type == "攻击宝石"), "all three color multipliers affect the real gem pool")
	systems = fresh()
	systems.profile.data.run.inventory["22151"] = 1
	for index in 3:
		status = systems.gem_offering_status("curse:" + str(index))
		check(status.price == 300, "curse applies source +200 percent gem price")
		var result: Dictionary = systems.buy_gem_offering(status.key)
		check(result.success and result.drops.size() == (2 if index == 2 else 1), "third offering purifies before generating its reward")
	check(systems.rank(systems.profile.data.run.inventory, 22151) == 0 and systems.rank(systems.profile.data.run.inventory, 22152) == 1, "gem event purifies the actual source relic")
	check(systems.gem_offering_status("purified").price == 100, "purification removes price curse")

func _test_room_page() -> void:
	var page = preload("res://scripts/presentation/room_shop.gd").new()
	root.add_child(page)
	page.size = Vector2(844, 390)
	var row = {"title": "Relic", "description": "", "loot_id": 20150, "price": 90, "sold": false}
	page.configure([row], {"magic": 100, "free": 0, "shop": {"level": 1, "deposit": 10, "remaining": 5, "next_needed": 100, "refresh_remaining": 0, "can_refresh": false}})
	page._show_item(row)
	check(is_instance_valid(page.modal), "purchase detail opens")
	page.configure([row], {"magic": 500, "free": 2, "shop": {"level": 2, "deposit": 50, "remaining": 4, "next_needed": 350, "refresh_remaining": 1, "can_refresh": true, "refresh_cost": 30}})
	check(not is_instance_valid(page.modal), "reconfiguration closes stale purchase quote")
	check(page.magic_text.text == "500" and page.free_text.text == "2" and page.level_text.text == "2", "merchant view refreshes resource and level state")
	check(page.deposit.text == "50 存入" and not page.refresh.disabled and page.refresh_cost.text == "30 魔力", "merchant view refreshes deposit and refresh controls")
	var emitted: Array = []
	page.command.connect(func(kind, id, extra): emitted.append([kind, id, extra]))
	page.deposit.pressed.emit()
	check(emitted == [["invest_room_shop", 50, 0]], "deposit emits current quote after reconfiguration")
	row.sold = true
	page._show_item(row)
	var confirm: Button = page.modal.find_child("Confirm", true, false)
	check(confirm.disabled and confirm.text == "已售罄", "sold detail cannot confirm even without a supplied status label")
	page.queue_free()
	await process_frame
