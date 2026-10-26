# Frozen pre-compilation behavior used only by the differential runtime test.
extends RefCounted

var position := Vector3.ZERO
var previous := Vector3.ZERO
var direction := Vector3.FORWARD
var origin := Vector3.ZERO
var destination := Vector3.ZERO
var speed := 0.0
var age := 0.0
var distance := 0.0
var lifetime := 1.0
var max_distance := INF
var motion_type := "EMAT_Line"
var entity: Dictionary = {}
var motion: Dictionary = {}
var hit: Dictionary = {}
var hits: Dictionary = {}
var last_hit_times: Dictionary = {}
var interval_summon_times: Dictionary = {}
var hit_interval := 0.0
var hit_limit := 999999
var passed := 0
var finished := false
var source_key := ""
var target_key := ""
var source_player := true
var radius := 0.13
var owner_offset := Vector3.ZERO
var diagnostics: Array[String] = []

func reset() -> void:
	position = Vector3.ZERO
	previous = Vector3.ZERO
	direction = Vector3.FORWARD
	origin = Vector3.ZERO
	destination = Vector3.ZERO
	owner_offset = Vector3.ZERO
	speed = 0.0
	age = 0.0
	distance = 0.0
	lifetime = 1.0
	max_distance = INF
	motion_type = "EMAT_Line"
	entity = {}
	motion = {}
	hit = {}
	hits = {}
	last_hit_times = {}
	interval_summon_times = {}
	hit_interval = 0.0
	hit_limit = 999999
	passed = 0
	finished = false
	source_key = ""
	target_key = ""
	source_player = true
	radius = 0.13
	diagnostics.clear()

static func emission_facing(raw: Dictionary, index: int, facing: Vector3, toward: Vector3) -> Vector3:
	if str(raw.get("EmitType", "")) != "EET_ARC": return facing
	var emit: Dictionary = raw.get("EmitProperty", {})
	var mode = str(emit.get("EmitType", "EAE_Sector_RelativeSelfDir"))
	var count = maxi(1, int(emit.get("Num", 1)))
	var circle = mode.begins_with("EAE_Circle")
	var step = int(360.0 / count) if circle else int(emit.get("IntervalDegree", 0))
	var start = 0 if circle else int(float((1 - count) * step) / 2.0)
	var direction = facing
	if mode == "EAE_Sector_DirToTarget":
		toward.y = 0
		if toward.length_squared() > 0.00001: direction = toward.normalized()
	var offset = float(emit.get("DegreeOffet", 0)) if mode == "EAE_Circle_DirToTarget" else 0.0
	return direction.rotated(Vector3.UP, deg_to_rad(start + index * step + offset))

func configure(event: Dictionary, point: Vector3, facing: Vector3, target: Vector3, owner_facing: Vector3 = Vector3.INF) -> void:
	reset()
	hit = event.duplicate(true)
	hit.erase("source")
	var definition: Dictionary = hit.get("definition", {})
	var raw = JSON.parse_string(str(definition.get("raw", "{}")))
	if not raw is Dictionary: raw = {}
	entity = raw.get("EntityProperty", {})
	hit_interval = maxf(0.0, float(raw.get("EffectActiveIntervalToEachUnit", 0)))
	hit_limit = maxi(1, int(raw.get("EffectActiveTotalCountToEachUnit", 999999)))
	motion = raw.get("MotionAnimatorProperty", {})
	motion_type = str(raw.get("MotionAnimatorType", "EMAT_Line"))
	direction = facing.normalized() if facing.length_squared() > 0.001 else Vector3.FORWARD
	var emit: Dictionary = raw.get("EmitProperty", {})
	if raw.get("EmitType", "") == "EET_ARC":
		var basis = owner_facing if owner_facing.is_finite() else facing
		owner_offset = orient(DungeonWorld.vector(emit.get("PosOffset", {})), basis) + basis * float(emit.get("RadiusOffset", 0))
	else:
		owner_offset = orient(DungeonWorld.vector(emit.get("EmitOffset", {})), direction)
		direction = direction.rotated(Vector3.UP, deg_to_rad(float(emit.get("EmitRotation", {}).get("y", 0))))
		owner_offset += orient(DungeonWorld.vector(emit.get("AfterRotateEmitOffset", {})), direction)
	position = point + owner_offset
	origin = position
	previous = position
	speed = float(motion.get("Speed", definition.get("speed", 12)))
	lifetime = maxf(0.01, float(motion.get("MaxLifetime", motion.get("LifeTime", motion.get("LastTime", definition.get("lifetime", 3))))))
	# Original FollowOwner/Fixed properties explicitly label LastTime in ms.
	if motion_type in ["EMAT_FollowOwner", "EMAT_Fixed", "EMAT_None"] and motion.has("LastTime"):
		lifetime = maxf(0.01, float(motion.LastTime) / 1000.0)
	max_distance = float(motion.get("Distance", INF))
	if max_distance <= 0: max_distance = INF
	var size = DungeonWorld.vector(entity.get("ModelBoxColliderSize", {}))
	radius = maxf(0.13, maxf(size.x, size.z) * 0.5)
	if motion_type in ["EMAT_Curve", "EMAT_Parabola"]:
		var range_value = float(motion.get("DistanceMax", motion.get("XDis", 6)))
		destination = position + direction * range_value
		if motion.get("PreferTargetPoint", motion.get("TargetMode", false)):
			destination = target
			var flat = destination - position
			flat.y = 0
			var length_value = clampf(flat.length(), float(motion.get("DistanceMin", 0)), maxf(0.01, range_value))
			destination = position + flat.normalized() * length_value
		destination.y = float(motion.get("EndPosHeight", 0)) + 0.2
		lifetime = maxf(0.01, float(motion.get("MoveTime", motion.get("HitTime", lifetime))))
	if motion_type == "EMAT_RotateOwner":
		lifetime = maxf(0.01, float(motion.get("LastingTime", 1000)) / 1000.0)
	if motion_type not in ["EMAT_Line", "EMAT_Fixed", "EMAT_None", "EMAT_FollowOwner", "EMAT_Curve", "EMAT_Parabola", "EMAT_RotateOwner"]:
		diagnostics.append("Unmapped projectile motion: " + motion_type)

