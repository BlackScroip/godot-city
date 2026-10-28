extends Control

const DISPLAY_SECONDS := 4.0
const FADE_SECONDS := 0.25
const TIME_REVEAL_SECONDS := 1.8

var banner := VBoxContainer.new()
var title := Label.new()
var clock := Label.new()
var room_key := ""
var battle_seconds := 0.0
var elapsed := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_theme_constant_override("separation", 8)
	add_child(banner)
	for label in [title, clock]:
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_outline_color", Color("182424"))
		label.add_theme_constant_override("outline_size", 5)
		banner.add_child(label)
	title.text = DungeonLocale.text("战斗胜利")
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color("f2d897"))
	clock.add_theme_font_size_override("font_size", 24)
	clock.add_theme_color_override("font_color", Color.WHITE)
	resized.connect(_layout)
	clear()

static func format_time(seconds: float) -> String:
	var centiseconds := floori(maxf(0.0, seconds) * 100.0) if is_finite(seconds) else 0
	return "%02d:%02d.%02d" % [centiseconds / 6000, centiseconds / 100 % 60, centiseconds % 100]

func present(key: String, seconds: float) -> void:
	if key.is_empty() or key == room_key: return
	room_key = key
	battle_seconds = maxf(0.0, seconds) if is_finite(seconds) else 0.0
	clock.text = "%s  %s" % [DungeonLocale.text("讨伐用时"), format_time(battle_seconds)]
	elapsed = 0.0
	modulate.a = 1.0
	clock.modulate.a = 0.0
	show()
	_layout()
	set_process(true)

func clear() -> void:
	room_key = ""
	battle_seconds = 0.0
	elapsed = 0.0
	hide()
	set_process(false)

func _process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	if not visible: return
	elapsed += maxf(0.0, delta) if is_finite(delta) else 0.0
	clock.modulate.a = 1.0 if elapsed >= TIME_REVEAL_SECONDS else 0.0
	modulate.a = clampf((DISPLAY_SECONDS - elapsed) / FADE_SECONDS, 0.0, 1.0)
	if elapsed >= DISPLAY_SECONDS:
		hide()
		set_process(false)

func _layout() -> void:
	if size.x <= 0 or size.y <= 0: return
	var factor := minf(size.x / 1600.0, size.y / 720.0)
	banner.scale = Vector2.ONE * factor
	banner.position = Vector2(size.x * 0.15, size.y * 0.25)
	banner.size = Vector2(size.x * 0.7 / factor, 105)
