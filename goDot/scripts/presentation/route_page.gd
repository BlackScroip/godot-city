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
var _graph_margin := 36.0
var map_switch: Button
var selection_detail: Label
var _selection_submitted := false
var _scroll_initialized := false
var _scroll_view_width := 0.0
var _last_layout_scroll := 0
var _preserve_browsing := false
var _opening_started := false
var _opening_tween: Tween
var _opening_alpha := 0.0:
	set(value):
		_opening_alpha = value
		if is_instance_valid(graph): graph.queue_redraw()
const PATH_ART = "res://assets/ui/route/connections/"

func is_world_map() -> bool:
	return context.get("map_scope", "rooms") == "world"

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
	header.modulate.a = 0.0
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
	map_switch = Button.new()
	map_switch.text = "小地图" if is_world_map() else "大地图"
	map_switch.tooltip_text = "查看区域内路线" if is_world_map() else "查看区域总览"
	map_switch.custom_minimum_size = Vector2(94, 44)
	map_switch.visible = not is_world_map() or bool(context.get("can_view_rooms", false))
	map_switch.pressed.connect(func(): command.emit("route_rooms" if is_world_map() else "route_world", 0, 0))
	header.add_child(map_switch)
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var counters = VBoxContainer.new()
	counters.add_theme_constant_override("separation", 8)
	header.add_child(counters)
	_counter(counters, "魔力精华", str(context.get("magic", 0)), Color("4898ee"))
	_counter(counters, "刻印圣典", "%d/%d" % [int(context.get("search", 0)), int(context.get("search_max", 3))], Color("7fdf6a"))
	selection_detail = DungeonStyle.label("", 16)
	selection_detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	selection_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(selection_detail)
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
	origin.room = {"name": str(context.get("character", "")), "map_mode": "world" if is_world_map() else "rooms", "world_icon": "森林图标"}
	origin.disabled = true
	origin.visible = is_world_map()
	if is_world_map() and int(context.get("current_layer", 1)) > 1: origin.portrait = null
	graph.add_child(origin)
	if origin.visible: origin.prepare_reveal()
	for row in rows:
		var key = DungeonRouteNode.new()
		key.room = row
		key.available = bool(row.get("available", false)) and not context.get("preview", false)
		key.visited = bool(row.get("visited", false))
		if row.get("is_anchor", false):
			key.portrait = origin.portrait
		key.disabled = not _can_select(row)
		key.pressed.connect(func(): _select(int(row.node_id), int(row.layer_index)))
		key.focus_entered.connect(func(): scroll.ensure_control_visible(key))
		graph.add_child(key)
		key.prepare_reveal()
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
	footer.modulate.a = 0.0
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
	automatic.text = "无多选项时自动进入下一节点（含切层演出）"
	automatic.button_pressed = bool(context.get("automatic", false))
	automatic.add_theme_font_size_override("font_size", 17)
	for state in ["normal", "hover", "pressed", "focus"]: automatic.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	automatic.toggled.connect(func(value): command.emit("auto_route", value, 0))
	footer.add_child(automatic)
	var trailing = Control.new()
	trailing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(trailing)
	confirm.visible = false
	automatic.visible = not context.get("preview", false)
	resized.connect(_layout)
	_layout.call_deferred()

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
	var browsing = _scroll_initialized and (_preserve_browsing or scroll.scroll_horizontal != _last_layout_scroll)
	var center_column = (scroll.scroll_horizontal + _scroll_view_width * 0.5 - _graph_margin - node_size.x * 0.5) / column_width if browsing else NAN
	header.position = Vector2(30, 20)
	header.size = Vector2(maxf(0, size.x - 60), 74)
	footer.size = footer.get_combined_minimum_size().max(Vector2(size.x - 48, 56))
	var compact = size.x < 1000
	automatic.text = "单一路线自动进入" if compact else "无多选项时自动进入下一节点（含切层演出）"
	confirm.custom_minimum_size.x = 190 if compact else 360 if size.x >= 1800 else 260
	footer.get_child(0).custom_minimum_size.x = automatic.get_combined_minimum_size().x + 24 if size.x >= 1100 else 0
	footer.position = Vector2(24, size.y - 82)
	footer.size.x = maxf(0, size.x - 48)
	selection_detail.position = Vector2(30, 96)
	selection_detail.size = Vector2(maxf(0, size.x - 60), 24)
	scroll.position = Vector2(24, 126)
	scroll.size = Vector2(maxf(0, size.x - 48), maxf(160, size.y - 234))
	_scroll_view_width = scroll.size.x
	var height = maxf(120, scroll.size.y - 20)
	var card_height = clampf(height * (0.29 if is_world_map() else 0.20), 80 if is_world_map() else 40, 170 if is_world_map() else 132)
	node_size = Vector2(maxf(100, card_height * (1.15 if is_world_map() else 2.15)), card_height)
	var frame_margin = node_size * (DungeonRouteNode.SELECTED_FRAME_SIZE * DungeonRouteNode.SELECTION_PEAK_SCALE - Vector2.ONE) * 0.5 if not is_world_map() else Vector2.ZERO
	_graph_margin = maxf(36, frame_margin.x)
	column_width = node_size.x + clampf(size.x * 0.1, 90, 220)
	var first_column = int(context.get("first_layer", 0))
	var last_column = first_column
	origin.position = Vector2(_graph_margin, height * 0.5 - node_size.y * 0.5)
	origin.size = node_size
	for index in rows.size():
		var row: Dictionary = rows[index]
		var column = int(row.layer_index)
		last_column = maxi(column, last_column)
		var lane = int(row.lane)
		var count = int(row.lane_count)
		var margin = (0.25 if is_world_map() else 0.14) if compact else 0.18
		var y = height * (0.5 if count == 1 else margin + (1.0 - margin * 2.0) * lane / maxf(1, count - 1))
		y = clampf(y, node_size.y * 0.5 + frame_margin.y, height - node_size.y * 0.5 - frame_margin.y)
		nodes[index].position = Vector2(_graph_margin + (column - first_column + int(origin.visible)) * column_width, y - node_size.y * 0.5)
		nodes[index].size = node_size
	graph.custom_minimum_size = Vector2(_graph_margin * 2 + (last_column - first_column + int(origin.visible)) * column_width + node_size.x, height)
	edges.clear()
	var by_id: Dictionary = {}
	for index in rows.size(): by_id[int(rows[index].config_id)] = nodes[index]
	for index in rows.size():
		var row: Dictionary = rows[index]
		if int(row.layer_index) == first_column and origin.visible: _add_edge(origin, nodes[index])
		for parent in row.get("parents", []):
			if by_id.has(int(parent)): _add_edge(by_id[int(parent)], nodes[index])
		for neighbor in row.get("vertical_neighbors", []):
			var other = int(row.layer_index) * 100000000 + int(neighbor)
			if int(row.node_id) < int(neighbor) and by_id.has(other): _add_edge(nodes[index], by_id[other], true)
	graph.queue_redraw()
	_restore_scroll.call_deferred(center_column)
	if not _opening_started: _play_opening.call_deferred()

