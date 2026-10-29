extends Control

signal command(kind: String, id: Variant, extra: Variant)
signal closed

const INK = Color("101b20")
const PAPER = Color("eeeae0")
const GOLD = Color("c7ae6e")
const NAVIGATION = preload("res://scripts/presentation/role_navigation.gd")
const ART_ROOT = "res://assets/ui/room_shop/"
const RARITIES = [Color("737b79"), Color("56893c"), Color("3280a4"), Color("a045ab"), Color("c2a344")]
static var _art_map: Dictionary = {}
var rows: Array = []
var context: Dictionary = {}
var header: Control
var magic_text: Label
var free_text: Label
var search_text: Label
var merchant: TextureRect
var investment: PanelContainer
var level_text: Label
var next_text: Label
var remaining_text: Label
var deposit: Button
var refresh: Button
var refresh_cost: Label
var tabs: HBoxContainer
var purchase_tab: Button
var seal_tab: Button
var scroll: ScrollContainer
var grid: GridContainer
var empty: Label
var footer: Button
var cards: Array[Control] = []
var modal: Control
var _mode := "buy"
var _built := false
var _compact := false

func _art(key: String) -> Texture2D:
	if _art_map.is_empty():
		_art_map = JSON.parse_string(FileAccess.get_file_as_string(ART_ROOT + "resource_map.json"))
	return load(str(_art_map[key])) as Texture2D if _art_map.has(key) else DungeonStyle.texture(key)

func _source_box(key: String, tint := Color.WHITE, margin := 0.0) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = _art(key)
	box.modulate_color = tint
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]: box.set_texture_margin(side, margin)
	return box

func configure(data: Array, state: Dictionary) -> void:
	rows = data
	context = state
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	if not _built: _build()
	_close_modal()
	_update_state()
	_select_mode(str(context.get("mode", "buy")), false)
	_layout.call_deferred()

