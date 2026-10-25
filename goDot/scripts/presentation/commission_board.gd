class_name DungeonCommissionBoard
extends Control

signal command(kind: String, id: Variant, extra: Variant)

const INK = Color("263844")
const PAPER = Color("fffdf7")
var systems
var catalog
var selected_group = 0
var group_buttons: Dictionary = {}
var task_buttons: Dictionary = {}
var task_bars: Dictionary = {}
var footer_button: Button
var sidebar: ScrollContainer
var task_scroll: ScrollContainer
var footer: PanelContainer
var _groups: Array = []
var _body: HBoxContainer
var _rail: VBoxContainer
var _tasks: VBoxContainer
var _right: VBoxContainer
var _context: Dictionary = {}
var _compact = false

func configure(_host: DungeonMenuPage, _rows: Array, context: Dictionary) -> void:
	systems = context.get("systems")
	catalog = context.get("catalog")
	_context = context
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	if systems == null or catalog == null: return
	_groups = catalog.rows("AchieveData").duplicate()
	_groups.sort_custom(func(a, b): return int(a.get("order_index", 0)) < int(b.get("order_index", 0)))
	selected_group = int(context.get("group_id", 0))
	if catalog.find("AchieveData", selected_group).is_empty() and not _groups.is_empty(): selected_group = int(_groups[0].id)
	_context["group_id"] = selected_group
	resized.connect(_adapt)
	_build()

