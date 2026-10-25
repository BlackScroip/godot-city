class_name DungeonMenuPage
extends PanelContainer

signal command(kind: String, id: Variant, extra: Variant)
signal closed
signal back_requested
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
var page_context: Dictionary = {}

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
	var back = Button.new()
	back.text = "‹"
	back.tooltip_text = "返回营地菜单"
	back.custom_minimum_size = Vector2(48, 48)
	back.pressed.connect(func(): back_requested.emit())
	heading.add_child(back)
	title_label = DungeonStyle.label("", 28)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title_label)
	resource_bar = HBoxContainer.new()
	resource_bar.add_theme_constant_override("separation", 12)
	heading.add_child(resource_bar)
	var close = Button.new()
	close.text = "×"
	close.tooltip_text = "关闭"
	close.custom_minimum_size = Vector2(48, 48)
	close.pressed.connect(func(): closed.emit())
	heading.add_child(close)
	stack.add_child(HSeparator.new())
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
	page_context = context
	_clear(resource_bar)
	for resource in context.get("resources", []):
		var line = HBoxContainer.new()
		line.custom_minimum_size.x = 130
		resource_bar.add_child(line)
		line.add_child(DungeonStyle.picture(str(resource[0]), Vector2(36, 36)))
		line.add_child(DungeonStyle.label(str(resource[1]), 22))
	title_label.text = title
	_rows = rows
	_layout = layout
	_choices.clear()
	_clear(rows_host)
	_clear(detail)
	if is_instance_valid(outcome_view):
		stack.remove_child(outcome_view)
		outcome_view.queue_free()
		outcome_view = null
	if is_instance_valid(route_view):
		stack.remove_child(route_view)
		route_view.queue_free()
		route_view = null
	if is_instance_valid(special):
		stack.remove_child(special)
		special.queue_free()
		special = null
	stack.get_child(0).visible = layout not in ["route", "outcome"]
	stack.get_child(1).visible = layout not in ["route", "outcome"]
	stack.add_theme_constant_override("separation", 0 if layout in ["route", "outcome"] else 16)
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
	var specialized = layout in ["inventory", "altar", "talent", "character", "weapon", "settings", "tree", "awakening", "buildings", "route", "prepare", "shop"]
	backdrop.visible = layout in ["inventory", "character", "weapon", "awakening"]
	add_theme_stylebox_override("panel", DungeonStyle.box(Color(0.03, 0.06, 0.06, 0.2)) if backdrop.visible or layout in ["settings", "route", "shop"] else DungeonStyle.panel())
	if layout == "altar": add_theme_stylebox_override("panel", DungeonStyle.box(Color("291f1e")))
	if layout in ["tree", "buildings", "prepare"]:
		var paper = DungeonStyle.box(Color("eae6da"), DungeonStyle.GOLD, 3)
		paper.set_content_margin_all(28)
		add_theme_stylebox_override("panel", paper)
		title_label.add_theme_color_override("font_color", Color("5b4933"))
	else: title_label.add_theme_color_override("font_color", DungeonStyle.TEXT)
	body.visible = not specialized
	if specialized:
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
			choice.custom_minimum_size = Vector2(130, 140)
			choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			choice.text = str(row.get("title", ""))
			choice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			choice.icon = _icon(row)
			choice.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			choice.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
			choice.expand_icon = true
			choice.add_theme_constant_override("icon_max_width", 68)
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
		var art = DungeonStyle.picture(str(row.get("icon", "menu_adventure")), Vector2(120, 120))
		detail.add_child(art)
	_row(detail, row, false)
	detail_scroll.scroll_vertical = 0

func _row(parent: Control, row: Dictionary, separator := true) -> void:
	var item = VBoxContainer.new()
	item.add_theme_constant_override("separation", 10)
	parent.add_child(item)
	var heading = HBoxContainer.new()
	item.add_child(heading)
	if separator and not str(row.get("icon", "")).is_empty(): heading.add_child(DungeonStyle.picture(str(row.icon), Vector2(42, 42)))
	var title = DungeonStyle.label(str(row.get("title", "")), 22)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	if not str(row.get("description", "")).is_empty():
		var description = DungeonStyle.label(str(row.description), 18)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.modulate = Color("b9c8c5")
		item.add_child(description)
	var commands = HFlowContainer.new()
	commands.add_theme_constant_override("h_separation", 10)
	commands.add_theme_constant_override("v_separation", 8)
	item.add_child(commands)
	for entry in row.get("buttons", []):
		var button = Button.new()
		button.text = str(entry.text)
		button.custom_minimum_size.y = 46
		button.disabled = entry.get("disabled", false)
		button.pressed.connect(func(): command.emit(str(entry.action), entry.get("id", 0), entry.get("extra", 0)))
		commands.add_child(button)
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
	var compact = size.x < 1000
	resource_bar.add_theme_constant_override("separation", 6 if compact else 12)
	for line in resource_bar.get_children():
		line.custom_minimum_size.x = 74 if compact else 130
		for child in line.get_children():
			if child is Label: child.add_theme_font_size_override("font_size", 17 if compact else 22)
			if child is TextureRect: child.custom_minimum_size = Vector2(26, 26) if compact else Vector2(36, 36)
	title_label.add_theme_font_size_override("font_size", 22 if compact else 28)
	if is_instance_valid(grid): grid.columns = 2 if size.x < 1100 or _layout == "model" else 3
	if detail_scroll.visible:
		list_scroll.size_flags_stretch_ratio = 1.2 if size.x >= 1100 else 1.0

func displayed_row_count() -> int:
	return _rows.size()

func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