func _build() -> void:
	_built = true
	var shade = ColorRect.new()
	shade.color = Color(0.035, 0.065, 0.075, 0.56)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	header = Control.new()
	add_child(header)
	var back = NAVIGATION.create_back_button("返回房间")
	back.name = "Back"
	back.pressed.connect(func(): closed.emit())
	header.add_child(back)
	var title = DungeonStyle.picture("", Vector2.ZERO)
	title.texture = _art("迷宫商店")
	title.name = "Title"
	header.add_child(title)
	var resources = HBoxContainer.new()
	resources.name = "Resources"
	resources.add_theme_constant_override("separation", 14)
	header.add_child(resources)
	for item in [["sprite_materialicon_102", str(context.get("magic", 0))], ["sprite_abilityitemicon_15101", "%d/%d" % [int(context.get("search", 0)), int(context.get("search_max", 3))]]]:
		var holder = PanelContainer.new()
		holder.add_theme_stylebox_override("panel", _source_box("货币_底", Color.WHITE, 16))
		resources.add_child(holder)
		var line = HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		holder.add_child(line)
		var icon = DungeonStyle.picture("", Vector2(30, 30))
		icon.texture = _art(item[0])
		line.add_child(icon)
		var value = _label(item[1], 24, PAPER)
		value.custom_minimum_size.x = 75
		line.add_child(value)
		if magic_text == null: magic_text = value
		else: search_text = value
	free_text = _label("", 16, PAPER)
	free_text.name = "FreePurchases"
	add_child(free_text)
	merchant = DungeonStyle.picture("res://assets/ui/camp/portraits/characterillustration_shangdian_normal.png", Vector2.ZERO)
	merchant.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(merchant)
	investment = PanelContainer.new()
	investment.add_theme_stylebox_override("panel", _source_box("31", Color(1, 1, 1, 0.84), 24))
	add_child(investment)
	var stack = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 7)
	investment.add_child(stack)
	var status: Dictionary = context.get("shop", {})
	level_text = _stat_line(stack, "当前商店等级：", str(status.get("level", 1)))
	next_text = _stat_line(stack, "距离下一级：", "最高等级" if status.get("max_level", false) else str(status.get("next_needed", 0)))
	remaining_text = _stat_line(stack, "剩余存入次数：", str(status.get("remaining", 0)))
	var space = Control.new()
	space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(space)
	var actions = HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	stack.add_child(actions)
	var info = _button("等级详情")
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.pressed.connect(_show_levels)
	actions.add_child(info)
	deposit = _button("%d 存入" % int(status.get("deposit", 0)))
	deposit.icon = _art("sprite_materialicon_102")
	deposit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deposit.disabled = bool(status.get("max_level", false)) or int(status.get("remaining", 0)) <= 0 or int(context.get("magic", 0)) < int(status.get("deposit", 0))
	deposit.tooltip_text = "本局存入次数已用完" if int(status.get("remaining", 0)) <= 0 else "魔力不足" if int(context.get("magic", 0)) < int(status.get("deposit", 0)) else "商店已达最高等级" if status.get("max_level", false) else "存入商店"
	deposit.pressed.connect(func(): command.emit("invest_room_shop", int(context.get("shop", {}).get("deposit", 0)), 0))
	actions.add_child(deposit)
	tabs = HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 0)
	add_child(tabs)
	purchase_tab = _button("购买", "sprite_conversation_buy")
	seal_tab = _button("封印", "sprite_conversation_crystallize")
	purchase_tab.icon = _art("已解锁遗物")
	seal_tab.icon = _art("解锁")
	for tab in [purchase_tab, seal_tab]:
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.toggle_mode = true
		for state in ["normal", "hover", "pressed"]:
			tab.add_theme_color_override("font_color" if state == "normal" else "font_" + state + "_color", PAPER)
			tab.add_theme_stylebox_override(state, _source_box("6", Color(1, 1, 1, 0.9 if state == "pressed" else 0.45)))
		tabs.add_child(tab)
	purchase_tab.pressed.connect(func(): _select_mode("buy"))
	seal_tab.pressed.connect(func(): _select_mode("seal"))
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	grid = GridContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 16)
	scroll.add_child(grid)
	empty = _label("暂无可封印的遗物", 22, PAPER)
	empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(empty)
	refresh = _button("")
	refresh.icon = _art("Button_Refresh")
	refresh.add_theme_constant_override("icon_max_width", 64)
	for state in ["normal", "hover", "pressed", "disabled"]: refresh.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	refresh.tooltip_text = str(status.get("refresh_reason", "")) if not status.get("can_refresh", true) else "刷新商品 · 剩余 %d 次" % int(status.get("refresh_remaining", 0))
	if not refresh.icon: refresh.text = "↻"
	refresh.disabled = not bool(status.get("can_refresh", int(status.get("refresh_remaining", 0)) > 0))
	refresh.pressed.connect(func(): command.emit("refresh_room_shop", 0, 0))
	add_child(refresh)
	refresh_cost = _label("%d 魔力" % int(status.get("refresh_cost", 0)) if int(status.get("refresh_cost", 0)) > 0 else "", 14, PAPER)
	refresh_cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(refresh_cost)
	footer = _button("继续前进", "sprite_conversation_leave")
	footer.pressed.connect(func():
		if context.get("return_to_room", false): closed.emit()
		else: command.emit("finish_noncombat", 0, 0))
	add_child(footer)
	resized.connect(_layout)

