extends SceneTree

var checks := 0
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	var catalog = DungeonCatalog.new()
	catalog.load_all()
	var profile = DungeonProfile.new()
	var systems = DungeonSystems.new(catalog, profile)
	for example in [[1, 1, 0, 0], [2, 1, 50, 1], [3, 1, 100, 1], [4, 1, 150, 2], [1, 2, 50, 1], [10, 3, 550, 6]]:
		var quote = systems.settlement_experience(example[0], example[1], 999)
		check(quote.experience == example[2] and quote.vouchers == example[3], "APK depth/region experience conversion %s" % [example])
	profile.data.stats["blessing"] = 1
	check(systems.settlement_experience(4, 1, 0).vouchers == 3, "Offline blessing doubles effective experience")
	profile.data.stats["blessing"] = 0
	systems.begin_run(7, 1, 100, 0)
	profile.data.run.health = 0
	profile.data.run.counters["RevivalRemainCount"] = 2
	check(systems.revive().success and profile.data.run.health == 30, "Default revival restores thirty percent")
	check(systems.revival_protection_seconds() == 1, "Default protection is one second")
	check(not systems.revive().success and systems.revival_count() == 1, "Alive player cannot consume another revival")
	profile.data.talents["317"] = 2
	profile.data.run.health = 0
	check(systems.revive().success and profile.data.run.health == 50, "Recovered talent adds twenty percent to the base revival")
	profile.data.run.health = 0
	check(not systems.revive().success and profile.data.run.health == 0, "No remaining revival cannot restore health")
	profile.data.run.max_health = 99
	profile.data.run.counters["RevivalRemainCount"] = 1
	check(systems.revive().success and is_equal_approx(profile.data.run.health, 49.5), "Native fractional health ratio is not rounded up")
	systems.end_run(false)
	profile.data.run["outcome"] = {"stage": "summary", "vouchers": 4, "experience_claimed": false}
	var before = systems.material(501)
	check(not systems.begin_run(8, 1, 100).success, "Pending settlement cannot be overwritten by new run")
	check(systems.claim_settlement_experience().success and systems.material(501) == before + 4, "Settlement grants expected vouchers")
	check(not systems.claim_settlement_experience().success and systems.material(501) == before + 4, "Settlement grant is idempotent")
	_test_camp_cleanup(catalog)
	print("SETTLEMENT_RULES_TEST ", JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)

func _test_camp_cleanup(catalog: DungeonCatalog) -> void:
	for victory in [false, true]:
		var profile = DungeonProfile.new()
		var systems = DungeonSystems.new(catalog, profile)
		profile.data.talents["317"] = 2
		profile.data.discovered_loot = [11001]
		profile.data.character_levels["1"] = 5
		systems.begin_run(12, 1, 100)
		profile.data.run.inventory["11001"] = 1
		profile.data.run.talents["101"] = 1
		profile.data.run.counters["SearchPoint"] = 20
		profile.data.run["region_rewards"] = [{"AttributeType": "AtkAddFixed", "Value": 10}]
		profile.data.run.battle = {"player": {"buffs": [1]}}
		for id in [101, 102, 103, 90002, 10101]: systems.grant_material(id, 10)
		var active_run = profile.data.run.duplicate(true)
		check(not systems.clear_completed_run() and profile.data.run == active_run, "Camp cleanup preserves active adventure and regional travel")
		systems.end_run(victory)
		profile.data.run["outcome"] = {"stage": "summary", "vouchers": 4, "experience_claimed": false}
		var pending_run = profile.data.run.duplicate(true)
		check(not systems.clear_completed_run() and profile.data.run == pending_run, "Camp cleanup preserves pending settlement")
		systems.claim_settlement_experience()
		profile.data.run.outcome.stage = "rewards"
		pending_run = profile.data.run.duplicate(true)
		check(not systems.clear_completed_run() and profile.data.run == pending_run, "Reward conversion keeps temporary items until settlement closes")
		var persistent = profile.data.duplicate(true)
		persistent.erase("run")
		persistent.materials["102"] = 0
		profile.data.run.erase("outcome")
		check(systems.clear_completed_run(), "Completed settlement permits camp cleanup: victory=%s" % victory)
		check(profile.data.run == DungeonProfile.new_run(), "Camp removes all run items, talents, resources, buffs and progress")
		var actual = profile.data.duplicate(true)
		actual.erase("run")
		check(actual == persistent, "Camp preserves converted vouchers, permanent resources, discoveries and upgrades")
		check(systems.material(501) == 4 and systems.material(102) == 0, "Converted vouchers remain while temporary magic is zero")
		check(systems.clear_completed_run() and profile.data.run == DungeonProfile.new_run(), "Repeated camp cleanup is idempotent")
		check(profile.restore(profile.data.duplicate(true)), "Clean camp state survives profile serialization")
		check(systems.begin_run(13, 1, 100).success and profile.data.run.inventory.is_empty() and profile.data.run.talents.is_empty(), "Next adventure starts without previous items or talents")
