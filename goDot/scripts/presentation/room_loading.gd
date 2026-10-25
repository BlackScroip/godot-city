extends CanvasLayer

const RELIC_TIP := "或许是迷宫的力量，又或许是英雄们的传说，这些遗落在迷宫的神秘道具能让带上它们的冒险者在迷宫内获得强大祝福！"

var blocker := Control.new()
var background := TextureRect.new()
var bottom_shade := TextureRect.new()
var content := VBoxContainer.new()
var spinner := TextureRect.new()
var title_label := Label.new()
var tip_label := Label.new()
var progress_bar := ProgressBar.new()
var status_label := Label.new()
var elapsed := 0.0
var destination := ""

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.theme = DungeonStyle.theme()
	add_child(blocker)
	background.texture = DungeonStyle.texture("res://assets/ui/loading/forest.png")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blocker.add_child(background)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.05, 0.04, 0.18)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blocker.add_child(shade)
	var fade := Gradient.new()
	fade.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.82)])
	var fade_texture := GradientTexture2D.new()
	fade_texture.gradient = fade
	fade_texture.fill_from = Vector2(0.5, 0)
	fade_texture.fill_to = Vector2(0.5, 1)
	bottom_shade.texture = fade_texture
	bottom_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blocker.add_child(bottom_shade)
	content.add_theme_constant_override("separation", 4)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blocker.add_child(content)
	title_label.text = "【遗物】"
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(title_label)
	tip_label.text = RELIC_TIP
	tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(tip_label)
	spinner.texture = DungeonStyle.texture("res://assets/ui/loading/spinner.png")
	spinner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	spinner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	spinner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blocker.add_child(spinner)
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blocker.add_child(status_label)
	progress_bar.show_percentage = false
	progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for state in ["background", "fill"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.17, 0.19, 0.20, 0.8) if state == "background" else Color("f5f0db")
		progress_bar.add_theme_stylebox_override(state, style)
	blocker.add_child(progress_bar)
	blocker.resized.connect(_layout)
	_layout()
	hide()

func begin(title: String) -> void:
	destination = title
	elapsed = 0.0
	spinner.rotation = 0.0
	progress_bar.value = 0.0
	status_label.text = "加载中... 0%"
	show()
	_layout()

func set_progress(value: float) -> void:
	progress_bar.value = maxf(progress_bar.value, clampf(value, 0.0, 1.0) * 100.0)
	status_label.text = "加载中... %d%%" % roundi(progress_bar.value)

func finish() -> void:
	hide()

func _layout() -> void:
	var viewport_size := blocker.size
	var compact := viewport_size.y < 600.0 or viewport_size.x < 1000.0
	var margin := 24.0 if compact else 48.0
	var font_size := 17 if compact else 23
	var status_width := 116.0 if compact else 154.0
	var spinner_size := 40.0 if compact else 62.0
	var bar_y := viewport_size.y - (30.0 if compact else 64.0)
	var text_width := maxf(120.0, viewport_size.x - margin * 2.0 - status_width - spinner_size - 30.0)
	title_label.add_theme_font_size_override("font_size", font_size)
	tip_label.add_theme_font_size_override("font_size", font_size)
	status_label.add_theme_font_size_override("font_size", 15 if compact else 18)
	# Measure wrapped text before positioning so the lower edge stays above the bar.
	content.size = Vector2(text_width, 0)
	tip_label.size.x = text_width
	var text_height := title_label.get_minimum_size().y + tip_label.get_minimum_size().y + 4.0
	content.size.y = text_height
	content.position = Vector2(margin, bar_y - text_height - 20.0)
	spinner.size = Vector2.ONE * spinner_size
	spinner.position = Vector2(viewport_size.x - margin - status_width - spinner_size - 12.0, bar_y - spinner_size - 20.0)
	status_label.size = Vector2(status_width, spinner_size)
	status_label.position = Vector2(viewport_size.x - margin - status_width, spinner.position.y)
	progress_bar.position = Vector2(0, bar_y)
	progress_bar.size = Vector2(viewport_size.x, 6.0 if compact else 10.0)
	bottom_shade.position = Vector2(0, maxf(0.0, content.position.y - 100.0))
	bottom_shade.size = Vector2(viewport_size.x, viewport_size.y - bottom_shade.position.y)

func _process(delta: float) -> void:
	if not visible: return
	elapsed += delta
	spinner.pivot_offset = spinner.size * 0.5
	spinner.rotation = elapsed * 1.8

func _input(_event: InputEvent) -> void:
	if visible: get_viewport().set_input_as_handled()
