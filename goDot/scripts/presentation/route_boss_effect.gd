class_name DungeonRouteBossEffect
extends ColorRect

const ART = "res://assets/ui/route/chrome/"
const SHADER = """shader_type canvas_item;
render_mode unshaded, blend_add;

uniform sampler2D glow_tex : repeat_disable, filter_linear;
uniform sampler2D flow_tex : repeat_enable, filter_linear;
uniform sampler2D flow_mask : repeat_disable, filter_linear;
uniform sampler2D streamer_tex : repeat_enable, filter_linear;
uniform sampler2D streamer_mask : repeat_disable, filter_linear;
uniform sampler2D distortion_tex : repeat_enable, filter_linear;
uniform float intensity : hint_range(0.0, 1.5) = 1.0;
uniform float flow_speed = 0.05;
uniform float streamer_speed = 0.03;
uniform float preview_time = -1.0;

void fragment() {
	vec4 inherited = COLOR;
	float time = preview_time >= 0.0 ? preview_time : TIME;
	vec2 centered = UV * 2.0 - 1.0;
	float radius = max(abs(centered.x), abs(centered.y));
	vec2 rim_uv = vec2(atan(centered.y, centered.x) / 6.2831853 + 0.5,
		0.5 + (radius - 0.82) * 2.6);
	vec4 glow = texture(glow_tex, UV);
	float flow = texture(flow_tex, rim_uv * vec2(3.0, 0.5) + vec2(0.0, time * flow_speed)).r;
	flow *= texture(flow_mask, rim_uv * vec2(1.0, 0.7) + vec2(0.0, 0.1)).r;
	vec2 distortion = texture(distortion_tex,
		rim_uv * vec2(1.0, 0.3) + vec2(0.0, time * streamer_speed)).rg - vec2(0.5);
	float streamer = texture(streamer_tex,
		rim_uv * vec2(2.0, 1.5) + vec2(0.0, time * streamer_speed) + distortion * 0.15).r;
	streamer *= texture(streamer_mask, rim_uv * vec2(1.0, 0.8) + vec2(0.0, 0.1)).r;
	float rim = smoothstep(0.62, 0.78, radius);
	float edge = smoothstep(0.0, 0.06, min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y)));
	float breath = 0.92 + 0.08 * sin(time * 2.5132741);
	float energy = glow.r * glow.a * 0.349 + (flow * 0.502 + streamer * 0.54) * rim;
	float alpha = min(0.92, energy * intensity * breath) * edge * inherited.a;
	COLOR = vec4(vec3(1.0, 0.0, 0.0) * inherited.rgb, alpha);
}
"""

var effect_material: ShaderMaterial
var intensity := 1.0:
	set(value):
		intensity = clampf(value, 0.0, 1.5)
		if effect_material: effect_material.set_shader_parameter("intensity", intensity)
var _textures_ready := true

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	show_behind_parent = true
	color = Color.WHITE
	var shader = Shader.new()
	shader.code = SHADER
	effect_material = ShaderMaterial.new()
	effect_material.shader = shader
	material = effect_material
	# APK material speeds and masks are retained; their particle layers become a bounded UI rim.
	var textures = {"glow_tex": "boss_glow_maintex", "flow_tex": "boss_flow_maintex",
		"flow_mask": "boss_flow_masktex", "streamer_tex": "boss_streamer_maintex",
		"streamer_mask": "boss_streamer_masktex", "distortion_tex": "boss_streamer_distortiontex"}
	for parameter in textures:
		var texture = DungeonStyle.texture(ART + textures[parameter] + ".png")
		if texture == null: _textures_ready = false
		effect_material.set_shader_parameter(parameter, texture)
	effect_material.set_shader_parameter("intensity", intensity)
	visible = _textures_ready

func configure(bounds: Rect2, strength := 1.0) -> void:
	position = bounds.position
	size = bounds.size
	intensity = strength
	visible = _textures_ready and intensity > 0.0
