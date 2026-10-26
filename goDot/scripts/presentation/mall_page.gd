class_name DungeonMallPage
extends Control

signal command(kind: String, id: Variant, extra: Variant)

const INK := Color("604b36")
const GOLD := Color("d4b667")
const TABS := [["vip", "迷宫特权"], ["blessing", "祝福模式"], ["treasure", "公会宝箱"], ["rainbow", "彩虹商店"], ["bundles", "礼包商店"]]
var host: Control
var systems
var catalog
var rows: Array = []
var selected_category := "vip"
var selected_offer := 30001
var selected_box_count := 1
var category_buttons: Dictionary = {}
var offer_buttons: Dictionary = {}
var purchase_buttons: Array[Button] = []
var visible_offer_ids: Array[int] = []
var canvas: Control
var board: Control
var portrait: TextureRect
var primary_button: Button
var daily_reward: Label
var status_label: Label
var _context: Dictionary = {}
var _art: Dictionary = {}
var _logical_size := Vector2(1920, 900)
var _board_size := Vector2(1120, 690)
var _detail: VBoxContainer
var _canvas_scale := 1.0
var _layout_pending := false

func configure(owner_page: Control, data: Array, context: Dictionary) -> void:
	host = owner_page
	rows = data
	systems = context.get("systems")
	catalog = context.get("catalog")
	_context = context
	selected_category = str(context.get("mall_category", "vip"))
	if not TABS.any(func(tab): return tab[0] == selected_category): selected_category = "vip"
	selected_offer = int(context.get("selected_offer", 30001))
	selected_box_count = int(context.get("mall_box_count", 1))
	if FileAccess.file_exists("res://assets/ui/mall/resource_map.json"):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/mall/resource_map.json"))
		if parsed is Dictionary: _art = parsed
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	clip_contents = true
	resized.connect(_request_layout)
	_build()
	_request_layout()

func _texture(key: String) -> Texture2D:
	return DungeonStyle.texture(str(_art.get(key, key)))

func _picture(parent: Node, key: String, rect: Rect2) -> TextureRect:
	var result = TextureRect.new()
	result.texture = _texture(key)
	result.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	result.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(result)
	_place(result, rect)
	return result

func _place(control: Control, rect: Rect2) -> void:
	control.position = rect.position
	control.size = rect.size

func _label(parent: Node, value: String, rect: Rect2, font_size: int = 22, color: Color = INK) -> Label:
	var result = DungeonStyle.label(value, font_size)
	result.add_theme_color_override("font_color", color)
	result.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(result)
	_place(result, rect)
	return result

func _skin(key: String, margin: int = 8, tint: Color = Color.WHITE) -> StyleBox:
	var art = _texture(key)
	if art == null: return DungeonStyle.box(Color("f7f3ea") * tint, GOLD, 2)
	var result = StyleBoxTexture.new()
	result.texture = art
	result.modulate_color = tint
	var edge = 65 if key == "30" else 70 if key in ["商店按钮_底", "暗色按钮", "购买按钮"] else 40
	for side in [SIDE_LEFT, SIDE_RIGHT]:
		result.set_texture_margin(side, edge)
		result.set_content_margin(side, margin)
	for side in [SIDE_TOP, SIDE_BOTTOM]:
		result.set_texture_margin(side, 65 if key == "30" else 12)
		result.set_content_margin(side, margin)
	return result

func _button(parent: Node, value: String, rect: Rect2, key: String = "商店按钮_底", font_size: int = 24) -> Button:
	var result = Button.new()
	result.text = value
	result.custom_minimum_size = Vector2.ZERO
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", Color("fffdf3"))
	result.add_theme_color_override("font_disabled_color", Color("ece9e0"))
	result.add_theme_color_override("font_outline_color", Color("46382c"))
	result.add_theme_constant_override("outline_size", 4)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var tint = Color("e4e0d7") if state == "disabled" else Color("fff4ce") if state == "hover" else Color("d8c48e") if state == "pressed" else Color.WHITE
		var skin = _skin(key, 6, tint)
		if skin is StyleBoxTexture and rect.size.x > 0:
			for side in [SIDE_LEFT, SIDE_RIGHT]: skin.set_texture_margin(side, minf(skin.get_texture_margin(side), rect.size.x * 0.3))
		result.add_theme_stylebox_override(state, skin)
	result.add_theme_stylebox_override("focus", DungeonStyle.box(Color.TRANSPARENT, Color("ffe399"), 2))
	parent.add_child(result)
	_place(result, rect)
	return result

