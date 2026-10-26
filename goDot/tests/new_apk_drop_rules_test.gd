extends SceneTree

const Rewards = preload("res://scripts/domain/loot_rewards.gd")
var failures: Array[String] = []
var checks := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func item_ids(rows: Array) -> Array:
	return rows.filter(func(row): return not row.material).map(func(row): return int(row.id))

func material_ids(rows: Array) -> Array:
	return rows.filter(func(row): return row.material).map(func(row): return int(row.id))

func _initialize() -> void:
	var catalog = DungeonCatalog.new()
	check(catalog.load_all(), "New APK catalogs load")
	var systems = DungeonSystems.new(catalog, DungeonProfile.new())
	systems.begin_run(1729, 1, 100)
	check(catalog.config.EnemyExtraDropLowRareAbilityItemChanceArray.map(func(x): return int(x)) == [50, 200, 350], "New APK rank probabilities")
	check(catalog.config.EnemyExtraDropLowRareAbilityItemMaxCountArray.map(func(x): return int(x)) == [1, 3, 5], "New APK rank attempt counts")
	check(catalog.rows("EnemyData").size() == 60, "New rank lookup covers all sixty enemies")
	for id in [13002, 23002, 110012, 410011]: check(not catalog.find("EnemyData", id).is_empty(), "New enemy has a drop rank: %d" % id)
	var at149 = Rewards.new(systems, func(limit): return 500000 if limit == 1000001 else mini(149, limit - 1))
	var at150 = Rewards.new(systems, func(limit): return 500000 if limit == 1000001 else mini(150, limit - 1))
	var at499 = Rewards.new(systems, func(limit): return 500000 if limit == 1000001 else mini(499, limit - 1))
	var at500 = Rewards.new(systems, func(limit): return 500000 if limit == 1000001 else mini(500, limit - 1))
	var at999 = Rewards.new(systems, func(limit): return 500000 if limit == 1000001 else mini(999, limit - 1))
	var at1000 = Rewards.new(systems, func(limit): return 500000 if limit == 1000001 else limit - 1)
	check(material_ids(at149.monster("Normal", 1, {})) == [101, 102], "Ordinary source gold500 and magic150 both succeed below150")
	check(material_ids(at150.monster("Normal", 1, {})) == [101], "Ordinary magic roll150 fails its strict chance150")
	check(material_ids(at499.monster("Normal", 1, {})) == [101] and material_ids(at500.monster("Normal", 1, {})).is_empty(), "Ordinary gold boundary499 succeeds and500 fails")
	check(material_ids(at499.monster("Elite", 1, {})) == [101, 102] and material_ids(at500.monster("Elite", 1, {})) == [101], "Elite gold1000 and magic500 retain independent source chances")
	for rate in ["Elite", "Boss"]:
		check(material_ids(at999.monster(rate, 1, {})).has(101) and material_ids(at1000.monster(rate, 1, {})).is_empty(), "Configured chance1000 retains1000/1001 boundary for " + rate)
	var boss_resources := at999.monster("Boss", 20, {}).filter(func(row): return row.material)
	check(boss_resources.size() == 2 and int(boss_resources[0].amount) == 100 and int(boss_resources[1].amount) == 100, "Boss gold and magic use source base50 with multiplicative depth growth")
	for rate in ["Normal", "Elite", "Boss"]: catalog.config["Default" + ("Enemy" if rate == "Normal" else rate) + "DropResPoolData"] = {}
	var zero = Rewards.new(systems, func(_limit): return 0)
	for rate in ["Normal", "Elite"]:
		check(item_ids(zero.monster(rate, 1, {})).is_empty(), "Requested lord-only equipment rule also blocks successful source rolls for " + rate)
		var forced := {"EnemyDropLowAbilityChance_Normal": 100000, "EnemyDropLowAbilityChance_Elite": 100000, "EliteDropExtraRelicBag": 1, "BossDropExtraChance": 5000}
		check(item_ids(zero.monster(rate, 1, forced)).is_empty(), "Attributes cannot restore equipment or bags for " + rate)
		var recovery := {"EnemyDropRecoverRate": 1, "EliteEnemyDropRecoverRate": 1}
		var recovered: Array = item_ids(zero.monster(rate, 1, recovery))
		check(recovered.size() == 1 and recovered.all(func(id): return str(catalog.find("LootData", id).loot_type) == "生命药水"), "Lord-only equipment restriction preserves source recovery items for " + rate)
		check(item_ids(zero.monster(rate, 1, {"EnemyDropRecoverRate": 0, "EliteEnemyDropRecoverRate": 0})).is_empty(), "Zero recovery chance never succeeds for " + rate)
	check(zero._round_even(50.5) == 50 and zero._round_even(51.5) == 52, "Native round-to-even ties remain exact")
	var at350 = Rewards.new(systems, func(_limit): return 350)
	check(item_ids(at350.monster("Boss", 1, {})).size() == 5, "Boss performs five low-rarity attempts")
	var at351 = Rewards.new(systems, func(_limit): return 351)
	check(item_ids(at351.monster("Boss", 1, {})).is_empty(), "Boss roll351 fails configured chance350")
	var at354 = Rewards.new(systems, func(_limit): return 354)
	check(item_ids(at354.monster("Boss", 1, {"EnemyDropLowAbilityChance_Boss": 10})).size() == 5, "Boss modifier multiplies350 by1.01 and rounds353.5 to354")
	check(item_ids(at354.monster("Boss", 1, {"EnemyDropLowAbilityChance_Boss": 9})).is_empty(), "Boss modifier retains native truncation and chance rounding")
	var at501 = Rewards.new(systems, func(limit): return mini(501, limit - 1))
	check(item_ids(at501.monster("Boss", 1, {"BossDropExtraChance": 2500})).size() == 2, "Boss extra chance2500 yields two guaranteed drops above remainder")
	check(item_ids(at500.monster("Boss", 1, {"BossDropExtraChance": 2500})).size() == 3, "Boss remainder500 includes exact boundary")
	check(int(catalog.config.SelectTalentIfMaxChangeToMaterialPoint_Normal) == 300 and int(catalog.config.SelectTalentIfMaxChangeToMaterialPoint_High) == 500, "Full talent conversion uses new quality amounts")
	for level in [3, 4, 5, 10]:
		systems.profile.data.run.difficulty = level
		for rank in 3:
			var materials: Array = at501.monster(["Normal", "Elite", "Boss"][rank], 1, {}).filter(func(row): return row.material and int(row.id) == 108)
			var expected: int = 0 if level < 4 else [1, 20, 100][rank] if level == 4 else [1, 30, 150][rank]
			check(materials.is_empty() if expected == 0 else materials.size() == 1 and int(materials[0].amount) == expected, "Difficulty%d rank%d fixed token upgrade material count" % [level, rank])
	for level in range(10): systems.set_record("difficulty:win:" + str(level), 1)
	systems.end_run(false)
	check(systems.begin_run(91, 1, 100, 10).success, "Unlocked chaos run captures its layer")
	var first = Rewards.new(systems, func(_limit): return 0)
	var low_boundary = Rewards.new(systems, func(limit): return mini(44, limit - 1))
	var high_boundary = Rewards.new(systems, func(limit): return mini(45, limit - 1))
	var drops: Array = []
	low_boundary._amplifiers(drops, 0, {})
	check(drops.size() == 1, "Chaos1 ordinary tier1 chance30 times1.5 includes roll45")
	drops.clear()
	high_boundary._amplifiers(drops, 0, {})
	check(drops.is_empty(), "Chaos1 ordinary tier1 roll46 fails45")
	drops.clear()
	first._amplifiers(drops, 2, {"BlessingPlusAmplifyDropRateMulti": -1000})
	check(drops.is_empty(), "Zero blessing multiplier suppresses ornament drops")
	var clone = DungeonProfile.new()
	check(clone.restore(JSON.parse_string(JSON.stringify(systems.profile.data))), "Chaos drop state survives save/restore")
	var clone_systems = DungeonSystems.new(catalog, clone)
	check(JSON.stringify(systems.monster_drops(13002)) == JSON.stringify(clone_systems.monster_drops(13002)), "New boss probability sequence survives save/restore")
	systems.decorations = null
	clone_systems.decorations = null
	print("NEW_APK_DROP_RULES_TEST ", JSON.stringify({"checks": checks, "passed": failures.is_empty(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)
