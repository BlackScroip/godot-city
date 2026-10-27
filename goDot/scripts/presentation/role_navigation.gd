extends RefCounted

const DESIGN := Vector2(2048, 900)
const BACK_RECT := Rect2(20, 14, 120, 100)
const BACK_TEXTURE = preload("res://assets/ui/role_character/panel/_____395376c50f.png")

static func scale_factor(view_size: Vector2) -> float:
	return minf(view_size.x / DESIGN.x, view_size.y / DESIGN.y)

static func create_back_button(hint := "返回") -> Button:
	var button := Button.new()
	button.name = "RoleBackButton"
	button.tooltip_text = hint
	button.focus_mode = Control.FOCUS_NONE
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

static func place_back_button(button: Button, factor := 1.0) -> void:
	button.position = BACK_RECT.position * factor
	button.size = BACK_RECT.size * factor
