extends SceneTree

const Reference = preload("res://tests/fixtures/projectile_motion_reference.gd")
const Projectile = preload("res://scripts/domain/projectile.gd")
const BENCH_COUNT := 200
const BENCH_STEPS := 200

var checks := 0
var failures: Array[String] = []
var definitions: Array[Dictionary] = []
var seen: Dictionary = {}
var motion_counts: Dictionary = {}
var source_count := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value and failures.size() < 30: failures.append(message)

func _collect(value: Variant) -> void:
	if value is Array:
		for child in value: _collect(child)
	elif value is Dictionary:
		if value.get("raw") is String:
			var raw = JSON.parse_string(value.raw)
			if raw is Dictionary and raw.get("EntityType", "") == "EET_Physical":
				var key := str(value.raw) + ":" + str(value.get("speed", 12)) + ":" + str(value.get("lifetime", 3))
				if not seen.has(key):
					seen[key] = true
					definitions.append(value)
					var motion := str(raw.get("MotionAnimatorType", "EMAT_Line"))
					motion_counts[motion] = int(motion_counts.get(motion, 0)) + 1
		for child in value.values(): _collect(child)

func _add_synthetic() -> void:
	var entities := [
		{},
		{"ColliderType": "Sphere", "ModelBoxColliderSize": {"x": 1.2, "y": 0.2, "z": 0.7}, "ModelBoxColliderCenterOffset": {"x": 0.2, "y": 0.8, "z": -0.3}, "MaxPassNum": 999, "MaxCollisionCountPerTarget": 8, "CanBounceWall": true},
		{"ColliderType": "Cube", "ModelBoxColliderSize": {"x": 1.7, "y": 0.8, "z": 2.1}, "ModelBoxColliderCenterOffset": {"x": -0.4, "y": 0.2, "z": 0.8}, "EnableGlobalCollisionDelayTime": 0.05, "MaxPassNum": 999, "MaxCollisionCountPerTarget": 12},
		{"ColliderType": "Sphere", "IsCheckRoleUnitCollider": false, "MaxPassNum": -1}
	]
	var motions := [
		["EMAT_Line", {"Speed": 4, "Acc": 2, "MaxSpeed": 5, "Distance": 2, "MaxLifetime": 1.3, "TraceTarget": true, "TraceDelayTime": 0.02, "TraceMaxKeepTime": 0.15, "TraceMaxDis": 3, "TraceMaxAngle": 75, "TraceAngelRotateIndentity": 0.05}],
		["EMAT_Line", {"Speed": "8", "Acc": -6, "MaxSpeed": "10", "Distance": 0, "TraceTarget": true, "TraceMaxAngle": 180, "TraceAngelRotateIndentity": -1}],
		["EMAT_Curve", {"DistanceMin": 2, "DistanceMax": 5, "MoveTime": 0.4, "CurveHeightCoeff": 0.5, "PreferTargetPoint": true, "EndPosHeight": 2}],
		["EMAT_Parabola", {"XDis": 3, "YDis": 2, "HitTime": 0.5, "TargetMode": true}],
		["EMAT_RotateOwner", {"RotateRadius": 2, "RadiusDeltaSpeed": -3, "RotateAngleSpeed": -180, "LastingTime": 800, "IsFollowOwner": false, "FollowOwnerRotatePointOffset": {"x": 0.3, "y": 0.2, "z": 0.7}}],
		["EMAT_RotateOwner", {}],
		["EMAT_FollowOwner", {"LastTime": 750}],
		["EMAT_Fixed", {"LastTime": 250}],
		["EMAT_None", {"LastTime": 120}],
		["EMAT_Unmapped", {}]
	]
	for motion in motions:
		for entity in entities:
			var raw := {"EntityType": "EET_Physical", "MotionAnimatorType": motion[0], "MotionAnimatorProperty": motion[1], "EntityProperty": entity.duplicate(true), "EffectActiveIntervalToEachUnit": 0.07, "EffectActiveTotalCountToEachUnit": 5}
			raw.EntityProperty.IntervalCreateSummonUnitDefList = [{"Duration": 0.02, "DelayTime": 0.01, "SummonUnitDef": {"Id": "fixture", "Value": 7}}, {"Duration": 0, "DelayTime": 0, "SummonUnitDef": {"Id": "disabled"}}]
			definitions.append({"raw": JSON.stringify(raw), "speed": 7, "lifetime": 0.8})

