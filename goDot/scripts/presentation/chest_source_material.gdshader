shader_type spatial;
render_mode cull_back, specular_disabled;

uniform sampler2D base_texture : source_color, hint_default_white, repeat_enable;
uniform vec4 base_st = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 base_tint : source_color = vec4(1.0);
uniform float source_brightness = 1.0;
uniform float source_contrast = 1.0;
uniform float diffuse_wrap = 0.0;
uniform float diffuse_brightness = 1.0;
uniform float diffuse_contrast = 1.0;
uniform vec4 rim_color : source_color = vec4(1.0);
uniform float rim_amount = 1.0;
uniform float rim_contrast = 2.0;
uniform bool rim_inverse = false;
uniform sampler2D emissive_texture : source_color, hint_default_black, repeat_enable;
uniform vec4 emissive_st = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 emissive_color : source_color = vec4(0.0);
uniform bool use_normal_map = false;
uniform sampler2D normal_texture : hint_normal, repeat_enable;
uniform vec4 normal_st = vec4(1.0, 1.0, 0.0, 0.0);
uniform float normal_strength = 1.0;

vec2 source_uv(vec2 coordinates, vec4 st) {
    vec2 uv = vec2(coordinates.x, 1.0 - coordinates.y) * st.xy + st.zw;
    return vec2(uv.x, 1.0 - uv.y);
}

void fragment() {
    vec3 base = texture(base_texture, source_uv(UV, base_st)).rgb;
    ALBEDO = pow(max(base, vec3(0.0)), vec3(source_contrast)) * (source_brightness + 0.05) * base_tint.rgb;
    ROUGHNESS = 1.0;
    vec3 surface_normal = NORMAL;
    if (use_normal_map) {
        vec2 packed_normal = texture(normal_texture, source_uv(UV, normal_st)).ag * 2.0 - 1.0;
        vec3 map_normal = normalize(vec3(packed_normal * normal_strength, max(sqrt(1.0 - min(dot(packed_normal, packed_normal), 1.0)), 1e-16)));
        surface_normal = normalize(TANGENT * map_normal.x + BINORMAL * map_normal.y + NORMAL * map_normal.z);
        NORMAL = surface_normal;
    }
    // APK OmniShade GLES program 209: clamped additive view rim plus emissive map.
    float facing = max(dot(normalize(surface_normal), normalize(VIEW)), 0.0);
    float rim = min(pow(rim_inverse ? facing : 1.0 - facing, rim_contrast) * rim_amount, 1.0);
    EMISSION = rim * rim_color.a * rim_color.rgb;
    EMISSION += texture(emissive_texture, source_uv(UV, emissive_st)).rgb * emissive_color.rgb;
}

void light() {
    float diffuse = max(dot(NORMAL, LIGHT), 0.0);
    diffuse = pow(max(diffuse_wrap * (1.0 - diffuse) + diffuse, 0.0), diffuse_contrast);
    DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * diffuse * (diffuse_brightness - 0.07);
}
