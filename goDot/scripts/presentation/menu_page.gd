class_name DungeonMenuPage
extends PanelContainer

signal command(kind: String, id: Variant, extra: Variant)
signal closed
signal back_requested
const ROLE_NAVIGATION = preload("res://scripts/presentation/role_navigation.gd")
var title_label: Label
var rows_host: VBoxContainer
var grid: GridContainer
var detail: VBoxContainer
var list_scroll: ScrollContainer
var detail_scroll: ScrollContainer
var body: HBoxContainer
var _rows: Array = []
var _layout := "list"
var _selected := 0
var _choices: Array[Button] = []
var special: DungeonReferencePages
var stack: VBoxContainer
var backdrop: TextureRect
var route_view: DungeonRoutePage
var resource_bar: HBoxContainer
var outcome_view: Control
var building_view: Control
var commission_view: Control
var guild_view: Control
var dialogue_view: Control
var prepare_view: Control
var unclaimed_view: Control
var room_shop_view: Control
var character_view: Control
var weapon_view: Control
var inventory_view: Control
var shop_view: Control
var camp_service_view: Control
var awakening_view: Control
var adventure_event_view: Control
var page_context: Dictionary = {}
var _open_tween: Tween
var _adapting := false

func _ready() -> void:
	add_theme_stylebox_override("panel", DungeonStyle.panel())
	backdrop = DungeonStyle.picture("res://assets/art_generated/showcase-v1.png", Vector2.ZERO)
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.show_behind_parent = true
	add_child(backdrop)
	stack = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 16)
	add_child(stack)
	var heading = HBoxContainer.new()
	stack.add_child(heading)
	var back = ROLE_NAVIGATION.create_header_back_button(size, "关闭")
	back.pressed.connect(func(): back_requested.emit())
	heading.add_child(back)
	title_label = DungeonStyle.label("", 28)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	heading.add_child(title_label)
	var heading_art = DungeonStyle.picture("gold_line_top", Vector2.ZERO)
	title_label.add_child(heading_art)
	heading_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	heading_art.stretch_mode = TextureRect.STRETCH_SCALE
	heading_art.show_behind_parent = true
	resource_bar = HBoxContainer.new()
	resource_bar.add_theme_constant_override("separation", 12)
	heading.add_child(resource_bar)
	var close = Button.new()
	close.text = "×"
	close.tooltip_text = "关闭"
	close.custom_minimum_size = Vector2(44, 44)
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		close.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	close.pressed.connect(func(): closed.emit())
	heading.add_child(close)
	var divider = TextureRect.new()
	divider.texture = DungeonStyle.texture("gold_line_bottom")
	divider.custom_minimum_size.y = 2
	divider.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	divider.modulate = DungeonStyle.GOLD
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(divider)
	body = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 24)
	stack.add_child(body)
	list_scroll = ScrollContainer.new()
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(list_scroll)
	rows_host = VBoxContainer.new()
	rows_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows_host.add_theme_constant_override("separation", 10)
	list_scroll.add_child(rows_host)
	detail_scroll = ScrollContainer.new()
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(detail_scroll)
	detail = VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 14)
	detail_scroll.add_child(detail)
	resized.connect(_adapt)

