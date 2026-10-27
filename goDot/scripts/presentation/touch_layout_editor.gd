extends Control

signal saved(layout: Dictionary)
signal canceled

const CONTROL_ORDER := ["attack", "dodge", "skill", "burst", "auto", "joystick"]
const CAPTIONS := {"attack": "攻击", "dodge": "闪避", "skill": "战技", "burst": "爆发", "auto": "自动攻击", "joystick": "摇杆"}
const BASE_SIZES := {"attack": 192.0, "dodge": 120.0, "skill": 128.0, "burst": 112.0, "auto": 72.0, "joystick": 128.0}
const ART := {"attack": "skill_attack", "dodge": "skill_dodge", "skill": "skill_sword_whirl", "burst": "skill_sword_slash", "auto": "skill_swap", "joystick": "joystick_ring"}
static var settings_path := "user://touch_controls.cfg"
var stock: Dictionary = {}
var draft: Dictionary = {}
var selected := "attack"
var toolbar: Control
var selected_label: OptionButton
var size_slider: HSlider
var size_label: Label
var status: Label
var save_button: Button
var cancel_button: Button
var reset_button: Button
var _finger := -1
var _drag_offset := Vector2.ZERO
var _syncing := false

static func read_layout() -> Dictionary:
	var config := ConfigFile.new()
	if config.load(settings_path) != OK: return {}
	return normalize(config.get_value("touch", "controls", {}))

static func normalize(layout: Variant) -> Dictionary:
	var result := {}
	if not layout is Dictionary: return result
	for key in CONTROL_ORDER:
		var value: Variant = layout.get(key)
		if not value is Dictionary: continue
		var center: Variant = value.get("center")
		var factor: Variant = value.get("scale", 1.0)
		if not center is Vector2 or not center.is_finite(): continue
		if not (factor is int or factor is float) or not is_finite(float(factor)): continue
		result[key] = {"center": center.clamp(Vector2.ZERO, Vector2.ONE), "scale": clampf(float(factor), 0.65, 1.6)}
	return result

static func store_layout(layout: Dictionary) -> bool:
	var config := ConfigFile.new()
	config.set_value("touch", "version", 1)
	config.set_value("touch", "controls", normalize(layout))
	var temporary := settings_path + ".tmp"
	if config.save(temporary) != OK: return false
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(settings_path)) != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		return false
	return true

func configure(default_layout: Dictionary, current_layout: Dictionary) -> void:
	stock = normalize(default_layout)
	draft = stock.duplicate(true)
	draft.merge(normalize(current_layout), true)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = DungeonStyle.theme()
	toolbar = Control.new()
	add_child(toolbar)
	selected_label = OptionButton.new()
	for key in CONTROL_ORDER: selected_label.add_item(CAPTIONS[key])
	selected_label.item_selected.connect(func(index): _select(CONTROL_ORDER[index]))
	selected_label.tooltip_text = "操作按钮"
	toolbar.add_child(selected_label)
	size_slider = HSlider.new()
	size_slider.min_value = 65
	size_slider.max_value = 160
	size_slider.step = 5
	size_slider.tooltip_text = "按钮大小"
	size_slider.value_changed.connect(_change_size)
	toolbar.add_child(size_slider)
	size_label = DungeonStyle.label("100%", 19)
	size_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toolbar.add_child(size_label)
	reset_button = _button("重置", reset_draft)
	cancel_button = _button("取消", func(): canceled.emit())
	save_button = _button("保存", func(): saved.emit(draft.duplicate(true)))
	status = DungeonStyle.label("", 17)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.add_theme_color_override("font_color", Color("ffd77c"))
	add_child(status)
	resized.connect(_layout)
	_layout()
	_select(selected)

func _button(caption: String, callback: Callable) -> Button:
	var key := Button.new()
	key.text = caption
	key.custom_minimum_size = Vector2(80, 44)
	key.pressed.connect(callback)
	toolbar.add_child(key)
	return key

func _layout() -> void:
	if not is_instance_valid(toolbar): return
	var compact := size.x < 760
	var inset := 12.0
	toolbar.position = Vector2(inset, inset)
	toolbar.size = Vector2(size.x - inset * 2, 100 if compact else 56)
	selected_label.position = Vector2(8, 5)
	selected_label.size = Vector2(112, 40)
	var button_width := 72.0 if compact else 88.0
	var right := toolbar.size.x - (button_width + 8) * 3
	for index in 3:
		var key: Button = [reset_button, cancel_button, save_button][index]
		key.position = Vector2(right + index * (button_width + 8), 2)
		key.size = Vector2(button_width, 44)
	size_slider.position = Vector2(8, 62) if compact else Vector2(130, 10)
	size_slider.size = Vector2(minf(260, toolbar.size.x - 90), 28) if compact else Vector2(maxf(90, right - 218), 28)
	size_label.position = size_slider.position + Vector2(size_slider.size.x + 12, 0)
	size_label.size = Vector2(64, 30)
	status.position = Vector2(inset + 8, toolbar.position.y + toolbar.size.y + 6)
	status.size = Vector2(size.x - inset * 2 - 16, 28)
	_finger = -1
	for key in draft: _clamp_control(key)
	queue_redraw()

