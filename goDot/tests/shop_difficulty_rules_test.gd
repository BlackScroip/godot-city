extends SceneTree

var checks := 0
var failures: Array[String] = []

class TestSystems extends DungeonSystems:
	var extra_attributes: Dictionary = {}
	var forced_random := true
	var chance_roll := 0
	var replacement_index := 1
	var random_limits: Array = []
	var pool_calls: Array = []
	func attributes(character: int = 0) -> Dictionary:
		var result = super.attributes(character)
		for key in extra_attributes: result[key] = result.get(key, 0) + extra_attributes[key]
		return result
	func next_random(maximum: int) -> int:
		if not forced_random: return super.next_random(maximum)
		random_limits.append(maximum)
		if maximum == 1000: return chance_roll
		return 0 if maximum == 16777217 else mini(replacement_index, maximum - 1)
	func roll_pool(pool: int, count: int, green: float = 0, excluded: Array = [], weights: Dictionary = {}) -> Array:
		pool_calls.append({"pool": pool, "count": count, "weights": weights.duplicate()})
		return super.roll_pool(pool, count, green, excluded, weights)

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	var catalog := DungeonCatalog.new()
	check(catalog.load_all(), "Catalog loads")
	var normal_ids: Array = []
	for rare in range(1, 6):
		var id := 992000 + rare
		normal_ids.append(id)
		_loot(catalog, id, rare)
	for id in [992101, 992102, 992103]: _loot(catalog, id, 5)
	_loot(catalog, 992104, 5)
	catalog._indices.LootData["992101"].loot_type = "诅咒遗物"
	catalog._indices.LootData["992101"]["pure_group_id"] = 77
	catalog._indices.LootData["992104"].loot_type = "净化遗物"
	catalog._indices.LootData["992104"]["pure_group_id"] = 77
	_insert(catalog, "UnlockData", {"id": 992500, "unlock_condition_type": 500, "unlock_param1": 99})
	catalog._indices.LootData["992102"].unlock_data_id = 992500
	_pool(catalog, 992201, normal_ids)
	_pool(catalog, 992202, [992101, 992102, 992103])
	catalog.config.DefaultAbilityItemLootPoolId = 992201
	catalog.config.AbilityItemLootPoolId_Curse = 992202
	var systems := TestSystems.new(catalog, DungeonProfile.new())
	check(systems.begin_run(619, 1, 100).success, "Run starts")
	systems.profile.data.run.inventory["992103"] = 1

	check(systems._shop_rarity_weights({}) == {1: 0, 2: 0, 3: 50, 4: 40, 5: 30}, "Ordinary shop uses APK base rarity additions")
	check(systems._shop_rarity_weights({"ShopItemQualityIncrease": 1000}) == {1: 0, 2: 0, 3: 50, 4: 80, 5: 60}, "Tier seven doubles fourth and fifth rarity additions")
	check(systems._shop_rarity_weights({"ShopItemQualityIncrease": 999.9})[4] == 79 and systems._shop_rarity_weights({"ShopItemQualityIncrease": 999.9})[5] == 59, "Quality multiplication precedes truncation")
	check(systems._shop_rarity_weights({"ShopItemQualityIncrease": -25.1})[4] == 39 and systems._shop_rarity_weights({"ShopItemQualityIncrease": -25.1})[5] == 30, "Quality additions truncate toward zero separately")
	check(systems._shop_base_price(0) == 90 and systems._shop_base_price(9) == 390, "Price rarity clamps to authored one through five")
	systems.profile.data.run.region = 2
	check(systems._shop_base_price(3) == 306, "Region price truncates after multiplicative and fixed depth additions")
	systems.profile.data.run.region = 1
	systems.profile.data.run.difficulty = 3
	check(systems._shop_base_price(1) == 90, "Difficulty price threshold has not activated at index three")
	systems.profile.data.run.difficulty = 4
	check(systems._shop_base_price(1) == 116 and systems._shop_base_price(5) == 506, "Difficulty threshold uses native float32 arithmetic before truncation")
	for pair in [[-100, -100], [-300, -300], [-350, -325], [-400, -350], [-500, -375], [-600, -400], [-700, -425], [-800, -450], [-900, -475], [-1000, -500], [-5000, -500], [250, 250]]:
		check(is_equal_approx(systems._shop_price_rate(pair[0]), pair[1]), "APK diminishing discount conversion: " + str(pair[0]))
	systems.profile.data.run.difficulty = 0
	check(systems._shop_price(1, {"ShopBasePriceAddRate": 99.9}) == 98, "Base price rate truncates before price multiplication; final price truncates")
	check(systems._shop_price(1, {"ShopBasePriceAddRate": 1000, "ShopPriceAddRate": -1000}) == 90, "Player discount follows static base price multiplier")
	check(systems._shop_price(1, {"ShopBasePriceAddRate": -1000}) == 45, "Native price floor is half the unmodified regional price")

	for level in [6, 7, 8, 10]:
		systems.profile.data.run.difficulty = level
		systems.pool_calls.clear()
		var shop = {"offers": []}
		systems._fill_shop(shop)
		check(systems.pool_calls.size() == 1 and systems.pool_calls[0].weights == {1: 0, 2: 0, 3: 50, 4: 40 if level == 6 else 80, 5: 30 if level == 6 else 60}, "Actual shop consumes inherited difficulty quality at " + str(level))
		check(shop.offers.size() == 3 and shop.offers[0].price == (116 if level == 6 else 232), "Actual shop consumes inherited difficulty price at " + str(level))
		check(systems.pool_calls.all(func(call): return int(call.pool) != 992202), "Shop does not trigger curse replacement at " + str(level))
		var ordinary = [992001, 992002, 992003]
		systems._replace_normal_reward_with_curse(ordinary, "Low")
		check(ordinary.has(992101) == (level >= 8), "Actual normal or Chaos tier inherits curse chance at " + str(level))
	systems.set_record("shop:level", 3)
	systems.profile.data.run.region = 2
	var combined = systems._shop_attributes()
	check(combined.ShopBasePriceAddRate == 950 and combined.ShopShowCount == 1, "Shop investment and active difficulty combine exactly once")
	var invested = {"offers": []}
	systems._fill_shop(invested)
	check(invested.offers.size() == 4 and invested.offers[0].price == 362, "Invested shop applies base multiplier to the complete regional price")
	systems.set_record("shop:level", 4)
	var saved_shop = systems.get_room_shop("shop-persistence")
	saved_shop.offers[0].sold = true
	var saved = saved_shop.duplicate(true)
	systems.extra_attributes.ShopItemQualityIncrease = 5000
	check(systems.get_room_shop("shop-persistence") == saved, "Reopening shop preserves generated offers, prices and sold slots")
	check(systems.refresh_room_shop("shop-persistence").success and not saved_shop.offers[0].sold, "Authorized refresh generates fresh offers with current modifiers")
	check(not systems.refresh_room_shop("shop-persistence").success, "Refresh still respects investment limit")

	systems.extra_attributes.clear()
	systems.profile.data.run.difficulty = 8
	for quality in ["Low", "Middle", "High"]:
		systems.pool_calls.clear()
		systems.chance_roll = 99
		systems.queue_loot_reward(quality, 1)
		var reward: Dictionary = systems.profile.data.run.rewards.back()
		check(reward.choices.size() == 3 and reward.choices[1] == 992101 and reward.choices.count(992101) == 1, "Native 100 of 1000 endpoint replaces exactly one " + quality + " candidate")
		check(systems.pool_calls.size() == 2 and systems.pool_calls[1].count == 1, "Replacement draws exactly one curse " + quality + " candidate")
		check(not reward.choices.has(992102) and not reward.choices.has(992103), "Replacement respects locked and already owned curses " + quality)
	var untouched = [992001, 992002, 992003]
	systems.chance_roll = 100
	systems._replace_normal_reward_with_curse(untouched, "Low")
	check(untouched == [992001, 992002, 992003], "101 of 1000 does not satisfy native 100 chance")
	systems.extra_attributes.CurseRelicInNormalPool = -99.1
	systems.random_limits.clear()
	systems._replace_normal_reward_with_curse(untouched, "Low")
	check(not systems.random_limits.has(1000), "Chance truncates below one before consuming random state")
	systems.extra_attributes.CurseRelicInNormalPool = 900
	systems.chance_roll = 999
	systems._replace_normal_reward_with_curse(untouched, "Low")
	check(untouched[1] == 992101, "1000 of 1000 succeeds with inherited plus item chance")
	for quality in ["Curse", "OldDay", "Reward", "Sprites", ""]:
		var special = [992001, 992002, 992003]
		systems.random_limits.clear()
		systems._replace_normal_reward_with_curse(special, quality)
		check(special == [992001, 992002, 992003] and systems.random_limits.is_empty(), "Special reward avoids normal curse hook: " + quality)
	systems.profile.data.run.inventory["992104"] = 1
	var purified = [992001, 992002, 992003]
	systems._replace_normal_reward_with_curse(purified, "Low")
	check(purified == [992001, 992002, 992003] and systems._reward_pure_group_exclusions().has(992101), "Owned purified relic excludes the curse in its pure group")
	systems.profile.data.run.inventory.erase("992104")
	systems.profile.data.run.inventory["992101"] = 1
	check(systems._reward_pure_group_exclusions().has(992104), "Owned curse excludes the purified relic in its pure group")
	var exhausted = [992001, 992002, 992003]
	systems._replace_normal_reward_with_curse(exhausted, "Low")
	check(exhausted == [992001, 992002, 992003], "Exhausted curse candidates leave ordinary choices intact")
	systems.random_limits.clear()
	systems._replace_normal_reward_with_curse([], "Low")
	check(systems.random_limits.is_empty(), "Empty initial normal pool bypasses curse roll before guaranteed fallback")
	systems.profile.data.run.inventory.erase("992101")
	systems.profile.data.run.counters.SelectRefreshTime = 1
	systems.pool_calls.clear()
	var reward_key = str(systems.profile.data.run.rewards[0].key)
	check(systems.refresh_loot_reward(reward_key).success and systems.pool_calls.size() == 1 and systems.pool_calls[0].pool == 992201, "Reward refresh uses original pool without repeating curse replacement")
	var restored_profile := DungeonProfile.new()
	check(restored_profile.restore(JSON.parse_string(JSON.stringify(systems.profile.data))), "Shop and reward state restores")
	var restored := TestSystems.new(catalog, restored_profile)
	var restored_shop = restored.get_room_shop("shop-persistence")
	check(restored.pool_calls.is_empty() and int(restored_shop.refreshes) == int(saved_shop.refreshes) and restored_shop.offers.size() == saved_shop.offers.size(), "Reload reopens the persisted shop without generating offers")
	for i in saved_shop.offers.size():
		var old_offer: Dictionary = saved_shop.offers[i]
		var restored_offer: Dictionary = restored_shop.offers[i]
		check(int(old_offer.loot_id) == int(restored_offer.loot_id) and int(old_offer.price) == int(restored_offer.price) and old_offer.sold == restored_offer.sold, "Reload preserves generated shop item, price and sold state at " + str(i))
	for i in systems.profile.data.run.rewards.size():
		check(restored.profile.data.run.rewards[i].choices == systems.profile.data.run.rewards[i].choices, "Reload preserves generated reward choices at " + str(i))
	for instance in [systems, restored]: instance.decorations = null
	print("SHOP_DIFFICULTY_RULES_TEST ", JSON.stringify({"checks": checks, "passed": failures.is_empty(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func _insert(catalog, table: String, row: Dictionary) -> void:
	catalog.tables[table].append(row)
	catalog._indices[table][str(DungeonCatalog.row_id(row))] = row

func _loot(catalog, id: int, rarity: int) -> void:
	_insert(catalog, "LootData", {"id": id, "ability_item_id": id, "loot_type": "普通遗物", "unlock_data_id": 0})
	_insert(catalog, "AbilityItems", {"ID": str(id), "Rare": rarity, "MaxHaveCount": 1})

func _pool(catalog, id: int, ids: Array) -> void:
	_insert(catalog, "ItemPoolData", {"id": id, "sub_data_id_list": str(id)})
	_insert(catalog, "ItemPoolSubData", {"id": id, "item_id_list_str": ",".join(ids.map(str)), "weight_list_str": "100", "unlock_data_id_list_str": ""})