func _update_state() -> void:
	footer.text = "返回房间" if context.get("return_to_room", false) else "继续前进"
	footer.visible = not context.get("return_to_room", false)
	var status: Dictionary = context.get("shop", {})
	magic_text.text = str(context.get("magic", 0))
	free_text.text = str(context.get("free", 0))
	free_text.visible = int(context.get("free", 0)) > 0
	free_text.tooltip_text = "剩余免费购买次数"
	search_text.text = "%d/%d" % [int(context.get("search", 0)), int(context.get("search_max", 3))]
	level_text.text = str(status.get("level", 1))
	next_text.text = "最高等级" if status.get("max_level", false) else str(status.get("next_needed", 0))
	remaining_text.text = str(status.get("remaining", 0))
	deposit.text = "%d 存入" % int(status.get("deposit", 0))
	deposit.disabled = bool(status.get("max_level", false)) or int(status.get("remaining", 0)) <= 0 or int(context.get("magic", 0)) < int(status.get("deposit", 0))
	deposit.tooltip_text = "商店已达最高等级" if status.get("max_level", false) else "本局存入次数已用完" if int(status.get("remaining", 0)) <= 0 else "魔力不足" if int(context.get("magic", 0)) < int(status.get("deposit", 0)) else "存入商店"
	refresh.disabled = not bool(status.get("can_refresh", int(status.get("refresh_remaining", 0)) > 0))
	refresh.tooltip_text = str(status.get("refresh_reason", "")) if refresh.disabled else "刷新商品 · 剩余 %d 次" % int(status.get("refresh_remaining", 0))
	refresh_cost.text = "%d 魔力" % int(status.get("refresh_cost", 0)) if int(status.get("refresh_cost", 0)) > 0 else ""

func _label(value: String, font_size: int, color: Color) -> Label:
	var label = DungeonStyle.label(value, font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _button(value: String, icon_key := "") -> Button:
	var button = Button.new()
	button.text = value
	button.icon = DungeonStyle.texture(icon_key)
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 28)
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_color_override("font_focus_color", INK)
	button.add_theme_color_override("font_disabled_color", Color("747773"))
	for state in ["normal", "hover", "pressed", "disabled"]:
		var box = _source_box("几何ui-椭圆白色按钮", Color.WHITE if state == "normal" else Color("fff7d6") if state in ["hover", "pressed"] else Color("7c8182"))
		box.set_texture_margin(SIDE_LEFT, 45)
		box.set_texture_margin(SIDE_RIGHT, 45)
		box.set_content_margin_all(5)
		button.add_theme_stylebox_override(state, box)
	return button

func _stat_line(parent: Node, title: String, value: String) -> Label:
	var panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _source_box("商店升级详情选项_底", Color.WHITE, 12))
	parent.add_child(panel)
	var line = HBoxContainer.new()
	panel.add_child(line)
	var key = _label(title, 22, PAPER)
	key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(key)
	var text = _label(value, 22, PAPER)
	line.add_child(text)
	return text

func _select_mode(value: String, announce := true) -> void:
	_mode = "seal" if value == "seal" else "buy"
	purchase_tab.set_pressed_no_signal(_mode == "buy")
	seal_tab.set_pressed_no_signal(_mode == "seal")
	for node in grid.get_children():
		grid.remove_child(node)
		node.queue_free()
	cards.clear()
	var visible_rows: Array = context.get("seal_rows", []) if _mode == "seal" else rows
	for row in visible_rows: _add_card(row)
	empty.visible = visible_rows.is_empty()
	empty.text = "暂无可封印的遗物" if _mode == "seal" else "暂无商品"
	refresh.visible = _mode == "buy"
	refresh_cost.visible = _mode == "buy"
	if announce: command.emit("room_shop_mode", _mode, 0)
	_layout.call_deferred()

