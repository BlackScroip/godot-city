class_name DungeonRouteNode
extends Button

var room: Dictionary = {}
var available := false
var chosen := false:
	set(value):
		if chosen == value: return
		chosen = value
		if is_node_ready(): _animate_selection()
		queue_redraw()
var visited := false
var portrait: Texture2D
const GOLD = Color("dcc58b")
const ROOM_CONTENT_SCALE = 0.94
# Align the bright outer stroke, excluding the sprite's transparent glow padding.
const ROOM_OUTLINE_UV = Rect2(21.0 / 331.0, 21.0 / 190.0, 289.0 / 331.0, 148.0 / 190.0)
const SELECTED_FRAME_SIZE = Vector2(ROOM_CONTENT_SCALE / ROOM_OUTLINE_UV.size.x, ROOM_CONTENT_SCALE / ROOM_OUTLINE_UV.size.y)
const SELECTION_PEAK_SCALE = 1.055
const WORLD_SELECTED_FRAME_SCALE = 1.12
const BADGE_ART = "res://assets/ui/route/badges/"
const BADGE_IDS = {"gold": "70001", "magic": "70002", "mineral": "10000", "partner": "13006", "spirit": "13008"}
const BADGE_ICON_SIZES = {"gold": Vector2(1, 55.0 / 60), "magic": Vector2(1, 55.0 / 60), "mineral": Vector2(46.0 / 60, 55.0 / 60), "partner": Vector2(54.0 / 60, 55.0 / 60), "spirit": Vector2(44.0 / 60, 57.5 / 60)}
var _selection_scale := 1.0:
	set(value):
		_selection_scale = value
		queue_redraw()
var _reveal_scale := 1.0:
	set(value):
		_reveal_scale = value
		queue_redraw()
var _reveal_offset := 0.0:
	set(value):
		_reveal_offset = value
		queue_redraw()
var _badge_alpha := 1.0:
	set(value):
		_badge_alpha = value
		queue_redraw()
var _selection_tween: Tween
var _reveal_tween: Tween
static var icons: Array[AtlasTexture] = []

func _ready() -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if not disabled else Control.CURSOR_ARROW
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	tooltip_text = str(room.get("name", ""))
	if not str(room.get("lock_reason", "")).is_empty(): tooltip_text += "\n" + str(room.lock_reason)
	if room.get("vertical", false): tooltip_text += "（换路消耗 %d 点刻印圣典）" % int(room.get("shift_cost", 1))
	if not available and portrait == null and not room.get("selectable", false): tooltip_text += "（已通过）" if visited else "（后续路线）"
	resized.connect(queue_redraw)
	visibility_changed.connect(_animate_selection)
	if chosen: _animate_selection()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED: queue_redraw()

