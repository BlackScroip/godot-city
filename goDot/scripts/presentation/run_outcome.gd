extends Control

signal command(kind: String, id: Variant, extra: Variant)
var content: VBoxContainer
var portrait: TextureRect
var title: Label
var details: Label
var confirm: Button

func configure(context: Dictionary) -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var shade = ColorRect.new()
	shade.color = Color(0.025, 0.035, 0.04, 0.88)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	add_child(content)
	var center = CenterContainer.new()
	content.add_child(center)
	portrait = DungeonStyle.picture(str(context.get("portrait", "")), Vector2(80, 80))
	center.add_child(portrait)
	title = DungeonStyle.label(str(context.get("title", "")), 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.modulate = DungeonStyle.GOLD if context.get("victory", false) else Color("e9a5a1")
	content.add_child(title)
	var subtitle = DungeonStyle.label(str(context.get("subtitle", "")), 20)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(subtitle)
	var scroller = ScrollContainer.new()
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroller)
	details = DungeonStyle.label(str(context.get("details", "")), 20)
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scroller.add_child(details)
	confirm = Button.new()
	confirm.text = str(context.get("button", ""))
	confirm.custom_minimum_size = Vector2(200, 48)
	confirm.visible = not context.get("pending", false)
	confirm.pressed.connect(func():
		confirm.disabled = true
		command.emit(str(context.get("action", "")), 0, 0))
	content.add_child(confirm)
	resized.connect(_layout)
	_layout.call_deferred()

func _layout() -> void:
	if not is_instance_valid(content): return
	var height = minf(520, maxf(240, size.y - 32))
	content.size = Vector2(minf(560, maxf(200, size.x - 48)), height)
	content.position = (size - content.size) * 0.5
	portrait.custom_minimum_size = Vector2.ONE * (64 if size.y < 500 else 80)
	content.add_theme_constant_override("separation", 8 if size.y < 500 else 14)
