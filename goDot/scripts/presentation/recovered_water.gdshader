shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert;

uniform float elapsed = 0.0;
uniform vec2 flow_speed = vec2(0.3, 0.0);
uniform vec2 wave_tiling = vec2(3.0);
uniform vec4 deep_color : source_color = vec4(0.08, 0.72, 1.0, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.0, 1.0, 0.7, 1.0);
uniform vec4 foam_color : source_color = vec4(1.0);
uniform float opacity = 0.9;
uniform float foam_strength = 1.0;
uniform bool waterfall = false;
uniform bool world_uv = false;
uniform sampler2D foam_mask : filter_linear, repeat_enable;
varying vec3 world_position;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 base_uv = world_uv ? world_position.xz * 0.35 : UV;
	vec2 flow = flow_speed * elapsed * 0.2;
	vec2 p = base_uv * wave_tiling - flow;
	if (waterfall) p *= vec2(3.0, 0.65);
	float waves = noise(p * 6.0) * 0.65 + noise(p * 11.0 + flow * 0.7) * 0.35;
	float ripples = sin((p.x + p.y * 0.7 + waves * 0.6) * 24.0) * 0.5 + 0.5;
	float foam = smoothstep(0.68, 0.86, waves) * (0.35 + ripples * 0.65);
	if (waterfall) {
		float mask = texture(foam_mask, UV - flow).r;
		foam = max(foam, mask * smoothstep(0.35, 0.75, waves));
	}
	vec3 water = mix(deep_color.rgb, shallow_color.rgb, waves * 0.75);
	ALBEDO = mix(water, foam_color.rgb, clamp(foam * foam_strength * 0.65, 0.0, 0.8));
	EMISSION = water * 0.12 + foam_color.rgb * foam * 0.08;
	ROUGHNESS = 0.32;
	SPECULAR = 0.35;
	ALPHA = clamp(opacity + foam * 0.1, 0.0, 1.0);
}
