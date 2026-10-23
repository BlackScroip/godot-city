shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform sampler2D main_texture : source_color, hint_default_white;
uniform vec4 tint : source_color = vec4(1.0);
uniform bool luminance_alpha = false;
uniform float shape_alpha_weight = 1.0;
uniform float shape_brightness = 0.0;
uniform float visual_gain = 1.0;
uniform bool crimson_blade = false;
uniform bool reconstructed_ribbon = false;
uniform bool reconstructed_water_shell = false;
uniform bool reconstructed_water_splash = false;
uniform sampler2D opacity_mask : hint_default_white, repeat_disable;
uniform bool use_opacity_mask = false;
uniform vec2 mask_uv_scale = vec2(1.0);
uniform vec2 mask_uv_offset = vec2(0.0);
uniform float mask_power = 1.0;
uniform vec2 edge_feather = vec2(0.0);
uniform bool billboard = false;
uniform bool vertical_billboard = false;
uniform bool stretched_billboard = false;
uniform float stretch_length = 1.0;
uniform vec2 initial_rotation = vec2(0.0);
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
uniform vec2 sheet = vec2(1.0);
uniform sampler2D frame_curve : hint_default_white;
uniform bool use_frame_curve = false;
uniform float sheet_cycles = 1.0;
uniform float sheet_start = 0.0;
uniform sampler2D motion_curve : hint_default_black;
uniform bool use_motion_curve = false;
uniform bool world_motion = false;
uniform mat3 emitter_basis = mat3(1.0);
varying float animation_frame;
varying float life_phase;

void vertex() {
    animation_frame = INSTANCE_CUSTOM.z;
    float phase = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
    life_phase = phase;
    if (use_frame_curve) {
        float cycle_phase = fract(min(phase, 0.999999) * sheet_cycles);
        animation_frame = texture(frame_curve, vec2(cycle_phase, 0.5)).r + sheet_start;
    }
    vec3 world_offset = vec3(0.0);
    if (use_motion_curve) {
        world_offset = texture(motion_curve, vec2(phase, 0.5)).rgb;
        if (!world_motion) world_offset = emitter_basis * world_offset;
    }
    float x = initial_rotation.x;
    float y = initial_rotation.y;
    mat3 rx = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, cos(x), sin(x)), vec3(0.0, -sin(x), cos(x)));
    mat3 ry = mat3(vec3(cos(y), 0.0, -sin(y)), vec3(0.0, 1.0, 0.0), vec3(sin(y), 0.0, cos(y)));
    VERTEX = ry * rx * VERTEX;
    if (billboard) {
        vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
        float angle = INSTANCE_CUSTOM.x;
        vec3 right = INV_VIEW_MATRIX[0].xyz * cos(angle) + INV_VIEW_MATRIX[1].xyz * sin(angle);
        vec3 up = -INV_VIEW_MATRIX[0].xyz * sin(angle) + INV_VIEW_MATRIX[1].xyz * cos(angle);
        MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(right * scale.x, 0.0), vec4(up * scale.y, 0.0), vec4(INV_VIEW_MATRIX[2].xyz * scale.z, 0.0), MODEL_MATRIX[3]);
    } else if (vertical_billboard) {
        vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
        vec3 forward = normalize(vec3(INV_VIEW_MATRIX[2].x, 0.0, INV_VIEW_MATRIX[2].z) + vec3(0.000001, 0.0, 0.0));
        vec3 right = cross(vec3(0.0, 1.0, 0.0), forward);
        MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(right * scale.x, 0.0), vec4(0.0, scale.y, 0.0, 0.0), vec4(forward * scale.z, 0.0), MODEL_MATRIX[3]);
    } else if (stretched_billboard) {
        vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
        vec3 direction = normalize(MODEL_MATRIX[1].xyz);
        vec3 right = normalize(cross(direction, INV_VIEW_MATRIX[2].xyz) + INV_VIEW_MATRIX[0].xyz * 0.000001);
        vec3 forward = normalize(cross(right, direction));
        MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(right * scale.x, 0.0), vec4(direction * scale.y * stretch_length, 0.0), vec4(forward * scale.z, 0.0), MODEL_MATRIX[3]);
    } else {
        float angle = INSTANCE_CUSTOM.x;
        VERTEX.xy = mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle))) * VERTEX.xy;
    }
    MODELVIEW_MATRIX[3].xyz += (VIEW_MATRIX * vec4(world_offset, 0.0)).xyz;
}