func _play_opening() -> void:
	if _opening_started or not is_inside_tree(): return
	_opening_started = true
	_opening_tween = create_tween().set_parallel()
	_opening_tween.tween_property(header, "modulate:a", 1.0, 0.18)
	_opening_tween.tween_property(footer, "modulate:a", 1.0, 0.22).set_delay(0.14)
	_opening_tween.tween_property(self, "_opening_alpha", 1.0, 0.72).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if origin.visible: origin.reveal(0.0)
	for node in nodes:
		# Start at the visible column, including when reopening a later route.
		var column = clampf(floorf((node.position.x - scroll.scroll_horizontal) / column_width), 0, 4)
		var lane = clampf(float(node.room.get("lane", 0)), 0, 2)
		node.reveal(column * 0.07 + lane * 0.02)

func _restore_scroll(center_column: float) -> void:
	if not is_inside_tree(): return
	if is_nan(center_column):
		_scroll_to_current()
	else:
		_preserve_browsing = true
		_set_scroll_center(_graph_margin + center_column * column_width + node_size.x * 0.5)
	_scroll_initialized = true

func _set_scroll_center(center: float) -> void:
	var maximum = maxf(0, graph.size.x - scroll.size.x)
	scroll.scroll_horizontal = roundi(clampf(center - scroll.size.x * 0.5, 0, maximum))
	_last_layout_scroll = scroll.scroll_horizontal

