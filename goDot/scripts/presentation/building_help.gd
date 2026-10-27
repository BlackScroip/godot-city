extends Control

signal closed

const GUIDE_ID := 101
var canvas: Control
var panel: NinePatchRect
var shade: ColorRect
var close_button: Button
var side_close: Button
var body_scroll: ScrollContainer
var body: RichTextLabel
var _art: Dictionary = {}
var _tween: Tween
var _closing := false
var _logical_size := Vector2.ZERO

func configure() -> void:
	name = "BuildingHelp"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_art = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/settings/resource_map.json"))
	var articles: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/settings/guides.json"))
	var article: Dictionary = {}
	for entry in articles:
		if int(entry.id) == GUIDE_ID: article = entry
	var page: Dictionary = article.pages[0]
	shade = ColorRect.new()
	shade.color = Color(0, 0, 0, 0.7843137)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	canvas = Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	panel = _patch("几何ui-暗圆角矩形", 38)
	canvas.add_child(panel)
	var caption := _label(str(article.title), 30)
	caption.position = Vector2(80, 58)
	caption.size = Vector2(980, 50)
	panel.add_child(caption)
	for index in 2:
		var line := DungeonStyle.picture(str(_art["分割线3_白"]), Vector2.ZERO)
		line.position = Vector2(280 + index * 290, 118)
		line.size = Vector2(290, 22)
		line.flip_h = index == 1
		panel.add_child(line)
	var heading := _label(str(page.head), 28)
	heading.position = Vector2(120, 171)
	heading.size = Vector2(900, 44)
	panel.add_child(heading)
	var picture_frame := _patch("几何ui-白圆角矩形", 28)
	picture_frame.position = Vector2(220, 228)
	picture_frame.size = Vector2(700, 360)
	panel.add_child(picture_frame)
	var picture := DungeonStyle.picture(str(page.image), Vector2.ZERO)
	picture.name = "GuideImage"
	picture.position = Vector2(230, 238)
	picture.size = Vector2(680, 340)
	panel.add_child(picture)
	body_scroll = ScrollContainer.new()
	body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body_scroll.position = Vector2(115, 612)
	body_scroll.size = Vector2(910, 112)
	panel.add_child(body_scroll)
	body = RichTextLabel.new()
	body.name = "GuideBody"
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = false
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_PASS
	body.add_theme_font_size_override("normal_font_size", 28)
	body.add_theme_color_override("default_color", Color.WHITE)
	body.text = "[center]" + DungeonLocale.text(str(page.body)) + "[/center]"
	body_scroll.add_child(body)
	var dot := DungeonStyle.picture(str(_art["滑动按钮_white"]), Vector2.ZERO)
	dot.position = Vector2(555, 747)
	dot.size = Vector2(30, 30)
	dot.modulate = Color("f6d948")
	panel.add_child(dot)
	close_button = _close_button()
	close_button.position = Vector2(1074, -16)
	close_button.size = Vector2(106, 106)
	panel.add_child(close_button)
	side_close = _close_button()
	side_close.size = Vector2(72, 72)
	canvas.add_child(side_close)
	resized.connect(_layout)
	_layout()
	modulate.a = 0.0
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0, 0.3 / float(DungeonSettings.read_options().ui_speed)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	close_button.grab_focus.call_deferred()

func _label(value: String, font_size: int) -> Label:
	var result := DungeonStyle.label(value, font_size)
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.add_theme_color_override("font_color", Color.WHITE)
	result.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	return result

func _patch(key: String, margin: int) -> NinePatchRect:
	var result := NinePatchRect.new()
	result.texture = DungeonStyle.texture(str(_art[key]))
	result.patch_margin_left = margin
	result.patch_margin_right = margin
	result.patch_margin_top = margin
	result.patch_margin_bottom = margin
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result

func _close_button() -> Button:
	var result := Button.new()
	result.icon = DungeonStyle.texture(str(_art["滑动按钮_close"]))
	result.expand_icon = true
	result.tooltip_text = "关闭"
	for state in ["normal", "hover", "pressed", "focus"]:
		result.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	result.pressed.connect(go_back)
	return result

func go_back() -> void:
	if _closing: return
	_closing = true
	if _tween and _tween.is_valid(): _tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 0.0, 0.3 / float(DungeonSettings.read_options().ui_speed)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_callback(func():
		closed.emit()
		queue_free())

func _layout() -> void:
	if not is_instance_valid(canvas): return
	var factor := maxf(0.01, minf(size.y / 900.0, size.x / 1500.0))
	_logical_size = size / factor
	canvas.scale = Vector2.ONE * factor
	canvas.size = _logical_size
	panel.size = Vector2(1140, 810)
	panel.position = (_logical_size - panel.size) * 0.5
	side_close.position = Vector2(_logical_size.x - 150, _logical_size.y * 0.5 - 36)
