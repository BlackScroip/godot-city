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
var back_button: Button
var route_title: Label
var resource_counters: VBoxContainer
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
var selection_info: VBoxContainer
var selection_heading: HBoxContainer
var selection_icon: TextureRect
var selection_description: Label
var _selection_submitted := false
var _scroll_initialized := false
var _initial_scroll_pending := false
var _scroll_view_width := 0.0
var _last_layout_scroll := 0
var _preserve_browsing := false
var _opening_started := false
var _opening_tween: Tween
var _selection_detail_tween: Tween
var _confirm_tween: Tween
var _focused_node: DungeonRouteNode
var _departure_tween: Tween
var _departing_portrait: TextureRect
var _departing_source: DungeonRouteNode
var _opening_alpha := 0.0:
	set(value):
		_opening_alpha = value
		if is_instance_valid(graph): graph.queue_redraw()
const PATH_ART = "res://assets/ui/route/connections/"
const CHROME_ART = "res://assets/ui/route/chrome/"

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
	back_button = back
	back.custom_minimum_size = Vector2(68, 58)
	back.tooltip_text = "返回"
	for state in ["normal", "hover", "pressed", "focus"]: back.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	back.icon = DungeonStyle.texture(CHROME_ART + "back_button.png")
	back.expand_icon = true
	back.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func(): back_requested.emit())
	header.add_child(back)
	var title = DungeonStyle.label("区域路线" if context.get("preview", false) else "选择路线", 30)
	route_title = title
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(title)
	map_switch = Button.new()
	map_switch.text = "小地图" if is_world_map() else "大地图"
	map_switch.tooltip_text = "查看区域内路线" if is_world_map() else "查看区域总览"
	map_switch.custom_minimum_size = Vector2(94, 44)
	map_switch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	map_switch.visible = not is_world_map() or bool(context.get("can_view_rooms", false))
	map_switch.pressed.connect(func(): command.emit("route_rooms" if is_world_map() else "route_world", 0, 0))
	header.add_child(map_switch)
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var counters = VBoxContainer.new()
	resource_counters = counters
	counters.add_theme_constant_override("separation", 8)
	header.add_child(counters)
	_counter(counters, "魔力精华", str(context.get("magic", 0)), "magic_essence", Rect2(64, 62, 136, 135))
	_counter(counters, "刻印圣典", "%d/%d" % [int(context.get("search", 0)), int(context.get("search_max", 3))], "search_point", Rect2(12, 10, 108, 112))
	selection_info = VBoxContainer.new()
	selection_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selection_info.add_theme_constant_override("separation", 2)
	selection_info.visible = false
	add_child(selection_info)
	selection_heading = HBoxContainer.new()
	selection_heading.alignment = BoxContainer.ALIGNMENT_CENTER
	selection_heading.add_theme_constant_override("separation", 10)
	selection_info.add_child(selection_heading)
	selection_icon = DungeonStyle.picture("", Vector2(48, 48))
	selection_heading.add_child(selection_icon)
	selection_detail = DungeonStyle.label("", 28)
	selection_detail.add_theme_color_override("font_color", Color("ffdc81"))
	selection_detail.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	selection_detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	selection_detail.clip_text = true
	selection_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selection_heading.add_child(selection_detail)
	selection_description = DungeonStyle.label("", 18)
	selection_description.add_theme_color_override("font_color", Color("efd393"))
	selection_description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	selection_description.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	selection_description.clip_text = true
	selection_info.add_child(selection_description)
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
		key.focus_entered.connect(func():
			_focused_node = key
			_ensure_node_visible.call_deferred(key))
		key.focus_exited.connect(func():
			if _focused_node == key: _focused_node = null)
		graph.add_child(key)
		key.prepare_reveal()
		if row.get("current", false):
			key.tooltip_text = str(row.get("name", "")) + "（当前位置）"
			var marker = DungeonStyle.label("当前位置", 14)
			marker.name = "CurrentMarker"
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
	filler.size_flags_horizontal = Control.SIZE_FILL
	footer.add_child(filler)
	confirm = Button.new()
	confirm.text = "选择"
	confirm.custom_minimum_size = Vector2(260, 56)
	confirm.add_theme_font_size_override("font_size", 28)
	confirm.add_theme_color_override("font_color", Color("fff7df"))
	confirm.add_theme_color_override("font_hover_color", Color.WHITE)
	confirm.add_theme_color_override("font_pressed_color", Color("fff7df"))
	confirm.add_theme_color_override("font_outline_color", Color("62462b"))
	confirm.add_theme_constant_override("outline_size", 4)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style = StyleBoxTexture.new()
		style.texture = DungeonStyle.texture(CHROME_ART + "select_button.png")
		style.texture_margin_left = 89
		style.texture_margin_right = 92
		style.content_margin_left = 32
		style.content_margin_right = 32
		style.content_margin_top = 4
		style.content_margin_bottom = 4
		style.modulate_color = Color("ffe080")
		if state == "hover" or state == "focus": style.modulate_color = Color("fff0ae")
		elif state == "pressed": style.modulate_color = Color("d7b65e")
		elif state == "disabled": style.modulate_color = Color("81775c")
		confirm.add_theme_stylebox_override(state, style)
	confirm.disabled = true
	confirm.pressed.connect(_confirm)
	footer.add_child(confirm)
	automatic = CheckBox.new()
	automatic.text = "无多选项时自动进入下一节点（含切层演出）"
	automatic.button_pressed = bool(context.get("automatic", false))
	automatic.add_theme_font_size_override("font_size", 17)
	var empty_icon = GradientTexture2D.new()
	empty_icon.width = 1
	empty_icon.height = 1
	empty_icon.gradient = Gradient.new()
	empty_icon.gradient.colors = PackedColorArray([Color.TRANSPARENT, Color.TRANSPARENT])
	for state in ["checked", "unchecked", "checked_disabled", "unchecked_disabled"]: automatic.add_theme_icon_override(state, empty_icon)
	for state in ["normal", "hover", "pressed", "focus"]:
		var style = StyleBoxEmpty.new()
		style.content_margin_left = 34
		automatic.add_theme_stylebox_override(state, style)
	automatic.draw.connect(func():
		var area = Rect2(Vector2(0, (automatic.size.y - 26) * 0.5), Vector2.ONE * 26)
		automatic.draw_texture_rect(DungeonStyle.texture(CHROME_ART + "checkbox.png"), area, false)
		if automatic.button_pressed:
			automatic.draw_texture_rect(DungeonStyle.texture(CHROME_ART + "checkmark.png"), Rect2(area.position + Vector2(0, 3), Vector2(26, 20)), false))
	automatic.toggled.connect(func(value): command.emit("auto_route", value, 0))
	footer.add_child(automatic)
	var trailing = Control.new()
	trailing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(trailing)
	confirm.visible = false
	automatic.visible = not context.get("preview", false)
	resized.connect(_layout)
	_layout.call_deferred()

