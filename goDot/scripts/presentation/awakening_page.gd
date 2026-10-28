class_name DungeonAwakeningPage
extends Control

signal command(kind: String, id: Variant, extra: Variant)
signal closed
signal back_requested

const INK := Color("303e39")
const MUTED := Color("65746d")
const GREEN := Color("397459")
const RED := Color("985646")
const ROLE_NAVIGATION = preload("res://scripts/presentation/role_navigation.gd")
var systems
var catalog
var owner_page: DungeonMenuPage
var context: Dictionary = {}
var selected_character := 1
var selected_awakening := 0
var node_buttons: Dictionary = {}
var character_buttons: Dictionary = {}
var node_rows: Array = []
var collection_scroll: ScrollContainer
var detail_scroll: ScrollContainer
var character_scroll: ScrollContainer
var collection: GridContainer
var details: VBoxContainer
var body: BoxContainer
var summary_label: Label
var budget_label: Label
var unlock_button: Button
var toggle_button: Button
var selected_status: Dictionary = {}
var _compact := false
var _portrait := false

func configure(host: DungeonMenuPage, _rows: Array, page_context: Dictionary = {}) -> void:
	owner_page = host
	context = page_context
	systems = context.get("systems")
	catalog = context.get("catalog")
	if systems == null or catalog == null: return
	selected_character = int(context.get("awakening_character_id", context.get("character_id", systems.profile.data.selected_character)))
	selected_awakening = int(context.get("selected_awakening", 0))
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	clip_contents = true
	theme = DungeonStyle.theme()
	resized.connect(_adapt)
	_build()

