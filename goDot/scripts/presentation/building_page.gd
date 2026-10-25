extends Control

signal command(kind: String, id: Variant, extra: Variant)
const PAPER := Color("faf9f6")
const INK := Color("604324")
var host: Control
var systems: RefCounted
var catalog: RefCounted
var canvas: Control
var board: NinePatchRect
var graph_frame: PanelContainer
var scroll: ScrollContainer
var graph: Control
var detail_frame: PanelContainer
var detail_title: Label
var detail_icon: TextureRect
var detail_text: Label
var detail_scroll: ScrollContainer
var cost_label: Label
var build_button: Button
var close_button: Button
var help_button: Button
var wood: TextureRect
var hammer: TextureRect
var title: Label
var nodes: Array[Dictionary] = []
var connectors: Array[TextureRect] = []
var selected_id := 2
var selected_stage := 0
var _logical_size := Vector2.ZERO

func configure(owner_page: Control, _rows: Array, context: Dictionary) -> void:
	host = owner_page
	systems = context.systems
	catalog = context.catalog
	selected_id = int(context.get("selected_id", 2))
	if selected_id <= 0: selected_id = 2
	selected_stage = mini(systems.rank(systems.profile.data.buildings, selected_id), 2)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas = Control.new()
	add_child(canvas)
	board = patch("几何ui-书页矩形花纹", 42)
	canvas.add_child(board)
	title = text("据点建设", 30, Color("f2bb4e"))
	title.add_theme_color_override("font_outline_color", Color("392818"))
	title.add_theme_constant_override("outline_size", 5)
	canvas.add_child(title)
	close_button = art_button("X", "关闭")
	close_button.pressed.connect(func(): command.emit("close_page", 0, 0))
	canvas.add_child(close_button)
	help_button = art_button("须知", "建设进度")
	help_button.pressed.connect(_show_progress)
	canvas.add_child(help_button)
	graph_frame = framed()
	canvas.add_child(graph_frame)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	graph_frame.add_child(scroll)
	graph = Control.new()
	scroll.add_child(graph)
	detail_frame = framed()
	canvas.add_child(detail_frame)
	var content = Control.new()
	detail_frame.add_child(content)
	var emblem = DungeonStyle.picture("bg装饰", Vector2.ZERO)
	emblem.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	emblem.position = Vector2(-120, 60)
	emblem.size = Vector2(240, 240)
	emblem.modulate = Color("ece8df")
	content.add_child(emblem)
	detail_title = text("", 28, Color("d99b28"))
	detail_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(detail_title)
	detail_icon = DungeonStyle.picture("", Vector2.ZERO)
	content.add_child(detail_icon)
	detail_scroll = ScrollContainer.new()
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(detail_scroll)
	detail_text = text("", 24, INK)
	detail_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.add_child(detail_text)
	cost_label = text("", 22, INK)
	cost_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(cost_label)
	build_button = Button.new()
	build_button.add_theme_font_size_override("font_size", 26)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style = DungeonStyle.box(Color("685749") if state != "disabled" else Color("d9d0c5"), Color("bdb3a7"), 3)
		style.set_corner_radius_all(24)
		build_button.add_theme_stylebox_override(state, style)
	build_button.pressed.connect(func(): command.emit("op:upgrade_building", selected_id, 0))
	content.add_child(build_button)
	wood = DungeonStyle.picture("wood", Vector2.ZERO)
	hammer = DungeonStyle.picture("hammer", Vector2.ZERO)
	canvas.add_child(wood)
	canvas.add_child(hammer)
	_build_nodes()
	resized.connect(_layout)
	_layout.call_deferred()
	select_stage(selected_id, selected_stage)

