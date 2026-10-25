extends SceneTree

var failures: Array[String] = []
var assertions := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message)

func _run() -> void:
	for name in ["move_left", "move_right", "move_up", "move_down"]:
		if not InputMap.has_action(name): InputMap.add_action(name)
	var world := DungeonWorld.new()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.auto_attack_enabled = false
	world.presentation.set_process(false)
	world.presentation.audio_enabled = false
	world.low_effects = true
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(200, 1, 200)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	world.add_child(floor_body)
	floor_body.position.y = -0.5
	var navigation := NavigationRegion3D.new()
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-99, 0, -99), Vector3(-99, 0, 99), Vector3(99, 0, 99), Vector3(99, 0, -99)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	navigation.navigation_mesh = mesh
	world.add_child(navigation)
	NavigationServer3D.map_force_update(world.get_world_3d().navigation_map)
	var combat := DungeonCombat.new()
	combat.configure()
	combat.max_health = 1000000000.0
	combat.health = combat.max_health
	world.create_player(combat, 1, Vector3.ZERO)
	var spawns: Array = []
	for index in combat.catalog.enemies.size():
		var enemy: Dictionary = combat.catalog.enemies[index]
		var angle = TAU * float(index) / combat.catalog.enemies.size()
		spawns.append({"enemy_id": int(enemy.id), "position": [sin(angle) * 6, 0, cos(angle) * 6]})
	world.spawn_wave(spawns, 0, 731)
	await physics_frame
	await physics_frame
	var observed: Dictionary = {}
	var moved: Dictionary = {}
	var damage := 0.0
	for actor in world.actors:
		if actor.is_player: continue
		observed[actor.actor_id] = {}
		moved[actor.actor_id] = 0.0
	for frame in 2400:
		await physics_frame
		var before = combat.health
		world._physics_process(1.0 / 60.0)
		damage += maxf(0, before - combat.health)
		combat.health = combat.max_health
		for actor in world.actors:
			if actor.is_player: continue
			observed[actor.actor_id][actor.combat.current_action] = true
			moved[actor.actor_id] = maxf(moved[actor.actor_id], actor.position.distance_to(actor.born_position))
		world.presentation._process(1.0 / 60.0)
	var rows: Array = []
	for actor in world.actors:
		if actor.is_player: continue
		check(actor.position.is_finite() and actor.facing.is_finite(), "Monster %d keeps finite physical state" % actor.actor_id)
		check(actor.position.y > -0.2, "Monster %d stays on arena floor: %s" % [actor.actor_id, actor.position])
		check(observed[actor.actor_id].size() > 1, "Monster %d leaves its spawn action in real world" % actor.actor_id)
		var attacks = observed[actor.actor_id].keys().filter(func(name): return "attack" in str(name).to_lower())
		if actor.actor_id < 90000:
			check(not attacks.is_empty(), "Monster %d reaches attack with physical world targeting: %s" % [actor.actor_id, observed[actor.actor_id].keys()])
		rows.append({"enemy": actor.actor_id, "actions": observed[actor.actor_id].keys(), "max_travel": moved[actor.actor_id], "position": DungeonProjectile._array(actor.position)})
	check(not world.player.dead and damage > 0, "Actual monster attacks reach the stationary test player")
	check(world.diagnostics.is_empty(), "World has no unresolved diagnostics: %s" % [world.diagnostics])
	var report = {"passed": failures.is_empty(), "assertions": assertions, "failures": failures, "enemies": rows, "simulated_seconds": 40, "received_damage": damage, "scope": "All 39 real world actors, source AI and action dispatch, physical movement and collision, actual player damage, projectiles and summons in a shared empty navigation arena. Headless reconstruction only; not APK runtime or performance acceptance."}
	FileAccess.open("res://reports/monster-world.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("MONSTER_WORLD ", JSON.stringify({"passed": report.passed, "assertions": assertions, "failures": failures, "received_damage": damage}))
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
