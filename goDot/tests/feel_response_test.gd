extends SceneTree

const Combat = preload("res://scripts/domain/combat.gd")
const Intent = preload("res://scripts/player_intent.gd")
var failures: Array[String] = []
var assertions := 0

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for action in ["move_left", "move_right", "move_up", "move_down"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	for id in range(1, 8):
		var combat = Combat.new()
		combat.configure(null, null, id)
		combat.request_attack(0)
		var old_sequence = combat._cast_sequence
		var intent = Intent.new()
		check(intent.request(combat, 2, true).success, "Character %d skill accepts during normal startup" % id)
		check(intent.take_ready(combat, 0) == 2, "Character %d skill consumes immediately, without waiting for normal recovery" % id)
		check(combat.request_attack(2).success, "Character %d executes skill interrupt" % id)
		check(not combat._pending.any(func(event): return int(event.sequence) == old_sequence), "Character %d removes interrupted normal events" % id)
		combat.drain_events()
	var world = DungeonWorld.new()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	var combat = Combat.new()
	combat.configure()
	var player = world.create_player(combat, 1, Vector3.ZERO)
	var enemy = DungeonActor.new()
	enemy.combat = Combat.new()
	enemy.combat.configure_enemy(11001)
	enemy.combat.busy = 100
	world.add_child(enemy)
	world.actors.append(enemy)
	var toward = -world.camera.global_basis.z
	toward.y = 0
	toward = toward.normalized()
	enemy.position = toward * 2
	world.fighting = true
	await physics_frame
	world._physics_process(1.0 / 60)
	check(world._automatic_action and combat._current_slot == 0, "Idle auto attack starts near target")
	Input.action_press("move_down")
	await physics_frame
	world._physics_process(1.0 / 60)
	check(not world._automatic_action and combat.busy == 0, "Retreat cancels auto attack in next physics frame")
	check(player.action_motion.is_empty() and player.velocity.dot(toward) < 0, "Retreat removes forward lunge and moves away immediately")
	for frame in 10:
		await physics_frame
		world._physics_process(1.0 / 60)
	check(not world._automatic_action and combat.busy == 0, "Held retreat cannot restart auto attack")
	Input.action_release("move_down")
	combat.cooldowns[2] = 0
	combat.energy[2] = combat.fighter.skills[2].maxSp
	world.use_skill(2)
	await physics_frame
	world._physics_process(1.0 / 60)
	check(combat._current_slot == 2 and not world._automatic_action, "Manual action wins over ready auto attack")
	world.free()
	var report = {"passed": failures.is_empty(), "assertions": assertions, "failures": failures}
	FileAccess.open("res://reports/feel-response.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("FEEL_RESPONSE ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
