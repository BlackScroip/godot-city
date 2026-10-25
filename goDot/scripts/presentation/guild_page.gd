class_name DungeonGuildPage
extends Control

signal command(kind: String, id: Variant, extra: Variant)

class BranchCanvas extends Control:
	var branches: Array = []
	func _draw() -> void:
		for branch in branches:
			var a: Vector2 = branch.from
			var b: Vector2 = branch.to
			var middle = (a.x + b.x) * 0.5
			draw_polyline(PackedVector2Array([a, Vector2(middle, a.y), Vector2(middle, b.y), b]), Color("f7d480") if branch.active else Color("b6b3a6"), 3.0, true)

class NodeBadge extends Control:
	var locked = false
	var actionable = false
	var lock_texture: Texture2D
	var dot_texture: Texture2D
	func _draw() -> void:
		if locked:
			var center = size * 0.5
			if lock_texture:
				draw_texture_rect(lock_texture, Rect2(center - Vector2(14, 16), Vector2(28, 32)), false)
			else:
				draw_circle(center, 16, Color(0.08, 0.12, 0.15, 0.85))
				draw_arc(center + Vector2(0, -3), 6, PI, TAU, 14, Color("e4e7df"), 3, true)
				draw_rect(Rect2(center + Vector2(-8, -2), Vector2(16, 12)), Color("e4e7df"))
		if actionable:
			if dot_texture: draw_texture_rect(dot_texture, Rect2(Vector2(size.x - 12, -4), Vector2(16, 16)), false)
			else:
				draw_circle(Vector2(size.x - 4, 4), 7, Color("f16654"))
				draw_circle(Vector2(size.x - 4, 4), 7, Color("ffddae"), false, 1.5, true)

const INK = Color("453e36")
var systems
var catalog
var selected_category = 1
var selected_talent = 0
var node_buttons: Dictionary = {}
var category_buttons: Dictionary = {}
var graph_scroll: ScrollContainer
var detail_scroll: ScrollContainer
var upgrade_button: Button
var graph: BranchCanvas
var detail: VBoxContainer
var _body: HBoxContainer
var _tabs: VBoxContainer
var _detail_panel: PanelContainer
var _context: Dictionary = {}
var _nodes: Array = []
var _compact = false
var _node_size = Vector2(72, 72)
var _graph_content_height = 0.0
var _graph_offset_y = 0.0

func configure(_host: DungeonMenuPage, _rows: Array, context: Dictionary) -> void:
	systems = context.get("systems")
	catalog = context.get("catalog")
	_context = context
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	if systems == null or catalog == null: return
	selected_category = clampi(int(context.get("category", 1)), 1, 3)
	selected_talent = int(context.get("selected_talent", 0))
	resized.connect(_adapt)
	_build()

func _flat(color: Color, border: Color = Color.TRANSPARENT, margin: int = 8) -> StyleBoxFlat:
	var style = DungeonStyle.box(color, border, 2)
	style.set_content_margin_all(margin)
	style.set_corner_radius_all(2)
	return style

func _skin(key: String, edges: Vector4 = Vector4(16, 16, 16, 16), tint: Color = Color.WHITE, margin: int = 8) -> StyleBox:
	var texture = DungeonStyle.texture(key)
	if texture == null: return _flat(Color("eeeadd") * tint, Color("bcb59e"), margin)
	var style = StyleBoxTexture.new()
	style.texture = texture
	style.texture_margin_left = edges.x
	style.texture_margin_top = edges.y
	style.texture_margin_right = edges.z
	style.texture_margin_bottom = edges.w
	style.modulate_color = tint
	style.set_content_margin_all(margin)
	return style