func _counter(parent: Control, caption: String, value: String, icon_name: String, region: Rect2) -> void:
	var bar = Control.new()
	bar.name = icon_name.to_pascal_case() + "Counter"
	bar.custom_minimum_size = Vector2(200, 38)
	bar.tooltip_text = caption
	parent.add_child(bar)
	var background = DungeonStyle.picture(CHROME_ART + "resource_bar.png", Vector2.ZERO)
	background.stretch_mode = TextureRect.STRETCH_SCALE
	bar.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.offset_left = 14
	background.offset_top = 3
	background.offset_bottom = -3
	var art = AtlasTexture.new()
	art.atlas = DungeonStyle.texture(CHROME_ART + icon_name + ".png")
	art.region = region
	var icon = DungeonStyle.picture("", Vector2.ZERO)
	icon.name = "Icon"
	icon.texture = art
	bar.add_child(icon)
	var label = DungeonStyle.label(value, 21)
	label.name = "Amount"
	label.clip_text = true
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.offset_left = 46
	label.offset_right = -12
	var update_counter = func():
		if not is_inside_tree() or is_queued_for_deletion(): return
		var side = bar.size.y * (1.12 if icon_name == "search_point" else 0.92)
		icon.size = Vector2.ONE * side
		icon.position = Vector2((40 - side) * 0.5, (bar.size.y - side) * 0.5)
		DungeonStyle.fit_label_text(label, 21 if bar.size.y > 32 else 18, 12)
	bar.resized.connect(update_counter)
	update_counter.call_deferred()

