extends SceneTree

const Catalog = preload("res://scripts/domain/catalog.gd")
const Profile = preload("res://scripts/domain/profile.gd")
const Systems = preload("res://scripts/domain/systems.gd")
var assertions := 0
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message)

func _initialize() -> void:
	var catalog = Catalog.new()
	check(catalog.load_all(), "Adventure data loads")
	check(catalog.rows("RogueLevelDifficultyInfluencerData").size() == 101, "New APK difficulty table is present")
	var profile = Profile.new()
	var systems = Systems.new(catalog, profile)
	check(systems.difficulty_unlocked(0), "New profile can select difficulty zero")
	for level in range(1, 11):
		check(not systems.difficulty_unlocked(level), "New profile cannot skip difficulty %d" % level)
		var before = profile.data.duplicate(true)
		check(not systems.begin_run(17, 1, 500, level).success and profile.data == before, "Locked run start preserves state")
	for level in [-1, 11]:
		check(not systems.difficulty_unlocked(level) and not systems.begin_run(17, 1, 500, level).success, "Unknown difficulty cannot start")
	check(not systems.select_chaos_level(1).success and not systems.claim_chaos_rewards().success, "Chaos actions start locked")
	for level in range(10):
		var status = systems.difficulty_status(level)
		check(status.unlocked and status.can_start, "Next ordinary difficulty is available")
		check(systems.begin_run(17 + level, 1, 500, level).success, "Unlocked run begins")
		check(not systems.difficulty_status(level).can_start and not systems.begin_run(17, 1, 500, level).success, "Active run blocks preparation and a second run")
		check(systems.end_run(false).success and not systems.difficulty_unlocked(level + 1), "Failure cannot unlock the next difficulty")
		check(systems.begin_run(27 + level, 1, 500, level).success and systems.end_run(true).success, "Ordinary victory records a clear")
		check(systems.stat("difficulty:win:" + str(level)) == 1 and systems.difficulty_unlocked(level + 1), "A single clear unlocks exactly the next difficulty")
		if level < 9: check(not systems.difficulty_unlocked(level + 2), "Clear cannot unlock a later tier")
	check(systems.difficulty_status(10).category == "Chaos" and systems.difficulty_status(10).tier == 1, "Ladder ten maps to Chaos tier one")
	var normal = systems.difficulty_attributes(1)
	check(normal.get("DropGoldFactor", 0) == 200 and normal.get("DropFreeCoinFactor", 0) == 100, "Normal one applies APK gold and crystal bonuses")
	check(not normal.has("DropMagicPointFactor"), "Disabled magic essence bonus is excluded")
	check(systems.difficulty_attributes(2).get("DropGoldFactor", 0) == 500, "Difficulty reward tiers replace lower values without accumulating")
	check(systems.difficulty_attributes(9).get("DropGoldFactor", 0) == 5000, "Normal nine applies its authored gold bonus")
	var chaos = systems.difficulty_attributes(10)
	check(chaos.get("DropGoldFactor", 0) == 6000 and chaos.get("DropFreeCoinFactor", 0) == 2000 and chaos.get("DropMineralMatFactor", 0) == 5000, "Chaos overrides normal reward values")
	check(systems.difficulty_status(0).rewards.is_empty(), "Difficulty zero has no additional rewards")
	for level in range(11):
		check(systems.difficulty_status(level).rewards.all(func(row): return row.attribute != "DropMagicPointFactor"), "Preparation filters disabled bonuses")
	profile.data.run["outcome"] = {"pending": true}
	check(not systems.difficulty_status(0).can_start and not systems.begin_run(17, 1, 500).success, "Unfinished settlement blocks a new run")
	profile.data.run.erase("outcome")
	check(systems.selected_chaos_level() == 1 and systems.chaos_max_level() == 15, "Chaos begins at layer one and caps at fifteen")
	check(systems.chaos_drop_rate_multiplier() == 1.0 and systems.chaos_drop_rate_multiplier(1) == 1.5 and systems.chaos_drop_rate_multiplier(10) == 6.0 and systems.chaos_drop_rate_multiplier(15) == 6.0, "Chaos ornament drop multipliers match the APK config")
	check(not systems.select_chaos_level(2).success, "Future chaos layers cannot be selected")
	check(systems.begin_run(117, 1, 500, 10).success and profile.data.run.counters.chaos_level == 1, "Run captures selected chaos layer")
	check(systems.chaos_drop_rate_multiplier() == 1.5, "Active chaos uses the captured layer for ornament drops")
	check(not systems.select_chaos_level(1).success and not systems.claim_chaos_rewards().success, "Active chaos run blocks selection and claims")
	check(systems.end_run(true).success and systems.chaos_cleared_level() == 1 and systems.selected_chaos_level() == 2, "First chaos clear opens layer two")
	var status = systems.difficulty_status(10)
	check(status.unclaimed_chaos_rewards == {"90002": 500, "504": 25}, "First clear has the exact APK material rewards")
	check(status.chaos_rewards[0].available and not status.chaos_rewards[1].available and not status.chaos_rewards[2].unlocked, "Reward rows distinguish claimable, next and locked layers")
	var crystals = systems.material(90002)
	check(systems.claim_chaos_rewards().success and systems.material(90002) == crystals + 500 and systems.material(504) == 25, "Claim grants first-clear rewards once")
	var after_claim = profile.data.duplicate(true)
	check(not systems.claim_chaos_rewards().success and profile.data == after_claim, "Repeat claim cannot duplicate materials")
	check(systems.select_chaos_level(1).success and systems.begin_run(118, 1, 500, 10).success and systems.end_run(true).success, "Completed chaos layer can be replayed")
	check(systems.chaos_cleared_level() == 1 and systems.difficulty_status(10).unclaimed_chaos_rewards.is_empty(), "Replay does not advance chaos or grant another first clear")
	check(systems.select_chaos_level(2).success and systems.begin_run(119, 1, 500, 10).success and systems.end_run(true).success, "Selecting next unlocked chaos layer advances once")
	check(systems.chaos_cleared_level() == 2 and systems.difficulty_status(10).unclaimed_chaos_rewards == {"90002": 600, "504": 25}, "Second layer preserves individual reward amount")
	for layer in range(3, 16):
		check(systems.select_chaos_level(layer).success, "Each completed frontier unlocks one next layer")
		check(systems.begin_run(120 + layer, 1, 500, 10).success and systems.end_run(true).success, "Each chaos frontier can be cleared")
	check(systems.chaos_cleared_level() == 15 and systems.selected_chaos_level() == 15 and not systems.select_chaos_level(16).success, "Maximum chaos layer stays capped")
	var pending = systems.difficulty_status(10).unclaimed_chaos_rewards
	var sum_rewards: Dictionary = {}
	for layer in range(2, 16):
		for key in Systems.costs(catalog.config.ChaosLevelRewardDict[str(layer)]): sum_rewards[key] = int(sum_rewards.get(key, 0)) + int(Systems.costs(catalog.config.ChaosLevelRewardDict[str(layer)])[key])
	check(pending == sum_rewards and systems.claim_chaos_rewards().success, "Claim-all merges every unclaimed chaos layer")
	profile.data.character_levels["2"] = 1
	check(systems.chaos_cleared_level(2) == 0 and systems.selected_chaos_level(2) == 1 and systems.difficulty_status(10, 2).unclaimed_chaos_rewards.is_empty(), "Chaos progression and claimed rewards are per character")
	var restored = Profile.new()
	check(restored.restore(JSON.parse_string(JSON.stringify(profile.data))), "Difficulty records survive profile serialization")
	var reloaded = Systems.new(catalog, restored)
	check(reloaded.chaos_cleared_level(1) == 15 and reloaded.difficulty_unlocked(10) and reloaded.difficulty_status(10, 1).unclaimed_chaos_rewards.is_empty(), "Reload keeps unlocks, chaos cap and claim history")
	var legacy = Profile.new()
	legacy.data.stats["wins"] = 1
	check(Systems.new(catalog, legacy).difficulty_unlocked(1), "Legacy victory retains the first difficulty unlock")
	var preparation = systems.adventure_preparation_status(0)
	check(not preparation.tokens_unlocked and not preparation.extra_challenge_unlocked, "Empty profile preparation sidebars stay locked")
	profile.data.buildings["2"] = 3
	check(not systems.adventure_preparation_status(0).tokens_unlocked, "Guild construction alone does not unlock the preparation token panel")
	var token = catalog.rows("RelationshipTokenData")[0]
	systems.set_record("token:" + str(int(token.material_id)), 1)
	check(systems.adventure_preparation_status(0).tokens_unlocked, "Owning a token unlocks its preparation panel")
	profile.data.buildings["5"] = 1
	check(not systems.adventure_preparation_status(0).extra_challenge_unlocked, "First commission facility level cannot use extra challenges")
	profile.data.buildings["5"] = 2
	check(systems.adventure_preparation_status(0).extra_challenge_unlocked, "Second commission facility level unlocks extra challenges")
	print("ADVENTURE_DIFFICULTY ", JSON.stringify({"passed": failures.is_empty(), "assertions": assertions, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