func _label(value: String, font_size: int = 18, color: Color = INK) -> Label:
	var label = DungeonStyle.label(value, font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _build() -> void:
	for child in get_children(): remove_child(child); child.queue_free()
	node_buttons.clear()
	category_buttons.clear()
	_compact = size.y > 0 and (size.y < 500 or size.x < 1000)
	_node_size = Vector2(52, 52) if _compact else Vector2(76, 76)
	_body = HBoxContainer.new()
	_body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_body.add_theme_constant_override("separation", 8 if _compact else 16)
	add_child(_body)
	_tabs = VBoxContainer.new()
	_tabs.custom_minimum_size.x = 72 if _compact else 130
	_tabs.add_theme_constant_override("separation", 10 if _compact else 18)
	_body.add_child(_tabs)
	var categories = [{"id": 1, "name": "冒险", "color": Color("7595a8"), "icon": "sprite_talenttree_10001"}, {"id": 2, "name": "战斗", "color": Color("9b7d79"), "icon": "sprite_talenttree_20001"}, {"id": 3, "name": "生存", "color": Color("7f9c7e"), "icon": "sprite_talenttree_30001"}]
	for category in categories:
		var button = Button.new()
		button.text = category.name
		button.custom_minimum_size.y = 62 if _compact else 100
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.add_theme_font_size_override("font_size", 13 if _compact else 19)
		button.add_theme_color_override("font_color", INK)
		button.icon = DungeonStyle.texture(category.icon)
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		button.add_theme_constant_override("icon_max_width", 26 if _compact else 43)
		for state in ["normal", "hover", "pressed"]:
			button.add_theme_stylebox_override(state, _skin("几何ui-书页矩形花纹" if int(category.id) == selected_category else "几何ui-书页矩形", Vector4(12, 12, 12, 12), Color("fff0c9") if int(category.id) == selected_category else Color("d0d0c5"), 4))
		button.pressed.connect(func(): select_category(int(category.id)))
		_tabs.add_child(button)
		category_buttons[int(category.id)] = button
	var graph_background = PanelContainer.new()
	graph_background.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graph_background.add_theme_stylebox_override("panel", _skin("几何ui-书页矩形", Vector4(18, 18, 18, 18), Color("c8c9bb"), 4))
	_body.add_child(graph_background)
	graph_scroll = ScrollContainer.new()
	graph_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graph_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	graph_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	graph_background.add_child(graph_scroll)
	graph = BranchCanvas.new()
	graph.mouse_filter = Control.MOUSE_FILTER_PASS
	graph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	graph_scroll.add_child(graph)
	_detail_panel = PanelContainer.new()
	_detail_panel.custom_minimum_size.x = 208 if _compact else 310
	_detail_panel.add_theme_stylebox_override("panel", _skin("几何ui-书页矩形花纹", Vector4(24, 24, 24, 24), Color.WHITE, 12 if _compact else 24))
	_body.add_child(_detail_panel)
	detail_scroll = ScrollContainer.new()
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail_panel.add_child(detail_scroll)
	detail = VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 7 if _compact else 13)
	detail_scroll.add_child(detail)
	_build_graph()
	graph_scroll.resized.connect(_center_graph)
	_center_graph.call_deferred()
	_show_detail()

