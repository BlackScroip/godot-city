class_name DungeonCharacterPage
extends Control

signal command(kind: String, id: Variant, extra: Variant)
signal closed
signal back_requested

const PAPER := Color("f5edda")
const MUTED := Color("cbbca7")
const GOLD := Color("f0d78f")
const INK := Color("38252b")

var owner_page: DungeonMenuPage
var rows: Array = []
var context: Dictionary = {}
var selected := 0
var use_model := false
var active_tab := "details"
var showcase: VBoxContainer
var detail: VBoxContainer
var category_tabs: VBoxContainer
var selections: Array[Button] = []
var resource_bar: HBoxContainer
var navigation: Array[Button] = []
var detail_scroll: ScrollContainer
var roster_scroll: ScrollContainer
var roster: HBoxContainer
var title_label: Label
var name_label: Label
var level_label: Label
var biography: Label
var attributes_button: Button
var style_button: Button
var details_button: Button
var model_button: Button
var awakening_button: Button
var talent_button: Button
var action_bar: HBoxContainer
var art_commands: HBoxContainer
var content: HBoxContainer
var right_column: VBoxContainer
var identity: HBoxContainer
var portrait: TextureRect
var margin: MarginContainer
var page_stack: VBoxContainer
var heading: HBoxContainer
var _attribute_overlay: Control
var _catalog: DungeonCatalog
var _combat_characters: Array = []
var _compact := false

func configure(host: DungeonMenuPage, data: Array, page_context: Dictionary = {}) -> void:
	owner_page = host
	rows = data
	context = page_context
	_catalog = context.get("catalog") as DungeonCatalog
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	theme = DungeonStyle.theme()
	clip_contents = true
	if FileAccess.file_exists("res://assets/data/combat.json"):
		var recovered = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/combat.json"))
		if recovered is Dictionary: _combat_characters = recovered.get("characters", [])
	var background = DungeonStyle.picture("res://assets/art_generated/showcase-v1.png", Vector2.ZERO)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.modulate = Color(0.78, 0.7, 0.79)
	add_child(background)
	var veil = ColorRect.new()
	veil.color = Color(0.13, 0.07, 0.1, 0.3)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(veil)
	margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(margin)
	page_stack = VBoxContainer.new()
	page_stack.add_theme_constant_override("separation", 12)
	margin.add_child(page_stack)
	_build_heading()
	_build_content()
	var requested = int(context.get("selected_character", context.get("selected_id", 0)))
	if requested <= 0: requested = int(context.get("character_id", 0))
	for index in rows.size():
		if (requested > 0 and int(rows[index].get("config_id", 0)) == requested) or (requested <= 0 and rows[index].get("active_character", false)):
			selected = index
	resized.connect(_adapt)
	if not rows.is_empty(): _select_showcase(selected)
	else: detail.add_child(_label("暂无可用角色", 22))
	_adapt.call_deferred()

func _build_heading() -> void:
	heading = HBoxContainer.new()
	heading.add_theme_constant_override("separation", 14)
	page_stack.add_child(heading)
	var back = _icon_button("退出按钮", "返回", Vector2(70, 56))
	back.pressed.connect(func(): back_requested.emit())
	heading.add_child(back)
	title_label = _label("角色详情", 31)
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title_label)
	resource_bar = HBoxContainer.new()
	resource_bar.add_theme_constant_override("separation", 16)
	heading.add_child(resource_bar)
	for resource in context.get("resources", []):
		var line = HBoxContainer.new()
		line.custom_minimum_size = Vector2(126, 38)
		line.add_theme_constant_override("separation", 7)
		resource_bar.add_child(line)
		line.add_child(DungeonStyle.picture(str(resource[0]), Vector2(34, 34)))
		var value = _label(str(resource[1]), 21)
		value.autowrap_mode = TextServer.AUTOWRAP_OFF
		value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(value)
	var close = _icon_button("X", "关闭角色详情", Vector2(40, 40))
	close.pressed.connect(func(): closed.emit())
	heading.add_child(close)

