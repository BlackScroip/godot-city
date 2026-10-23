class_name DungeonReferencePages
extends HBoxContainer

signal command(kind: String, id: Variant, extra: Variant)
var owner_page: DungeonMenuPage
var rows: Array
var mode := ""
var rail: VBoxContainer
var showcase: VBoxContainer
var detail: VBoxContainer
var selections: Array[Button] = []
var selected := 0
var use_model := false
var altar_parts: Array[Dictionary] = []
var altar_cards: HBoxContainer
var altar_toolbar: HBoxContainer
const PAPER = Color("f2efe6")
const BROWN = Color("5b4933")

func configure(host: DungeonMenuPage, data: Array, layout: String) -> void:
	owner_page = host
	rows = data
	mode = layout
	if mode in ["tree", "buildings", "prepare", "shop"]:
		var paper_theme = DungeonStyle.theme().duplicate()
		paper_theme.set_color("font_color", "Label", BROWN)
		paper_theme.set_color("font_shadow_color", "Label", Color.TRANSPARENT)
		theme = paper_theme
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 28)
	match mode:
		"altar", "talent": _altar()
		"inventory": _inventory()
		"character", "weapon": _showcase()
		"settings": _settings()
		"tree", "awakening", "buildings", "route": _tree()
		"prepare": _prepare()
		"shop": _shop()

func _altar() -> void:
	var outer = VBoxContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(outer)
	var toolbar = HBoxContainer.new()
	altar_toolbar = toolbar
	toolbar.alignment = BoxContainer.ALIGNMENT_END
	outer.add_child(toolbar)
	toolbar.add_child(_command_button({"text": "角色", "action": "page:inventory"}))
	for row in rows:
		if row.get("presentation_role", "") == "refresh":
			for entry in row.get("buttons", []): toolbar.add_child(_command_button(entry))
	var cards = HBoxContainer.new()
	altar_cards = cards
	cards.alignment = BoxContainer.ALIGNMENT_CENTER
	cards.add_theme_constant_override("separation", 26)
	cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(cards)
	for row in rows:
		if row.get("presentation_role", "") == "refresh": continue
		var panel = preload("res://scripts/presentation/altar_card.gd").new()
		panel.accent = row.get("grade_color", Color("e2c97c"))
		panel.custom_minimum_size.x = 320
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cards.add_child(panel)
		var stack = VBoxContainer.new()
		stack.add_theme_constant_override("separation", 16)
		panel.add_child(stack)
		var icon_center = CenterContainer.new()
		stack.add_child(icon_center)
		var icon_frame = PanelContainer.new()
		icon_frame.add_theme_stylebox_override("panel", DungeonStyle.box(Color("255873"), Color("7ab6d1"), 3))
		icon_center.add_child(icon_frame)
		var icon = DungeonStyle.picture(str(row.get("icon", "")), Vector2(120, 120))
		icon_frame.add_child(icon)
		var title = DungeonStyle.label(str(row.title), 26)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_color_override("font_color", Color("624015"))
		title.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
		stack.add_child(title)
		if row.has("level_text"):
			var level = DungeonStyle.label(str(row.get("grade", "")) + "  " + str(row.level_text), 23)
			level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			level.add_theme_color_override("font_color", Color("32465b"))
			level.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
			stack.add_child(level)
		stack.add_child(HSeparator.new())
		var scroll = ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		stack.add_child(scroll)
		var description = DungeonStyle.label(str(row.get("description", "")), 22)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		description.add_theme_color_override("font_color", Color("233946"))
		description.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
		scroll.add_child(description)
		for entry in row.get("buttons", []): stack.add_child(_command_button(entry, true))
		altar_parts.append({"panel": panel, "stack": stack, "icon": icon, "icon_frame": icon_frame, "title": title, "description": description, "scroll": scroll})
	resized.connect(_adapt_altar)
	_adapt_altar.call_deferred()

