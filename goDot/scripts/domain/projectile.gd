class_name DungeonProjectile
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

var _acceleration := 0.0
var _maximum_speed := INF
var _trace_target := false
var _trace_delay := 0.0
var _trace_end := 99.0
var _trace_distance := INF
var _trace_angle := PI
var _trace_turn := 0.02
var _rotate_radius := 1.0
var _radius_delta_speed := 0.0
var _rotate_follow_owner := true
var _rotate_offset := Vector3.ZERO
var _rotate_angle_speed := deg_to_rad(120.0)
var _curve_height := 0.0
var _collider_offset := Vector3.ZERO
var _collider_size := Vector3.ZERO
var _sphere_collider := true
var _check_role_collider := true
var _collision_delay := 0.0
var _max_collision_count := 1
var _max_passes := 0
var _bounce_wall := false

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
	_acceleration = 0.0
	_maximum_speed = INF
	_trace_target = false
	_trace_delay = 0.0
	_trace_end = 99.0
	_trace_distance = INF
	_trace_angle = PI
	_trace_turn = 0.02
	_rotate_radius = 1.0
	_radius_delta_speed = 0.0
	_rotate_follow_owner = true
	_rotate_offset = Vector3.ZERO
	_rotate_angle_speed = deg_to_rad(120.0)
	_curve_height = 0.0
	_collider_offset = Vector3.ZERO
	_collider_size = Vector3.ZERO
	_sphere_collider = true
	_check_role_collider = true
	_collision_delay = 0.0
	_max_collision_count = 1
	_max_passes = 0
	_bounce_wall = false

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

static func multipoint_transform(event: Dictionary, point: Vector3, facing: Vector3) -> Dictionary:
	var raw := DungeonWorld._read_definition(event.get("definition", {}))
	var points: Array = raw.get("EmitProperty", {}).get("PointData", [])
	var index := int(event.get("emit_index", 0))
	if index < 0 or index >= points.size(): return {"position": point, "facing": facing}
	var selected: Dictionary = points[index]
	var offset := DungeonWorld.vector(selected.get("Offset", {}))
	var yaw := deg_to_rad(float(selected.get("Rotate", {}).get("y", 0)))
	return {"position": point + orient(offset, facing) + DungeonWorld.vector(event.get("emit_random_offset", [])), "facing": facing.rotated(Vector3.UP, yaw)}

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
	if raw.get("EmitType", "") == "EET_MultiPoint":
		var transform_data := multipoint_transform(hit, point, direction)
		owner_offset = transform_data.position - point
		direction = transform_data.facing
	elif raw.get("EmitType", "") == "EET_ARC":
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
	_compile_properties()

func _compile_properties() -> void:
	# Source dictionaries remain intact for snapshots and presentation consumers.
	# Only immutable configuration is compiled; simulation state stays live.
	_collider_offset = DungeonWorld.vector(entity.get("ModelBoxColliderCenterOffset", {}))
	_collider_size = DungeonWorld.vector(entity.get("ModelBoxColliderSize", {}))
	_sphere_collider = str(entity.get("ColliderType", "Cube")) == "Sphere" or _collider_size.length_squared() < 0.001
	_check_role_collider = bool(entity.get("IsCheckRoleUnitCollider", true))
	_collision_delay = float(entity.get("EnableGlobalCollisionDelayTime", 0))
	_max_collision_count = maxi(1, int(entity.get("MaxCollisionCountPerTarget", 1)))
	_max_passes = int(entity.get("MaxPassNum", 0))
	_bounce_wall = bool(entity.get("CanBounceWall", false))
	match motion_type:
		"EMAT_Line":
			_acceleration = float(motion.get("Acc", 0))
			_maximum_speed = maxf(0, float(motion.get("MaxSpeed", INF)))
			_trace_target = bool(motion.get("TraceTarget", false))
			_trace_delay = float(motion.get("TraceDelayTime", 0))
			_trace_end = _trace_delay + float(motion.get("TraceMaxKeepTime", 99))
			_trace_distance = float(motion.get("TraceMaxDis", INF))
			_trace_angle = deg_to_rad(float(motion.get("TraceMaxAngle", 180)))
			_trace_turn = maxf(0, float(motion.get("TraceAngelRotateIndentity", 0.02)))
		"EMAT_RotateOwner":
			_rotate_radius = float(motion.get("RotateRadius", 1))
			_radius_delta_speed = float(motion.get("RadiusDeltaSpeed", 0))
			_rotate_follow_owner = bool(motion.get("IsFollowOwner", true))
			_rotate_offset = DungeonWorld.vector(motion.get("FollowOwnerRotatePointOffset", {}))
			_rotate_angle_speed = deg_to_rad(float(motion.get("RotateAngleSpeed", 120)))
		"EMAT_Curve", "EMAT_Parabola":
			_curve_height = float(motion.get("YDis", origin.distance_to(destination) * float(motion.get("CurveHeightCoeff", 0.3))))

