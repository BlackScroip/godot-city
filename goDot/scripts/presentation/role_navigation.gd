extends RefCounted

const DESIGN := Vector2(2048, 900)
const BACK_RECT := Rect2(20, 14, 120, 100)
const BACK_TEXTURE = preload("res://assets/ui/role_character/panel/_____395376c50f.png")
const MINIMUM_TOUCH_SIZE := 44.0

static func scale_factor(view_size: Vector2) -> float:
	return minf(view_size.x / DESIGN.x, view_size.y / DESIGN.y)

static func header_margin(view_size: Vector2) -> Vector2:
	return (BACK_RECT.position * scale_factor(view_size)).max(Vector2(12, 8)).ceil()

static func header_button_size(view_size: Vector2) -> Vector2:
	return (BACK_RECT.size * scale_factor(view_size)).max(Vector2.ONE * MINIMUM_TOUCH_SIZE).ceil()

static func create_back_button(hint := "返回") -> Button:
	var button := Button.new()
	button.name = "RoleBackButton"
	button.tooltip_text = hint
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.set_meta("camp_back_navigation", true)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	var arrow := TextureRect.new()
	arrow.name = "Arrow"
	arrow.texture = BACK_TEXTURE
	arrow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	arrow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(arrow)
	arrow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.position = BACK_RECT.position
	button.size = BACK_RECT.size
	return button

static func create_header_back_button(view_size: Vector2, hint := "返回") -> Button:
	var button := create_back_button(hint)
	configure_header_back_button(button, view_size, hint)
	return button

static func configure_header_back_button(button: Button, view_size: Vector2, hint := "返回") -> void:
	button.tooltip_text = hint
	button.custom_minimum_size = header_button_size(view_size)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

static func place_back_button(button: Button, factor := 1.0) -> void:
	var parent_scale := Vector2.ONE
	if button.get_parent() is CanvasItem: parent_scale = button.get_parent().get_global_transform().get_scale().abs()
	parent_scale = parent_scale.max(Vector2.ONE * 0.001)
	button.position = (BACK_RECT.position * factor).max(Vector2(12, 8) / parent_scale)
	button.size = (BACK_RECT.size * factor).max(Vector2.ONE * MINIMUM_TOUCH_SIZE / parent_scale)