func _adapt_altar() -> void:
	if not is_instance_valid(owner_page) or altar_parts.is_empty(): return
	var compact := get_viewport_rect().size.y < 600.0
	var page_style = DungeonStyle.panel().duplicate()
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]: page_style.set_content_margin(side, 12 if compact else 62)
	owner_page.add_theme_stylebox_override("panel", page_style)
	owner_page.stack.add_theme_constant_override("separation", 6 if compact else 16)
	owner_page.title_label.add_theme_font_size_override("font_size", 20 if compact else 28)
	for control in owner_page.stack.get_child(0).get_children():
		if control is Button:
			control.custom_minimum_size = Vector2(40, 40) if compact else Vector2(48, 48)
			_altar_button_spacing(control, compact)
	for control in altar_toolbar.get_children():
		control.custom_minimum_size = Vector2(72, 32) if compact else Vector2(100, 44)
		control.add_theme_font_size_override("font_size", 14 if compact else 19)
		_altar_button_spacing(control, compact)
	altar_cards.add_theme_constant_override("separation", 8 if compact else 26)
	for part in altar_parts:
		part.panel.compact = compact
		part.panel.apply_spacing()
		part.panel.custom_minimum_size.x = 0 if compact else 320
		part.stack.add_theme_constant_override("separation", 4 if compact else 16)
		part.icon.custom_minimum_size = Vector2(36, 36) if compact else Vector2(120, 120)
		var icon_style = part.icon_frame.get_theme_stylebox("panel").duplicate()
		icon_style.set_content_margin_all(4 if compact else 12)
		part.icon_frame.add_theme_stylebox_override("panel", icon_style)
		part.title.add_theme_font_size_override("font_size", 17 if compact else 26)
		part.description.add_theme_font_size_override("font_size", 15 if compact else 22)
		for control in part.stack.get_children():
			if control is Label and control != part.title: control.add_theme_font_size_override("font_size", 14 if compact else 23)
			if control is Button:
				control.custom_minimum_size.y = 36 if compact else 48
				control.add_theme_font_size_override("font_size", 16 if compact else 19)
				_altar_button_spacing(control, compact)
	_fit_altar_page.call_deferred()

func _altar_button_spacing(button: Button, compact: bool) -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style = button.get_theme_stylebox(state).duplicate()
		style.set_content_margin_all(6 if compact else 12)
		button.add_theme_stylebox_override(state, style)

func _fit_altar_page() -> void:
	if not is_instance_valid(owner_page): return
	owner_page.size = get_viewport_rect().size

func _inventory() -> void:
	var tabs = VBoxContainer.new()
	tabs.custom_minimum_size.x = 135
	add_child(tabs)
	for entry in [["角色", "characters"], ["武器", "weapons"], ["背包", "inventory"], ["遗物图鉴", "archive"]]:
		var key = _command_button({"text": entry[0], "action": "page:" + entry[1]})
		key.custom_minimum_size.y = 65
		if entry[1] == "inventory": key.modulate = DungeonStyle.GOLD
		tabs.add_child(key)
	tabs.add_child(_command_button({"text": "角色天赋", "action": "page:character_talents"}))
	var items = _scroll(self)
	items.add_child(DungeonStyle.label("持有遗物", 26))
	var grid = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	items.add_child(grid)
	var panel = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 0.7
	panel.add_theme_stylebox_override("panel", DungeonStyle.box(PAPER, DungeonStyle.GOLD, 2))
	add_child(panel)
	detail = _scroll(panel)
	for index in rows.size():
		var key = _select_button(rows[index], Vector2(88, 90))
		key.text = ""
		key.tooltip_text = str(rows[index].title)
		key.pressed.connect(func(): _inventory_detail(index))
		grid.add_child(key)
		selections.append(key)
	if not rows.is_empty(): _inventory_detail(0)

func _inventory_detail(index: int) -> void:
	_clear(detail)
	for i in selections.size(): selections[i].add_theme_stylebox_override("normal", DungeonStyle.box(Color("275269"), DungeonStyle.GOLD if i == index else Color("6eacbf"), 3 if i == index else 1))
	var row: Dictionary = rows[index]
	detail.add_child(DungeonStyle.picture(str(row.get("icon", "")), Vector2(180, 190)))
	for text in [str(row.title), str(row.get("description", ""))]:
		var label = DungeonStyle.label(text, 23)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_color_override("font_color", BROWN)
		label.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
		detail.add_child(label)
		detail.add_child(HSeparator.new())
	for entry in row.get("buttons", []): detail.add_child(_command_button(entry, true))