func _add_card(row: Dictionary) -> void:
	var card = Button.new()
	card.clip_contents = true
	card.tooltip_text = str(row.get("title", "")) + "\n" + str(row.get("description", ""))
	card.add_theme_stylebox_override("normal", _source_box("商品_底框_1"))
	card.add_theme_stylebox_override("hover", _source_box("商品_底框_1", Color("fff8df")))
	card.add_theme_stylebox_override("pressed", _source_box("商品_底框_1", Color("e3d8b2")))
	grid.add_child(card)
	cards.append(card)
	card.set_meta("row", row)
	var title = _label(str(row.get("title", "")), 20, INK)
	title.name = "Title"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.max_lines_visible = 2
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	card.add_child(title)
	var rarity = clampi(int(row.get("rarity", 1)), 1, 5)
	title.add_theme_color_override("font_color", RARITIES[rarity - 1])
	var frame = TextureRect.new()
	frame.texture = load("res://assets/ui/role_inventory/slotfg_rare_square_%d_v2.png" % rarity)
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.name = "Frame"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(frame)
	var icon = DungeonStyle.picture(str(row.get("icon", "")), Vector2.ZERO)
	var source_icon = DungeonItemArt.source_texture(int(row.get("loot_id", 0)))
	if source_icon: icon.texture = source_icon
	icon.name = "Icon"
	frame.add_child(icon)
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 7
	icon.offset_top = 7
	icon.offset_right = -7
	icon.offset_bottom = -7
	var price_band = ColorRect.new()
	price_band.name = "PriceBand"
	price_band.color = Color("58433f")
	price_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price_band.visible = false
	card.add_child(price_band)
	var price_icon = DungeonStyle.picture("res://assets/ui/camp/portraits/sprite_materialicon_102.png", Vector2.ZERO)
	price_icon.name = "PriceIcon"
	price_icon.texture = _art("sprite_materialicon_102")
	card.add_child(price_icon)
	var price = _label(("+" if _mode == "seal" else "") + str(row.get("price", 0)) if not row.get("free", false) else "免费", 24, PAPER)
	price.name = "Price"
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(price)
	var change = int(row.get("price_change", 0))
	var change_text = "%s%s%%" % ["+" if change > 0 else "", str(snappedf(change / 10.0, 0.1))] if change != 0 else ""
	var state = _label(str(row.get("status", "")) if not str(row.get("status", "")).is_empty() else change_text, 18, Color("d24435") if change > 0 else Color("38833f") if change < 0 else Color("ffdf86"))
	state.name = "State"
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card.add_child(state)
	if row.get("sold", false) or not row.get("affordable", true) or not row.get("compatible", true):
		frame.modulate = Color(0.65, 0.65, 0.65)
		price.modulate = Color(0.65, 0.65, 0.65)
	card.pressed.connect(func(): _show_item(row))

