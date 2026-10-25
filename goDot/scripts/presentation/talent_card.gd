extends PanelContainer

var selected := false:
	set(value):
		selected = value
		queue_redraw()
var compact := false

func _ready() -> void:
	resized.connect(queue_redraw)

func fit(is_compact: bool) -> void:
	compact = is_compact
	var inset = StyleBoxEmpty.new()
	inset.content_margin_left = 14 if compact else 24
	inset.content_margin_right = 14 if compact else 24
	inset.content_margin_top = 16 if compact else 42
	inset.content_margin_bottom = 14 if compact else 36
	add_theme_stylebox_override("panel", inset)
	queue_redraw()

func _outline(inset: float) -> PackedVector2Array:
	var points = PackedVector2Array()
	var arch = 22.0 if compact else 40.0
	for i in 25:
		var t = i / 24.0
		points.append(Vector2(inset + (size.x - inset * 2) * t, inset + arch * pow(absf(t * 2 - 1), 1.6)))
	for i in 25:
		var t = i / 24.0
		points.append(Vector2(size.x - inset - (size.x - inset * 2) * t, size.y - inset - arch * pow(absf(t * 2 - 1), 1.6)))
	points.append(points[0])
	return points

func _draw() -> void:
	if size.x < 24 or size.y < 80: return
	var edge = _outline(7)
	if selected:
		for width in [28.0, 18.0, 10.0]:
			draw_polyline(edge, Color(0.45, 0.78, 1.0, 0.07), width, true)
	draw_colored_polygon(edge, Color("c4e4f3") if selected else Color("b4d8e9"))
	draw_polyline(edge, Color("f4d887") if selected else Color("bca568"), 3, true)
	draw_polyline(_outline(12), Color(0.95, 0.91, 0.69, 0.58), 1, true)
	var corner = DungeonStyle.texture("gold_corner")
	if corner:
		var extent = 26.0 if compact else 38.0
		for origin in [Vector2(9, 24 if compact else 42), Vector2(size.x - 9, 24 if compact else 42), Vector2(9, size.y - (24 if compact else 42)), Vector2(size.x - 9, size.y - (24 if compact else 42))]:
			var direction = Vector2(1 if origin.x < size.x * 0.5 else -1, 1 if origin.y < size.y * 0.5 else -1)
			draw_set_transform(origin, 0, direction)
			draw_texture_rect(corner, Rect2(Vector2.ZERO, Vector2.ONE * extent), false, Color("fff0bd"))
			draw_set_transform(Vector2.ZERO)
