extends SceneTree

const Choices = preload("res://scripts/domain/room_choices.gd")
var checks := 0
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/campaign.json"))
	var boss_count := 0
	for room in source.Nodes:
		if str(room.get("EnemyClass", "")) != "Boss": continue
		boss_count += 1
		var limit := float(room.FightData.BossBattleRankTime[0])
		check(Choices.sacrifice_spawn_eligible(room, limit - 0.01), "Fast boss clear reveals the altar: " + str(room.Id))
		check(not Choices.sacrifice_spawn_eligible(room, limit), "Exact first threshold does not reveal the altar: " + str(room.Id))
		check(not Choices.sacrifice_spawn_eligible(room, limit + 0.01), "Slow boss clear does not reveal the altar: " + str(room.Id))
	check(boss_count == 28, "All 28 imported boss-node variants use source time limits")
	var room := {"FightType": "Regular", "EnemyClass": "Boss", "FightData": {"BossBattleRankTime": [45, 100, 180, 240]}}
	check(Choices.sacrifice_spawn_eligible(room, 53.99, {"BossRatingTimeAddRate": 200}), "20 percent boss-rating bonus extends 45 seconds to 54")
	check(not Choices.sacrifice_spawn_eligible(room, 54.0, {"BossRatingTimeAddRate": 200}), "Extended first threshold is still exclusive")
	check(Choices.sacrifice_spawn_eligible(room, 66.99, {"BossRatingTimeAddRate": 500}), "Fractional scaled limit truncates to 67 seconds")
	check(not Choices.sacrifice_spawn_eligible(room, 67.0, {"BossRatingTimeAddRate": 500}), "Truncated fractional limit is exclusive")
	check(Choices.sacrifice_spawn_eligible(room, 44.0, {"BossRatingTimeAddRate": 0.9}), "Attribute value truncates before multiplication")
	check(not Choices.sacrifice_spawn_eligible(room, 45.0, {"BossRatingTimeAddRate": 0.9}), "Fractional attribute cannot extend the threshold")
	check(not Choices.sacrifice_spawn_eligible(room, 44.9999999), "Elapsed time compares at native float32 precision")
	check(not Choices.sacrifice_spawn_eligible(room, -1), "Negative elapsed time is rejected")
	check(not Choices.sacrifice_spawn_eligible(room, INF), "Infinite elapsed time is rejected")
	check(not Choices.sacrifice_spawn_eligible(room, NAN), "NaN elapsed time is rejected")
	check(not Choices.sacrifice_spawn_eligible(room, 0, {"BossRatingTimeAddRate": -1000}), "Zero scaled threshold cannot reveal the altar")
	room["FinalBoss"] = true
	check(Choices.sacrifice_spawn_eligible(room, 44), "Final-boss flag does not bypass the source speed gate")
	room.EnemyClass = "Elite"
	room["Flow"] = "Boss"
	check(not Choices.sacrifice_spawn_eligible(room, 1), "Source enemy class takes precedence over flow labels")
	room.erase("EnemyClass")
	check(Choices.sacrifice_spawn_eligible(room, 1), "Canonical boss flow supports room fixtures without an enemy alias")
	room.erase("Flow")
	room["flow"] = "Boss"
	check(Choices.sacrifice_spawn_eligible(room, 1), "Runtime boss flow supports room fixtures without an enemy alias")
	for kind in ["TimeLimit", "DodgeBattle", "ProtectTarget", "Endless", ""]:
		room.FightType = kind
		check(not Choices.sacrifice_spawn_eligible(room, 1), "Only regular boss combat reveals the altar: " + kind)
	room.FightType = "Regular"
	for invalid in [{}, {"BossBattleRankTime": []}, {"BossBattleRankTime": [0]}, {"BossBattleRankTime": [-1]}, {"BossBattleRankTime": ["45"]}, {"BossBattleRankTime": [INF]}, {"BossBattleRankTime": [NAN]}, "invalid"]:
		room.FightData = invalid
		check(not Choices.sacrifice_spawn_eligible(room, 0), "Missing or invalid source first threshold cannot grant an altar")
	if failures.is_empty(): print("purification_altar_rules_test PASS ", checks)
	else:
		for failure in failures: push_error(failure)
		print("purification_altar_rules_test FAIL ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
