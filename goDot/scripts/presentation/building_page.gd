extends Control

signal command(kind: String, id: Variant, extra: Variant)
const PAPER := Color("faf9f6")
const INK := Color("604324")
var host: Control
var systems: RefCounted
var catalog: RefCounted
var canvas: Control
var decoration_canvas: Control
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
var help_dialog: Control
var _selected_node: Dictionary = {}
var _selection_time := 0.0
var _page_tween: Tween
var _open_progress := 0.0
var _closing := false
var _pointer := -1
var _drag_scroll: ScrollContainer
var _press_point := Vector2.ZERO
var _press_scroll := 0
var _dragging := false
var _pressed_node: Dictionary = {}
var _restore_scroll := 0
var _has_restore_scroll := false
var _art: Dictionary = {}
var _opening := true
var _open_elapsed := 0.0
var _rotation_curves: Array = []

func configure(owner_page: Control, _rows: Array, context: Dictionary) -> void:
	host = owner_page
	systems = context.systems
	catalog = context.catalog
	if FileAccess.file_exists("res://assets/ui/camp/construction/resource_map.json"):
		_art = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/camp/construction/resource_map.json"))
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/camp/construction/source.json"))
	_rotation_curves = source.animations.open.other_curves.m_RotationCurves
	selected_id = int(context.get("selected_id", 2))
	if selected_id <= 0: selected_id = 2
	selected_stage = clampi(int(context.get("selected_stage", mini(systems.rank(systems.profile.data.buildings, selected_id), 2))), 0, 2)
	_restore_scroll = int(context.get("building_scroll", 0))
	_has_restore_scroll = context.has("building_scroll")
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
	close_button.pressed.connect(go_back)
	canvas.add_child(close_button)
	help_button = art_button("须知", "修复营地吧！")
	help_button.pressed.connect(show_help)
	canvas.add_child(help_button)
	graph_frame = framed()
	canvas.add_child(graph_frame)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = false
	graph_frame.add_child(scroll)
	graph = Control.new()
	graph.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(graph)
	scroll.get_v_scroll_bar().value_changed.connect(func(value): host.page_context.building_scroll = int(value))
	detail_frame = framed()
	canvas.add_child(detail_frame)
	var content = Control.new()
	detail_frame.add_child(content)
	var emblem = picture("bg装饰")
	emblem.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	emblem.position = Vector2(-120, 60)
	emblem.size = Vector2(240, 240)
	emblem.modulate = Color("ece8df")
	content.add_child(emblem)
	detail_title = text("", 28, Color("d99b28"))
	detail_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(detail_title)
	detail_icon = picture("")
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
	build_button.pressed.connect(func():
		if not _closing and not is_instance_valid(help_dialog): command.emit("op:upgrade_building", selected_id, 0))
	content.add_child(build_button)
	decoration_canvas = Control.new()
	decoration_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(decoration_canvas)
	wood = picture("wood")
	wood.flip_h = true
	hammer = picture("hammer")
	decoration_canvas.add_child(wood)
	decoration_canvas.add_child(hammer)
	_build_nodes()
	resized.connect(_layout)
	_layout.call_deferred()
	select_stage(selected_id, selected_stage)
	_open.call_deferred()