func _layout() -> void:
	if not is_inside_tree() or is_queued_for_deletion() or not is_instance_valid(scroll): return
	var browsing = _scroll_initialized and (_preserve_browsing or scroll.scroll_horizontal != _last_layout_scroll)
	var center_column = (scroll.scroll_horizontal + _scroll_view_width * 0.5 - _graph_margin - node_size.x * 0.5) / column_width if browsing else NAN
	var compact = size.x < 1000
	var short_view = size.y < 540
	header.add_theme_constant_override("separation", 10 if compact else 18)
	back_button.custom_minimum_size = Vector2(52 if compact else 68, 58)
	back_button.add_theme_constant_override("icon_max_width", 50 if compact else 68)
	route_title.add_theme_font_size_override("font_size", 24 if compact else 30)
	map_switch.custom_minimum_size.x = 82 if compact else 94
	for bar in resource_counters.get_children(): bar.custom_minimum_size = Vector2(144 if compact else 200, 30 if short_view else 38)
	header.position = Vector2(24 if compact else 30, 10 if short_view else 20)
	header.size = Vector2(maxf(0, size.x - header.position.x * 2), 68 if short_view else 84)
	footer.add_theme_constant_override("separation", 12 if compact else 24)
	automatic.text = "单一路线自动进入" if compact else "无多选项时自动进入下一节点（含切层演出）"
	automatic.add_theme_font_size_override("font_size", 15 if size.x < 700 else 17)
	confirm.custom_minimum_size = Vector2(160 if size.x < 700 else 190 if compact else 360 if size.x >= 1800 else 260, 44 if short_view else 56)
	confirm.add_theme_font_size_override("font_size", 24 if short_view else 28)
	var footer_gap = footer.get_theme_constant("separation")
	var footer_width = maxf(0, size.x - 48)
	var centered_left = (footer_width - confirm.custom_minimum_size.x) * 0.5 - footer_gap
	var available_left = footer_width - confirm.custom_minimum_size.x - (automatic.get_combined_minimum_size().x if automatic.visible else 0) - footer_gap * 3
	footer.get_child(0).custom_minimum_size.x = maxf(0, minf(centered_left, available_left))
	footer.position = Vector2(24, size.y - (56 if short_view else 82))
	footer.size = Vector2(maxf(0, size.x - 48), 44 if short_view else 56)
	_layout_selection_info()
	scroll.position = Vector2(24, 110 if short_view else 152 if size.x < 1100 else 126)
	scroll.size = Vector2(maxf(0, size.x - 48), maxf(120, footer.position.y - scroll.position.y - (6 if short_view else 12)))
	_scroll_view_width = scroll.size.x
	var height = maxf(120, scroll.size.y - 20)
	var card_height = clampf(height * (0.29 if is_world_map() else 0.20), 80 if is_world_map() else 40, 170 if is_world_map() else 132)
	var gap = clampf(size.x * 0.1, 90, 220)
	var width_ratio = 1.15 if is_world_map() else 2.15
	var frame_ratio = 1.0 if is_world_map() else DungeonRouteNode.SELECTED_FRAME_SIZE.x * DungeonRouteNode.SELECTION_PEAK_SCALE
	card_height = minf(card_height, maxf(1.0, (scroll.size.x - gap - 8.0) / (width_ratio * (1.0 + frame_ratio))))
	if not is_world_map():
		var lanes := 1
		for row in rows: lanes = maxi(lanes, int(row.get("lane_count", 1)))
		var peak_height = DungeonRouteNode.SELECTED_FRAME_SIZE.y * DungeonRouteNode.SELECTION_PEAK_SCALE
		card_height = minf(card_height, (height - 12 - (lanes - 1) * 24) / (lanes * peak_height))
	node_size = Vector2(card_height * width_ratio, card_height)
	var frame_margin := Vector2.ZERO
	origin.size = node_size
	for node in nodes:
		node.size = node_size
		var marker = node.get_node_or_null("CurrentMarker")
		if marker: marker.visible = node_size.y >= 60
		var bounds = node.selection_bounds()
		frame_margin = frame_margin.max(-bounds.position).max(bounds.end - node_size)
	frame_margin += Vector2.ONE * 6
	_graph_margin = maxf(36, frame_margin.x)
	column_width = node_size.x + gap
	# The APK spaces room rows by 220 units against a 289-unit visible card border.
	var room_row_space = maxf(node_size.x * DungeonRouteNode.ROOM_CONTENT_SCALE * 220.0 / 289.0, node_size.y + frame_margin.y * 2 + 24)
	var first_column = int(context.get("first_layer", 0))
	var last_column = first_column
	origin.position = Vector2(_graph_margin, height * 0.5 - node_size.y * 0.5)
	for index in rows.size():
		var row: Dictionary = rows[index]
		var column = int(row.layer_index)
		last_column = maxi(column, last_column)
		var lane = int(row.lane)
		var count = int(row.lane_count)
		var margin = (0.25 if is_world_map() else 0.14) if compact else 0.18
		if not is_world_map() and short_view: margin = (node_size.y * 0.5 + frame_margin.y) / height
		var y = height * (0.5 if count == 1 else margin + (1.0 - margin * 2.0) * lane / maxf(1, count - 1))
		if not is_world_map():
			var row_space = minf(room_row_space, (height - node_size.y - frame_margin.y * 2) / maxf(1, count - 1))
			y = height * 0.5 + (lane - (count - 1) * 0.5) * row_space
		y = clampf(y, node_size.y * 0.5 + frame_margin.y, height - node_size.y * 0.5 - frame_margin.y)
		nodes[index].position = Vector2(_graph_margin + (column - first_column + int(origin.visible)) * column_width, y - node_size.y * 0.5)
		if is_world_map(): nodes[index].position = nodes[index].position.round()
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
	if not _scroll_initialized:
		if not _initial_scroll_pending:
			_initial_scroll_pending = true
			_initialize_scroll.call_deferred()
	else:
		_restore_scroll.call_deferred(center_column)

