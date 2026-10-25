extends SceneTree

const Combat = preload("res://scripts/domain/combat.gd")
const Stats = preload("res://scripts/domain/enemy_stats.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	var combat = Combat.new()
	combat.configure_enemy(11001)
	check(combat.max_health == 600, "Difficulty zero forest wolf uses source 2x HP")
	combat.configure_enemy(12001, 1, 0, null, 2)
	check(combat.max_health == 9000, "Elite region two uses source 5x HP")
	combat.configure_enemy(13001, 1, 0, null, 3)
	check(combat.max_health == 72000, "Boss region three uses source 18x HP")
	combat.configure_enemy(11001, 1, 1)
	check(combat.max_health == 1050, "Difficulty one wolf uses source 3.5x HP")
	check(Stats.hp_multiplier("Normal", 10) == 46.68, "Missing difficulty ten falls back to highest lower difficulty")
	check(Stats.hp_multiplier("Elite", 10, 3, 2) == 508.3, "Chaos two uses difficulty key 102")
	check(Stats.hp_multiplier("Boss", 0, 0) == 2.0 and Stats.hp_multiplier("Boss", 0, 99) == 162.0, "Stage clamped to source range one through five")
	var base_rows: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/EnemyData.json"))
	for enemy in combat.catalog.enemies:
		for row in base_rows:
			if int(row.id) == int(enemy.id):
				check(float(row.hp) == float(enemy.hp), "Base HP matches source EnemyData: %s" % enemy.id)
		for difficulty in range(11):
			for stage in range(1, 6):
				check(combat.configure_enemy(int(enemy.id), 1, difficulty, null, stage).success, "Every enemy configures across difficulty and stage")
				check(combat.health == combat.max_health and combat.health >= float(enemy.hp), "Every enemy starts at full scaled HP")
				var before = combat.health
				combat.health *= 0.37
				var snapshot = combat.snapshot()
				check(combat.restore(snapshot) and combat.max_health == before and is_equal_approx(combat.health, before * 0.37), "Scaled HP survives snapshot restore")
				check(int(combat.custom_properties.get("enemy_stage", -1)) == stage, "Snapshot retains monster stage for generated offspring")
	combat.configure_enemy(12001, 1, 10, null, 4, 2)
	var chaos_snapshot = combat.snapshot()
	combat.configure_enemy(12001)
	check(combat.restore(chaos_snapshot) and combat.difficulty == 10 and int(combat.custom_properties.get("enemy_stage", -1)) == 4 and int(combat.custom_properties.get("enemy_chaos", -1)) == 2, "Restoring into a fresh combat retains difficulty, stage and chaos")
	print("ENEMY_HEALTH ", JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)
