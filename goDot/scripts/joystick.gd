class_name DungeonJoystick
extends Control

var value := Vector2.ZERO
var finger := -1
var radius := 64.0
var knob := Vector2.ZERO
var home := Vector2.INF
var center := Vector2.ZERO
var drag_origin := Vector2.ZERO
var excluded_controls: Array[Control] = []
const FEEL = preload("res://assets/feel_settings.tres")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(164, 164)
	get_window().mouse_exited.connect(_mouse_exited)
	get_window().focus_exited.connect(_reset)
	resized.connect(_reset)
	visibility_changed.connect(_reset)

func _home() -> Vector2:
	return home if home.is_finite() else size * 0.5

func _draw() -> void:
	var point := _home() if finger == -1 else center
	var opacity := 0.24 if finger == -1 else 0.65
	var ring = DungeonStyle.texture("joystick_ring")
	var thumb = DungeonStyle.texture("joystick_thumb")
	if ring: draw_texture_rect(ring, Rect2(point - Vector2.ONE * radius, Vector2.ONE * radius * 2), false, Color(1, 1, 1, opacity))
	draw_arc(point, radius, 0, TAU, 64, Color(0.85, 0.92, 0.88, 0.28 if finger == -1 else 0.45), 1.5, true)
	if value.length_squared() > 0.001:
		draw_arc(point, radius, knob.angle() - 0.3, knob.angle() + 0.3, 16, Color(0.85, 0.92, 0.75, 0.8), 3, true)
	if thumb: draw_texture_rect(thumb, Rect2(point + knob - Vector2.ONE * 25, Vector2.ONE * 50), false, Color(1, 1, 1, opacity + 0.12))

func _can_begin(point: Vector2, global_point: Vector2) -> bool:
	if not Rect2(Vector2.ZERO, size).has_point(point): return false
	for control in excluded_controls:
		if is_instance_valid(control) and control.is_visible_in_tree():
			var local := control.get_global_transform_with_canvas().affine_inverse() * global_point
			if Rect2(Vector2.ZERO, control.size).has_point(local): return false
	return true

func _begin_pointer(index: int, point: Vector2) -> void:
	finger = index
	drag_origin = point
	var margin := Vector2.ONE * (radius + 8)
	center = point.clamp(margin, size - margin)
	_set_point(point)

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		_reset()
		return
	var local_point = Vector2.ZERO
	if event is InputEventScreenTouch or event is InputEventScreenDrag or event is InputEventMouseButton or event is InputEventMouseMotion:
		local_point = get_global_transform_with_canvas().affine_inverse() * event.position
	if event is InputEventScreenTouch:
		if event.canceled:
			if finger != event.index: return
			_reset()
		elif event.pressed and finger in [-1, event.index] and _can_begin(local_point, event.position):
			_begin_pointer(event.index, local_point)
		elif not event.pressed and finger == event.index:
			_reset()
		else: return
	elif event is InputEventScreenDrag and event.index == finger:
		_set_point(local_point)
	elif event is InputEventMouseButton and event.device != -1 and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and finger in [-1, -2] and _can_begin(local_point, event.position):
			_begin_pointer(-2, local_point)
		elif not event.pressed and finger == -2: _reset()
		else: return
	elif event is InputEventMouseMotion and event.device != -1 and finger == -2:
		_set_point(local_point)
	else: return
	get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]: _reset()

func _mouse_exited() -> void:
	if finger == -2: _reset()

func _process(_delta: float) -> void:
	if finger == -2 and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): _reset()

func _set_point(point: Vector2) -> void:
	knob = (point - (_home() if finger == -1 else drag_origin)).limit_length(radius)
	var magnitude = knob.length() / radius
	value = knob.normalized() * maxf(0.0, (magnitude - FEEL.joystick_deadzone) / (1.0 - FEEL.joystick_deadzone))
	queue_redraw()

func _reset() -> void:
	finger = -1
	drag_origin = Vector2.ZERO
	center = _home()
	knob = Vector2.ZERO
	value = Vector2.ZERO
	queue_redraw()