func advance(delta: float, owner_position: Vector3, owner_facing: Vector3, target: Vector3 = Vector3.INF) -> void:
	if finished: return
	delta = minf(maxf(0, delta), maxf(0, lifetime - age))
	previous = position
	age += delta
	match motion_type:
		"EMAT_Line":
			if _trace_target and target.is_finite() and age >= _trace_delay and age <= _trace_end:
				var difference = target - position
				difference.y = 0
				var desired = difference.normalized()
				if difference.length() <= _trace_distance and absf(direction.signed_angle_to(desired, Vector3.UP)) <= _trace_angle:
					# Original sensitivity units are unverified; this uses radians per 50 Hz step.
					var turn = _trace_turn * 50 * delta
					direction = direction.rotated(Vector3.UP, clampf(direction.signed_angle_to(desired, Vector3.UP), -turn, turn)).normalized()
			speed = clampf(speed + _acceleration * delta, 0, _maximum_speed)
			position += direction * speed * delta
		"EMAT_FollowOwner":
			position = owner_position + owner_offset
		"EMAT_RotateOwner":
			var radius_value = maxf(0, _rotate_radius + age * _radius_delta_speed)
			var center = owner_position if _rotate_follow_owner else origin
			position = center + orient(_rotate_offset, owner_facing) + direction.rotated(Vector3.UP, _rotate_angle_speed * age) * radius_value
		"EMAT_Curve", "EMAT_Parabola":
			var progress = minf(1, age / lifetime)
			position = origin.lerp(destination, progress) + Vector3.UP * 4 * _curve_height * progress * (1 - progress)
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
	return not finished and _check_role_collider and age >= _collision_delay and int(hits.get(key, 0)) < mini(hit_limit, _max_collision_count) and age + 0.000001 >= float(last_hit_times.get(key, -INF)) + hit_interval

func record_hit(key: String) -> void:
	hits[key] = int(hits.get(key, 0)) + 1
	last_hit_times[key] = age
	passed += 1
	if passed > _max_passes: finished = true

func intersects(center: Vector3) -> bool:
	var offset = orient(_collider_offset, direction)
	var from = previous + offset
	var to = position + offset
	if _sphere_collider:
		# Use the same standing hurt volume as box attacks, including upper-body
		# contacts. A point at waist height made authored high shots miss entirely.
		var contacts = Geometry3D.get_closest_points_between_segments(from, to, center - Vector3.UP * 0.75, center + Vector3.UP * 0.75)
		return contacts[0].distance_squared_to(contacts[1]) <= (radius + 0.35) * (radius + 0.35)
	var closest = Geometry3D.get_closest_point_to_segment(center, from, to)
	var difference = center - closest
	return absf(difference.y) <= _collider_size.y * 0.5 + 0.75 and absf(difference.dot(direction)) <= _collider_size.z * 0.5 + 0.35 and absf(difference.dot(Vector3(direction.z, 0, -direction.x))) <= _collider_size.x * 0.5 + 0.35

func wall_collision(point: Vector3, normal: Vector3) -> void:
	position = point + normal * 0.02
	if _bounce_wall: direction = direction.bounce(normal).normalized()
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
	_compile_properties()

static func _array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]
