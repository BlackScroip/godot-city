extends SceneTree

const Combat = preload("res://scripts/domain/combat.gd")
const INPUTS = ["move_left", "move_right", "move_up", "move_down"]
var checks := 0
var failures: Array[String] = []
var cases: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _run() -> void:
	create_timer(120).timeout.connect(func(): quit(2))
	for action in INPUTS:
		if not InputMap.has_action(action): InputMap.add_action(action)
	for character_id in range(1, 9):
		await _character_case(character_id)
	for action in INPUTS: Input.action_release(action)
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "characters": cases}
	FileAccess.open("res://reports/player-movement-20261028.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("PLAYER_MOVEMENT ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func _step(world: DungeonWorld, frames: int) -> void:
	for frame in frames:
		await physics_frame
		world._physics_process(1.0 / 60.0)

func _character_case(character_id: int) -> void:
	var world := DungeonWorld.new()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.presentation.audio_enabled = false
	world.auto_attack_enabled = false
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -0.5
	world.add_child(floor_body)
	var combat = Combat.new()
	combat.configure(null, null, character_id)
	var actor := world.create_player(combat, character_id, Vector3.ZERO)
	actor.set_process(false)
	world.camera.position = Vector3(0, 12, 8)
	world.camera.look_at(Vector3.ZERO)
	await _step(world, 2)
	var start := actor.position
	Input.action_press("move_right")
	await _step(world, 30)
	var walked := actor.position.x - start.x
	check(walked > combat.move_speed * 0.4 and walked < combat.move_speed * 0.51, "%d: sustained input reaches the configured walking speed" % character_id)
	check(actor.facing.dot(Vector3.RIGHT) > 0.99, "%d: walking faces the input direction" % character_id)
	Input.action_release("move_right")
	Input.action_press("move_left")
	await _step(world, 15)
	check(actor.velocity.x < -combat.move_speed * 0.99 and actor.facing.dot(Vector3.LEFT) > 0.99, "%d: reverse input turns and reverses velocity" % character_id)
	Input.action_release("move_left")
	await _step(world, 10)
	var stopped := actor.position
	await _step(world, 5)
	check(actor.position.distance_to(stopped) < 0.001 and actor.locomotion.is_zero_approx(), "%d: released input settles without drift" % character_id)
	Input.action_press("move_up")
	await _step(world, 20)
	check(actor.position.z < stopped.z - combat.move_speed * 0.25, "%d: screen-up input follows the camera's ground-plane forward" % character_id)
	Input.action_release("move_up")
	await _step(world, 10)
	check(world._execute_player(0), "%d: normal attack starts through the world input path" % character_id)
	Input.action_press("move_right")
	await _step(world, 90)
	check(actor.action_timeline_duration <= 0.0 or actor.action_cursor >= actor.action_timeline_duration - 0.000001, "%d: attack timeline releases movement" % character_id)
	check(actor.velocity.x > combat.move_speed * 0.99 and actor.facing.dot(Vector3.RIGHT) > 0.99, "%d: held input resumes walking after an attack" % character_id)
	var before_pause := actor.position
	world.paused = true
	await _step(world, 3)
	check(actor.position.is_equal_approx(before_pause), "%d: pause stops physical movement" % character_id)
	world.paused = false
	Input.action_press("move_right")
	await _step(world, 10)
	check(actor.position.x > before_pause.x + combat.move_speed * 0.1, "%d: input resumes after pause" % character_id)
	Input.action_release("move_right")
	cases.append({"character": character_id, "speed": combat.move_speed, "walk_distance_0_5s": walked, "final_action": combat.current_action, "timeline_remaining": maxf(0.0, actor.action_timeline_duration - actor.action_cursor)})
	world.free()
	await process_frame
