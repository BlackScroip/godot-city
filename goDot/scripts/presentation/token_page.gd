extends "res://scripts/presentation/camp_services_page.gd"

var token_state: Dictionary = {}
var socket_buttons: Array[Button] = []
var preset_buttons: Array[Button] = []

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
	var character = _label(str(token_state.get("character_name", "")), 17)
	character.autowrap_mode = TextServer.AUTOWRAP_OFF
	character.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(character)
	for entry in token_state.get("toolbar_buttons", []): toolbar.add_child(_command_button(entry))
	var loadouts = HFlowContainer.new()
	loadouts.add_theme_constant_override("h_separation", 8)
	root_box.add_child(loadouts)
	var preset_title = _label("预设", 16)
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
	var capacity = _label("信物 %d / %d" % [token_state.get("equipped", []).size(), slots], 16)
	capacity.autowrap_mode = TextServer.AUTOWRAP_OFF
	loadouts.add_child(capacity)

func _columns() -> int:
	return 3 if compact else 4

func _show_detail() -> void:
	super._show_detail()
	socket_buttons.clear()
	if rows.is_empty(): return
	var row: Dictionary = rows[selected]
	var slots: Array = row.get("slot_rows", token_state.get("sockets", []))
	var title = _label("信物镶嵌", 20)
	details.add_child(title)
	var socket_bar = HBoxContainer.new()
	socket_bar.add_theme_constant_override("separation", 8)
	details.add_child(socket_bar)
	details.move_child(title, mini(1, details.get_child_count() - 1))
	details.move_child(socket_bar, mini(2, details.get_child_count() - 1))
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
		if not str(slot.get("description", "")).is_empty(): column.add_child(_label(str(slot.description), 14, MUTED))
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
	if str(data.get("action", "")) == "token_socket_select":
		var button = _button(str(data.get("text", "选择")), func():
			token_state.selected_token_id = int(data.get("id", 0))
			token_state.selected_slot_index = int(data.get("extra", 0))
			owner_page.page_context.token_selected = token_state.selected_token_id
			owner_page.page_context.token_slot = token_state.selected_slot_index
			_show_detail(), bool(data.get("disabled", false)))
		button.set_meta("command", data)
		return button
	if str(data.get("action", "")) == "op:equip_amplifier":
		data.extra = {"character_id": token_state.get("character_id", 1), "token_id": token_state.get("selected_token_id", 0), "slot_index": token_state.get("selected_slot_index", 0)}
	return super._command_button(data)