func _layout() -> void:
	if not _built or size.x < 1 or size.y < 1: return
	_compact = size.y < 560
	var margin := 18.0 if _compact else 36.0
	var heading := 54.0 if _compact else 88.0
	header.position = Vector2.ZERO
	header.size = Vector2(size.x, heading)
	NAVIGATION.place_back_button(header.get_node("Back"), NAVIGATION.scale_factor(size))
	var back: Button = header.get_node("Back")
	header.get_node("Title").position = Vector2(back.position.x + back.size.x + 12, 8)
	header.get_node("Title").size = Vector2(140 if _compact else 230, heading - 12)
	var resources = header.get_node("Resources")
	resources.position = Vector2(header.size.x - margin - (226 if _compact else 310), 10)
	resources.size = Vector2(226 if _compact else 310, 38 if _compact else 56)
	for holder in resources.get_children():
		var line = holder.get_child(0)
		line.get_child(0).custom_minimum_size = Vector2.ONE * (22 if _compact else 30)
		line.get_child(1).custom_minimum_size.x = 60 if _compact else 95
		line.get_child(1).add_theme_font_size_override("font_size", 18 if _compact else 24)
	free_text.position = Vector2(margin, heading)
	free_text.size = Vector2(60, 24)
	var left_width = floor(size.x * 0.29)
	var right_x = floor(size.x * 0.42)
	if _compact: right_x = floor(size.x * 0.35)
	var right_width = size.x - right_x - margin
	merchant.position = Vector2(margin, heading - 6)
	merchant.size = Vector2(left_width + margin, size.y - heading - 32)
	var info_height := 160.0 if _compact else 236.0
	investment.get_theme_stylebox("panel").set_content_margin_all(8 if _compact else 12)
	investment.get_child(0).add_theme_constant_override("separation", 5 if _compact else 7)
	for line in investment.get_child(0).get_children():
		if line is PanelContainer: line = line.get_child(0)
		if line is HBoxContainer:
			for control in line.get_children():
				if control is Label: control.add_theme_font_size_override("font_size", 14 if _compact else 22)
	deposit.add_theme_font_size_override("font_size", 14 if _compact else 20)
	deposit.add_theme_constant_override("icon_max_width", 18 if _compact else 28)
	deposit.get_parent().get_child(0).add_theme_font_size_override("font_size", 14 if _compact else 20)
	var action_gap := 8.0 if _compact else 12.0
	var action_height := 36.0 if _compact else 58.0
	var price_height := 20.0 if _mode == "buy" and not refresh_cost.text.is_empty() else 0.0
	var action_y := size.y - action_height - price_height - (8 if _compact else 14)
	footer.position = Vector2(margin, action_y)
	footer.size = Vector2(left_width - action_height - action_gap, action_height)
	footer.add_theme_font_size_override("font_size", 15 if _compact else 20)
	refresh.position = Vector2(margin + left_width - action_height, action_y)
	refresh.size = Vector2(action_height, action_height)
	refresh_cost.visible = price_height > 0
	refresh_cost.position = Vector2(margin + left_width - 90, action_y + action_height)
	refresh_cost.size = Vector2(90, 20)
	investment.size = Vector2(left_width, maxf(info_height, investment.get_combined_minimum_size().y))
	investment.position = Vector2(margin, action_y - action_gap - investment.size.y)
	tabs.position = Vector2(right_x, heading)
	tabs.size = Vector2(right_width, 36 if _compact else 70)
	for tab in [purchase_tab, seal_tab]:
		tab.add_theme_font_size_override("font_size", 17 if _compact else 26)
		tab.add_theme_constant_override("icon_max_width", 20 if _compact else 38)
		for state in ["normal", "hover", "pressed"]: tab.get_theme_stylebox(state).set_content_margin_all(3 if _compact else 12)
	var list_top = heading + tabs.size.y + (10 if _compact else 18)
	scroll.position = Vector2(right_x, list_top)
	scroll.size = Vector2(right_width, size.y - list_top - (16 if _compact else 30))
	empty.position = scroll.position
	empty.size = scroll.size
	grid.columns = 4 if right_width >= 460 else 3
	var gap := 8 if _compact else 16
	grid.add_theme_constant_override("h_separation", gap)
	grid.add_theme_constant_override("v_separation", gap)
	var width = floor((right_width - 12 - gap * (grid.columns - 1)) / grid.columns)
	var height = floor(minf(width * (1.28 if _compact else 1.32), (scroll.size.y - gap) / 2.0))
	for card in cards:
		card.custom_minimum_size = Vector2(width, height)
		var title = card.get_node("Title")
		title.add_theme_font_size_override("font_size", 13 if _compact else 20)
		title.position = Vector2(5, 4)
		title.size = Vector2(width - 10, height * 0.18)
		var icon_side = floor(minf(width * 0.59, height * 0.48))
		var frame = card.get_node("Frame")
		frame.position = Vector2((width - icon_side) / 2, maxf(height * 0.24, title.position.y + title.size.y + 3))
		frame.size = Vector2(icon_side, icon_side)
		card.get_node("PriceBand").position = Vector2(3, height * 0.8)
		card.get_node("PriceBand").size = Vector2(width - 6, height * 0.2 - 3)
		card.get_node("PriceIcon").position = Vector2(width * 0.17, height * 0.825)
		card.get_node("PriceIcon").size = Vector2(height * 0.12, height * 0.12)
		card.get_node("Price").position = Vector2(width * 0.36, height * 0.8)
		card.get_node("Price").size = Vector2(width * 0.56, height * 0.2)
		card.get_node("Price").add_theme_font_size_override("font_size", 17 if _compact else 24)
		card.get_node("State").position = Vector2(3, height * 0.65)
		card.get_node("State").size = Vector2(width - 6, height * 0.15)
		card.get_node("State").add_theme_font_size_override("font_size", 12 if _compact else 18)
	if is_instance_valid(modal): _layout_modal()

