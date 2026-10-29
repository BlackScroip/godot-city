extends SceneTree

var checks := 0
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var world := DungeonWorld.new()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.presentation.set_process(false)
	var player := DungeonActor.new()
	player.is_player = true
	player.combat = DungeonCombat.new()
	player.combat.configure()
	player.combat.actor_key = "player"
	world.add_child(player)
	player.set_process(false)
	player.set_physics_process(false)
	world.player = player
	world.actors.append(player)
	player.position = Vector3(5, 0, -2)
	player.facing = Vector3.BACK
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/combat.json"))
	for case in [["50202500", 1], ["50202510", 2], ["50202520", 4], ["50203101", 6]]:
		var row: Dictionary = catalog.summons.filter(func(item): return item.id == case[0])[0]
		var states: Array = []
		for index in int(case[1]):
			var hit := {"definition": row.hit, "summon_id": case[0], "emit_index": index, "sequence": 1}
			var state := world._projectile(player, hit)
			states.append(state)
			var visual: Node3D = world.projectiles.back().visual
			var effect: Dictionary = world.presentation.active.back()
			check(state.is_light_spirit_sword() and effect.authored != null, "%s uses the source sword" % case[0])
			check(not visual.visible and effect.follow_rotation and effect.authored.scale == Vector3.ONE, "%s uses the source-sized sword without the fallback sphere" % case[0])
			check(is_equal_approx(state.position.distance_to(player.position + Vector3.UP), 3.0), "%s starts on its orbit" % case[0])
			check(visual.basis.z.is_equal_approx(state.orbit_facing()) and effect.root.basis.z.is_equal_approx(state.orbit_facing()), "%s starts with its hilt inward" % case[0])
		for index in states.size():
			var expected := TAU * float(index) / float(states.size())
			check(is_equal_approx(absf(states[0].direction.signed_angle_to(states[index].direction, Vector3.UP)), minf(expected, TAU - expected)), "%s distributes swords evenly" % case[0])
		var initial: Vector3 = states[0].position
		player.position += Vector3(1, 0, 2)
		world._tick_projectiles(0.5)
		world.presentation._process(0.0)
		for index in states.size():
			var state: DungeonProjectile = states[index]
			var visual: Node3D = world.projectiles[index].visual
			var effect: Dictionary = world.presentation.active[index]
			var radial: Vector3 = (state.position - player.position - Vector3.UP).normalized()
			check(radial.is_equal_approx(state.orbit_facing()) and visual.basis.z.is_equal_approx(radial), "%s follows owner with the hilt inward" % case[0])
			check(effect.root.global_position.is_equal_approx(state.position) and effect.root.global_basis.z.is_equal_approx(radial), "%s rendered effect follows position and rotation" % case[0])
		var saved := DungeonProjectile.new()
		saved.restore(states[0].snapshot())
		check(saved.orbit_facing().is_equal_approx(states[0].orbit_facing()), "%s restores orbit angle" % case[0])
		world._tick_projectiles(1.5 if case[0] != "50203101" else 5.0 / 6.0)
		check((states[0].position - player.position).is_equal_approx(initial - (player.position - Vector3(1, 0, 2))), "%s completes a full rotation" % case[0])
		for projectile in world.projectiles.duplicate(): world._recycle_projectile(projectile)
		world.projectiles.clear()
		world.presentation.clear()
	player.combat.add_buff("50202510")
	player.combat.drain_events()
	for frame in 1810:
		player.combat.tick(1.0 / 60.0)
		for event in player.combat.drain_events(): world._consume(player, event)
	check(world.projectiles.size() == 2, "Advanced light spirit produces two real sword projectiles after its cooldown")
	var enemy := DungeonActor.new()
	enemy.is_player = false
	enemy.combat = DungeonCombat.new()
	enemy.combat.configure_enemy(11001)
	enemy.combat.actor_key = "enemy"
	enemy.combat.max_health = 100000
	enemy.combat.health = 100000
	world.add_child(enemy)
	enemy.set_process(false)
	enemy.set_physics_process(false)
	world.actors.append(enemy)
	if not world.projectiles.is_empty():
		enemy.position = world.projectiles[0].state.position - Vector3.UP * 0.75
		world._tick_projectiles(0.01)
		check(enemy.combat.health < 100000, "A light sword damages an enemy along its orbit")
	print("LIGHT_SPIRIT_SWORD ", JSON.stringify({"checks": checks, "failures": failures}))
	world.free()
	quit(0 if failures.is_empty() else 1)
