extends Button

const DISPLAY_TIME := 5.0
const FADE_IN_TIME := 0.5
const CHANGE_TIME := 4.0

var resource_icon: TextureRect
var value_label: Label
var change_label: Label
var amount := 0
var _initialized := false
var _remaining := 0.0
var _fade_elapsed := 0.0
var _fade_start := 0.0
var _change_remaining := 0.0
var _change := 0
var _value_elapsed := 1.5

func _init() -> void:
	custom_minimum_size = Vector2(212, 40)
	focus_mode = Control.FOCUS_NONE
	var frame := DungeonStyle.box(Color(0.08, 0.07, 0.05, 0.85), DungeonStyle.GOLD, 2)
	frame.set_corner_radius_all(20)
	frame.content_margin_top = 0
	frame.content_margin_bottom = 0
	for state in ["normal", "hover", "pressed", "disabled"]:
		add_theme_stylebox_override(state, frame)
	var line := HBoxContainer.new()
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	line.offset_left = 8
	line.offset_right = -8
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(line)
	resource_icon = DungeonStyle.picture("", Vector2(36, 36))
	line.add_child(resource_icon)
	value_label = DungeonStyle.label("0", 20)
	value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(value_label)
	change_label = DungeonStyle.label("", 18)
	change_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	change_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(change_label)
	hide()

func update_amount(value: int, caption := "", auto_reveal := true) -> void:
	value_label.text = str(value) if caption.is_empty() else caption
	var difference := value - amount
	if auto_reveal and _initialized and difference != 0:
		if _change_remaining <= 0 or signi(difference) != signi(_change): _change = 0
		_change += difference
		_change_remaining = CHANGE_TIME
		change_label.text = "%+d" % _change
		change_label.modulate = Color("93df88") if _change > 0 else Color("f17f76")
		_value_elapsed = 0.0
		value_label.pivot_offset = value_label.size * 0.5
		value_label.scale = Vector2.ONE * 1.8
		value_label.modulate = Color(1.0, 0.9, 0.12)
		_reveal()
	amount = value
	_initialized = true

func _reveal() -> void:
	_fade_start = modulate.a if visible else 0.0
	_fade_elapsed = 0.0
	_remaining = DISPLAY_TIME
	modulate.a = _fade_start
	show()

func _process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	if _remaining > 0:
		_remaining = maxf(0.0, _remaining - maxf(0.0, delta))
		if _remaining <= 0: hide()
		else:
			_fade_elapsed = minf(FADE_IN_TIME, _fade_elapsed + maxf(0.0, delta))
			modulate.a = lerpf(_fade_start, 1.0, _fade_elapsed / FADE_IN_TIME)
	_change_remaining = maxf(0.0, _change_remaining - maxf(0.0, delta))
	if _change_remaining <= 0: _change = 0
	change_label.modulate.a = minf(1.0, _change_remaining / 2.0)
	_value_elapsed = minf(1.5, _value_elapsed + maxf(0.0, delta))
	value_label.scale = Vector2.ONE * lerpf(1.8, 1.0, minf(1.0, _value_elapsed / 0.62))
	value_label.modulate = Color(1.0, 0.9, 0.12).lerp(Color.WHITE, _value_elapsed / 1.5)
