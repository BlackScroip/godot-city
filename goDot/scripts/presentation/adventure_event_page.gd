extends Control

signal command(kind: String, id: Variant, extra: Variant)
signal closed

const RICH_TEXT = preload("res://scripts/presentation/source_rich_text.gd")
const NAVIGATION = preload("res://scripts/presentation/role_navigation.gd")
static var _art: Dictionary = {}
var background: TextureRect
var illustration: TextureRect
var title_label: Label
var story: RichTextLabel
var story_scroll: ScrollContainer
var choice_scroll: ScrollContainer
var choices: VBoxContainer
var choice_buttons: Array[Button] = []
var resource_bar: HBoxContainer
var divider: TextureRect
var back_button: Button
var stars: Array[TextureRect] = []
var _context: Dictionary = {}
var _submitting := false

func configure(_host, _rows: Array, context: Dictionary) -> void:
	_context = context
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	background = _picture("事件2背景" if context.get("event_type", "Normal") == "Spacial" else "事件1背景")
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.modulate = Color(0.46, 0.46, 0.46)
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var mask := _picture("事件圆形遮罩")
	mask.stretch_mode = TextureRect.STRETCH_SCALE
	mask.modulate.a = 0.59
	add_child(mask)
	mask.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	illustration = _picture(str(context.get("icon", "")))
	add_child(illustration)
	for index in 3:
		var star := _picture("高亮星标_淡蓝")
		add_child(star)
		stars.append(star)
	title_label = DungeonStyle.label(DungeonCatalog.clean(context.get("name", "冒险事件")), 36)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(title_label)
	divider = _picture("11")
	divider.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(divider)
	story_scroll = ScrollContainer.new()
	story_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(story_scroll)
	story = RICH_TEXT.new()
	story.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	story.add_theme_font_override("normal_font", DungeonStyle.font())
	story.add_theme_color_override("default_color", Color.WHITE)
	story.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	story.add_theme_constant_override("shadow_offset_y", 1)
	story_scroll.add_child(story)
	choice_scroll = ScrollContainer.new()
	choice_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(choice_scroll)
	choices = VBoxContainer.new()
	choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choices.add_theme_constant_override("separation", 16)
	choice_scroll.add_child(choices)
	for choice in context.get("choices", []):
		var button := Button.new()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = bool(choice.get("disabled", false))
		button.tooltip_text = DungeonCatalog.clean(choice.get("reason", ""))
		button.set_meta("choice", choice)
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			var style := StyleBoxTexture.new()
			style.texture = _texture("几何ui-暗圆角矩形")
			style.texture_margin_left = 26
			style.texture_margin_right = 26
			style.texture_margin_top = 26
			style.texture_margin_bottom = 26
			style.modulate_color = Color("fff0ba") if state in ["hover", "focus"] else Color("cccccc") if state == "pressed" else Color.WHITE
			button.add_theme_stylebox_override(state, style)
		var paper := _picture("几何ui-白圆角矩形")
		paper.stretch_mode = TextureRect.STRETCH_SCALE
		paper.modulate = Color("aaaaaa") if button.disabled else Color.WHITE
		button.add_child(paper)
		paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		paper.offset_left = 7
		paper.offset_right = -7
		paper.offset_top = 7
		paper.offset_bottom = -7
		var label := RICH_TEXT.new()
		label.name = "ChoiceText"
		label.add_theme_font_override("normal_font", DungeonStyle.font())
		label.add_theme_color_override("default_color", Color("716247") if button.disabled else Color("79531e"))
		button.add_child(label)
		button.pressed.connect(func():
			if _submitting: return
			_submitting = true
			command.emit(str(choice.action), choice.get("id", 0), choice.get("extra", 0)))
		button.resized.connect(func(): _layout_choice(button))
		choices.add_child(button)
		choice_buttons.append(button)
	resource_bar = HBoxContainer.new()
	resource_bar.add_theme_constant_override("separation", 22)
	add_child(resource_bar)
	for pair in [["sprite_materialicon_102", str(context.get("magic", 0))], ["sprite_abilityitemicon_15101", "%d/%d" % [int(context.get("search", 0)), maxi(3, int(context.get("search_max", 3)))]]]:
		var counter := PanelContainer.new()
		var panel := StyleBoxTexture.new()
		panel.texture = _texture("货币_底")
		panel.texture_margin_left = 24
		panel.texture_margin_right = 24
		panel.set_content_margin_all(4)
		counter.add_theme_stylebox_override("panel", panel)
		resource_bar.add_child(counter)
		var line := HBoxContainer.new()
		counter.add_child(line)
		var icon := _picture(str(pair[0]))
		icon.custom_minimum_size = Vector2(36, 36)
		line.add_child(icon)
		var value := DungeonStyle.label(str(pair[1]), 22)
		value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.add_child(value)
	back_button = NAVIGATION.create_header_back_button(size, "返回")
	back_button.pressed.connect(func(): closed.emit())
	add_child(back_button)
	resized.connect(_layout)
	_layout.call_deferred()