func _scale_factor() -> float:
	return minf(1.0, minf(size.x / 1280.0, size.y / 720.0))

func _diameter(key: String) -> float:
	return maxf(48, float(BASE_SIZES[key]) * _scale_factor() * float(draft[key].scale))

func _center(key: String) -> Vector2:
	return Vector2(draft[key].center) * size

func _clamp_control(key: String) -> void:
	if not draft.has(key) or size.x <= 0 or size.y <= 0: return
	var radius := _diameter(key) * 0.5 + 8
	var minimum := Vector2(radius, maxf(radius, toolbar.position.y + toolbar.size.y + 40 + radius))
	var maximum := (size - Vector2.ONE * radius).max(minimum)
	draft[key].center = _center(key).clamp(minimum, maximum) / size

func _select(key: String) -> void:
	selected = key
	_syncing = true
	selected_label.select(CONTROL_ORDER.find(key))
	size_slider.value = float(draft.get(key, {}).get("scale", 1.0)) * 100
	size_label.text = "%d%%" % size_slider.value
	_syncing = false
	queue_redraw()

func _change_size(value: float) -> void:
	if _syncing or not draft.has(selected): return
	draft[selected].scale = value / 100.0
	_clamp_control(selected)
	size_label.text = "%d%%" % value
	status.text = ""
	queue_redraw()

func reset_draft() -> void:
	draft = stock.duplicate(true)
	for key in draft: _clamp_control(key)
	_select(selected)
	status.text = ""

func show_save_error() -> void:
	status.text = "保存失败，请重试"

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.015, 0.03, 0.025, 0.5))
	if is_instance_valid(toolbar):
		draw_style_box(DungeonStyle.box(Color(0.13, 0.17, 0.17, 0.94), Color("bbaa76"), 1), Rect2(toolbar.position, toolbar.size))
	for key in CONTROL_ORDER:
		if not draft.has(key): continue
		var center := _center(key)
		var diameter := _diameter(key)
		var bounds := Rect2(center - Vector2.ONE * diameter * 0.5, Vector2.ONE * diameter)
		var ring := DungeonStyle.texture("skill_ring" if key == "attack" else "skill_circle_small" if key == "auto" else "skill_circle")
		if key != "joystick" and ring: draw_texture_rect(ring, bounds, false)
		var art := DungeonStyle.texture(ART[key])
		if art: draw_texture_rect(art, bounds if key == "joystick" else bounds.grow(-diameter * 0.12), false)
		if key == "joystick":
			draw_arc(center, diameter * 0.5, 0, TAU, 64, Color(0.85, 0.92, 0.88, 0.6), 1.5, true)
			var thumb := DungeonStyle.texture("joystick_thumb")
			if thumb: draw_texture_rect(thumb, Rect2(center - Vector2.ONE * diameter * 0.195, Vector2.ONE * diameter * 0.39), false)
		if key == selected: draw_arc(center, diameter * 0.5 + 4, 0, TAU, 64, Color("ffe29a"), 3, true)

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree(): return
	var point := Vector2.ZERO
	var pointer := -1
	var pressed := false
	var released := false
	var moved := false
	if event is InputEventScreenTouch:
		point = event.position
		pointer = event.index
		pressed = event.pressed and not event.canceled
		released = not event.pressed or event.canceled
	elif event is InputEventScreenDrag:
		point = event.position
		pointer = event.index
		moved = true
	elif event is InputEventMouseButton and event.device != -1 and event.button_index == MOUSE_BUTTON_LEFT:
		point = event.position
		pointer = -2
		pressed = event.pressed
		released = not event.pressed
	elif event is InputEventMouseMotion and event.device != -1:
		point = event.position
		pointer = -2
		moved = true
	else: return
	point = get_global_transform_with_canvas().affine_inverse() * point
	if pressed and _finger == -1:
		if point.y < toolbar.position.y + toolbar.size.y + 36: return
		for key in CONTROL_ORDER:
			if draft.has(key) and point.distance_to(_center(key)) <= _diameter(key) * 0.5 + 8:
				_select(key)
				_finger = pointer
				_drag_offset = _center(key) - point
				break
	elif moved and _finger == pointer:
		draft[selected].center = (point + _drag_offset) / size
		_clamp_control(selected)
		status.text = ""
		queue_redraw()
	elif released and _finger == pointer:
		_finger = -1
	else: return
	get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]: _finger = -1
