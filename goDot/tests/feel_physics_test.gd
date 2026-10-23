extends SceneTree

const FEEL = preload("res://assets/feel_settings.tres")
var failures: Array[String] = []
var rows: Array = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var space = Node3D.new()
	root.add_child(space)
	var wall = StaticBody3D.new()
	var shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(0.2, 20, 20)
	shape.shape = box
	wall.add_child(shape)
	space.add_child(wall)
	wall.position.x = 100
	for fps in [30, 60, 120]:
		Engine.physics_ticks_per_second = fps
		var actor = DungeonActor.new()
		actor.is_player = true
		space.add_child(actor)
		actor.desired_velocity = Vector3.RIGHT * 5
		for frame in fps:
			await physics_frame
			actor._physics_process(1.0 / fps)
		var start = actor.position.x
		for frame in fps:
			await physics_frame
			actor._physics_process(1.0 / fps)
		var moved = actor.position.x - start
		if absf(moved - 5) > 0.02: failures.append("Movement distance at %d Hz: %f" % [fps, moved])
		actor.desired_velocity = Vector3.LEFT * 5
		for frame in ceili(fps * 0.04):
			await physics_frame
			actor._physics_process(1.0 / fps)
		if actor.velocity.x >= 0: failures.append("Reverse input must reverse velocity within 40 ms at %d Hz" % fps)
		actor.combat = preload("res://scripts/domain/combat.gd").new()
		actor.combat.configure()
		actor.action_motion.append({"velocity": Vector3.RIGHT * 2, "remaining": 0.2, "input_motion": true, "scale_input": true, "speed": 2.0})
		actor.desired_velocity = Vector3.LEFT * actor.combat.move_speed
		await physics_frame
		actor._physics_process(1.0 / fps)
		if actor.velocity.x >= 0: failures.append("Action motion must use live input at %d Hz" % fps)
		actor.desired_velocity = Vector3.ZERO
		await physics_frame
		actor._physics_process(1.0 / fps)
		if absf(actor.velocity.x) > 0.001: failures.append("Released input must stop input-driven action motion at %d Hz" % fps)
		actor.desired_velocity = Vector3.RIGHT * 5
		actor.position = Vector3.ZERO
		actor.velocity = Vector3.ZERO
		actor.start_dodge(Vector3.RIGHT)
		while actor.dodge_elapsed >= 0:
			await physics_frame
			actor._physics_process(1.0 / fps)
		var dodged = actor.position.x
		if absf(dodged - FEEL.dodge_distance) > 0.02: failures.append("Dodge distance at %d Hz: %f" % [fps, dodged])
		actor.position = Vector3.ZERO
		actor.velocity = Vector3.ZERO
		wall.position.x = 1.5
		await physics_frame
		actor.start_dodge(Vector3.RIGHT)
		while actor.dodge_elapsed >= 0:
			await physics_frame
			actor._physics_process(1.0 / fps)
		if actor.position.x > 1.06 or actor.position.x < 0.8: failures.append("Wall must block dodge at %d Hz: %f" % [fps, actor.position.x])
		rows.append({"fps": fps, "move_distance": moved, "dodge_distance": dodged, "wall_stop": actor.position.x})
		wall.position.x = 100
		actor.free()
	space.free()
	Engine.physics_ticks_per_second = 60
	var report = {"passed": failures.is_empty(), "failures": failures, "physics": rows}
	FileAccess.open("res://reports/feel-physics.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("FEEL_PHYSICS ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