func _label(text: String, font_size := 18, color := INK) -> Label:
	var label = DungeonStyle.label(DungeonCatalog.clean(text), font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _style(fill: Color, border := Color("9aa9a1"), margin := 8) -> StyleBoxFlat:
	var style = DungeonStyle.box(fill, border, 1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(margin)
	return style

func _button(text: String, callback: Callable, disabled := false) -> Button:
	var button = Button.new()
	button.text = text
	button.disabled = disabled
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.custom_minimum_size = Vector2(44, 40 if _compact else 48)
	button.add_theme_font_size_override("font_size", 14 if _compact else 18)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_disabled_color", MUTED)
	button.add_theme_stylebox_override("normal", _style(Color("eef1e9")))
	button.add_theme_stylebox_override("hover", _style(Color("fff4ce"), Color("a98a47")))
	button.add_theme_stylebox_override("pressed", _style(Color("e1d6af"), Color("8f7845")))
	button.add_theme_stylebox_override("disabled", _style(Color("d5dbd6")))
	button.add_theme_stylebox_override("focus", _style(Color.TRANSPARENT, Color("ae8743"), 0))
	button.pressed.connect(callback)
	return button

func _set_context(key: String, value: Variant) -> void:
	context[key] = value
	if is_instance_valid(owner_page): owner_page.page_context[key] = value

func _build() -> void:
	var collection_y = int(context.get("awakening_collection_scroll", 0))
	var detail_y = int(context.get("awakening_detail_scroll", 0))
	for child in get_children(): remove_child(child); child.queue_free()
	node_buttons.clear()
	character_buttons.clear()
	_compact = size.y > 0 and (size.y < 600 or size.x < 1000)
	_portrait = size.x > 0 and size.x < 650
	var background = ColorRect.new()
	background.color = Color("d7dfd9")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin = MarginContainer.new()
	margin.name = "AwakeningMargin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 10 if _compact else 24)
	var safe_margin = ROLE_NAVIGATION.header_margin(size)
	margin.add_theme_constant_override("margin_left", int(safe_margin.x))
	margin.add_theme_constant_override("margin_top", int(safe_margin.y))
	add_child(margin)
	var stack = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8 if _compact else 16)
	margin.add_child(stack)
	var heading = HBoxContainer.new()
	heading.add_theme_constant_override("separation", 10)
	stack.add_child(heading)
	var back = ROLE_NAVIGATION.create_header_back_button(size, "返回" if context.has("back_action") else "关闭")
	back.name = "AwakeningBack"
	back.pressed.connect(func(): back_requested.emit())
	heading.add_child(back)
	var title = _label("角色觉醒", 20 if _compact else 28)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var progress = systems.awakening_progress()
	summary_label = _label("Lv.%d / %d\n结晶 %d" % [int(progress.level), int(progress.maximum), int(progress.total)], 12 if _compact else 17)
	summary_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	heading.add_child(summary_label)
	var close = _button("×", func(): closed.emit())
	close.tooltip_text = "关闭"
	heading.add_child(close)
	var toolbar = HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 10)
	stack.add_child(toolbar)
	character_scroll = ScrollContainer.new()
	character_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	character_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	character_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	toolbar.add_child(character_scroll)
	var characters = HBoxContainer.new()
	characters.add_theme_constant_override("separation", 6)
	character_scroll.add_child(characters)
	for row in catalog.rows("CharData"):
		if str(row.get("available_state", "Normal")) != "Normal": continue
		var id = int(row.id)
		var button = _button("", func(): select_character(id))
		button.custom_minimum_size = Vector2(44, 44) if _compact else Vector2(60, 60)
		button.icon = DungeonStyle.texture(str(row.get("square_icon_name", "")))
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.add_theme_constant_override("icon_max_width", 34 if _compact else 48)
		button.tooltip_text = DungeonCatalog.row_name(row) + ("" if systems.rank(systems.profile.data.character_levels, id) > 0 else " · 尚未招募")
		if systems.rank(systems.profile.data.character_levels, id) == 0: button.add_theme_color_override("icon_normal_color", Color("858e87"))
		if id == selected_character: button.add_theme_stylebox_override("normal", _style(Color("fff0bb"), Color("a0803f"), 4))
		characters.add_child(button)
		character_buttons[id] = button
	if not character_buttons.has(selected_character) and not character_buttons.is_empty(): selected_character = int(character_buttons.keys()[0])
	var budget = VBoxContainer.new()
	budget.custom_minimum_size.x = 106 if _compact else 160
	toolbar.add_child(budget)
	budget.add_child(_label(DungeonCatalog.row_name(catalog.find("CharData", selected_character)), 16 if _compact else 22))
	budget_label = _label("", 12 if _compact else 16, GREEN)
	budget.add_child(budget_label)
	if not _compact:
		var advancement = HBoxContainer.new()
		stack.add_child(advancement)
		var next_level = "觉醒等级已满" if int(progress.required) == 0 else "下一级 %d / %d" % [int(progress.progress), int(progress.required)]
		var level_text = _label(next_level, 16, MUTED)
		level_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		advancement.add_child(level_text)
		var rewards = _button("混沌奖励", func(): command.emit("page:difficulty", 10, 0))
		rewards.custom_minimum_size.x = 140
		advancement.add_child(rewards)
	body = VBoxContainer.new() if _portrait else HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12 if _compact else 24)
	stack.add_child(body)
	collection_scroll = ScrollContainer.new()
	collection_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	collection_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	collection_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	collection_scroll.size_flags_stretch_ratio = 1.45
	body.add_child(collection_scroll)
	collection_scroll.get_v_scroll_bar().value_changed.connect(func(value): _set_context("awakening_collection_scroll", int(value)))
	collection = GridContainer.new()
	collection.columns = 2 if _compact else 3
	collection.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	collection.add_theme_constant_override("h_separation", 8)
	collection.add_theme_constant_override("v_separation", 8)
	collection_scroll.add_child(collection)
	detail_scroll = ScrollContainer.new()
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if not _portrait: detail_scroll.custom_minimum_size.x = 220 if _compact else 320
	body.add_child(detail_scroll)
	detail_scroll.get_v_scroll_bar().value_changed.connect(func(value): _set_context("awakening_detail_scroll", int(value)))
	details = VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 8 if _compact else 14)
	detail_scroll.add_child(details)
	_build_nodes()
	_show_detail(false)
	collection_scroll.set_deferred("scroll_vertical", collection_y)
	detail_scroll.set_deferred("scroll_vertical", detail_y)
	character_scroll.ensure_control_visible.call_deferred(character_buttons.get(selected_character))

