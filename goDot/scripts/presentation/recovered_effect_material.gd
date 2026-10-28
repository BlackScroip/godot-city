extends RefCounted

const PARTICLE = preload("res://scripts/presentation/recovered_particle.gdshader")
static var _additive: Shader

static func create(source: Dictionary, textures: Dictionary) -> ShaderMaterial:
	var result := ShaderMaterial.new()
	if source.get("blend", "") == "add":
		if _additive == null:
			_additive = Shader.new()
			_additive.code = PARTICLE.code.replace("blend_mix", "blend_add")
		result.shader = _additive
	else:
		result.shader = PARTICLE
	apply_source(result, source, textures)
	return result

static func _texture(path: String, textures: Dictionary) -> Texture2D:
	if path.is_empty(): return null
	if not textures.has(path) and ResourceLoader.exists(path): textures[path] = load(path)
	return textures.get(path)

static func _color(value: Dictionary) -> Color:
	return Color(value.get("r", 1.0), value.get("g", 1.0), value.get("b", 1.0), value.get("a", 1.0))

static func _st(value: Dictionary) -> Vector4:
	var scale: Dictionary = value.get("scale", {"x": 1.0, "y": 1.0})
	var offset: Dictionary = value.get("offset", {})
	return Vector4(scale.get("x", 1.0), scale.get("y", 1.0), offset.get("x", 0.0), offset.get("y", 0.0))

static func _wrap(value: Dictionary) -> Vector2:
	var wrap: Dictionary = value.get("wrap", {})
	return Vector2(wrap.get("x", 0), wrap.get("y", 0))

