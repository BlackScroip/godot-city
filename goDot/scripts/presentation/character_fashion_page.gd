extends Control

const NAVIGATION = preload("res://scripts/presentation/role_navigation.gd")
var host
var fashions: Array = []
var selected_id := 0
var swatches: Array[Button] = []
var _list: ScrollContainer
var _art: Control
var _details: Control
var _model_button: Button
var _help: Control
var _use_model := false

func configure(page) -> void:
	host = page
	name = "CharacterFashions"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background = host._picture("charamenumask_%d" % host._character_id(), Vector2.ZERO)
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var back = NAVIGATION.create_back_button("返回角色详情")
	back.pressed.connect(close)
	add_child(back)
	var title = host._picture("时装", Vector2.ZERO)
	add_child(title)
	host._rect(title, 150, 30, 145, 75)
	DungeonStyle.localize_artwork_title(title, "时装", 44, host.PAPER)
	var help = host._icon_button("须知", "时装说明", Vector2(52, 52))
	if help.icon == null: help.text = "?"
	help.pressed.connect(_show_help)
	add_child(help)
	host._rect(help, 320, 38, 52, 52)
	_list = ScrollContainer.new()
	_list.name = "FashionSwatches"
	_list.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	add_child(_list)
	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	_list.add_child(column)
	for fashion in host._fashions:
		if int(fashion.get("chara_id", 0)) != host._character_id() or bool(fashion.get("is_admin_only", false)): continue
		fashions.append(fashion)
		var button = host._icon_button(str(fashion.get("slot_icon_path", "")), str(fashion.get("name", "")), Vector2(144, 140))
		button.name = "Fashion_%d" % int(fashion.id)
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.add_theme_constant_override("icon_max_width", 136)
		button.pressed.connect(func(): select_fashion(int(fashion.id)))
		column.add_child(button)
		swatches.append(button)
	_art = Control.new()
	_art.name = "FashionArtwork"
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_art)
	_details = Control.new()
	_details.name = "FashionDetails"
	add_child(_details)
	_model_button = host._vertical_button("角色详情(未选择3D)", "3D", "查看角色模型")
	_model_button.pressed.connect(func():
		_use_model = not _use_model
		_refresh_art())
	add_child(_model_button)
	resized.connect(_layout)
	selected_id = int(host._selected_fashion().get("id", host._selected_equipped_fashion()))
	select_fashion(selected_id)
	_layout()

func select_fashion(id: int) -> void:
	if not fashions.any(func(row): return int(row.id) == id): return
	selected_id = id
	_use_model = false
	host._preview_fashion = id
	host._store_context("selected_fashion", id)
	for index in swatches.size():
		var button = swatches[index]
		for child in button.get_children():
			button.remove_child(child)
			child.queue_free()
		var fashion: Dictionary = fashions[index]
		var quote = _status(fashion)
		var border = StyleBoxFlat.new()
		border.bg_color = Color(0.03, 0.02, 0.03, 0.3)
		border.border_color = host.GOLD if int(fashion.id) == id else Color("b8b6af")
		border.set_border_width_all(4 if int(fashion.id) == id else 3)
		border.set_corner_radius_all(14)
		if int(fashion.id) == id:
			border.shadow_color = Color(1, 0.85, 0.24, 0.65)
			border.shadow_size = 6
		for state in ["normal", "hover", "pressed", "focus"]: button.add_theme_stylebox_override(state, border)
		if not bool(quote.get("owned", false)):
			var dim = ColorRect.new()
			dim.color = Color(0, 0, 0, 0.5)
			dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
			button.add_child(dim)
			dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			var lock = host._picture("锁", Vector2.ZERO)
			button.add_child(lock)
			host._rect(lock, 44, 36, 56, 68)
		elif bool(quote.get("equipped", false)):
			var label = host._label("穿戴中", 25)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			button.add_child(label)
			host._rect(label, 0, 101, 144, 34)
	_refresh_art()
	_refresh_details()

func _fashion() -> Dictionary:
	for row in fashions:
		if int(row.id) == selected_id: return row
	return {}