func advance(delta: float, owner_position: Vector3, owner_facing: Vector3, target: Vector3 = Vector3.INF) -> void:
	if finished: return
	delta = minf(maxf(0, delta), maxf(0, lifetime - age))
	previous = position
	age += delta
	match motion_type:
		"EMAT_Line":
			if bool(motion.get("TraceTarget", false)) and target.is_finite() and age >= float(motion.get("TraceDelayTime", 0)) and age <= float(motion.get("TraceDelayTime", 0)) + float(motion.get("TraceMaxKeepTime", 99)):
				var difference = target - position
				difference.y = 0
				var desired = difference.normalized()
				if difference.length() <= float(motion.get("TraceMaxDis", INF)) and absf(direction.signed_angle_to(desired, Vector3.UP)) <= deg_to_rad(float(motion.get("TraceMaxAngle", 180))):
					# Original sensitivity units are unverified; this uses radians per 50 Hz step.
					var turn = maxf(0, float(motion.get("TraceAngelRotateIndentity", 0.02))) * 50 * delta
					direction = direction.rotated(Vector3.UP, clampf(direction.signed_angle_to(desired, Vector3.UP), -turn, turn)).normalized()
			speed = clampf(speed + float(motion.get("Acc", 0)) * delta, 0, maxf(0, float(motion.get("MaxSpeed", INF))))
			position += direction * speed * delta
		"EMAT_FollowOwner":
			position = owner_position + owner_offset
		"EMAT_RotateOwner":
			var radius_value = maxf(0, float(motion.get("RotateRadius", 1)) + age * float(motion.get("RadiusDeltaSpeed", 0)))
			var center = owner_position if motion.get("IsFollowOwner", true) else origin
			position = center + orient(DungeonWorld.vector(motion.get("FollowOwnerRotatePointOffset", {})), owner_facing) + direction.rotated(Vector3.UP, deg_to_rad(float(motion.get("RotateAngleSpeed", 120))) * age) * radius_value
		"EMAT_Curve", "EMAT_Parabola":
			var progress = minf(1, age / lifetime)
			var height = float(motion.get("YDis", origin.distance_to(destination) * float(motion.get("CurveHeightCoeff", 0.3))))
			position = origin.lerp(destination, progress) + Vector3.UP * 4 * height * progress * (1 - progress)
	var travelled := previous.distance_to(position)
	if travelled > 0 and distance + travelled > max_distance:
		travelled = maxf(0, max_distance - distance)
		position = previous.move_toward(position, travelled)
	distance += travelled
	if age >= lifetime or distance >= max_distance: finished = true

func drain_interval_summons() -> Array:
	var result: Array = []
	var definitions: Array = entity.get("IntervalCreateSummonUnitDefList", [])
	for index in definitions.size():
		var rule: Dictionary = definitions[index]
		var interval = float(rule.get("Duration", 0))
		if interval <= 0: continue
		var next = float(interval_summon_times.get(str(index), maxf(0, float(rule.get("DelayTime", 0)))))
		while next <= age + 0.000001 and next < lifetime - 0.000001 and result.size() < 100:
			result.append(rule.get("SummonUnitDef", {}).duplicate(true))
			next += interval
		interval_summon_times[str(index)] = next
	return result

