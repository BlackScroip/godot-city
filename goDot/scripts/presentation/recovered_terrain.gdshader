shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform sampler2D control_map : filter_linear, repeat_disable;
uniform sampler2D layer_0 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D layer_1 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D layer_2 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 uv_0 = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 uv_1 = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 uv_2 = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 tint_0 : source_color = vec4(1.0);
uniform vec4 tint_1 : source_color = vec4(1.0);
uniform vec4 tint_2 : source_color = vec4(1.0);
uniform int layer_count = 3;

void fragment() {
	vec3 weights = texture(control_map, UV).rgb;
	if (layer_count < 3) { weights.b = 0.0; }
	weights /= max(dot(weights, vec3(1.0)), 0.001);
	ALBEDO = texture(layer_0, UV * uv_0.xy + uv_0.zw).rgb * tint_0.rgb * weights.r
		+ texture(layer_1, UV * uv_1.xy + uv_1.zw).rgb * tint_1.rgb * weights.g
		+ texture(layer_2, UV * uv_2.xy + uv_2.zw).rgb * tint_2.rgb * weights.b;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