void fragment() {
    float frame = min(floor(clamp(animation_frame, 0.0, 0.999999) * sheet.x * sheet.y), sheet.x * sheet.y - 1.0);
    // Repeat authored UVs inside their frame instead of sampling neighbouring tiles.
    vec2 local_uv = fract(UV * uv_scale + uv_offset);
    vec2 frame_cell = vec2(mod(frame, sheet.x), floor(frame / sheet.x));
    vec2 sheet_uv = (local_uv + frame_cell) / sheet;
    vec2 half_texel = 0.5 / vec2(textureSize(main_texture, 0));
    sheet_uv = clamp(sheet_uv, frame_cell / sheet + half_texel, (frame_cell + 1.0) / sheet - half_texel);
    vec4 sample_color = texture(main_texture, sheet_uv);
    float mask = luminance_alpha ? max(sample_color.r, max(sample_color.g, sample_color.b)) : 1.0;
    ALBEDO = max(sample_color.rgb + vec3(shape_brightness), vec3(0.0)) * tint.rgb * COLOR.rgb * visual_gain;
    if (crimson_blade) {
        float value = clamp(dot(sample_color.rgb * tint.rgb * COLOR.rgb, vec3(0.3, 0.5, 0.2)), 0.0, 1.0);
        vec3 tail = vec3(0.19, 0.008, 0.018);
        vec3 body = vec3(0.68, 0.028, 0.036);
        vec3 edge = vec3(0.98, 0.13, 0.055);
        float sweep = smoothstep(0.08, 0.92, UV.x);
        vec3 red = mix(tail, body, sweep);
        red = mix(red, edge, pow(value, 3.0) * pow(sin(clamp(UV.y, 0.0, 1.0) * 3.14159265), 6.0) * 0.6);
        ALBEDO = mix(red, tail, life_phase * 0.55) * visual_gain;
    }
    float opacity = sample_color.a * tint.a * COLOR.a * mix(1.0, mask, shape_alpha_weight);
    if (use_opacity_mask) {
        vec4 source_mask = texture(opacity_mask, clamp(UV * mask_uv_scale + mask_uv_offset, vec2(0.0), vec2(1.0)));
        opacity *= pow(max(source_mask.r * source_mask.a, 0.0), mask_power);
    }
    if (edge_feather.x > 0.0 || edge_feather.y > 0.0) {
        vec2 edge = min(UV, vec2(1.0) - UV);
        vec2 feather = smoothstep(vec2(0.0), max(edge_feather, vec2(0.0001)), edge);
        opacity *= feather.x * feather.y;
    }
    if (reconstructed_ribbon) {
        float width = clamp(UV.y, 0.0, 1.0);
        float along = clamp(UV.x, 0.0, 1.0);
        float feather = pow(max(sin(width * 3.14159265), 0.0), 1.5);
        feather *= smoothstep(0.0, 0.08, along) * (1.0 - smoothstep(0.92, 1.0, along));
        opacity *= feather * 0.28;
        ALBEDO *= 1.35;
    }
    if (reconstructed_water_shell) {
        float feather = smoothstep(0.0, 0.1, min(UV.y, 1.0 - UV.y));
        opacity *= mix(0.12, 0.28, feather);
        ALBEDO *= 1.15;
    }
    if (reconstructed_water_splash) {
        float feather = smoothstep(0.0, 0.24, min(UV.y, 1.0 - UV.y));
        opacity *= feather * 0.16;
    }
    ALPHA = clamp(opacity, 0.0, 1.0);
}
