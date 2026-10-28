extends ScrollContainer

const DRAG_THRESHOLD := 10.0
const DECELERATION_RATE := 0.135
const WHEEL_STEP := 110.0
var _pointer := -1
var _origin := Vector2.ZERO
var _last_position := Vector2.ZERO
var _last_motion := 0
var _dragging := false
var _slider: HSlider
var _slider_dragging := false
var _offset := 0.0
var _velocity := 0.0
var _wheel_target := 0.0
var _wheel_active := false

func _ready() -> void:
	# Gesture arbitration happens before child buttons or sliders receive a drag.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	follow_focus = true
	set_process(false)

func reset_motion(value := 0.0) -> void:
	_cancel_pointer()
	_velocity = 0.0
	_wheel_active = false
	_offset = clampf(value, 0.0, _maximum())
	scroll_vertical = roundi(_offset)
	set_process(false)

func _maximum() -> float:
	var bar := get_v_scroll_bar()
	return maxf(0.0, bar.max_value - bar.page)

func _local_delta(value: Vector2) -> Vector2:
	return get_global_transform_with_canvas().basis_xform_inv(value)

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not is_inside_tree(): return
	if event is InputEventPanGesture and get_global_rect().has_point(event.position):
		_wheel(event.delta.y * 0.4)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if event.pressed and get_global_rect().has_point(event.position):
				_wheel(event.factor * (-1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0))
				get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed: _begin_pointer(event.position, -2)
			elif _pointer == -2: _release_pointer(event.position)
	elif event is InputEventMouseMotion and _pointer == -2:
		_move_pointer(event.position)
	elif not bool(ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch", true)):
		if event is InputEventScreenTouch:
			if event.pressed: _begin_pointer(event.position, event.index)
			elif _pointer == event.index: _release_pointer(event.position)
		elif event is InputEventScreenDrag and _pointer == event.index:
			_move_pointer(event.position)

func _begin_pointer(point: Vector2, index: int) -> void:
	if _pointer != -1 or not get_global_rect().has_point(point): return
	reset_motion(float(scroll_vertical))
	var bar := get_v_scroll_bar()
	if bar.visible and bar.get_global_rect().has_point(point): return
	_pointer = index
	_origin = point
	_last_position = point
	_last_motion = Time.get_ticks_msec()
	for child in find_children("*", "HSlider", true, false):
		if child.is_visible_in_tree() and child.get_global_rect().has_point(point):
			_slider = child
			get_viewport().set_input_as_handled()
			break

func _move_pointer(point: Vector2) -> void:
	var distance := point - _origin
	if not _dragging and not _slider_dragging:
		if distance.length() < DRAG_THRESHOLD: return
		if is_instance_valid(_slider) and absf(distance.x) > absf(distance.y):
			_slider_dragging = true
		else:
			_dragging = true
			_offset = float(scroll_vertical)
			propagate_notification(Control.NOTIFICATION_SCROLL_BEGIN)
			scroll_started.emit()
	if _slider_dragging:
		_adjust_slider(point)
	elif _dragging:
		var now := Time.get_ticks_msec()
		var movement := -_local_delta(point - _last_position).y
		var elapsed := maxf(0.008, float(now - _last_motion) / 1000.0)
		_velocity = lerpf(_velocity, clampf(movement / elapsed, -4000.0, 4000.0), 0.5)
		_offset = clampf(_offset + movement, 0.0, _maximum())
		scroll_vertical = roundi(_offset)
		_last_position = point
		_last_motion = now
	get_viewport().set_input_as_handled()

func _release_pointer(point: Vector2) -> void:
	if _dragging:
		if Time.get_ticks_msec() - _last_motion > 100: _velocity = 0.0
		get_viewport().set_input_as_handled()
		set_process(absf(_velocity) > 1.0)
	elif is_instance_valid(_slider):
		_adjust_slider(point)
		get_viewport().set_input_as_handled()
	_cancel_pointer()

func _cancel_pointer() -> void:
	if _dragging:
		propagate_notification(Control.NOTIFICATION_SCROLL_END)
		scroll_ended.emit()
	_pointer = -1
	_dragging = false
	_slider_dragging = false
	_slider = null

func _adjust_slider(point: Vector2) -> void:
	if not is_instance_valid(_slider): return
	_slider.grab_focus()
	var local := _slider.get_global_transform_with_canvas().affine_inverse() * point
	var thumb := _slider.get_theme_icon("grabber")
	var inset := float(thumb.get_width()) * 0.5 if thumb else 0.0
	var fraction := clampf((local.x - inset) / maxf(1.0, _slider.size.x - inset * 2.0), 0.0, 1.0)
	_slider.value = lerpf(_slider.min_value, _slider.max_value, fraction)

func _wheel(direction: float) -> void:
	if _dragging or _slider_dragging: return
	_velocity = 0.0
	if not _wheel_active:
		_offset = float(scroll_vertical)
		_wheel_target = _offset
	_wheel_target = clampf(_wheel_target + direction * WHEEL_STEP, 0.0, _maximum())
	_wheel_active = true
	set_process(true)

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		reset_motion(float(scroll_vertical))
		return
	if _wheel_active:
		_offset = lerpf(_offset, _wheel_target, 1.0 - exp(-18.0 * delta))
		if absf(_offset - _wheel_target) < 0.5:
			_offset = _wheel_target
			_wheel_active = false
	else:
		var decay := pow(DECELERATION_RATE, delta)
		_offset = clampf(_offset + _velocity * (1.0 - decay) / -log(DECELERATION_RATE), 0.0, _maximum())
		_velocity *= decay
		if _offset <= 0.0 or _offset >= _maximum(): _velocity = 0.0
	scroll_vertical = roundi(_offset)
	if not _wheel_active and absf(_velocity) < 8.0:
		_velocity = 0.0
		set_process(false)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		reset_motion(float(scroll_vertical))