func _scroll_to_current() -> void:
	_preserve_browsing = false
	if not is_world_map():
		for index in rows.size():
			if rows[index].get("is_anchor", false):
				_set_scroll_center(nodes[index].get_rect().get_center().x)
				return
	for index in rows.size():
		if int(rows[index].layer_index) == int(context.get("current_layer", 0)):
			_set_scroll_center(nodes[index].get_rect().get_center().x)
			return
	_set_scroll_center(0)

func _draw_paths() -> void:
	for edge in edges:
		var alpha = _opening_alpha * minf(edge.from.modulate.a, edge.to.modulate.a)
		if alpha <= 0: continue
		if edge.vertical:
			_draw_vertical_path(edge, alpha)
		else:
			_draw_forward_path(_path_geometry(edge), alpha)

func _add_edge(source: DungeonRouteNode, target: DungeonRouteNode, vertical := false) -> void:
	var kind = "vertical" if vertical else "solid"
	if is_world_map() and not is_equal_approx(source.position.y, target.position.y):
		kind = "dotted" if source == origin or int(source.room.get("lane_count", 1)) == 1 or int(target.room.get("lane_count", 1)) == 1 else "cross"
	edges.append({"from": source, "to": target, "vertical": vertical, "kind": kind})

func _path_state(edge: Dictionary) -> String:
	var source: DungeonRouteNode = edge.from
	var target: DungeonRouteNode = edge.to
	if source == origin:
		return "passed" if target.visited or bool(target.room.get("current", false)) else "unavailable"
	if target.room.get("passed_parents", []).has(int(source.room.get("config_id", 0))): return "passed"
	if not is_world_map() and bool(source.room.get("is_anchor", false)) and target.available and not bool(target.room.get("vertical", false)): return "available"
	return "unavailable"

func _path_geometry(edge: Dictionary) -> Dictionary:
	var source: DungeonRouteNode = edge.from
	var target: DungeonRouteNode = edge.to
	var start = source.position + Vector2(source.size.x + 8, source.size.y * 0.5)
	var end = target.position + Vector2(-12, target.size.y * 0.5)
	var direction = signf(end.y - start.y)
	var state = _path_state(edge)
	var sprite = "path_" + state
	if is_world_map():
		start.y = source.position.y + _world_center_y(source)
		end.y = target.position.y + _world_center_y(target)
		if edge.kind == "cross":
			# Cross-module links leave the diamond corners, clear of icons and captions.
			var corner = minf(source.size.y * 0.48, absf(end.y - start.y) * 0.28)
			start = source.position + Vector2(source.size.x * 0.78, _world_center_y(source) + direction * corner)
			end = target.position + Vector2(target.size.x * 0.22, _world_center_y(target) - direction * corner)
			sprite = "world_path_cross"
		elif edge.kind == "dotted":
			start.y += direction * source.size.y * 0.16
			end.y -= direction * target.size.y * 0.16
			sprite = "world_path_dotted_passed" if state == "passed" else "world_path_dotted"
	else:
		start.y += direction * source.size.y * 0.32
		end.y -= direction * target.size.y * 0.24
	var texture = DungeonStyle.texture(PATH_ART + sprite + ".png")
	var image_size = texture.get_size() if texture else Vector2.ONE
	var length = start.distance_to(end)
	var rotation = (end - start).angle()
	var draw_scale = Vector2.ONE
	var draw_size: Vector2
	var draw_position: Vector2
	if edge.kind in ["dotted", "cross"]:
		# Match the diagonal sprite's endpoints with a uniform scale so dots and dashes stay round.
		var image_start = image_size * (Vector2(0.04, 0.965) if edge.kind == "cross" else Vector2(0.05, 0.955))
		var image_end = image_size * Vector2(0.97, 0.04)
		rotation -= (image_end - image_start).angle()
		draw_scale = Vector2.ONE * length / image_start.distance_to(image_end)
		draw_size = image_size
		draw_position = start - (image_start * draw_scale).rotated(rotation)
	else:
		var thickness = (56.0 if state == "available" else 42.0 if state == "passed" else 38.0) * clampf(node_size.y / (200.0 if is_world_map() else 140.0), 0.35, 1.0)
		draw_size = Vector2(length, thickness)
		draw_position = start - Vector2(0, thickness * 0.5).rotated(rotation)
	var area = Rect2(draw_position, Vector2.ZERO)
	for corner in [Vector2(draw_size.x, 0), draw_size, Vector2(0, draw_size.y)]:
		area = area.expand(draw_position + (corner * draw_scale).rotated(rotation))
	return {"start": start, "end": end, "area": area, "sprite": sprite, "state": state, "kind": edge.kind,
		"draw_position": draw_position, "draw_rotation": rotation, "draw_scale": draw_scale, "draw_size": draw_size}

