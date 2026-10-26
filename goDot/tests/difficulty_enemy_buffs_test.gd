extends SceneTree

const Combat = preload("res://scripts/domain/combat.gd")
var checks := 0
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var catalog := DungeonCatalog.new()
	check(catalog.load_all(), "Source catalogs load")
	var systems := DungeonSystems.new(catalog, DungeonProfile.new())
	check(systems.enemy_creation_buffs(13001).is_empty(), "Camp never applies run difficulty buffs")
	for level in range(10): systems.set_record("difficulty:win:" + str(level), 1)
	check(systems.begin_run(3107, 1, 100, 0).success, "Difficulty fixture starts")
	check(systems.enemy_creation_buffs(13001).is_empty(), "Difficulty zero has no boss enhancement")
	systems.profile.data.run.difficulty = 1
	check(systems.enemy_creation_buffs(13001) == ["45400001"], "First boss enhancement uses its source tier")
	check(systems.enemy_creation_buffs(11001).is_empty() and systems.enemy_creation_buffs(12001).is_empty(), "Boss enhancement never leaks to ordinary or elite ranks")
	systems.profile.data.run.difficulty = 4
	check(systems.enemy_creation_buffs(11001) == ["101000040"], "Ordinary monster cooldown buff starts at tier four")
	check(systems.enemy_creation_buffs(12001).is_empty(), "Ordinary cooldown buff excludes elite monsters")
	check(systems.enemy_creation_buffs(13001) == ["45400001", "45400002", "45400003", "45400004"], "Boss creation keeps all active source tier buffs")
	systems.profile.data.run.difficulty = 10
	var boss_buffs: Array = systems.enemy_creation_buffs(13002)
	for id in ["45400001", "45400002", "45400003", "45400004", "45400005", "45400006", "45400010", "101000101"]:
		check(boss_buffs.has(id), "Chaos boss receives active source buff " + id)
	check(systems.enemy_creation_buffs(11001) == ["101000040", "101000101"], "Chaos ordinary monster combines normal and chaos passive buffs")
	check(systems.enemy_creation_buffs(12001) == ["101000101"], "Chaos elite receives the all-enemy passive")
	for id in [90001, 90002, 90003]: check(systems.enemy_creation_buffs(id).is_empty(), "Native resource slime exclusion " + str(id))
	check(boss_buffs.all(func(id): return not str(id).begins_with("999102")), "Heat buffs stay outside normal and chaos selection")
	var step := int(systems.profile.data.run.random_step)
	systems.enemy_creation_buffs(13002)
	check(int(systems.profile.data.run.random_step) == step, "Deterministic creation buffs do not consume loot RNG")
	var world := DungeonWorld.new()
	root.add_child(world)
	world.systems = systems
	world.set_process(false)
	world.set_physics_process(false)
	world.presentation.audio_enabled = false
	var combat := Combat.new()
	combat.configure()
	world.create_player(combat, 1)
	world.spawn_wave([{"enemy_id": 13002, "position": Vector3.ZERO}], 10, 3107)
	var actor: DungeonActor = world.actors.back()
	check(boss_buffs.all(func(id): return actor.combat.statuses.has(id)), "Actual world boss receives difficulty passives before combat")
	check(actor.combat.statuses.has("13000214") and actor.combat.statuses.has("45400007"), "Recovered island boss enhancement initializes its native dependency buffs")
	check(not actor.combat.is_mohua(), "Boss passive enhancement does not mark a magic-corrupted monster")
	check(is_equal_approx(actor.combat.health, actor.combat.max_health), "Difficulty buffs spawn with complete effective health")
	actor.combat.health -= 37
	var saved: Dictionary = JSON.parse_string(JSON.stringify(actor.combat.snapshot()))
	step = int(systems.profile.data.run.random_step)
	world.spawn_wave([{"enemy_id": 13002, "position": Vector3.RIGHT * 10, "combat_snapshot": saved}], 10, 9999)
	var restored: DungeonActor = world.actors.back()
	check(int(systems.profile.data.run.random_step) == step, "Saved enemy recreation does not consume run RNG")
	check(JSON.parse_string(JSON.stringify(restored.combat.statuses)) == JSON.parse_string(JSON.stringify(actor.combat.statuses)), "Saved enemy recreation preserves passive layers and timers")
	check(is_equal_approx(restored.combat.health, actor.combat.health), "Saved enemy recreation preserves damaged health")
	check(not restored.combat.diagnostics.any(func(message): return "Unknown buff" in str(message)), "Every active difficulty buff has a recovered runtime definition")
	world.free()
	systems.decorations = null
	var report := {"checks": checks, "passed": failures.is_empty(), "failures": failures}
	FileAccess.open("res://reports/difficulty-enemy-buffs.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("DIFFICULTY_ENEMY_BUFFS ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
