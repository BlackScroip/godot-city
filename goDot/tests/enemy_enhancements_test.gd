extends SceneTree

const Enhancements = preload("res://scripts/domain/enemy_enhancements.gd")
const Combat = preload("res://scripts/domain/combat.gd")
const Rewards = preload("res://scripts/domain/loot_rewards.gd")
var checks := 0
var failures: Array[String] = []
var rolls: Array = []
var limits: Array = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _random(limit: int) -> int:
	limits.append(limit)
	return clampi(int(rolls.pop_front()) if not rolls.is_empty() else 0, 0, limit - 1)

func essence(drops: Array) -> Array:
	return drops.filter(func(entry): return bool(entry.material) and int(entry.id) == 107)

func _run() -> void:
	var catalog = DungeonCatalog.new()
	check(catalog.load_all(), "Source catalogs load")
	var profile = DungeonProfile.new()
	var systems = DungeonSystems.new(catalog, profile)
	for level in range(10): systems.set_record("difficulty:win:" + str(level), 1)
	check(systems.begin_run(1729, 1, 100, 2).success, "Difficulty two fixture starts")
	var selection = Enhancements.new(systems, _random)
	var candidates: Array = [{"Id": 1, "Tier": 1, "Name": "first", "BuffId": "110100020"}, {"Id": 2, "Tier": 4, "Name": "second", "BuffId": "110100210"}]
	var attrs := {"NormalEnemySpStrengthenChance": 300, "MaxNormalEnemySpStrengthenCount": 1, "EliteEnemySpStrengthenChance": 1000, "MaxEliteEnemySpStrengthenCount": 2}
	rolls = [301]
	check(selection.roll(11001, "Normal", attrs, candidates).is_empty(), "Ordinary roll301 fails chance300")
	rolls = [300, 0]
	check(selection.roll(11001, "Normal", attrs, candidates).size() == 1, "Ordinary roll300 includes exact chance boundary")
	check(limits.has(1001) and limits.has(1000001), "Integer and weighted draws include native endpoints")
	rolls = [1000, 1000000, 1000, 0]
	var selected: Array = selection.roll(12001, "Elite", attrs, candidates)
	check(selected.map(func(row): return int(row.id)) == [2, 1], "Weighted upper endpoint and without-replacement draws")
	rolls = [301, 300, 0]
	var twice: Dictionary = attrs.duplicate()
	twice.MaxNormalEnemySpStrengthenCount = 2
	check(selection.roll(11001, "Normal", twice, candidates).size() == 1, "Each max-count attempt has an independent success roll")
	for id in [90001, 90002, 90003]:
		limits.clear()
		check(selection.roll(id, "Normal", attrs, candidates).is_empty() and limits.is_empty(), "Resource slime%d is excluded before random draws" % id)
	limits.clear()
	check(selection.roll(13001, "Boss", attrs, candidates).is_empty() and limits.is_empty(), "Boss is excluded before random draws")
	check(selection.roll(11001, "Normal", {}, candidates).is_empty(), "Absent chance and count do not create mohua")
	var disabled: Dictionary = attrs.duplicate()
	disabled.NormalEnemySpStrengthenChance = 0
	check(selection.roll(11001, "Normal", disabled, candidates).is_empty(), "Zero chance does not get an endpoint success")
	disabled.NormalEnemySpStrengthenChance = INF
	check(selection.roll(11001, "Normal", disabled, candidates).is_empty(), "Native missing-attribute infinity sentinel is excluded")
	for level in [1, 2, 3, 4, 5, 10]:
		profile.data.run.difficulty = level
		var actual := Enhancements.new(systems, func(_limit): return 0)
		var elite: Array = actual.for_enemy(12001)
		check(elite.size() == (0 if level < 2 else 2 if level >= 5 else 1), "Difficulty%d uses native elite count and active pool" % level)
		var ordinary: Array = actual.for_enemy(11001)
		check(ordinary.size() == (0 if level < 3 else 2 if level >= 4 else 1), "Difficulty%d uses native ordinary count" % level)
		check(elite.all(func(row): return int(row.id) not in [110100010, 110100220, 99910211, 99910221, 99910231]), "Disabled and unselected heat entries stay outside the active pool")
	profile.data.run.difficulty = 2
	var combat = Combat.new()
	check(combat.configure_enemy(12001, 91, 2).success, "Elite combat loads")
	var base_hp: float = combat.max_health
	check(combat.apply_enemy_enhancements([{"id": 110100020, "buff_id": "110100020", "name": "ambush"}]), "Successful selection applies the source mohua buff")
	check(combat.is_mohua() and combat.statuses.has("110100020") and combat.statuses.has("26012001") and combat.statuses.has("26012002"), "Actual selected and generic mohua buffs reach combat")
	check(is_equal_approx(combat.max_health, base_hp * 2.0) and is_equal_approx(combat.health, combat.max_health), "Generic mohua buff adds100 percent HP on spawn")
	check(not combat.apply_enemy_enhancements([{"buff_id": "110100210"}]) and is_equal_approx(combat.max_health, base_hp * 2.0), "Repeated initialization cannot duplicate enhancements")
	combat.health -= 37.0
	var saved: Dictionary = JSON.parse_string(JSON.stringify(combat.snapshot()))
	var restored = Combat.new()
	restored.configure_enemy(12001, 555, 2)
	check(restored.restore(saved) and restored.is_mohua(), "Combat JSON snapshot preserves the mohua property")
	check(is_equal_approx(restored.health, combat.health) and is_equal_approx(restored.max_health, combat.max_health), "Reload keeps damaged HP and one copy of the HP multiplier")
	check(restored._random_state == int(saved.random_state) and not restored.apply_enemy_enhancements(selected), "Reload preserves actor RNG and prevents reapplication")
	var rewards = Rewards.new(systems, func(limit): return limit - 1)
	check(essence(rewards.monster("Normal", 1, {}, true))[0].amount == 1, "Marked ordinary enemy drops one essence")
	check(essence(rewards.monster("Elite", 1, {}, true))[0].amount == 4, "Marked elite drops four essence")
	check(essence(rewards.monster("Normal", 1, {})).is_empty() and essence(rewards.monster("Boss", 1, {}, true)).is_empty(), "Unmarked enemies and bosses never enter the essence branch")
	var world := DungeonWorld.new()
	root.add_child(world)
	world.systems = systems
	world.set_process(false)
	world.set_physics_process(false)
	world.presentation.audio_enabled = false
	var player_combat = Combat.new()
	player_combat.configure()
	world.create_player(player_combat, 1, Vector3(30, 0, 30))
	world.spawn_wave([{"enemy_id": 12001, "position": Vector3.ZERO}], 2, 77)
	var actor: DungeonActor = world.actors.back()
	check(actor.combat.is_mohua() and actor.combat.custom_properties._enemy_enhancements.size() == 1, "Real world spawn uses active difficulty attributes and selected source buff")
	check(actor.scale.is_equal_approx(Vector3.ONE * 1.1), "Real mohua actor uses native scale1.1")
	actor.combat.health -= 100.0
	var world_saved: Dictionary = JSON.parse_string(JSON.stringify(actor.combat.snapshot()))
	var run_step := int(profile.data.run.random_step)
	world.spawn_wave([{"enemy_id": 12001, "position": Vector3(10, 0, 0), "combat_snapshot": world_saved}], 2, 555)
	var reloaded: DungeonActor = world.actors.back()
	check(int(profile.data.run.random_step) == run_step, "Recreating a saved enemy does not consume run RNG")
	check(reloaded.combat.is_mohua() and reloaded.scale.is_equal_approx(Vector3.ONE * 1.1), "Saved world actor restores the mohua scale")
	check(JSON.parse_string(JSON.stringify(reloaded.combat.statuses)) == JSON.parse_string(JSON.stringify(actor.combat.statuses)), "World restoration keeps exact saved buff layers and timers")
	check(is_equal_approx(reloaded.combat.health, actor.combat.health), "World restoration keeps damaged HP")
	check(reloaded.combat._random_state == actor.combat._random_state, "World restoration keeps actor RNG")
	var before := int(systems.material(107))
	reloaded.combat.health = 0
	world._die(reloaded)
	var ground: Array = world.ground_loot.entries.filter(func(entry): return entry.material and int(entry.id) == 107)
	check(ground.size() == 1 and int(ground[0].amount) == 4, "Real marked-elite death creates a four-essence ground pickup")
	check(int(systems.material(107)) == before, "Essence stays on the ground until pickup")
	var drops_before: int = world.ground_loot.entries.size()
	world._die(reloaded)
	check(world.ground_loot.entries.size() == drops_before, "Repeated death cannot duplicate essence")
	for index in world.ground_loot.entries.size(): world.ground_loot.pickup(reloaded.position, systems)
	check(int(systems.material(107)) == before + 4, "Ground pickup grants the exact four essence to the profile")
	check(world.ground_loot.entries.filter(func(entry): return entry.material and int(entry.id) == 107).is_empty(), "Granted essence pickup is consumed once")
	world.free()
	systems.decorations = null
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures}
	FileAccess.open("res://reports/enemy-enhancements.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("ENEMY_ENHANCEMENTS_TEST ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
