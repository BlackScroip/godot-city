extends Control

var hp_fraction := 1.0
var charge_fraction := 0.0

func _draw() -> void:
	var edge = PackedVector2Array([Vector2(0, 62), Vector2(10, 52), Vector2(234, 52), Vector2(244, 62), Vector2(234, 72), Vector2(10, 72)])
	draw_colored_polygon(edge, Color("333632"))
	if hp_fraction > 0:
		var end = 9 + 225 * clampf(hp_fraction, 0, 1)
		draw_colored_polygon(PackedVector2Array([Vector2(4, 62), Vector2(12, 55), Vector2(end, 55), Vector2(end, 69), Vector2(12, 69)]), Color("62b934"))
	edge.append(edge[0])
	draw_polyline(edge, Color("e4e2d2"), 2, true)
	draw_line(Vector2(0, 38), Vector2(244, 38), Color("dc8027"), 2, true)
	var marker := DungeonStyle.texture("hud_charge_marker")
	for x in [0.0, 122.0, 244.0]:
		if marker: draw_texture_rect(marker, Rect2(Vector2(x - 6, 32), Vector2(12, 12)), false, Color("ffc35c"))
	for i in 5:
		var x = 18 + i * 46
		var filled = charge_fraction >= (i + 1) / 5.0
		if filled:
			draw_colored_polygon(PackedVector2Array([Vector2(x - 8, 35), Vector2(x - 13, 19), Vector2(x, 27), Vector2(x + 8, 5), Vector2(x + 12, 24), Vector2(x + 29, 17), Vector2(x + 25, 35)]), Color("d94418"))
			draw_line(Vector2(x - 2, 24), Vector2(x + 25, 24), Color(1, 0.47, 0.05, 0.4), 16, true)
		draw_line(Vector2(x - 2, 24), Vector2(x + 25, 24), Color("ffdc62") if filled else Color("67543e"), 8, true)
