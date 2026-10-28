shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform sampler2D main_texture : source_color, hint_default_white, repeat_enable;
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
uniform float ground_feather = 0.0;
uniform float ground_level = 0.0;
uniform bool billboard = false;
uniform bool vertical_billboard = false;
uniform bool stretched_billboard = false;
uniform float stretch_length = 1.0;
uniform float stretch_velocity = 0.0;
uniform float stretch_speed = 0.0;
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
uniform bool source_shapes = false;
uniform bool source_polar_uv = false;
uniform float clock = 0.0;
uniform float timing_seed = 0.0;
uniform vec4 source_tint : source_color = vec4(1.0);
uniform float source_alpha = 1.0;
uniform bool source_rim = false;
uniform int source_cull = 0;
uniform vec4 source_rim_color : source_color = vec4(1.0);
uniform vec3 source_rim_shape = vec3(0.0, 1.0, 1.0);
uniform vec3 source_rim_blend = vec3(1.0, 1.0, 0.0);
uniform vec4 shape1_st = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 shape2_st = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 shape3_st = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec2 shape1_wrap = vec2(0.0);
uniform vec2 shape2_wrap = vec2(0.0);
uniform vec2 shape3_wrap = vec2(0.0);
uniform vec4 shape1_color : source_color = vec4(1.0);
uniform vec4 shape2_color : source_color = vec4(1.0);
uniform vec4 shape3_color : source_color = vec4(1.0);
uniform bool shape1_color_mode = false;
uniform bool shape2_color_mode = false;
uniform bool shape3_color_mode = false;
uniform float shape1_weight = 1.0;
uniform float shape2_weight = 1.0;
uniform float shape3_weight = 1.0;
uniform bool use_shape2 = false;
uniform bool use_shape3 = false;
uniform sampler2D shape2_texture : source_color, hint_default_white, repeat_enable;
uniform sampler2D shape3_texture : source_color, hint_default_white, repeat_enable;
uniform vec2 shape1_scroll = vec2(0.0);
uniform vec2 shape2_scroll = vec2(0.0);
uniform vec2 shape3_scroll = vec2(0.0);
uniform float shape1_stream_offset = 0.0;
uniform float shape2_stream_offset = 0.0;
uniform float shape3_stream_offset = 0.0;
uniform vec2 shape1_rotation = vec2(0.0);
uniform vec2 shape2_rotation = vec2(0.0);
uniform vec2 shape3_rotation = vec2(0.0);
uniform vec2 shape1_contrast = vec2(1.0, 0.0);
uniform vec2 shape2_contrast = vec2(1.0, 0.0);
uniform vec2 shape3_contrast = vec2(1.0, 0.0);
uniform sampler2D shape1_distort : hint_default_black, repeat_enable;
uniform sampler2D shape2_distort : hint_default_black, repeat_enable;
uniform sampler2D shape3_distort : hint_default_black, repeat_enable;
uniform vec4 shape1_distort_st = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 shape2_distort_st = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec4 shape3_distort_st = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec2 shape1_distort_wrap = vec2(0.0);
uniform vec2 shape2_distort_wrap = vec2(0.0);
uniform vec2 shape3_distort_wrap = vec2(0.0);
uniform vec2 shape1_distort_scroll = vec2(0.0);
uniform vec2 shape2_distort_scroll = vec2(0.0);
uniform vec2 shape3_distort_scroll = vec2(0.0);
uniform float shape1_distort_amount = 0.0;
uniform float shape2_distort_amount = 0.0;
uniform float shape3_distort_amount = 0.0;
uniform bool use_shape1_mask = false;
uniform sampler2D shape1_mask : hint_default_white, repeat_enable;
uniform vec4 shape1_mask_st = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec2 shape1_mask_wrap = vec2(0.0);
uniform float shape1_mask_power = 1.0;
uniform bool use_source_mask = false;
uniform sampler2D source_mask : hint_default_white, repeat_enable;
uniform vec4 source_mask_st = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec2 source_mask_wrap = vec2(0.0);
uniform float source_mask_power = 1.0;
uniform bool source_soft_particles = false;
uniform float source_soft_factor = 1.0;
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D source_distort : hint_default_black, repeat_enable;
uniform vec4 source_distort_st = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec2 source_distort_wrap = vec2(0.0);
uniform vec2 source_distort_scroll = vec2(0.0);
uniform float source_distort_amount = 0.0;
uniform sampler2D source_fade : hint_default_white, repeat_enable;
uniform vec4 source_fade_st = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec2 source_fade_wrap = vec2(0.0);
uniform bool use_source_fade = false;
uniform bool source_fade_input = false;
uniform bool source_fade_vertex_alpha = false;
uniform float source_fade_amount = -0.1;
uniform float source_fade_power = 1.0;
uniform float source_fade_transition = 0.075;
uniform vec2 source_fade_scroll = vec2(0.0);
uniform sampler2D source_burn : source_color, hint_default_white, repeat_enable;
uniform vec4 source_burn_st = vec4(1.0, 1.0, 0.0, 0.0);
uniform vec2 source_burn_wrap = vec2(0.0);
uniform bool use_source_burn = false;
uniform vec4 source_burn_color : source_color = vec4(1.0);
uniform float source_burn_width = 0.01;
uniform float source_burn_glow = 0.0;
uniform sampler2D custom_stream0 : hint_default_black, repeat_disable;
uniform sampler2D custom_stream1 : hint_default_black, repeat_disable;
uniform bool use_custom_stream0 = false;
uniform bool use_custom_stream1 = false;
varying float animation_frame;
varying float life_phase;
varying float world_height;
varying vec2 stream0;
varying vec2 stream1;
varying vec3 rim_normal;
varying vec3 rim_view;

