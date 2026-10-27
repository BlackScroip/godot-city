class_name DungeonDialoguePage
extends Control

signal command(kind: String, id: Variant, extra: Variant)

var portrait: TextureRect
var dialogue_band: Panel
var speaker_label: Label
var text_label: Label
var text_scroll: ScrollContainer
var skip_button: Button
var next_button: Button
var choice_scroll: ScrollContainer
var choice_buttons: Array[Button] = []
var relationship_icon: TextureRect
var relationship_label: Label
var reward_popup: Control
var _context: Dictionary = {}
var _choices: Array = []
var _choice_stack: VBoxContainer
var _divider: TextureRect
var _skip_icon: TextureRect
var _skip_label: Label
var _press_position = Vector2.ZERO
var _pressed = false
var _input_locked = false

func configure(_host: DungeonMenuPage, _rows: Array, context: Dictionary) -> void:
	_context = context
	_choices = context.get("choices", [])
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	if context.has("rewards"):
		reward_popup = preload("res://scripts/presentation/npc_reward_receipt.gd").new()
		add_child(reward_popup)
		reward_popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		reward_popup.closed.connect(func(): _send("talk_reward_close", 0, 0))
		reward_popup.configure(context.rewards)
		return
	portrait = DungeonStyle.picture(str(context.get("portrait", "")), Vector2.ZERO)
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(portrait)
	dialogue_band = Panel.new()
	dialogue_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var texture = DungeonStyle.texture("剧情对话框")
	if texture:
		var style = StyleBoxTexture.new()
		style.texture = texture
		style.texture_margin_left = 2
		style.texture_margin_right = 2
		style.texture_margin_top = 42
		style.texture_margin_bottom = 85
		dialogue_band.add_theme_stylebox_override("panel", style)
	else:
		var style = DungeonStyle.box(Color(0, 0, 0, 0.83))
		style.set_corner_radius_all(0)
		dialogue_band.add_theme_stylebox_override("panel", style)
	add_child(dialogue_band)
	speaker_label = _label(str(context.get("speaker", "")), 30, Color(1, 0.894, 0.447))
	speaker_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	speaker_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	speaker_label.clip_text = true
	add_child(speaker_label)
	_divider = DungeonStyle.picture("res://assets/ui/dialogue/speaker_mark.png", Vector2.ZERO)
	_divider.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(_divider)
	text_scroll = ScrollContainer.new()
	text_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	text_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(text_scroll)
	text_label = _label(DungeonCatalog.clean(str(context.get("text", ""))), 24, Color("fffdf4"))
	text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_scroll.add_child(text_label)
	skip_button = Button.new()
	skip_button.visible = bool(context.get("can_skip", true))
	skip_button.tooltip_text = "跳过当前对话"
	_button_style(skip_button, false)
	skip_button.pressed.connect(func(): _send("talk_skip", 0, 0))
	add_child(skip_button)
	_skip_icon = DungeonStyle.picture("res://assets/ui/dialogue/skip.png", Vector2.ZERO)
	_skip_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	skip_button.add_child(_skip_icon)
	_skip_label = _label("跳过", 28, Color.WHITE)
	_skip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_skip_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	skip_button.add_child(_skip_label)
	relationship_icon = DungeonStyle.picture("res://assets/ui/dialogue/relationship.png", Vector2.ZERO)
	relationship_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	relationship_icon.visible = bool(context.get("show_relationship", false))
	add_child(relationship_icon)
	relationship_label = _label(str(context.get("relationship", 0)), 28, Color.WHITE)
	relationship_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	relationship_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	relationship_label.visible = relationship_icon.visible
	add_child(relationship_label)
	next_button = Button.new()
	next_button.text = ""
	next_button.tooltip_text = "继续对话"
	next_button.icon = DungeonStyle.texture("箭头白")
	next_button.expand_icon = true
	next_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	next_button.add_theme_constant_override("icon_max_width", 22)
	_button_style(next_button, false)
	next_button.visible = _choices.is_empty()
	next_button.pressed.connect(_advance)
	add_child(next_button)
	choice_scroll = ScrollContainer.new()
	choice_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	choice_scroll.visible = not _choices.is_empty()
	add_child(choice_scroll)
	_choice_stack = VBoxContainer.new()
	_choice_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_choice_stack.add_theme_constant_override("separation", 12)
	choice_scroll.add_child(_choice_stack)
	for choice in _choices:
		var button = Button.new()
		button.text = DungeonCatalog.clean(str(choice.get("text", "")))
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.disabled = bool(choice.get("disabled", false))
		button.tooltip_text = str(choice.get("reason", ""))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.icon = DungeonStyle.texture(str(choice.get("icon", "sprite_conversation_talk")))
		button.expand_icon = true
		button.add_theme_color_override("icon_disabled_color", Color("999999"))
		_button_style(button, true)
		button.pressed.connect(func(): _send(str(choice.get("action", "")), choice.get("id", 0), choice.get("extra", 0)))
		_choice_stack.add_child(button)
		choice_buttons.append(button)
	resized.connect(_layout)
	_layout.call_deferred()

