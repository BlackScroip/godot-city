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
var _context: Dictionary = {}
var _choices: Array = []
var _choice_stack: VBoxContainer
var _divider: TextureRect
var _press_position = Vector2.ZERO
var _pressed = false
var _input_locked = false

func configure(_host: DungeonMenuPage, _rows: Array, context: Dictionary) -> void:
	_context = context
	_choices = context.get("choices", [])
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
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
	speaker_label = _label(str(context.get("speaker", "")), 30, Color("f7d989"))
	speaker_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	speaker_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	speaker_label.clip_text = true
	add_child(speaker_label)
	_divider = DungeonStyle.picture("分割线四", Vector2.ZERO)
	_divider.stretch_mode = TextureRect.STRETCH_SCALE
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
	skip_button.text = "跳过"
	skip_button.tooltip_text = "跳过当前对话"
	skip_button.icon = DungeonStyle.texture("箭头白")
	skip_button.expand_icon = true
	skip_button.add_theme_constant_override("icon_max_width", 22)
	_button_style(skip_button, false)
	skip_button.pressed.connect(func(): _send("talk_skip", 0, 0))
	add_child(skip_button)
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
	button.add_theme_color_override("font_color", Color("fff3d0"))
	button.add_theme_color_override("font_disabled_color", Color("a2a5a0"))
	for state in ["normal", "hover", "pressed", "disabled"]:
		var color = Color(0.06, 0.10, 0.11, 0.82 if choice else 0.45)
		if state == "hover": color = Color(0.22, 0.28, 0.28, 0.9)
		var border = Color("cfbc81") if choice else Color.TRANSPARENT
		var style = DungeonStyle.box(color, border, 1)
		style.set_corner_radius_all(0)
		style.set_content_margin_all(10 if choice else 5)
		button.add_theme_stylebox_override(state, style)

func _layout() -> void:
	if not is_instance_valid(portrait) or size.x <= 0 or size.y <= 0: return
	var compact = size.y < 500
	var band_height = clampf(size.y * 0.42, 160, 190) if compact else clampf(size.y * 0.34, 140, 360)
	var text_x = size.x * 0.25
	var text_width = size.x * 0.61
	portrait.size = Vector2(size.x * 0.4, size.y * 0.91)
	portrait.position = Vector2(-size.x * 0.025, size.y - portrait.size.y)
	dialogue_band.position = Vector2(0, size.y - band_height)
	dialogue_band.size = Vector2(size.x, band_height)
	speaker_label.add_theme_font_size_override("font_size", 20 if compact else 30)
	speaker_label.position = Vector2(text_x, size.y - band_height + (16 if compact else 28))
	speaker_label.size = Vector2(text_width, 28 if compact else 43)
	_divider.position = speaker_label.position + Vector2(0, (28 if compact else 43) + 2)
	_divider.size = Vector2(42 if compact else 60, 3)
	text_scroll.position = _divider.position + Vector2(0, 11 if compact else 20)
	text_scroll.size = Vector2(text_width, maxf(40, size.y - text_scroll.position.y - (20 if compact else 38)))
	text_label.add_theme_font_size_override("font_size", 16 if compact else 24)
	skip_button.position = Vector2(18 if compact else 30, 14 if compact else 26)
	skip_button.size = Vector2(84 if compact else 116, 36 if compact else 48)
	skip_button.add_theme_font_size_override("font_size", 16 if compact else 22)
	next_button.size = Vector2(38, 32) if compact else Vector2(52, 44)
	next_button.position = Vector2(size.x * 0.91, size.y - next_button.size.y - (14 if compact else 28))
	var row_height = 42 if compact else 62
	var choice_height = minf(size.y * 0.50, _choices.size() * (row_height + (6 if compact else 12)))
	choice_scroll.position = Vector2(size.x * 0.60, maxf(skip_button.get_rect().end.y + 8, dialogue_band.position.y - choice_height - 12))
	choice_scroll.size = Vector2(size.x * 0.35, maxf(0, dialogue_band.position.y - choice_scroll.position.y - 12))
	_choice_stack.add_theme_constant_override("separation", 6 if compact else 12)
	for button in choice_buttons:
		button.custom_minimum_size.y = row_height
		button.add_theme_font_size_override("font_size", 14 if compact else 21)

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
	_input_locked = true
	next_button.disabled = true
	skip_button.disabled = true
	for button in choice_buttons: button.disabled = true
	command.emit(kind, id, extra)