static func text(value: String, font_size: int, color: Color) -> Label:
	var label = DungeonStyle.label(value, font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	return label

func art_texture(key: String) -> Texture2D:
	return DungeonStyle.texture(str(_art.get(key, key)))

func picture(key: String) -> TextureRect:
	return DungeonStyle.picture(str(_art.get(key, key)), Vector2.ZERO)

func patch(key: String, margin: int) -> NinePatchRect:
	var result = NinePatchRect.new()
	result.texture = art_texture(key)
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

func art_button(key: String, tooltip: String) -> Button:
	var result = Button.new()
	result.icon = art_texture(key)
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
				var line = picture("主城建造节点连接线")
				line.stretch_mode = TextureRect.STRETCH_SCALE
				line.set_meta("grid", Vector2i(stage, row_index))
				graph.add_child(line)
				connectors.append(line)
			var key = Button.new()
			key.mouse_filter = Control.MOUSE_FILTER_PASS
			key.tooltip_text = DungeonCatalog.clean(systems._part(building.name, stage))
			for state in ["normal", "hover", "pressed", "focus"]: key.add_theme_stylebox_override(state, StyleBoxEmpty.new())
			graph.add_child(key)
			var frame = picture("主城建造节点_已升级_v1" if stage < level else "主城建造节点_当前升级_v1" if stage == level else "主城建造节点_未达到_v1")
			frame.position = Vector2(10, 0)
			frame.size = Vector2(140, 140)
			key.add_child(frame)
			var known = stage <= level
			var icon = picture(systems._part(building.icon_name, stage))
			icon.position = Vector2(42, 32)
			icon.size = Vector2(76, 76)
			icon.visible = known
			key.add_child(icon)
			if stage >= level:
				var lock_icon = picture("锁")
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
				var badge = picture("提示点")
				badge.position = Vector2(120, 12)
				badge.size = Vector2(24, 24)
				key.add_child(badge)
			var selection = Control.new()
			selection.mouse_filter = Control.MOUSE_FILTER_IGNORE
			selection.size = Vector2(160, 140)
			key.add_child(selection)
			var left = picture("res://assets/ui/camp/construction/arrow.png")
			left.size = Vector2(38, 32)
			left.flip_h = true
			selection.add_child(left)
			var right = picture("res://assets/ui/camp/construction/arrow.png")
			right.size = Vector2(38, 32)
			selection.add_child(right)
			key.pressed.connect(func(): select_stage(int(building.id), stage))
			nodes.append({"id": int(building.id), "stage": stage, "row": row_index, "button": key, "selection": selection, "left": left, "right": right})
		row_index += 1

func select_stage(id: int, stage: int) -> void:
	if _closing or is_instance_valid(help_dialog): return
	selected_id = id
	selected_stage = stage
	host.page_context.selected_id = id
	host.page_context.selected_stage = stage
	var building = catalog.find("Buildings", id)
	var level = systems.rank(systems.profile.data.buildings, id)
	var status = systems.building_status(id)
	for node in nodes:
		node.selection.visible = node.id == id and node.stage == stage
		if node.selection.visible: _selected_node = node
	_selection_time = 0.0
	_animate_selection()
	detail_title.text = DungeonCatalog.clean(systems._part(building.name, stage))
	detail_icon.texture = art_texture(systems._part(building.icon_name, stage))
	detail_text.text = DungeonCatalog.clean(systems._part(building.description, stage))
	var cost = systems.costs(systems._part(building.get("need_materials", ""), stage, ";"))
	cost["101"] = int(cost.get("101", 0)) + int(systems._part(building.need_gold, stage))
	cost_label.text = "" if stage < level else systems.price_description(cost)
	build_button.disabled = stage != level or not status.can_upgrade
	build_button.text = "已建造" if stage < level else "请先建设前级" if stage > level else "建造" if status.can_upgrade else "条件不足"
	if stage == level and not status.can_upgrade: detail_text.text += "\n\n" + DungeonCatalog.clean(status.reason)
	if stage > level: detail_text.text += "\n\n前置：" + DungeonCatalog.clean(systems._part(building.name, stage - 1))
	detail_scroll.scroll_vertical = 0

func show_help() -> void:
	if _closing or is_instance_valid(help_dialog): return
	_cancel_drag()
	help_dialog = preload("res://scripts/presentation/building_help.gd").new()
	add_child(help_dialog)
	help_dialog.closed.connect(func():
		help_dialog = null
		help_button.grab_focus())
	help_dialog.configure()

func go_back() -> void:
	if is_instance_valid(help_dialog):
		help_dialog.go_back()
		return
	if _closing: return
	_closing = true
	_cancel_drag()
	if _page_tween and _page_tween.is_valid(): _page_tween.kill()
	_page_tween = create_tween()
	_page_tween.tween_property(self, "modulate:a", 0.0, 0.3 / float(DungeonSettings.read_options().ui_speed)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_page_tween.tween_callback(func(): command.emit("close_page", 0, 0))

func _open() -> void:
	_layout()
	if _has_restore_scroll:
		scroll.scroll_vertical = _restore_scroll
	else:
		_reveal_selection()
	_open_elapsed = 0.0
	_apply_open(0.0)

func _apply_open(progress: float) -> void:
	_open_progress = progress
	var slide := 225.0 * (1.0 - smoothstep(0.0, 1.0, progress))
	canvas.position.y = slide * canvas.scale.y
	canvas.modulate.a = smoothstep(0.0, 1.0, progress)
	var decoration_progress := smoothstep(0.0, 0.8, progress)
	wood.modulate.a = decoration_progress
	wood.position.y = _logical_size.y - 200 - 385.76 * (1.0 - decoration_progress)
	hammer.position.y = _logical_size.y - 218

func _reveal_selection() -> void:
	if _selected_node.is_empty(): return
	var bounds: Rect2 = _selected_node.button.get_rect()
	var visible_height := scroll.size.y
	if bounds.end.y > visible_height: scroll.scroll_vertical = int(bounds.end.y - visible_height + 12)

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		_cancel_drag()
		return
	if _opening and not _closing:
		_open_elapsed = minf(0.5, _open_elapsed + delta * float(DungeonSettings.read_options().ui_speed))
		_apply_open(minf(1.0, _open_elapsed * 3.0))
		_animate_decorations(_open_elapsed)
		_opening = _open_elapsed < 0.5
	_selection_time = fposmod(_selection_time + delta * float(DungeonSettings.read_options().ui_speed), 1.0)
	_animate_selection()

func _animate_decorations(time: float) -> void:
	for curve in _rotation_curves:
		var keys: Array = curve.curve.m_Curve
		var rotation := _quaternion(keys.back().value)
		for index in range(1, keys.size()):
			if time > float(keys[index].time): continue
			var weight := inverse_lerp(float(keys[index - 1].time), float(keys[index].time), time)
			rotation = _quaternion(keys[index - 1].value).slerp(_quaternion(keys[index].value), clampf(weight, 0.0, 1.0))
			break
		var axis_x := 1.0 - 2.0 * (rotation.y * rotation.y + rotation.z * rotation.z)
		var axis_y := 2.0 * (rotation.x * rotation.y + rotation.z * rotation.w)
		if curve.path == "Wood": wood.rotation = atan2(axis_y, -axis_x)
		elif curve.path == "Hammer": hammer.rotation = atan2(-axis_y, axis_x)

static func _quaternion(value: Dictionary) -> Quaternion:
	return Quaternion(float(value.x), float(value.y), float(value.z), float(value.w)).normalized()

func _animate_selection() -> void:
	if _selected_node.is_empty(): return
	# APK Anim_Select uses zero-slope keys at 0, 0.5 and 1 second.
	var half := _selection_time * 2.0 if _selection_time < 0.5 else (1.0 - _selection_time) * 2.0
	var offset := lerpf(6.4, -6.4, smoothstep(0.0, 1.0, half))
	_selected_node.left.position = Vector2(-19 + offset, 54)
	_selected_node.right.position = Vector2(141 - offset, 54)

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree(): return
	if _closing:
		get_viewport().set_input_as_handled()
		return
	if _opening and (event is InputEventMouse or event is InputEventScreenTouch or event is InputEventScreenDrag):
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(help_dialog): return
	var point := Vector2.ZERO
	var pointer := -1
	var pressed := false
	var released := false
	var moved := false
	var canceled := false
	if event is InputEventScreenTouch:
		point = event.position
		pointer = event.index
		pressed = event.pressed and not event.canceled
		released = not event.pressed or event.canceled
		canceled = event.canceled
	elif event is InputEventScreenDrag:
		point = event.position
		pointer = event.index
		moved = true
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.device != -1:
		point = event.position
		pointer = -2
		pressed = event.pressed
		released = not event.pressed
	elif event is InputEventMouseMotion and event.device != -1:
		point = event.position
		pointer = -2
		moved = true
	else: return
	if pressed and _pointer == -1:
		for target in [scroll, detail_scroll]:
			if not _contains(target, point): continue
			var bar: VScrollBar = target.get_v_scroll_bar()
			if bar.visible and _contains(bar, point): return
			_pointer = pointer
			_drag_scroll = target
			_press_point = point
			_press_scroll = target.scroll_vertical
			_pressed_node = {}
			if target == scroll:
				for node in nodes:
					if _contains(node.button, point):
						_pressed_node = node
						break
			break
		if _pointer != pointer: return
	elif _pointer == pointer and moved:
		if point.distance_to(_press_point) > 10.0: _dragging = true
		if _dragging:
			var inverse := _drag_scroll.get_global_transform_with_canvas().affine_inverse()
			_drag_scroll.scroll_vertical = _press_scroll + int((inverse * _press_point).y - (inverse * point).y)
	elif _pointer == pointer and released:
		var activate := not canceled and not _dragging and not _pressed_node.is_empty() and _contains(_pressed_node.button, point) and _contains(scroll, point)
		var node := _pressed_node
		_cancel_drag()
		if activate: select_stage(node.id, node.stage)
	else: return
	get_viewport().set_input_as_handled()

static func _contains(control: Control, point: Vector2) -> bool:
	return Rect2(Vector2.ZERO, control.size).has_point(control.get_global_transform_with_canvas().affine_inverse() * point)

func _cancel_drag() -> void:
	_pointer = -1
	_drag_scroll = null
	_dragging = false
	_pressed_node = {}

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]: _cancel_drag()

func _layout() -> void:
	if not is_instance_valid(canvas): return
	var factor = minf(1.0, minf(size.x / 1500.0, size.y / 700.0))
	canvas.scale = Vector2.ONE * factor
	_logical_size = size / maxf(0.1, factor)
	canvas.size = _logical_size
	decoration_canvas.size = _logical_size
	decoration_canvas.scale = Vector2.ONE * factor
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
		node.button.position = Vector2(32 + float(node.stage) * (graph_width - 224) / 2.0, 12 + node.row * 190)
		node.button.size = Vector2(160, 170)
	for line in connectors:
		var grid: Vector2i = line.get_meta("grid")
		line.position = Vector2(112 + grid.x * (graph_width - 224) / 2.0, 81 + grid.y * 190)
		line.size = Vector2((graph_width - 224) / 2.0, 5)
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
	wood.pivot_offset = wood.size * 0.5
	hammer.position = Vector2(_logical_size.x - 181, _logical_size.y - 218)
	hammer.size = Vector2(240, 240)
	hammer.pivot_offset = hammer.size * Vector2(0.71703285, 0.86340463)
	_apply_open(_open_progress)