func _build_content() -> void:
	content = HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 30)
	page_stack.add_child(content)
	category_tabs = VBoxContainer.new()
	category_tabs.add_theme_constant_override("separation", 4)
	content.add_child(category_tabs)
	for entry in [["角色", "characters", "menu_character"], ["武器", "weapons", "interaction_weapon"], ["背包", "inventory", "sprite_conversation_warehouse"], ["仓库", "storage", "sprite_conversation_warehouse1"]]:
		var key = Button.new()
		key.text = entry[0]
		key.icon = DungeonStyle.texture(entry[2])
		key.expand_icon = true
		key.add_theme_constant_override("icon_max_width", 34)
		key.add_theme_constant_override("h_separation", 18)
		key.custom_minimum_size = Vector2(172, 78)
		key.add_theme_font_size_override("font_size", 25)
		key.alignment = HORIZONTAL_ALIGNMENT_LEFT
		key.add_theme_color_override("font_color", GOLD if entry[1] == "characters" else Color("d6c9b9"))
		key.add_theme_stylebox_override("normal", _flat(Color(0.83, 0.6, 0.23, 0.24) if entry[1] == "characters" else Color(0.2, 0.1, 0.12, 0.12), Color(0.85, 0.65, 0.32, 0.4), 0))
		key.pressed.connect(func():
			if entry[1] == "characters": return
			command.emit("page:" + str(entry[1]), _character_id() if entry[1] == "weapons" else 0, 0))
		category_tabs.add_child(key)
		navigation.append(key)
	var center = VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 8)
	content.add_child(center)
	showcase = VBoxContainer.new()
	showcase.name = "CharacterArtwork"
	showcase.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	showcase.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(showcase)
	art_commands = HBoxContainer.new()
	art_commands.add_theme_constant_override("separation", 12)
	center.add_child(art_commands)
	model_button = _paper_button("3D", "查看角色模型")
	model_button.custom_minimum_size.x = 58
	model_button.pressed.connect(func():
		use_model = not use_model
		context["use_model"] = use_model
		if is_instance_valid(owner_page): owner_page.page_context["use_model"] = use_model
		_select_showcase(selected))
	art_commands.add_child(model_button)
	var art_spacer = Control.new()
	art_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	art_commands.add_child(art_spacer)
	attributes_button = _paper_button("属性详情", "查看完整属性")
	attributes_button.icon = DungeonStyle.texture("sprite_conversation_archives")
	attributes_button.expand_icon = true
	attributes_button.add_theme_constant_override("icon_max_width", 25)
	attributes_button.pressed.connect(_show_attributes)
	art_commands.add_child(attributes_button)
	roster_scroll = ScrollContainer.new()
	roster_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	roster_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	center.add_child(roster_scroll)
	roster = HBoxContainer.new()
	roster.add_theme_constant_override("separation", 8)
	roster_scroll.add_child(roster)
	for index in rows.size():
		var key = Button.new()
		key.custom_minimum_size = Vector2(59, 59)
		key.icon = DungeonStyle.texture(str(rows[index].get("icon", "menu_character")))
		key.expand_icon = true
		key.add_theme_constant_override("icon_max_width", 48)
		key.tooltip_text = str(rows[index].get("title", ""))
		key.pressed.connect(func(): _select_showcase(index))
		roster.add_child(key)
		selections.append(key)
	roster_scroll.visible = rows.size() > 1
	right_column = VBoxContainer.new()
	right_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_column.size_flags_stretch_ratio = 0.53
	right_column.add_theme_constant_override("separation", 12)
	content.add_child(right_column)
	identity = HBoxContainer.new()
	identity.add_theme_constant_override("separation", 14)
	right_column.add_child(identity)
	portrait = DungeonStyle.picture("", Vector2(84, 84))
	identity.add_child(portrait)
	var names = VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_child(names)
	name_label = _label("", 29)
	name_label.add_theme_color_override("font_color", GOLD)
	names.add_child(name_label)
	level_label = _label("", 19)
	level_label.add_theme_color_override("font_color", MUTED)
	names.add_child(level_label)
	awakening_button = _icon_button("res://assets/art_generated/awakening-flame-v1.png", "查看觉醒", Vector2(72, 80))
	awakening_button.text = "觉醒"
	awakening_button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	awakening_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	awakening_button.add_theme_constant_override("icon_max_width", 44)
	awakening_button.add_theme_font_size_override("font_size", 17)
	awakening_button.pressed.connect(func(): command.emit("page:awakening", _character_id(), 0))
	identity.add_child(awakening_button)
	talent_button = _paper_button("查看天赋", "查看角色天赋")
	talent_button.pressed.connect(func(): command.emit("page:character_talents", _character_id(), 0))
	right_column.add_child(talent_button)
	detail_scroll = ScrollContainer.new()
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_column.add_child(detail_scroll)
	detail = VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 12)
	detail_scroll.add_child(detail)
	action_bar = HBoxContainer.new()
	action_bar.add_theme_constant_override("separation", 8)
	right_column.add_child(action_bar)
	var tabs = HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	right_column.add_child(tabs)
	details_button = _paper_button("角色详情", "角色详情")
	details_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_button.pressed.connect(func(): set_detail_tab("details"))
	tabs.add_child(details_button)
	style_button = _paper_button("战斗风格", "查看战斗技能")
	style_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	style_button.pressed.connect(func(): set_detail_tab("style"))
	tabs.add_child(style_button)
	use_model = bool(context.get("use_model", false))
	active_tab = str(context.get("character_mode", "details"))

