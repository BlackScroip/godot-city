extends Control

const ANIMATION_PATH := "res://assets/ui/region_notice/animation.json"

var banner := Control.new()
var background := TextureRect.new()
var title_label := Label.new()
var elapsed := 0.0
var entry_key := ""
var _animation: Dictionary = {}
var _frames: Array[Texture2D] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_animation = JSON.parse_string(FileAccess.get_file_as_string(ANIMATION_PATH))
	for path in _animation.frames: _frames.append(load(str(path)))
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(banner)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	banner.add_child(background)
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.add_theme_color_override("font_color", Color.WHITE)
	title_label.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	banner.add_child(title_label)
	resized.connect(_layout)
	_layout()
	hide()
	set_process(false)

func present(key: String, title: String) -> void:
	if key.is_empty() or title.is_empty() or key == entry_key: return
	entry_key = key
	title_label.text = title
	elapsed = 0.0
	_layout()
	show()
	_apply_frame()
	set_process(true)

func clear() -> void:
	entry_key = ""
	elapsed = 0.0
	title_label.text = ""
	hide()
	set_process(false)

func _process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	if not visible: return
	elapsed += maxf(0.0, delta)
	if elapsed >= float(_animation.duration):
		hide()
		set_process(false)
		return
	_apply_frame()

func _sample(track: String) -> float:
	var keys: Array = _animation.tracks[track]
	var key: Array = keys[0]
	for candidate in keys:
		if float(candidate[0]) > elapsed: break
		key = candidate
	# Unity streamed keys store cubic coefficients relative to their key time.
	var time := maxf(0.0, elapsed - float(key[0]))
	return ((float(key[1]) * time + float(key[2])) * time + float(key[3])) * time + float(key[4])

func _apply_frame() -> void:
	modulate.a = clampf(_sample("root_alpha"), 0.0, 1.0)
	banner.visible = _sample("background_active") >= 0.5
	banner.modulate.a = clampf(_sample("background_alpha"), 0.0, 1.0)
	title_label.visible = _sample("title_active") >= 0.5
	title_label.modulate.a = clampf(_sample("title_alpha"), 0.0, 1.0)
	background.texture = _frames[clampi(roundi(_sample("sprite_frame")), 0, _frames.size() - 1)]

func _layout() -> void:
	if _animation.is_empty() or size.x <= 0.0 or size.y <= 0.0: return
	var reference: Array = _animation.reference_size
	var factor := minf(size.x / float(reference[0]), size.y / float(reference[1]))
	banner.position = Vector2(0, float(_animation.top) * factor)
	banner.size = Vector2(size.x / factor, float(_animation.height))
	banner.scale = Vector2.ONE * factor
	title_label.position = Vector2(banner.size.x * 0.1, float(_animation.title_center_y) - 50.0)
	title_label.size = Vector2(banner.size.x * 0.8, 100.0)
	var font_size := int(_animation.font_size)
	var font := title_label.get_theme_font("font")
	while font_size > 14 and font.get_string_size(title_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > title_label.size.x:
		font_size -= 1
	title_label.add_theme_font_size_override("font_size", font_size)
