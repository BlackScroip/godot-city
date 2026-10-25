extends RefCounted

static func source_bool(value: Variant) -> bool:
	return str(value).to_lower() == "true" if value is String else bool(value)

# Integrate source action seconds so speed changes and hit stop preserve travel.
static func curve_integral(kind: String, t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	match kind:
		"EMST_GraduallyStop", "EMST_SelfMoveSpeedAttribute_GraduallyStop": return 2.0 * t - t * t
		"EMST_GraduallyStartAndStop": return t - t * t if t <= 0.5 else t * t - t + 0.5
	return t

static func distance(raw: Dictionary, duration: float, first: float, last: float, combat: RefCounted) -> float:
	if duration <= 0.0 or last <= first: return 0.0
	var speed = float(raw.get("CustomSpeed", 0.0))
	for property in str(raw.get("CustomSpeed_ProtextContext", "")).split("|", false):
		var value: Variant = combat.property_value(property)
		if value is float or value is int: speed += float(value)
	var kind = str(raw.get("MoveSpeedType", "EMST_Line"))
	if kind.begins_with("EMST_SelfMoveSpeedAttribute"): speed *= combat.move_speed
	return speed * duration * (curve_integral(kind, last / duration) - curve_integral(kind, first / duration))

static func direction(raw: Dictionary, actor: CharacterBody3D) -> Vector3:
	var input: Vector3 = actor.desired_velocity / maxf(0.01, actor.combat.move_speed)
	input = input.limit_length()
	# The shipped MultiInput branch replaces direction, then scales speed by its length.
	if raw.get("MoveSpeedMultiInputDir", false): return input * input.length()
	match str(raw.get("MoveDirType", "EMDT_FrontFace")):
		"EMDT_InputMoveDir": return input.normalized() if input.length_squared() > 0.00001 else actor.facing
		"EMDT_Custom":
			var custom: Dictionary = raw.get("CustomDirection", {})
			return actor.facing * float(custom.get("z", 0)) + Vector3.UP.cross(actor.facing) * float(custom.get("x", 0)) + Vector3.UP * float(custom.get("y", 0))
		"EMDT_UnitLeft": return -Vector3.UP.cross(actor.facing)
		"EMDT_UnitRight": return Vector3.UP.cross(actor.facing)
		"EMDT_Perpendicular2BornPoint", "EMDT_Perpendicular2Target", "EMDT_AroundFieldCenter":
			var center: Vector3 = actor.born_position
			if str(raw.MoveDirType) == "EMDT_AroundFieldCenter": center = actor.field_center
			elif str(raw.MoveDirType) == "EMDT_Perpendicular2Target" and is_instance_valid(actor.action_target): center = actor.action_target.position
			var radial: Vector3 = actor.position - center
			radial.y = 0
			if radial.length_squared() < 0.00001: radial = -actor.born_facing * 0.01
			var tangent = Vector3.UP.cross(radial)
			var gap = float(raw.get("TargetRadius", 0)) - radial.length()
			var sensitivity = maxf(0.01, float(raw.get("TargetRadius_Nearfarspeed", 0.5)))
			if str(raw.MoveDirType) == "EMDT_Perpendicular2BornPoint":
				if absf(gap) > 0.2: tangent += signf(gap) * sensitivity * radial.normalized()
			else:
				tangent += radial * gap / sensitivity
			return tangent.normalized()
		"EMDT_MoveToTarget", "EMDT_LeaveAwayTarget":
			if is_instance_valid(actor.action_target) and not actor.action_target.dead:
				var result: Vector3 = actor.action_target.position - actor.position
				result.y = 0
				return result.normalized() * (-1.0 if raw.MoveDirType == "EMDT_LeaveAwayTarget" else 1.0)
	return actor.facing

static func turn(actor: CharacterBody3D, direction_value: Vector3, smooth: bool, scale: float, delta: float) -> void:
	direction_value.y = 0
	if direction_value.length_squared() < 0.00001: return
	if smooth and scale < 1.0:
		var angle = actor.facing.signed_angle_to(direction_value.normalized(), Vector3.UP)
		actor.face_direction(actor.facing.rotated(Vector3.UP, clampf(angle, -TAU * maxf(0, scale) * delta, TAU * maxf(0, scale) * delta)))
	else:
		actor.face_direction(direction_value)

static func aim(actor: CharacterBody3D, raw: Dictionary, delta: float) -> void:
	if not raw.get("IsFaceTarget", true): return
	var direction_value := Vector3.ZERO
	if is_instance_valid(actor.action_target) and not actor.action_target.dead:
		direction_value = actor.action_target.position - actor.position
	elif raw.get("IsCanRotateWhenNoSearchTarget", true):
		direction_value = actor.desired_velocity
	var scale = float(raw.get("RotateSpeedScale", 1.0))
	var modifier: Variant = actor.combat.property_value(str(raw.get("RotateSpeedScaleModifyPropertyName", "")))
	if modifier is float or modifier is int: scale += float(modifier)
	turn(actor, direction_value, bool(raw.get("IsSmoothFaceTarget", false)), scale, delta)