func _build_nodes() -> void:
	node_rows = catalog.rows("CharaTalentAwakeTreeData").filter(func(row): return int(row.chara_id) == selected_character and not bool(row.get("is_admin_mode", false)) and bool(row.get("is_enabled", true)))
	node_rows.sort_custom(func(a, b): return int(a.unlock_awake_tree_level) < int(b.unlock_awake_tree_level) if int(a.unlock_awake_tree_level) != int(b.unlock_awake_tree_level) else int(a.id) < int(b.id))
	if not node_rows.any(func(row): return int(row.id) == selected_awakening): selected_awakening = int(node_rows[0].id) if not node_rows.is_empty() else 0
	_set_context("awakening_character_id", selected_character)
	_set_context("selected_awakening", selected_awakening)
	for row in node_rows:
		var id = int(row.id)
		var status = systems.awakening_status(id)
		var state = "已激活" if status.active else "已解锁" if status.unlocked else "可解锁" if status.can_unlock else "未解锁"
		var button = _button("Lv.%d · %d点\n%s\n%s" % [int(row.unlock_awake_tree_level), int(row.active_need_awake_point), DungeonCatalog.clean(DungeonCatalog.row_name(row)), state], func(): select_awakening(id))
		button.custom_minimum_size = Vector2(0, 104 if _compact else 132)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.icon = _node_icon(row)
		if DungeonStyle.texture(str(row.get("icon_name", ""))) != null:
			for state_name in ["normal", "hover", "pressed", "focus"]: button.add_theme_color_override("icon_" + state_name + "_color", Color("486654"))
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 40 if _compact else 60)
		button.add_theme_font_size_override("font_size", 12 if _compact else 16)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.tooltip_text = DungeonCatalog.clean(DungeonCatalog.row_name(row)) + "\n" + state + "\n" + str(status.activation_reason if status.unlocked else status.reason)
		button.set_meta("node_id", id)
		collection.add_child(button)
		node_buttons[id] = button
		_style_node(id, status)
	if node_rows.is_empty(): collection.add_child(_label("暂无觉醒节点", 18, MUTED))

func _node_icon(row: Dictionary) -> Texture2D:
	var icon = DungeonStyle.texture(str(row.get("icon_name", "")))
	if icon != null: return icon
	return DungeonStyle.texture(str(catalog.find("CharData", int(row.chara_id)).get("square_icon_name", "")))

func _style_node(id: int, status: Dictionary) -> void:
	var selected = id == selected_awakening
	var fill = Color("f8eecf") if selected else Color("d2e6d8") if status.active else Color("eef1e9") if status.unlocked or status.can_unlock else Color("cbd3ce")
	var border = Color("a0803f") if selected else Color("538569") if status.active else Color("a0ada5")
	node_buttons[id].add_theme_stylebox_override("normal", _style(fill, border))

