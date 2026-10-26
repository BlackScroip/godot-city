shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, blend_mix;

uniform float clock = 0.0;
uniform float timing_seed = 0.0;
uniform sampler2D main_texture : source_color, hint_default_white, repeat_enable;
uniform vec4 main_st = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec2 main_wrap = vec2(0.0);
uniform vec4 shape_color : source_color = vec4(1.0);
uniform vec4 source_tint : source_color = vec4(1.0);
uniform float source_alpha = 1.0;
uniform float shape_weight = 1.0;
uniform vec2 shape_scroll = vec2(0.0);
uniform bool use_shape2 = false;
uniform sampler2D shape2_texture : source_color, hint_default_white, repeat_enable;
uniform vec4 shape2_st = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec2 shape2_wrap = vec2(0.0);
uniform vec4 shape2_color : source_color = vec4(1.0);
uniform float shape2_weight = 1.0;
uniform vec2 shape2_scroll = vec2(0.0);
uniform vec2 shape2_contrast = vec2(1.0, 0.0);
uniform sampler2D shape2_distort : hint_default_black, repeat_enable;
uniform vec4 shape2_distort_st = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec2 shape2_distort_wrap = vec2(0.0);
uniform vec2 shape2_distort_scroll = vec2(0.0);
uniform float shape2_distort_amount = 0.0;
uniform sampler2D source_fade : hint_default_white, repeat_enable;
uniform vec4 source_fade_st = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec2 source_fade_wrap = vec2(0.0);
uniform float source_fade_amount = 0.0;
uniform float source_fade_power = 1.0;
uniform float source_fade_transition = 0.075;
uniform vec2 source_fade_scroll = vec2(0.0);
uniform bool use_source_burn = false;
uniform sampler2D source_burn : source_color, hint_default_white, repeat_enable;
uniform vec4 source_burn_st = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec2 source_burn_wrap = vec2(0.0);
uniform vec4 source_burn_color : source_color = vec4(1.0);
uniform float source_burn_width = 0.01;
uniform float source_burn_glow = 0.0;
uniform bool use_alpha_cutoff = false;
uniform float alpha_cutoff = 0.0;
uniform bool use_rim = false;
uniform vec4 rim_color : source_color = vec4(1.0);
uniform float rim_power = 1.0;
uniform float rim_scale = 1.0;
uniform float rim_bias = 0.0;
uniform float rim_intensity = 0.0;
uniform float rim_add = 1.0;
uniform float rim_erode = 0.0;
varying vec3 source_normal;
varying vec3 source_view;

vec2 signed_fraction(vec2 value) { return sign(value) * fract(abs(value)); }

float source_axis(float value, float wrap, float half_texel) {
    if (wrap < 0.5) return value;
    if (wrap > 2.5) value = abs(value);
    else if (wrap > 1.5) value = 1.0 - abs(1.0 - mod(value, 2.0));
    return clamp(value, half_texel, 1.0 - half_texel);
}

vec4 source_sample(sampler2D map, vec2 uv, vec2 wrap) {
    vec2 half_texel = 0.5 / vec2(textureSize(map, 0));
    uv = vec2(source_axis(uv.x, wrap.x, half_texel.x), source_axis(uv.y, wrap.y, half_texel.y));
    // ActorExporter flips Unity UV.y for glTF's image convention.
    return texture(map, vec2(uv.x, 1.0 - uv.y));
}

void vertex() {
    source_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
    source_view = PROJECTION_MATRIX[3][3] > 0.5 ? INV_VIEW_MATRIX[2].xyz : normalize(CAMERA_POSITION_WORLD - (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz);
}

void fragment() {
    vec2 uv = vec2(UV.x, 1.0 - UV.y);
    float time = clock + timing_seed;
    vec4 first = source_sample(main_texture, uv * main_st.xy + main_st.zw + signed_fraction(shape_scroll * time), main_wrap) * shape_color;
    vec4 combined = first;
    if (use_shape2) {
        vec2 second_uv = uv * shape2_st.xy + shape2_st.zw + signed_fraction(shape2_scroll * time);
        float noise = source_sample(shape2_distort, uv * shape2_distort_st.xy + shape2_distort_st.zw + signed_fraction(shape2_distort_scroll * (clock + 2.0 * timing_seed)), shape2_distort_wrap).r;
        second_uv += vec2((noise - 0.5) * 0.2 * shape2_distort_amount);
        vec4 second = source_sample(shape2_texture, second_uv, shape2_wrap) * shape2_color;
        second.rgb = max(vec3(0.0), (second.rgb - vec3(0.5)) * shape2_contrast.x + vec3(0.5 + shape2_contrast.y));
        second *= shape2_weight;
        combined = vec4(first.rgb * shape_weight + second.rgb, max(first.a * shape_weight, second.a));
    }
    combined.a = clamp(combined.a, 0.0, 1.0);
    vec2 fade_base = uv + vec2(timing_seed) + signed_fraction(source_fade_scroll * time);
    float fade_sample = source_sample(source_fade, fade_base * source_fade_st.xy + source_fade_st.zw, source_fade_wrap).r;
    // The source mesh variant uses vertex alpha, unlike the Custom1 particle variant.
    float fade_value = clamp(1.0 + source_fade_amount - COLOR.a, 0.0, 1.0);
    float threshold = fade_sample + 1.0 - 2.0 * min(pow(fade_value, source_fade_power), 1.0);
    float transition = max((1.0 - pow(1.0 - fade_value, 5.0)) * source_fade_transition, 0.01);
    float fade_alpha = smoothstep(0.0, transition, threshold);
    vec3 color = combined.rgb * source_tint.rgb * COLOR.rgb;
    if (use_source_burn) {
        float edge = fade_alpha - smoothstep(0.0, transition + source_burn_width, threshold);
        color += source_sample(source_burn, fade_base * source_burn_st.xy + source_burn_st.zw, source_burn_wrap).rgb * edge * source_burn_color.rgb * source_burn_glow * combined.a;
    }
    float opacity = fade_alpha * combined.a;
    if (use_rim) {
        float rim = clamp(rim_scale * pow(1.0 - abs(dot(source_normal, source_view)), rim_power) + rim_bias, 0.0, 1.0);
        vec3 light = rim * rim_color.rgb * rim_intensity;
        color = mix(color * (light + vec3(1.0)), color + light, rim_add);
        opacity = clamp(opacity * (1.0 - rim * rim_erode), 0.0, 1.0);
    }
    if (use_alpha_cutoff) opacity *= smoothstep(alpha_cutoff - 0.01, alpha_cutoff + 0.01, opacity);
    ALBEDO = color;
    ALPHA = clamp(opacity * source_alpha, 0.0, 1.0);
}
