extends Control

signal command(kind: String, id: Variant, extra: Variant)

var dialog: PanelContainer
var content: VBoxContainer
var heading: Label
var introduction: Label
var warning: Label
var reward_scroll: ScrollContainer
var reward_list: VBoxContainer
var return_button: Button
var continue_button: Button
var _reward_rows: Array[HBoxContainer] = []
var _sent := false

func configure(_host: DungeonMenuPage, rows: Array, _context: Dictionary) -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	dialog = PanelContainer.new()
	var frame = DungeonStyle.box(Color("363e4b"), DungeonStyle.GOLD, 1)
	frame.set_corner_radius_all(8)
	frame.shadow_color = Color(0, 0, 0, 0.35)
	frame.shadow_size = 12
	dialog.add_theme_stylebox_override("panel", frame)
	add_child(dialog)
	content = VBoxContainer.new()
	dialog.add_child(content)
	heading = _label("奖励尚未领取", 32, Color("fff5d9"))
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(heading)
	var divider = DungeonStyle.picture("gold_line_bottom", Vector2(0, 2))
	divider.stretch_mode = TextureRect.STRETCH_SCALE
	divider.modulate = Color(1, 1, 1, 0.65)
	content.add_child(divider)
	introduction = _label("本节点还有以下奖励未领取", 22, Color("e6e8ec"))
	introduction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(introduction)
	reward_scroll = ScrollContainer.new()
	reward_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	reward_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(reward_scroll)
	reward_list = VBoxContainer.new()
	reward_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reward_list.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	reward_scroll.add_child(reward_list)
	for row in rows:
		var line = HBoxContainer.new()
		line.add_child(DungeonStyle.picture(str(row.get("icon", "interaction_quest")), Vector2(40, 40)))
		var name_label = _label(str(row.get("title", "")), 23, DungeonStyle.TEXT)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(name_label)
		var count = _label("× %d" % int(row.get("count", 1)), 24, Color("ffe094"))
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count.custom_minimum_size.x = 70
		line.add_child(count)
		reward_list.add_child(line)
		_reward_rows.append(line)
	warning = _label("离开后将无法返回领取，是否继续？", 19, Color("c3c8d0"))
	warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(warning)
	var actions = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 28)
	content.add_child(actions)
	return_button = _button("返回领取", false)
	return_button.pressed.connect(func(): _send("close_page"))
	actions.add_child(return_button)
	continue_button = _button("继续前进", true)
	continue_button.pressed.connect(func(): _send("leave_unclaimed"))
	actions.add_child(continue_button)
	for button in [return_button, continue_button]:
		var other = continue_button if button == return_button else return_button
		button.focus_neighbor_left = button.get_path_to(other)
		button.focus_neighbor_right = button.get_path_to(other)
		button.focus_next = button.get_path_to(other)
		button.focus_previous = button.get_path_to(other)
	resized.connect(_layout)
	_layout.call_deferred()
	_focus_return.call_deferred()

func _label(text: String, font_size: int, color: Color) -> Label:
	var label = DungeonStyle.label(text, font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _button(text: String, primary: bool) -> Button:
	var button = Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "disabled"]:
		var fill = Color("ffdc77") if primary else Color("c4c8ce")
		if state == "hover": fill = fill.lightened(0.12)
		if state == "pressed": fill = fill.darkened(0.14)
		if state == "disabled": fill = fill.darkened(0.3)
		var style = DungeonStyle.box(fill, Color("f7e4a6") if primary else Color("e2e4e8"), 1)
		style.set_corner_radius_all(8)
		style.set_content_margin_all(6)
		button.add_theme_stylebox_override(state, style)
	var focus = DungeonStyle.box(Color.TRANSPARENT, Color("fff5d9"), 2)
	focus.set_corner_radius_all(8)
	focus.set_expand_margin_all(4)
	button.add_theme_stylebox_override("focus", focus)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		button.add_theme_color_override(state, Color("303641"))
	return button

func _layout() -> void:
	if not is_instance_valid(dialog) or size.x <= 0 or size.y <= 0: return
	var compact = size.y < 600 or size.x < 640
	var style = dialog.get_theme_stylebox("panel").duplicate()
	style.set_content_margin_all(20 if compact else 36)
	dialog.add_theme_stylebox_override("panel", style)
	content.add_theme_constant_override("separation", 10 if compact else 20)
	dialog.size = Vector2(minf(620 if compact else 900, size.x - 32), minf((230 + mini(_reward_rows.size(), 3) * 46) if compact else (330 + mini(_reward_rows.size(), 3) * 60), size.y - 32))
	dialog.position = ((size - dialog.size) * 0.5).floor()
	heading.add_theme_font_size_override("font_size", 24 if compact else 32)
	introduction.add_theme_font_size_override("font_size", 16 if compact else 22)
	warning.add_theme_font_size_override("font_size", 14 if compact else 19)
	reward_list.add_theme_constant_override("separation", 6 if compact else 12)
	for line in _reward_rows:
		line.custom_minimum_size.y = 38 if compact else 48
		line.add_theme_constant_override("separation", 12 if compact else 18)
		line.get_child(0).custom_minimum_size = Vector2.ONE * (30 if compact else 40)
		line.get_child(1).add_theme_font_size_override("font_size", 18 if compact else 23)
		line.get_child(2).add_theme_font_size_override("font_size", 18 if compact else 24)
	for button in [return_button, continue_button]:
		button.custom_minimum_size.y = 44 if compact else 58
		button.add_theme_font_size_override("font_size", 18 if compact else 24)

func _send(action: String) -> void:
	if _sent: return
	_sent = true
	return_button.disabled = true
	continue_button.disabled = true
	command.emit(action, 0, 0)

func _focus_return() -> void:
	if is_instance_valid(return_button) and return_button.is_visible_in_tree(): return_button.grab_focus()
