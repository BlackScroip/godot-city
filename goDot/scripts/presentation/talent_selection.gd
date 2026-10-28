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
var selection_effect: Control
var _selection_tween: Tween
var _submitted := false

const Palette = preload("res://scripts/presentation/choice_palette.gd")
const ROLE_NAVIGATION = preload("res://scripts/presentation/role_navigation.gd")
const SELECTED_SCALE := 1.08

func configure(page: DungeonMenuPage, rows: Array) -> void:
	host = page
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	back_button = ROLE_NAVIGATION.create_back_button()
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
	selection_effect = preload("res://scripts/presentation/talent_selection_effect.gd").new()
	add_child(selection_effect)
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
	var rare = Palette.rarity(int(row.target_level)) if row.has("target_level") else clampi(int(row.get("rarity", 3)), 1, 5)
	var loot_type = row.get("loot_type", "")
	var cursed = Palette.is_curse(loot_type)
	var panel = preload("res://scripts/presentation/talent_card.gd").new()
	panel.configure(rare, loot_type)
	var marked = _is_marked(row)
	panel.set_meta("talent_marked", marked)
	if marked:
		panel.tooltip_text = "已标记天赋"
	panel.focus_mode = Control.FOCUS_ALL
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.gui_input.connect(func(event):
		if (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed) or event.is_action_pressed("ui_accept"):
			_select(index)
			panel.accept_event())
	panel.focus_entered.connect(func(): _select(index))
	var slot = Control.new()
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards.add_child(slot)
	slot.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.resized.connect(func(): _refresh_selection_geometry.call_deferred())
	var stack = VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(stack)
	var center = CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	stack.add_child(center)
	var icon_frame = PanelContainer.new()
	icon_frame.mouse_filter = Control.MOUSE_FILTER_PASS
	var icon_style = StyleBoxTexture.new()
	icon_style.texture = Palette.texture(Palette.sprite_key("slotfg_rare_square", rare, loot_type))
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]: icon_style.set_texture_margin(side, 16)
	icon_style.set_content_margin_all(5)
	icon_frame.add_theme_stylebox_override("panel", icon_style)
	center.add_child(icon_frame)
	var icon = DungeonStyle.picture(str(row.get("icon", "")), Vector2(120, 120))
	icon_frame.add_child(icon)
	var mark = DungeonStyle.picture("AwakenSkillBg_1", Vector2.ZERO)
	mark.name = "TalentMark"
	mark.visible = marked
	icon.add_child(mark)
	mark.anchor_left = -0.05
	mark.anchor_top = -0.05
	mark.anchor_right = 0.45
	mark.anchor_bottom = 0.45
	var star = DungeonStyle.picture("白星标", Vector2.ZERO)
	star.modulate = Color(1, 0.9055, 0.5236)
	mark.add_child(star)
	star.anchor_left = -0.07
	star.anchor_top = -0.07
	star.anchor_right = 1.07
	star.anchor_bottom = 1.07
	var title = _label(str(row.get("title", "")), 30, Palette.color("curse_title_color" if cursed else "title"), true)
	title.add_theme_color_override("font_outline_color", Palette.outline("Text_Name"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(title)
	var tag = _label(str(row.get("grade", "")) + "  " + str(row.get("level_text", "")), 18, Palette.color("level"))
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
	var text_stack = VBoxContainer.new()
	text_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(text_stack)
	var description = _label(str(row.get("effect_description", row.get("description", ""))), 25, Palette.color("curse_desc_color" if cursed else "effect"), true)
	description.add_theme_color_override("font_outline_color", Palette.outline("Text_EffectDescription"))
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_stack.add_child(description)
	var level_description = _label(str(row.get("level_description", "")), 25, Palette.color("level_description"))
	level_description.visible = row.has("level_description")
	text_stack.add_child(level_description)
	var lower_line = Control.new()
	lower_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(lower_line)
	var choose = Button.new()
	choose.text = "选择"
	choose.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color", "font_disabled_color"]:
		choose.add_theme_color_override(state, Palette.color("choose"))
	choose.add_theme_color_override("font_outline_color", Palette.outline("Text_Select"))
	choose.add_theme_constant_override("outline_size", 2)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style = StyleBoxEmpty.new()
		style.set_content_margin_all(0)
		choose.add_theme_stylebox_override(state, style)
	for entry in row.get("buttons", []):
		choose.disabled = bool(entry.get("disabled", false))
		choose.pressed.connect(func():
			if _submitted or selected != index or choose.disabled: return
			_submitted = true
			for part in parts: part.choose.disabled = true
			command.emit(str(entry.action), entry.get("id", ""), entry.get("extra", "")))
	var footer = CenterContainer.new()
	footer.mouse_filter = Control.MOUSE_FILTER_PASS
	stack.add_child(footer)
	footer.add_child(choose)
	choose.hide()
	parts.append({"slot": slot, "panel": panel, "stack": stack, "icon": icon, "icon_frame": icon_frame, "tag": tag, "title": title, "description": description, "level_description": level_description, "scroll": scroll, "choose": choose, "footer": footer, "upper_line": upper_line, "lower_line": lower_line})

func _is_marked(row: Dictionary) -> bool:
	if row.has("marked"): return bool(row.marked)
	var systems = host.page_context.get("systems")
	return systems != null and systems.has_method("is_character_talent_marked") and systems.is_character_talent_marked(int(row.get("config_id", 0)))

func _label(value: String, font_size: int, color: Color, outlined := false) -> Label:
	var label = DungeonStyle.label(value, font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	label.add_theme_color_override("font_outline_color", Color("443d32"))
	label.add_theme_constant_override("outline_size", 4 if outlined else 0)
	return label

func _select(index: int) -> void:
	if index < 0 or index >= parts.size() or _submitted: return
	if selected == index: return
	selected = index
	if _selection_tween and _selection_tween.is_valid(): _selection_tween.kill()
	_selection_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for i in parts.size():
		var part: Dictionary = parts[i]
		part.panel.selected = i == index
		part.panel.pivot_offset = part.panel.size * 0.5
		part.slot.z_index = 1 if i == index else 0
		part.choose.visible = i == index
		_selection_tween.tween_property(part.panel, "scale", Vector2.ONE * (SELECTED_SCALE if i == index else 1.0), 0.16)
	selection_effect.set_active(true)
	_refresh_selection_geometry()
	_update_separators.call_deferred()

func _refresh_selection_geometry() -> void:
	for part in parts: part.panel.pivot_offset = part.panel.size * 0.5
	if selected < 0 or selected >= parts.size() or not is_instance_valid(selection_effect): return
	var part: Dictionary = parts[selected]
	var card_size: Vector2 = part.panel.size * SELECTED_SCALE
	var origin: Vector2 = cards.position + part.slot.position - (card_size - part.panel.size) * 0.5
	var sides := card_size.x * 0.14
	var height := card_size.y * 0.15
	selection_effect.position = origin - Vector2(sides, height)
	selection_effect.size = card_size + Vector2(sides * 2.0, height * 2.0)

func _adapt() -> void:
	if not is_inside_tree() or not is_instance_valid(host) or size.y < 1: return
	var scale_factor = clampf(size.y / 1080.0, 0.3, 1.5)
	var compact = size.y < 600
	host.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	host.stack.add_theme_constant_override("separation", 0)
	var pad = maxf(12, 28 * scale_factor)
	var tool_width = maxf(42, 96 * scale_factor)
	var tool_height = maxf(46, 124 * scale_factor)
	ROLE_NAVIGATION.place_back_button(back_button, ROLE_NAVIGATION.scale_factor(size))
	heading.position = Vector2(back_button.get_rect().end.x + 12, back_button.position.y)
	heading.size = Vector2(maxf(0, size.x - heading.position.x - tool_width * toolbar.get_child_count() - pad * 2), back_button.size.y)
	heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
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
		part.level_description.add_theme_font_size_override("font_size", maxi(14, int(27 * scale_factor)))
		part.description.add_theme_constant_override("outline_size", 3 if compact else 4)
		part.choose.custom_minimum_size.y = maxi(26, int(44 * scale_factor))
		part.footer.custom_minimum_size.y = part.choose.custom_minimum_size.y
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
	_refresh_selection_geometry.call_deferred()
	_update_separators.call_deferred()

func _update_separators() -> void:
	for part in parts:
		var inverse: Transform2D = part.panel.get_global_transform().affine_inverse()
		part.panel.dividers = PackedFloat32Array([(inverse * part.upper_line.get_global_transform().origin).y + part.upper_line.size.y * 0.5, (inverse * part.lower_line.get_global_transform().origin).y + part.lower_line.size.y * 0.5])
		part.panel.queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.13, 0.10, 0.08, 0.97))
	for index in 55:
		var point = Vector2(fposmod(index * 0.618034, 1.0) * size.x, fposmod(index * 0.381966 + 0.13, 1.0) * size.y)
		draw_circle(point, 0.65, Color(0.95, 0.82, 0.49, 0.28))