func _art_button(parent: Node, key: String, tooltip: String, rect: Rect2) -> Button:
	var result = Button.new()
	result.icon = _texture(key)
	result.expand_icon = true
	result.tooltip_text = tooltip
	for state in ["normal", "hover", "pressed", "focus"]: result.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	parent.add_child(result)
	_place(result, rect)
	return result

func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

func _build() -> void:
	_clear(self)
	category_buttons.clear()
	offer_buttons.clear()
	purchase_buttons.clear()
	visible_offer_ids.clear()
	primary_button = null
	daily_reward = null
	status_label = null
	var background = _picture(self, "bg_maincity", Rect2(Vector2.ZERO, size))
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.modulate = Color("9baca8")
	var shade = ColorRect.new()
	shade.color = Color(0.025, 0.075, 0.075, 0.42)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	canvas = Control.new()
	add_child(canvas)
	canvas.size = _logical_size
	portrait = _picture(canvas, "characterillustration_tianfushu_normal", Rect2(180, 40, 595, 900))
	var back = _art_button(canvas, "退出按钮", "返回", Rect2(28, 18, 108, 90))
	back.pressed.connect(func():
		if is_instance_valid(host): host.back_requested.emit()
		else: command.emit("close_page", 0, 0))
	_picture(canvas, "商城", Rect2(135, 24, 230, 102))
	_label(canvas, "请适度娱乐，理性消费。", Rect2(138, 118, 310, 30), 18, Color("e7e8da"))
	var wallet_x = _logical_size.x - 330
	_picture(canvas, "货币_底", Rect2(wallet_x, 20, 280, 48))
	_picture(canvas, "sprite_materialicon_90002", Rect2(wallet_x - 25, 10, 70, 70))
	_label(canvas, str(systems.material(90002)) if systems != null else "0", Rect2(wallet_x + 48, 25, 210, 42), 28, Color.WHITE)
	var support = _art_button(canvas, "客服", "客服", Rect2(44, 795, 70, 70))
	support.pressed.connect(func(): command.emit("customer_support", 0, 0))
	_label(canvas, "客服", Rect2(39, 865, 90, 30), 20, Color.WHITE)
	var restore = _art_button(canvas, "客服", "恢复内购", Rect2(159, 795, 70, 70))
	restore.pressed.connect(func(): command.emit("restore_purchases", 0, 0))
	_label(canvas, "恢复内购", Rect2(142, 865, 140, 30), 20, Color.WHITE)
	board = Control.new()
	canvas.add_child(board)
	_place(board, Rect2(775, 90, _board_size.x, _board_size.y))
	var panel = Panel.new()
	panel.add_theme_stylebox_override("panel", _skin("30", 16))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(panel)
	_place(panel, Rect2(Vector2.ZERO, _board_size))
	_build_tabs()
	match selected_category:
		"vip": _build_vip()
		"treasure": _build_treasure()
		_: _build_offers()
	_store_selection()
	_apply_canvas_transform()

func _build_tabs() -> void:
	var start_x = 720.0
	var gap = 14.0
	var width = (_logical_size.x - start_x - 28 - gap * 4) / 5.0
	for i in TABS.size():
		var tab = TABS[i]
		var selected = selected_category == tab[0]
		var button = _button(canvas, tab[1], Rect2(start_x + i * (width + gap), 808, width, 68), "商店按钮_底" if selected else "暗色按钮", 28)
		button.pressed.connect(func(): select_category(tab[0]))
		category_buttons[tab[0]] = button
		if tab[0] == "rainbow" and _has_claimable_ad():
			_picture(canvas, "提示点", Rect2(start_x + (i + 1) * width + i * gap - 14, 797, 28, 28))

func _has_claimable_ad() -> bool:
	for row in rows:
		if str(row.get("payment_type", "")) != "Ad": continue
		for entry in row.get("buttons", []):
			if not entry.get("disabled", false): return true
	return false

