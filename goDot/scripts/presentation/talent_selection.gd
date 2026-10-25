extends VBoxContainer

signal command(kind: String, id: Variant, extra: Variant)
var host: DungeonMenuPage
var cards: HBoxContainer
var parts: Array[Dictionary] = []
var selected := 0
var refresh_button: Button

func configure(page: DungeonMenuPage, rows: Array) -> void:
	host = page
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var toolbar = HBoxContainer.new()
	toolbar.alignment = BoxContainer.ALIGNMENT_END
	add_child(toolbar)
	for row in rows:
		if row.get("presentation_role", "") != "refresh": continue
		for entry in row.get("buttons", []):
			refresh_button = Button.new()
			refresh_button.text = "刷新"
			refresh_button.icon = DungeonStyle.texture("skill_refresh")
			refresh_button.expand_icon = true
			refresh_button.add_theme_constant_override("icon_max_width", 26)
			refresh_button.disabled = bool(entry.get("disabled", false))
			refresh_button.pressed.connect(func(): command.emit(str(entry.action), entry.get("id", ""), entry.get("extra", "")))
			toolbar.add_child(refresh_button)
	cards = HBoxContainer.new()
	cards.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(cards)
	for row in rows:
		if row.get("presentation_role", "") == "refresh": continue
		_build_card(row)
	resized.connect(_adapt)
	_select(0)
	_adapt.call_deferred()

func _build_card(row: Dictionary) -> void:
	var index = parts.size()
	var panel = preload("res://scripts/presentation/talent_card.gd").new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.focus_mode = Control.FOCUS_ALL
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.gui_input.connect(func(event):
		if (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed) or event.is_action_pressed("ui_accept"):
			_select(index)
			panel.accept_event())
	panel.focus_entered.connect(func(): _select(index))
	cards.add_child(panel)
	var stack = VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(stack)
	var center = CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	stack.add_child(center)
	var icon_frame = PanelContainer.new()
	icon_frame.mouse_filter = Control.MOUSE_FILTER_PASS
	var icon_style = DungeonStyle.box(Color("225d7b"), Color("82bbd2"), 2)
	icon_style.set_content_margin_all(6)
	icon_frame.add_theme_stylebox_override("panel", icon_style)
	center.add_child(icon_frame)
	var icon = DungeonStyle.picture(str(row.get("icon", "")), Vector2(92, 92))
	icon_frame.add_child(icon)
	var tag = _label(str(row.get("grade", "天赋")) + "  " + str(row.get("level_text", "")), 16, Color("42566a"))
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(tag)
	var title = _label(str(row.get("title", "")), 25, Color("845514"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(title)
	stack.add_child(_separator())
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(scroll)
	var description = _label(str(row.get("description", "")), 21, Color("213d4e"))
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(description)
	stack.add_child(_separator())
	var choose = Button.new()
	choose.text = "选择"
	choose.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	choose.add_theme_color_override("font_color", Color("80500a"))
	choose.add_theme_color_override("font_hover_color", Color("623b00"))
	for state in ["normal", "hover", "pressed", "focus"]:
		var style = DungeonStyle.box(Color(0.95, 0.88, 0.64, 0.5) if state == "hover" else Color.TRANSPARENT, Color("d1b967") if state == "focus" else Color.TRANSPARENT, 2)
		style.set_content_margin_all(4)
		choose.add_theme_stylebox_override(state, style)
	for entry in row.get("buttons", []):
		choose.disabled = bool(entry.get("disabled", false))
		choose.pressed.connect(func():
			_select(index)
			command.emit(str(entry.action), entry.get("id", ""), entry.get("extra", "")))
	stack.add_child(choose)
	parts.append({"panel": panel, "stack": stack, "icon": icon, "tag": tag, "title": title, "description": description, "scroll": scroll, "choose": choose})

func _label(value: String, font_size: int, color: Color) -> Label:
	var label = DungeonStyle.label(value, font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	return label

func _separator() -> TextureRect:
	var line = DungeonStyle.picture("gold_separator", Vector2(0, 8))
	line.stretch_mode = TextureRect.STRETCH_SCALE
	line.modulate = Color(0.48, 0.66, 0.76, 0.6)
	return line

func _select(index: int) -> void:
	selected = index
	for i in parts.size():
		parts[i].panel.selected = i == index
		parts[i].choose.modulate.a = 1.0 if i == index else 0.55

func _adapt() -> void:
	if not is_inside_tree() or not is_instance_valid(host): return
	var compact = get_viewport_rect().size.y < 600
	var style = DungeonStyle.box(Color("291f1e"))
	style.set_content_margin_all(12 if compact else 28)
	host.add_theme_stylebox_override("panel", style)
	host.stack.add_theme_constant_override("separation", 4 if compact else 8)
	host.title_label.add_theme_font_size_override("font_size", 22 if compact else 30)
	add_theme_constant_override("separation", 4 if compact else 10)
	cards.add_theme_constant_override("separation", 12 if compact else 28)
	cards.custom_minimum_size.x = minf(get_viewport_rect().size.x - (24 if compact else 56), 1240)
	if is_instance_valid(refresh_button):
		refresh_button.custom_minimum_size = Vector2(90, 32 if compact else 40)
		refresh_button.add_theme_font_size_override("font_size", 16 if compact else 20)
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			var button_style = refresh_button.get_theme_stylebox(state).duplicate()
			button_style.set_content_margin_all(4 if compact else 8)
			refresh_button.add_theme_stylebox_override(state, button_style)
	for part in parts:
		part.panel.fit(compact)
		part.stack.add_theme_constant_override("separation", 4 if compact else 10)
		part.icon.custom_minimum_size = Vector2(32, 32) if compact else Vector2(92, 92)
		part.title.add_theme_font_size_override("font_size", 19 if compact else 25)
		part.tag.add_theme_font_size_override("font_size", 13 if compact else 16)
		part.description.add_theme_font_size_override("font_size", 16 if compact else 21)
		part.choose.custom_minimum_size.y = 32 if compact else 44
		part.choose.add_theme_font_size_override("font_size", 22 if compact else 28)
	host.size = get_viewport_rect().size
