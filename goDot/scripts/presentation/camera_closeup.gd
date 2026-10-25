extends RefCounted

const SOURCE = "res://assets/data/camera_closeup.json"
const ZOOM_SPEED := 0.1

var distance_offset := 0.0
var target_offset := 0.0
var paused := false
var owner: Variant = null
var action_key := ""
var action_time_ms := 0.0
var _windows: Dictionary = {}
var _condition_check: Callable
var _follow: Node3D
var _look_at: Node3D

func _init() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
	for row in data.get("fade_windows", []):
		var key := "playerchara/" + str(row.action)
		if not _windows.has(key): _windows[key] = []
		_windows[key].append(row.event)

func enter(event_owner: Variant, key: String, condition_check := Callable()) -> void:
	owner = event_owner
	action_key = key
	if action_key.begins_with("ActGroup_"):
		action_key = action_key.trim_prefix("ActGroup_")
	if not key.contains("/"): action_key = "playerchara/" + key
	action_time_ms = 0.0
	_condition_check = condition_check
	_follow = null
	_look_at = null
	_update_target()

func update_action(event_owner: Variant, elapsed_ms: float) -> void:
	if event_owner != owner or paused: return
	action_time_ms = maxf(0.0, elapsed_ms)
	_update_target()

func _update_target() -> void:
	target_offset = 0.0
	for event in _windows.get(action_key, []):
		if not event.get("Enabled", true): continue
		var start := float(event.get("TriggerTime", 0.0))
		var end := start + float(event.get("Duration", 0.0))
		if action_time_ms < start or action_time_ms >= end: continue
		var conditions: Array = event.get("Conditions", [])
		if not conditions.is_empty():
			if not _condition_check.is_valid(): continue
			if not bool(_condition_check.call(event)): continue
		target_offset = float(event.get("EventData", {}).get("TargetFade", 0.0))

func exit(event_owner: Variant) -> void:
	if event_owner != owner: return
	owner = null
	action_key = ""
	target_offset = 0.0
	_follow = null
	_look_at = null

func cancel() -> void:
	owner = null
	action_key = ""
	action_time_ms = 0.0
	target_offset = 0.0
	distance_offset = 0.0
	_follow = null
	_look_at = null
	_condition_check = Callable()

func pause(value: bool) -> void:
	paused = value

func restore() -> void:
	cancel()
	paused = false

func step(delta: float) -> float:
	if paused or delta <= 0.0: return distance_offset
	if owner is Object and not is_instance_valid(owner): cancel()
	# The APK uses per-LateUpdate Lerp(ZoomSpeed=.1), without multiplying delta.
	distance_offset = lerpf(distance_offset, target_offset, ZOOM_SPEED)
	if absf(distance_offset - target_offset) < 0.00001:
		distance_offset = target_offset
	return distance_offset

func enter_transforms(event_owner: Variant, follow: Node3D, look_target: Node3D) -> bool:
	if not is_instance_valid(follow) or not is_instance_valid(look_target): return false
	owner = event_owner
	action_key = ""
	target_offset = 0.0
	_follow = follow
	_look_at = look_target
	return true

func apply(camera: Camera3D, focus: Vector3, base_offset: Vector3) -> void:
	if not is_instance_valid(camera): return
	if is_instance_valid(_follow) and is_instance_valid(_look_at):
		camera.global_position = _follow.global_position
		if not camera.global_position.is_equal_approx(_look_at.global_position):
			camera.look_at(_look_at.global_position)
		return
	var distance := base_offset.length()
	if distance <= 0.0: return
	# The guard prevents crossing the focus if a caller supplies an invalid baseline.
	camera.global_position = focus + base_offset.normalized() * maxf(camera.near, distance + distance_offset)
	camera.look_at(focus)