func _build_vip() -> void:
	var quote = _quote(30001)
	visible_offer_ids.append(30001)
	var width = _board_size.x
	var height = _board_size.y
	_picture(board, "背景装饰环", Rect2(-20, 95, width * 0.61, height - 150)).modulate = Color(1.0, 0.86, 0.5, 0.24)
	_picture(board, "特权", Rect2(75, 165, width * 0.37, height - 215)).flip_h = true
	_picture(board, "迷宫特权标题cn", Rect2(width * 0.41, 36, width * 0.58, 170))
	var right_x = width * 0.56
	var right_width = width * 0.38
	var ad_band = Panel.new()
	ad_band.add_theme_stylebox_override("panel", _skin("16", 0))
	board.add_child(ad_band)
	_place(ad_band, Rect2(right_x - 12, 214, right_width + 24, 70))
	_picture(board, "免广告", Rect2(right_x + 40, 218, 68, 62))
	_label(board, "免广告", Rect2(right_x + 128, 218, right_width - 140, 66), 40)
	var immediate = 0
	for option in quote.get("rewards", []):
		if option.get("ids", []) == [90002]: immediate += int(option.get("amount", 0))
	_reward_band("购买立即获得！", immediate, right_x, 312, right_width)
	var daily = int(catalog.config.get("VIPDailyFreeCoinCount", 200)) if catalog != null else 200
	daily_reward = _reward_band("每日额外领取！", daily, right_x, 440, right_width)
	primary_button = _button(board, _price_text(quote), Rect2(right_x - 4, height - 114, right_width + 8, 76), "商店按钮_底", 42)
	var entry = _entry(30001)
	primary_button.disabled = bool(entry.get("disabled", true))
	primary_button.tooltip_text = str(quote.get("reason", ""))
	primary_button.pressed.connect(func(): _emit_entry(entry))
	purchase_buttons.append(primary_button)
	var reason = _payment_reason(quote)
	status_label = _label(board, "暂未接入支付，无法购买" if reason.contains("尚未接入") else reason, Rect2(32, height - 38, width - 64, 36), 26, Color("92745a"))
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.tooltip_text = reason

func _reward_band(title: String, amount: int, x: float, y: float, width: float) -> Label:
	_picture(board, "白星标", Rect2(x + 8, y, 28, 28)).modulate = Color("a68f73")
	_label(board, title, Rect2(x + 55, y - 2, width - 60, 34), 24, Color("9f8c76"))
	var band = Panel.new()
	band.add_theme_stylebox_override("panel", _skin("16", 0))
	board.add_child(band)
	_place(band, Rect2(x + 20, y + 40, width - 40, 56))
	_picture(board, "sprite_materialicon_90002", Rect2(x + 72, y + 41, 44, 54))
	var amount_label = _label(board, str(amount), Rect2(x + 130, y + 40, width - 160, 56), 37, Color.WHITE)
	amount_label.add_theme_color_override("font_outline_color", INK)
	amount_label.add_theme_constant_override("outline_size", 3)
	return amount_label

func _offer_category(row: Dictionary) -> String:
	var id = int(row.get("config_id", 0))
	if id == 30001: return "vip"
	if id in [30002, 30003, 30004]: return "blessing"
	if str(row.get("payment_type", "")) in ["Ad", "FreeCion", "PurchaseCion", "Gold"] or id in [2001, 2002, 2003, 2004]: return "rainbow"
	return "bundles"