func _show_detail(reset_scroll := true) -> void:
	if reset_scroll:
		_set_context("awakening_detail_scroll", 0)
		detail_scroll.scroll_vertical = 0
	for child in details.get_children(): details.remove_child(child); child.queue_free()
	unlock_button = null
	toggle_button = null
	var row = catalog.find("CharaTalentAwakeTreeData", selected_awakening)
	if row.is_empty(): return
	selected_status = systems.awakening_status(selected_awakening)
	budget_label.text = "潜能点 %d / %d" % [int(selected_status.used_points), int(selected_status.points)]
	var heading = HBoxContainer.new()
	details.add_child(heading)
	var image = TextureRect.new()
	image.texture = _node_icon(row)
	if DungeonStyle.texture(str(row.get("icon_name", ""))) != null: image.modulate = Color("486654")
	image.custom_minimum_size = Vector2(44, 44) if _compact else Vector2(68, 68)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	heading.add_child(image)
	var title = _label(DungeonCatalog.row_name(row), 18 if _compact else 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var state = "已激活" if selected_status.active else "已解锁" if selected_status.unlocked else "待解锁"
	details.add_child(_label(state + " · 需要觉醒 Lv.%d" % int(row.unlock_awake_tree_level), 13 if _compact else 17, GREEN if selected_status.active else MUTED))
	var description = SourceRichText.new()
	description.name = "AwakeningDescription"
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	description.add_theme_font_size_override("normal_font_size", 14 if _compact else 18)
	description.add_theme_color_override("default_color", INK)
	description.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	description.set_source(DungeonCatalog.description(row))
	details.add_child(description)
	var talent_id = int(row.get("link_chara_talent_id", 0))
	if talent_id > 0: details.add_child(_label("关联天赋：" + DungeonCatalog.row_name(catalog.find("CharTalentData", talent_id)), 12 if _compact else 16, MUTED))
	details.add_child(_label("激活消耗 %d 潜能点 · 剩余 %d" % [int(selected_status.cost_points), maxi(0, int(selected_status.points) - int(selected_status.used_points))], 13 if _compact else 17, GREEN))
	if not selected_status.unlocked:
		for key in selected_status.price:
			var amount = int(selected_status.price[key])
			if amount <= 0: continue
			var cost = HBoxContainer.new()
			details.add_child(cost)
			cost.add_child(DungeonStyle.picture("material:" + str(key), Vector2(24, 24) if _compact else Vector2(32, 32)))
			var owned = systems.material(int(key))
			var price = _label("%s  %d / %d" % [DungeonCatalog.clean(systems.material_name(int(key))), owned, amount], 13 if _compact else 17, GREEN if owned >= amount else RED)
			price.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cost.add_child(price)
	var reason = str(selected_status.activation_reason if selected_status.unlocked else selected_status.reason)
	if not reason.is_empty(): details.add_child(_label(reason, 13 if _compact else 17, RED))
	unlock_button = _button("已解锁" if selected_status.unlocked else "解锁", func(): command.emit("op:unlock_awakening", selected_awakening, 0), not selected_status.can_unlock)
	unlock_button.set_meta("command", {"action": "op:unlock_awakening", "id": selected_awakening})
	details.add_child(unlock_button)
	toggle_button = _button("停用" if selected_status.active else "激活", func(): command.emit("op:toggle_awakening", selected_awakening, 0), not selected_status.can_toggle)
	toggle_button.set_meta("command", {"action": "op:toggle_awakening", "id": selected_awakening})
	details.add_child(toggle_button)
	if _compact:
		var progress = systems.awakening_progress()
		details.add_child(_label("觉醒等级已满" if int(progress.required) == 0 else "下一级 %d / %d" % [int(progress.progress), int(progress.required)], 12, MUTED))
		details.add_child(_button("混沌奖励", func(): command.emit("page:difficulty", 10, 0)))

func select_character(id: int) -> void:
	if not character_buttons.has(id) or id == selected_character: return
	selected_character = id
	selected_awakening = 0
	_set_context("awakening_collection_scroll", 0)
	_set_context("awakening_detail_scroll", 0)
	_build()

func select_awakening(id: int) -> void:
	if not node_buttons.has(id) or id == selected_awakening: return
	selected_awakening = id
	_set_context("selected_awakening", id)
	for node_id in node_buttons: _style_node(int(node_id), systems.awakening_status(int(node_id)))
	_show_detail()

func refresh() -> void:
	if systems != null: _build()

func _adapt() -> void:
	if systems == null or size.x <= 0 or size.y <= 0: return
	var compact = size.y < 600 or size.x < 1000
	var portrait = size.x < 650
	if compact != _compact or portrait != _portrait: _build()
	var back = find_child("AwakeningBack", true, false)
	if back is Button: ROLE_NAVIGATION.configure_header_back_button(back, size, "返回" if context.has("back_action") else "关闭")
	var margin = find_child("AwakeningMargin", true, false)
	if margin is MarginContainer:
		var safe_margin = ROLE_NAVIGATION.header_margin(size)
		margin.add_theme_constant_override("margin_left", int(safe_margin.x))
		margin.add_theme_constant_override("margin_top", int(safe_margin.y))