func display(title: String, rows: Array, layout := "list", context: Dictionary = {}) -> void:
	if _open_tween and _open_tween.is_valid(): _open_tween.kill()
	modulate.a = 1.0 if layout == "buildings" else 0.35
	if layout != "buildings":
		_open_tween = create_tween()
		_open_tween.tween_property(self, "modulate:a", 1.0, 0.3 / float(DungeonSettings.read_options().ui_speed))
	page_context = context
	_clear(resource_bar)
	for resource in context.get("resources", []):
		var line = HBoxContainer.new()
		line.custom_minimum_size.x = 130
		resource_bar.add_child(line)
		line.add_child(DungeonStyle.picture(str(resource[0]), Vector2(36, 36)))
		var amount = DungeonStyle.label(str(resource[1]), 22)
		amount.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.add_child(amount)
	title_label.text = title
	var reference = layout in ["commission", "guild"]
	for decoration in title_label.get_children(): decoration.visible = not reference
	title_label.add_theme_color_override("font_shadow_color", Color.TRANSPARENT if reference else Color(0, 0, 0, 0.8))
	var back: Button = stack.get_child(0).get_child(0)
	ROLE_NAVIGATION.configure_header_back_button(back, size, "返回" if context.has("back_action") else "关闭")
	_rows = rows
	_layout = layout
	_choices.clear()
	_clear(rows_host)
	_clear(detail)
	for view in [building_view, commission_view, guild_view, dialogue_view, prepare_view, room_shop_view, unclaimed_view, character_view, weapon_view, inventory_view, shop_view, camp_service_view, awakening_view, adventure_event_view]:
		if is_instance_valid(view):
			stack.remove_child(view)
			view.queue_free()
	building_view = null
	commission_view = null
	guild_view = null
	dialogue_view = null
	prepare_view = null
	unclaimed_view = null
	room_shop_view = null
	character_view = null
	weapon_view = null
	inventory_view = null
	shop_view = null
	camp_service_view = null
	awakening_view = null
	adventure_event_view = null
	if is_instance_valid(outcome_view):
		stack.remove_child(outcome_view)
		outcome_view.queue_free()
		outcome_view = null
	release_route_view()
	if is_instance_valid(special):
		stack.remove_child(special)
		special.queue_free()
		special = null
	stack.get_child(0).visible = layout not in ["route", "outcome", "buildings", "dialogue", "prepare", "altar", "talent", "support", "room_shop", "unclaimed", "character", "weapon", "inventory", "shop", "settings"]
	stack.get_child(1).visible = layout not in ["route", "outcome", "buildings", "dialogue", "prepare", "altar", "talent", "support", "room_shop", "unclaimed", "character", "weapon", "inventory", "shop", "settings"]
	stack.add_theme_constant_override("separation", 0 if layout in ["route", "outcome"] else 16)
	if layout == "adventure_event":
		stack.get_child(0).hide()
		stack.get_child(1).hide()
		backdrop.hide()
		body.hide()
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		stack.add_theme_constant_override("separation", 0)
		adventure_event_view = load("res://scripts/presentation/adventure_event_page.gd").new()
		stack.add_child(adventure_event_view)
		adventure_event_view.command.connect(func(kind, id, extra): command.emit(kind, id, extra))
		adventure_event_view.closed.connect(func(): closed.emit())
		adventure_event_view.configure(self, rows, context)
		return
	if layout in ["tokens", "camp_service", "awakening"]:
		stack.get_child(0).hide()
		stack.get_child(1).hide()
		backdrop.hide()
		body.hide()
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		stack.add_theme_constant_override("separation", 0)
		var view = load("res://scripts/presentation/" + {"tokens": "token_page", "camp_service": "camp_services_page", "awakening": "awakening_page"}[layout] + ".gd").new()
		if layout == "awakening": awakening_view = view
		else: camp_service_view = view
		stack.add_child(view)
		view.command.connect(func(kind, id, extra): command.emit(kind, id, extra))
		view.closed.connect(func(): closed.emit())
		view.back_requested.connect(func(): back_requested.emit())
		view.configure(self, rows, context)
		return
	if layout in ["character", "weapon", "inventory", "shop"]:
		backdrop.hide()
		body.hide()
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		stack.add_theme_constant_override("separation", 0)
		var pages = {"character": "character_page", "weapon": "weapon_page", "inventory": "inventory_page", "shop": "mall_page"}
		var view = load("res://scripts/presentation/" + str(pages[layout]) + ".gd").new()
		match layout:
			"character": character_view = view
			"weapon": weapon_view = view
			"inventory": inventory_view = view
			"shop": shop_view = view
		stack.add_child(view)
		view.command.connect(func(kind, id, extra): command.emit(kind, id, extra))
		if view.has_signal("closed"): view.closed.connect(func(): closed.emit())
		if view.has_signal("back_requested"): view.back_requested.connect(func(): closed.emit())
		view.configure(self, rows, context)
		return
	if layout == "room_shop":
		backdrop.hide()
		body.hide()
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		stack.add_theme_constant_override("separation", 0)
		room_shop_view = load("res://scripts/presentation/room_shop.gd").new()
		stack.add_child(room_shop_view)
		room_shop_view.command.connect(func(kind, id, extra): command.emit(kind, id, extra))
		room_shop_view.closed.connect(func(): closed.emit())
		room_shop_view.configure(rows, context)
		return
	if layout in ["buildings", "commission", "guild", "dialogue", "prepare", "unclaimed"]:
		backdrop.hide()
		body.hide()
		var paths = {"buildings": "building_page", "commission": "commission_board", "guild": "guild_page", "dialogue": "dialogue_page", "prepare": "adventure_prepare", "unclaimed": "unclaimed_prompt"}
		var view = load("res://scripts/presentation/" + paths[layout] + ".gd").new()
		match layout:
			"buildings": building_view = view
			"commission": commission_view = view
			"guild": guild_view = view
			"dialogue": dialogue_view = view
			"unclaimed": unclaimed_view = view
			"prepare":
				prepare_view = view
				view.closed.connect(func(): closed.emit())
		stack.add_child(view)
		view.command.connect(func(kind, id, extra): command.emit(kind, id, extra))
		if layout in ["buildings", "dialogue", "prepare", "unclaimed"]:
			add_theme_stylebox_override("panel", StyleBoxEmpty.new())
			stack.add_theme_constant_override("separation", 0)
		else:
			var style = DungeonStyle.artwork_box("几何ui-书页矩形花纹", 40)
			style.set_content_margin_all(16 if get_viewport_rect().size.y < 600 else 32)
			add_theme_stylebox_override("panel", style)
			title_label.add_theme_color_override("font_color", Color("69431d"))
		view.configure(self, rows, context)
		_adapt.call_deferred()
		return
	if layout == "outcome":
		backdrop.hide()
		body.hide()
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		outcome_view = preload("res://scripts/presentation/run_outcome.gd").new()
		stack.add_child(outcome_view)
		outcome_view.command.connect(func(kind, id, extra): command.emit(kind, id, extra))
		outcome_view.configure(context)
		return
	if layout == "route":
		backdrop.hide()
		body.hide()
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		route_view = DungeonRoutePage.new()
		stack.add_child(route_view)
		route_view.command.connect(func(kind, id, extra): command.emit(kind, id, extra))
		route_view.back_requested.connect(func(): closed.emit())
		route_view.configure(rows, context)
		return
	var specialized = layout in ["inventory", "altar", "talent", "support", "character", "weapon", "settings", "tree", "awakening", "buildings", "route", "prepare", "shop"]
	backdrop.visible = layout in ["inventory", "character", "weapon", "awakening"]
	add_theme_stylebox_override("panel", DungeonStyle.box(Color(0.03, 0.06, 0.06, 0.2)) if backdrop.visible or layout in ["settings", "route", "shop"] else DungeonStyle.panel())
	if layout == "altar":
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		stack.add_theme_constant_override("separation", 0)
	if layout in ["tree", "buildings", "prepare"]:
		var paper = DungeonStyle.box(Color("eae6da"), DungeonStyle.GOLD, 3)
		paper.set_content_margin_all(28)
		add_theme_stylebox_override("panel", paper)
		title_label.add_theme_color_override("font_color", Color("5b4933"))
	else: title_label.add_theme_color_override("font_color", DungeonStyle.TEXT)
	body.visible = not specialized
	if specialized:
		if layout == "settings":
			add_theme_stylebox_override("panel", StyleBoxEmpty.new())
			stack.add_theme_constant_override("separation", 0)
		special = DungeonReferencePages.new()
		stack.add_child(special)
		special.command.connect(func(kind, id, extra): command.emit(kind, id, extra))
		special.configure(self, rows, layout)
		_adapt.call_deferred()
		return
	detail_scroll.visible = layout in ["grid", "model"]
	if rows.is_empty(): rows_host.add_child(DungeonStyle.label("暂无可用项目"))
	if detail_scroll.visible:
		grid = GridContainer.new()
		grid.columns = 3 if layout == "grid" else 2
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		rows_host.add_child(grid)
		for index in rows.size():
			var row: Dictionary = rows[index]
			var choice = Button.new()
			choice.custom_minimum_size = Vector2(130, 84 if page_context.get("room_activity", false) and get_viewport_rect().size.y < 600 else 140)
			choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			choice.text = str(row.get("title", ""))
			choice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			choice.icon = _icon(row)
			choice.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			choice.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
			choice.expand_icon = true
			choice.add_theme_constant_override("icon_max_width", 42 if page_context.get("room_activity", false) and get_viewport_rect().size.y < 600 else 68)
			choice.add_theme_font_size_override("font_size", 17)
			choice.pressed.connect(func(): _select(index))
			grid.add_child(choice)
			_choices.append(choice)
		if not rows.is_empty(): _select(0)
	else:
		for row in rows: _row(rows_host, row)
	list_scroll.scroll_vertical = 0
	_adapt.call_deferred()

