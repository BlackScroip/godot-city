shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

void fragment() {
	vec3 scenery = textureLod(screen_texture, SCREEN_UV, 3.2).rgb;
	COLOR = vec4(mix(scenery, vec3(0.14, 0.23, 0.23), 0.24), 1.0);
}