func _animate_selection() -> void:
	if _selection_tween: _selection_tween.kill()
	_selection_scale = 1.0
	if not chosen or not is_visible_in_tree(): return
	_selection_tween = create_tween()
	_selection_tween.tween_property(self, "_selection_scale", SELECTION_PEAK_SCALE, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_selection_tween.tween_property(self, "_selection_scale", 1.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_selection_tween.finished.connect(_pulse_selection)

func _pulse_selection() -> void:
	if not chosen or not is_visible_in_tree(): return
	_selection_tween = create_tween().set_loops()
	_selection_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_selection_tween.tween_property(self, "_selection_scale", SELECTION_PEAK_SCALE, 0.5)
	_selection_tween.tween_property(self, "_selection_scale", 1.0, 0.5)

func prepare_reveal() -> void:
	modulate.a = 0.0
	_reveal_scale = 0.86
	_reveal_offset = -0.12
	_badge_alpha = 0.0

func reveal(delay: float) -> void:
	if _reveal_tween: _reveal_tween.kill()
	_reveal_tween = create_tween().set_parallel()
	_reveal_tween.tween_property(self, "modulate:a", 1.0, 0.333).set_delay(delay)
	_reveal_tween.tween_property(self, "_reveal_scale", 1.0, 0.45).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_reveal_tween.tween_property(self, "_reveal_offset", 0.0, 0.333).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_reveal_tween.tween_property(self, "_reveal_offset", 0.04, 0.017).from(0.0).set_delay(delay + 0.333)
	_reveal_tween.tween_property(self, "_reveal_offset", 0.0, 0.1).from(0.04).set_delay(delay + 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_reveal_tween.tween_property(self, "_badge_alpha", 1.0, 0.167).set_delay(delay + 0.833)

func _reveal_transform() -> Transform2D:
	return Transform2D(0, Vector2.ONE * _reveal_scale, 0, size * (1.0 - _reveal_scale) * 0.5 + Vector2(0, size.y * _reveal_offset))

func _selected_frame_rect(at_scale: float = -1.0) -> Rect2:
	var frame_scale = at_scale if at_scale >= 0 else _selection_scale if chosen else 1.0
	if room.get("map_mode", "rooms") == "world":
		var base = _world_frame_rect()
		var dimensions = base.size * WORLD_SELECTED_FRAME_SCALE * frame_scale
		return Rect2(base.get_center() - dimensions * 0.5, dimensions)
	var dimensions = size * SELECTED_FRAME_SIZE * frame_scale
	return Rect2(size * 0.5 - (ROOM_OUTLINE_UV.position + ROOM_OUTLINE_UV.size * 0.5) * dimensions, dimensions)

func _selection_outline_rect() -> Rect2:
	var frame = _selected_frame_rect()
	if room.get("map_mode", "rooms") == "world": return frame
	return Rect2(frame.position + frame.size * ROOM_OUTLINE_UV.position, frame.size * ROOM_OUTLINE_UV.size)

func selection_bounds(peak := true) -> Rect2:
	var bounds = Rect2(Vector2.ZERO, size).merge(_selected_frame_rect(SELECTION_PEAK_SCALE if peak else -1.0))
	if room.get("map_mode", "rooms") != "world":
		for badge in _badge_rects(): bounds = bounds.merge(badge)
	if room.get("current", false) and size.y >= 60: bounds = bounds.merge(Rect2(Vector2(0, size.y + 2), Vector2(size.x, 20)))
	return bounds

func _world_frame_rect() -> Rect2:
	var radius = maxf(14, minf(size.x * 0.44, (size.y - 24) * 0.5))
	return Rect2(Vector2(size.x * 0.5 - radius, 3), Vector2.ONE * radius * 2)

func _room_rect() -> Rect2:
	var dimensions = size * ROOM_CONTENT_SCALE
	return Rect2((size - dimensions) * 0.5, dimensions)

func _draw() -> void:
	draw_set_transform_matrix(_reveal_transform())
	if room.get("map_mode", "rooms") != "world":
		_draw_room()
		return
	var frame_rect = _world_frame_rect()
	var radius = frame_rect.size.x * 0.5
	var center = frame_rect.get_center()
	var locked = bool(room.get("locked", false))
	var unknown = bool(room.get("unknown", false))
	var tint = Color("e64d36") if locked else GOLD
	var diamond = PackedVector2Array([center + Vector2(0, -radius), center + Vector2(radius, 0), center + Vector2(0, radius), center + Vector2(-radius, 0)])
	var frame = DungeonStyle.texture("res://assets/ui/route/world_node_frame_active.png" if chosen else "res://assets/ui/route/world_node_frame.png")
	if frame: draw_texture_rect(frame, _selected_frame_rect() if chosen else frame_rect, false, Color.WHITE if chosen else Color(1, 1, 1, 0.45))
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
	var caption = DungeonLocale.text("未知领域" if unknown else str(room.get("name", "")))
	var font_size = 13 if size.y < 90 else 17
	var font := get_theme_font("font")
	while font_size > 9 and font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > size.x:
		font_size -= 1
	if font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > size.x:
		while not caption.is_empty() and font.get_string_size(caption + "...", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > size.x:
			caption = caption.left(-1)
		caption += "..."
	var baseline = minf(size.y - 2, radius * 2 + font_size + 5)
	draw_string_outline(font, Vector2(0, baseline), caption, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, 3, Color("17201b"))
	draw_string(font, Vector2(0, baseline), caption, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, Color("fff4d7"))
	if visited and portrait == null:
		draw_polyline(PackedVector2Array([center + Vector2(radius - 16, 0), center + Vector2(radius - 10, 6), center + Vector2(radius + 1, -6)]), Color("d7f29b"), 3, true)

func _world_artwork() -> Texture2D:
	var names = {"森林图标": "forest", "沙漠图标": "desert", "雪山图标": "snow", "矿场图标": "mine", "封魔图标": "seal", "海岛图标": "island", "熔岩图标": "lava", "未知图标": "unknown"}
	return DungeonStyle.texture("res://assets/ui/route/world_" + str(names.get(str(room.get("world_icon", "")), "camp")) + ".png")

func _draw_room() -> void:
	var inner = _room_rect()
	var state = "node_current" if available or visited else "room_available" if portrait else "node_2"
	var frame = DungeonStyle.texture("res://assets/ui/route/" + state + ".png")
	if frame: draw_texture_rect(frame, inner, false)
	var art = portrait if portrait else _artwork()
	if art:
		var side = inner.size.y * 0.9
		draw_texture_rect(art, Rect2((size - Vector2.ONE * side) * 0.5, Vector2.ONE * side), false)
	if chosen or (available and (is_hovered() or has_focus())):
		var selected = DungeonStyle.texture("res://assets/ui/route/node_selected_frame.png")
		if selected: draw_texture_rect(selected, _selected_frame_rect(), false)
	_badges()

func _frame(fill: Color, border: Color, width: int) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(4)
	return style

func _artwork() -> Texture2D:
	if bool(room.get("is_hidden", false)): return DungeonStyle.texture("res://assets/ui/route/room_unknown.png")
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

func _badges() -> void:
	var types := _badge_types()
	var areas := _badge_rects()
	var frame = DungeonStyle.texture(BADGE_ART + "frame.png")
	var tint = Color(1, 1, 1, _badge_alpha)
	for index in types.size():
		var area = areas[index]
		if frame: draw_texture_rect(frame, area, false, tint)
		var icon = DungeonStyle.texture(BADGE_ART + types[index] + ".png")
		if icon:
			var dimensions = area.size * BADGE_ICON_SIZES[types[index]]
			var offset = Vector2(0, -area.size.y * (1.25 if types[index] == "spirit" else 2.5) / 60.0)
			draw_texture_rect(icon, Rect2(area.get_center() + offset - dimensions * 0.5, dimensions), false, tint)

func _badge_rects() -> Array[Rect2]:
	var result: Array[Rect2] = []
	var count = _badge_types().size()
	var inner = _room_rect()
	var diameter = clampf(inner.size.y * 0.44, 18, 56)
	for index in count:
		var upper = index >= 2
		var row_count = count - 2 if upper else mini(count, 2)
		var column = index - 2 if upper else index
		var x = inner.get_center().x if row_count == 1 else lerpf(inner.position.x + diameter * 0.12, inner.end.x - diameter * 0.12, float(column) / (row_count - 1))
		var y = inner.position.y + diameter * 0.12 if upper else inner.end.y - diameter * 0.12
		result.append(Rect2(Vector2(x, y) - Vector2.ONE * diameter * 0.5, Vector2.ONE * diameter))
	return result

func _badge_types() -> Array[String]:
	var types: Array[String] = []
	if bool(room.get("is_hidden", false)): return types
	var rewards: Dictionary = room.get("NodeIncrementData", {})
	for kind in BADGE_IDS:
		var id: String = BADGE_IDS[kind]
		if rewards.has(id) or rewards.has(int(id)): types.append(kind)
	return types
