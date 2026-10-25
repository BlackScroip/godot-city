class_name DungeonTouchButton
extends Button

var finger := -1
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

static func has_full_skill_resource(slot: int, current: float, capacity: float, cost: float, remaining_cooldown: float, alive: bool) -> bool:
	return slot == 3 and alive and remaining_cooldown <= 0 and capacity > 0 and current + 0.001 >= capacity and current + 0.001 >= cost

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	toggle_mode = true
	focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)
	ready_orbit = preload("res://scripts/presentation/skill_ready_orbit.gd").new()
	add_child(ready_orbit)
	visibility_changed.connect(_visibility_changed)
	resized.connect(_sync_ready_effect)
	_sync_ready_effect()

func _process(_delta: float) -> void:
	_sync_ready_effect()

func _sync_ready_effect() -> void:
	if not is_instance_valid(ready_orbit): return
	var show_effect = ready_full and not readiness_suspended and _application_focused and not disabled and not unavailable and cooldown <= 0 and not charging and is_visible_in_tree()
	ready_orbit.button_size = size
	ready_orbit.low_effects = low_effects
	ready_orbit.set_active(show_effect, show_effect and not _readiness_latched)
	_readiness_latched = ready_full

func _visibility_changed() -> void:
	release()
	_sync_ready_effect()

func _draw() -> void:
	var center = size * 0.5
	var radius = size.x * 0.48
	draw_circle(center, radius, Color(0.06, 0.13, 0.18, 0.25 if not button_pressed else 0.6))
	if ring: draw_texture_rect(ring, Rect2(Vector2.ZERO, size), false, Color(1, 1, 1, 0.65))
	else: draw_arc(center, radius, 0, TAU, 64, Color(0.8, 0.9, 0.9, 0.5), 1.0, true)
	if art: draw_texture_rect(art, Rect2(size * 0.12, size * 0.76), false, Color(1, 1, 1, 0.35 if unavailable else 1.0))
	if charging: draw_arc(center, radius, -PI / 2, -PI / 2 + TAU * maxf(0.01, charge_fraction), 48, Color("a4edff"), 4, true)
	if queued: draw_arc(center, radius, 0, TAU, 48, Color("ffdc78"), 3, true)
	if recharge_remaining > 0:
		var progress = 1.0 - clampf(recharge_remaining / maxf(0.001, recharge_total), 0, 1)
		draw_arc(center, radius, -PI / 2, -PI / 2 + TAU * maxf(0.001, progress), 48, Color("a4edff"), 4, true)
	if cooldown > 0:
		var points = PackedVector2Array([center])
		var angle = TAU * clampf(cooldown / cooldown_total, 0, 1)
		for i in range(33): points.append(center + Vector2.from_angle(-PI / 2 + angle * i / 32.0) * radius)
		draw_colored_polygon(points, Color(0.02, 0.06, 0.09, 0.65))
		var value = "%.1f" % cooldown
		var font = get_theme_default_font()
		draw_string(font, Vector2(center.x - font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x / 2, center.y + 8), value, HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
	elif recharge_remaining > 0 and unavailable:
		var value = "%.1f" % recharge_remaining
		var font = get_theme_default_font()
		draw_string(font, Vector2(center.x - font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x / 2, center.y + 8), value, HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
	if stock >= 0:
		draw_string(get_theme_default_font(), Vector2(size.x * 0.65, 23), str(stock), HORIZONTAL_ALIGNMENT_LEFT, -1, 22)

func _input(event: InputEvent) -> void:
	if disabled or not is_visible_in_tree():
		release()
		return
	if event is InputEventScreenTouch:
		if event.canceled:
			if finger != event.index: return
			release()
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
	return (get_global_transform_with_canvas().affine_inverse() * point).distance_to(size * 0.5) <= size.x * 0.5

func release() -> void:
	if finger == -1: return
	finger = -1
	button_pressed = false
	button_up.emit()
	queue_redraw()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		_application_focused = false
		release()
		_sync_ready_effect()
	elif what in [NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED]:
		_application_focused = true
		_sync_ready_effect()
