extends PanelContainer

const Palette = preload("res://scripts/presentation/choice_palette.gd")

var selected := false:
	set(value):
		selected = value
		queue_redraw()
var compact := false
var art_scale := 1.0
var background: Texture2D
var separator: Texture2D
var background_key := ""
var dividers := PackedFloat32Array()
var _pressed := false

func _ready() -> void:
	resized.connect(queue_redraw)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(func():
		_pressed = false
		queue_redraw())
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)

func configure(rare: int, loot_type: Variant = "") -> void:
	background_key = Palette.sprite_key("rarebg_vertical", rare, loot_type)
	background = Palette.texture(background_key)
	separator = Palette.texture(Palette.sprite_key("rarebg_vertical_line", rare, loot_type))

func fit(is_compact: bool, scale_factor := 1.0) -> void:
	compact = is_compact
	art_scale = scale_factor
	var inset = StyleBoxEmpty.new()
	inset.content_margin_left = maxf(13, 30 * art_scale)
	inset.content_margin_right = maxf(13, 30 * art_scale)
	inset.content_margin_top = maxf(30, 96 * art_scale)
	inset.content_margin_bottom = maxf(24, 78 * art_scale)
	add_theme_stylebox_override("panel", inset)
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_pressed = event.pressed
		queue_redraw()

func background_color() -> Color:
	var state := "m_NormalColor"
	if _pressed: state = "m_PressedColor"
	elif selected or has_focus(): state = "m_SelectedColor"
	elif Rect2(Vector2.ZERO, size).has_point(get_local_mouse_position()): state = "m_HighlightedColor"
	return Palette.color("background_tint") * Palette.button_color(state)

func _draw() -> void:
	if size.x < 24 or size.y < 80 or not background: return
	draw_texture_rect(background, Rect2(Vector2.ZERO, size), false, background_color())
	if not separator: return
	var width = size.x - 36 * art_scale
	var height = width * separator.get_height() / separator.get_width()
	for y in dividers:
		draw_texture_rect(separator, Rect2(18 * art_scale, y - height * 0.5, width, height), false)
