extends RefCounted

# Inner edge of the bright outline in the recovered 68x68 selection sprite.
const INNER_RECT := Rect2(8, 9, 52, 51)
const SOURCE_SIZE := Vector2(68, 68)

static func place(frame: Control, target_size: Vector2) -> void:
	var factor := Vector2(target_size.x / INNER_RECT.size.x, target_size.y / INNER_RECT.size.y)
	frame.position = -INNER_RECT.position * factor
	frame.size = SOURCE_SIZE * factor