static func _texture(key: String) -> Texture2D:
	if _art.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/adventure_events/resource_map.json"))
		if parsed is Dictionary: _art = parsed
	return DungeonStyle.texture(str(_art.get(key, key)))

func _picture(key: String) -> TextureRect:
	var image := TextureRect.new()
	image.texture = _texture(key)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return image

func _layout() -> void:
	if not is_instance_valid(story) or size.x <= 0 or size.y <= 0: return
	var compact := size.y < 600
	var portrait := size.x < size.y
	var content_x := size.x * 0.43 if not portrait else 20.0
	var content_width := size.x * 0.50 if not portrait else size.x - 40.0
	var title_y := size.y * 0.095 if not portrait else size.y * 0.25
	var title_height := 40.0 if compact else 64.0
	back_button.position = Vector2(14, 12)
	NAVIGATION.configure_header_back_button(back_button, size, "返回")
	resource_bar.position = Vector2(size.x - (270 if compact or portrait else 390), 16)
	resource_bar.size = Vector2(250 if compact or portrait else 370, 36 if compact else 48)
	for counter in resource_bar.get_children():
		counter.custom_minimum_size.x = 115 if compact or portrait else 170
		var line: HBoxContainer = counter.get_child(0)
		line.get_child(0).custom_minimum_size = Vector2(28, 28) if compact else Vector2(36, 36)
		line.get_child(1).add_theme_font_size_override("font_size", 17 if compact else 22)
	illustration.position = Vector2(size.x * 0.07, size.y * 0.26) if not portrait else Vector2(size.x * 0.30, 65)
	illustration.size = Vector2(size.x * 0.30, size.y * 0.46) if not portrait else Vector2(size.x * 0.40, size.y * 0.17)
	for index in stars.size():
		var points := [Vector2(0.16, 0.63), Vector2(0.42, 0.30), Vector2(0.25, 0.40)]
		stars[index].visible = not portrait
		stars[index].position = size * points[index]
		stars[index].size = Vector2(26, 26) if compact else Vector2(50, 50)
	title_label.position = Vector2(content_x, title_y)
	title_label.size = Vector2(content_width, title_height)
	title_label.add_theme_font_size_override("font_size", 24 if compact or portrait else 36)
	divider.position = Vector2(content_x + content_width * 0.08, title_y + title_height + 2)
	divider.size = Vector2(content_width * 0.84, 16 if compact else 24)
	var story_top := divider.position.y + divider.size.y + (8 if compact else 14)
	var choice_top := size.y * (0.59 if not portrait else 0.64)
	story_scroll.position = Vector2(content_x + 8, story_top)
	story_scroll.size = Vector2(content_width - 16, maxf(45, choice_top - story_top - (16 if compact else 30)))
	story.add_theme_font_size_override("normal_font_size", 17 if compact or portrait else 26)
	story.set_source(str(_context.get("story", "")))
	story.text = "[center]" + story.text + "[/center]"
	choice_scroll.position = Vector2(content_x - 5, choice_top)
	choice_scroll.size = Vector2(content_width + 10, maxf(60, size.y - choice_top - (18 if compact else 70)))
	choices.add_theme_constant_override("separation", 10 if compact else 20)
	for button in choice_buttons: _layout_choice(button)

func _layout_choice(button: Button) -> void:
	var compact := size.y < 600 or size.x < size.y
	var label: RichTextLabel = button.get_node("ChoiceText")
	label.add_theme_font_size_override("normal_font_size", 16 if compact else 24)
	var padding := 18.0 if compact else 30.0
	label.position = Vector2(padding, 12 if compact else 18)
	label.size.x = maxf(60, button.size.x - padding * 2)
	label.set_source(str(button.get_meta("choice").get("text", "")))
	button.custom_minimum_size.y = maxf(54 if compact else 90, label.get_content_height() + label.position.y * 2)
