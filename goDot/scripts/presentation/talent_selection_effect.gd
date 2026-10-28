extends Control

const Palette = preload("res://scripts/presentation/choice_palette.gd")
const LIGHT_SHADER := """
shader_type canvas_item;
render_mode unshaded;
uniform float elapsed = 0.0;
void fragment() {
	float x = abs(UV.x - 0.5) * 2.0;
	float body = pow(max(0.0, 1.0 - x), 1.7);
	float edge = exp(-pow((x - 0.72) * 17.0, 2.0));
	float streak = pow(max(0.0, sin(UV.x * 95.0 + sin(UV.x * 29.0) * 2.0)), 12.0);
	float drift = 0.68 + 0.32 * sin(UV.y * 16.0 - elapsed * 1.6 + UV.x * 24.0);
	float fade = smoothstep(0.0, 0.14, UV.y) * smoothstep(0.0, 0.09, 1.0 - UV.y);
	float light = body * 0.33 + edge * 0.30 + streak * body * drift * 0.18;
	COLOR = vec4(mix(vec3(0.24, 0.52, 1.0), vec3(0.78, 0.93, 1.0), edge * 0.75 + streak * 0.2), light * fade);
}
"""

var elapsed := 0.0
var _light: ColorRect
var _material: ShaderMaterial
var _star: Texture2D

func _ready() -> void:
	name = "SelectedTalentLight"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader = Shader.new()
	shader.code = LIGHT_SHADER
	_material = ShaderMaterial.new()
	_material.shader = shader
	_light = ColorRect.new()
	_light.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_light.material = _material
	add_child(_light)
	_light.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_star = Palette.texture("白星标")
	hide()
	set_process(false)

func set_active(value: bool) -> void:
	visible = value
	set_process(value)
	if value:
		elapsed = 0.0
		_material.set_shader_parameter("elapsed", elapsed)
		queue_redraw()

func _process(delta: float) -> void:
	elapsed += delta
	_material.set_shader_parameter("elapsed", elapsed)
	queue_redraw()

func _draw() -> void:
	if not _star: return
	var points := [Vector2(0.22, 0.12), Vector2(0.61, 0.09), Vector2(0.82, 0.18), Vector2(0.09, 0.39), Vector2(0.93, 0.56), Vector2(0.13, 0.78), Vector2(0.68, 0.92), Vector2(0.88, 0.87)]
	for index in points.size():
		var phase := elapsed * 1.7 + index * 1.83
		var pulse := 0.45 + 0.55 * (sin(phase) * 0.5 + 0.5)
		var radius := size.x * (0.027 if index % 3 == 0 else 0.014) * pulse
		var point: Vector2 = points[index] * size + Vector2(0, sin(phase * 0.6) * size.y * 0.006)
		draw_texture_rect(_star, Rect2(point - Vector2.ONE * radius, Vector2.ONE * radius * 2.0), false, Color(0.78, 0.94, 1.0, pulse))
