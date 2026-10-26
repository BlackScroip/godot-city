extends Control

signal command(kind: String, id: Variant, extra: Variant)
var host: DungeonMenuPage
var cards: HBoxContainer
var parts: Array[Dictionary] = []
var selected := -1
var refresh_button: Button
var character_button: Button
var back_button: Button
var heading: Label
var toolbar: HBoxContainer

const PALETTES = {
	1: [Color("cdd1d6"), Color("f0f0ef"), Color("777e86"), Color("515a62")],
	2: [Color("abc99b"), Color("e6f0e7"), Color("729660"), Color("47662c")],
	3: [Color("93d1f2"), Color("e5f2f5"), Color("639fc0"), Color("236588")],
	4: [Color("c8afe0"), Color("f0eaf7"), Color("9a7aba"), Color("71518d")],
	5: [Color("e9cc89"), Color("faf2d9"), Color("b19550"), Color("8b6b2f")]
}

func configure(page: DungeonMenuPage, rows: Array) -> void:
	host = page
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	back_button = _tool_button("", "退出按钮", "返回")
	back_button.pressed.connect(func(): host.closed.emit())
	add_child(back_button)
	heading = _label(host.title_label.text, 40, Color.WHITE, true)
	add_child(heading)
	toolbar = HBoxContainer.new()
	toolbar.alignment = BoxContainer.ALIGNMENT_END
	add_child(toolbar)
	toolbar.minimum_size_changed.connect(_fit_toolbar)
	character_button = _tool_button("角色", "menu_character", "查看角色与已获得的道具")
	character_button.pressed.connect(func(): command.emit("page:inventory", 0, 0))
	toolbar.add_child(character_button)
	for row in rows:
		if row.get("presentation_role", "") != "refresh": continue
		for entry in row.get("buttons", []):
			refresh_button = _tool_button("刷新", "skill_refresh", str(entry.get("tooltip", "刷新候选")))
			refresh_button.disabled = bool(entry.get("disabled", false))
			refresh_button.pressed.connect(func(): command.emit(str(entry.action), entry.get("id", ""), entry.get("extra", "")))
			toolbar.add_child(refresh_button)
	cards = HBoxContainer.new()
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(cards)
	cards.minimum_size_changed.connect(_fit_cards)
	cards.resized.connect(func(): _update_separators.call_deferred())
	for row in rows:
		if row.get("presentation_role", "") != "refresh": _build_card(row)
	resized.connect(_adapt)
	_adapt.call_deferred()

func _tool_button(text: String, icon: String, hint: String) -> Button:
	var button = Button.new()
	button.text = text
	button.tooltip_text = hint
	button.icon = DungeonStyle.texture(icon)
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_color_override("font_outline_color", Color("241c15"))
	button.add_theme_constant_override("outline_size", 4)
	button.add_theme_color_override("font_disabled_color", Color("96958f"))
	button.add_theme_color_override("icon_disabled_color", Color("747570"))
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style = StyleBoxFlat.new()
		style.bg_color = Color(1, 0.91, 0.63, 0.08) if state in ["hover", "focus"] else Color.TRANSPARENT
		style.set_corner_radius_all(4)
		style.set_content_margin_all(2)
		button.add_theme_stylebox_override(state, style)
	return button

