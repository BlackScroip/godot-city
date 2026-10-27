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
	for rate in ["Normal", "Elite", "Boss"]:
		var coin_attr: String = "DropFreeCoinChanceAdd_" + rate
		var coin_pass: Array = at149.monster(rate, 1, {coin_attr: 150, "DropFreeCoinFactor": 10000}).filter(func(row): return row.material and int(row.id) == 90002)
		check(coin_pass.size() == 1 and int(coin_pass[0].amount) == 1, "Rank coin bonus drops exactly one, independently of free-coin quantity modifier: " + rate)
		check(not material_ids(at150.monster(rate, 1, {coin_attr: 150})).has(90002), "Rank coin bonus uses strict threshold150: " + rate)
		check(not material_ids(at149.monster(rate, 1, {coin_attr: 149.9})).has(90002), "Rank coin bonus truncates fractional chance: " + rate)
		check(not material_ids(at1000.monster(rate, 1, {coin_attr: 1000})).has(90002), "Rank coin threshold1000 rejects roll1000: " + rate)
		check(material_ids(at1000.monster(rate, 1, {coin_attr: 1001})).has(90002), "Rank coin threshold1001 accepts all source outcomes: " + rate)
		var wrong_rank := "Elite" if rate == "Normal" else "Normal"
		check(not material_ids(at149.monster(rate, 1, {"DropFreeCoinChanceAdd_" + wrong_rank: 1001})).has(90002), "Coin bonus does not leak between ranks: " + rate)
		var mineral: Array = at149.monster(rate, 1, {"DropMineralMatChanceAdd_" + rate: 1001}).filter(func(row): return row.material and int(row.id) == 103)
		check(mineral.size() == 1 and int(mineral[0].amount) == 2, "Monster mineral adds source initial count one to computed minimum one: " + rate)
	for rate in ["Normal", "Elite", "Boss"]: catalog.config["Default" + ("Enemy" if rate == "Normal" else rate) + "DropResPoolData"] = {}
	var zero = Rewards.new(systems, func(_limit): return 0)
	for rate in ["Normal", "Elite"]:
		var attempts := 1 if rate == "Normal" else 3
		check(item_ids(zero.monster(rate, 1, {})).size() == attempts, "Source rank uses all successful low-rarity attempts for " + rate)
		var recovery := {"EnemyDropRecoverRate": 1, "EliteEnemyDropRecoverRate": 1}
		var recovered: Array = item_ids(zero.monster(rate, 1, recovery))
		check(recovered.size() == attempts + 1 and recovered.filter(func(id): return str(catalog.find("LootData", id).loot_type) == "生命药水").size() == 1, "Source recovery item is independent of rank equipment for " + rate)
		check(item_ids(zero.monster(rate, 1, {"EnemyDropRecoverRate": 0, "EliteEnemyDropRecoverRate": 0})).size() == attempts, "Zero recovery chance adds no recovery item for " + rate)
		check(item_ids(zero.monster(rate, 1, {"EnemyDropLowAbilityChance_" + rate: -1000})).is_empty(), "Zero low-rarity chance rejects even roll zero for " + rate)
	var at50 = Rewards.new(systems, func(limit): return mini(50, limit - 1))
	var at51 = Rewards.new(systems, func(limit): return mini(51, limit - 1))
	check(item_ids(at50.monster("Normal", 1, {})).size() == 1 and item_ids(at51.monster("Normal", 1, {})).is_empty(), "Ordinary low-rarity threshold50 includes50 and rejects51")
	var at200 = Rewards.new(systems, func(limit): return mini(200, limit - 1))
	var at201 = Rewards.new(systems, func(limit): return mini(201, limit - 1))
	check(item_ids(at200.monster("Elite", 1, {})).size() == 3 and item_ids(at201.monster("Elite", 1, {})).is_empty(), "Elite low-rarity threshold200 includes200 and rejects201 on three attempts")
	check(item_ids(at200.monster("Normal", 1, {"EnemyDropLowAbilityChance_Normal": 100000})).size() == 1 and item_ids(at201.monster("Normal", 1, {"EnemyDropLowAbilityChance_Normal": 100000})).is_empty(), "Ordinary modifier retains source chance cap200")
	check(item_ids(at1000.monster("Elite", 1, {"EnemyDropLowAbilityChance_Elite": 100000})).size() == 3, "Elite modifier cap1000 includes endpoint1000")
	check(item_ids(at499.monster("Elite", 1, {"EliteDropExtraRelicBag": 5})) == [14101], "Elite attribute adds one low bag even above one")
	check(item_ids(zero.monster("Normal", 1, {"EliteDropExtraRelicBag": 1})).size() == 1, "Elite bag attribute cannot add a bag to ordinary enemies")
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