func _build_offers() -> void:
	var content = HBoxContainer.new()
	content.add_theme_constant_override("separation", 18)
	board.add_child(content)
	_place(content, Rect2(28, 30, _board_size.x - 56, _board_size.y - 60))
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	var grid = GridContainer.new()
	grid.columns = 3 if selected_category == "rainbow" else 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 14)
	scroll.add_child(grid)
	var candidates: Array = []
	for row in rows:
		if row.get("presentation_role", "") == "navigation" or _offer_category(row) != selected_category: continue
		candidates.append(row)
		visible_offer_ids.append(int(row.get("config_id", 0)))
	if not selected_offer in visible_offer_ids and not candidates.is_empty(): selected_offer = int(candidates[0].get("config_id", 0))
	for row in candidates:
		var id = int(row.get("config_id", 0))
		var quote = _quote(id)
		var button = _button(grid, "", Rect2(0, 0, 210, 258), "30", 20)
		button.custom_minimum_size = Vector2(205, 258)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.tooltip_text = DungeonCatalog.clean(str(row.get("title", "")))
		button.add_theme_stylebox_override("normal", _card_style(id == selected_offer))
		button.add_theme_stylebox_override("hover", _card_style(true))
		var stack = VBoxContainer.new()
		stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		stack.offset_left = 8
		stack.offset_top = 10
		stack.offset_right = -8
		stack.offset_bottom = -10
		stack.add_theme_constant_override("separation", 4)
		stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(stack)
		var icon = DungeonStyle.picture(_offer_icon(id), Vector2(100, 118))
		icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stack.add_child(icon)
		var title = _stack_label(stack, _offer_title(id, row), 18)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.custom_minimum_size.y = 48
		var price = _stack_label(stack, _price_text(quote), 19, Color("917340"))
		price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var limit = _stack_label(stack, _limit_text(quote), 13, Color("8d8576"))
		limit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.pressed.connect(func(): select_offer(id))
		offer_buttons[id] = button
	var detail_panel = PanelContainer.new()
	detail_panel.custom_minimum_size.x = 325
	detail_panel.add_theme_stylebox_override("panel", DungeonStyle.box(Color("eeeae1"), Color("d9ccb4"), 1))
	content.add_child(detail_panel)
	var detail_scroll = ScrollContainer.new()
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_panel.add_child(detail_scroll)
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 10)
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.add_child(_detail)
	_show_offer_detail()

func _card_style(selected: bool) -> StyleBoxFlat:
	var result = DungeonStyle.box(Color("fffaf0") if selected else Color("f5f2eb"), Color("d9b456") if selected else Color("d3c9b9"), 3 if selected else 1)
	result.set_corner_radius_all(8)
	return result

func _stack_label(parent: Node, value: String, font_size: int = 20, color: Color = INK) -> Label:
	var result = _label(parent, value, Rect2(), font_size, color)
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return result

func _show_offer_detail() -> void:
	if not is_instance_valid(_detail): return
	_clear(_detail)
	purchase_buttons.clear()
	var row = _row(selected_offer)
	if row.is_empty():
		_stack_label(_detail, "暂无可用商品", 23)
		return
	var quote = _quote(selected_offer)
	var icon = DungeonStyle.picture(_offer_icon(selected_offer), Vector2(140, 140))
	_detail.add_child(icon)
	_stack_label(_detail, _offer_title(selected_offer, row), 25)
	_stack_label(_detail, _limit_text(quote), 16, Color("8d7960"))
	_detail.add_child(HSeparator.new())
	_stack_label(_detail, "礼包包含", 18, Color("9b7738"))
	for reward in quote.get("rewards", []):
		var names: Array[String] = []
		for id in reward.get("ids", []): names.append(DungeonCatalog.clean(systems.material_name(int(id))) if systems != null else str(id))
		var reward_line = HBoxContainer.new()
		_detail.add_child(reward_line)
		if reward.get("ids", []).size() == 1: reward_line.add_child(DungeonStyle.picture("material:" + str(reward.ids[0]), Vector2(32, 32)))
		_stack_label(reward_line, ("随机：" if names.size() > 1 else "") + " / ".join(names) + " ×" + str(reward.get("amount", 0)), 17)
	_stack_label(_detail, _price_text(quote), 24, Color("9a752f"))
	var reason = _payment_reason(quote)
	if str(quote.get("payment", "")) == "Ad":
		reason = "已达领取上限" if int(quote.get("remaining", -1)) == 0 else "完成广告后领取奖励"
	if not reason.is_empty(): _stack_label(_detail, reason, 16, Color("9d6b52"))
	for entry in row.get("buttons", []):
		var button = _button(_detail, str(entry.get("text", "兑换")), Rect2(0, 0, 200, 52), "购买按钮", 22)
		button.custom_minimum_size.y = 52
		button.disabled = bool(entry.get("disabled", false))
		button.tooltip_text = str(quote.get("reason", ""))
		button.pressed.connect(func(): _emit_entry(entry))
		purchase_buttons.append(button)
	if selected_category == "blessing":
		_detail.add_child(HSeparator.new())
		_stack_label(_detail, "冒险模式", 18, Color("9b7738"))
		var modes = HBoxContainer.new()
		_detail.add_child(modes)
		var current = systems.stat("blessing") if systems != null else 0
		for i in 3:
			var mode = i
			var button = _button(modes, ["关闭", "祝福", "高阶祝福"][i], Rect2(0, 0, 88, 44), "商店按钮_底" if current == i else "暗色按钮", 15)
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.custom_minimum_size = Vector2(82, 44)
			button.disabled = current == i or (systems != null and systems.profile.data.run.active)
			button.pressed.connect(func(): command.emit("op:set_blessing_mode", mode, 0))
	_store_selection()

