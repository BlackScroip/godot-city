class_name DungeonCharacterUpgradeDialog
extends Control

signal confirmed(character_id: int)
signal canceled

const GOLD := Color("ffdc84")
const PAPER := Color("fff9ee")
const DESIGN_SIZE := Vector2(850, 680)

var systems: DungeonSystems
var character_id := 0
var quote: Dictionary = {}
var panel: Panel
var confirm_button: Button
var cancel_button: Button
var reason_label: Label
var material_labels: Array[Label] = []
var _map: Dictionary = {}
var _submitted := false

func configure(source: DungeonSystems, id: int) -> void:
	systems = source
	character_id = id
	name = "CharacterUpgradeDialog"
	theme = DungeonStyle.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_map = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/role_character/resource_map.json"))
	var dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.48)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	panel = Panel.new()
	panel.name = "UpgradeConfirmation"
	panel.size = DESIGN_SIZE
	panel.add_theme_stylebox_override("panel", _box(Color("444d5c"), Color("bcac76"), 28, 2))
	add_child(panel)
	var inner = Panel.new()
	inner.position = Vector2(10, 10)
	inner.size = DESIGN_SIZE - Vector2(20, 20)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_theme_stylebox_override("panel", _box(Color.TRANSPARENT, GOLD, 23, 2))
	panel.add_child(inner)
	resized.connect(_adapt)
	refresh()
	_adapt.call_deferred()

func refresh() -> void:
	quote = systems.character_upgrade_status(character_id)
	for child in panel.get_children():
		if child.name == "Quote":
			panel.remove_child(child)
			child.queue_free()
	material_labels.clear()
	var content = Control.new()
	content.name = "Quote"
	content.size = DESIGN_SIZE
	panel.add_child(content)
	_badge(content, int(quote.level), Vector2(220, 45))
	_badge(content, int(quote.next_level), Vector2(470, 45))
	_label(content, "➜", Rect2(355, 65, 115, 75), 72, GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	var icons = ["icon_hp_white", "icon_atk_white", "icon_def_white"]
	for index in 3:
		var y = 205 + index * 63
		var stripe = ColorRect.new()
		stripe.position = Vector2(173, y)
		stripe.size = Vector2(485, 54)
		stripe.color = Color(0.12, 0.14, 0.18, 0.14)
		stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(stripe)
		_picture(content, icons[index], Rect2(177, y + 5, 44, 44), Color("edce95"))
		var stat: Dictionary = quote.stats[index]
		_label(content, str(stat.name), Rect2(230, y, 150, 54), 29)
		_label(content, str(stat.current), Rect2(437, y, 73, 54), 26, PAPER, HORIZONTAL_ALIGNMENT_RIGHT)
		_label(content, "➜", Rect2(521, y, 40, 54), 31)
		_label(content, str(stat.next), Rect2(568, y, 83, 54), 26, GOLD)
	_label(content, "所需材料", Rect2(300, 395, 250, 36), 24, Color("e0cea0"), HORIZONTAL_ALIGNMENT_CENTER)
	var materials: Array = []
	for key in quote.price:
		if int(quote.price[key]) > 0: materials.append(key)
	for index in materials.size():
		var key = materials[index]
		var x = 425.0 - materials.size() * 58.0 + index * 116.0 + 10.0
		var icon = TextureRect.new()
		icon.texture = load("res://assets/ui/camp/portraits/sprite_materialicon_%s.png" % key)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.position = Vector2(x + 7, 441)
		icon.size = Vector2(80, 80)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(icon)
		var frame = TextureRect.new()
		var rarity = clampi(int(systems.catalog.find("MaterialData", int(key)).get("star_num", 1)), 1, 5)
		frame.texture = load("res://assets/ui/role_inventory/slotfg_rare_square_%d_v2.png" % rarity)
		frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		frame.position = Vector2(x, 435)
		frame.size = Vector2(96, 96)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(frame)
		content.move_child(icon, -1)
		var owned = systems.material(int(key))
		var required = int(quote.price[key])
		var amount = _label(content, "%d/%d" % [owned, required], Rect2(x, 504, 96, 25), 19, Color("b5e45b") if owned >= required else Color("ff8f80"), HORIZONTAL_ALIGNMENT_CENTER)
		amount.tooltip_text = "%s：%d / %d" % [systems.material_name(int(key)), owned, required]
		amount.mouse_filter = Control.MOUSE_FILTER_PASS
		material_labels.append(amount)
	reason_label = _label(content, str(quote.reason), Rect2(65, 535, 720, 33), 21, Color("ffb4a3"), HORIZONTAL_ALIGNMENT_CENTER)
	cancel_button = _button(content, "取消", Rect2(70, 581, 280, 65), Color("dfdcd6"))
	cancel_button.pressed.connect(func(): canceled.emit(); queue_free())
	confirm_button = _button(content, "确定", Rect2(495, 581, 280, 65), Color("ffda7b"))
	confirm_button.disabled = not bool(quote.can_upgrade)
	confirm_button.pressed.connect(_confirm)

func _confirm() -> void:
	if _submitted: return
	var current = systems.character_upgrade_status(character_id)
	if not bool(current.can_upgrade) or current.level != quote.level or current.price != quote.price:
		refresh()
		if bool(current.can_upgrade): reason_label.text = "角色状态已变化，请确认新的升级信息"
		return
	_submitted = true
	confirm_button.disabled = true
	confirmed.emit(character_id)
	queue_free()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		canceled.emit()
		queue_free()

func _adapt() -> void:
	if not is_instance_valid(panel): return
	var factor = minf(1.0, minf(size.x / 1100.0, size.y / 800.0))
	panel.scale = Vector2.ONE * factor
	panel.position = (size - DESIGN_SIZE * factor) * 0.5

func _badge(parent: Control, level: int, at: Vector2) -> void:
	_picture(parent, "Adventure_Level_5", Rect2(at, Vector2(130, 130)))
	_label(parent, str(level), Rect2(at + Vector2(0, 30), Vector2(130, 73)), 48, PAPER, HORIZONTAL_ALIGNMENT_CENTER)

func _picture(parent: Control, key: String, rect: Rect2, tint := Color.WHITE) -> TextureRect:
	var image = TextureRect.new()
	if _map.has(key): image.texture = load(str(_map[key]))
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.position = rect.position
	image.size = rect.size
	image.modulate = tint
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(image)
	return image

func _label(parent: Control, text: String, rect: Rect2, font_size: int, color := PAPER, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label = Label.new()
	label.text = text
	label.position = rect.position
	label.size = rect.size
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color("282b33"))
	label.add_theme_constant_override("outline_size", 4)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.horizontal_alignment = align
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _button(parent: Control, text: String, rect: Rect2, color: Color) -> Button:
	var button = Button.new()
	button.text = text
	button.position = rect.position
	button.size = rect.size
	button.add_theme_font_size_override("font_size", 38)
	button.add_theme_color_override("font_color", PAPER)
	button.add_theme_color_override("font_outline_color", Color("282b33"))
	button.add_theme_constant_override("outline_size", 6)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, _box(color.darkened(0.18) if state == "pressed" or state == "disabled" else color, Color("a9a59a"), 33, 3))
	parent.add_child(button)
	return button

func _box(fill: Color, border: Color, radius: int, width: int) -> StyleBoxFlat:
	var box = StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(radius)
	return box