func _build_card(row: Dictionary) -> void:
	var index = parts.size()
	var palette: Array = PALETTES[clampi(int(row.get("rarity", 3)), 1, 5)]
	var panel = preload("res://scripts/presentation/talent_card.gd").new()
	panel.fill_top = palette[0]
	panel.fill_bottom = palette[1]
	panel.accent = palette[2]
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
	var icon_style = DungeonStyle.box(palette[3], Color("f0e4b3"), 2)
	icon_style.set_corner_radius_all(8)
	icon_style.shadow_color = Color(0.1, 0.14, 0.16, 0.35)
	icon_style.shadow_size = 2
	icon_style.set_content_margin_all(5)
	icon_frame.add_theme_stylebox_override("panel", icon_style)
	center.add_child(icon_frame)
	var icon = DungeonStyle.picture(str(row.get("icon", "")), Vector2(120, 120))
	icon_frame.add_child(icon)
	var title = _label(str(row.get("title", "")), 30, Color("ffda65"), true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(title)
	var tag = _label(str(row.get("grade", "")) + "  " + str(row.get("level_text", "")), 18, Color("47535a"))
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.visible = row.has("level_text")
	stack.add_child(tag)
	var upper_line = Control.new()
	upper_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(upper_line)
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(scroll)
	var description = _label(str(row.get("description", "")), 25, Color("fffdf4"), true)
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(description)
	var lower_line = Control.new()
	lower_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(lower_line)
	var choose = Button.new()
	choose.text = "选择"
	choose.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	choose.add_theme_color_override("font_color", Color("785018"))
	choose.add_theme_color_override("font_hover_color", Color("4d310a"))
	choose.add_theme_color_override("font_pressed_color", Color("4d310a"))
	choose.add_theme_color_override("font_disabled_color", Color("8a8b84"))
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style = DungeonStyle.box(Color(1, 0.94, 0.7, 0.45) if state in ["hover", "pressed", "focus"] else Color.TRANSPARENT)
		style.set_content_margin_all(0)
		choose.add_theme_stylebox_override(state, style)
	for entry in row.get("buttons", []):
		choose.disabled = bool(entry.get("disabled", false))
		choose.pressed.connect(func():
			_select(index)
			command.emit(str(entry.action), entry.get("id", ""), entry.get("extra", "")))
	stack.add_child(choose)
	parts.append({"panel": panel, "stack": stack, "icon": icon, "tag": tag, "title": title, "description": description, "scroll": scroll, "choose": choose, "upper_line": upper_line, "lower_line": lower_line})

func _label(value: String, font_size: int, color: Color, outlined := false) -> Label:
	var label = DungeonStyle.label(value, font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	label.add_theme_color_override("font_outline_color", Color("443d32"))
	label.add_theme_constant_override("outline_size", 4 if outlined else 0)
	return label

func _select(index: int) -> void:
	selected = index
	for i in parts.size(): parts[i].panel.selected = i == index

func _adapt() -> void:
	if not is_inside_tree() or not is_instance_valid(host) or size.y < 1: return
	var scale_factor = clampf(size.y / 1080.0, 0.3, 1.5)
	var compact = size.y < 600
	host.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	host.stack.add_theme_constant_override("separation", 0)
	var pad = maxf(12, 28 * scale_factor)
	var tool_width = maxf(42, 96 * scale_factor)
	var tool_height = maxf(46, 124 * scale_factor)
	back_button.position = Vector2(pad, 18 * scale_factor)
	back_button.size = Vector2(138 * scale_factor, tool_height)
	back_button.add_theme_constant_override("icon_max_width", int(134 * scale_factor))
	heading.position = Vector2(back_button.get_rect().end.x + 22 * scale_factor, 34 * scale_factor)
	heading.size = Vector2(maxf(0, size.x - heading.position.x - tool_width * toolbar.get_child_count() - pad * 2), tool_height * 0.6)
	heading.add_theme_font_size_override("font_size", maxi(18, int(44 * scale_factor)))
	toolbar.add_theme_constant_override("separation", int(20 * scale_factor))
	for button in toolbar.get_children():
		button.custom_minimum_size = Vector2(tool_width, tool_height)
		button.add_theme_font_size_override("font_size", maxi(14, int(38 * scale_factor)))
		button.add_theme_constant_override("icon_max_width", maxi(26, int(76 * scale_factor)))
	cards.add_theme_constant_override("separation", maxi(12, int(54 * scale_factor)))
	for part in parts:
		part.panel.fit(compact, scale_factor)
		part.stack.add_theme_constant_override("separation", maxi(3, int(14 * scale_factor)))
		var icon_size = maxi(36, int(138 * scale_factor))
		part.icon.custom_minimum_size = Vector2(icon_size, icon_size)
		part.title.add_theme_font_size_override("font_size", maxi(15, int(31 * scale_factor)))
		part.tag.add_theme_font_size_override("font_size", maxi(11, int(20 * scale_factor)))
		part.description.add_theme_font_size_override("font_size", maxi(14, int(27 * scale_factor)))
		part.description.add_theme_constant_override("outline_size", 3 if compact else 4)
		part.choose.custom_minimum_size.y = maxi(26, int(44 * scale_factor))
		part.choose.add_theme_font_size_override("font_size", maxi(16, int(29 * scale_factor)))
		part.upper_line.custom_minimum_size.y = maxi(5, int(16 * scale_factor))
		part.lower_line.custom_minimum_size.y = maxi(5, int(16 * scale_factor))
	_fit_toolbar.call_deferred()
	_fit_cards.call_deferred()
	queue_redraw()

func _fit_toolbar() -> void:
	var scale_factor = clampf(size.y / 1080.0, 0.3, 1.5)
	toolbar.size = toolbar.get_combined_minimum_size()
	toolbar.position = Vector2(size.x - toolbar.size.x - maxf(12, 28 * scale_factor), 20 * scale_factor)

func _fit_cards() -> void:
	if not is_instance_valid(cards): return
	var scale_factor = clampf(size.y / 1080.0, 0.3, 1.5)
	var count = maxi(1, parts.size())
	var gap = cards.get_theme_constant("separation")
	var card_width = minf(420 * scale_factor, (size.x - maxf(12, 28 * scale_factor) * 2 - gap * (count - 1)) / count)
	cards.size = Vector2(card_width * count + gap * (count - 1), size.y * 0.75)
	cards.position = Vector2((size.x - cards.size.x) * 0.5, size.y * 0.17)
	_update_separators.call_deferred()

func _update_separators() -> void:
	for part in parts:
		part.panel.dividers = PackedFloat32Array([part.upper_line.global_position.y - part.panel.global_position.y + part.upper_line.size.y * 0.5, part.lower_line.global_position.y - part.panel.global_position.y + part.lower_line.size.y * 0.5])
		part.panel.queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.13, 0.10, 0.08, 0.97))
	for index in 55:
		var point = Vector2(fposmod(index * 0.618034, 1.0) * size.x, fposmod(index * 0.381966 + 0.13, 1.0) * size.y)
		draw_circle(point, 0.65, Color(0.95, 0.82, 0.49, 0.28))
