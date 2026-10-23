extends SceneTree

var assertions := 0
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message)

func projectile(motion: Dictionary = {}, entity: Dictionary = {}, type := "EMAT_Line") -> DungeonProjectile:
	var value = DungeonProjectile.new()
	value.configure({"definition": {"speed": 10, "raw": JSON.stringify({"EntityType": "EET_Physical", "MotionAnimatorType": type, "MotionAnimatorProperty": motion, "EntityProperty": entity})}}, Vector3.ZERO, Vector3(0, 0, 1), Vector3(0, 0, 6))
	return value

func _initialize() -> void:
	for motion_type in ["EMAT_FollowOwner", "EMAT_Fixed"]:
		var short_lived = projectile({"LastTime": 200}, {}, motion_type)
		check(is_equal_approx(short_lived.lifetime, 0.2), "Original LastTime milliseconds: " + motion_type)
		short_lived.advance(0.21, Vector3.ZERO, Vector3.FORWARD)
		check(short_lived.finished, "Melee collider cannot linger for hundreds of seconds")
	var repeated = DungeonProjectile.new()
	repeated.configure({"definition": {"raw": JSON.stringify({"MotionAnimatorType": "EMAT_FollowOwner", "MotionAnimatorProperty": {"LastTime": 200}, "EntityProperty": {"MaxCollisionCountPerTarget": 9999, "MaxPassNum": 9999}, "EffectActiveIntervalToEachUnit": 0.4})}}, Vector3.ZERO, Vector3.FORWARD, Vector3.ZERO)
	check(repeated.can_hit("target"), "Melee first contact is eligible")
	repeated.record_hit("target")
	repeated.advance(0.016, Vector3.ZERO, Vector3.FORWARD)
	check(not repeated.can_hit("target"), "Per-target interval blocks next-frame repeated damage")
	var restored_melee = DungeonProjectile.new()
	restored_melee.restore(JSON.parse_string(JSON.stringify(repeated.snapshot())))
	check(not restored_melee.can_hit("target"), "Saved collision retains per-target interval")
	var line = projectile({"Speed": 20, "Distance": 10, "MaxLifetime": 3}, {"MaxPassNum": 1})
	line.advance(0.25, Vector3.ZERO, Vector3(0, 0, 1))
	check(line.position.is_equal_approx(Vector3(0, 0, 5)), "Original speed advances physical shot")
	check(line.intersects(Vector3(0, 0, 3)), "Swept segment detects crossed actor")
	line.record_hit("a")
	check(not line.can_hit("a") and line.can_hit("b") and not line.finished, "Per-target deduplication and one piercing pass")
	line.record_hit("b")
	check(line.finished, "Pass budget disposes after second target")
	var bounced = projectile({}, {"CanBounceWall": true})
	bounced.wall_collision(Vector3(0, 0, 2), Vector3(0, 0, -1))
	check(bounced.direction.z < 0 and not bounced.finished, "Wall reflection remains active")
	var stopped = projectile()
	stopped.wall_collision(Vector3(0, 0, 2), Vector3(0, 0, -1))
	check(stopped.finished, "Nonreflecting shot stops at wall")
	var traced = projectile({"TraceTarget": true, "TraceMaxDis": 30, "TraceMaxAngle": 180, "TraceAngelRotateIndentity": 0.05, "TraceDelayTime": 0.1})
	traced.advance(0.05, Vector3.ZERO, Vector3(0, 0, 1), Vector3(5, 0, 10))
	check(is_zero_approx(traced.direction.x), "Tracking waits for configured delay")
	traced.advance(0.1, Vector3.ZERO, Vector3(0, 0, 1), Vector3(5, 0, 10))
	check(traced.direction.x > 0, "Tracking turns toward target")
	var curved = projectile({"MoveTime": 1, "DistanceMax": 6, "CurveHeightCoeff": 0.5}, {}, "EMAT_Curve")
	curved.advance(0.5, Vector3.ZERO, Vector3(0, 0, 1))
	check(curved.position.y > 2 and curved.position.z > 2, "Curved shot has visible arc")
	curved.advance(0.5, Vector3.ZERO, Vector3(0, 0, 1))
	check(curved.finished and curved.position.distance_to(curved.destination) < 0.01, "Arc lands at endpoint")
	var copy = DungeonProjectile.new()
	copy.restore(JSON.parse_string(JSON.stringify(traced.snapshot())))
	traced.advance(0.1, Vector3.ZERO, Vector3(0, 0, 1), Vector3(5, 0, 10))
	copy.advance(0.1, Vector3.ZERO, Vector3(0, 0, 1), Vector3(5, 0, 10))
	check(copy.position.distance_to(traced.position) < 0.0001, "JSON restore preserves projectile integration")
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/combat.json"))
	var physical_count := 0
	for action in data.actions:
		for hit in action.hits:
			var raw = JSON.parse_string(hit.raw)
			if raw.get("EntityType", "") != "EET_Physical": continue
			var value = DungeonProjectile.new()
			value.configure({"definition": hit}, Vector3.ZERO, Vector3(0, 0, 1), Vector3(0, 0, 6))
			value.advance(0.016, Vector3.ZERO, Vector3(0, 0, 1), Vector3(0, 0, 6))
			check(value.position.is_finite() and value.diagnostics.is_empty(), "Physical definition finite: " + str(action.key))
			physical_count += 1
	check(physical_count == 321, "All 321 original physical attack definitions exercised")
	var report = {"assertions": assertions, "failures": failures, "passed": failures.is_empty(), "physical_definitions": physical_count, "limits": ["Trace sensitivity, curve interpolation and push units are documented reconstructions", "Does not validate original effect prefab appearance"]}
	FileAccess.open("res://reports/projectile-tests.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("PROJECTILE_TESTS ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
