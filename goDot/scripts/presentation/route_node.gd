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
	if not str(room.get("lock_reason", "")).is_empty(): tooltip_text += "\n" + str(room.lock_reason)
	if room.get("vertical", false): tooltip_text += "（换路消耗 %d 点刻印圣典）" % int(room.get("shift_cost", 1))
	if not available and portrait == null: tooltip_text += "（已通过）" if visited else "（后续路线）"
	resized.connect(queue_redraw)

func _draw() -> void:
	if room.get("map_mode", "rooms") != "world":
		_draw_room()
		return
	var radius = maxf(14, minf(size.x * 0.44, (size.y - 24) * 0.5))
	var center = Vector2(size.x * 0.5, radius + 3)
	var locked = bool(room.get("locked", false))
	var unknown = bool(room.get("unknown", false))
	var tint = Color("e64d36") if locked else GOLD
	var diamond = PackedVector2Array([center + Vector2(0, -radius), center + Vector2(radius, 0), center + Vector2(0, radius), center + Vector2(-radius, 0)])
	var frame = DungeonStyle.texture("res://assets/ui/route/world_node_frame_active.png" if chosen else "res://assets/ui/route/world_node_frame.png")
	if frame: draw_texture_rect(frame, Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2), false, Color.WHITE if chosen else Color(1, 1, 1, 0.45))
	else:
		draw_colored_polygon(diamond, Color(0.08, 0.09, 0.06, 0.42))
		diamond.append(diamond[0])
		draw_polyline(diamond, tint if chosen else Color(tint, 0.38), 3 if chosen else 1.5, true)
	if available and (is_hovered() or has_focus()): draw_polyline(diamond, Color("fff0b3"), 3, true)
	var art = portrait if portrait else _world_artwork()
	if unknown and art == null:
		draw_string(get_theme_font("font"), center + Vector2(-radius * 0.32, radius * 0.42), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, int(radius * 1.5), GOLD)
	elif art:
		var side = radius * 1.5
		draw_texture_rect(art, Rect2(center - Vector2.ONE * side * 0.5, Vector2.ONE * side), false, Color("ed6752") if locked else Color.WHITE)
	if locked:
		var lock_art = DungeonStyle.texture("res://assets/ui/route/world_lock.png")
		if lock_art: draw_texture_rect(lock_art, Rect2(center - Vector2(radius * 0.25, radius * 0.32), Vector2(radius * 0.5, radius * 0.64)), false, Color("cb0000"))
	var caption = "未知领域" if unknown else str(room.get("name", ""))
	var font_size = 13 if size.y < 90 else 17
	var baseline = minf(size.y - 2, radius * 2 + font_size + 5)
	draw_string_outline(get_theme_font("font"), Vector2(0, baseline), caption, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, 3, Color("17201b"))
	draw_string(get_theme_font("font"), Vector2(0, baseline), caption, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, Color("fff4d7"))
	if visited and portrait == null:
		draw_polyline(PackedVector2Array([center + Vector2(radius - 16, 0), center + Vector2(radius - 10, 6), center + Vector2(radius + 1, -6)]), Color("d7f29b"), 3, true)
	if chosen:
		var x = size.x * 0.5
		draw_colored_polygon(PackedVector2Array([Vector2(x - 6, 1), Vector2(x, 7), Vector2(x + 6, 1)]), Color("ffe9a0"))

func _world_artwork() -> Texture2D:
	var names = {"森林图标": "forest", "沙漠图标": "desert", "雪山图标": "snow", "矿场图标": "mine", "封魔图标": "seal", "海岛图标": "island", "熔岩图标": "lava", "未知图标": "unknown"}
	return DungeonStyle.texture("res://assets/ui/route/world_" + str(names.get(str(room.get("world_icon", "")), "camp")) + ".png")

func _draw_room() -> void:
	var state = "node_current" if available or visited else "room_available" if portrait else "node_2"
	var frame = DungeonStyle.texture("res://assets/ui/route/" + state + ".png")
	if frame: draw_texture_rect(frame, Rect2(Vector2.ZERO, size), false)
	var art = portrait if portrait else _artwork()
	if art:
		var side = size.y * 0.9
		draw_texture_rect(art, Rect2((size - Vector2.ONE * side) * 0.5, Vector2.ONE * side), false)
	_badges()
	if chosen or (available and (is_hovered() or has_focus())):
		var selected = DungeonStyle.texture("res://assets/ui/route/node_selected_frame.png")
		if selected: draw_texture_rect(selected, Rect2(Vector2(-3, -3), size + Vector2(6, 6)), false)

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