func _modal_stack(title: String) -> VBoxContainer:
	_close_modal()
	modal = Control.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(modal)
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(overlay)
	var panel = PanelContainer.new()
	panel.name = "Panel"
	panel.add_theme_stylebox_override("panel", DungeonStyle.box(INK, GOLD, 2))
	modal.add_child(panel)
	var stack = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 12)
	panel.add_child(stack)
	var heading = HBoxContainer.new()
	stack.add_child(heading)
	var caption = _label(title, 24 if not _compact else 18, GOLD)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_child(caption)
	var close = NAVIGATION.create_header_back_button(size, "返回商店")
	close.pressed.connect(_close_modal)
	heading.add_child(close)
	_layout_modal.call_deferred()
	return stack

func _layout_modal() -> void:
	if not is_instance_valid(modal): return
	var panel = modal.get_node("Panel")
	panel.size = Vector2(minf(570, size.x - 48), minf(500, size.y - 40))
	panel.position = (size - panel.size) / 2

func _show_item(row: Dictionary) -> void:
	var stack = _modal_stack(str(row.get("title", "")))
	var icon = DungeonStyle.picture(str(row.get("icon", "")), Vector2(80, 80) if _compact else Vector2(120, 120))
	var source_icon = DungeonItemArt.source_texture(int(row.get("loot_id", 0)))
	if source_icon: icon.texture = source_icon
	stack.add_child(icon)
	var description = preload("res://scripts/presentation/source_rich_text.gd").new()
	description.name = "SourceDescription"
	description.add_theme_font_size_override("normal_font_size", 16 if _compact else 21)
	description.add_theme_color_override("default_color", PAPER)
	description.set_source(str(row.get("source_description", row.get("description", ""))))
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var body = ScrollContainer.new()
	body.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(body)
	body.add_child(description)
	var seal = str(row.get("action", "")) == "seal_room_loot"
	var confirm = _button("封印 · +%d 魔力" % int(row.price) if seal else "免费领取" if row.get("free", false) else "购买 · %d 魔力" % int(row.price))
	confirm.name = "Confirm"
	var reason = str(row.get("status", ""))
	if reason.is_empty(): reason = "已售罄" if row.get("sold", false) else "物品不兼容" if not row.get("compatible", true) else "魔力不足" if not row.get("affordable", true) else ""
	confirm.disabled = not reason.is_empty()
	if confirm.disabled: confirm.text = reason
	confirm.pressed.connect(func():
		_close_modal()
		command.emit(str(row.get("action", "buy_room")), int(row.get("loot_id", 0)), 0))
	stack.add_child(confirm)

func _show_levels() -> void:
	var stack = _modal_stack("商店等级详情")
	var list = ScrollContainer.new()
	list.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(list)
	var levels = VBoxContainer.new()
	levels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	levels.add_theme_constant_override("separation", 10)
	list.add_child(levels)
	for level in context.get("shop", {}).get("levels", []):
		var text = _label("等级 %d    累计存入 %d\n%s" % [int(level.Level), int(level.NeedSaveResCount), DungeonCatalog.clean(str(level.get("EffectString", "")))], 15 if _compact else 20, GOLD if int(level.Level) <= int(context.shop.get("level", 1)) else PAPER)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		levels.add_child(text)

func _close_modal() -> void:
	if is_instance_valid(modal):
		remove_child(modal)
		modal.queue_free()
	modal = null
