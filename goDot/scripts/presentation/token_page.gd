extends "res://scripts/presentation/camp_services_page.gd"

var token_state: Dictionary = {}
var socket_buttons: Array[Button] = []
var preset_buttons: Array[Button] = []
var equipped_buttons: Array[Button] = []
var equipment_strip: HBoxContainer

func _build() -> void:
	super._build()
	var background = get_child(0)
	if background is ColorRect: background.color = Color(0.07, 0.10, 0.10, 0.88)
	for child in heading.get_children():
		if child is Label:
			child.add_theme_color_override("font_color", Color("fff1c9"))
			if child.size_flags_horizontal & Control.SIZE_EXPAND_FILL: child.text = "信物"
		elif child is HBoxContainer:
			for amount in child.get_children():
				if amount is Label: amount.add_theme_color_override("font_color", Color.WHITE)
	collection_scroll.size_flags_stretch_ratio = 1.7
	detail_scroll.add_theme_stylebox_override("panel", _skin("信物详情底"))
	equipped_buttons.clear()
	if page_id == "tokens":
		var left = VBoxContainer.new()
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left.size_flags_stretch_ratio = 1.7
		left.add_theme_constant_override("separation", 12)
		body.remove_child(collection_scroll)
		body.add_child(left)
		body.move_child(left, 0)
		left.add_child(collection_scroll)
		collection_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var caption = _label("已装备 %d / %d" % [token_state.get("equipped", []).size(), token_state.get("slots", 1)], 16, Color("fff1c9"))
		left.add_child(caption)
		equipment_strip = HBoxContainer.new()
		equipment_strip.add_theme_constant_override("separation", 8)
		left.add_child(equipment_strip)
		var equipped: Array = token_state.get("equipped", [])
		var systems = context.get("systems")
		for index in int(token_state.get("slots", 1)):
			var token_id = int(equipped[index]) if index < equipped.size() else 0
			var button = _button("", func(): _select_equipped(token_id))
			button.custom_minimum_size = Vector2(48, 48) if compact else Vector2(84, 84)
			button.expand_icon = true
			button.add_theme_constant_override("icon_max_width", 36 if compact else 64)
			var icon = str(systems.token_status(token_id).icon) if token_id > 0 and systems != null else "material:" + str(token_id) if token_id > 0 else str(_source_sprites.get("icon_addnum", "icon_addnum"))
			button.icon = DungeonStyle.texture(icon)
			button.tooltip_text = "空闲信物槽" if token_id == 0 else systems.material_name(token_id) if systems != null else "信物 " + str(token_id)
			button.add_theme_stylebox_override("normal", _skin("slotfg_rare_square_1_v2", Color("485462")))
			button.set_meta("token_id", token_id)
			equipment_strip.add_child(button)
			equipped_buttons.append(button)
	_resize_tiles.call_deferred()

func _select_equipped(token_id: int) -> void:
	if token_id <= 0: return
	for index in rows.size():
		if int(rows[index].get("token_id", 0)) == token_id:
			select_row(index)
			collection_scroll.ensure_control_visible(choice_buttons[index])
			return

func configure(host: DungeonMenuPage, data: Array, page_context: Dictionary = {}) -> void:
	token_state = page_context.get("token_state", {})
	super.configure(host, data, page_context)

