extends PanelContainer

var selected := false:
	set(value):
		selected = value
		queue_redraw()
var compact := false
var art_scale := 1.0
var fill_top := Color("93d1f2")
var fill_bottom := Color("e5f2f5")
var accent := Color("639fc0")
var dividers := PackedFloat32Array()

func _ready() -> void:
	resized.connect(queue_redraw)
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)

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

func _top_edge(inset: float) -> PackedVector2Array:
	var width = size.x - inset * 2
	var cap = minf(width * 0.3, size.y * 0.13)
	var points = PackedVector2Array()
	for point in [Vector2(0, 1), Vector2(0, 0.76), Vector2(0.06, 0.76), Vector2(0.06, 0.57), Vector2(0.13, 0.57)]:
		points.append(Vector2(inset + point.x * width, inset + point.y * cap))
	var left = Vector2(inset + width * 0.13, inset + cap * 0.57)
	var middle = Vector2(size.x * 0.5, inset)
	for step in range(1, 19):
		points.append(left.bezier_interpolate(Vector2(inset + width * 0.24, inset + cap * 0.57), Vector2(inset + width * 0.32, inset), middle, step / 18.0))
	for step in range(1, 19):
		points.append(middle.bezier_interpolate(Vector2(inset + width * 0.68, inset), Vector2(inset + width * 0.76, inset + cap * 0.57), Vector2(inset + width * 0.87, inset + cap * 0.57), step / 18.0))
	for point in [Vector2(0.94, 0.57), Vector2(0.94, 0.76), Vector2(1, 0.76), Vector2(1, 1)]:
		points.append(Vector2(inset + point.x * width, inset + point.y * cap))
	return points

func _outline(inset: float) -> PackedVector2Array:
	var points = _top_edge(inset)
	var top = points.duplicate()
	for index in range(top.size() - 1, -1, -1): points.append(Vector2(top[index].x, size.y - top[index].y))
	points.append(points[0])
	return points

func _curve(points: Array, color: Color, width: float) -> void:
	var sampled = PackedVector2Array()
	for step in 25: sampled.append(points[0].bezier_interpolate(points[1], points[2], points[3], step / 24.0))
	draw_polyline(sampled, color, width, true)

func _ornament(origin: Vector2, flipped: bool) -> void:
	var extent = size.x * 0.21
	var color = fill_bottom.lightened(0.25)
	color.a = 0.8
	draw_set_transform(origin, 0, Vector2(1, -1 if flipped else 1))
	var diamond = PackedVector2Array([Vector2(0, -9), Vector2(5, 0), Vector2(0, 9), Vector2(-5, 0), Vector2(0, -9)])
	for index in diamond.size(): diamond[index] *= art_scale
	draw_polyline(diamond, color, maxf(1, 2 * art_scale), true)
	for direction in [-1, 1]:
		var end = extent * direction
		_curve([Vector2(0, 4 * art_scale), Vector2(end * 0.48, -25 * art_scale), Vector2(end, -10 * art_scale), Vector2(end, 7 * art_scale)], color, maxf(1, 2 * art_scale))
		_curve([Vector2(end, 7 * art_scale), Vector2(end * 0.9, 21 * art_scale), Vector2(end * 0.55, 14 * art_scale), Vector2(end * 0.71, 4 * art_scale)], color, maxf(1, 2 * art_scale))
		_curve([Vector2(0, 9 * art_scale), Vector2(end * 0.2, 26 * art_scale), Vector2(end * 0.62, 29 * art_scale), Vector2(end * 0.52, 11 * art_scale)], color, maxf(1, 2 * art_scale))
	draw_set_transform(Vector2.ZERO)

func _draw() -> void:
	if size.x < 24 or size.y < 80: return
	var edge = _outline(maxf(3, 7 * art_scale))
	var active = selected or has_focus() or Rect2(Vector2.ZERO, size).has_point(get_local_mouse_position())
	if active:
		for width in [18.0, 10.0]: draw_polyline(edge, Color(1, 0.85, 0.42, 0.09), width * art_scale, true)
	var colors = PackedColorArray()
	for point in edge: colors.append(fill_top.lerp(fill_bottom, clampf(point.y / size.y, 0, 1)))
	draw_polygon(edge, colors)
	draw_polyline(edge, Color("f7e6a3") if active else Color("d7c078"), maxf(2, 5 * art_scale), true)
	draw_polyline(_outline(maxf(6, 13 * art_scale)), Color(1, 0.95, 0.73, 0.65), maxf(1, 2 * art_scale), true)
	_ornament(Vector2(size.x * 0.5, 58 * art_scale), false)
	_ornament(Vector2(size.x * 0.5, size.y - 58 * art_scale), true)
	var line_color = accent
	line_color.a = 0.38
	for y in dividers:
		draw_line(Vector2(18 * art_scale, y), Vector2(size.x - 18 * art_scale, y), line_color, maxf(1, 2 * art_scale), true)
		var center = Vector2(size.x * 0.5, y)
		var radius = maxf(3, 7 * art_scale)
		draw_polyline(PackedVector2Array([center + Vector2(-radius, 0), center + Vector2(0, -radius), center + Vector2(radius, 0), center + Vector2(0, radius), center + Vector2(-radius, 0)]), line_color, maxf(1, 2 * art_scale), true)
	var corner = DungeonStyle.texture("gold_corner")
	if corner:
		var extent = 36 * art_scale
		var y = minf(size.x * 0.3, size.y * 0.13)
		for origin in [Vector2(10 * art_scale, y), Vector2(size.x - 10 * art_scale, y), Vector2(10 * art_scale, size.y - y), Vector2(size.x - 10 * art_scale, size.y - y)]:
			draw_set_transform(origin, 0, Vector2(1 if origin.x < size.x * 0.5 else -1, 1 if origin.y < size.y * 0.5 else -1))
			draw_texture_rect(corner, Rect2(Vector2.ZERO, Vector2.ONE * extent), false, Color("f2df9c"))
		draw_set_transform(Vector2.ZERO)