func _icon(row: Dictionary) -> Texture2D:
	var art = DungeonStyle.texture(str(row.get("icon", "")))
	return art if art else DungeonStyle.texture("menu_adventure")

func _select(index: int) -> void:
	_selected = index
	_clear(detail)
	for i in _choices.size():
		_choices[i].add_theme_stylebox_override("normal", DungeonStyle.box(Color("34494a") if i == index else Color("15262c"), DungeonStyle.GOLD if i == index else Color("455454")))
	var row: Dictionary = _rows[index]
	if not str(row.get("model", "")).is_empty():
		var preview = DungeonModelPreview.new()
		detail.add_child(preview)
		preview.show_model(str(row.model))
	else:
		var art_size := 48 if page_context.get("room_activity", false) and get_viewport_rect().size.y < 600 else 120
		var art = DungeonStyle.picture(str(row.get("icon", "menu_adventure")), Vector2(art_size, art_size))
		detail.add_child(art)
	_row(detail, row, false)
	detail_scroll.scroll_vertical = 0

func _row(parent: Control, row: Dictionary, separator := true) -> void:
	var compact = (page_context.get("camp", false) or page_context.get("room_activity", false)) and get_viewport_rect().size.y < 600
	var item = VBoxContainer.new()
	item.add_theme_constant_override("separation", 6 if compact else 10)
	parent.add_child(item)
	var heading = HBoxContainer.new()
	item.add_child(heading)
	if separator and not str(row.get("icon", "")).is_empty():
		var picture = DungeonStyle.picture(str(row.icon), Vector2(42, 42))
		if str(row.icon).begins_with("sprite_mosterwork_"):
			var backing = PanelContainer.new()
			var backing_style = DungeonStyle.box(Color("e7e9d5"), Color("a9b393"), 1)
			backing_style.set_content_margin_all(3)
			backing.add_theme_stylebox_override("panel", backing_style)
			backing.add_child(picture)
			heading.add_child(backing)
		else: heading.add_child(picture)
	var title = DungeonStyle.label(str(row.get("title", "")), 18 if compact else 22)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	if not str(row.get("description", "")).is_empty():
		var description = SourceRichText.new()
		description.add_theme_font_size_override("normal_font_size", 16 if compact else 18)
		description.add_theme_color_override("default_color", Color("b9c8c5"))
		description.set_source(str(row.get("source_description", row.description)))
		item.add_child(description)
	var commands = HFlowContainer.new()
	commands.add_theme_constant_override("h_separation", 10)
	commands.add_theme_constant_override("v_separation", 8)
	item.add_child(commands)
	for entry in row.get("buttons", []):
		var button = Button.new()
		button.text = str(entry.text)
		button.custom_minimum_size.y = 36 if compact else 46
		if compact: button.add_theme_font_size_override("font_size", 16)
		button.disabled = entry.get("disabled", false)
		button.pressed.connect(func(): command.emit(str(entry.action), entry.get("id", 0), entry.get("extra", 0)))
		commands.add_child(button)
	if row.get("commands_first", false): item.move_child(commands, 1)
	for entry in row.get("controls", []):
		if entry.get("type") == "slider":
			var slider = HSlider.new()
			slider.min_value = entry.get("min", 0)
			slider.max_value = entry.get("max", 1)
			slider.step = entry.get("step", 0.05)
			slider.value = entry.get("value", 1)
			slider.custom_minimum_size = Vector2(200, 44)
			slider.value_changed.connect(func(value): command.emit(str(entry.action), value, 0))
			item.add_child(slider)
		elif entry.get("type") == "toggle":
			var toggle = CheckButton.new()
			toggle.text = str(entry.get("text", ""))
			toggle.button_pressed = entry.get("value", true)
			toggle.toggled.connect(func(value): command.emit(str(entry.action), value, 0))
			item.add_child(toggle)
	if separator: item.add_child(HSeparator.new())

