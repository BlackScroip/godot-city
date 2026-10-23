shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add;

uniform sampler2D runes : source_color;
uniform vec4 tint : source_color = vec4(0.1, 0.8, 1.0, 0.8);
uniform float clock = 0.0;
uniform bool ribbon = false;

void fragment() {
    float mask = 0.0;
    if (ribbon) {
        float height = UV.y;
        float spiral = fract(UV.x * 2.0 - height * 0.65 + clock * 0.17);
        float band = smoothstep(0.035, 0.0, abs(spiral - 0.5));
        float edge = sin(height * 3.14159265);
        mask = band * edge * 0.7;
    } else {
        vec2 p = UV * 2.0 - 1.0;
        float radius = length(p);
        float angle = atan(p.y, p.x) / 6.2831853 + 0.5;
        float outer = smoothstep(0.012, 0.0, abs(radius - 0.90));
        float inner = smoothstep(0.009, 0.0, abs(radius - 0.67));
        float center = smoothstep(0.012, 0.0, abs(radius - 0.36));
        float ring = smoothstep(0.055, 0.0, abs(radius - 0.81)) * 0.12;
        float spin = fract(angle + clock * 0.018);
        float segment = floor(spin * 20.0);
        vec2 glyph_uv = vec2(fract(spin * 20.0), clamp((radius - 0.70) / 0.16, 0.0, 1.0));
        vec2 tile = vec2(mod(segment * 3.0, 8.0), floor(segment * 3.0 / 8.0));
        vec3 glyph = texture(runes, (tile + glyph_uv * 0.84 + 0.08) / 8.0).rgb;
        float letters = max(glyph.r, max(glyph.g, glyph.b));
        letters *= step(0.70, radius) * step(radius, 0.86);
        float sweep = pow(max(0.0, cos((angle - clock * 0.06) * 18.8495559)), 24.0);
        float arcs = smoothstep(0.025, 0.0, abs(radius - 0.52)) * sweep;
        float wash = smoothstep(0.9, 0.1, radius) * 0.055;
        mask = outer + inner + center * 0.8 + ring + letters * 1.35 + arcs + wash;
        mask *= 0.85 + 0.15 * sin(clock * 1.8);
    }
    ALBEDO = tint.rgb * 1.5;
    ALPHA = clamp(mask * tint.a, 0.0, 1.0);
}