func _select_showcase(index: int) -> void:
	if index < 0 or index >= rows.size(): return
	selected = index
	var row: Dictionary = rows[index]
	context["selected_id"] = _character_id()
	context["character_id"] = _character_id()
	context["selected_character"] = _character_id()
	if is_instance_valid(owner_page):
		owner_page.page_context["selected_id"] = _character_id()
		owner_page.page_context["character_id"] = _character_id()
		owner_page.page_context["selected_character"] = _character_id()
	for i in selections.size():
		selections[i].add_theme_stylebox_override("normal", _flat(Color("705844") if i == selected else Color("33252c"), GOLD if i == selected else Color("796859"), 2 if i == selected else 1))
		selections[i].modulate = Color.WHITE if _owned(rows[i]) else Color(0.62, 0.62, 0.68)
	_clear(showcase)
	var artwork = DungeonStyle.texture(str(row.get("artwork", "")))
	if not use_model and artwork:
		var image = DungeonStyle.picture(str(row.artwork), Vector2(110, 90))
		image.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		image.size_flags_vertical = Control.SIZE_EXPAND_FILL
		showcase.add_child(image)
	else:
		var preview = DungeonModelPreview.new()
		preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
		showcase.add_child(preview)
		preview.custom_minimum_size = Vector2(110, 90)
		preview.show_model(str(row.get("model", "")))
	model_button.text = "2D" if use_model else "3D"
	model_button.tooltip_text = "查看角色立绘" if use_model else "查看角色模型"
	portrait.texture = DungeonStyle.texture(str(row.get("icon", "")))
	var source = _source()
	name_label.text = DungeonCatalog.clean(DungeonCatalog.row_name(source)) if not source.is_empty() else str(row.get("title", "")).split("  ")[0]
	var row_title = str(row.get("title", ""))
	level_label.text = row_title.get_slice("  ", 1) + ("  · 已出战" if row.get("active_character", false) else "" if _owned(row) else "  · 未招募")
	_clear(action_bar)
	for entry in row.get("buttons", []):
		var action = str(entry.get("action", ""))
		if action == "page:character_talents": continue
		if action == "select_character" and row.get("in_run", false): continue
		var key = _command_button(entry)
		key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if action == "select_character" and row.get("active_character", false): key.disabled = true
		action_bar.add_child(key)
	action_bar.visible = action_bar.get_child_count() > 0
	_refresh_detail()
	_adapt.call_deferred()

func set_detail_tab(tab: String) -> void:
	active_tab = tab
	context["character_mode"] = tab
	if is_instance_valid(owner_page): owner_page.page_context["character_mode"] = tab
	_refresh_detail()
	_adapt.call_deferred()

