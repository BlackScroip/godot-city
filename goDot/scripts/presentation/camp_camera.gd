extends RefCounted

# Shared act camera :77/:115 and EnvCfg_[10000] from the APK.
const FIELD_OF_VIEW := 45.0
const DEFAULT_DISTANCE := 13.0
const MIN_DISTANCE := 8.0
const MAX_DISTANCE := 15.0
const FOLLOW_PER_FRAME := 0.08
const ZOOM_PER_FRAME := 0.1

var distance := DEFAULT_DISTANCE
var target_distance := DEFAULT_DISTANCE
var direction := Vector3(0.5, sqrt(0.5), -0.5)
var focus_position := Vector3.ZERO
var focus_remaining := 0.0

func configure(camera: Camera3D, entry: Dictionary) -> void:
	reset()
	var angles: Array = entry.get("camera_rotation", [45.0, -45.0])
	var elevation := deg_to_rad(float(angles[0]))
	var yaw := deg_to_rad(float(angles[1]))
	direction = Vector3(-sin(yaw) * cos(elevation), sin(elevation), -cos(yaw) * cos(elevation))
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.fov = FIELD_OF_VIEW

func reset() -> void:
	distance = DEFAULT_DISTANCE
	target_distance = DEFAULT_DISTANCE
	focus_remaining = 0.0

func zoom(steps: float) -> void:
	if not is_finite(steps): return
	target_distance = clampf(target_distance + steps * 0.8, MIN_DISTANCE, MAX_DISTANCE)

func focus(point: Vector3, duration: float) -> void:
	if not point.is_finite() or not is_finite(duration): return
	focus_position = point
	focus_remaining = maxf(0.0, duration)

func target(player_position: Vector3) -> Vector3:
	return focus_position if focus_remaining > 0.0 else player_position + Vector3.UP * 0.4

func step(delta: float, hold_focus := false) -> void:
	if delta <= 0.0: return
	# Convert source per-frame smoothing to a 60 Hz reference for mobile refresh rates.
	distance = lerpf(distance, target_distance, 1.0 - pow(1.0 - ZOOM_PER_FRAME, delta * 60.0))
	if not hold_focus: focus_remaining = maxf(0.0, focus_remaining - delta)

func follow_weight(delta: float) -> float:
	return 1.0 - pow(1.0 - FOLLOW_PER_FRAME, maxf(0.0, delta) * 60.0)

func offset() -> Vector3:
	return direction * distance
