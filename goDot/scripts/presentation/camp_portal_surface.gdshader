shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add;

uniform sampler2D main_texture : source_color, hint_default_white;
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
uniform float clock = 0.0;
uniform bool flow = false;

void fragment() {
    vec2 uv = UV * uv_scale + uv_offset;
    if (flow) uv.x += clock * 0.08;
    vec4 source = texture(main_texture, uv);
    float mask = max(source.r, max(source.g, source.b));
    ALBEDO = vec3(0.06, 0.78, 1.0) * 1.5;
    ALPHA = mask * source.a * (flow ? 0.24 : 0.7);
}