static func text(value: String, font_size: int, color: Color) -> Label:
	var label = DungeonStyle.label(value, font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	return label

static func patch(key: String, margin: int) -> NinePatchRect:
	var result = NinePatchRect.new()
	result.texture = DungeonStyle.texture(key)
	result.patch_margin_left = margin
	result.patch_margin_right = margin
	result.patch_margin_top = margin
	result.patch_margin_bottom = margin
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result

static func framed() -> PanelContainer:
	var panel = PanelContainer.new()
	var style = DungeonStyle.box(PAPER, Color("d9d6cd"), 2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	return panel

static func art_button(key: String, tooltip: String) -> Button:
	var result = Button.new()
	result.icon = DungeonStyle.texture(key)
	result.expand_icon = true
	result.tooltip_text = tooltip
	for state in ["normal", "hover", "pressed", "focus"]: result.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	return result

func _build_nodes() -> void:
	var buildings = catalog.rows("Buildings").duplicate()
	buildings.sort_custom(func(a, b): return int(a.sort_index) < int(b.sort_index))
	var row_index := 0
	for building in buildings:
		if int(building.max_level) <= 0: continue
		var level = systems.rank(systems.profile.data.buildings, building.id)
		var status = systems.building_status(int(building.id))
		for stage in int(building.max_level):
			if stage < 2:
				var line = DungeonStyle.picture("主城建造节点连接线", Vector2.ZERO)
				line.stretch_mode = TextureRect.STRETCH_SCALE
				line.set_meta("grid", Vector2i(stage, row_index))
				graph.add_child(line)
				connectors.append(line)
			var key = Button.new()
			key.tooltip_text = DungeonCatalog.clean(systems._part(building.name, stage))
			for state in ["normal", "hover", "pressed", "focus"]: key.add_theme_stylebox_override(state, StyleBoxEmpty.new())
			graph.add_child(key)
			var frame = DungeonStyle.picture("主城建造节点_已升级_v1" if stage < level else "主城建造节点_当前升级_v1" if stage == level else "主城建造节点_未达到_v1", Vector2.ZERO)
			frame.position = Vector2(10, 0)
			frame.size = Vector2(140, 140)
			key.add_child(frame)
			var known = stage <= level
			var icon = DungeonStyle.picture(systems._part(building.icon_name, stage), Vector2.ZERO)
			icon.position = Vector2(42, 32)
			icon.size = Vector2(76, 76)
			icon.visible = known
			key.add_child(icon)
			if stage >= level:
				var lock_icon = DungeonStyle.picture("锁", Vector2.ZERO)
				lock_icon.position = Vector2(62, 51)
				lock_icon.size = Vector2(36, 46)
				key.add_child(lock_icon)
			var plaque = patch("信息框底2", 14)
			plaque.position = Vector2(5, 120)
			plaque.size = Vector2(150, 44)
			key.add_child(plaque)
			var label = text(DungeonCatalog.clean(systems._part(building.name, stage)) if known else "？？？", 22, Color.WHITE)
			label.position = Vector2(8, 122)
			label.size = Vector2(144, 40)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			key.add_child(label)
			if stage == level and status.can_upgrade:
				var badge = DungeonStyle.picture("提示点", Vector2.ZERO)
				badge.position = Vector2(120, 12)
				badge.size = Vector2(24, 24)
				key.add_child(badge)
			var selection = DungeonStyle.picture("选择高亮", Vector2.ZERO)
			selection.position = Vector2(7, 7)
			selection.size = Vector2(146, 146)
			selection.modulate = Color(1, 0.9, 0.55, 0.65)
			key.add_child(selection)
			key.pressed.connect(func(): select_stage(int(building.id), stage))
			nodes.append({"id": int(building.id), "stage": stage, "row": row_index, "button": key, "selection": selection})
		row_index += 1

func select_stage(id: int, stage: int) -> void:
	selected_id = id
	selected_stage = stage
	host.page_context.selected_id = id
	var building = catalog.find("Buildings", id)
	var level = systems.rank(systems.profile.data.buildings, id)
	var status = systems.building_status(id)
	for node in nodes: node.selection.visible = node.id == id and node.stage == stage
	detail_title.text = DungeonCatalog.clean(systems._part(building.name, stage))
	detail_icon.texture = DungeonStyle.texture(systems._part(building.icon_name, stage))
	detail_text.text = DungeonCatalog.clean(systems._part(building.description, stage))
	var cost = systems.costs(systems._part(building.get("need_materials", ""), stage, ";"))
	cost["101"] = int(cost.get("101", 0)) + int(systems._part(building.need_gold, stage))
	cost_label.text = "" if stage < level else systems.price_description(cost)
	build_button.disabled = stage != level or not status.can_upgrade
	build_button.text = "已建造" if stage < level else "请先建设前级" if stage > level else "建造" if status.can_upgrade else "条件不足"
	if stage == level and not status.can_upgrade: detail_text.text += "\n\n" + DungeonCatalog.clean(status.reason)
	if stage > level: detail_text.text += "\n\n前置：" + DungeonCatalog.clean(systems._part(building.name, stage - 1))
	detail_scroll.scroll_vertical = 0

func _show_progress() -> void:
	var completed = 0
	for level in systems.profile.data.buildings.values(): completed += int(level)
	detail_title.text = "据点建设"
	detail_icon.texture = DungeonStyle.texture("icon_maincitybulid_blacksmith")
	detail_text.text = "建设进度：%d / 21\n\n金币：%d\n\n已探索迷宫：%d 次" % [completed, systems.material(101), systems.stat("runs")]
	cost_label.text = ""
	build_button.disabled = true
	build_button.text = "建设记录"

func _layout() -> void:
	if not is_instance_valid(canvas): return
	var factor = minf(1.0, minf(size.x / 1500.0, size.y / 700.0))
	canvas.scale = Vector2.ONE * factor
	_logical_size = size / maxf(0.1, factor)
	canvas.size = _logical_size
	board.position = Vector2(38, 30)
	board.size = _logical_size - Vector2(70, 65)
	title.position = Vector2(136, 68)
	close_button.position = Vector2(16, 10)
	close_button.size = Vector2(104, 104)
	help_button.position = Vector2(_logical_size.x - 114, 66)
	help_button.size = Vector2(48, 48)
	var width = _logical_size.x - 160
	graph_frame.position = Vector2(92, 126)
	graph_frame.size = Vector2(width * 0.73 - 20, _logical_size.y - 218)
	detail_frame.position = Vector2(graph_frame.position.x + graph_frame.size.x + 18, 126)
	detail_frame.size = Vector2(width * 0.27, graph_frame.size.y)
	var graph_width = graph_frame.size.x - 42
	graph.custom_minimum_size = Vector2(graph_width, 7 * 190 + 24)
	for node in nodes:
		node.button.position = Vector2(24 + float(node.stage) * (graph_width - 208) / 2.0, 12 + node.row * 190)
		node.button.size = Vector2(160, 170)
	for line in connectors:
		var grid: Vector2i = line.get_meta("grid")
		line.position = Vector2(104 + grid.x * (graph_width - 208) / 2.0, 81 + grid.y * 190)
		line.size = Vector2((graph_width - 208) / 2.0, 5)
	var inner = detail_frame.size - Vector2(24, 24)
	detail_title.position = Vector2(12, 20)
	detail_title.size = Vector2(inner.x - 24, 68)
	detail_icon.position = Vector2((inner.x - 110) / 2, 104)
	detail_icon.size = Vector2(110, 110)
	detail_scroll.position = Vector2(18, 242)
	detail_scroll.size = Vector2(inner.x - 36, maxf(90, inner.y - 366))
	cost_label.position = Vector2(14, inner.y - 104)
	cost_label.size = Vector2(inner.x - 28, 44)
	build_button.position = Vector2(30, inner.y - 58)
	build_button.size = Vector2(inner.x - 60, 46)
	wood.position = Vector2(-18, _logical_size.y - 200)
	wood.size = Vector2(218, 218)
	hammer.position = Vector2(_logical_size.x - 144, _logical_size.y - 218)
	hammer.size = Vector2(166, 240)
