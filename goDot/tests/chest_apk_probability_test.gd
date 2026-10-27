extends SceneTree

const Rewards = preload("res://scripts/domain/loot_rewards.gd")
var checks := 0
var failures: Array[String] = []

class FixedRewards extends Rewards:
	var sample := 0
	func _init(owner) -> void:
		super(owner, _sample)
	func _sample(limit: int) -> int:
		return mini(sample, limit - 1)
	func _pool(result: Array, field: String, count: int = 1) -> void:
		for index in count:
			_item(result, {"LowRareAbilityItemLootPoolId": 990001, "DefaultRecoverItemLootPoolId": 990002, "DefaultArmorItemLootPoolId": 990003}[field])

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func ids(rows: Array) -> Array:
	return rows.filter(func(row): return not row.material).map(func(row): return int(row.id))

func _initialize() -> void:
	var catalog := DungeonCatalog.new()
	check(catalog.load_all(), "Authoritative chest configuration loads")
	var systems := DungeonSystems.new(catalog, DungeonProfile.new())
	check(systems.begin_run(1729, 1, 100).success, "Chest probability fixture starts")
	for quality in ["Normal", "Unusual", "Luxury", "Curse", "Curse_Final"]:
		catalog.config["TreasureBoxResDropData_" + quality] = {}
	var rewards := FixedRewards.new(systems)
	# Enumerate every RandomTools(0,1001) outcome, including its maximum.
	for quality in ["Normal", "Unusual", "Luxury", "Curse"]:
		var scroll_id := 13103 if quality == "Curse" else 13102
		var scrolls := 0
		for sample in 1002:
			rewards.sample = sample
			scrolls += ids(rewards.treasure(quality, 1, false, true, 1, {})).count(scroll_id)
		check(scrolls == {"Normal": 301, "Unusual": 801, "Luxury": 1001, "Curse": 1001}[quality], quality + " completion scroll respects all 1002 native outcomes")
	for quality in ["Normal", "Unusual", "Luxury", "Curse", "Curse_Final"]:
		rewards.sample = 0
		check(ids(rewards.treasure(quality, 2, false, true, 1, {})).count(13101) == 1, quality + " zero extra-scroll attribute still accepts roll zero")
		rewards.sample = 1
		check(not ids(rewards.treasure(quality, 2, false, true, 1, {})).has(13101), quality + " zero extra-scroll attribute rejects roll one")
	rewards.sample = 1001
	check(not ids(rewards.treasure("Normal", 2, false, true, 1, {"OpenTreasureBoxExtraGetSelectChara_Low": 1000})).has(13101), "Extra scroll threshold1000 rejects the inclusive maximum1001")
	rewards.sample = 0
	check(not ids(rewards.treasure("Normal", 2, false, true, 1, {"OpenTreasureBoxExtraGetSelectChara_Low": -1})).has(13101), "Negative extra-scroll threshold rejects zero")
	var high_bags := 0
	for sample in 1001:
		rewards.sample = sample
		high_bags += ids(rewards.treasure("Unusual", 2, false, true, 1, {})).count(14103)
	check(high_bags == 1, "Unusual base upgrade succeeds once among all1001 native outcomes at attribute zero")
	rewards.sample = 1000
	check(ids(rewards.treasure("Unusual", 2, false, true, 1, {"DropLuxuryBag": 999})).has(14102), "Unusual roll1000 rejects luxury threshold999")
	check(ids(rewards.treasure("Unusual", 2, false, true, 1, {"NormalBagUpgradeToHighBag": 999})).has(14102), "Middle-to-high reroll1000 rejects upgrade threshold999")
	check(ids(rewards.treasure("Unusual", 2, false, true, 1, {"NormalBagUpgradeToHighBag": 1000})).has(14103), "Middle-to-high threshold1000 includes endpoint1000")
	check(ids(rewards.treasure("Normal", 2, false, true, 1, {"TreasureBoxDropLowAbilityChance_Normal": 999})).count(990001) == 1, "Extra low item keeps Unity's distinct upper boundary")
	for bag_bonus in [-1, 0, 2]:
		for extra_bag in [0, 1, 5]:
			var attrs := {"ExtraRelicBagCount": bag_bonus, "BossTreasureBoxDropExtraHighLoot": extra_bag, "BossTreasureBoxDropExtraSuperTalentItem": 2.9}
			var curse := ids(rewards.treasure("Curse", 2, false, true, 1, attrs))
			check(curse.count(14103) == maxi(0, 1 + bag_bonus) + (1 if extra_bag >= 1 else 0), "Curse extra high bag is outside the repeating bag loop")
			check(curse.count(13103) == 2, "Curse extra super scroll count truncates and ignores completion chest gate")
	for quality in ["Normal", "Unusual", "Luxury", "Curse_Final"]:
		check(not ids(rewards.treasure(quality, 2, false, true, 1, {"BossTreasureBoxDropExtraSuperTalentItem": 2})).has(13103), quality + " excludes Curse-only extra super scrolls")
	for amount in [-1, 0, 0.9]:
		check(not ids(rewards.treasure("Curse", 2, false, true, 1, {"BossTreasureBoxDropExtraSuperTalentItem": amount})).has(13103), "Nonpositive truncated super-scroll count adds nothing")
	rewards.sample = 500
	var completed := ids(rewards.treasure("Curse", 1, false, true, 1, {"BossTreasureBoxDropExtraSuperTalentItem": 2}))
	check(completed.count(13103) == 3, "Curse completion scroll and two bonus scrolls accumulate independently")
	check(ids(rewards.treasure("Curse", 1, true, true, 1, {"BossTreasureBoxDropExtraSuperTalentItem": 2})).count(13103) == 2, "Curse entrance still receives its extra super scrolls")
	check(rewards.completion_quality({"Flow": "Entrance"}, {}) == "Normal", "Entrance starts with normal quality")
	check(rewards.completion_quality({"Flow": "Entrance"}, {"RegionEnterTreasureBoxType": 1.9}) == "Unusual", "Entrance quality truncates its attribute")
	check(rewards.completion_quality({"Flow": "Entrance"}, {"RegionEnterTreasureBoxType": 8}) == "Luxury", "Entrance quality caps at luxury")
	check(rewards.completion_quality({"Flow": "Treasure", "TreasureBoxType": "Unusual"}, {}) == "Unusual", "Treasure-only node retains packaged quality")
	for enemy_class in ["Normal", "Elite", "Boss"]:
		check(rewards.completion_quality({"FightType": "Regular", "EnemyClass": enemy_class}, {}) == {"Normal": "Normal", "Elite": "Unusual", "Boss": "Curse"}[enemy_class], "Regular completion quality follows enemy class " + enemy_class)
	check(rewards.completion_quality({"FightType": "Regular", "EnemyClass": "Boss", "FinalBoss": true}, {}) == "Curse_Final", "Final boss uses its distinct completion branch")
	check(rewards.completion_quality({"Flow": "TreasureTrial"}, {}) == "", "Trial chest choice stays independent")
	var dodge := {"FightType": "DodgeBattle", "FightData": {"BeHitCount_Lv3": 1, "BeHitCount_Lv2": 4, "BeHitCount_Lv1": 9}}
	check(rewards.completion_quality(dodge, {}) == "None", "Challenges have no completion box before their result")
	for hits in [0, 1, 3, 4, 8, 9]:
		var expected: String = {0: "Luxury", 1: "Unusual", 3: "Unusual", 4: "Normal", 8: "Normal", 9: "None"}[hits]
		check(rewards.completion_quality(dodge, {"ChallengeGoldUnlock": 1}, {"hits": hits}) == expected, "Dodge strict boundary at " + str(hits))
	check(rewards.completion_quality(dodge, {}, {"hits": 0}) == "Unusual", "Best challenge result still needs gold unlock")
	check(rewards.completion_quality(dodge, {"ChallengeGoldUnlock": 0.9}, {"hits": 0}) == "Unusual", "Gold unlock truncates fractional values")
	check(rewards.completion_quality(dodge, {"ChallengeGoldUnlock": 1, "DodgeRoomAddDodgeCount": 2.9}, {"hits": 2}) == "Luxury", "Dodge bonus adds truncated count to each threshold")
	var timed := {"FightType": "TimeLimit", "FightData": {"RewardTimeLimit_Lv3": 25, "RewardTimeLimit_Lv2": 40, "RewardTimeLimit_Lv1": 60}}
	for elapsed in [25.0, 25.99, 26.0, 40.0, 40.99, 41.0, 60.0, 60.99, 61.0]:
		var expected := "Luxury" if int(elapsed) <= 25 else "Unusual" if int(elapsed) <= 40 else "Normal" if int(elapsed) <= 60 else "None"
		check(rewards.completion_quality(timed, {"ChallengeGoldUnlock": 1}, {"elapsed": elapsed}) == expected, "TimeLimit inclusive boundary at " + str(elapsed))
	check(rewards.completion_quality(timed, {"ChallengeGoldUnlock": 1, "TimeLimitRoomAddTime": 5.9}, {"elapsed": 30}) == "Luxury", "TimeLimit bonus adds truncated seconds")
	var protect := {"FightType": "ProtectTarget", "FightData": {"RemainTargetHp_Lv3": 80, "RemainTargetHp_Lv2": 60}}
	for hp in [100, 80, 79, 60, 59, 1, 0]:
		var expected := "Luxury" if hp >= 80 else "Unusual" if hp >= 60 else "Normal" if hp > 0 else "None"
		check(rewards.completion_quality(protect, {"ChallengeGoldUnlock": 1}, {"target_hp": hp}) == expected, "Protection remaining health boundary at " + str(hp))
	check(rewards.completion_quality(protect, {"ChallengeGoldUnlock": 1, "RemainTargetAddHp": 1000}, {"target_hp": 9}) == "Normal", "Protection threshold cannot fall below ten")
	check(rewards.completion_quality(protect, {"ChallengeGoldUnlock": 1, "RemainTargetAddHp": 1000}, {"target_hp": 10}) == "Luxury", "Protection lower clamp includes ten")
	var endless := {"FightType": "Endless", "FightData": {"KillCount_Lv3": 100, "KillCount_Lv2": 50, "KillCount_Lv1": 20}}
	for kills in [19, 20, 49, 50, 99, 100]:
		var expected := "Luxury" if kills >= 100 else "Unusual" if kills >= 50 else "Normal" if kills >= 20 else "None"
		check(rewards.completion_quality(endless, {"ChallengeGoldUnlock": 1}, {"kills": kills}) == expected, "Endless kill boundary at " + str(kills))
	check(systems.room_treasure_quality("challenge", dodge) == "None", "Pending challenge suppresses its box")
	check(systems.room_treasure_quality("challenge", dodge, {"hits": 4}) == "Normal", "Result replaces pending quality")
	var clone := DungeonProfile.new()
	check(clone.restore(JSON.parse_string(JSON.stringify(systems.profile.data))), "Chest quality checkpoint restores")
	var restored := DungeonSystems.new(catalog, clone)
	check(restored.room_treasure_quality("challenge", dodge) == "Normal", "Checkpoint preserves earned quality without reevaluating result")
	restored.decorations = null
	systems.decorations = null
	print("CHEST_APK_PROBABILITY_TEST ", JSON.stringify({"checks": checks, "passed": failures.is_empty(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)