static func apply_source(material: ShaderMaterial, source: Dictionary, textures: Dictionary) -> void:
	if not source.has("source_floats") or not str(source.get("shader", "")).begins_with("AllIn1Vfx/"): return
	var floats: Dictionary = source.source_floats
	var colors: Dictionary = source.get("source_colors", {})
	var keywords: Array = source.get("keywords", [])
	var maps: Dictionary = {}
	for entry in source.get("textures", []): maps[str(entry.property)] = entry
	material.set_shader_parameter("source_shapes", true)
	material.set_shader_parameter("source_polar_uv", "POLARUV_ON" in keywords)
	material.set_shader_parameter("source_tint", _color(colors.get("_Color", {})))
	material.set_shader_parameter("source_alpha", float(floats.get("_Alpha", 1.0)))
	if str(source.get("name", "")) == "mat_fx_24071901_void_sphere":
		material.set_shader_parameter("source_cull", int(floats.get("_CullingOption", 0)))
		material.set_shader_parameter("source_rim", "RIM_ON" in keywords)
		material.set_shader_parameter("source_rim_color", _color(colors.get("_RimColor", {})))
		material.set_shader_parameter("source_rim_shape", Vector3(floats.get("_RimBias", 0.0), floats.get("_RimScale", 1.0), floats.get("_RimPower", 1.0)))
		material.set_shader_parameter("source_rim_blend", Vector3(floats.get("_RimIntensity", 1.0), floats.get("_RimAddAmount", 1.0), floats.get("_RimErodesAlpha", 0.0)))
	material.set_shader_parameter("timing_seed", float(floats.get("_TimingSeed", 0.0)))
	for i in 3:
		var index := str(i + 1)
		var prefix := "_Shape" + ("" if i == 0 else index)
		var texture_property := "_MainTex" if i == 0 else prefix + "Tex"
		var texture_uniform := "main_texture" if i == 0 else "shape" + index + "_texture"
		var shape := "shape" + index
		var primary: Dictionary = maps.get(texture_property, {})
		material.set_shader_parameter(texture_uniform, _texture(str(primary.get("texture", "")), textures))
		material.set_shader_parameter(shape + "_st", _st(primary))
		material.set_shader_parameter(shape + "_wrap", _wrap(primary))
		material.set_shader_parameter(shape + "_color", _color(colors.get(prefix + "Color", {})))
		material.set_shader_parameter(shape + "_color_mode", "SHAPE" + index + "SHAPECOLOR_ON" in keywords)
		material.set_shader_parameter(shape + "_weight", float(floats.get(prefix + "ColorWeight", 1.0)))
		material.set_shader_parameter(shape + "_scroll", Vector2(floats.get(prefix + "XSpeed", 0.0), floats.get(prefix + "YSpeed", 0.0)))
		material.set_shader_parameter(shape + "_stream_offset", float(floats.get("_OffsetSh" + index, 0.0)) if "OFFSETSTREAM_ON" in keywords else 0.0)
		material.set_shader_parameter(shape + "_rotation", Vector2(floats.get(prefix + "RotationOffset", 0.0), floats.get(prefix + "RotationSpeed", 0.0)) if "SHAPE" + index + "ROTATE_ON" in keywords else Vector2.ZERO)
		material.set_shader_parameter(shape + "_contrast", Vector2(floats.get(prefix + "Contrast", 1.0), floats.get(prefix + "Brightness", 0.0)) if "SHAPE" + index + "CONTRAST_ON" in keywords else Vector2(1.0, 0.0))
		var distort: Dictionary = maps.get(prefix + "DistortTex", {})
		material.set_shader_parameter(shape + "_distort", _texture(str(distort.get("texture", "")), textures))
		material.set_shader_parameter(shape + "_distort_st", _st(distort))
		material.set_shader_parameter(shape + "_distort_wrap", _wrap(distort))
		material.set_shader_parameter(shape + "_distort_scroll", Vector2(floats.get(prefix + "DistortXSpeed", 0.0), floats.get(prefix + "DistortYSpeed", 0.0)))
		material.set_shader_parameter(shape + "_distort_amount", float(floats.get(prefix + "DistortAmount", 0.0)) if "SHAPE" + index + "DISTORT_ON" in keywords else 0.0)
	material.set_shader_parameter("use_shape2", "SHAPE2_ON" in keywords)
	material.set_shader_parameter("use_shape3", "SHAPE3_ON" in keywords)
	var mask: Dictionary = maps.get("_MaskTex", {})
	material.set_shader_parameter("source_mask", _texture(str(mask.get("texture", "")), textures))
	material.set_shader_parameter("source_mask_st", _st(mask))
	material.set_shader_parameter("source_mask_wrap", _wrap(mask))
	material.set_shader_parameter("source_mask_power", float(floats.get("_MaskPow", 1.0)))
	material.set_shader_parameter("use_source_mask", "MASK_ON" in keywords)
	var first_mask: Dictionary = maps.get("_Shape1MaskTex", {})
	material.set_shader_parameter("shape1_mask", _texture(str(first_mask.get("texture", "")), textures))
	material.set_shader_parameter("shape1_mask_st", _st(first_mask))
	material.set_shader_parameter("shape1_mask_wrap", _wrap(first_mask))
	material.set_shader_parameter("shape1_mask_power", float(floats.get("_Shape1MaskPow", 1.0)))
	material.set_shader_parameter("use_shape1_mask", "SHAPE1MASK_ON" in keywords)
	material.set_shader_parameter("source_soft_particles", "SOFTPART_ON" in keywords)
	material.set_shader_parameter("source_soft_factor", float(floats.get("_SoftFactor", 1.0)))
	var distortion: Dictionary = maps.get("_DistortTex", {})
	material.set_shader_parameter("source_distort", _texture(str(distortion.get("texture", "")), textures))
	material.set_shader_parameter("source_distort_st", _st(distortion))
	material.set_shader_parameter("source_distort_wrap", _wrap(distortion))
	material.set_shader_parameter("source_distort_scroll", Vector2(floats.get("_DistortTexXSpeed", 0.0), floats.get("_DistortTexYSpeed", 0.0)))
	material.set_shader_parameter("source_distort_amount", float(floats.get("_DistortAmount", 0.0)) if "DISTORT_ON" in keywords else 0.0)
	for pair in [["_FadeTex", "source_fade"], ["_FadeBurnTex", "source_burn"]]:
		var entry: Dictionary = maps.get(pair[0], {})
		material.set_shader_parameter(pair[1], _texture(str(entry.get("texture", "")), textures))
		material.set_shader_parameter(pair[1] + "_st", _st(entry))
		material.set_shader_parameter(pair[1] + "_wrap", _wrap(entry))
	material.set_shader_parameter("use_source_fade", "FADE_ON" in keywords)
	material.set_shader_parameter("source_fade_input", "ALPHAFADEINPUTSTREAM_ON" in keywords)
	material.set_shader_parameter("source_fade_amount", float(floats.get("_FadeAmount", -0.1)))
	material.set_shader_parameter("source_fade_power", float(floats.get("_FadePower", 1.0)))
	material.set_shader_parameter("source_fade_transition", float(floats.get("_FadeTransition", 0.075)))
	material.set_shader_parameter("source_fade_scroll", Vector2(floats.get("_FadeScrollXSpeed", 0.0), floats.get("_FadeScrollYSpeed", 0.0)))
	material.set_shader_parameter("use_source_burn", "FADEBURN_ON" in keywords)
	material.set_shader_parameter("source_burn_color", _color(colors.get("_FadeBurnColor", {})))
	material.set_shader_parameter("source_burn_glow", float(floats.get("_FadeBurnGlow", 0.0)))
	material.set_shader_parameter("source_burn_width", float(floats.get("_FadeBurnWidth", 0.01)))
