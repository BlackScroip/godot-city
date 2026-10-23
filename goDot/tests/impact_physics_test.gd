extends SceneTree

const Combat = preload("res://scripts/domain/combat.gd")
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
	box.size = Vector3(0.2, 30, 30)
	shape.shape = box
	wall.add_child(shape)
	space.add_child(wall)
	for fps in [30, 60, 120]:
		Engine.physics_ticks_per_second = fps
		await process_frame
		await physics_frame
		for category in ["light", "heavy", "explosion"]:
			var profile: Dictionary = FEEL.impact_profiles[category]
			var actor = DungeonActor.new()
			actor.combat = Combat.new()
			actor.combat.configure_enemy(11001)
			space.add_child(actor)
			actor.desired_velocity = Vector3.LEFT * 5
			wall.position.x = 100
			await physics_frame
			actor.start_knockback(Vector3.RIGHT, float(profile.distance), float(profile.travel))
			while actor.knockback_elapsed >= 0:
				await physics_frame
				actor.combat.tick(1.0 / fps)
				actor._physics_process(1.0 / fps)
			var travelled = actor.position.x
			if absf(travelled - float(profile.distance)) > float(profile.distance) * 0.05:
				failures.append("%s distance at%s Hz:%s" % [category, fps, travelled])
			actor.position = Vector3.ZERO
			actor.velocity = Vector3.ZERO
			actor.locomotion = Vector3.ZERO
			actor.desired_velocity = Vector3.ZERO
			wall.position.x = 0.5
			await physics_frame
			actor.start_knockback(Vector3.RIGHT, float(profile.distance) + 1, float(profile.travel))
			while actor.knockback_elapsed >= 0:
				await physics_frame
				actor.combat.tick(1.0 / fps)
				actor._physics_process(1.0 / fps)
			if actor.position.x > 0.061 or actor.position.x < 0.02:
				failures.append("Wall must stop %s at%s Hz:%s" % [category, fps, actor.position.x])
			rows.append({"fps": fps, "category": category, "expected": profile.distance, "distance": travelled, "wall_stop": actor.position.x})
			actor.free()
		var stopped = DungeonActor.new()
		stopped.combat = Combat.new()
		stopped.combat.configure()
		space.add_child(stopped)
		wall.position.x = 100
		stopped.combat.apply_hit_stop(0.08)
		stopped.start_knockback(Vector3.RIGHT, 0.75, 0.22)
		stopped.combat.tick(1.0 / fps)
		stopped._physics_process(1.0 / fps)
		if absf(stopped.position.x) > 0.0001: failures.append("Knockback waits for contact pose at%s Hz" % fps)
		stopped.start_dodge(Vector3.LEFT)
		if stopped.knockback_elapsed >= 0 or stopped.combat.impact_pause > 0: failures.append("Dodge must clear knockback and freeze")
		stopped.free()
	space.free()
	Engine.physics_ticks_per_second = 60
	var report = {"passed": failures.is_empty(), "failures": failures, "physics": rows}
	FileAccess.open("res://reports/impact-physics.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("IMPACT_PHYSICS ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
