class_name DungeonRoutePage
extends Control

signal command(kind: String, id: Variant, extra: Variant)
signal back_requested
var rows: Array = []
var context: Dictionary = {}
var scroll: ScrollContainer
var graph: Control
var confirm: Button
var automatic: CheckBox
var header: HBoxContainer
var footer: HBoxContainer
var nodes: Array[DungeonRouteNode] = []
var origin: DungeonRouteNode
var selected_id := 0
var selected_index := -1
var edges: Array = []
var column_width := 310.0
var node_size := Vector2(180, 88)

func configure(data: Array, details: Dictionary) -> void:
	rows = data
	context = details
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var background = ColorRect.new()
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shader = Shader.new()
	shader.code = """shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
void fragment() {
 vec3 col = textureLod(screen_texture, SCREEN_UV, 4.0).rgb;
 COLOR = vec4(col * vec3(0.24, 0.30, 0.27) + vec3(0.008, 0.012, 0.014), 1.0);
}"""
	var material = ShaderMaterial.new()
	material.shader = shader
	background.material = material
	add_child(background)
	header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 18)
	add_child(header)
	var back = Button.new()
	back.custom_minimum_size = Vector2(68, 58)
	back.tooltip_text = "返回"
	for state in ["normal", "hover", "pressed", "focus"]: back.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	back.draw.connect(func():
		var points = PackedVector2Array([Vector2(54, 7), Vector2(12, 29), Vector2(54, 51), Vector2(44, 34), Vector2(65, 34), Vector2(65, 24), Vector2(44, 24), Vector2(54, 7)])
		back.draw_colored_polygon(points, Color("e6d8a8"))
		back.draw_polyline(points, Color("907947"), 2, true))
	back.pressed.connect(func(): back_requested.emit())
	header.add_child(back)
	var title = DungeonStyle.label("区域路线" if context.get("preview", false) else "选择路线", 30)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(title)
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var counters = VBoxContainer.new()
	counters.add_theme_constant_override("separation", 8)
	header.add_child(counters)
	_counter(counters, "魔力精华", str(context.get("magic", 0)), Color("4898ee"))
	_counter(counters, "刻印圣典", "%d/%d" % [int(context.get("search", 0)), int(context.get("search_max", 3))], Color("7fdf6a"))
	scroll = ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(scroll)
	graph = Control.new()
	graph.mouse_filter = Control.MOUSE_FILTER_PASS
	graph.draw.connect(_draw_paths)
	scroll.add_child(graph)
	origin = DungeonRouteNode.new()
	origin.portrait = DungeonStyle.texture(str(context.get("portrait", "sprite_cardicon_square_jiannan")))
	origin.room = {"name": str(context.get("character", ""))}
	origin.disabled = true
	origin.visible = int(context.get("current_layer", 0)) == int(context.get("first_layer", 0)) and not context.get("preview", false)
	graph.add_child(origin)
	for row in rows:
		var key = DungeonRouteNode.new()
		key.room = row
		key.available = bool(row.get("available", false)) and not context.get("preview", false)
		key.visited = bool(row.get("visited", false))
		if row.get("is_anchor", false):
			key.portrait = origin.portrait
		key.disabled = not key.available
		key.pressed.connect(func(): _select(int(row.node_id), int(row.layer_index)))
		key.focus_entered.connect(func(): scroll.ensure_control_visible(key))
		graph.add_child(key)
		if row.get("current", false):
			key.tooltip_text = str(row.get("name", "")) + "（当前位置）"
			var marker = DungeonStyle.label("当前位置", 14)
			marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
			marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			marker.add_theme_color_override("font_color", Color("f2d790"))
			key.add_child(marker)
			marker.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
			marker.offset_top = 2
			marker.offset_bottom = 22
		nodes.append(key)
	footer = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 24)
	add_child(footer)
	var filler = Control.new()
	filler.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(filler)
	confirm = Button.new()
	confirm.text = "选择"
	confirm.custom_minimum_size = Vector2(260, 56)
	confirm.add_theme_font_size_override("font_size", 28)
	confirm.add_theme_color_override("font_color", Color("5c4936"))
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style = DungeonStyle.box(Color("f3eedf") if state != "pressed" else Color("dfcda4"), Color("9a8f75"), 2)
		style.corner_radius_top_left = 14
		style.corner_radius_bottom_right = 14
		confirm.add_theme_stylebox_override(state, style)
	confirm.disabled = true
	confirm.pressed.connect(_confirm)
	footer.add_child(confirm)
	automatic = CheckBox.new()
	automatic.text = "无多选项时自动进入下一节点"
	automatic.button_pressed = bool(context.get("automatic", false))
	automatic.add_theme_font_size_override("font_size", 17)
	for state in ["normal", "hover", "pressed", "focus"]: automatic.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	automatic.toggled.connect(func(value): command.emit("auto_route", value, 0))
	footer.add_child(automatic)
	var trailing = Control.new()
	trailing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(trailing)
	confirm.visible = not context.get("preview", false)
	automatic.visible = not context.get("preview", false)
	resized.connect(_layout)
	_layout.call_deferred()
	for row in rows:
		if row.get("available", false):
			_select(int(row.node_id))
			break