func _build_graph() -> void:
	_nodes = catalog.rows("TalentTreeData").filter(func(row): return int(row.talent_type) == selected_category)
	if not _nodes.any(func(row): return int(row.id) == selected_talent) and not _nodes.is_empty(): selected_talent = int(_nodes[0].id)
	_context["category"] = selected_category
	_context["selected_talent"] = selected_talent
	var points: Dictionary = {}
	var x_step = 112 if _compact else 160
	var y_step = 86 if _compact else 135
	var maximum_column = 1
	for row in _nodes:
		var index = int(row.index)
		var column = int(index / 10)
		var lane = index % 10
		maximum_column = maxi(maximum_column, column)
		points[int(row.id)] = Vector2(24 + (column - 1) * x_step, 20 + (lane - 1) * y_step)
	_graph_content_height = y_step * 2 + _node_size.y + 55
	_graph_offset_y = 0.0
	graph.custom_minimum_size = Vector2(maximum_column * x_step + 24, _graph_content_height)
	for row in _nodes:
		var id = int(row.id)
		var status = systems.global_talent_status(id)
		var prerequisites_ready = true
		for parent in DungeonCatalog.ids(row.parent_id_list):
			var active = systems.rank(systems.profile.data.talents, parent) > 0
			prerequisites_ready = prerequisites_ready and active
			if points.has(parent): graph.branches.append({"from": points[parent] + Vector2(_node_size.x, _node_size.y * 0.5), "to": points[id] + Vector2(0, _node_size.y * 0.5), "active": active})
		var button = Button.new()
		button.position = points[id]
		button.size = _node_size
		button.custom_minimum_size = _node_size
		button.icon = DungeonStyle.texture(str(row.icon))
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", int(_node_size.x) - 12)
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.tooltip_text = "%s\nLv.%d / %d\n%s" % [DungeonCatalog.row_name(row), int(status.level), int(status.max_level), str(status.reason)]
		button.pressed.connect(func(): select_talent(id))
		graph.add_child(button)
		node_buttons[id] = button
		_style_node(button, id, int(status.level), prerequisites_ready)
		var badge = NodeBadge.new()
		badge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.locked = not prerequisites_ready
		badge.actionable = status.can_upgrade
		badge.lock_texture = DungeonStyle.texture("锁头")
		badge.dot_texture = DungeonStyle.texture("提示点")
		button.add_child(badge)
		var stars = HBoxContainer.new()
		stars.alignment = BoxContainer.ALIGNMENT_CENTER
		stars.add_theme_constant_override("separation", 1)
		stars.position = points[id] + Vector2(-6, _node_size.y + 2)
		stars.size = Vector2(_node_size.x + 12, 22)
		graph.add_child(stars)
		for star in clampi(int(row.get("star_num", 1)), 1, 5):
			stars.add_child(DungeonStyle.picture("星星大" if int(status.level) > 0 else "星星底", Vector2(11, 11) if _compact else Vector2(16, 16)))
	graph.queue_redraw()

func _center_graph() -> void:
	if not is_instance_valid(graph_scroll) or not is_instance_valid(graph): return
	var height = maxf(_graph_content_height, graph_scroll.size.y - 12)
	var offset = maxf(0.0, (height - _graph_content_height) * 0.5)
	var delta = offset - _graph_offset_y
	graph.custom_minimum_size.y = height
	if absf(delta) < 0.5: return
	_graph_offset_y = offset
	for child in graph.get_children():
		if child is Control: child.position.y += delta
	for branch in graph.branches:
		branch.from.y += delta
		branch.to.y += delta
	graph.queue_redraw()

func _style_node(button: Button, id: int, level: int, unlocked: bool) -> void:
	for state in ["normal", "hover", "pressed"]:
		button.add_theme_stylebox_override(state, _skin("40_1" if id == selected_talent or level > 0 else "slotfg_rare_square_1_v2", Vector4(12, 12, 12, 12), Color.WHITE if unlocked else Color("969990"), 5))
	button.add_theme_stylebox_override("focus", _flat(Color.TRANSPARENT, Color("ffe49a"), 0))
	button.add_theme_color_override("icon_normal_color", Color.WHITE if unlocked else Color(0.6, 0.6, 0.6, 1))

