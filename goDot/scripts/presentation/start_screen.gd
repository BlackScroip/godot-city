extends CanvasLayer

signal start_requested

const ART := "res://assets/ui/startup/"

var stage := Control.new()
var scenery := Control.new()
var logo := TextureRect.new()
var start_button := Button.new()
var version_label := Label.new()
var error_label := Label.new()
var _trees: Array[TextureRect] = []
var _elapsed := 0.0
var _starting := false

func _ready() -> void:
	layer = 110
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.mouse_filter = Control.MOUSE_FILTER_STOP
	stage.theme = DungeonStyle.theme()
	add_child(stage)
	scenery.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(scenery)
	_picture("30e884e8e45f1d6f.png", scenery, Rect2(0, 0, 2048, 1024))
	_picture("240c397c0477927b.png", scenery, Rect2(0, 242, 2048, 782))
	_trees.append(_picture("b4783a3e2f3fed47.png", scenery, Rect2(0, 448, 587, 576)))
	_trees.append(_picture("322ad728caf6116e.png", scenery, Rect2(233, 244, 1197, 780)))
	_trees.append(_picture("867355ec8d421339.png", scenery, Rect2(1230, 336, 818, 688)))
	var shade := _picture("2606c99ee8989af8.png", stage, Rect2())
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	logo.texture = load(ART + "b88120e33506c245.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(logo)
	start_button.text = "开始游戏"
	start_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxTexture.new()
		style.texture = load(ART + "bbda49887a4d167b.png")
		style.modulate_color = Color(0.65, 0.85, 1.0, 0.9) if state == "hover" else Color(1, 1, 1, 0.7 if state == "pressed" else 0.4)
		start_button.add_theme_stylebox_override(state, style)
	start_button.add_theme_color_override("font_color", Color("fff9e8"))
	start_button.add_theme_color_override("font_hover_color", Color.WHITE)
	start_button.add_theme_color_override("font_shadow_color", Color("101e33"))
	start_button.add_theme_constant_override("shadow_offset_y", 2)
	start_button.pressed.connect(request_start)
	stage.add_child(start_button)
	var left := _picture("a770ab71cb367134.png", start_button, Rect2())
	left.name = "LeftArrow"
	var right := _picture("a770ab71cb367134.png", start_button, Rect2())
	right.name = "RightArrow"
	right.flip_h = true
	version_label.text = "v" + str(ProjectSettings.get_setting("application/config/version", "0.1.0"))
	version_label.add_theme_color_override("font_color", Color("a8b3ca"))
	version_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(version_label)
	error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error_label.add_theme_color_override("font_color", Color("ffd9a6"))
	error_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(error_label)
	stage.resized.connect(_layout)
	_layout()

func _picture(filename: String, parent: Node, rect: Rect2) -> TextureRect:
	var picture := TextureRect.new()
	picture.texture = load(ART + filename)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_SCALE
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.position = rect.position
	picture.size = rect.size
	parent.add_child(picture)
	return picture

func request_start() -> void:
	if _starting or not visible: return
	_starting = true
	start_button.disabled = true
	start_requested.emit()

func show_error(message: String) -> void:
	_starting = false
	start_button.disabled = false
	start_button.text = "重新加载"
	error_label.text = message
	show()

func _layout() -> void:
	var dimensions := stage.size
	var scale_factor := maxf(dimensions.x / 2048.0, dimensions.y / 1024.0)
	scenery.size = Vector2(2048, 1024)
	scenery.scale = Vector2.ONE * scale_factor
	scenery.position = (dimensions - scenery.size * scale_factor) * 0.5
	var compact := dimensions.y < 600.0
	logo.size = Vector2(650, 186) if not compact else Vector2(390, 112)
	logo.size.x = minf(logo.size.x, dimensions.x - 48.0)
	logo.position = Vector2((dimensions.x - logo.size.x) * 0.5, dimensions.y * 0.14)
	start_button.size = Vector2(440, 72) if not compact else Vector2(310, 52)
	start_button.size.x = minf(start_button.size.x, dimensions.x - 48.0)
	start_button.position = Vector2((dimensions.x - start_button.size.x) * 0.5, dimensions.y * (0.72 if compact else 0.76))
	start_button.add_theme_font_size_override("font_size", 32 if not compact else 24)
	for child_name in ["LeftArrow", "RightArrow"]:
		var arrow := start_button.get_node(child_name) as TextureRect
		arrow.size = Vector2.ONE * (36.0 if not compact else 28.0)
		arrow.position = Vector2(34 if child_name == "LeftArrow" else start_button.size.x - arrow.size.x - 34, (start_button.size.y - arrow.size.y) * 0.5)
	version_label.add_theme_font_size_override("font_size", 16 if not compact else 13)
	version_label.position = Vector2(24, dimensions.y - 38)
	version_label.size = Vector2(140, 24)
	error_label.add_theme_font_size_override("font_size", 18 if not compact else 14)
	error_label.position = Vector2(24, start_button.position.y + start_button.size.y + 8)
	error_label.size = Vector2(dimensions.x - 48, 48)

func _process(delta: float) -> void:
	if not visible: return
	_elapsed += delta
	for index in _trees.size():
		var tree := _trees[index]
		tree.pivot_offset = Vector2(tree.size.x * 0.5, tree.size.y)
		tree.rotation = sin(_elapsed * 0.55 + index * 1.7) * 0.003

func _unhandled_input(event: InputEvent) -> void:
	if not visible or _starting: return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		request_start()
		get_viewport().set_input_as_handled()
