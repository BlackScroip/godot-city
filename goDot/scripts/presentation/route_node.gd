class_name DungeonRouteNode
extends Button

var room: Dictionary = {}
var available := false
var chosen := false
var visited := false
var portrait: Texture2D
const GOLD = Color("dcc58b")
static var icons: Array[AtlasTexture] = []

func _ready() -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if available else Control.CURSOR_ARROW
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	tooltip_text = str(room.get("name", ""))
	if room.get("vertical", false): tooltip_text += "（换路消耗 %d 点刻印圣典）" % int(room.get("shift_cost", 1))
	if not available and portrait == null: tooltip_text += "（已通过）" if visited else "（后续路线）"
	resized.connect(queue_redraw)

func _draw() -> void:
	var frame = Rect2(Vector2(5, 5), size - Vector2(10, 10))
	var lit = available or portrait != null or visited
	var fill = Color("e7d69c") if lit else Color(0.08, 0.065, 0.045, 0.91)
	if chosen: fill = Color("fff0b3")
	if chosen or (available and (is_hovered() or has_focus())):
		for width in [14.0, 9.0, 5.0]:
			draw_style_box(_frame(Color(1, 0.84, 0.37, 0.045), Color(1, 0.85, 0.39, 0.09), int(width)), frame.grow(width * 0.45))
	draw_style_box(_frame(fill, GOLD, 2), frame)
	draw_style_box(_frame(Color.TRANSPARENT, Color("927c50"), 1), frame.grow(-4))
	draw_line(frame.position + Vector2(9, 3), Vector2(frame.end.x - 9, frame.position.y + 3), Color(1, 0.94, 0.7, 0.38), 1, true)
	if portrait:
		var side = minf(size.y - 12, size.x * 0.65)
		draw_texture_rect(portrait, Rect2((size - Vector2.ONE * side) * 0.5, Vector2.ONE * side), false)
	else:
		var art = _artwork()
		if art:
			var side = size.y * 1.04
			draw_texture_rect(art, Rect2((size - Vector2.ONE * side) * 0.5, Vector2.ONE * side), false)
		_badges()
	if visited and portrait == null:
		draw_polyline(PackedVector2Array([Vector2(size.x - 29, 17), Vector2(size.x - 23, 23), Vector2(size.x - 12, 11)]), Color("527841"), 3, true)
	if chosen:
		var x = size.x * 0.5
		draw_colored_polygon(PackedVector2Array([Vector2(x - 8, size.y + 12), Vector2(x, size.y + 21), Vector2(x + 8, size.y + 12), Vector2(x, size.y + 15)]), Color("ffe9a0"))

func _frame(fill: Color, border: Color, width: int) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(4)
	return style

func _artwork() -> Texture2D:
	if icons.is_empty():
		var atlas = DungeonStyle.texture("res://assets/art_generated/route-icons-v2.png")
		if not atlas: return null
		var cell = Vector2(atlas.get_width() / 4.0, atlas.get_height() / 2.0)
		for index in 8:
			var icon = AtlasTexture.new()
			icon.atlas = atlas
			icon.region = Rect2(Vector2(index % 4, index / 4) * cell, cell)
			icons.append(icon)
	var index = {"Battle": 1 if room.get("EnemyClass", "") == "Elite" else 0, "Entrance": 2, "Treasure": 2, "Event": 3, "Shop": 4, "Rest": 5, "Curse": 6, "Boss": 7}.get(str(room.get("flow", "Battle")), 2)
	return icons[int(index)]

func _crystal(center: Vector2, color: Color, height: float) -> void:
	var points = PackedVector2Array([center + Vector2(0, -height), center + Vector2(height * 0.6, 0), center + Vector2(0, height * 0.6), center + Vector2(-height * 0.6, 0)])
	draw_colored_polygon(points, color.darkened(0.3))
	draw_colored_polygon(PackedVector2Array([points[0], points[1], points[2], center]), color)
	draw_line(points[0], center, color.lightened(0.6), 2, true)

func _badges() -> void:
	var rewards = str(room.get("IncrementOptions", ""))
	var types: Array[String] = []
	if "MagicpointLode" in rewards: types.append("magic")
	if "CollectingMaterials" in rewards: types.append("mineral")
	if "GoldLode" in rewards: types.append("gold")
	if "SpritesAltar" in rewards: types.append("spirit")
	for index in mini(types.size(), 3):
		var radius = clampf(size.y * 0.15, 5, 16)
		var point = Vector2(radius if index < 2 else size.x - radius, radius * 0.7 if index == 0 else size.y - radius * 0.7)
		draw_circle(point, radius, Color("554633"))
		draw_arc(point, radius, 0, TAU, 32, Color("c6b99a"), 1.5, true)
		draw_set_transform(point, 0, Vector2.ONE)
		_crystal(Vector2.ZERO, {"magic": Color("ad93ed"), "mineral": Color("80cee9"), "gold": Color("ebd16e"), "spirit": Color("73d5ac")}[types[index]], radius * 0.66)
		draw_set_transform(Vector2.ZERO)