func _status(fashion: Dictionary) -> Dictionary:
	var systems = host.context.get("systems")
	if systems: return systems.character_fashion_status(int(fashion.id), host._character_id())
	return {"owned": host._fashion_owned(fashion), "equipped": host._selected_equipped_fashion() == int(fashion.id)}

func _refresh_art() -> void:
	host._clear(_art)
	var fashion = _fashion()
	var has_model = selected_id == host._character_id() * 1000 + 1
	_model_button.disabled = not has_model
	_model_button.tooltip_text = "查看角色模型" if has_model else "此时装尚未恢复3D模型"
	_model_button.text = "2D" if _use_model else "3D"
	_model_button.icon = host._texture("角色详情(已选择3D)" if _use_model else "角色详情(未选择3D)")
	if _use_model and has_model:
		var preview = DungeonModelPreview.new()
		_art.add_child(preview)
		preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		preview.show_model(str(host.rows[host.selected].get("model", "")))
	else:
		var art = host._picture(str(fashion.get("illustration_path", "")), Vector2.ZERO)
		_art.add_child(art)
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _refresh_details() -> void:
	host._clear(_details)
	var fashion = _fashion()
	var quote = _status(fashion)
	for y in [14, 86]:
		var ornament = host._picture("分割线3_白", Vector2.ZERO)
		ornament.stretch_mode = TextureRect.STRETCH_SCALE
		ornament.flip_v = y == 86
		_details.add_child(ornament)
		host._rect(ornament, 4, y, 500, 18)
	var title_star = host._picture("白星标", Vector2.ZERO)
	_details.add_child(title_star)
	host._rect(title_star, 12, 40, 32, 32)
	var title = host._label(str(fashion.get("name", "")), 38)
	_details.add_child(title)
	host._rect(title, 45, 17, 430, 56)
	var description = host._label(DungeonCatalog.clean(str(fashion.get("description", ""))), 23)
	_details.add_child(description)
	host._rect(description, 44, 90, 455, 90)
	var divider = host._picture("ArtLineDown_white", Vector2.ZERO)
	divider.stretch_mode = TextureRect.STRETCH_SCALE
	_details.add_child(divider)
	host._rect(divider, 36, 180, 470, 4)
	var effect_title = host._label("时装效果", 32)
	effect_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_details.add_child(effect_title)
	host._rect(effect_title, 60, 196, 420, 48)
	for x in [172, 362]:
		var star = host._picture("白星标", Vector2.ZERO)
		_details.add_child(star)
		host._rect(star, x, 202, 27, 35)
	var effects = VBoxContainer.new()
	effects.name = "FashionEffects"
	effects.add_theme_constant_override("separation", 7)
	_details.add_child(effects)
	host._rect(effects, 44, 253, 455, 100)
	for pair in [["unlock_hp_add", "生命"], ["unlock_atk_add", "攻击"], ["unlock_def_add", "防御"], ["unlock_criti_rate_add", "暴击率"], ["unlock_criti_mult_add", "暴击伤害"]]:
		var amount = int(fashion.get(pair[0], 0))
		if amount == 0: continue
		var value = "%+.1f%%" % (amount / 10.0) if "criti" in pair[0] else "%+d" % amount
		effects.add_child(host._label("%s  %s" % [pair[1], value], 24))
	var effect_text = str(fashion.get("effect_description", ""))
	if not effect_text.begins_with("CharaFashion_") and not effect_text.is_empty(): effects.add_child(host._label(DungeonCatalog.clean(effect_text), 23))
	var card_line = host._picture("ArtLineDown_1_white", Vector2.ZERO)
	card_line.stretch_mode = TextureRect.STRETCH_SCALE
	_details.add_child(card_line)
	host._rect(card_line, 36, 460, 470, 6)
	var card_holder = Panel.new()
	card_holder.name = "SuitCard"
	var frame = StyleBoxFlat.new()
	frame.bg_color = Color("ffe798")
	frame.border_color = host.GOLD
	frame.set_border_width_all(4)
	frame.set_corner_radius_all(8)
	card_holder.add_theme_stylebox_override("panel", frame)
	_details.add_child(card_holder)
	host._rect(card_holder, 102, 490, 172, 350)
	var elements = {1: "Fire", 2: "Dark", 3: "Thunder", 4: "Water", 5: "Wind", 6: "Light", 7: "Ice", 8: "Soil"}
	var background = host._picture("CharaFashion_" + str(elements.get(host._character_id(), "Fire")), Vector2.ZERO)
	card_holder.add_child(background)
	host._rect(background, 4, 4, 164, 342)
	background.stretch_mode = TextureRect.STRETCH_SCALE
	var card = host._picture("CharaFashionCard_%d" % int(fashion.get("suit_id", 0)), Vector2.ZERO)
	card.name = "FashionSuitCard"
	card_holder.add_child(card)
	host._rect(card, 4, 4, 164, 342)
	card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	card_holder.clip_contents = true
	var suits: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/role_character/FashionSuitConfigData.json"))
	for suit in suits:
		if int(suit.id) != int(fashion.get("suit_id", 0)): continue
		var suit_name = host._label(str(suit.name), 23)
		suit_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		suit_name.add_theme_constant_override("outline_size", 4)
		suit_name.add_theme_color_override("font_outline_color", Color("42352c"))
		card_holder.add_child(suit_name)
		host._rect(suit_name, 4, 293, 164, 45)
	for index in 5:
		var star = host._picture("icon_rarestar", Vector2.ZERO)
		_details.add_child(star)
		host._rect(star, 108 + index * 30, 825, 34, 38)
	if not bool(quote.get("equipped", false)):
		var actions = VBoxContainer.new()
		actions.name = "FashionActions"
		actions.add_theme_constant_override("separation", 12)
		_details.add_child(actions)
		host._rect(actions, 285, 520, 218, 250)
		var owned = bool(quote.get("owned", false))
		if not owned:
			for key in quote.get("price", {}):
				var cost = HBoxContainer.new()
				actions.add_child(cost)
				cost.add_child(host._picture("sprite_materialicon_%s" % key, Vector2(42, 42)))
				var systems = host.context.get("systems")
				cost.add_child(host._label("%d/%d" % [systems.material(int(key)) if systems else 0, int(quote.price[key])], 24))
		var action = host._paper_button("装备" if owned else "解锁", "装备时装" if owned else "解锁时装")
		action.name = "FashionAction"
		action.disabled = not bool(quote.get("can_equip" if owned else "can_unlock", false))
		action.pressed.connect(func():
			action.disabled = true
			host.command.emit("op:equip_character_fashion" if owned else "op:unlock_character_fashion", selected_id, host._character_id()))
		actions.add_child(action)
		if action.disabled:
			var reason = str(quote.get("equip_reason" if owned else "reason", ""))
			action.tooltip_text = reason
			actions.add_child(host._label(reason, 21))

func _show_help() -> void:
	if is_instance_valid(_help): _help.queue_free()
	_help = host._overlay("FashionHelp", "时装", Vector2(650, 300))
	_help.get_node("Center/Panel/Stack").add_child(host._label("解锁时装后获得属性加成，切换外观不会移除已解锁的属性加成。", 27))

func _layout() -> void:
	if not is_instance_valid(_details): return
	NAVIGATION.place_back_button(get_node("RoleBackButton"))
	host._rect(_list, 44, 133, 165, size.y - 173)
	host._rect(_art, 340, 70, maxf(600, size.x - 1070), size.y - 78)
	host._rect(_details, size.x - 565, 15, 525, size.y - 25)
	host._rect(_model_button, size.x - 640, size.y - 130, 110, 108)

func close() -> void:
	if is_instance_valid(_help): _help.queue_free()
	_use_model = false
	host._preview_fashion = 0
	host._store_context("selected_fashion", 0)
	host._store_context("fashion_open", false)
	host._select_showcase(host.selected)
	hide()

func dismiss_help() -> bool:
	if not is_instance_valid(_help) or not _help.visible: return false
	_help.hide()
	return true