func _equivalent() -> void:
	var deltas := [-0.02, 0.0, 0.001, 0.016, 0.033, 0.1, 0.25, 0.6]
	for index in definitions.size():
		for scenario in 3:
			var before = Reference.new()
			var after = Projectile.new()
			var point := Vector3(0.3, 0.75, -1.2)
			var facing := [Vector3.BACK, Vector3(0.7, 0.0, -0.4), Vector3.ZERO][scenario] as Vector3
			var owner_facing := Vector3.INF if scenario == 0 else Vector3(0.4, 0, 0.9).normalized()
			var event := {"definition": definitions[index], "sequence": 17, "status": {"element": "fixture", "stacks": 3}}
			before.configure(event, point, facing, Vector3(4, 0.2, 5), owner_facing)
			after.configure(event, point, facing, Vector3(4, 0.2, 5), owner_facing)
			check(before.snapshot() == after.snapshot() and before.diagnostics == after.diagnostics, "Configure source %d scenario %d" % [index, scenario])
			for step in 32:
				var owner := Vector3(step * 0.03, 0.75, sin(step * 0.1))
				var owner_direction := Vector3.BACK.rotated(Vector3.UP, step * 0.07)
				var target := Vector3.INF if step % 7 == 0 else Vector3(sin(step * 0.15) * 4, 0.75, cos(step * 0.1) * 7)
				before.advance(deltas[step % deltas.size()], owner, owner_direction, target)
				after.advance(deltas[step % deltas.size()], owner, owner_direction, target)
				check(before.snapshot() == after.snapshot() and before.finished == after.finished, "Exact trajectory/state source %d scenario %d step %d" % [index, scenario, step])
				check(before.drain_interval_summons() == after.drain_interval_summons(), "Interval summons source %d step %d" % [index, step])
				var centers := [before.position, before.previous, before.previous.lerp(before.position, 0.5), before.position + Vector3(0.2, 0.75, 0.1), before.position - Vector3(0.2, 0.75, 0.1), before.position + Vector3(0.4, 0.0, 0.4), before.position + Vector3(0.0, 2.0, 0.0), before.position + Vector3(4, 0, 4)]
				for center in centers:
					check(before.intersects(center) == after.intersects(center), "Swept collision source %d step %d" % [index, step])
				var key := "target_%d" % (step % 3)
				check(before.can_hit(key) == after.can_hit(key), "Per-target collision gate source %d step %d" % [index, step])
				if scenario == 1 and before.can_hit(key):
					before.record_hit(key)
					after.record_hit(key)
				if scenario == 2 and step in [4, 9]:
					before.wall_collision(before.position, Vector3.FORWARD)
					after.wall_collision(after.position, Vector3.FORWARD)
				if step == 12:
					var saved: Dictionary = JSON.parse_string(JSON.stringify(before.snapshot()))
					if scenario == 2:
						saved.erase("interval_summon_times")
						saved.erase("last_hit_times")
					before.restore(saved)
					after.restore(saved)
				check(before.snapshot() == after.snapshot() and before.finished == after.finished, "Hit/wall/restore state source %d scenario %d step %d" % [index, scenario, step])
			before.reset()
			after.reset()
			check(before.snapshot() == after.snapshot() and before.finished == after.finished, "Pool reset source %d" % index)
			before.advance(0.016, Vector3.ZERO, Vector3.RIGHT)
			after.advance(0.016, Vector3.ZERO, Vector3.RIGHT)
			check(before.snapshot() == after.snapshot(), "Reset default integration source %d" % index)
			var next_event := {"definition": definitions[(index + 137) % definitions.size()]}
			before.configure(next_event, point, facing, Vector3.ZERO)
			after.configure(next_event, point, facing, Vector3.ZERO)
			before.advance(0.016, Vector3.ZERO, Vector3.RIGHT)
			after.advance(0.016, Vector3.ZERO, Vector3.RIGHT)
			check(before.snapshot() == after.snapshot(), "Pool reconfigure source %d" % index)

func _pool(script: GDScript) -> Array:
	var pool: Array = []
	for index in BENCH_COUNT:
		var shot = script.new()
		shot.configure({"definition": definitions[int(float(index) * source_count / BENCH_COUNT)]}, Vector3.ZERO, Vector3.BACK, Vector3(3, 0, 8))
		shot.lifetime = INF
		shot.max_distance = INF
		pool.append(shot)
	return pool

func _measure(pool: Array, phase: String) -> float:
	var steps := 20 if phase == "configure" else BENCH_STEPS
	var events: Array = []
	if phase == "configure":
		for shot in pool: events.append(shot.hit)
	var start := Time.get_ticks_usec()
	match phase:
		"configure":
			for step in steps:
				for index in pool.size(): pool[index].configure(events[index], Vector3.ZERO, Vector3.BACK, Vector3(3, 0, 8))
		"advance":
			for step in steps:
				for shot in pool:
					shot.finished = false
					shot.advance(1.0 / 60.0, Vector3.ZERO, Vector3.BACK, Vector3(2, 0, 6))
		"intersects":
			for step in steps:
				for shot in pool: shot.intersects(shot.position + Vector3(0.2, 0.5, 0.2))
		"can_hit":
			for step in steps:
				for shot in pool:
					shot.finished = false
					shot.can_hit("target")
		"interval_summons":
			for step in steps:
				for shot in pool: shot.drain_interval_summons()
	return float(Time.get_ticks_usec() - start) / steps

func _benchmark() -> Dictionary:
	var report: Dictionary = {}
	for phase in ["configure", "advance", "intersects", "can_hit", "interval_summons"]:
		var samples := {"before": [], "after": []}
		for round_index in 7:
			for kind in (["before", "after"] if round_index % 2 == 0 else ["after", "before"]):
				var script: GDScript = Reference if kind == "before" else Projectile
				var value := _measure(_pool(script), phase)
				if round_index > 0: samples[kind].append(value)
		for values in samples.values(): values.sort()
		var before_us: float = (samples.before[2] + samples.before[3]) * 0.5
		var after_us: float = (samples.after[2] + samples.after[3]) * 0.5
		report[phase] = {"before_us_per_200": before_us, "after_us_per_200": after_us, "ratio": after_us / maxf(0.001, before_us), "samples_us": samples}
	return report

func _run() -> void:
	var catalog = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/combat.json"))
	_collect(catalog)
	source_count = definitions.size()
	check(source_count >= 321, "All physical source definitions are available")
	_add_synthetic()
	_equivalent()
	var report := {"checks": checks, "failures": failures, "passed": failures.is_empty(), "unique_source_definitions": source_count, "synthetic_definitions": definitions.size() - source_count, "source_motion_counts": motion_counts, "benchmark": _benchmark(), "scope": "Exact snapshots, trajectories, collision results, intervals, hits, bounce, reset and JSON/legacy restore versus frozen pre-compilation implementation. Median headless desktop CPU cost for 200 projectiles; not Android FPS."}
	FileAccess.open("res://reports/projectile-runtime-tests.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("PROJECTILE_RUNTIME_TEST ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
