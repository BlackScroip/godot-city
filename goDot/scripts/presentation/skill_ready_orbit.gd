extends Node2D

var button_size := Vector2(100, 100)
var low_effects := false
var active := false
var age := 0.0
var burst_age := 1.0

func _ready() -> void:
	var additive = CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = additive
	hide()
	set_process(false)

func set_active(value: bool, burst := false) -> void:
	if value == active:
		if value and burst: burst_age = 0
		return
	active = value
	visible = value
	set_process(value)
	if value:
		age = 0
		burst_age = 0 if burst else 1.0
	else:
		burst_age = 1.0
	queue_redraw()

func _process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	if not active: return
	age += delta
	burst_age += delta
	queue_redraw()

func _draw() -> void:
	if not active: return
	var center = button_size * 0.5
	var radius = minf(button_size.x, button_size.y) * 0.51
	var unit = minf(button_size.x, button_size.y) / 100.0
	var count = 6 if low_effects else 14
	for i in count:
		var phase = float(i) / count
		var angle = phase * TAU + age * (1.25 + float(i % 3) * 0.13)
		var wave = 0.6 + 0.4 * sin(age * 3.1 + i * 1.7)
		var lane = radius + sin(age * 2.2 + i * 2.4) * 2.0 * unit
		var point = center + Vector2.from_angle(angle) * lane
		var tangent = Vector2.from_angle(angle + PI / 2)
		var outward = Vector2.from_angle(angle)
		var width = (0.75 + wave * 0.7) * unit
		var length = (4.0 + wave * 5.0) * unit
		if not low_effects:
			draw_arc(center, lane, angle - 0.18 - wave * 0.10, angle, 8, Color(1, 0.20, 0.025, 0.30 * wave), 2.7 * unit, true)
			draw_circle(point, width * 3.0, Color(1, 0.12, 0.015, 0.14 * wave))
		draw_circle(point, width * 1.8, Color(1, 0.30, 0.025, 0.20 * wave))
		draw_colored_polygon(PackedVector2Array([point - tangent * length, point - outward * width, point + tangent * width, point + outward * width]), Color(1, 0.48 + 0.15 * wave, 0.08, 0.65 * wave))
		draw_circle(point, maxf(0.55, width * 0.55), Color(1, 0.91, 0.47, 0.85 * wave))
	if burst_age < 0.32:
		var progress = burst_age / 0.32
		var burst_count = 6 if low_effects else 12
		for i in burst_count:
			var angle = float(i) / burst_count * TAU - 0.15
			var point = center + Vector2.from_angle(angle) * (radius + progress * 9.0 * unit)
			var tail = point - Vector2.from_angle(angle) * (3.5 * unit * (1 - progress))
			draw_line(tail, point, Color(1, 0.45, 0.06, (1 - progress) * 0.8), 1.8 * unit, true)