func _counter(parent: Control, caption: String, value: String, color: Color) -> void:
	var bar = PanelContainer.new()
	bar.custom_minimum_size = Vector2(174, 30)
	bar.tooltip_text = caption
	var style = DungeonStyle.box(Color("261e15"), Color("a8946f"), 2)
	style.set_corner_radius_all(15)
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	parent.add_child(bar)
	bar.add_theme_stylebox_override("panel", style)
	var label = DungeonStyle.label("    " + value, 21)
	bar.add_child(label)
	bar.draw.connect(func():
		bar.draw_circle(Vector2(10, 15), 17, color.darkened(0.5))
		bar.draw_circle(Vector2(10, 15), 13, color)
		bar.draw_arc(Vector2(10, 15), 16, 0, TAU, 40, color.lightened(0.5), 2, true)
		bar.draw_arc(Vector2(8, 12), 8, 0.3, 2.8, 20, Color(1, 1, 1, 0.65), 2, true))

func _layout() -> void:
	if not is_instance_valid(scroll): return
	header.position = Vector2(30, 20)
	header.size = Vector2(maxf(0, size.x - 60), 74)
	footer.size = footer.get_combined_minimum_size().max(Vector2(size.x - 48, 56))
	var compact = size.x < 1000
	automatic.text = "单一路线自动进入" if compact else "无多选项时自动进入下一节点"
	confirm.custom_minimum_size.x = 190 if compact else 360 if size.x >= 1800 else 260
	footer.get_child(0).custom_minimum_size.x = automatic.get_combined_minimum_size().x + 24 if size.x >= 1100 else 0
	footer.position = Vector2(24, size.y - 82)
	footer.size.x = maxf(0, size.x - 48)
	scroll.position = Vector2(24, 112)
	scroll.size = Vector2(maxf(0, size.x - 48), maxf(160, size.y - 220))
	var height = maxf(160, scroll.size.y - 20)
	var card_height = clampf(height * 0.29, 48, 170)
	node_size = Vector2(maxf(100, card_height * 1.15), card_height)
	column_width = node_size.x + clampf(size.x * 0.1, 90, 220)
	var first_column = int(context.get("first_layer", 0))
	var last_column = first_column
	origin.position = Vector2(36, height * 0.5 - node_size.y * 0.5)
	origin.size = node_size
	for index in rows.size():
		var row: Dictionary = rows[index]
		var column = int(row.layer_index)
		last_column = maxi(column, last_column)
		var lane = int(row.lane)
		var count = int(row.lane_count)
		var y = height * (0.5 if count == 1 else 0.18 + 0.64 * lane / maxf(1, count - 1))
		nodes[index].position = Vector2(36 + (column - first_column + 1) * column_width, y - node_size.y * 0.5)
		nodes[index].size = node_size
	graph.custom_minimum_size = Vector2(72 + (last_column - first_column + 1) * column_width + node_size.x, height)
	edges.clear()
	var by_id: Dictionary = {}
	for index in rows.size(): by_id[int(rows[index].config_id)] = nodes[index]
	for index in rows.size():
		var row: Dictionary = rows[index]
		if int(row.layer_index) == first_column and origin.visible: edges.append({"from": origin, "to": nodes[index], "vertical": false})
		for parent in row.get("parents", []):
			if by_id.has(int(parent)): edges.append({"from": by_id[int(parent)], "to": nodes[index], "vertical": false})
		for neighbor in row.get("vertical_neighbors", []):
			var other = int(row.layer_index) * 100000000 + int(neighbor)
			if int(row.node_id) < int(neighbor) and by_id.has(other): edges.append({"from": nodes[index], "to": by_id[other], "vertical": true})
	graph.queue_redraw()
	_scroll_to_current.call_deferred()

