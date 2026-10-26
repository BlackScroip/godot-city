extends RefCounted

const MODEL_SHADER = preload("res://scripts/presentation/recovered_model.gdshader")
const FLOATS = {"_Alpha": "source_alpha", "_TimingSeed": "timing_seed", "_ShapeColorWeight": "shape_weight", "_Shape2ColorWeight": "shape2_weight", "_FadeAmount": "source_fade_amount", "_FadePower": "source_fade_power", "_FadeTransition": "source_fade_transition", "_FadeBurnWidth": "source_burn_width", "_FadeBurnGlow": "source_burn_glow", "_AlphaCutoffValue": "alpha_cutoff", "_RimPower": "rim_power", "_RimScale": "rim_scale", "_RimBias": "rim_bias", "_RimIntensity": "rim_intensity", "_RimAddAmount": "rim_add", "_RimErodesAlpha": "rim_erode"}
const COLORS = {"_Color": "source_tint", "_ShapeColor": "shape_color", "_Shape2Color": "shape2_color", "_FadeBurnColor": "source_burn_color", "_RimColor": "rim_color"}
const MAPS = {"_MainTex": "main", "_Shape2Tex": "shape2", "_Shape2DistortTex": "shape2_distort", "_FadeTex": "source_fade", "_FadeBurnTex": "source_burn"}
static var _additive: Shader
var materials: Dictionary = {}
var controllers: Array[Dictionary] = []
var source: Dictionary = {}

static func sample_curve(curve: Dictionary, time: float) -> float:
	match str(curve.get("kind", "constant")):
		"streamed":
			var keys: Array = curve.get("keys", [])
			if keys.is_empty(): return 0.0
			var selected: Array = keys[0]
			for key in keys:
				if float(key[0]) > time: break
				selected = key
			var delta = maxf(0, time - float(selected[0])) if float(selected[0]) > -1e10 else 0.0
			return ((float(selected[1]) * delta + float(selected[2])) * delta + float(selected[3])) * delta + float(selected[4])
		"dense":
			var values: Array = curve.get("values", [])
			if values.is_empty(): return 0.0
			var frame = clampf((time - float(curve.get("begin", 0))) * float(curve.get("rate", 1)), 0, values.size() - 1)
			var index = int(floor(frame))
			return lerpf(float(values[index]), float(values[mini(index + 1, values.size() - 1)]), frame - index)
	return float(curve.get("value", 0))

static func _material(data: Dictionary, textures: Dictionary) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	if data.get("blend", "") == "add":
		if _additive == null:
			_additive = Shader.new()
			_additive.code = MODEL_SHADER.code.replace("blend_mix", "blend_add")
		material.shader = _additive
	else: material.shader = MODEL_SHADER
	material.resource_name = str(data.get("name", ""))
	var floats: Dictionary = data.get("source_floats", {})
	for property in FLOATS:
		if floats.has(property): material.set_shader_parameter(FLOATS[property], float(floats[property]))
	for property in COLORS:
		if data.get("source_colors", {}).has(property): material.set_shader_parameter(COLORS[property], _color(data.source_colors[property]))
	for property in MAPS:
		var prefix: String = MAPS[property]
		var entry: Dictionary = {}
		for candidate in data.get("textures", []):
			if candidate.property == property: entry = candidate; break
		var path = str(entry.get("texture", ""))
		if not path.is_empty():
			if not textures.has(path) and ResourceLoader.exists(path): textures[path] = load(path)
			material.set_shader_parameter(prefix + "_texture" if prefix in ["main", "shape2"] else prefix, textures.get(path))
		material.set_shader_parameter(prefix + "_st", _st(entry))
		material.set_shader_parameter(prefix + "_wrap", Vector2(float(entry.get("wrap", {}).get("x", 0)), float(entry.get("wrap", {}).get("y", 0))))
	material.set_shader_parameter("shape_scroll", Vector2(float(floats.get("_ShapeXSpeed", 0)), float(floats.get("_ShapeYSpeed", 0))))
	material.set_shader_parameter("shape2_scroll", Vector2(float(floats.get("_Shape2XSpeed", 0)), float(floats.get("_Shape2YSpeed", 0))))
	material.set_shader_parameter("source_fade_scroll", Vector2(float(floats.get("_FadeScrollXSpeed", 0)), float(floats.get("_FadeScrollYSpeed", 0))))
	var keywords: Array = data.get("keywords", [])
	material.set_shader_parameter("shape2_distort_scroll", Vector2(float(floats.get("_Shape2DistortXSpeed", 0)), float(floats.get("_Shape2DistortYSpeed", 0))))
	material.set_shader_parameter("shape2_distort_amount", float(floats.get("_Shape2DistortAmount", 0)) if "SHAPE2DISTORT_ON" in keywords else 0.0)
	material.set_shader_parameter("shape2_contrast", Vector2(float(floats.get("_Shape2Contrast", 1)), float(floats.get("_Shape2Brightness", 0))) if "SHAPE2CONTRAST_ON" in keywords else Vector2(1, 0))
	for pair in [["SHAPE2_ON", "use_shape2"], ["FADEBURN_ON", "use_source_burn"], ["ALPHACUTOFF_ON", "use_alpha_cutoff"], ["RIM_ON", "use_rim"]]: material.set_shader_parameter(pair[1], pair[0] in keywords)
	return material