func _world_center_y(node: DungeonRouteNode) -> float:
	return maxf(14, minf(node.size.x * 0.44, (node.size.y - 24) * 0.5)) + 3

func _draw_forward_path(path: Dictionary, alpha := 1.0) -> void:
	var texture = DungeonStyle.texture(PATH_ART + str(path.sprite) + ".png")
	if texture == null: return
	var tint = Color.WHITE
	if path.kind == "cross":
		tint = Color(0.45, 0.44, 0.44) if path.state == "passed" else Color(0.85, 0.85, 0.85)
	tint.a = alpha
	graph.draw_set_transform(path.draw_position, path.draw_rotation, path.draw_scale)
	graph.draw_texture_rect(texture, Rect2(Vector2.ZERO, path.draw_size), false, tint)
	graph.draw_set_transform(Vector2.ZERO)

func _draw_vertical_path(edge: Dictionary, alpha := 1.0) -> void:
	var areas = _vertical_path_rects(edge)
	for index in areas.size():
		var texture = DungeonStyle.texture(PATH_ART + ("arrow_down.png" if index == 0 else "arrow_up.png"))
		if texture: graph.draw_texture_rect(texture, areas[index], false, Color(1, 1, 1, alpha))

func _vertical_path_rects(edge: Dictionary) -> Array[Rect2]:
	var source: DungeonRouteNode = edge.from
	var target: DungeonRouteNode = edge.to
	var top = source if source.position.y < target.position.y else target
	var bottom = target if top == source else source
	var gap = bottom.position.y - top.get_rect().end.y
	var height = minf(gap, maxf(8, minf(node_size.y * 0.65, gap * 0.75)))
	if height <= 0: return []
	var dimensions = Vector2(height * 47.0 / 74.0, height)
	var middle = Vector2(top.position.x + top.size.x * 0.5, top.get_rect().end.y + gap * 0.5)
	var result: Array[Rect2] = []
	for index in 2:
		result.append(Rect2(middle + Vector2((-0.7 if index == 0 else 0.7) * dimensions.x, 0) - dimensions * 0.5, dimensions))
	return result

func _can_select(row: Dictionary) -> bool:
	if context.get("preview", false): return false
	return bool(row.get("selectable", row.get("available", false))) if is_world_map() else bool(row.get("available", false))

func _select(id: int, layer := -1) -> void:
	if context.get("preview", false) or _selection_submitted: return
	var candidate := -1
	for index in rows.size():
		if int(rows[index].node_id) == id and _can_select(rows[index]) and (layer < 0 or int(rows[index].layer_index) == layer):
			candidate = index
			break
	if candidate < 0: return
	selected_id = id
	selected_index = candidate
	for index in nodes.size():
		var key = nodes[index]
		key.chosen = index == selected_index
		key.queue_redraw()
		if key.chosen: confirm.text = "换路 · %d" % int(key.room.get("shift_cost", 1)) if key.room.get("vertical", false) else "选择"
	var row: Dictionary = rows[selected_index]
	confirm.disabled = not bool(row.get("available", false))
	confirm.visible = true
	selection_detail.text = DungeonCatalog.clean(str(row.get("display_name", row.get("name", ""))))
	if is_world_map() and confirm.disabled: selection_detail.text += "  " + DungeonCatalog.clean(str(row.get("lock_reason", "")))
	selection_detail.tooltip_text = selection_detail.text

func _confirm() -> void:
	if selected_index < 0 or context.get("preview", false) or _selection_submitted: return
	var row: Dictionary = rows[selected_index]
	if not _can_select(row) or not bool(row.get("available", false)): return
	_selection_submitted = true
	confirm.disabled = true
	command.emit("select_region" if is_world_map() else "enter_node", selected_id, 0 if is_world_map() else {"layer_index": int(row.layer_index)})