func _layout_selection_info() -> void:
	var short_view = size.y < 540
	var compact = size.x < 1100
	var icon_size = 24 if short_view else 32 if compact else 48
	var font_size = 18 if short_view else 22 if compact else 30
	var width = maxf(0, size.x - 60)
	var left = 30.0
	if not compact:
		var safe_left = header.position.x + back_button.custom_minimum_size.x + route_title.get_combined_minimum_size().x + 56
		if map_switch.visible: safe_left += map_switch.custom_minimum_size.x + 18
		var safe_right = size.x - resource_counters.get_combined_minimum_size().x - 60
		width = minf(760, maxf(0, safe_right - safe_left))
		left = clampf((size.x - width) * 0.5, safe_left, safe_right - width)
	selection_info.position = Vector2(left, (80 if short_view else 112) if compact else 18)
	selection_icon.custom_minimum_size = Vector2.ONE * icon_size
	selection_detail.add_theme_font_size_override("font_size", font_size)
	var text_width = selection_detail.get_theme_font("font").get_string_size(DungeonLocale.text(selection_detail.text), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	selection_detail.custom_minimum_size.x = minf(text_width + 4, maxf(0, width - icon_size - 10))
	selection_description.visible = not compact and not selection_description.text.is_empty()
	selection_info.size = Vector2(width, icon_size + (28 if selection_description.visible else 0))

func _play_opening() -> void:
	if _opening_started or not is_inside_tree() or is_queued_for_deletion(): return
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

func _initialize_scroll() -> void:
	while is_inside_tree() and not is_queued_for_deletion():
		if not is_visible_in_tree():
			await visibility_changed
			continue
		_layout()
		# ScrollContainer updates its scrollbar range after its child is laid out.
		var tree = get_tree()
		for frame in 2:
			await tree.process_frame
			if not is_inside_tree() or is_queued_for_deletion(): return
		if is_visible_in_tree(): break
	if not is_inside_tree() or is_queued_for_deletion(): return
	_scroll_to_current()
	_scroll_initialized = true
	_initial_scroll_pending = false
	_play_opening()

func _restore_scroll(center_column: float) -> void:
	if not is_inside_tree() or is_queued_for_deletion(): return
	if is_nan(center_column):
		_scroll_to_current()
	else:
		_preserve_browsing = true
		_set_scroll_center(_graph_margin + center_column * column_width + node_size.x * 0.5)
	_scroll_initialized = true
	if is_instance_valid(_focused_node): _ensure_node_visible(_focused_node)
	elif selected_index >= 0: _ensure_node_visible(nodes[selected_index])

func _ensure_node_visible(node: DungeonRouteNode) -> void:
	if not is_inside_tree() or is_queued_for_deletion() or not is_instance_valid(node) or graph.size.x <= 0: return
	var bounds = node.selection_bounds().grow(4)
	bounds.position += node.position
	var target = float(scroll.scroll_horizontal)
	if bounds.position.x < target: target = bounds.position.x
	elif bounds.end.x > target + scroll.size.x: target = bounds.end.x - scroll.size.x
	scroll.scroll_horizontal = roundi(clampf(target, 0, maxf(0, graph.size.x - scroll.size.x)))
	_last_layout_scroll = scroll.scroll_horizontal

func _set_scroll_center(center: float) -> void:
	var maximum = maxf(0, graph.size.x - scroll.size.x)
	scroll.scroll_horizontal = roundi(clampf(center - scroll.size.x * 0.5, 0, maximum))
	_last_layout_scroll = scroll.scroll_horizontal

func _scroll_to_current() -> void:
	_preserve_browsing = false
	for index in rows.size():
		if rows[index].get("is_anchor", false):
			_scroll_to_anchor(nodes[index])
			return
	if is_world_map() and int(context.get("current_layer", 0)) <= int(context.get("first_layer", 0)) and not rows.any(func(row): return bool(row.get("current", false))):
		_scroll_to_anchor(origin)
		return
	for index in rows.size():
		if int(rows[index].layer_index) == int(context.get("current_layer", 0)):
			_scroll_to_anchor(nodes[index])
			return
	_set_scroll_center(0)

func _scroll_to_anchor(anchor: DungeonRouteNode) -> void:
	var bounds = anchor.selection_bounds()
	bounds.position += anchor.position
	var anchor_layer = int(anchor.room.get("layer_index", int(context.get("first_layer", 0)) - 1))
	var next_layer = 2147483647
	for node in nodes:
		var layer = int(node.room.layer_index)
		if layer > anchor_layer: next_layer = mini(next_layer, layer)
	for node in nodes:
		if int(node.room.layer_index) != next_layer: continue
		var target = node.selection_bounds()
		target.position += node.position
		if not is_world_map() and node.available:
			target = target.grow_individual(_graph_margin, 0, _graph_margin, 0)
		bounds = bounds.merge(target)
	var center = anchor.get_rect().get_center().x if is_world_map() else bounds.get_center().x
	var min_center = bounds.end.x - scroll.size.x * 0.5
	var max_center = bounds.position.x + scroll.size.x * 0.5
	if min_center <= max_center: center = clampf(center, min_center, max_center)
	else: center = (bounds.position.x + bounds.end.x) * 0.5
	_set_scroll_center(center)

func _draw_paths() -> void:
	# Keep the traversed/current route readable where legal branches intersect.
	for state in ["unavailable", "passed", "available"]:
		for edge in edges:
			if _path_state(edge) != state: continue
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
	elif not vertical and not is_equal_approx(source.position.y, target.position.y):
		kind = "diagonal"
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
	if not is_world_map(): return _room_path_geometry(edge)
	var source: DungeonRouteNode = edge.from
	var target: DungeonRouteNode = edge.to
	var start = source.position + Vector2(source.size.x + 8, source.size.y * 0.5)
	var end = target.position + Vector2(-12, target.size.y * 0.5)
	var direction = signf(end.y - start.y)
	var state = _path_state(edge)
	var sprite = "path_" + state
	var thickness = (56.0 if state == "available" else 42.0 if state == "passed" else 38.0) * clampf(node_size.y / (200.0 if is_world_map() else 140.0), 0.35, 1.0)
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
		draw_size = Vector2(length, thickness)
		draw_position = start - Vector2(0, thickness * 0.5).rotated(rotation)
	var area = Rect2(draw_position, Vector2.ZERO)
	for corner in [Vector2(draw_size.x, 0), draw_size, Vector2(0, draw_size.y)]:
		area = area.expand(draw_position + (corner * draw_scale).rotated(rotation))
	return {"start": start, "end": end, "area": area, "sprite": sprite, "state": state, "kind": edge.kind,
		"draw_position": draw_position, "draw_rotation": rotation, "draw_scale": draw_scale, "draw_size": draw_size}

func _room_path_geometry(edge: Dictionary) -> Dictionary:
	var source: DungeonRouteNode = edge.from
	var target: DungeonRouteNode = edge.to
	var state = _path_state(edge)
	var diagonal = edge.kind == "diagonal"
	var sprite = ("path_diagonal_" if diagonal else "path_") + state
	var left = source.position.x + source.selection_bounds().end.x + 4
	var right = target.position.x + target.selection_bounds().position.x - 4
	var source_y = source.get_rect().get_center().y
	var target_y = target.get_rect().get_center().y
	var direction = signf(target_y - source_y)
	var thickness = (56.0 if state == "available" else 42.0 if state == "passed" else 38.0) * clampf(node_size.y / 140.0, 0.35, 1.0)
	var dimensions = Vector2(maxf(1, right - left), thickness)
	var position = Vector2(left, source_y - thickness * 0.5)
	var scale = Vector2.ONE
	var tail = Vector2(0.075, 0.5)
	var tip = Vector2(0.965, 0.5)
	if diagonal:
		# ATSlot_RoadMapNode uses a 256x200 diagonal image, mirrored vertically for down.
		var inset = minf(node_size.y * 15.0 / 148.0, absf(target_y - source_y) * 0.2)
		dimensions.y = maxf(1, absf(target_y - source_y) - inset * 2)
		position.y = target_y - direction * inset
		scale.y = -direction
		tail.y = 0.92
		tip.y = 0.04
	var area = Rect2(position, dimensions * scale).abs()
	return {"start": position + tail * dimensions * scale, "end": position + tip * dimensions * scale,
		"area": area, "sprite": sprite, "state": state, "kind": edge.kind, "tint": _room_path_tint(edge),
		"draw_position": position, "draw_rotation": 0.0, "draw_scale": scale, "draw_size": dimensions}

func _room_path_tint(edge: Dictionary) -> Color:
	if _path_state(edge) != "unavailable": return Color.WHITE
	var source: DungeonRouteNode = edge.from
	if source.room.get("is_anchor", false) or source.room.get("current", false): return Color.WHITE
	var anchor_layer = int(context.get("current_layer", 0)) - 1
	for node in nodes:
		if node.room.get("is_anchor", false):
			anchor_layer = int(node.room.layer_index)
			break
	# Slot_RoadMapNode: Passed/NoReachable use the prefab's lineColor_Gray (90/255).
	return Color("5a5a5a") if source.visited or int(source.room.get("layer_index", 0)) <= anchor_layer else Color.WHITE

func _world_center_y(node: DungeonRouteNode) -> float:
	return maxf(14, minf(node.size.x * 0.44, (node.size.y - 24) * 0.5)) + 3

func _draw_forward_path(path: Dictionary, alpha := 1.0) -> void:
	var texture = DungeonStyle.texture(PATH_ART + str(path.sprite) + ".png")
	if texture == null: return
	var tint: Color = path.get("tint", Color.WHITE)
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
	var top_edge = top.position.y + top.selection_bounds().end.y + 3
	var bottom_edge = bottom.position.y + bottom.selection_bounds().position.y - 3
	var gap = bottom_edge - top_edge
	var height = minf(gap, maxf(14, minf(node_size.y * 0.65, gap * 0.9)))
	if height <= 0: return []
	var dimensions = Vector2(height * 47.0 / 74.0, height)
	var middle = Vector2(top.position.x + top.size.x * 0.5, (top_edge + bottom_edge) * 0.5)
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
	var first_selection = not confirm.visible
	confirm.visible = true
	selection_detail.text = DungeonCatalog.clean(str(row.get("display_name", row.get("name", ""))))
	selection_description.text = DungeonCatalog.clean(str(row.get("lock_reason", ""))) if is_world_map() and confirm.disabled else DungeonCatalog.clean(str(row.get("description", row.get("Desc", ""))))
	selection_detail.tooltip_text = selection_detail.text + ("\n" + selection_description.text if not selection_description.text.is_empty() else "")
	selection_icon.texture = nodes[selected_index]._world_artwork() if is_world_map() else nodes[selected_index]._artwork()
	selection_info.visible = true
	_layout_selection_info()
	_ensure_node_visible(nodes[selected_index])
	if _selection_detail_tween: _selection_detail_tween.kill()
	selection_info.modulate.a = 0.35
	_selection_detail_tween = create_tween()
	_selection_detail_tween.tween_property(selection_info, "modulate:a", 1.0, 0.18)
	if first_selection:
		confirm.modulate.a = 0.0
		if _confirm_tween: _confirm_tween.kill()
		_confirm_tween = create_tween()
		_confirm_tween.tween_property(confirm, "modulate:a", 1.0, 0.18)

func _confirm() -> void:
	if selected_index < 0 or context.get("preview", false) or _selection_submitted: return
	var row: Dictionary = rows[selected_index]
	if not _can_select(row) or not bool(row.get("available", false)): return
	_selection_submitted = true
	confirm.disabled = true
	command.emit("select_region" if is_world_map() else "enter_node", selected_id, 0 if is_world_map() else {"layer_index": int(row.layer_index)})

func play_departure(id: int, layer := -1) -> float:
	if _departure_tween or context.get("preview", false): return 0.0
	var target: DungeonRouteNode
	if is_world_map() and selected_index >= 0:
		target = nodes[selected_index]
	else:
		for node in nodes:
			if int(node.room.node_id) == id and (layer < 0 or int(node.room.layer_index) == layer):
				target = node
				break
	if target == null: return 0.0
	_departing_source = origin if origin.visible else null
	for node in nodes:
		if node.room.get("is_anchor", false):
			_departing_source = node
			break
	if _departing_source == null or _departing_source == target: return 0.0
	var portrait = _departing_source.portrait if _departing_source.portrait else origin.portrait
	if portrait == null: return 0.0
	_selection_submitted = true
	confirm.disabled = true
	back_button.disabled = true
	map_switch.disabled = true
	automatic.disabled = true
	for node in nodes: node.disabled = true
	_departing_portrait = DungeonStyle.picture("", Vector2.ZERO)
	_departing_portrait.name = "DepartingPortrait"
	_departing_portrait.texture = portrait
	_departing_portrait.z_index = 2
	graph.add_child(_departing_portrait)
	var side = target._world_frame_rect().size.y * 0.75 if is_world_map() else target._room_rect().size.y * 0.9
	_departing_portrait.size = Vector2.ONE * side
	_departing_portrait.position = _departing_source.position + (_departing_source._world_frame_rect().get_center() if is_world_map() else _departing_source.size * 0.5) - _departing_portrait.size * 0.5
	_departing_source.portrait = null
	_departing_source.queue_redraw()
	_departure_tween = create_tween()
	_departure_tween.tween_method(func(progress: float):
		var start = _departing_source.position + (_departing_source._world_frame_rect().get_center() if is_world_map() else _departing_source.size * 0.5)
		var end = target.position + (target._world_frame_rect().get_center() if is_world_map() else target.size * 0.5)
		var diagonal = absf(end.x - start.x) > 1 and absf(end.y - start.y) > 1
		var y_progress = smoothstep(0.25, 0.75, progress) if diagonal else progress
		_departing_portrait.position = Vector2(lerpf(start.x, end.x, progress), lerpf(start.y, end.y, y_progress)) - _departing_portrait.size * 0.5,
		0.0, 1.0, 1.0)
	return 1.0

func _exit_tree() -> void:
	for tween in [_opening_tween, _selection_detail_tween, _confirm_tween, _departure_tween]:
		if tween and tween.is_valid(): tween.kill()