func _refresh_detail() -> void:
	_clear(detail)
	if rows.is_empty(): return
	var row: Dictionary = rows[selected]
	var source = _source()
	if active_tab == "style":
		_build_battle_style()
	else:
		detail.add_child(_label("角色详情", 23))
		biography = _label(DungeonCatalog.clean(DungeonCatalog.description(source)) if not source.is_empty() else str(row.get("description", "")).split("\n金币")[0], 18)
		biography.add_theme_color_override("font_color", Color("e7dbcc"))
		detail.add_child(biography)
		var stats = VBoxContainer.new()
		stats.add_theme_constant_override("separation", 3)
		detail.add_child(stats)
		var stat_icons = ["icon_stagerewardtypeicon_heal", "interaction_weapon", "skill_dodge", "skill_attack", "hud_charge_diamond"]
		for index in row.get("stats", []).size():
			var stat: Array = row.stats[index]
			var line = HBoxContainer.new()
			line.custom_minimum_size.y = 38
			line.add_theme_constant_override("separation", 10)
			stats.add_child(line)
			var icon = DungeonStyle.picture(stat_icons[index % stat_icons.size()], Vector2(27, 27))
			line.add_child(icon)
			var stat_name = _label(str(stat[0]), 22)
			stat_name.autowrap_mode = TextServer.AUTOWRAP_OFF
			stat_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.add_child(stat_name)
			var value = _label(str(stat[1]), 22)
			value.autowrap_mode = TextServer.AUTOWRAP_OFF
			value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			line.add_child(value)
			var bonuses: Array = row.get("stats_bonus", [])
			if index < bonuses.size() and not str(bonuses[index]).is_empty() and str(bonuses[index]) not in ["0", "0.0", "0%", "0.0%"]:
				var bonus = _label("(" + str(bonuses[index]) + ")", 20)
				bonus.autowrap_mode = TextServer.AUTOWRAP_OFF
				bonus.add_theme_color_override("font_color", Color("e99583") if index == 1 else Color("9dcde9"))
				line.add_child(bonus)
		if not row.get("in_run", false):
			var progress_text = str(row.get("description", ""))
			var base_text = DungeonCatalog.clean(DungeonCatalog.description(source))
			if not base_text.is_empty() and progress_text.begins_with(base_text): progress_text = progress_text.trim_prefix(base_text).strip_edges()
			if not progress_text.is_empty() and progress_text != biography.text:
				var progression = _label(progress_text, 17)
				progression.add_theme_color_override("font_color", MUTED)
				detail.add_child(progression)
	for pair in [[details_button, "details"], [style_button, "style"]]:
		pair[0].add_theme_stylebox_override("normal", _flat(PAPER if active_tab == pair[1] else Color(0.74, 0.65, 0.61, 0.48), Color("d6c7aa"), 1))
	detail_scroll.scroll_vertical = 0

func _build_battle_style() -> void:
	var fighter: Dictionary = {}
	for entry in _combat_characters:
		if int(entry.get("id", 0)) == _character_id(): fighter = entry; break
	var source = _source()
	var weapon_icon = DungeonStyle.picture(str(source.get("weapon_type_icon", "interaction_weapon")), Vector2(40, 40))
	detail.add_child(weapon_icon)
	var skills: Array = fighter.get("skills", [])
	var categories = ["普通攻击", "闪避", "战技", "爆发技"]
	for index in mini(4, skills.size()):
		var skill: Dictionary = skills[index]
		var title = _label(categories[index] + "  ·  " + DungeonCatalog.clean(skill.get("name", "")), 21)
		title.add_theme_color_override("font_color", GOLD)
		detail.add_child(title)
		detail.add_child(_label(DungeonCatalog.clean(skill.get("description", "")), 17))
		if float(skill.get("cooldown", 0)) >= 1:
			var cooldown = _label("冷却  %.1f 秒" % float(skill.cooldown), 16)
			cooldown.add_theme_color_override("font_color", MUTED)
			detail.add_child(cooldown)
		detail.add_child(HSeparator.new())
	if skills.is_empty(): detail.add_child(_label("暂无技能信息", 19))

