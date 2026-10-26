extends PanelContainer

signal command(kind: String)

var statistics: Label
var clock: Label
var reset_button: Button
var end_button: Button

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(270, 136)
	add_theme_stylebox_override("panel", DungeonStyle.box(Color(0.08, 0.1, 0.1, 0.88), Color("b79c65"), 1))
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)
	add_child(stack)
	var heading := HBoxContainer.new()
	stack.add_child(heading)
	var title := DungeonStyle.label("训练场", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	clock = DungeonStyle.label("00:00", 18)
	heading.add_child(clock)
	statistics = DungeonStyle.label("", 18)
	stack.add_child(statistics)
	var actions := HBoxContainer.new()
	stack.add_child(actions)
	reset_button = Button.new()
	reset_button.text = "重置统计"
	reset_button.pressed.connect(func(): command.emit("reset_training"))
	end_button = Button.new()
	end_button.text = "结束训练"
	end_button.pressed.connect(func(): command.emit("end_training"))
	for key in [reset_button, end_button]:
		key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		key.custom_minimum_size.y = 32
		key.add_theme_font_size_override("font_size", 16)
		actions.add_child(key)
	hide()

func update_state(state: Dictionary, blocked: bool) -> void:
	visible = bool(state.get("active", false)) and not blocked
	if not visible: return
	var seconds := maxi(0, int(state.get("elapsed", 0)))
	clock.text = "%02d:%02d" % [seconds / 60, seconds % 60]
	statistics.text = "命中 %d  |  伤害 %.0f\n秒伤 %.1f  |  最高 %.0f" % [int(state.get("hits", 0)), float(state.get("total_damage", 0)), float(state.get("dps", 0)), float(state.get("maximum_hit", 0))]
	var screen: Vector2 = get_parent().size
	var factor := minf(1.0, minf(screen.x / 1280.0, screen.y / 720.0))
	scale = Vector2.ONE * factor
	position = Vector2(28, 148) * factor
	size = Vector2(270, 136)
