class_name DungeonTouchButton
extends Button

const PRESSED_SCALE := 0.88
const PRESS_DURATION := 0.065
const RELEASE_DURATION := 0.18
const SP_FILL = preload("res://assets/ui/battle_guide/39b0cffbf50d0122.png")

var finger := -1
var hit_padding := 0.0
var visual_scale := 1.0
var _feedback_start := 1.0
var _feedback_target := 1.0
var _feedback_elapsed := 0.0
var _feedback_duration := 0.0
var art: Texture2D
var ring: Texture2D
var cooldown := 0.0
var cooldown_total := 1.0
var unavailable := false
var stock := -1
var recharge_remaining := 0.0
var recharge_total := 1.0
var charging := false
var charge_fraction := 0.0
var resource_fraction := -1.0
var resource_color := Color(1, 0.675732, 0.117647)
var queued := false
var ready_full := false:
	set(value):
		if ready_full == value: return
		ready_full = value
		_sync_ready_effect()
var readiness_suspended := false:
	set(value):
		if readiness_suspended == value: return
		readiness_suspended = value
		_sync_ready_effect()
var low_effects := false:
	set(value):
		if low_effects == value: return
		low_effects = value
		if is_instance_valid(ready_orbit): ready_orbit.low_effects = value
var ready_orbit: Node2D
var _readiness_latched := false
var _application_focused := true

static func skill_resource_color(element: int) -> Color:
	return {
		1: Color(1, 0.675732, 0.117647), 2: Color(0.494118, 0.764706, 1),
		3: Color(0.149020, 1, 0.925490), 4: Color(1, 0.780392, 0.345098),
		5: Color(1, 0.925490, 0.701961), 6: Color(0.592157, 0.298039, 1),
		9: Color(0.330189, 0.68846, 1)
	}.get(element, Color.WHITE)

static func has_full_skill_resource(slot: int, current: float, capacity: float, cost: float, remaining_cooldown: float, alive: bool) -> bool:
	return slot == 3 and alive and remaining_cooldown <= 0 and capacity > 0 and current + 0.001 >= capacity and current + 0.001 >= cost

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	toggle_mode = true
	focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	button_down.connect(func(): _start_feedback(true))
	button_up.connect(func(): _start_feedback(false))
	ready_orbit = preload("res://scripts/presentation/skill_ready_orbit.gd").new()
	add_child(ready_orbit)
	visibility_changed.connect(_visibility_changed)
	resized.connect(func():
		release(true)
		_sync_ready_effect())
	get_window().mouse_exited.connect(_mouse_exited)
	_sync_ready_effect()

func _process(delta: float) -> void:
	if disabled or (finger == -2 and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)):
		release(true)
	_advance_feedback(delta)
	_sync_ready_effect()

func _start_feedback(pressed: bool) -> void:
	_feedback_start = minf(visual_scale, 0.96) if pressed else visual_scale
	_feedback_target = PRESSED_SCALE if pressed else 1.0
	_feedback_elapsed = 0.0
	_feedback_duration = PRESS_DURATION if pressed else RELEASE_DURATION
	_set_visual_scale(_feedback_start)

func _advance_feedback(delta: float) -> void:
	if _feedback_duration <= 0: return
	_feedback_elapsed = minf(_feedback_duration, _feedback_elapsed + delta)
	var progress = _feedback_elapsed / _feedback_duration
	var tail = progress - 1.0
	var eased = 1.0 + tail * tail * tail
	if _feedback_target == 1.0:
		eased = 1.0 + 2.70158 * tail * tail * tail + 1.70158 * tail * tail
	_set_visual_scale(lerpf(_feedback_start, _feedback_target, eased))
	if _feedback_elapsed >= _feedback_duration: _feedback_duration = 0.0

func _set_visual_scale(value: float) -> void:
	visual_scale = value
	if is_instance_valid(ready_orbit):
		ready_orbit.scale = Vector2.ONE * value
		ready_orbit.position = size * 0.5 * (1.0 - value)
	queue_redraw()

func _reset_feedback() -> void:
	if _feedback_duration <= 0 and visual_scale == 1.0: return
	_feedback_duration = 0.0
	_set_visual_scale(1.0)

func _sync_ready_effect() -> void:
	if not is_instance_valid(ready_orbit): return
	var show_effect = ready_full and not readiness_suspended and _application_focused and not disabled and not unavailable and cooldown <= 0 and not charging and is_visible_in_tree()
	ready_orbit.button_size = size
	ready_orbit.low_effects = low_effects
	ready_orbit.set_active(show_effect, show_effect and not _readiness_latched)
	_readiness_latched = ready_full

