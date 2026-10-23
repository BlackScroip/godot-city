extends PanelContainer

var highlighted := false
var accent := Color("e2c97c")
var compact := false

func _ready() -> void:
	apply_spacing()
	mouse_entered.connect(func(): highlighted = true; queue_redraw())
	mouse_exited.connect(func(): highlighted = false; queue_redraw())
	resized.connect(queue_redraw)

func apply_spacing() -> void:
	var inset = StyleBoxEmpty.new()
	inset.content_margin_left = 22
	inset.content_margin_right = 22
	inset.content_margin_top = 12 if compact else 50
	inset.content_margin_bottom = 12 if compact else 45
	if compact:
		inset.content_margin_left = 12
		inset.content_margin_right = 12
	add_theme_stylebox_override("panel", inset)
	queue_redraw()

func _draw() -> void:
	var w = size.x
	var h = size.y
	var arch = 14.0 if compact else 56.0
	var outline = PackedVector2Array()
	for i in 25:
		var t = i / 24.0
		outline.append(Vector2(5 + (w - 10) * t, 7 + arch * pow(absf(t * 2 - 1), 1.7)))
	for i in 25:
		var t = i / 24.0
		outline.append(Vector2(w - 5 - (w - 10) * t, h - 7 - arch * pow(absf(t * 2 - 1), 1.7)))
	draw_colored_polygon(outline, Color("b6dcf0") if not highlighted else Color("ccecff"))
	outline.append(outline[0])
	draw_polyline(outline, accent, 4, true)
	if compact: return
	for y in [76.0, h - 76]:
		draw_line(Vector2(20, y), Vector2(w - 20, y), Color(0.55, 0.76, 0.85, 0.5), 2, true)
		var center = Vector2(w * 0.5, y)
		draw_polyline(PackedVector2Array([center + Vector2(-6, 0), center + Vector2(0, -6), center + Vector2(6, 0), center + Vector2(0, 6), center + Vector2(-6, 0)]), Color("e4d69e"), 2, true)
	for x in [18.0, w - 18]:
		for y in [60.0, h - 60]:
			draw_arc(Vector2(x, y), 12, 0, TAU, 24, Color("e2c97c"), 2, true)
