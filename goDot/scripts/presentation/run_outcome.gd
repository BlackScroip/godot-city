extends Control

signal command(kind: String, id: Variant, extra: Variant)
var stage: Control
var header: Control
var title: Label
var portrait: TextureRect
var talents: VBoxContainer
var relics: VBoxContainer
var statistics: VBoxContainer
var rewards: VBoxContainer
var confirm: Button
var experience_bar: ProgressBar
var _grids: Array[GridContainer] = []
var _context: Dictionary

const GOLD = Color("d3bd85")
const ICE = Color("c3e6f5")
const GRADES = [Color("a9b4b7"), Color("64a9dc"), Color("d15ce0"), Color("f0cb69"), Color("ef9863")]

func configure(context: Dictionary) -> void:
	_context = context
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL
	if context.get("pending", false):
		_pending(context)
		return
	var shade = ColorRect.new()
	shade.color = Color("191314")
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(shade)
	stage = Control.new()
	add_child(stage)
	header = Control.new()
	stage.add_child(header)
	header.draw.connect(_draw_header)
	title = DungeonStyle.label(str(context.get("title", "战斗失败")), 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 38)
	title.size = Vector2(440, 80)
	title.add_theme_color_override("font_color", GOLD if context.get("victory", false) else ICE)
	title.add_theme_color_override("font_shadow_color", Color("426d85"))
	title.add_theme_constant_override("shadow_outline_size", 8)
	header.add_child(title)
	if context.get("stage", "summary") == "rewards":
		_build_rewards()
	else:
		talents = _collection("角色天赋", context.get("talents", []), "未获得角色天赋")
		relics = _collection("获得遗物", context.get("relics", []), "未获得遗物")
		_build_statistics()
	confirm = Button.new()
	confirm.text = str(context.get("button", "下一步"))
	confirm.add_theme_font_size_override("font_size", 28)
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		confirm.add_theme_color_override(state, Color("332e33"))
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style = DungeonStyle.box(Color("e9e7e6") if state != "pressed" else Color("babfc6"), Color("99959e"), 2)
		style.set_corner_radius_all(28)
		confirm.add_theme_stylebox_override(state, style)
	confirm.visible = not context.get("pending", false)
	confirm.pressed.connect(func():
		confirm.disabled = true
		command.emit(str(context.get("action", "")), 0, 0))
	stage.add_child(confirm)
	resized.connect(_layout)
	_layout.call_deferred()

func _draw_header() -> void:
	var color = GOLD if _context.get("victory", false) else ICE
	var muted = Color(color, 0.35)
	header.draw_arc(Vector2(220, 82), 72, PI, TAU, 48, muted, 1.5, true)
	header.draw_arc(Vector2(220, 82), 61, PI, TAU, 48, muted, 1.0, true)
	header.draw_colored_polygon(PackedVector2Array([Vector2(220, 0), Vector2(226, 18), Vector2(244, 24), Vector2(226, 30), Vector2(220, 48), Vector2(214, 30), Vector2(196, 24), Vector2(214, 18)]), Color(color, 0.75))
	header.draw_line(Vector2(25, 124), Vector2(415, 124), color, 2, true)
	for side in [-1, 1]:
		var points = PackedVector2Array()
		for point in [Vector2(150, 124), Vector2(173, 116), Vector2(190, 118), Vector2(201, 132), Vector2(213, 134), Vector2(219, 126), Vector2(215, 115)]:
			points.append(Vector2(220 + point.x * side, point.y))
		header.draw_polyline(points, color, 2, true)

func _pending(context: Dictionary) -> void:
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(center)
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	center.add_child(column)
	portrait = DungeonStyle.picture(str(context.get("portrait", "")), Vector2(80, 80))
	column.add_child(portrait)
	title = DungeonStyle.label(str(context.get("title", "")), 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var subtitle = DungeonStyle.label(str(context.get("subtitle", "")), 20)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(subtitle)

func _section(parent: Control, text: String) -> void:
	var band = PanelContainer.new()
	var style = DungeonStyle.box(Color(0, 0, 0, 0.38))
	style.set_content_margin_all(9)
	band.add_theme_stylebox_override("panel", style)
	parent.add_child(band)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 13)
	band.add_child(row)
	var diamond = Control.new()
	diamond.custom_minimum_size = Vector2(20, 20)
	diamond.size_flags_vertical = SIZE_SHRINK_CENTER
	var shape = Polygon2D.new()
	shape.polygon = PackedVector2Array([Vector2(10, 0), Vector2(20, 10), Vector2(10, 20), Vector2(0, 10)])
	shape.color = GOLD
	diamond.add_child(shape)
	row.add_child(diamond)
	var label = DungeonStyle.label(text, 23)
	label.modulate = GOLD
	row.add_child(label)

func _collection(text: String, items: Array, empty_text: String) -> VBoxContainer:
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	stage.add_child(column)
	_section(column, text)
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	column.add_child(scroll)
	if items.is_empty():
		var empty = DungeonStyle.label(empty_text, 20)
		empty.modulate = Color("948d8c")
		scroll.add_child(empty)
	else:
		var grid = GridContainer.new()
		grid.size_flags_horizontal = SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 14)
		scroll.add_child(grid)
		_grids.append(grid)
		for item in items: _item(grid, item)
	return column

