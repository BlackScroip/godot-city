extends CanvasLayer

var blocker := Control.new()
var content := VBoxContainer.new()
var spinner := TextureRect.new()
var title_label := Label.new()
var progress_bar := ProgressBar.new()
var status_label := Label.new()
var elapsed := 0.0

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.theme = DungeonStyle.theme()
	add_child(blocker)
	var shade := ColorRect.new()
	shade.color = Color("101916")
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blocker.add_child(shade)
	content.add_theme_constant_override("separation", 16)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blocker.add_child(content)
	var icon_holder := CenterContainer.new()
	icon_holder.custom_minimum_size.y = 84
	icon_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(icon_holder)
	spinner.texture = DungeonStyle.texture("material:102")
	spinner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	spinner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	spinner.custom_minimum_size = Vector2(64, 64)
	spinner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_holder.add_child(spinner)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.add_theme_font_size_override("font_size", 24)
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(title_label)
	progress_bar.custom_minimum_size.y = 8
	progress_bar.show_percentage = false
	progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress_bar.add_theme_stylebox_override("background", DungeonStyle.box(Color("273b31")))
	progress_bar.add_theme_stylebox_override("fill", DungeonStyle.box(DungeonStyle.GOLD))
	content.add_child(progress_bar)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 16)
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(status_label)
	blocker.resized.connect(_layout)
	_layout()
	hide()

func begin(title: String) -> void:
	title_label.text = title
	elapsed = 0.0
	spinner.rotation = 0.0
	progress_bar.value = 0.0
	status_label.text = "正在进入关卡 · 0%"
	show()
	_layout()

func set_progress(value: float) -> void:
	progress_bar.value = maxf(progress_bar.value, clampf(value, 0.0, 1.0) * 100.0)
	status_label.text = "正在进入关卡 · %d%%" % roundi(progress_bar.value)

func finish() -> void:
	hide()

func _layout() -> void:
	var width := minf(420.0, maxf(120.0, blocker.size.x - 64.0))
	content.size = Vector2(width, 230)
	content.position = (blocker.size - content.size) * 0.5

func _process(delta: float) -> void:
	if not visible: return
	elapsed += delta
	spinner.pivot_offset = spinner.size * 0.5
	spinner.rotation = elapsed * 1.5
	spinner.modulate.a = 0.8 + 0.2 * sin(elapsed * 3.0)

func _input(_event: InputEvent) -> void:
	if visible: get_viewport().set_input_as_handled()
