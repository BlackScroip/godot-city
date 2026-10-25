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
	print("SETTLEMENT_RULES_TEST ", JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