func _label(value: String, font_size: int = 18, color: Color = INK) -> Label:
	var label = DungeonStyle.label(value, font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _flat(color: Color, border: Color = Color.TRANSPARENT, margin: int = 10) -> StyleBoxFlat:
	var style = DungeonStyle.box(color, border)
	style.set_corner_radius_all(0)
	style.set_content_margin_all(margin)
	return style

func _skin(key: String, edges: Vector4 = Vector4(14, 14, 14, 14), tint: Color = Color.WHITE, margin: int = 8) -> StyleBox:
	var texture = DungeonStyle.texture(key)
	if texture == null: return _flat(PAPER * tint, Color("c5bca4"), margin)
	var style = StyleBoxTexture.new()
	style.texture = texture
	style.texture_margin_left = edges.x
	style.texture_margin_top = edges.y
	style.texture_margin_right = edges.z
	style.texture_margin_bottom = edges.w
	style.modulate_color = tint
	style.set_content_margin_all(margin)
	return style

func _button(text: String, action: String, id: int, disabled: bool = false) -> Button:
	var button = Button.new()
	button.text = text
	button.disabled = disabled
	button.custom_minimum_size = Vector2(74 if _compact else 108, 34 if _compact else 46)
	button.add_theme_font_size_override("font_size", 14 if _compact else 18)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_disabled_color", Color("344c58"))
	for state in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(state, _skin("商店按钮_底", Vector4(32, 12, 32, 12), Color("a7aba5") if state == "disabled" else Color("fff3bf") if state == "hover" else Color.WHITE, 5))
	button.pressed.connect(func(): command.emit(action, id, 0))
	return button

func _build() -> void:
	for child in get_children(): remove_child(child); child.queue_free()
	group_buttons.clear()
	task_buttons.clear()
	task_bars.clear()
	_compact = size.y > 0 and (size.y < 500 or size.x < 1000)
	_body = HBoxContainer.new()
	_body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_body.add_theme_constant_override("separation", 0)
	add_child(_body)
	var rail_panel = PanelContainer.new()
	rail_panel.add_theme_stylebox_override("panel", _flat(Color("dadbd5"), Color("bfc3bc"), 5 if _compact else 12))
	_body.add_child(rail_panel)
	sidebar = ScrollContainer.new()
	sidebar.custom_minimum_size.x = 170 if _compact else 292
	sidebar.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sidebar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rail_panel.add_child(sidebar)
	_rail = VBoxContainer.new()
	_rail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rail.add_theme_constant_override("separation", 5 if _compact else 10)
	sidebar.add_child(_rail)
	_right = VBoxContainer.new()
	_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right.add_theme_constant_override("separation", 0)
	_body.add_child(_right)
	task_scroll = ScrollContainer.new()
	task_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	task_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_right.add_child(task_scroll)
	_tasks = VBoxContainer.new()
	_tasks.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tasks.add_theme_constant_override("separation", 4 if _compact else 8)
	task_scroll.add_child(_tasks)
	footer = PanelContainer.new()
	footer.add_theme_stylebox_override("panel", _skin("几何ui-白圆角矩形", Vector4(18, 18, 18, 18), Color("fff0bc"), 7 if _compact else 16))
	_right.add_child(footer)
	_build_groups()
	_build_tasks()

func _group_state(id: int) -> Dictionary:
	var total = 0
	var claimed = 0
	var claimable = false
	var available = true
	for task in catalog.rows("SubAchieveData"):
		if int(task.group_id) != id: continue
		var status = systems.task_status(int(task.id))
		total += 1
		if status.claimed: claimed += 1
		available = bool(status.available)
		if status.available and status.complete and not status.claimed: claimable = true
	var group_claimed = systems.profile.data.claimed_achievements.has(id)
	return {"total": total, "claimed": claimed, "available": available, "group_claimed": group_claimed, "claimable": claimable or (total > 0 and claimed == total and not group_claimed), "complete": total > 0 and claimed == total}

func _build_groups() -> void:
	for group in _groups:
		var id = int(group.id)
		var status = _group_state(id)
		var button = Button.new()
		button.custom_minimum_size.y = 64 if _compact else 106
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.text = "%s\n%d / %d" % [DungeonCatalog.row_name(group), int(status.claimed), int(status.total)]
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.icon = DungeonStyle.texture(str(group.get("icon", "")))
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		button.add_theme_constant_override("icon_max_width", 44 if _compact else 76)
		button.add_theme_constant_override("h_separation", 5 if _compact else 12)
		button.add_theme_font_size_override("font_size", 13 if _compact else 17)
		button.tooltip_text = DungeonCatalog.clean(DungeonCatalog.description(group))
		for state in ["normal", "hover", "pressed"]:
			button.add_theme_stylebox_override(state, _skin("几何ui-白圆角矩形", Vector4(16, 16, 16, 16), Color("fff1c9") if id == selected_group else Color("e1e3dd"), 7))
		button.add_theme_color_override("font_color", INK if status.available else Color("7a817e"))
		button.pressed.connect(func(): select_group(id))
		_rail.add_child(button)
		group_buttons[id] = button
		if id == selected_group:
			var outline = Panel.new()
			outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
			outline.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			var selected_style = _flat(Color.TRANSPARENT, Color("bc9852"), 0)
			selected_style.set_border_width_all(3)
			selected_style.set_corner_radius_all(6)
			outline.add_theme_stylebox_override("panel", selected_style)
			button.add_child(outline)
		if status.claimable:
			var dot = DungeonStyle.picture("提示点", Vector2.ZERO)
			dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			dot.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
			dot.position = Vector2(-15, 5)
			dot.size = Vector2(12, 12)
			button.add_child(dot)

func _rewards(expression: Variant) -> Control:
	var line = HBoxContainer.new()
	line.add_theme_constant_override("separation", 7 if _compact else 12)
	for material_id in systems.costs(expression):
		var frame = PanelContainer.new()
		frame.custom_minimum_size = Vector2(44, 48) if _compact else Vector2(64, 72)
		frame.add_theme_stylebox_override("panel", _skin("slotfg_rare_square_1_v2", Vector4(12, 12, 12, 12), Color.WHITE, 4))
		line.add_child(frame)
		var reward = VBoxContainer.new()
		reward.add_theme_constant_override("separation", 0)
		frame.add_child(reward)
		var icon = "sprite_materialicon_" + str(material_id)
		if DungeonStyle.texture(icon) == null: icon = "material:" + str(material_id)
		var picture = DungeonStyle.picture(icon, Vector2(24, 24) if _compact else Vector2(36, 36))
		reward.add_child(picture)
		var count = _label("x%d" % int(systems.costs(expression)[material_id]), 13 if _compact else 17)
		count.add_theme_color_override("font_color", Color("fff8dc"))
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count.autowrap_mode = TextServer.AUTOWRAP_OFF
		reward.add_child(count)
		line.tooltip_text += "%s x%d\n" % [DungeonCatalog.clean(systems.material_name(int(material_id))), int(systems.costs(expression)[material_id])]
	return line

func _build_tasks() -> void:
	for task in catalog.rows("SubAchieveData"):
		if int(task.group_id) != selected_group: continue
		var id = int(task.id)
		var status = systems.task_status(id)
		var panel = PanelContainer.new()
		panel.add_theme_stylebox_override("panel", _skin("几何ui-白圆角矩形", Vector4(14, 14, 14, 14), Color.WHITE, 7 if _compact else 14))
		panel.custom_minimum_size.y = 79 if _compact else 118
		_tasks.add_child(panel)
		var line = HBoxContainer.new()
		line.add_theme_constant_override("separation", 9 if _compact else 22)
		panel.add_child(line)
		var content = VBoxContainer.new()
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.add_theme_constant_override("separation", 3 if _compact else 7)
		line.add_child(content)
		content.add_child(_label(DungeonCatalog.row_name(task), 15 if _compact else 21))
		var text = DungeonCatalog.clean(str(status.get("description", "")))
		var description = _label(text, 12 if _compact else 16, Color("58676a"))
		content.add_child(description)
		var progress_line = HBoxContainer.new()
		content.add_child(progress_line)
		var bar = ProgressBar.new()
		bar.custom_minimum_size.y = 10 if _compact else 14
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.max_value = maxi(1, int(status.required))
		bar.value = mini(int(status.current), int(bar.max_value))
		bar.show_percentage = false
		bar.add_theme_stylebox_override("background", _skin("底部进度条底", Vector4(7, 0, 7, 0), Color.WHITE, 0))
		bar.add_theme_stylebox_override("fill", _skin("分割线高亮-有进度顶", Vector4(5, 0, 5, 0), Color("d4ba6d"), 0))
		progress_line.add_child(bar)
		task_bars[id] = bar
		var amount = _label("%d / %d" % [mini(int(status.current), int(status.required)), int(status.required)], 12 if _compact else 15)
		amount.autowrap_mode = TextServer.AUTOWRAP_OFF
		progress_line.add_child(amount)
		var rewards_and_action = VBoxContainer.new()
		rewards_and_action.alignment = BoxContainer.ALIGNMENT_CENTER
		line.add_child(rewards_and_action)
		rewards_and_action.add_child(_rewards(task.reward_get_materials))
		var action = _button("已领取" if status.claimed else "领取" if status.complete and status.available else "进行中" if status.available else "未解锁", "op:claim_task", id, status.claimed or not status.complete or not status.available)
		action.tooltip_text = text
		rewards_and_action.add_child(action)
		task_buttons[id] = action
	var group = catalog.find("AchieveData", selected_group)
	var state = _group_state(selected_group)
	var footer_line = HBoxContainer.new()
	footer_line.add_theme_constant_override("separation", 10)
	footer.add_child(footer_line)
	var summary = VBoxContainer.new()
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_line.add_child(summary)
	summary.add_child(_label("全部完成奖励", 15 if _compact else 21))
	summary.add_child(_label("已领取委托 %d / %d" % [int(state.claimed), int(state.total)], 12 if _compact else 16, Color("657479")))
	footer_line.add_child(_rewards(group.get("reward_get_materials", "")))
	footer_button = _button("已领取" if state.group_claimed else "领取奖励", "op:claim_achievement", selected_group, state.group_claimed or not state.complete or not state.available)
	footer_line.add_child(footer_button)

func select_group(id: int) -> void:
	if catalog.find("AchieveData", id).is_empty(): return
	selected_group = id
	_context["group_id"] = id
	var scroll_y = sidebar.scroll_vertical if is_instance_valid(sidebar) else 0
	_build()
	sidebar.set_deferred("scroll_vertical", scroll_y)

func refresh() -> void:
	if systems != null: select_group(selected_group)

func _adapt() -> void:
	if systems == null or size.x <= 0 or size.y <= 0: return
	var compact = size.y < 500 or size.x < 1000
	if compact != _compact:
		_compact = compact
		_build()