func _scroll_to_current() -> void:
	for index in rows.size():
		var target = rows[index].get("is_anchor", false) if context.get("preview", false) else rows[index].get("available", false)
		if target and int(rows[index].layer_index) == int(context.get("current_layer", 0)):
			scroll.scroll_horizontal = maxi(0, int(nodes[index].position.x - column_width - 36))
			return

func _draw_paths() -> void:
	for edge in edges:
		var source: DungeonRouteNode = edge.from
		var target: DungeonRouteNode = edge.to
		if edge.vertical:
			var top = source if source.position.y < target.position.y else target
			var bottom = target if top == source else source
			var start = top.position + Vector2(top.size.x * 0.5, top.size.y + 5)
			var end = bottom.position + Vector2(bottom.size.x * 0.5, -5)
			var color = Color("efcd78") if context.get("shift_available", false) else Color("8e8263")
			var length = minf(48, maxf(4, end.y - start.y))
			var middle = (start + end) * 0.5
			_vertical_arrow(middle + Vector2(-12, -length * 0.5), middle + Vector2(-12, length * 0.5), color)
			_vertical_arrow(middle + Vector2(12, length * 0.5), middle + Vector2(12, -length * 0.5), color)
		else:
			var start = source.position + Vector2(source.size.x + 3, (source.size.y - 24) * 0.5)
			var end = target.position + Vector2(-6, (target.size.y - 24) * 0.5)
			var lit = source.portrait != null
			var color = Color("a77a4f")
			graph.draw_circle(start, 5, color)
			_arrow(start, end, color, lit)

func _vertical_arrow(start: Vector2, end: Vector2, color: Color) -> void:
	var direction = (end - start).normalized()
	var side = direction.orthogonal()
	var head = minf(8, start.distance_to(end) * 0.45)
	graph.draw_line(start, end - direction * head, color, 2, true)
	graph.draw_colored_polygon(PackedVector2Array([end, end - direction * head + side * head * 0.6, end - direction * head - side * head * 0.6]), color)

func _arrow(start: Vector2, end: Vector2, color: Color, lit: bool) -> void:
	var direction = (end - start).normalized()
	var side = direction.orthogonal()
	if absf(end.y - start.y) > 8:
		var length = start.distance_to(end) - 18
		for step in range(0, int(length), 18):
			graph.draw_circle(start + direction * step, 3.5, Color("f2d790") if lit else color)
	else:
		if lit: graph.draw_line(start, end - direction * 10, Color("f2d790"), 8, true)
		graph.draw_line(start, end - direction * 10, color, 4, true)
	var head = PackedVector2Array([end, end - direction * 21 + side * 9, end - direction * 16, end - direction * 21 - side * 9])
	graph.draw_colored_polygon(head, color)
	if lit: graph.draw_polyline(PackedVector2Array([head[1], head[0], head[3]]), Color("f2d790"), 2, true)

func _select(id: int, layer := -1) -> void:
	if context.get("preview", false): return
	for index in rows.size():
		if int(rows[index].node_id) == id and rows[index].get("available", false) and (layer < 0 or int(rows[index].layer_index) == layer):
			selected_id = id
			selected_index = index
			break
	for index in nodes.size():
		var key = nodes[index]
		key.chosen = key.available and index == selected_index
		key.queue_redraw()
		if key.chosen: confirm.text = "换路 · %d" % int(key.room.get("shift_cost", 1)) if key.room.get("vertical", false) else "选择"
	confirm.disabled = selected_id == 0

func _confirm() -> void:
	if selected_id == 0 or context.get("preview", false): return
	confirm.disabled = true
	command.emit("enter_node", selected_id, 0)
