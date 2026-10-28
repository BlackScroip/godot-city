extends Control

const NAVIGATION = preload("res://scripts/presentation/role_navigation.gd")
var host
var _header: Control
var _scroll: ScrollContainer
var _table: VBoxContainer
var _help: Control
const ROW_HEIGHT := 72.0

func configure(page) -> void:
	host = page
	name = "AttributeDetails"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade = ColorRect.new()
	shade.color = Color(0, 0, 0, 0.73)
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var close = NAVIGATION.create_back_button("返回角色详情")
	close.name = "CloseAttributes"
	close.pressed.connect(func(): host._dismiss_overlay(self))
	add_child(close)
	NAVIGATION.place_back_button(close)
	_header = Control.new()
	add_child(_header)
	for entry in [["属性", 130, 0.0], ["类型", 0, 0.64], ["当前值", 0, 0.865]]:
		var title = host._label(entry[0], 42)
		title.autowrap_mode = TextServer.AUTOWRAP_OFF
		_header.add_child(title)
		title.set_meta("column", entry)
	for column in [0.084, 0.55, 0.797, 0.985]:
		var divider = ColorRect.new()
		divider.color = Color(1, 1, 1, 0.7)
		divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
		divider.set_meta("divider", column)
		_header.add_child(divider)
	_scroll = ScrollContainer.new()
	_scroll.name = "AttributeScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	add_child(_scroll)
	_table = VBoxContainer.new()
	_table.name = "AttributeTable"
	_table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_table.add_theme_constant_override("separation", 0)
	_scroll.add_child(_table)
	var definitions: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/role_character/attribute_rows.json"))
	var battle: Dictionary = host.rows[host.selected].get("combat_stats", {})
	var raw_values: Dictionary = battle.get("attribute_values", {})
	var stats: Array = host.rows[host.selected].get("stats", [])
	for index in definitions.size():
		var definition: Dictionary = definitions[index]
		if definition.get("separator", false):
			_add_row("", "", "", "")
			continue
		var property = str(definition.property)
		var raw = float(raw_values.get(property, definition.baseSubtract))
		var value = format_value(raw, definition)
		if definition.format == "Discount" and host.context.get("systems"):
			value = _percent(host.context.systems._shop_price_rate(raw), true)
		if not raw_values.has(property):
			if index < stats.size(): value = str(stats[index][1])
			elif property == "CurAttackSpeed": value = "%.2f" % float(battle.get("attack_speed", 1.0))
			elif property == "CurMoveSpeed": value = "%.2f" % float(battle.get("move_speed", host._source().get("move_speed", 0)))
		_add_row(str(definition.label), value, str(definition.category), str(definition.icon), DungeonCatalog.clean(str(definition.help)))
		var hint = ""
		if not str(definition.defaultText).is_empty(): hint = "默认：" + str(definition.defaultText)
		if not str(definition.maxText).is_empty(): hint += "  上限：" + str(definition.maxText)
		if definition.format == "Discount": hint = "默认：" + _percent(raw, true)
		_table.get_child(-1).tooltip_text = hint.strip_edges()
	resized.connect(_layout)
	_layout()

static func format_value(raw: float, definition: Dictionary) -> String:
	var value = raw - float(definition.get("baseSubtract", 0))
	match str(definition.get("format", "Int")):
		"Float2": return "%.2f" % value
		"RateDiv10": return str(int(value / 10.0))
		"RateToPercentPlain": return _percent(value, false)
		"RateToPercent": return _percent(value, true)
		"Discount": return _percent(value, true)
	return str(int(value))

static func _percent(raw: float, signed: bool) -> String:
	var value = snappedf(raw / 10.0, 0.1)
	return ("+" if signed and value > 0 else "") + ("%.1f" % value).trim_suffix(".0") + "%"

func _add_row(caption: String, value: String, category: String, icon: String, help_text := "") -> void:
	var row = Control.new()
	row.name = "AttributeRow%d" % _table.get_child_count()
	row.custom_minimum_size.y = ROW_HEIGHT
	_table.add_child(row)
	if _table.get_child_count() % 2 == 0:
		var stripe = ColorRect.new()
		stripe.color = Color(0, 0, 0, 0.6)
		stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(stripe)
		stripe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if caption.is_empty(): return
	var image = host._picture(icon, Vector2.ZERO)
	row.add_child(image)
	host._rect(image, 36, 16, 40, 42)
	for entry in [[caption, 130, 0.0, 660], [category, 0, 0.62, 270], [value, 0, 0.865, 145]]:
		var label = host._label(entry[0], 25)
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.clip_text = true
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(label)
		host._rect(label, float(entry[1]), 0, float(entry[3]), ROW_HEIGHT)
		row.resized.connect(func(): host._rect(label, float(entry[1]) + row.size.x * float(entry[2]), 0, float(entry[3]), ROW_HEIGHT))
	if not help_text.is_empty():
		var help = host._icon_button("须知", caption, Vector2(36, 36))
		if help.icon == null: help.text = "?"
		row.add_child(help)
		row.resized.connect(func(): host._rect(help, row.size.x * 0.94, 20, 36, 36))
		help.pressed.connect(func():
			if is_instance_valid(_help): _help.queue_free()
			_help = host._overlay("AttributeHelp", caption, Vector2(680, 260))
			_help.get_node("Center/Panel/Stack").add_child(host._label(help_text, 26)))

func _layout() -> void:
	if not is_instance_valid(_scroll): return
	NAVIGATION.place_back_button(get_node("CloseAttributes"))
	var width = size.x - 590
	host._rect(_header, 335, 43, width, 68)
	for title in _header.get_children():
		if title.has_meta("divider"):
			host._rect(title, width * float(title.get_meta("divider")), 2, 2, 56)
			continue
		var column: Array = title.get_meta("column")
		host._rect(title, float(column[1]) + width * float(column[2]), 0, 210, 65)
	host._rect(_scroll, 335, 161, width, floorf((size.y - 205) / ROW_HEIGHT) * ROW_HEIGHT)

func close() -> void:
	if is_instance_valid(_help): _help.queue_free()
	hide()

func dismiss_help() -> bool:
	if not is_instance_valid(_help) or not _help.visible: return false
	_help.hide()
	return true