func _scroll(parent: Control, width := 0.0, expand := true) -> VBoxContainer:
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.x = width
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if expand: scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	var stack = VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 14)
	scroll.add_child(stack)
	return stack

func _showcase() -> void:
	rail = _scroll(self, 94, false)
	showcase = VBoxContainer.new()
	showcase.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(showcase)
	detail = _scroll(self, 300, false)
	detail.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.get_parent().size_flags_stretch_ratio = 0.6
	for i in rows.size():
		var key = _select_button(rows[i], Vector2(84, 84))
		key.text = ""
		key.tooltip_text = str(rows[i].get("title", ""))
		key.pressed.connect(func(): _select_showcase(i))
		rail.add_child(key)
		selections.append(key)
	if not rows.is_empty(): _select_showcase(0)

func _select_showcase(index: int) -> void:
	selected = index
	_clear(showcase)
	_clear(detail)
	for i in selections.size(): selections[i].add_theme_stylebox_override("normal", DungeonStyle.box(Color("465340") if i == index else Color("1f2d2f"), DungeonStyle.GOLD if i == index else Color("718276"), 2))
	var row: Dictionary = rows[index]
	var artwork = DungeonStyle.texture(str(row.get("artwork", ""))) if mode == "character" else null
	if artwork and not use_model and mode == "character":
		var image = DungeonStyle.picture(str(row.artwork), Vector2(220, 260))
		image.size_flags_vertical = Control.SIZE_EXPAND_FILL
		showcase.add_child(image)
	else:
		var model = DungeonModelPreview.new()
		model.size_flags_vertical = Control.SIZE_EXPAND_FILL
		showcase.add_child(model)
		model.show_model(str(row.get("model", "")))
	var commands = HBoxContainer.new()
	commands.alignment = BoxContainer.ALIGNMENT_CENTER
	showcase.add_child(commands)
	for entry in row.get("buttons", []):
		if str(entry.action) in ["select_character", "equip_weapon"]: commands.add_child(_command_button(entry, true))
	if mode == "character":
		var toggle = Button.new()
		toggle.text = "2D" if use_model else "3D"
		toggle.tooltip_text = "切换角色展示"
		toggle.pressed.connect(func(): use_model = not use_model; _select_showcase(selected))
		commands.add_child(toggle)
	var title = DungeonStyle.label(str(row.title), 26)
	title.modulate = DungeonStyle.GOLD
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(title)
	owner_page._row(detail, {"title": "角色详情" if mode == "character" else "武器详情", "description": row.get("description", "")}, false)
	for stat in row.get("stats", []):
		var line = HBoxContainer.new()
		var name_label = DungeonStyle.label(str(stat[0]))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(name_label)
		line.add_child(DungeonStyle.label(str(stat[1])))
		detail.add_child(line)
	detail.add_child(HSeparator.new())
	for entry in row.get("buttons", []):
		if str(entry.action) not in ["select_character", "equip_weapon"]: detail.add_child(_command_button(entry, true))

func _select_button(row: Dictionary, dimensions: Vector2) -> Button:
	var key = Button.new()
	key.custom_minimum_size = dimensions
	key.icon = owner_page._icon(row)
	key.expand_icon = true
	key.add_theme_constant_override("icon_max_width", 58)
	key.text = str(row.get("title", ""))
	key.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	key.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	key.add_theme_font_size_override("font_size", 16)
	return key

func _command_button(entry: Dictionary, paper := false) -> Button:
	var button = Button.new()
	button.text = str(entry.get("text", ""))
	button.custom_minimum_size = Vector2(100, 44)
	button.disabled = entry.get("disabled", false)
	if paper:
		button.add_theme_stylebox_override("normal", DungeonStyle.box(PAPER, Color("9a987d")))
		button.add_theme_color_override("font_color", BROWN)
	button.pressed.connect(func(): command.emit(str(entry.action), entry.get("id", 0), entry.get("extra", 0)))
	return button