vec2 signed_fraction(vec2 value) {
    return sign(value) * fract(abs(value));
}

float source_axis(float value, float wrap, float half_texel) {
    if (wrap < 0.5) return value;
    if (wrap > 2.5) value = abs(value);
    else if (wrap > 1.5) value = 1.0 - abs(1.0 - mod(value, 2.0));
    return clamp(value, half_texel, 1.0 - half_texel);
}

vec4 source_sample(sampler2D map, vec2 uv, vec2 wrap) {
    vec2 half_texel = 0.5 / vec2(textureSize(map, 0));
    return texture(map, vec2(source_axis(uv.x, wrap.x, half_texel.x), source_axis(uv.y, wrap.y, half_texel.y)));
}

vec2 source_uv(vec2 uv, vec4 st, vec2 scroll, vec2 rotation, float stream_offset) {
    vec2 centered = (uv - vec2(0.5)) * st.xy;
    float angle = rotation.x + (clock + timing_seed + stream0.x) * rotation.y;
    float c = cos(angle);
    float s = sin(angle);
    return mat2(vec2(c, s), vec2(-s, c)) * centered + st.xy * 0.5 + st.zw + signed_fraction(scroll * (clock + timing_seed + stream0.x)) + stream1 * stream_offset;
}

vec2 source_distortion(vec2 uv, sampler2D noise, vec4 st, vec2 scroll, float amount, vec2 wrap) {
    float value = source_sample(noise, uv * st.xy + st.zw + signed_fraction(scroll * (clock + 2.0 * (timing_seed + stream0.x))), wrap).r;
    return vec2((value - 0.5) * 0.2 * amount);
}

vec4 source_shape(vec4 sample_value, vec4 color, bool color_mode, vec2 contrast) {
    // Exact SHAPESHAPECOLOR variants store opacity in red and color in a uniform.
    if (color_mode) {
        float opacity = max(0.0, (sample_value.r - 0.5) * contrast.x + 0.5 + contrast.y);
        return vec4(color.rgb, opacity);
    }
    vec4 adjusted = sample_value * color;
    // Source RGBA variants grade RGB after tinting and preserve texture alpha.
    adjusted.rgb = max(vec3(0.0), (adjusted.rgb - vec3(0.5)) * contrast.x + vec3(0.5 + contrast.y));
    return adjusted;
}