func _show_detail() -> void:
	for child in detail.get_children(): detail.remove_child(child); child.queue_free()
	var row = catalog.find("TalentTreeData", selected_talent)
	if row.is_empty(): return
	var status = systems.global_talent_status(selected_talent)
	var heading = HBoxContainer.new()
	detail.add_child(heading)
	heading.add_child(DungeonStyle.picture(str(row.icon), Vector2(38, 38) if _compact else Vector2(68, 68)))
	var title = _label(DungeonCatalog.row_name(row), 18 if _compact else 25)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	detail.add_child(_label("等级 %d / %d" % [int(status.level), int(status.max_level)], 13 if _compact else 17, Color("627668")))
	var level_ids = DungeonCatalog.ids(row.level_data_id_list)
	if int(status.level) > 0:
		var current = catalog.find("TalentTreeLevelData", level_ids[int(status.level) - 1])
		detail.add_child(_label("当前效果", 14 if _compact else 18, Color("55806b")))
		detail.add_child(_label(DungeonCatalog.clean(DungeonCatalog.description(current)), 13 if _compact else 17))
	if int(status.level) < level_ids.size():
		var next = catalog.find("TalentTreeLevelData", level_ids[int(status.level)])
		detail.add_child(_label("下级效果", 14 if _compact else 18, Color("7e6743")))
		detail.add_child(_label(DungeonCatalog.clean(DungeonCatalog.description(next)), 13 if _compact else 17))
	var parents = DungeonCatalog.ids(row.parent_id_list)
	if not parents.is_empty():
		var names: Array[String] = []
		for parent in parents: names.append(DungeonCatalog.row_name(catalog.find("TalentTreeData", parent)))
		detail.add_child(_label("前置：" + "、".join(names), 12 if _compact else 15, Color("6e7168")))
	for material_id in status.price:
		if int(status.price[material_id]) <= 0: continue
		var cost = HBoxContainer.new()
		detail.add_child(cost)
		var icon = "sprite_materialicon_" + str(material_id)
		if DungeonStyle.texture(icon) == null: icon = "material:" + str(material_id)
		cost.add_child(DungeonStyle.picture(icon, Vector2(24, 24) if _compact else Vector2(32, 32)))
		var owned = systems.material(int(material_id))
		var amount = _label("%d / %d" % [owned, int(status.price[material_id])], 14 if _compact else 18, Color("597b53") if owned >= int(status.price[material_id]) else Color("ad5c47"))
		amount.autowrap_mode = TextServer.AUTOWRAP_OFF
		amount.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cost.add_child(amount)
	if not str(status.reason).is_empty(): detail.add_child(_label(str(status.reason), 12 if _compact else 15, Color("91604d")))
	upgrade_button = Button.new()
	upgrade_button.text = "已满级" if int(status.level) >= int(status.max_level) else "升级" if int(status.level) > 0 else "解锁"
	upgrade_button.disabled = not status.can_upgrade
	upgrade_button.custom_minimum_size.y = 36 if _compact else 48
	upgrade_button.add_theme_font_size_override("font_size", 15 if _compact else 20)
	upgrade_button.add_theme_color_override("font_color", INK)
	upgrade_button.add_theme_color_override("font_disabled_color", Color("3f5045"))
	for state in ["normal", "hover", "pressed", "disabled"]:
		upgrade_button.add_theme_stylebox_override(state, _skin("商店按钮_底", Vector4(32, 12, 32, 12), Color("a7aba5") if state == "disabled" else Color.WHITE, 6))
	upgrade_button.pressed.connect(func(): command.emit("op:upgrade_global_talent", selected_talent, 0))
	detail.add_child(upgrade_button)
	detail_scroll.scroll_vertical = 0

func select_talent(id: int) -> void:
	if not node_buttons.has(id): return
	selected_talent = id
	_context["selected_talent"] = id
	for row in _nodes:
		var unlocked = true
		for parent in DungeonCatalog.ids(row.parent_id_list): unlocked = unlocked and systems.rank(systems.profile.data.talents, parent) > 0
		_style_node(node_buttons[int(row.id)], int(row.id), systems.rank(systems.profile.data.talents, row.id), unlocked)
	_show_detail()

func select_category(category: int) -> void:
	selected_category = clampi(category, 1, 3)
	_context["category"] = selected_category
	selected_talent = 0
	_build()

func refresh() -> void:
	if systems == null: return
	var scroll_x = graph_scroll.scroll_horizontal if is_instance_valid(graph_scroll) else 0
	_build()
	graph_scroll.set_deferred("scroll_horizontal", scroll_x)

func _adapt() -> void:
	if systems == null or size.x <= 0 or size.y <= 0: return
	var compact = size.y < 500 or size.x < 1000
	if compact != _compact: _build()