func _build_treasure() -> void:
	var width = _board_size.x
	_label(board, "公会宝箱", Rect2(35, 25, width - 70, 65), 34, Color("9d7834"))
	var quote: Dictionary = systems.camp_treasure_quote(selected_box_count) if systems != null and systems.has_method("camp_treasure_quote") else {"can_buy": false, "reason": "宝箱暂不可用", "price": {}, "id": 0}
	_picture(board, "背景装饰环", Rect2(30, 110, 420, 420)).modulate = Color(1.0, 0.86, 0.5, 0.24)
	_picture(board, "金宝箱", Rect2(80, 140, 320, 320))
	var box_id = int(quote.get("id", 0))
	var source: Dictionary = catalog.find("ShopTreasureBoxData", box_id) if catalog != null else {}
	_label(board, "公会宝箱", Rect2(80, 470, 320, 50), 28).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var choices = HBoxContainer.new()
	choices.add_theme_constant_override("separation", 10)
	board.add_child(choices)
	_place(choices, Rect2(52, 530, 380, 60))
	for amount in [1, 5, 50, 300]:
		var button = _button(choices, "×" + str(amount), Rect2(0, 0, 84, 52), "商店按钮_底" if amount == selected_box_count else "暗色按钮", 23)
		button.custom_minimum_size = Vector2(84, 52)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func():
			selected_box_count = amount
			_build())
	var price = int(quote.get("price", {}).get("101", 0))
	_picture(board, "sprite_materialicon_101", Rect2(100, 605, 45, 45))
	_label(board, str(price), Rect2(155, 605, 200, 48), 29, Color("9d7834"))
	var right_x = 480.0
	var right_width = width - right_x - 35
	_label(board, "奖池内容", Rect2(right_x, 98, right_width, 50), 25)
	var rewards_scroll = ScrollContainer.new()
	rewards_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	board.add_child(rewards_scroll)
	_place(rewards_scroll, Rect2(right_x, 155, right_width, 325))
	var rewards = GridContainer.new()
	rewards.columns = 3
	rewards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rewards.add_theme_constant_override("h_separation", 10)
	rewards.add_theme_constant_override("v_separation", 10)
	rewards_scroll.add_child(rewards)
	var entries: Array = []
	var weight = 0.0
	for token in str(source.get("sub_data_id_list", "")).split("|", false):
		var values = token.strip_edges().split(":")
		if values.size() != 3: continue
		entries.append({"id": int(values[0]), "amount": int(values[1]), "weight": int(values[2])})
		weight += int(values[2])
	for entry in entries:
		var column = VBoxContainer.new()
		column.custom_minimum_size.x = 145
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rewards.add_child(column)
		column.add_child(DungeonStyle.picture("material:" + str(entry.id), Vector2(65, 65)))
		_stack_label(column, DungeonCatalog.clean(systems.material_name(entry.id)) + " ×" + str(entry.amount), 16).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_stack_label(column, "%.1f%%" % (entry.weight / maxf(1, weight) * 100), 14, Color("948169")).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label = _label(board, str(quote.get("reason", "")), Rect2(right_x, 492, right_width, 56), 18, Color("a36f52"))
	primary_button = _button(board, "开启 %d 个" % selected_box_count, Rect2(right_x, 565, right_width, 65), "购买按钮", 30)
	primary_button.disabled = not bool(quote.get("can_buy", false))
	primary_button.pressed.connect(func(): command.emit("op:open_camp_treasure_boxes", selected_box_count, 0))
	purchase_buttons.append(primary_button)
	var talk = _button(board, "与宝箱管理员交谈", Rect2(right_x, 637, right_width, 37), "暗色按钮", 17)
	talk.pressed.connect(func(): command.emit("page:npc", 1400, 0))

func _row(id: int) -> Dictionary:
	for row in rows:
		if int(row.get("config_id", 0)) == id: return row
	return {}

func _source(id: int) -> Dictionary:
	return catalog.find("MallTradeData", id) if catalog != null else {}

