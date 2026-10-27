extends Range

static var _sources: Dictionary = {}
static var _art: Dictionary = {}

var source_kind := "boss"
var source_path := "HpStateBar"
var fraction := 1.0
var follow_fraction := 1.0
var overcap_fraction := 0.0
var _initialized := false
var _shake_elapsed := 1.0
var _shake_window := 0.0
var _shake_count := 0
var _fill_mask: Control
var _fill_content: Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	step = 0.0
	allow_greater = true
	_fill_mask = Control.new()
	_fill_mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill_mask.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	_fill_mask.show_behind_parent = true
	add_child(_fill_mask)
	_fill_mask.draw.connect(func(): draw_part(_fill_mask, "boss", "HpStateBar/Bar", Rect2(Vector2.ZERO, size), 1.0, false, true))
	_fill_content = Control.new()
	_fill_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill_mask.add_child(_fill_content)
	_fill_content.draw.connect(func():
		draw_part(_fill_content, "boss", "HpStateBar/Bar", Rect2(Vector2.ZERO, size))
		_draw_fills(_fill_content)
	)
	resized.connect(_refresh_draw)
	_refresh_draw()

func configure(kind: String, path: String) -> void:
	source_kind = kind
	source_path = path
	_refresh_draw()

func _uses_boss_mask() -> bool:
	return source_kind == "boss" and source_path == "HpStateBar"

func _refresh_draw() -> void:
	pivot_offset = size * 0.5
	if is_instance_valid(_fill_mask):
		_fill_mask.visible = _uses_boss_mask()
		_fill_mask.size = size
		_fill_content.size = size
		_fill_mask.queue_redraw()
		_fill_content.queue_redraw()
	queue_redraw()

func reset() -> void:
	_initialized = false
	_shake_elapsed = 1.0
	_shake_window = 0.0
	_shake_count = 0
	scale = Vector2.ONE

func update_health(current: float, maximum: float, delta: float) -> void:
	var elapsed := maxf(0.0, delta)
	max_value = maxf(1.0, maximum)
	value = maxf(0.0, current)
	var ratio := clampf(value / max_value, 0.0, 2.0)
	var next := minf(ratio, 1.0)
	var extra := maxf(0.0, ratio - 1.0)
	_shake_window += elapsed
	if _shake_window >= 1.0:
		_shake_window = 0.0
		_shake_count = 0
	if not _initialized:
		follow_fraction = next
	elif next < fraction or extra < overcap_fraction:
		if _shake_count < 3:
			_shake_elapsed = 0.0
			_shake_count += 1
	fraction = next
	overcap_fraction = extra
	_initialized = true
	# HpStateBar.Update lerps by 0.1 per rendered frame, including healing.
	if elapsed > 0.0:
		follow_fraction = lerpf(follow_fraction, fraction, 0.1)
		_shake_elapsed += elapsed
	var progress := clampf(_shake_elapsed / 0.12, 0.0, 1.0)
	scale = Vector2.ONE * (1.0 + 0.15 * sin(progress * PI * 8.0) * (1.0 - progress))
	_refresh_draw()

static func source(kind: String) -> Dictionary:
	if _sources.is_empty():
		_sources = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/enemy_health/styles.json"))
	return _sources.get(kind, {})

static func draw_part(canvas: CanvasItem, kind: String, path: String, rectangle: Rect2, amount: float = 1.0, crop: bool = false, mask: bool = false) -> void:
	if amount <= 0.0 or rectangle.size.x <= 0.0 or rectangle.size.y <= 0.0: return
	var key := kind + ":" + path + (":mask" if mask else "")
	if not _art.has(key):
		var data: Dictionary = source(kind).get("images", {}).get(path, {})
		if data.is_empty(): return
		var texture := DungeonStyle.texture(str(data.resource))
		if texture == null: return
		if kind == "boss" and path in ["HpStateBar", "HpStateBar/Bar"]:
			texture = _restore_sprite_rect(texture, data)
		if mask:
			var stencil := texture.get_image()
			stencil.convert(Image.FORMAT_RGBA8)
			# Unity UI Mask uses alpha as a stencil, without dimming child colors.
			for y in stencil.get_height():
				for x in stencil.get_width():
					stencil.set_pixel(x, y, Color.WHITE if stencil.get_pixel(x, y).a > 0.001 else Color.TRANSPARENT)
			texture = ImageTexture.create_from_image(stencil)
		var tint: Dictionary = data.color
		var style := StyleBoxTexture.new()
		style.texture = texture
		style.modulate_color = Color.WHITE if mask else Color(tint.r, tint.g, tint.b, tint.a)
		var border: Dictionary = data.border
		var factor := 1.0 if kind == "boss" else 0.5
		for pair in [[SIDE_LEFT, "x"], [SIDE_BOTTOM, "y"], [SIDE_RIGHT, "z"], [SIDE_TOP, "w"]]:
			style.set_texture_margin(pair[0], float(border[pair[1]]) * factor)
		_art[key] = style
	var art: StyleBoxTexture = _art[key]
	var filled := Rect2(rectangle.position, Vector2(rectangle.size.x * minf(1.0, amount), rectangle.size.y))
	if crop:
		var texture_size := art.texture.get_size()
		canvas.draw_texture_rect_region(art.texture, filled, Rect2(Vector2.ZERO, Vector2(texture_size.x * minf(1.0, amount), texture_size.y)), art.modulate_color)
	else:
		canvas.draw_style_box(art, filled)

static func _restore_sprite_rect(texture: Texture2D, data: Dictionary) -> Texture2D:
	var rect: Dictionary = data.get("rect", {})
	if rect.is_empty(): return texture
	var dimensions := Vector2i(roundi(float(rect.width)), roundi(float(rect.height)))
	if dimensions == Vector2i(texture.get_size()): return texture
	var offset: Dictionary = data.texture_rect_offset
	var origin := Vector2i(roundi(float(offset.x)), roundi(dimensions.y - float(offset.y) - texture.get_height()))
	# Unity's tight sprite crop omits transparent pixels used by its UI mask and slicing.
	var content := texture.get_image()
	content.convert(Image.FORMAT_RGBA8)
	var restored := Image.create(dimensions.x, dimensions.y, false, Image.FORMAT_RGBA8)
	restored.fill(Color.TRANSPARENT)
	restored.blit_rect(content, Rect2i(Vector2i.ZERO, content.get_size()), origin)
	return ImageTexture.create_from_image(restored)

func _draw() -> void:
	var frame := Rect2(Vector2.ZERO, size)
	if _uses_boss_mask():
		draw_part(self, source_kind, source_path, frame)
		return
	draw_part(self, source_kind, source_path + "/Bar", frame)
	_draw_fills(self)

func _draw_fills(canvas: CanvasItem) -> void:
	var frame := Rect2(Vector2.ZERO, size)
	var inner := frame.grow(-1.0)
	var follow := inner
	var crop := source_kind == "boss"
	if source_kind == "boss" and source_path == "HpStateBar":
		inner = Rect2(5.0, 8.7125, size.x - 10.0, size.y - 17.7125)
		follow = Rect2(5.0, 9.0, size.x - 10.0, size.y - 14.0506)
	draw_part(canvas, source_kind, source_path + "/Bar/BarTop_Follow", follow, follow_fraction, crop)
	draw_part(canvas, source_kind, source_path + "/Bar/BarTop_Cur", inner, fraction, crop)
	draw_part(canvas, source_kind, source_path + "/Bar/BarTop_OverCap", inner, overcap_fraction, crop)
