extends SceneTree

var checks := 0
var failures: Array[String] = []

class TestSystems extends DungeonSystems:
	var test_attributes: Dictionary = {}
	func attributes(_character: int = 0) -> Dictionary: return test_attributes

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	var catalog := DungeonCatalog.new()
	check(catalog.load_all(), "Catalog loads")
	var ids: Array = []
	for rare in range(1, 6):
		for gem in 2:
			var id := 990000 + rare * 10 + gem
			ids.append(id)
			_insert(catalog, "LootData", {"id": id, "ability_item_id": id, "loot_type": ["普通遗物", "生命宝石"][gem], "unlock_data_id": 0})
			_insert(catalog, "AbilityItems", {"Id": id, "Rare": rare, "MaxHaveCount": 99})
	_insert(catalog, "ItemPoolData", {"id": 990001, "sub_data_id_list": "990002,990003"})
	_insert(catalog, "ItemPoolSubData", {"id": 990002, "item_id_list_str": ",".join(ids.map(str)), "weight_list_str": "10", "unlock_data_id_list_str": ""})
	_insert(catalog, "ItemPoolSubData", {"id": 990003, "item_id_list_str": "990010,990011", "weight_list_str": "30,20", "unlock_data_id_list_str": ""})
	var systems := TestSystems.new(catalog, DungeonProfile.new())
	check(systems.begin_run(414, 1, 100).success, "Active run for loot weights")
	for rare in range(1, 6):
		systems.test_attributes["Star%dItemExtraWeightAddPercent" % rare] = 100.9
		systems.test_attributes["GemExtraWeightRare%dAddPercent" % rare] = 200.9
	var candidates: Array = systems._pool_candidates(990001, 0, {1: 5, 2: 5, 3: 5, 4: 5, 5: 5})
	check(candidates.size() == ids.size(), "Duplicate subpool IDs merge before rarity modification")
	for rare in range(1, 6):
		var relic := _weight(candidates, 990000 + rare * 10)
		var gem := _weight(candidates, 990001 + rare * 10)
		check(is_equal_approx(relic, (45 if rare == 1 else 15) * 1.1), "Rarity%d star modifier applies after base plus rarity addition" % rare)
		check(is_equal_approx(gem, (35 if rare == 1 else 15) * 1.3), "Rarity%d gem and star modifiers sum in same multiplier" % rare)
	var boosted := systems._pool_candidates(990001, 1000, {1: 5})
	check(is_equal_approx(_weight(boosted, 990011), 35 * 1.3 * 2), "Positive life-gem external multiplier follows summed attributes")
	check(is_equal_approx(_weight(systems._pool_candidates(990001, -1000, {1: 5}), 990011), 35 * 1.3), "Nonpositive external multiplier falls back to one like native")
	for kind in ["攻击宝石", "防御宝石", "生命宝石"]:
		catalog._indices.LootData["990011"].loot_type = kind
		check(is_equal_approx(_weight(systems._pool_candidates(990001), 990011), 30 * 1.3), "Gem modifier recognizes original type " + kind)
	catalog._indices.LootData["990011"].loot_type = "生命宝石"
	systems.test_attributes = {"Star1ItemExtraWeightAddPercent": 0.9, "GemExtraWeightRare1AddPercent": 0.9}
	check(is_equal_approx(_weight(systems._pool_candidates(990001), 990011), 30), "Native truncates star and gem fractions separately before sum")
	systems.test_attributes = {"Star1ItemExtraWeightAddPercent": -1500, "GemExtraWeightRare1AddPercent": 200}
	check(_weight(systems._pool_candidates(990001), 990011) == 0 and _weight(systems._pool_candidates(990001), 990010) == 0, "Negative final weights clamp to zero")
	check(_weight(systems._pool_candidates(990001, 0, {2: -1000}), 990020) == 0, "Negative bag rarity weight remains excluded")
	systems.test_attributes = {"Star2ItemExtraWeightAddPercent": -999}
	var tiny := systems._pool_candidates(990001, -999, {2: -9})
	check(is_equal_approx(_weight(tiny, 990021), 0.000001), "Small positive weight survives without integer rounding")
	var excluded := ids.filter(func(id): return id != 990021)
	check(systems.roll_pool(990001, 1, -999, excluded, {2: -9}) == [990021], "Very small sole positive candidate is drawable")
	systems.test_attributes = {}
	var drawn := systems.roll_pool(990001, 20)
	check(drawn.size() == ids.size(), "Weighted pool draws all positive candidates without duplicates")
	for id in ids: check(drawn.count(id) == 1, "Merged candidate appears once: " + str(id))
	var clone_profile := DungeonProfile.new()
	check(clone_profile.restore(JSON.parse_string(JSON.stringify(systems.profile.data))), "Pool draw RNG state survives JSON restore")
	var clone := TestSystems.new(catalog, clone_profile)
	check(systems.roll_pool(990001, 3) == clone.roll_pool(990001, 3), "Fractional weighted draw sequence survives restart")
	systems.decorations = null
	clone.decorations = null
	print("POOL_WEIGHT_MODIFIERS_TEST ", JSON.stringify({"checks": checks, "passed": failures.is_empty(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func _insert(catalog, table: String, row: Dictionary) -> void:
	catalog._indices[table][str(DungeonCatalog.row_id(row))] = row

func _weight(candidates: Array, id: int) -> float:
	for row in candidates:
		if int(row.id) == id: return float(row.weight)
	return -1