func _show_attributes() -> void:
	if rows.is_empty(): return
	if is_instance_valid(_attribute_overlay):
		_attribute_overlay.queue_free()
	_attribute_overlay = Control.new()
	_attribute_overlay.name = "AttributeDetails"
	_attribute_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_attribute_overlay)
	var shade = ColorRect.new()
	shade.color = Color(0, 0, 0, 0.72)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed: _attribute_overlay.queue_free())
	_attribute_overlay.add_child(shade)
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_attribute_overlay.add_child(center)
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(minf(size.x - 32, 450), 0)
	panel.add_theme_stylebox_override("panel", _flat(Color("302129"), GOLD, 2))
	center.add_child(panel)
	var stack = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	panel.add_child(stack)
	var title = HBoxContainer.new()
	stack.add_child(title)
	var caption = _label(name_label.text + " · 属性详情", 23)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_child(caption)
	var close = _icon_button("X", "关闭属性详情", Vector2(30, 30))
	close.pressed.connect(func(): _attribute_overlay.queue_free())
	title.add_child(close)
	var values: Array = rows[selected].get("stats", []).duplicate(true)
	var source = _source()
	if not source.is_empty():
		values.append(["移动速度", str(source.get("move_speed", 0))])
		values.append(["索敌距离", str(source.get("search_distance", 0))])
	for value in values:
		var line = HBoxContainer.new()
		var key = _label(str(value[0]), 19)
		key.autowrap_mode = TextServer.AUTOWRAP_OFF
		key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(key)
		var attribute_value = _label(str(value[1]), 19)
		attribute_value.autowrap_mode = TextServer.AUTOWRAP_OFF
		line.add_child(attribute_value)
		stack.add_child(line)

func _adapt() -> void:
	if not is_inside_tree() or not is_instance_valid(content): return
	_compact = size.y < 560 or size.x < 1000
	var inset = 12 if _compact else 28
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]: margin.add_theme_constant_override(side, inset)
	page_stack.add_theme_constant_override("separation", 5 if _compact else 12)
	content.add_theme_constant_override("separation", 12 if _compact else 30)
	title_label.add_theme_font_size_override("font_size", 21 if _compact else 31)
	heading.add_theme_constant_override("separation", 8 if _compact else 14)
	for child in heading.get_children():
		if child is Button: child.custom_minimum_size = Vector2(38, 38) if _compact else Vector2(55, 50)
	resource_bar.add_theme_constant_override("separation", 8 if _compact else 16)
	for line in resource_bar.get_children():
		line.custom_minimum_size = Vector2(66, 28) if _compact else Vector2(126, 38)
		for child in line.get_children():
			if child is Label: child.add_theme_font_size_override("font_size", 16 if _compact else 21)
			if child is TextureRect: child.custom_minimum_size = Vector2(25, 25) if _compact else Vector2(34, 34)
	category_tabs.custom_minimum_size.x = 96 if _compact else 172
	for key in navigation:
		key.custom_minimum_size = Vector2(96, 48) if _compact else Vector2(172, 78)
		key.add_theme_font_size_override("font_size", 18 if _compact else 25)
		key.add_theme_constant_override("icon_max_width", 24 if _compact else 34)
		key.add_theme_constant_override("h_separation", 7 if _compact else 18)
		_spacing(key, 5 if _compact else 12)
	right_column.custom_minimum_size.x = 245 if _compact else 360
	right_column.add_theme_constant_override("separation", 6 if _compact else 12)
	detail.add_theme_constant_override("separation", 6 if _compact else 12)
	if active_tab == "details" and is_instance_valid(biography) and biography.get_parent() == detail:
		detail.move_child(biography, detail.get_child_count() - 1 if _compact else 1)
		if detail.get_child(0) is Label: detail.get_child(0).visible = not _compact
	identity.add_theme_constant_override("separation", 8 if _compact else 14)
	portrait.custom_minimum_size = Vector2(46, 46) if _compact else Vector2(84, 84)
	name_label.add_theme_font_size_override("font_size", 22 if _compact else 29)
	level_label.add_theme_font_size_override("font_size", 14 if _compact else 19)
	awakening_button.custom_minimum_size = Vector2(46, 46) if _compact else Vector2(72, 80)
	awakening_button.add_theme_constant_override("icon_max_width", 25 if _compact else 44)
	awakening_button.add_theme_font_size_override("font_size", 13 if _compact else 17)
	for key in [talent_button, attributes_button, model_button, details_button, style_button]:
		key.custom_minimum_size.y = 31 if _compact else 40
		key.add_theme_font_size_override("font_size", 16 if _compact else 19)
		_spacing(key, 4 if _compact else 8)
	for key in action_bar.get_children():
		key.custom_minimum_size = Vector2(0, 34 if _compact else 44)
		key.add_theme_font_size_override("font_size", 16 if _compact else 19)
		_spacing(key, 4 if _compact else 8)
	for key in selections:
		key.custom_minimum_size = Vector2(42, 42) if _compact else Vector2(59, 59)
		key.add_theme_constant_override("icon_max_width", 34 if _compact else 48)
		_spacing(key, 3 if _compact else 5)
	roster_scroll.custom_minimum_size.y = 48 if _compact else 67
	for child in detail.get_children():
		if child is Label: child.add_theme_font_size_override("font_size", 16 if _compact else 18 if child == biography else 21)
		if child is VBoxContainer:
			for line in child.get_children():
				line.custom_minimum_size.y = 26 if _compact else 38
				for item in line.get_children():
					if item is Label: item.add_theme_font_size_override("font_size", 17 if _compact else 22)
					if item is TextureRect: item.custom_minimum_size = Vector2(20, 20) if _compact else Vector2(27, 27)