vec2 sample_custom(sampler2D map, float phase) {
    float width = float(textureSize(map, 0).x);
    return texture(map, vec2((phase * (width - 1.0) + 0.5) / width, 0.5)).rg;
}

void vertex() {
    animation_frame = INSTANCE_CUSTOM.z;
    float phase = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
    life_phase = phase;
    stream0 = use_custom_stream0 ? sample_custom(custom_stream0, phase) : vec2(0.0);
    stream1 = use_custom_stream1 ? sample_custom(custom_stream1, phase) : vec2(0.0);
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
        float emitter_scale = (length(emitter_basis[0]) + length(emitter_basis[1]) + length(emitter_basis[2])) / 3.0;
        float particle_length = scale.y * stretch_length + stretch_speed * stretch_velocity * emitter_scale;
        MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(right * scale.x, 0.0), vec4(direction * particle_length, 0.0), vec4(forward * scale.z, 0.0), MODEL_MATRIX[3]);
    } else {
        float angle = INSTANCE_CUSTOM.x;
        VERTEX.xy = mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle))) * VERTEX.xy;
    }
    MODELVIEW_MATRIX[3].xyz += (VIEW_MATRIX * vec4(world_offset, 0.0)).xyz;
    world_height = (INV_VIEW_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).y;
    if (source_rim) {
        vec3 rotated_normal = ry * rx * NORMAL;
        float angle = INSTANCE_CUSTOM.x;
        rotated_normal.xy = mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle))) * rotated_normal.xy;
        rim_normal = normalize(MODEL_NORMAL_MATRIX * rotated_normal);
        rim_view = PROJECTION_MATRIX[3].w == 0.0 ? normalize(CAMERA_POSITION_WORLD - (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz) : INV_VIEW_MATRIX[2].xyz;
    }
}