func _adapt() -> void:
	if _adapting: return
	_adapting = true
	var compact = size.x < 1000
	ROLE_NAVIGATION.configure_header_back_button(stack.get_child(0).get_child(0), size, "返回" if page_context.has("back_action") else "关闭")
	if (page_context.get("camp", false) or page_context.get("room_activity", false)) and _layout in ["list", "grid", "model"]:
		var style = DungeonStyle.box(Color("172d30"), DungeonStyle.GOLD, 2) if get_viewport_rect().size.y < 600 else DungeonStyle.panel().duplicate()
		style.set_content_margin_all(16 if get_viewport_rect().size.y < 600 else 62)
		add_theme_stylebox_override("panel", style)
		stack.add_theme_constant_override("separation", 8 if get_viewport_rect().size.y < 600 else 16)
	if stack.get_child(0).visible:
		var panel = get_theme_stylebox("panel")
		var header_margin = ROLE_NAVIGATION.header_margin(size)
		if not is_equal_approx(panel.get_content_margin(SIDE_LEFT), header_margin.x) or not is_equal_approx(panel.get_content_margin(SIDE_TOP), header_margin.y):
			panel = panel.duplicate()
			panel.set_content_margin(SIDE_LEFT, header_margin.x)
			panel.set_content_margin(SIDE_TOP, header_margin.y)
			add_theme_stylebox_override("panel", panel)
	resource_bar.add_theme_constant_override("separation", 6 if compact else 12)
	for line in resource_bar.get_children():
		line.custom_minimum_size.x = 74 if compact else 130
		for child in line.get_children():
			if child is Label: child.add_theme_font_size_override("font_size", 17 if compact else 22)
			if child is TextureRect: child.custom_minimum_size = Vector2(26, 26) if compact else Vector2(36, 36)
	title_label.add_theme_font_size_override("font_size", 22 if compact else 28)
	if is_instance_valid(grid): grid.columns = 2 if size.x < 1100 or _layout == "model" else 3
	if page_context.get("room_activity", false):
		var short_view := get_viewport_rect().size.y < 600
		for choice in _choices:
			choice.custom_minimum_size = Vector2(130, 84 if short_view else 140)
			choice.add_theme_constant_override("icon_max_width", 42 if short_view else 68)
		if detail.get_child_count() > 0 and detail.get_child(0) is TextureRect:
			var art_size := 48 if short_view else 120
			detail.get_child(0).custom_minimum_size = Vector2(art_size, art_size)
	if detail_scroll.visible:
		list_scroll.size_flags_stretch_ratio = 1.2 if size.x >= 1100 else 1.0
	_adapting = false

func release_route_view() -> void:
	if not is_instance_valid(route_view): return
	route_view.hide()
	stack.remove_child(route_view)
	route_view.queue_free()
	route_view = null

func displayed_row_count() -> int:
	if _layout == "dialogue" and is_instance_valid(dialogue_view): return 1
	return _rows.size()

func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
