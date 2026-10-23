extends SceneTree

var failures: Array[String] = []
var checks := 0
const Combat = preload("res://scripts/domain/combat.gd")

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _run() -> void:
	for action in ["move_left", "move_right", "move_up", "move_down"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	var world = DungeonWorld.new()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.presentation.set_process(false)
	world.presentation.audio_enabled = false
	var player_combat = Combat.new()
	player_combat.configure()
	var player = world.create_player(player_combat, 1, Vector3(4, 0, 0))
	var enemy = DungeonActor.new()
	enemy.actor_id = 11005
	enemy.combat = Combat.new()
	enemy.combat.configure_enemy(11005)
	world.add_child(enemy)
	world.actors.append(enemy)
	enemy.face_direction(Vector3.FORWARD)
	enemy.combat._start(enemy.combat._action(str(enemy.combat.enemy.group), "attack"), 0)
	for event in enemy.combat.drain_events(): world._consume(enemy, event)
	check(world.presentation.telegraphs.size() == 1 and not world.presentation.telegraphs[0].node.visible, "Delayed warning remains hidden before its event")
	check(not enemy.has_telegraph_aim(), "Direction is still free before the red frame appears")
	enemy.face_direction(Vector3.RIGHT)
	check(enemy.facing == Vector3.RIGHT, "Monster may aim during preparation")
	enemy.combat.tick(0.21)
	for event in enemy.combat.drain_events(): world._consume(enemy, event)
	world.presentation._process(0.016)
	check(enemy.has_telegraph_aim(), "Showing the red frame commits the direction")
	for direction in [Vector3.FORWARD, Vector3.LEFT, Vector3.BACK]:
		enemy.aim_enemy(direction, 1.0)
		enemy.face_direction(direction)
		check(enemy.facing == Vector3.RIGHT, "Strafing cannot rotate a committed normal attack")
	# Exercise the world AI, not only the actor setter.
	player.position = Vector3(0, 0, -5)
	world.auto_attack_enabled = false
	world._physics_process(0.016)
	check(enemy.facing == Vector3.RIGHT, "World AI respects the lock when its target moves")
	check(enemy.desired_velocity == Vector3.ZERO, "Windup does not chase sideways; authored charge motion owns travel")
	var hit = {"definition": {"width": 2.0, "length": 4.0, "offset": 2.0}, "damage": 10.0, "sequence": enemy.combat._cast_sequence, "emission": 991, "source": enemy.combat}
	player.position = enemy.position + Vector3.FORWARD * 2
	var health: float = player.combat.health
	world._hit_area(enemy, hit)
	check(player.combat.health == health, "A player outside the locked red frame avoids the hit")
	player.position = enemy.position + Vector3.RIGHT * 2
	world._hit_area(enemy, hit)
	check(player.combat.health < health, "Damage still lands inside the committed attack direction")
	world.presentation.cancel_actor(enemy)
	enemy.face_direction(Vector3.LEFT)
	check(not enemy.has_telegraph_aim() and enemy.facing == Vector3.LEFT, "Cancellation releases aiming immediately")
	# Every monster, including bosses, locks unless the specific action is allowlisted.
	for definition in enemy.combat.catalog.enemies:
		enemy.actor_id = int(definition.id)
		enemy.combat.configure_enemy(enemy.actor_id)
		enemy.clear_telegraph_aim()
		enemy.face_direction(Vector3.FORWARD)
		enemy.combat.current_action = "ordinary_attack"
		enemy.combat.busy = 2.0
		enemy.lock_telegraph_aim(enemy.combat._cast_sequence)
		enemy.aim_enemy(Vector3.RIGHT, 1.0)
		check(enemy.facing == Vector3.FORWARD, "Default attack locks for enemy %d" % enemy.actor_id)
	for id in world.FEEL.telegraph_tracking_actions:
		for action in world.FEEL.telegraph_tracking_actions[id]:
			for fps in [30, 60, 120]:
				enemy.actor_id = int(id)
				enemy.combat.configure_enemy(enemy.actor_id)
				enemy.clear_telegraph_aim()
				enemy.face_direction(Vector3.FORWARD)
				enemy.combat.current_action = action
				enemy.combat.busy = 2.0
				check(not enemy.combat._action(str(enemy.combat.enemy.group), action).is_empty(), "Boss tracking exception names a real action")
				enemy.lock_telegraph_aim(enemy.combat._cast_sequence)
				for step in fps: enemy.aim_enemy(Vector3.RIGHT, 1.0 / fps)
				var angle = absf(rad_to_deg(Vector3.FORWARD.signed_angle_to(enemy.facing, Vector3.UP)))
				check(absf(angle - float(world.FEEL.telegraph_tracking_actions[id][action])) < 0.01, "Only designated boss attack tracks at bounded rate, %d Hz" % fps)
				enemy.combat.busy = 0
				enemy.face_direction(Vector3.BACK)
				check(enemy.facing.is_equal_approx(Vector3.BACK), "Finishing an attack releases its direction")
	var report = {"passed": failures.is_empty(), "checks": checks, "failures": failures}
	FileAccess.open("res://reports/telegraph-aim.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("TELEGRAPH_AIM ", JSON.stringify(report))
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
