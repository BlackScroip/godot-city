shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform float phase = 0.0;
uniform float variant = 0.0;
uniform float seed_value = 0.0;
uniform vec4 accent : source_color = vec4(0.85, 0.28, 0.08, 1.0);
uniform float strength = 1.0;

void vertex() {
    vec3 scale_value = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
    MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(INV_VIEW_MATRIX[0].xyz * scale_value.x, 0.0), vec4(INV_VIEW_MATRIX[1].xyz * scale_value.y, 0.0), vec4(INV_VIEW_MATRIX[2].xyz * scale_value.z, 0.0), MODEL_MATRIX[3]);
}

float blade(vec2 p, float offset, float tilt, float length_value, float width) {
    float along = p.x * cos(tilt) + p.y * sin(tilt);
    float across = -p.x * sin(tilt) + p.y * cos(tilt) - offset;
    float ends = max(0.0, 1.0 - abs(along) / length_value);
    float curve = along * along * 0.16;
    return (1.0 - smoothstep(width * ends, width * ends + 0.008, abs(across - curve))) * smoothstep(0.0, 0.12, ends);
}

void fragment() {
    vec2 p = (UV - 0.5) * 2.0;
    float t = clamp(phase, 0.0, 1.0);
    float fade = pow(1.0 - t, 1.2);
    float slash = 0.0;
    float edge = 0.0;
    if (variant < 0.5) {
        float tilt = 0.65 + mod(seed_value, 3.0) * 0.24;
        slash = blade(p, -0.14, tilt, 0.8, 0.026) + blade(p, 0.12, tilt, 0.64, 0.020);
        edge = blade(p, -0.155, tilt, 0.78, 0.006) + blade(p, 0.108, tilt, 0.61, 0.004);
    }
    float chips = 0.0;
    float streaks = 0.0;
    for (int i = 0; i < 9; i++) {
        float fi = float(i);
        float angle = fi * 2.39996 + seed_value * 0.7;
        vec2 direction = vec2(cos(angle), sin(angle));
        float speed = 0.45 + fract(fi * 0.37 + seed_value * 0.13) * 0.42;
        float travel = 0.14 + t * speed;
        vec2 q = p - direction * travel;
        float along = dot(q, direction);
        float across = dot(q, vec2(-direction.y, direction.x));
        float tail = 0.04 + (1.0 - t) * 0.07;
        float width = 0.014 + mod(fi, 3.0) * 0.003;
        chips += max(0.0, 1.0 - abs(along) / tail - abs(across) / width);
        streaks += max(0.0, 1.0 - abs(along + 0.045) / (tail * 1.8) - abs(across) / (width * 0.28)) * 0.55;
    }
    float angle = atan(p.y, p.x);
    float radius = length(p);
    float teeth = pow(abs(cos(angle * 5.0 + 0.4)), 7.0);
    float flash = (1.0 - smoothstep(0.03, 0.11 + teeth * 0.25, radius)) * (1.0 - smoothstep(0.0, 0.36, t));
    float shield = 0.0;
    if (variant > 2.5 && variant < 3.5) {
        slash = 0.0;
        flash *= 0.4;
        vec2 q = abs(p);
        shield = (1.0 - smoothstep(0.014, 0.035, abs(q.x * 0.7 + q.y - 0.28))) * (1.0 - smoothstep(0.25, 0.4, q.y));
    }
    float quiet = variant > 3.5 ? 0.35 : 1.0;
    float alpha = clamp((slash * 0.82 + edge * 0.6 + chips + streaks + flash * 0.7 + shield) * fade * quiet * strength, 0.0, 0.92);
    vec3 warm = vec3(0.96, 0.69, 0.24);
    vec3 ink = accent.rgb * 0.66;
    vec3 color = mix(ink, accent.rgb, clamp(slash + shield, 0.0, 1.0));
    color = mix(color, warm, clamp(chips + streaks + edge * 0.8, 0.0, 1.0));
    color = mix(color, vec3(1.0, 0.88, 0.58), clamp(flash, 0.0, 0.8));
    ALBEDO = color;
    ALPHA = alpha;
}