func _item(parent: Control, item: Dictionary) -> void:
	var tile = Panel.new()
	tile.custom_minimum_size = Vector2(92, 96)
	var grade = clampi(int(item.get("grade", 1)) - 1, 0, GRADES.size() - 1)
	var color: Color = GRADES[grade]
	var style = DungeonStyle.box(Color(color.r * 0.25, color.g * 0.25, color.b * 0.25), color, 2)
	style.set_corner_radius_all(7)
	if grade > 0:
		style.shadow_color = Color(color, 0.2)
		style.shadow_size = 7
	tile.add_theme_stylebox_override("panel", style)
	tile.tooltip_text = str(item.get("name", ""))
	parent.add_child(tile)
	var icon = DungeonStyle.picture(str(item.get("icon", "")), Vector2.ZERO)
	icon.position = Vector2(9, 6)
	icon.size = Vector2(74, 74)
	tile.add_child(icon)
	var count = DungeonStyle.label(str(item.get("count_text", item.get("count", ""))), 19)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.position = Vector2(2, 71)
	count.size = Vector2(88, 23)
	count.add_theme_constant_override("outline_size", 4)
	count.add_theme_color_override("font_outline_color", Color("181619"))
	if item.get("talent", false): count.modulate = GOLD
	tile.add_child(count)

func _build_statistics() -> void:
	statistics = VBoxContainer.new()
	statistics.add_theme_constant_override("separation", 12)
	stage.add_child(statistics)
	_section(statistics, "用时")
	var elapsed = maxi(0, int(_context.get("elapsed", 0)))
	var clock = DungeonStyle.label("%02d:%02d:%02d" % [elapsed / 3600, elapsed / 60 % 60, elapsed % 60], 40)
	clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clock.modulate = Color("ffa724")
	statistics.add_child(clock)
	_section(statistics, "数据统计")
	var table = GridContainer.new()
	table.columns = 2
	table.add_theme_constant_override("h_separation", 18)
	table.add_theme_constant_override("v_separation", 9)
	statistics.add_child(table)
	for entry in _context.get("statistics", []):
		var key = DungeonStyle.label(str(entry[0]), 21)
		key.size_flags_horizontal = SIZE_EXPAND_FILL
		table.add_child(key)
		var value = DungeonStyle.label(str(entry[1]), 21)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		table.add_child(value)

func _build_rewards() -> void:
	portrait = DungeonStyle.picture(str(_context.get("portrait", "")), Vector2.ZERO)
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.modulate = Color(0.8, 0.8, 0.8)
	stage.add_child(portrait)
	rewards = VBoxContainer.new()
	rewards.add_theme_constant_override("separation", 16)
	stage.add_child(rewards)
	var row = HBoxContainer.new()
	rewards.add_child(row)
	var caption = DungeonStyle.label("经验值转化冒险凭证", 25)
	caption.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(caption)
	var amount = DungeonStyle.label(str(int(_context.get("effective_experience", 0))), 24)
	amount.modulate = GOLD
	row.add_child(amount)
	experience_bar = ProgressBar.new()
	experience_bar.custom_minimum_size.y = 12
	experience_bar.show_percentage = false
	experience_bar.max_value = maxf(1.0, float(_context.get("conversion_capacity", 100)))
	experience_bar.value = 0
	experience_bar.add_theme_stylebox_override("background", DungeonStyle.box(Color("0d0c0c"), Color("514534")))
	experience_bar.add_theme_stylebox_override("fill", DungeonStyle.box(Color("d9b75e")))
	rewards.add_child(experience_bar)
	create_tween().tween_property(experience_bar, "value", float(_context.get("effective_experience", 0)), 0.65).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var voucher = HBoxContainer.new()
	voucher.add_child(DungeonStyle.picture("sprite_materialicon_501", Vector2(30, 30)))
	voucher.add_child(DungeonStyle.label("冒险凭证 × %d" % int(_context.get("vouchers", 0)), 21))
	rewards.add_child(voucher)
	var collection = _collection("此次冒险获得", _context.get("rewards", []), "此次冒险未获得材料")
	stage.remove_child(collection)
	rewards.add_child(collection)
	collection.size_flags_vertical = SIZE_EXPAND_FILL
	if int(_context.get("work_minutes", 0)) > 0:
		var work = DungeonStyle.label("伙伴派遣推进 %d 分钟" % int(_context.work_minutes), 19)
		work.modulate = GOLD
		rewards.add_child(work)

func _layout() -> void:
	if not is_instance_valid(stage) or size.x <= 0 or size.y <= 0: return
	var factor = minf(size.x / 1600.0, size.y / 720.0)
	stage.scale = Vector2.ONE * factor
	stage.size = size / factor
	var w = stage.size.x
	var h = stage.size.y
	var is_rewards = is_instance_valid(rewards)
	header.position = Vector2(w * (0.36 if is_rewards else 0.5) - 220, 20)
	header.size = Vector2(440, 140)
	confirm.position = Vector2(w - 350, h - 105)
	confirm.size = Vector2(280, 64)
	if is_rewards:
		portrait.position = Vector2(w * 0.64, -h * 0.08)
		portrait.size = Vector2(w * 0.36, h * 1.12)
		rewards.position = Vector2(w * 0.09, 205)
		rewards.size = Vector2(w * 0.49, h - 285)
	else:
		var left_width = w * 0.68 - 100
		talents.position = Vector2(70, 180)
		talents.size = Vector2(left_width, h * 0.34)
		relics.position = Vector2(70, h * 0.60)
		relics.size = Vector2(left_width, h * 0.32)
		statistics.position = Vector2(w * 0.76, 170)
		statistics.size = Vector2(w * 0.24 - 70, h - 300)
	for grid in _grids:
		grid.columns = maxi(1, int((w * 0.49 if is_rewards else w * 0.68 - 116) / 104.0))
