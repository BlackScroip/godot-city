extends Control

var hp_fraction := 1.0
var charge_fraction := 0.0
var resource_segments := 5
var resource_id := "100300"
var _styles: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/battle_guide/jp_styles.json"))
var _resource_style: Dictionary = _styles.get(resource_id, {})

func bind_resource(id: String, fraction: float) -> void:
	if id == resource_id and charge_fraction == fraction: return
	resource_id = id
	_resource_style = _styles.get(id, {})
	resource_segments = maxi(1, int(_resource_style.get("slots", 5)))
	charge_fraction = clampf(fraction, 0, 1)
	queue_redraw()

func _draw_resource_part(part: Dictionary, center: Vector2) -> void:
	if part.is_empty(): return
	var art := DungeonStyle.texture(str(part.resource))
	if not art: return
	var dimensions := Vector2(float(part.size[0]), float(part.size[1])) * (244.0 / 316.0)
	var rgba: Array = part.get("color", [1, 1, 1, 1])
	draw_texture_rect(art, Rect2(center - dimensions * 0.5, dimensions), false, Color(rgba[0], rgba[1], rgba[2], rgba[3]))

func _draw() -> void:
	var edge = PackedVector2Array([Vector2(0, 62), Vector2(10, 52), Vector2(234, 52), Vector2(244, 62), Vector2(234, 72), Vector2(10, 72)])
	draw_colored_polygon(edge, Color("333632"))
	if hp_fraction > 0:
		var end = 9 + 225 * clampf(hp_fraction, 0, 1)
		draw_colored_polygon(PackedVector2Array([Vector2(4, 62), Vector2(12, 55), Vector2(end, 55), Vector2(end, 69), Vector2(12, 69)]), Color("62b934"))
	edge.append(edge[0])
	draw_polyline(edge, Color("e4e2d2"), 2, true)
	_draw_resource_part(_resource_style.get("line", {}), Vector2(122, 38))
	var marker: Dictionary = _resource_style.get("marker", {})
	for point in marker.get("positions", []):
		_draw_resource_part(marker, Vector2(122, 38) + Vector2(float(point[0]), -float(point[1])) * (244.0 / 316.0))
	var count := maxi(1, resource_segments)
	var filled_count := mini(count, int(floor(clampf(charge_fraction, 0, 1) * count + 0.00001)))
	for i in count:
		var center := Vector2((i + 0.5) * 244.0 / count, 23)
		var filled := i < filled_count
		_draw_resource_part(_resource_style.get("full" if filled else "empty", {}), center)