func _settings() -> void:
	rail = VBoxContainer.new()
	rail.custom_minimum_size.x = 150
	rail.add_theme_constant_override("separation", 18)
	add_child(rail)
	detail = _scroll(self)
	for section in ["游戏性", "画面", "声音", "存档", "指南"]:
		var key = Button.new()
		key.text = section
		key.custom_minimum_size.y = 54
		key.pressed.connect(func(): _settings_section(section))
		rail.add_child(key)
	_settings_section("画面")

func _settings_section(section: String) -> void:
	_clear(detail)
	for key in rail.get_children(): key.modulate = DungeonStyle.GOLD if key.text == section else Color.WHITE
	for row in rows:
		if str(row.get("section", "游戏性")) != section: continue
		var panel = PanelContainer.new()
		panel.add_theme_stylebox_override("panel", DungeonStyle.box(PAPER, Color("b5b6a8")))
		detail.add_child(panel)
		var horizontal = HBoxContainer.new()
		horizontal.add_theme_constant_override("separation", 24)
		panel.add_child(horizontal)
		var name_label = DungeonStyle.label(str(row.title), 19)
		name_label.add_theme_color_override("font_color", BROWN)
		name_label.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
		name_label.custom_minimum_size.x = 170
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		horizontal.add_child(name_label)
		if row.has("options"):
			var options = HBoxContainer.new()
			horizontal.add_child(options)
			for option in row.options:
				var key = _command_button(option)
				key.custom_minimum_size.x = 70
				if option.get("selected", false): key.add_theme_stylebox_override("normal", DungeonStyle.box(Color("475966"), DungeonStyle.GOLD))
				options.add_child(key)
		else:
			var content = VBoxContainer.new()
			content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			horizontal.add_child(content)
			var copy = row.duplicate(true)
			copy.title = ""
			owner_page._row(content, copy, false)

func _tree() -> void:
	var tree_rows: Array = rows.filter(func(row): return row.get("presentation_role", "") != "awakening_summary")
	if mode == "awakening": tree_rows.sort_custom(func(a, b): return int(a.get("node_level", 0)) < int(b.get("node_level", 0)))
	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	var graph = Control.new()
	graph.custom_minimum_size = Vector2(610, 560) if mode == "awakening" else Vector2(570, 460)
	scroll.add_child(graph)
	if mode == "awakening":
		var emblem = DungeonStyle.picture("res://assets/art_generated/awakening-flame-v1.png", Vector2.ZERO)
		emblem.position = Vector2(115, 65)
		emblem.size = Vector2(350, 425)
		emblem.modulate = Color(1, 0.85, 0.6, 0.55)
		graph.add_child(emblem)
		for row in rows:
			if row.get("presentation_role", "") != "awakening_summary": continue
			var summary = VBoxContainer.new()
			summary.position = Vector2(10, 10)
			graph.add_child(summary)
			summary.add_child(DungeonStyle.label(str(row.get("description", "")), 24))
			for entry in row.get("buttons", []): summary.add_child(_command_button(entry))
	detail = _scroll(self, 275, false)
	var points: Dictionary = {}
	var depth: Dictionary = {}
	var layers: Dictionary = {}
	for row in tree_rows: depth[int(row.get("config_id", 0))] = 0
	for pass_index in tree_rows.size():
		var changed := false
		for row in tree_rows:
			var id = int(row.get("config_id", 0))
			for parent in row.get("parents", []):
				if depth.has(int(parent)) and depth[id] <= depth[int(parent)] and depth[int(parent)] < rows.size():
					depth[id] = depth[int(parent)] + 1
					changed = true
		if not changed: break
	for i in tree_rows.size():
		var row: Dictionary = tree_rows[i]
		var id = int(row.get("config_id", i))
		var d = int(row.get("column", depth.get(id, 0)))
		var lane = int(layers.get(d, 0))
		layers[d] = lane + 1
		var point = Vector2(30 + d * 190, 30 + lane * 150)
		if mode == "awakening" and tree_rows.size() > 1:
			point = Vector2(245, 240) + Vector2.from_angle(-PI / 2 + TAU * i / tree_rows.size()) * 205
		elif mode == "buildings": point = Vector2(30 + (i % 2) * 260, 30 + (i / 2) * 155)
		points[id] = point
		var dimensions = Vector2(88, 88) if mode == "awakening" else Vector2(128, 110)
		graph.custom_minimum_size = graph.custom_minimum_size.max(point + dimensions + Vector2(30, 30))
		var key = _select_button(row, dimensions)
		if mode == "awakening":
			key.text = str(row.get("node_label", ""))
			key.icon = null
			key.autowrap_mode = TextServer.AUTOWRAP_OFF
			for state in ["normal", "hover", "pressed", "focus"]:
				var circle = DungeonStyle.box(Color("674625") if row.get("active", false) else Color("241c19"), DungeonStyle.GOLD, 2)
				circle.set_corner_radius_all(44)
				key.add_theme_stylebox_override(state, circle)
			key.add_theme_constant_override("icon_max_width", 28)
		key.position = point
		key.pressed.connect(func(): _select_tree(row))
		key.tooltip_text = str(row.get("description", ""))
		graph.add_child(key)
	for row in tree_rows:
		var id = int(row.get("config_id", 0))
		for parent in row.get("parents", []):
			if not points.has(int(parent)) or not points.has(id): continue
			var line = Line2D.new()
			line.default_color = Color("b49a64")
			line.width = 2
			line.points = PackedVector2Array([points[int(parent)] + Vector2(128, 55), points[id] + Vector2(0, 55)])
			graph.add_child(line)
			graph.move_child(line, 0)
	if not tree_rows.is_empty(): _select_tree(tree_rows[0])