void fragment() {
    if ((source_cull == 2 && !FRONT_FACING) || (source_cull == 1 && FRONT_FACING)) discard;
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
        vec4 legacy_mask = texture(opacity_mask, clamp(UV * mask_uv_scale + mask_uv_offset, vec2(0.0), vec2(1.0)));
        opacity *= pow(max(legacy_mask.r * legacy_mask.a, 0.0), mask_power);
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
    if (source_shapes) {
        float seed = timing_seed + stream0.x;
        vec2 distorted_uv = UV;
        if (source_distort_amount != 0.0) {
            vec2 noise_uv = UV * source_distort_st.xy + source_distort_st.zw + signed_fraction(source_distort_scroll * (clock * 0.05 + seed));
            float distortion = (source_sample(source_distort, noise_uv, source_distort_wrap).r - 0.5) * 0.2 * source_distort_amount;
            distorted_uv += vec2(distortion);
        }
        vec2 shape_base = distorted_uv;
        if (source_polar_uv) {
            vec2 centered = distorted_uv - vec2(0.5);
            shape_base = vec2(atan(centered.y, centered.x) / 6.28318530718 + 0.5, length(centered) * 2.0);
        }
        vec2 primary_uv = source_uv(shape_base, shape1_st, shape1_scroll, shape1_rotation, shape1_stream_offset);
        primary_uv += source_distortion(UV, shape1_distort, shape1_distort_st, shape1_distort_scroll, shape1_distort_amount, shape1_distort_wrap);
        vec2 source_sheet_uv = (primary_uv + frame_cell) / sheet;
        vec4 first_sample = source_sample(main_texture, source_sheet_uv, shape1_wrap);
        vec4 first_shape = source_shape(first_sample, shape1_color, shape1_color_mode, shape1_contrast);
        vec4 combined = first_shape;
        if (use_shape2 || use_shape3) combined *= shape1_weight;
        if (use_shape2) {
            vec2 shape_uv = source_uv(shape_base, shape2_st, shape2_scroll, shape2_rotation, shape2_stream_offset);
            shape_uv += source_distortion(UV, shape2_distort, shape2_distort_st, shape2_distort_scroll, shape2_distort_amount, shape2_distort_wrap);
            combined *= source_shape(source_sample(shape2_texture, shape_uv, shape2_wrap), shape2_color, shape2_color_mode, shape2_contrast) * shape2_weight;
        }
        if (use_shape3) {
            vec2 shape_uv = source_uv(shape_base, shape3_st, shape3_scroll, shape3_rotation, shape3_stream_offset);
            shape_uv += source_distortion(UV, shape3_distort, shape3_distort_st, shape3_distort_scroll, shape3_distort_amount, shape3_distort_wrap);
            combined *= source_shape(source_sample(shape3_texture, shape_uv, shape3_wrap), shape3_color, shape3_color_mode, shape3_contrast) * shape3_weight;
        }
        combined.a = clamp(combined.a, 0.0, 1.0);
        if (use_shape1_mask) {
            float first_mask = pow(max(source_sample(shape1_mask, distorted_uv * shape1_mask_st.xy + shape1_mask_st.zw, shape1_mask_wrap).r, 0.0), shape1_mask_power);
            combined = mix(combined, first_shape, first_mask);
        }
        if (use_source_mask) {
            vec4 source_mask_value = source_sample(source_mask, distorted_uv * source_mask_st.xy + source_mask_st.zw, source_mask_wrap);
            combined.a *= pow(max(min(source_mask_value.r, source_mask_value.a), 0.0), source_mask_power);
        }
        if (source_soft_particles) {
            float depth = textureLod(scene_depth, SCREEN_UV, 0.0).r;
            vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
            if (OUTPUT_IS_SRGB) ndc.z = depth * 2.0 - 1.0;
            vec4 background_view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
            float difference = -background_view.z / background_view.w + VERTEX.z;
            combined.a *= clamp(difference * source_soft_factor, 0.0, 1.0);
        }
        ALBEDO = combined.rgb * source_tint.rgb * COLOR.rgb * visual_gain;
        opacity = combined.a * COLOR.a * source_alpha;
        if (source_rim) {
            // Exact APK RIM_ON GLES variant: Fresnel shape, additive/multiplicative blend, alpha erosion.
            float rim = clamp(source_rim_shape.y * pow(max(1.0 - abs(dot(rim_normal, rim_view)), 0.0), source_rim_shape.z) + source_rim_shape.x, 0.0, 1.0);
            vec3 glow = rim * source_rim_color.rgb * source_rim_blend.x * visual_gain;
            ALBEDO = mix(ALBEDO * (vec3(1.0) + glow), ALBEDO + glow, source_rim_blend.y);
            opacity *= 1.0 - rim * source_rim_blend.z;
        }
        if (use_source_fade) {
            vec2 fade_base = distorted_uv + vec2(seed) + signed_fraction(source_fade_scroll * (clock + seed));
            float fade_sample = source_sample(source_fade, fade_base * source_fade_st.xy + source_fade_st.zw, source_fade_wrap).r;
            float fade_vertex_alpha = source_fade_vertex_alpha ? COLOR.a : 0.0;
            float fade_value = clamp(1.0 - fade_vertex_alpha + source_fade_amount - (source_fade_input ? stream0.y : 0.0), 0.0, 1.0);
            float threshold = fade_sample + 1.0 - 2.0 * min(pow(fade_value, source_fade_power), 1.0);
            float transition = max((1.0 - pow(1.0 - fade_value, 5.0)) * source_fade_transition, 0.01);
            float fade_alpha = smoothstep(0.0, transition, threshold);
            if (use_source_burn) {
                float burn_edge = fade_alpha - smoothstep(0.0, transition + source_burn_width, threshold);
                vec3 burn = source_sample(source_burn, fade_base * source_burn_st.xy + source_burn_st.zw, source_burn_wrap).rgb;
                ALBEDO += burn * burn_edge * source_burn_color.rgb * source_burn_glow * first_shape.a * COLOR.a * visual_gain;
            }
            opacity *= fade_alpha;
        }
    }
    if (ground_feather > 0.0) opacity *= smoothstep(ground_level, ground_level + ground_feather, world_height);
    ALPHA = clamp(opacity, 0.0, 1.0);
}