func _label(value: String, font_size: int, color: Color) -> Label:
	var label = DungeonStyle.label(value, font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	return label

func _button_style(button: Button, choice: bool) -> void:
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color("a2a5a0"))
	button.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	button.add_theme_constant_override("outline_size", 2)
	for state in ["normal", "hover", "pressed", "disabled"]:
		if choice:
			var style = StyleBoxTexture.new()
			style.texture = DungeonStyle.texture("res://assets/ui/dialogue/choice.png")
			style.texture_margin_left = 50
			style.texture_margin_right = 126
			style.texture_margin_top = 0
			style.texture_margin_bottom = 0
			style.content_margin_left = 24
			style.content_margin_right = 20
			style.content_margin_top = 0
			style.content_margin_bottom = 0
			style.modulate_color = Color("fff0c5") if state == "hover" else Color("c7b993") if state == "pressed" else Color.WHITE
			button.add_theme_stylebox_override(state, style)
		else:
			button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

func _layout() -> void:
	if not is_instance_valid(portrait) or size.x <= 0 or size.y <= 0: return
	var compact = size.y < 500
	var unit = size.y / 1080.0
	var band_height = size.y * 0.35
	var text_x = size.x * 0.247
	var text_width = size.x * 0.69
	portrait.size = Vector2(size.y * 0.75, size.y * 1.5)
	portrait.position = Vector2(size.x * 0.03, -size.y * 0.05)
	dialogue_band.position = Vector2(0, size.y - band_height)
	dialogue_band.size = Vector2(size.x, band_height)
	speaker_label.add_theme_font_size_override("font_size", maxi(16, roundi(35.7 * unit)))
	speaker_label.position = Vector2(text_x, size.y * 0.69)
	speaker_label.size = Vector2(text_width, 27 if compact else 42)
	_divider.size = Vector2(20, 12) if compact else Vector2(34, 20)
	_divider.position = speaker_label.position + Vector2(-_divider.size.x - (6 if compact else 10), (speaker_label.size.y - _divider.size.y) * 0.5)
	text_scroll.position = Vector2(text_x, size.y * 0.75)
	text_scroll.size = Vector2(text_width, maxf(40, size.y - text_scroll.position.y - (20 if compact else 38)))
	text_label.add_theme_font_size_override("font_size", maxi(16, roundi(38 * unit)))
	skip_button.position = Vector2(42, 49.84) * unit
	skip_button.size = Vector2(200, 141.76) * unit
	_skip_icon.position = Vector2(38.55, 0) * unit
	_skip_icon.size = Vector2(122.89, 98.31) * unit
	_skip_label.position = Vector2(0, 91.76) * unit
	_skip_label.size = Vector2(200, 50) * unit
	_skip_label.add_theme_font_size_override("font_size", maxi(18, roundi(50 * unit)))
	relationship_icon.size = Vector2(100, 100) * unit
	relationship_icon.position = Vector2(size.x - 152 * unit, 36 * unit)
	relationship_label.position = relationship_icon.position - Vector2(0, 3 if compact else 6)
	relationship_label.size = relationship_icon.size
	relationship_label.add_theme_font_size_override("font_size", maxi(16, roundi(42 * unit)))
	next_button.size = Vector2(38, 32) if compact else Vector2(52, 44)
	next_button.position = Vector2(size.x * 0.91, size.y - next_button.size.y - (14 if compact else 28))
	var row_height = maxf(32, 84 * unit)
	var separation = 24 * unit
	var choice_height = minf(size.y * 0.51, _choices.size() * row_height + maxi(0, _choices.size() - 1) * separation)
	var choice_width = minf(size.x * 0.45, 840 * unit)
	choice_scroll.position = Vector2(size.x - 61 * unit - choice_width, maxf(size.y * 0.16, size.y * 0.5 - 107.25 * unit - choice_height * 0.5))
	choice_scroll.size = Vector2(choice_width, choice_height)
	_choice_stack.add_theme_constant_override("separation", separation)
	for button in choice_buttons:
		button.custom_minimum_size.y = row_height
		button.add_theme_font_size_override("font_size", maxi(14, roundi(34 * unit)))
		button.add_theme_constant_override("icon_max_width", roundi(86.5 * unit))
		button.add_theme_constant_override("h_separation", roundi(8 * unit))
		for state in ["normal", "hover", "pressed", "disabled"]:
			var style = button.get_theme_stylebox(state) as StyleBoxTexture
			style.content_margin_left = 20 * unit
			style.content_margin_right = 20 * unit

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressed = true
			_press_position = event.position
		elif _pressed:
			_pressed = false
			if event.position.distance_to(_press_position) < 12: _advance()
	elif event is InputEventScreenTouch:
		if event.pressed:
			_pressed = true
			_press_position = event.position
		elif _pressed:
			_pressed = false
			if event.position.distance_to(_press_position) < 12: _advance()

func _advance() -> void:
	if _choices.is_empty(): _send("talk_next", 0, 0)

func _send(kind: String, id: Variant, extra: Variant) -> void:
	if _input_locked or kind.is_empty(): return
	if kind == "talk_skip" and not _choices.is_empty():
		command.emit(kind, id, extra)
		return
	_input_locked = true
	if next_button: next_button.disabled = true
	if skip_button: skip_button.disabled = true
	for button in choice_buttons: button.disabled = true
	command.emit(kind, id, extra)