func can_hit(key: String) -> bool:
	return not finished and bool(entity.get("IsCheckRoleUnitCollider", true)) and age >= float(entity.get("EnableGlobalCollisionDelayTime", 0)) and int(hits.get(key, 0)) < mini(hit_limit, maxi(1, int(entity.get("MaxCollisionCountPerTarget", 1)))) and age + 0.000001 >= float(last_hit_times.get(key, -INF)) + hit_interval

func record_hit(key: String) -> void:
	hits[key] = int(hits.get(key, 0)) + 1
	last_hit_times[key] = age
	passed += 1
	if passed > int(entity.get("MaxPassNum", 0)): finished = true

func intersects(center: Vector3) -> bool:
	var offset = orient(DungeonWorld.vector(entity.get("ModelBoxColliderCenterOffset", {})), direction)
	var from = previous + offset
	var to = position + offset
	var closest = Geometry3D.get_closest_point_to_segment(center, from, to)
	var size = DungeonWorld.vector(entity.get("ModelBoxColliderSize", {}))
	if str(entity.get("ColliderType", "Cube")) == "Sphere" or size.length_squared() < 0.001:
		# Use the same standing hurt volume as box attacks, including upper-body
		# contacts. A point at waist height made authored high shots miss entirely.
		var contacts = Geometry3D.get_closest_points_between_segments(from, to, center - Vector3.UP * 0.75, center + Vector3.UP * 0.75)
		return contacts[0].distance_squared_to(contacts[1]) <= (radius + 0.35) * (radius + 0.35)
	var difference = center - closest
	return absf(difference.y) <= size.y * 0.5 + 0.75 and absf(difference.dot(direction)) <= size.z * 0.5 + 0.35 and absf(difference.dot(Vector3(direction.z, 0, -direction.x))) <= size.x * 0.5 + 0.35

func wall_collision(point: Vector3, normal: Vector3) -> void:
	position = point + normal * 0.02
	if entity.get("CanBounceWall", false): direction = direction.bounce(normal).normalized()
	else: finished = true

static func orient(offset: Vector3, forward: Vector3) -> Vector3:
	return Vector3(forward.z, 0, -forward.x) * offset.x + Vector3.UP * offset.y + forward * offset.z

func snapshot() -> Dictionary:
	return {"position": _array(position), "previous": _array(previous), "direction": _array(direction), "origin": _array(origin), "destination": _array(destination), "owner_offset": _array(owner_offset), "speed": speed, "age": age, "distance": distance, "lifetime": lifetime, "max_distance": max_distance if is_finite(max_distance) else -1, "motion_type": motion_type, "entity": entity.duplicate(true), "motion": motion.duplicate(true), "hit": hit.duplicate(true), "hits": hits.duplicate(), "last_hit_times": last_hit_times.duplicate(), "interval_summon_times": interval_summon_times.duplicate(), "passed": passed, "source_key": source_key, "target_key": target_key, "source_player": source_player, "radius": radius}

func restore(data: Dictionary) -> void:
	reset()
	for field in ["position", "previous", "direction", "origin", "destination", "owner_offset"]: set(field, DungeonWorld.vector(data.get(field, [])))
	for field in ["speed", "age", "distance", "lifetime", "radius"]: set(field, float(data.get(field, get(field))))
	max_distance = float(data.get("max_distance", -1))
	if max_distance < 0: max_distance = INF
	for field in ["motion_type", "source_key", "target_key"]: set(field, str(data.get(field, get(field))))
	for field in ["entity", "motion", "hit", "hits"]: set(field, data.get(field, {}).duplicate(true))
	var raw = DungeonWorld._raw_definition(hit.get("definition", {}))
	hit_interval = maxf(0, float(raw.get("EffectActiveIntervalToEachUnit", 0)))
	hit_limit = maxi(1, int(raw.get("EffectActiveTotalCountToEachUnit", 999999)))
	last_hit_times = data.get("last_hit_times", {}).duplicate()
	interval_summon_times = data.get("interval_summon_times", {}).duplicate()
	if not data.has("interval_summon_times"):
		for index in entity.get("IntervalCreateSummonUnitDefList", []).size():
			var rule: Dictionary = entity.IntervalCreateSummonUnitDefList[index]
			var interval = float(rule.get("Duration", 0))
			var delay = maxf(0, float(rule.get("DelayTime", 0)))
			if interval > 0: interval_summon_times[str(index)] = delay + maxf(0, floor((age - delay) / interval) + 1) * interval
	if not data.has("last_hit_times"):
		for key in hits: last_hit_times[key] = age
	if motion_type in ["EMAT_FollowOwner", "EMAT_Fixed", "EMAT_None"] and motion.has("LastTime"):
		lifetime = maxf(0.01, float(motion.LastTime) / 1000.0)
		finished = age >= lifetime
	passed = int(data.get("passed", 0))
	source_player = bool(data.get("source_player", true))

static func _array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]