static func _color(value: Dictionary) -> Color:
	return Color(float(value.get("r", 1)), float(value.get("g", 1)), float(value.get("b", 1)), float(value.get("a", 1)))

static func _st(value: Dictionary) -> Vector4:
	return Vector4(float(value.get("scale", {}).get("x", 1)), float(value.get("scale", {}).get("y", 1)), float(value.get("offset", {}).get("x", 0)), float(value.get("offset", {}).get("y", 0)))

func configure(visual: Node3D, definition: Dictionary, textures: Dictionary) -> void:
	source = definition
	for renderer in definition.get("renderers", []):
		var slots: Array[ShaderMaterial] = []
		for source_id in renderer.get("materials", []):
			var data: Dictionary = definition.get("materials", {}).get(source_id, {})
			if data.is_empty(): continue
			var material = _material(data, textures)
			for mesh: MeshInstance3D in visual.find_children("*", "MeshInstance3D", true, false):
				for surface in mesh.mesh.get_surface_count():
					var existing = mesh.get_active_material(surface)
					if existing != null and existing.resource_name == data.get("name", ""):
						mesh.set_surface_override_material(surface, material)
			slots.append(material)
		materials[str(renderer.transform_id)] = slots
	for controller in definition.get("controllers", []): controllers.append({"source": controller, "clip": {}, "age": 0.0})
	play("")

func play(source_name: String) -> void:
	for controller in controllers:
		var wanted = str(controller.source.get("default", "")) if source_name.is_empty() else source_name
		for name in controller.source.get("clips", {}):
			if str(name).to_lower() != wanted.to_lower(): continue
			controller.clip = controller.source.clips[name]
			controller.age = 0.0
			break
	apply()

func advance(delta: float) -> void:
	for controller in controllers: controller.age += delta
	apply()

func apply() -> void:
	for controller in controllers:
		var clip: Dictionary = controller.clip
		if clip.is_empty(): continue
		var duration = float(clip.get("duration", 0))
		var time = fmod(float(controller.age), duration) if clip.get("loop", false) and duration > 0 else minf(float(controller.age), duration)
		time += float(clip.get("start", 0))
		for track in clip.get("tracks", []):
			var value = sample_curve(track.curve, time)
			for material in materials.get(str(track.renderer), []):
				if track.field == "source_floats" and FLOATS.has(track.property): material.set_shader_parameter(FLOATS[track.property], value)
				elif track.field == "source_colors" and COLORS.has(track.property):
					var color: Color = material.get_shader_parameter(COLORS[track.property])
					color[int(track.component)] = value
					material.set_shader_parameter(COLORS[track.property], color)
				elif track.field == "texture_st" and MAPS.has(str(track.property).trim_suffix("_ST")):
					var uniform_name: String = MAPS[str(track.property).trim_suffix("_ST")] + "_st"
					var st: Vector4 = material.get_shader_parameter(uniform_name)
					st[int(track.component)] = value
					material.set_shader_parameter(uniform_name, st)
	for slots in materials.values():
		for material in slots: material.set_shader_parameter("clock", float(controllers[0].age) if not controllers.is_empty() else 0.0)
