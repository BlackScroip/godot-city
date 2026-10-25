shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add;

uniform sampler2D wave_texture : source_color, repeat_enable;
uniform float clock = 0.0;

void fragment() {
    vec2 centered = vec2((UV.x - 0.5) * 2.0, (0.5 - UV.y) * 2.0);
    float cap = length(vec2(centered.x, max(centered.y * 1.7 - 0.7, 0.0)));
    float silhouette = 1.0 - smoothstep(0.84, 1.0, cap);
    float floor_fade = smoothstep(0.0, 0.08, 1.0 - UV.y);
    float wave = texture(wave_texture, vec2(UV.x + clock * 0.06, UV.y)).r;
    ALBEDO = vec3(0.31, 0.5525, 1.0);
    ALPHA = silhouette * floor_fade * (0.16 + wave * 0.65);
}
