shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled;

uniform sampler2D forest_atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D grass_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D original_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 original_tint : source_color = vec4(1.0);
uniform vec3 original_uv_scale = vec3(1.0);
uniform vec3 original_uv_offset = vec3(0.0);
uniform int surface_kind = 0;
uniform bool use_alpha = false;
uniform float alpha_cutoff = 0.4;
uniform float tile_scale = 0.4;
varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

vec3 tile(vec2 uv, vec2 quadrant) {
	// Mirrored repetition keeps independently generated tile edges continuous.
	vec2 mirrored = 1.0 - abs(mod(uv, 2.0) - 1.0);
	return texture(forest_atlas, quadrant * 0.5 + vec2(0.002) + mirrored * 0.496).rgb;
}

vec3 projected(vec2 quadrant) {
	vec3 weights = pow(abs(world_normal), vec3(4.0));
	weights /= max(dot(weights, vec3(1.0)), 0.001);
	vec3 p = world_position * tile_scale;
	return tile(vec2(p.z, -p.y), quadrant) * weights.x
		+ tile(p.xz, quadrant) * weights.y
		+ tile(vec2(p.x, -p.y), quadrant) * weights.z;
}

void fragment() {
	vec4 source = texture(original_texture, UV * original_uv_scale.xy + original_uv_offset.xy);
	vec3 original = source.rgb * original_tint.rgb;
	float green = smoothstep(0.015, 0.12, source.g - max(source.r * 0.92, source.b));
	float value = dot(source.rgb, vec3(0.2126, 0.7152, 0.0722));
	vec3 paint;
	if (surface_kind == 0) {
		// Keep the recovered terrain's paths and painted ground boundaries.
		vec3 grass = texture(grass_texture, world_position.xz * tile_scale).rgb;
		grass = mix(vec3(0.065, 0.15, 0.115), grass, 0.38);
		vec3 path = mix(vec3(0.13, 0.16, 0.145), mix(vec3(dot(original, vec3(0.333))), original, 0.22), 0.40);
		paint = mix(path, grass, green * 0.94);
	} else if (surface_kind == 1) {
		paint = projected(vec2(1.0, 0.0));
	} else if (surface_kind == 2) {
		paint = mix(projected(vec2(0.0, 1.0)), original * vec3(0.65, 0.83, 0.95), 0.30);
	} else if (surface_kind == 3) {
		paint = projected(vec2(1.0));
	} else if (surface_kind == 4) {
		paint = mix(projected(vec2(1.0, 0.0)), projected(vec2(1.0)), green);
	} else {
		paint = mix(vec3(0.055, 0.16, 0.105), vec3(0.25, 0.45, 0.29), clamp(value * 1.8, 0.0, 1.0));
		paint = mix(paint, texture(grass_texture, world_position.xz * tile_scale).rgb, 0.35);
	}
	float foliage = surface_kind == 3 ? 1.0 : surface_kind == 4 ? green : 0.0;
	if (foliage > 0.0) {
		vec3 leaf_fill = mix(vec3(0.055, 0.15, 0.12), vec3(0.15, 0.29, 0.19), clamp(value * 2.0, 0.0, 1.0));
		paint = mix(paint, mix(leaf_fill, paint, 0.28), foliage);
		vec3 up = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
		NORMAL = normalize(mix(FRONT_FACING ? NORMAL : -NORMAL, up, foliage * 0.8));
	}
	ALBEDO = paint * (surface_kind == 0 ? 1.0 : mix(0.78, 1.18, clamp(value * 1.6, 0.0, 1.0)));
	ROUGHNESS = 1.0;
	// A subtle diffuse fill keeps dense leaf cards legible under the canopy.
	EMISSION = (surface_kind == 3 || surface_kind == 4) ? paint * 0.13 : vec3(0.0);
	SPECULAR = 0.0;
	ALPHA = use_alpha ? source.a * original_tint.a : 1.0;
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
}