func _select_tree(row: Dictionary) -> void:
	_clear(detail)
	detail.add_child(DungeonStyle.picture(str(row.get("icon", "menu_adventure")), Vector2(100, 100)))
	owner_page._row(detail, row, false)

func _prepare() -> void:
	var summary = PanelContainer.new()
	summary.custom_minimum_size.x = 310
	summary.add_theme_stylebox_override("panel", DungeonStyle.box(PAPER, DungeonStyle.GOLD, 2))
	add_child(summary)
	var stack = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 20)
	summary.add_child(stack)
	var title = DungeonStyle.label("冒险准备", 26)
	title.modulate = BROWN
	stack.add_child(title)
	var choices = HBoxContainer.new()
	stack.add_child(choices)
	for entry in [["角色", "page:characters", "menu_character"], ["武器", "page:weapons", "interaction_weapon"], ["信物", "page:tokens", "gold_corner"]]:
		var key = _command_button({"text": entry[0], "action": entry[1]})
		key.icon = DungeonStyle.texture(entry[2])
		key.expand_icon = true
		key.add_theme_constant_override("icon_max_width", 35)
		choices.add_child(key)
	stack.add_child(_command_button({"text": "进入迷宫", "action": "primary"}))
	detail = _scroll(self)
	for row in rows: owner_page._row(detail, row)

func _shop() -> void:
	var aside = VBoxContainer.new()
	aside.custom_minimum_size.x = 240
	add_child(aside)
	var portrait = DungeonStyle.picture("menu_store", Vector2(120, 140))
	portrait.size_flags_vertical = Control.SIZE_EXPAND_FILL
	aside.add_child(portrait)
	var title = DungeonStyle.label("迷宫商店", 26)
	title.modulate = DungeonStyle.GOLD
	aside.add_child(title)
	var items = _scroll(self)
	var grid = GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	items.add_child(grid)
	for row in rows:
		if row.get("presentation_role", "") == "navigation":
			for entry in row.get("buttons", []): aside.add_child(_command_button(entry, true))
			continue
		var panel = PanelContainer.new()
		panel.custom_minimum_size.x = 160
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.add_theme_stylebox_override("panel", DungeonStyle.box(PAPER, DungeonStyle.GOLD))
		grid.add_child(panel)
		var stack = VBoxContainer.new()
		panel.add_child(stack)
		stack.add_child(DungeonStyle.picture(str(row.get("icon", "interaction_weapon")), Vector2(72, 72)))
		owner_page._row(stack, row, false)
		stack.add_theme_color_override("font_color", BROWN)

func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