func _build_toolbar() -> void:
	var token_mode = str(token_state.get("mode", page_id)) != "amplifiers"
	for mode in [["信物", "tokens"], ["镶嵌", "amplifiers"]]:
		var tab = _button(mode[0], func(): command.emit("page:" + str(mode[1]), token_state.get("selected_token_id", 0), 0))
		tab.toggle_mode = true
		tab.button_pressed = token_mode if mode[1] == "tokens" else not token_mode
		if tab.button_pressed: tab.add_theme_stylebox_override("normal", DungeonStyle.box(Color("fff4c5"), Color("b49951"), 2))
		toolbar.add_child(tab)
	var character = _label(str(token_state.get("character_name", "")), 17, Color("fff1c9"))
	character.autowrap_mode = TextServer.AUTOWRAP_OFF
	character.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(character)
	var preset_toggle = _button("预设", func():
		context.token_presets_open = not bool(context.get("token_presets_open", false))
		owner_page.page_context.token_presets_open = context.token_presets_open
		_build())
	preset_toggle.toggle_mode = true
	preset_toggle.button_pressed = bool(context.get("token_presets_open", false))
	toolbar.add_child(preset_toggle)
	for entry in token_state.get("toolbar_buttons", []):
		if token_mode and str(entry.get("action", "")) in ["page:token_compose_preview", "op:unequip_all_amplifiers"]: continue
		toolbar.add_child(_command_button(entry))
	var loadouts = HFlowContainer.new()
	loadouts.add_theme_constant_override("h_separation", 8)
	loadouts.visible = bool(context.get("token_presets_open", false))
	root_box.add_child(loadouts)
	var preset_title = _label("预设", 16, Color("fff1c9"))
	preset_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	loadouts.add_child(preset_title)
	preset_buttons.clear()
	var presets: Array = token_state.get("presets", [])
	if not presets.is_empty():
		var preset_index = clampi(int(context.get("token_preset_index", 0)), 0, presets.size() - 1)
		var selector = OptionButton.new()
		selector.custom_minimum_size = Vector2(110, 42)
		for index in presets.size(): selector.add_item(str(presets[index].get("name", "预设%d" % (index + 1))))
		selector.selected = preset_index
		selector.item_selected.connect(func(index):
			context.token_preset_index = index
			owner_page.page_context.token_preset_index = index
			_build())
		loadouts.add_child(selector)
		var preset: Dictionary = presets[preset_index]
		for entry in preset.get("buttons", []):
			var button = _command_button(entry)
			button.tooltip_text = str(preset.get("name", "")) + " " + button.tooltip_text
			loadouts.add_child(button)
			preset_buttons.append(button)
	if preset_buttons.is_empty():
		var empty = _label("尚未保存", 16, MUTED)
		empty.autowrap_mode = TextServer.AUTOWRAP_OFF
		loadouts.add_child(empty)
	var slots = int(token_state.get("slots", 1))
	var capacity = _label("信物 %d / %d" % [token_state.get("equipped", []).size(), slots], 16, Color("fff1c9"))
	capacity.autowrap_mode = TextServer.AUTOWRAP_OFF
	loadouts.add_child(capacity)

func _columns() -> int:
	return 4 if compact else 8

func _populate() -> void:
	super._populate()
	for button in choice_buttons:
		var row: Dictionary = rows[int(button.get_meta("row_index"))]
		button.text = ""
		button.tooltip_text = DungeonCatalog.clean(str(row.get("title", "")) + "\n" + str(row.get("description", "")))
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		button.add_theme_color_override("icon_normal_color", Color.BLACK if bool(row.get("locked", false)) else Color.WHITE)
		button.add_theme_color_override("icon_hover_color", Color.BLACK if bool(row.get("locked", false)) else Color.WHITE)
		button.add_theme_color_override("icon_pressed_color", Color.BLACK if bool(row.get("locked", false)) else Color.WHITE)
		button.add_theme_stylebox_override("normal", _skin("40_1" if int(button.get_meta("row_index")) == selected else "slotfg_rare_square_1_v2", Color("485462")))
		var badge = _label("Lv.%d" % int(row.get("level", 0)) if page_id == "tokens" else str(row.get("title", "")).get_slice("×", 1), 13, Color.WHITE)
		badge.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		badge.offset_top = -22
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(badge)
		if bool(row.get("equipped", false)):
			var mark = DungeonStyle.picture(str(_source_sprites.get("勾选", "勾选")), Vector2.ZERO)
			button.add_child(mark)
			mark.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
			mark.position = Vector2(button.size.x - 24, 0)
			mark.size = Vector2(24, 24)
	_resize_tiles.call_deferred()

func _resize_tiles() -> void:
	if not is_instance_valid(collection_scroll): return
	var edge = maxf(44, (collection_scroll.size.x - 8 * (_columns() - 1) - 8) / _columns())
	for button in choice_buttons:
		button.custom_minimum_size = Vector2(0, edge)
		button.add_theme_constant_override("icon_max_width", int(edge * 0.72))

func _adapt() -> void:
	super._adapt()
	_resize_tiles.call_deferred()

