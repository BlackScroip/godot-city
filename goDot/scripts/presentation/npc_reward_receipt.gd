extends Control

signal closed

var heading: Label
var close_hint: Label
var slots: Array[Control] = []
var icons: Array[TextureRect] = []
var counts: Array[Label] = []
var _hint_icon: TextureRect
var _opened_at := 0
var _closed := false
var _pressed := false
var _press_position := Vector2.ZERO

func configure(items: Array) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_opened_at = Time.get_ticks_msec()
	var mask := ColorRect.new()
	mask.color = Color(0.08490568, 0.06238822, 0.02603240, 0.78431374)
	mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(mask)
	mask.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	heading = _label("获得物品", Color(0.8784, 0.7346, 0.3255))
	add_child(heading)
	for item in items:
		var slot := Control.new()
		slot.mouse_filter = Control.MOUSE_FILTER_STOP
		slot.tooltip_text = str(item.get("name", ""))
		add_child(slot)
		var frame := DungeonStyle.picture("res://assets/ui/dialogue/9dae02f4b49b75d9.png", Vector2.ZERO)
		slot.add_child(frame)
		frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var icon := DungeonStyle.picture(str(item.get("icon", "")), Vector2.ZERO)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		slot.add_child(icon)
		var count := _label(str(item.get("count", 0)), Color.WHITE)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		slot.add_child(count)
		slots.append(slot)
		icons.append(icon)
		counts.append(count)
	close_hint = _label("点击空白位置关闭", Color.WHITE)
	add_child(close_hint)
	_hint_icon = DungeonStyle.picture("res://assets/ui/dialogue/f748a084137297a6.png", Vector2.ZERO)
	_hint_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(_hint_icon)
	resized.connect(_layout)
	_layout.call_deferred()

func _label(value: String, color: Color) -> Label:
	var label := DungeonStyle.label(value, 30)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 2)
	return label

func _layout() -> void:
	if not is_instance_valid(heading) or size.y <= 0: return
	var unit := size.y / 1080.0
	var container_top := size.y * 0.5 - (56 + 480.753 * 0.5) * unit
	heading.position = Vector2(0, container_top + 25 * unit)
	heading.size = Vector2(size.x, 100 * unit)
	heading.add_theme_font_size_override("font_size", maxi(24, roundi(65 * unit)))
	var cell := 144 * unit
	var spacing := 50 * unit
	var columns := maxi(1, floori((size.x - 80 * unit + spacing) / (cell + spacing)))
	var row_count := ceili(float(slots.size()) / columns)
	var center_y := size.y * 0.5 + 32.821 * unit
	for index in slots.size():
		var row := index / columns
		var row_size := mini(columns, slots.size() - row * columns)
		var width := row_size * cell + maxi(0, row_size - 1) * spacing
		slots[index].position = Vector2((size.x - width) * 0.5 + (index % columns) * (cell + spacing), center_y - (row_count * cell + maxi(0, row_count - 1) * spacing) * 0.5 + row * (cell + spacing))
		slots[index].size = Vector2(cell, cell)
		icons[index].position = Vector2.ONE * 10 * unit
		icons[index].size = Vector2.ONE * 124 * unit
		counts[index].position = Vector2(0, 97 * unit)
		counts[index].size = Vector2(140, 47) * unit
		counts[index].add_theme_font_size_override("font_size", maxi(14, roundi(30 * unit)))
	close_hint.add_theme_font_size_override("font_size", maxi(13, roundi(27 * unit)))
	close_hint.size = Vector2(maxf(200 * unit, close_hint.get_minimum_size().x), maxf(30, 52.74 * unit))
	close_hint.position = Vector2((size.x - close_hint.size.x) * 0.5 + 5 * unit, size.y - 48 * unit - close_hint.size.y * 0.5)
	_hint_icon.size = Vector2.ONE * 26 * unit
	_hint_icon.position = Vector2(close_hint.position.x - 36 * unit, close_hint.position.y + (close_hint.size.y - _hint_icon.size.y) * 0.5)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_pointer(event.position, event.pressed)
	elif event is InputEventScreenTouch:
		_handle_pointer(event.position, event.pressed)

func _handle_pointer(point: Vector2, down: bool) -> void:
	if down:
		_pressed = Time.get_ticks_msec() - _opened_at >= 300
		_press_position = point
	elif _pressed:
		_pressed = false
		if _closed or point.distance_to(_press_position) >= 12: return
		for slot in slots:
			if slot.get_rect().has_point(point): return
		_closed = true
		closed.emit()
