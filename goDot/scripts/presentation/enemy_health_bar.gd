extends Control

var elite := false
var fraction := 1.0
var follow_fraction := 1.0
var shield_fraction := 0.0
var _hold := 0.0
var _initialized := false
var value_label: Label
var icon: TextureRect
var _frame: StyleBoxFlat
var _fill: StyleBoxFlat

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame = DungeonStyle.box(Color("111820"), Color("697588"), 2)
	_frame.set_content_margin_all(0)
	_frame.set_corner_radius_all(4)
	_fill = DungeonStyle.box(Color("ff1607"))
	_fill.set_content_margin_all(0)
	_fill.set_corner_radius_all(2)
	icon = DungeonStyle.picture("res://assets/ui/enemy/elite.png", Vector2.ZERO)
	add_child(icon)
	value_label = DungeonStyle.label("", 14)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.add_theme_color_override("font_color", Color.WHITE)
	value_label.add_theme_color_override("font_outline_color", Color("131820"))
	value_label.add_theme_constant_override("outline_size", 4)
	add_child(value_label)
	configure(elite)

func configure(is_elite: bool) -> void:
	elite = is_elite
	size = Vector2(242 if elite else 96, 48 if elite else 18)
	if not is_instance_valid(icon): return
	icon.visible = elite
	icon.position = Vector2(-13, 19)
	icon.size = Vector2(34, 31)
	value_label.visible = elite
	value_label.position = Vector2(20, 0)
	value_label.size = Vector2(size.x - 20, 21)
	queue_redraw()

func update_health(current: float, maximum: float, shield: float, delta: float) -> void:
	var previous_fraction := fraction
	var previous_follow := follow_fraction
	var previous_shield := shield_fraction
	var first_update := not _initialized
	var next := clampf(current / maxf(1.0, maximum), 0, 1)
	if not _initialized or next > fraction:
		follow_fraction = next
		_hold = 0.0
	elif next < fraction:
		_hold = 0.18
	fraction = next
	_initialized = true
	_hold = maxf(0, _hold - maxf(0, delta))
	if _hold <= 0: follow_fraction = move_toward(follow_fraction, fraction, maxf(0, delta) * 0.9)
	shield_fraction = clampf(shield / maxf(1.0, maximum), 0, 1)
	# A living unit with fractional HP must never display a misleading zero.
	if elite: value_label.text = "%d / %d" % [ceili(maxf(0, current)), ceili(maxf(1, maximum))]
	if first_update or fraction != previous_fraction or follow_fraction != previous_follow or shield_fraction != previous_shield:
		queue_redraw()

func _draw() -> void:
	if _frame == null: return
	var frame := Rect2(14 if elite else 0, 28 if elite else 4, size.x - (14 if elite else 0), 15 if elite else 10)
	draw_style_box(_frame, frame)
	var inner := frame.grow(-3)
	if follow_fraction > 0:
		draw_rect(Rect2(inner.position, Vector2(inner.size.x * follow_fraction, inner.size.y)), Color("ffba25"))
	if fraction > 0:
		draw_style_box(_fill, Rect2(inner.position, Vector2(inner.size.x * fraction, inner.size.y)))
	if fraction > 0 and fraction < 1:
		var edge := inner.position.x + inner.size.x * fraction
		draw_line(Vector2(edge, inner.position.y), Vector2(edge, inner.end.y), Color("fff0af"), 1.5)
	if shield_fraction > 0:
		draw_rect(Rect2(frame.position + Vector2(3, frame.size.y + 2), Vector2(inner.size.x * shield_fraction, 3)), Color("d7edff"))