func _visibility_changed() -> void:
	release(true)
	_sync_ready_effect()

func _draw() -> void:
	var center = size * 0.5
	var radius = size.x * 0.48
	# Animate the artwork while the pointer keeps its original circular target.
	draw_set_transform(center * (1.0 - visual_scale), 0, Vector2.ONE * visual_scale)
	draw_circle(center, radius, Color(0.06, 0.13, 0.18, 0.25 if not button_pressed else 0.6))
	if ring: draw_texture_rect(ring, Rect2(Vector2.ZERO, size), false, Color(1, 1, 1, 0.65))
	else: draw_arc(center, radius, 0, TAU, 64, Color(0.8, 0.9, 0.9, 0.5), 1.0, true)
	if resource_fraction >= 0:
		var disk_rect := Rect2(size * 0.08, size * 0.84)
		draw_texture_rect(SP_FILL, disk_rect, false, Color(0.04, 0.08, 0.1, 0.65))
		var fraction := clampf(resource_fraction, 0, 1)
		if fraction > 0:
			var source_size := Vector2(SP_FILL.get_size())
			var source := Rect2(Vector2(0, source_size.y * (1 - fraction)), Vector2(source_size.x, source_size.y * fraction))
			var destination := Rect2(disk_rect.position + Vector2(0, disk_rect.size.y * (1 - fraction)), Vector2(disk_rect.size.x, disk_rect.size.y * fraction))
			draw_texture_rect_region(SP_FILL, destination, source, Color(resource_color, 0.72))
	if art: draw_texture_rect(art, Rect2(size * 0.12, size * 0.76), false, Color(1, 1, 1, 0.5 if unavailable else 1.0))
	if charging: draw_arc(center, radius, -PI / 2, -PI / 2 + TAU * maxf(0.01, charge_fraction), 48, Color("a4edff"), 4, true)
	if queued: draw_arc(center, radius, 0, TAU, 48, Color("ffdc78"), 3, true)
	if recharge_remaining > 0:
		var progress = 1.0 - clampf(recharge_remaining / maxf(0.001, recharge_total), 0, 1)
		draw_arc(center, radius, -PI / 2, -PI / 2 + TAU * maxf(0.001, progress), 48, Color("a4edff"), 4, true)
	if cooldown > 0:
		var angle = TAU * clampf(cooldown / maxf(0.001, cooldown_total), 0, 1)
		var mask_color = Color(0.02, 0.06, 0.09, 0.65)
		if angle >= TAU - 0.001:
			draw_circle(center, radius, mask_color)
		elif angle > 0.001:
			var points = PackedVector2Array([center])
			for i in range(33): points.append(center + Vector2.from_angle(-PI / 2 + angle * i / 32.0) * radius)
			draw_colored_polygon(points, mask_color)
		var value = "%.1f" % cooldown
		var font = get_theme_default_font()
		draw_string(font, Vector2(center.x - font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x / 2, center.y + 8), value, HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
	elif recharge_remaining > 0 and unavailable:
		var value = "%.1f" % recharge_remaining
		var font = get_theme_default_font()
		draw_string(font, Vector2(center.x - font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x / 2, center.y + 8), value, HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
	if stock >= 0:
		draw_string(get_theme_default_font(), Vector2(size.x * 0.65, 23), str(stock), HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
	draw_set_transform(Vector2.ZERO)

func _input(event: InputEvent) -> void:
	if disabled or not is_visible_in_tree():
		release(true)
		return
	if event is InputEventScreenTouch:
		if event.canceled:
			if finger != event.index: return
			release(true)
		elif event.pressed and finger == -1 and _contains(event.position):
			finger = event.index
			button_pressed = true
			button_down.emit()
		elif not event.pressed and finger == event.index: release()
		else: return
	elif event is InputEventMouseButton and event.device != -1 and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and finger == -1 and _contains(event.position):
			finger = -2
			button_pressed = true
			button_down.emit()
		elif not event.pressed and finger == -2: release()
		else: return
	else: return
	get_viewport().set_input_as_handled()

func _contains(point: Vector2) -> bool:
	return (get_global_transform_with_canvas().affine_inverse() * point).distance_to(size * 0.5) <= minf(size.x, size.y) * 0.5 + hit_padding

func release(reset_feedback := false) -> void:
	if finger != -1:
		finger = -1
		button_pressed = false
		button_up.emit()
	if reset_feedback: _reset_feedback()

func _mouse_exited() -> void:
	if finger == -2: release(true)

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		_application_focused = false
		release(true)
		_sync_ready_effect()
	elif what in [NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED]:
		_application_focused = true
		_sync_ready_effect()