func _show_detail() -> void:
	if page_id == "tokens": _show_token_detail()
	else: super._show_detail()
	socket_buttons.clear()
	if rows.is_empty() or selected < 0: return
	var row: Dictionary = rows[selected]
	var slots: Array = row.get("slot_rows", token_state.get("sockets", []))
	var title = _label("信物镶嵌", 20)
	details.add_child(title)
	var socket_bar = HBoxContainer.new()
	socket_bar.add_theme_constant_override("separation", 8)
	details.add_child(socket_bar)
	for index in 3:
		var slot: Dictionary = slots[index] if index < slots.size() and slots[index] is Dictionary else {}
		var column = VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		socket_bar.add_child(column)
		var caption = str(slot.get("title", "镶嵌位 %d" % (index + 1)))
		if index == int(token_state.get("selected_slot_index", 0)): caption += " · 当前"
		var icon = DungeonStyle.picture(str(slot.get("icon", "锁")), Vector2(38, 38) if compact else Vector2(60, 60))
		column.add_child(icon)
		column.add_child(_label(caption, 14 if compact else 17))
		if not str(slot.get("description", "")).is_empty():
			var description = SourceRichText.new()
			description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			description.add_theme_font_size_override("normal_font_size", 14)
			description.add_theme_color_override("default_color", MUTED)
			description.set_source(str(slot.description))
			column.add_child(description)
		for entry in slot.get("buttons", []):
			var button = _command_button(entry)
			button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			column.add_child(button)
			socket_buttons.append(button)
	if not str(token_state.get("summary", "")).is_empty():
		details.add_child(_label("属性总结", 20))
		details.add_child(_label(str(token_state.summary), 16 if compact else 18))
	for result in token_state.get("compose_results", []):
		if result is Dictionary:
			details.add_child(_label(str(result.get("title", "合成结果")), 20))
			details.add_child(_label(str(result.get("description", "")), 16))
			_build_row_actions(result)

func _show_token_detail() -> void:
	for child in details.get_children(): details.remove_child(child); child.queue_free()
	action_buttons.clear()
	if rows.is_empty() or selected < 0: return
	var row: Dictionary = rows[selected]
	var systems = context.get("systems")
	if systems == null:
		super._show_detail()
		return
	var token_id = int(row.token_id)
	var state: Dictionary = systems.token_status(token_id, int(token_state.get("character_id", 0)))
	var title = _label(str(state.name), 22 if compact else 28, Color("73582d"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	details.add_child(title)
	var content = HBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	details.add_child(content)
	var art = DungeonStyle.picture(str(state.icon), Vector2(64, 100) if compact else Vector2(112, 190))
	art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	content.add_child(art)
	var effects = VBoxContainer.new()
	effects.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	effects.add_theme_constant_override("separation", 10)
	content.add_child(effects)
	for level in range(1, mini(6, maxi(3, int(state.level) + 1)) + 1):
		var source: Dictionary = systems.relationship_tokens.level_row(token_id, level)
		if source.is_empty(): continue
		var line = HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		effects.add_child(line)
		line.add_child(DungeonStyle.picture(str(_source_sprites.get("星星大" if level <= int(state.level) else "星星底", "星星底")), Vector2(20, 20)))
		var text = SourceRichText.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_theme_font_size_override("normal_font_size", 14 if compact else 18)
		text.add_theme_color_override("default_color", INK if level <= int(state.level) else MUTED)
		text.set_source(str(source.get("effect_desc", "")) if level <= int(state.level) else str(source.get("unlcok_desc", "")) if int(source.get("auto_unlock_data_id", 0)) > 0 else str(source.get("effect_desc", "")))
		line.add_child(text)
	if not state.price.is_empty(): details.add_child(_label(systems.price_description(state.price), 15 if compact else 18))
	if not str(state.reason).is_empty(): details.add_child(_label(str(state.reason), 14 if compact else 17, MUTED))
	if not state.can_equip and str(state.equip_reason) != str(state.reason): details.add_child(_label(str(state.equip_reason), 14 if compact else 17, MUTED))
	_build_row_actions(row)

func select_row(index: int) -> void:
	if rows.is_empty(): return
	var row: Dictionary = rows[clampi(index, 0, rows.size() - 1)]
	if row.has("token_id"):
		owner_page.page_context.token_selected = int(row.token_id)
		context.token_selected = int(row.token_id)
		token_state.selected_token_id = int(row.token_id)
	super.select_row(index)

func _command_button(entry: Dictionary) -> Button:
	var data = entry.duplicate(true)
	if str(data.get("action", "")) in ["token_socket_select", "page:amplifiers"]:
		var button = _button(str(data.get("text", "选择")), func():
			token_state.selected_token_id = int(data.get("id", 0))
			token_state.selected_slot_index = int(data.get("extra", 0))
			owner_page.page_context.token_selected = token_state.selected_token_id
			owner_page.page_context.token_slot = token_state.selected_slot_index
			if data.action == "page:amplifiers": command.emit("page:amplifiers", token_state.selected_token_id, token_state.selected_slot_index)
			else: _show_detail(), bool(data.get("disabled", false)))
		button.set_meta("command", data)
		return button
	if str(data.get("action", "")) == "op:equip_amplifier":
		data.extra = {"character_id": token_state.get("character_id", 1), "token_id": token_state.get("selected_token_id", 0), "slot_index": token_state.get("selected_slot_index", 0)}
	return super._command_button(data)
