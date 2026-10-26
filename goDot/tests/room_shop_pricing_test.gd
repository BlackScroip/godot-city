extends SceneTree

var checks := 0
var failures: Array[String] = []

class TestSystems extends DungeonSystems:
	var extra: Dictionary = {}
	var rolls: Array[int] = []
	func attributes(character: int = 0) -> Dictionary:
		var result = super.attributes(character)
		for key in extra: result[key] = result.get(key, 0) + extra[key]
		return result
	func next_random(maximum: int) -> int:
		if not rolls.is_empty(): return clampi(rolls.pop_front(), 0, maximum - 1)
		return super.next_random(maximum)

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	var catalog := DungeonCatalog.new()
	check(catalog.load_all(), "Catalog loads")
	for id in range(993001, 993013):
		_insert(catalog, "LootData", {"id": id, "ability_item_id": id, "loot_type": "普通遗物", "unlock_data_id": 0})
		_insert(catalog, "AbilityItems", {"ID": str(id), "Rare": 1, "MaxHaveCount": 1})
	var systems := TestSystems.new(catalog, DungeonProfile.new())
	check(systems.begin_run(261026, 1, 100).success, "Run starts")
	systems.grant_material(102, 100000)
	check(systems._shop_price(1, {}, 400) == 126, "Random markup multiplies the player-adjusted quote")
	check(systems._shop_price(1, {}, -800) == 45, "Deep offer discounts retain the regional half-price floor")
	check(systems._shop_price(1, {"ShopBasePriceAddRate": 1000, "ShopPriceAddRate": -1000}, 800) == 162, "Slot changes follow diminishing player discounts")
	check(systems._shop_supply_price("生命药水", {"ShopPriceAddRate": -1000}) == 80, "Supplies ignore ordinary discounts")
	check(systems._shop_supply_price("生命药水", {"PotionPriceAddRate": -500}) == 40, "Potion modifier applies to fixed supply prices")
	check(systems._shop_supply_price("生命药水", {"PotionPriceAddRate": -900}) == 8, "Native int(factor) zero leaves the one-magic floor for a ninety-percent supply discount")
	check(systems._shop_supply_price("生命药水", {"PotionPriceAddRate": 1500}) == 200, "Native int(factor) two retains the float32 quote for a 150-percent supply markup")
	check(systems._shop_supply_price("护甲", {"PotionPriceAddRate": 250}) == 150, "Armor uses the same separate supply modifier")
	check(systems._shop_supply_price("调查点数", {"PotionPriceAddRate": -2000}) == 75, "Supply quote retains the native derived half-price floor even for negative factors")

	var shop = _shop("dynamic", [993001, 993002, 993003, 993004])
	systems.profile.data.run.shops.append(shop)
	systems._reprice_shop(shop)
	check(shop.offers[0].price == 90, "Initial relic quote")
	systems.extra.ShopBasePriceAddRate = 1000
	check(systems.get_room_shop("dynamic").offers[0].price == 180, "Reopening recalculates prices from current attributes")
	systems.extra.ShopBasePriceAddRate = 0
	systems.extra.NormalShopPriceIncreasePerBuy = 100
	shop.offers[1].offer_change = -400
	shop.offers[0].price = 9999
	var before = systems.material(102)
	check(systems.buy_room_offer("dynamic", 993001).success, "Paid purchase succeeds")
	check(systems.material(102) == before - 90 and shop.buy_count == 1, "Transaction recalculates stale quotes before charging")
	check(shop.offers[1].price_change == -300 and shop.offers[1].price == 63, "Paid relic increments remaining quotes before the next transaction")
	systems.profile.data.run.counters.FreePurchaseAttempts = 1
	before = systems.material(102)
	check(systems.buy_room_offer("dynamic", 993002).success, "Free relic purchase succeeds")
	check(systems.material(102) == before and shop.buy_count == 1 and shop.offers[1].offer_change == 0, "Free purchases consume the slot offer without increasing purchase markup")
	var supply = systems.roll_pool(int(catalog.config.DefaultRecoverItemLootPoolId), 1)[0]
	shop.offers.append({"loot_id": supply, "price": 0, "sold": false, "offer_change": 0})
	check(systems.buy_room_offer("dynamic", supply).success and shop.buy_count == 1, "Paid consumables do not increase ordinary shop markup")
	systems.profile.data.run.region = 3
	check(systems.get_room_shop("dynamic").offers[2].price == 99, "Generated shop retains its original regional price basis")
	systems.profile.data.run.region = 1

	var changes = _shop("changes", [supply, 993005, 993006, 993007, 993008])
	systems.profile.data.run.counters.ShopPriceIncreaseCount = 2
	systems.profile.data.run.counters.ShopPriceDecreaseCount = 3
	systems.rolls.assign([0, 0, 0, 400, 0, 0, 0, 400])
	systems._roll_shop_offer_changes(changes)
	check(changes.offers[0].offer_change == 0, "Random changes exclude consumable slots")
	check(changes.offers.map(func(offer): return int(offer.offer_change)) == [0, 400, 800, -400, -800], "Increase slots are selected first and decrease slots cannot repeat them")
	systems.profile.data.run.counters.ShopPriceIncreaseCount = 0
	systems.profile.data.run.counters.ShopPriceDecreaseCount = 0
	systems.extra.clear()
	systems.profile.data.run.inventory["20150"] = 1
	var merchant = systems.get_room_shop("antique")
	check(merchant.offers.filter(func(offer): return int(offer.offer_change) < 0).size() == 1, "Real merchant antique triggers one random discount with MaxEffectCount zero")
	check(systems.profile.data.run.counters.ShopPriceDecreaseCount == 1, "Entering a shop starts fresh random-change counts")
	var second_merchant = systems.get_room_shop("antique-next")
	check(second_merchant.offers.filter(func(offer): return int(offer.offer_change) < 0).size() == 1 and systems.profile.data.run.counters.ShopPriceDecreaseCount == 1, "Unlimited antique record trigger works again without carrying previous shop counts")
	systems.profile.data.run.inventory.erase("20150")
	_insert(catalog, "LootData", {"id": 993020, "ability_item_id": 993020, "loot_type": "普通遗物", "unlock_data_id": 0})
	_insert(catalog, "AbilityItems", {"ID": "993020", "CombineDataList": [{"CombineDataType": "RecordTrigger", "ConditionList": [], "Data": {"TriggerEventType": "RogueEventType", "RogueEventTriggerData": {"EventType": "ShopPricingFixture"}, "MaxEffectCount": 1, "AddAttribute1": "shop:limited-trigger", "AddAttributeValue1": 1}}]})
	systems.profile.data.run.inventory["993020"] = 1
	systems.effects.dispatch("ShopPricingFixture")
	systems.effects.dispatch("ShopPricingFixture")
	check(systems.profile.data.run.counters.get("shop:limited-trigger", 0) == 1, "Positive RecordTrigger maximum still limits completed activations")
	systems.profile.data.run.inventory.erase("993020")

	systems.extra.ShopMaxRefreshTime = 4
	systems.extra.ShopRefreshCostByMagicEssence = 100
	var refreshed = _shop("refresh", [993005, 993006, 993007])
	refreshed.offers[0].sold = true
	refreshed.offers[1].offer_change = -500
	systems.profile.data.run.shops.append(refreshed)
	before = systems.material(102)
	check(systems.room_shop_status("refresh").refresh_cost == 100 and systems.refresh_room_shop("refresh").success, "First paid refresh uses the base cost")
	check(systems.material(102) == before - 100 and refreshed.offers[0].sold and refreshed.offers[0].loot_id == 993005, "Ordinary refresh preserves bought slots and charges exactly once")
	check(refreshed.offers[1].offer_change == -500, "Refresh preserves the discount for its unsold slot")
	check(systems.room_shop_status("refresh").refresh_cost == 200 and systems.refresh_room_shop("refresh").success, "Paid refresh cost doubles after successful use")
	systems.extra.ShopRefreshReplaceBoughtItems = 1
	check(systems.refresh_room_shop("refresh").success and not refreshed.offers[0].sold and refreshed.offers[0].offer_change == 0, "Logistics refresh restocks bought slots without reviving their consumed offer")
	systems.extra.DisableShopRefresh = 1
	before = systems.material(102)
	check(not systems.refresh_room_shop("refresh").success and systems.material(102) == before and refreshed.refreshes == 3, "Refresh prohibition rejects without money or allowance changes")
	systems.extra.DisableShopRefresh = 0
	systems.profile.data.materials["102"] = 0
	check(not systems.refresh_room_shop("refresh").success and refreshed.refreshes == 3, "Insufficient paid refresh leaves allowance intact")
	systems.grant_material(102, 10000)
	systems.profile.data.run.inventory["20408"] = 1
	systems.extra.clear()
	check(systems._shop_attributes().ShopRefreshCostByMagicEssence == 100, "Real shop voucher keeps its static modifier alongside the event trigger")
	systems.effects.dispatch("EnterNewNormalShop", "0")
	check(systems.profile.data.run.counters.FreePurchaseAttempts == 1, "Real shop voucher also retains its free purchase event")
	systems.profile.data.run.inventory.erase("20408")

	systems.profile.data.run.inventory["993009"] = 1
	systems.extra = {"ShopPriceAddRate": -800, "ShopBasePriceAddRate": 99.9, "SealLootGetMagicPointBonusPercent": 500}
	var seal = systems.shop_seal_quote(993009)
	check(seal.magic == 13, "Seal uses raw player discount and floating merchant modifier before integer bonus")
	systems.extra.ShopPriceAddRate = -1000
	check(systems.shop_seal_quote(993009).magic == 1, "Seal has its own one-magic floor rather than the purchase half-price floor")
	systems.extra = {"NormalShopPriceIncreasePerBuy": 100}
	systems._reprice_shop(shop)
	var restored_profile := DungeonProfile.new()
	check(restored_profile.restore(JSON.parse_string(JSON.stringify(systems.profile.data))), "Dynamic shop schema survives JSON restore")
	var restored := TestSystems.new(catalog, restored_profile)
	restored.extra = systems.extra.duplicate()
	var restored_shop = restored.get_room_shop("dynamic")
	check(restored_shop.buy_count == 1 and restored_shop.offers[1].offer_change == 0 and restored_shop.offers[2].price == 99, "Restored shop retains paid purchase count, consumed discounts, and current quotes")
	check(restored.room_shop_status("refresh").refresh_cost == 0, "Refresh quote responds to removed voucher instead of stale saved cost")
	for instance in [systems, restored]: instance.decorations = null
	print("ROOM_SHOP_PRICING_TEST ", JSON.stringify({"checks": checks, "passed": failures.is_empty(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func _shop(key: String, ids: Array) -> Dictionary:
	var offers: Array = []
	for id in ids: offers.append({"loot_id": id, "price": 0, "sold": false, "offer_change": 0})
	return {"key": key, "region": 1, "offers": offers, "refreshes": 0, "buy_count": 0, "paid_refreshes": 0}

func _insert(catalog, table: String, row: Dictionary) -> void:
	catalog.tables[table].append(row)
	catalog._indices[table][str(DungeonCatalog.row_id(row))] = row