func _character_id() -> int:
	return int(rows[selected].get("config_id", 0)) if not rows.is_empty() else 0

func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(_attribute_overlay) and event.is_action_pressed("ui_cancel"):
		_attribute_overlay.queue_free()
		get_viewport().set_input_as_handled()

func _source() -> Dictionary:
	return _catalog.find("CharData", _character_id()) if _catalog else {}

func _owned(row: Dictionary) -> bool:
	for entry in row.get("buttons", []):
		if str(entry.get("action", "")) == "select_character": return not bool(entry.get("disabled", false))
	return bool(row.get("in_run", false))

func _label(text: String, font_size: int) -> Label:
	var result = DungeonStyle.label(text, font_size)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.add_theme_color_override("font_color", PAPER)
	result.add_theme_color_override("font_shadow_color", Color(0.12, 0.06, 0.09, 0.8))
	return result

func _paper_button(text: String, hint: String) -> Button:
	var result = Button.new()
	result.text = text
	result.tooltip_text = hint
	result.custom_minimum_size.y = 40
	for state in ["normal", "hover", "pressed", "disabled"]:
		var fill = PAPER if state == "normal" else Color("fff8dd") if state == "hover" else Color("dec497") if state == "pressed" else Color("8a7e77")
		result.add_theme_stylebox_override(state, _flat(fill, Color("d6c7aa"), 1))
	result.add_theme_color_override("font_color", INK)
	result.add_theme_color_override("font_hover_color", INK)
	result.add_theme_color_override("font_pressed_color", INK)
	result.add_theme_color_override("font_disabled_color", Color("c8bcab"))
	return result

func _icon_button(icon: String, hint: String, dimensions: Vector2) -> Button:
	var result = Button.new()
	result.icon = DungeonStyle.texture(icon)
	result.expand_icon = true
	result.custom_minimum_size = dimensions
	result.add_theme_constant_override("icon_max_width", int(dimensions.x))
	result.tooltip_text = hint
	for state in ["normal", "hover", "pressed"]: result.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	return result

func _command_button(entry: Dictionary) -> Button:
	var result = _paper_button(str(entry.get("text", "")), str(entry.get("text", "")))
	result.disabled = bool(entry.get("disabled", false))
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.pressed.connect(func(): command.emit(str(entry.get("action", "")), entry.get("id", 0), entry.get("extra", 0)))
	return result

func _flat(fill: Color, border := Color.TRANSPARENT, width := 1) -> StyleBoxFlat:
	var result = DungeonStyle.box(fill, border, width)
	result.set_corner_radius_all(3)
	result.set_content_margin_all(8)
	return result

func _spacing(button: Button, value: int) -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style = button.get_theme_stylebox(state).duplicate()
		style.set_content_margin_all(value)
		button.add_theme_stylebox_override(state, style)

func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
