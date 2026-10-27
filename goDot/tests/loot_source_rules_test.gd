extends SceneTree

const Rewards = preload("res://scripts/domain/loot_rewards.gd")
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func ids(drops: Array, material := false) -> Array:
	return drops.filter(func(x): return bool(x.material) == material).map(func(x): return int(x.id))

func _run() -> void:
	var catalog = DungeonCatalog.new()
	check(catalog.load_all(), "Catalog loads")
	var profile = DungeonProfile.new()
	var systems = DungeonSystems.new(catalog, profile)
	systems.begin_run(827461, 1, 100)
	var midpoint = Rewards.new(systems, func(limit): return 500000 if limit == 1000001 else mini(500, limit - 1))
	var minimum = Rewards.new(systems, func(_limit): return 0)
	var maximum = Rewards.new(systems, func(limit): return limit - 1)
	var sample := {"DropBase": 23, "DropLevelDepthFactor": 18, "DropRandomFactor": 200}
	check(midpoint.resource_amount(sample, 20) == 31, "Native multiplicative depth formula truncates 31.28 to31")
	check(minimum.resource_amount(sample, 20) == 25 and maximum.resource_amount(sample, 20) == 37, "Source +/-20 percent random range")
	check(minimum.resource_amount({"DropBase": 0}, 0) == 1, "Source amount has minimum one before chance")
	var normal = midpoint.treasure("Normal", 1, false, true, 20, {})
	check(not ids(normal).is_empty(), "Normal chest yields original low-pool item")
	var low_ids = systems._pool_candidates(int(catalog.config.LowRareAbilityItemLootPoolId)).map(func(x): return int(x.id))
	check(ids(normal).any(func(id): return low_ids.has(id)), "Normal chest uses low pool not default high pool")
	check(not ids(normal).has(13102), "Completion scroll fails original chance at roll500")
	check(ids(normal, true).has(101) and ids(normal, true).has(102), "Gold and magic resources emitted")
	check(not ids(normal, true).has(103), "Zero chance minerals never emitted despite min-one count")
	var unusual = midpoint.treasure("Unusual", 1, false, true, 1, {})
	check(ids(unusual).has(14102) and ids(unusual).has(13102), "Unusual distinct middle bag plus talent scroll")
	var luxury = midpoint.treasure("Luxury", 1, false, true, 1, {})
	check(ids(luxury).has(14103) and ids(luxury).has(13102), "Luxury high relic bag remains separate from normal talent scroll")
	var curse = midpoint.treasure("Curse", 1, false, true, 1, {})
	check(ids(curse).has(14103) and ids(curse).has(13103), "Curse high bag plus high talent scroll")
	check(ids(curse, true).has(107) and ids(curse, true).has(90002), "Additional resource list is restored")
	var final_chest = midpoint.treasure("Curse_Final", 1, false, true, 1, {})
	check(ids(final_chest).is_empty() and ids(final_chest, true).has(107) and ids(final_chest, true).has(90002), "Curse_Final keeps its own resources without inferred bag or scroll")
	check(ids(midpoint.treasure("Luxury", 2, false, true, 1, {})).has(14103), "Environmental noncompletion chest retains bag")
	check(not ids(midpoint.treasure("Luxury", 2, false, true, 1, {})).has(13102), "Noncompletion chest excludes completion scroll")
	check(ids(midpoint.treasure("Luxury", 1, true, true, 1, {})).has(13103), "First-region entrance luxury source high-scroll override")
	check(not ids(midpoint.treasure("Luxury", 1, true, false, 12, {})).has(13103), "Later-region entrance does not receive first-region override")
	var upgrades = midpoint.treasure("Unusual", 2, false, true, 1, {"ExtraRelicBagCount": 2, "NormalBagUpgradeToHighBag": 1000})
	check(ids(upgrades).count(14103) == 3 and not ids(upgrades).has(14102), "Extra bags and middle-to-high upgrade")
	check(ids(midpoint.monster("Normal", 1, {})).is_empty(), "Normal monsters have no invented18 percent default relic")
	check(ids(midpoint.monster("Boss", 1, {})).is_empty(), "Boss has no unconditional default relic")
	check(ids(midpoint.monster("Elite", 1, {"EliteDropExtraRelicBag": 1})) == [14101], "Elite source attribute grants one low selection bag independently of failed item rolls")
	check(ids(minimum.monster("Normal", 1, {})).size() == 1, "Ordinary source low-pool chance succeeds on roll zero")
	check(ids(midpoint.monster("Boss", 1, {"BossDropExtraChance": 1000})).size() == 1, "Boss extra default-pool branch uses native base count1")
	check(ids(maximum.treasure("Luxury", 1, false, true, 1, {}), true).is_empty(), "Resource roll1000 fails chance1000 as original strict boundary")
	check(midpoint.monster("Unknown", 1, {}).is_empty() and midpoint.treasure("Unknown", 1, false, true, 1, {}).is_empty(), "Invalid source kinds do not silently spawn normal rewards")
	var no_duplicates = midpoint.treasure("Normal", 2, false, true, 1, {"TreasureBoxDropLowAbilityChance_Normal": 1000})
	var unique = ids(no_duplicates)
	for id in unique: check(unique.count(id) == 1, "Chest pool excludes IDs already in same drop batch")
	var restored = DungeonProfile.new()
	check(restored.restore(JSON.parse_string(JSON.stringify(profile.data))), "Profile RNG persists")
	var clone = DungeonSystems.new(catalog, restored)
	check(JSON.stringify(systems.treasure_drops("Luxury", 1, false)) == JSON.stringify(clone.treasure_drops("Luxury", 1, false)), "Save/restore preserves deterministic source rolls")
	for quality in ["Low", "Middle", "High"]:
		systems.queue_loot_reward(quality, 1)
		var reward: Dictionary = profile.data.run.rewards.back()
		check(int(reward.pool_id) == int(catalog.config.DefaultAbilityItemLootPoolId), "All source bag qualities start from default pool")
		check(reward.quality == quality and reward.choices.size() == 3, "Bag quality and three distinct choices persist")
		for choice in reward.choices:
			var loot = catalog.find("LootData", int(choice))
			var rare = int(catalog.find("AbilityItems", int(loot.ability_item_id)).get("Rare", 0))
			check(not (quality == "Low" and rare == 5) and not (quality == "Middle" and rare == 1) and not (quality == "High" and rare < 3), "Native quality weights exclude zero-weight rarity")
		var old_pool: int = int(reward.pool_id)
		profile.data.run.counters.SelectRefreshTime = 1
		check(systems.refresh_loot_reward(str(reward.key)).success and int(reward.pool_id) == old_pool, "Refresh retains selected source pool and consumes charge")
	for id in ids(curse) + ids(curse, true):
		check(not catalog.find("LootData", id).is_empty() or not catalog.find("MaterialData", id).is_empty(), "Every emitted ID has source item data")
	print("LOOT_SOURCE_RULES_TEST ", JSON.stringify({"checks": checks, "passed": failures.is_empty(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)