func _quote(id: int) -> Dictionary:
	return systems.offer_quote(id) if systems != null else _row(id).get("offer_quote", {})

func _entry(id: int) -> Dictionary:
	var buttons: Array = _row(id).get("buttons", [])
	return buttons[0] if not buttons.is_empty() else {"action": "op:buy_mall", "id": id, "disabled": true}

func _offer_icon(id: int) -> String:
	var icon = str(_source(id).get("IconName", ""))
	if not icon.is_empty(): return icon
	return str(_art.get("Icon_BlessingModeBreak" if id == 30004 else "Icon_BlessingModePlus" if id == 30003 else "Icon_BlessingMode", ""))

func _offer_title(id: int, row: Dictionary) -> String:
	if id == 30001: return "永久迷宫特权"
	if id == 30002: return "祝福模式"
	if id == 30003: return "祝福模式 Plus"
	if id == 30004: return "祝福模式·觉醒"
	var title = DungeonCatalog.clean(str(row.get("title", DungeonCatalog.row_name(_source(id)))))
	if title.begins_with("PopShopTradeData_"):
		var rewards: Array = _quote(id).get("rewards", [])
		if systems != null and rewards.size() == 1 and rewards[0].get("ids", []).size() == 1:
			return DungeonCatalog.clean(systems.material_name(int(rewards[0].ids[0]))) + "礼包"
		return "冒险物资礼包"
	return title

func _price_text(quote: Dictionary) -> String:
	match str(quote.get("payment", "")):
		"Money", "Other":
			var amount = float(quote.get("payment_price", quote.get("price", 0)))
			return "￥" + (str(int(amount)) if is_equal_approx(amount, int(amount)) else "%.2f" % amount)
		"Ad": return "广告领取"
		_: return "%s ×%d" % [DungeonCatalog.clean(systems.material_name(int(quote.get("currency", 0)))) if systems != null else "", int(quote.get("price", 0))]

func _limit_text(quote: Dictionary) -> String:
	if int(quote.get("limit", -1)) < 0: return "不限购买次数"
	var boundary = {"OneDay": "今日", "OneBattle": "本次冒险", "Never": "永久"}.get(str(quote.get("refresh_mode", "")), "")
	return "%s剩余 %d / %d" % [boundary, int(quote.get("remaining", 0)), int(quote.get("limit", 0))]

func _payment_reason(quote: Dictionary) -> String:
	return str(quote.get("reason", ""))

func _emit_entry(entry: Dictionary) -> void:
	if entry.is_empty() or bool(entry.get("disabled", false)): return
	command.emit(str(entry.get("action", "")), entry.get("id", 0), entry.get("extra", 0))

func select_category(category: String) -> void:
	if not TABS.any(func(tab): return tab[0] == category): return
	selected_category = category
	_build()

func select_offer(id: int) -> void:
	if not id in visible_offer_ids: return
	selected_offer = id
	for key in offer_buttons: offer_buttons[key].add_theme_stylebox_override("normal", _card_style(int(key) == id))
	_show_offer_detail()

func _store_selection() -> void:
	_context["mall_category"] = selected_category
	_context["selected_offer"] = selected_offer
	_context["mall_box_count"] = selected_box_count
	if is_instance_valid(host):
		host.page_context["mall_category"] = selected_category
		host.page_context["selected_offer"] = selected_offer
		host.page_context["mall_box_count"] = selected_box_count

func _request_layout() -> void:
	if _layout_pending: return
	_layout_pending = true
	_layout.call_deferred()

func _layout() -> void:
	_layout_pending = false
	if size.x <= 0 or size.y <= 0: return
	var canvas_scale = minf(size.x / 1920.0, size.y / 900.0)
	var logical = Vector2(size.x / canvas_scale, 900)
	if absf(logical.x - _logical_size.x) > 1:
		_logical_size = logical
		_board_size.x = logical.x - 810
		_build()
	_canvas_scale = canvas_scale
	_apply_canvas_transform()

func _apply_canvas_transform() -> void:
	if not is_instance_valid(canvas): return
	canvas.scale = Vector2.ONE * _canvas_scale
	canvas.position = Vector2((size.x - _logical_size.x * _canvas_scale) * 0.5, (size.y - 900 * _canvas_scale) * 0.5)

func refresh() -> void:
	_build()
