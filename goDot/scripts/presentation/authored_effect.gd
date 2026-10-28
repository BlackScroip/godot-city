extends Node3D

var emitters: Array[Dictionary] = []
var retained_particles: Array[Dictionary] = []
var model_players: Array[Dictionary] = []
var model_styles: Array[Dictionary] = []
const ModelMaterialAnimation = preload("res://scripts/presentation/model_material_animation.gd")
const Descriptors = preload("res://scripts/presentation/effect_descriptors.gd")
const ChestSmokeVelocity = preload("res://scripts/presentation/chest_smoke_velocity.gd")
const RetainedParticle = preload("res://scripts/presentation/retained_particle.gd")
var age := 0.0
var lifetime := 0.0
var unsupported: Array = []
var _running := false
static var _additive_shader: Shader
static var _material_libraries: Dictionary = {}
const CURVE_SAMPLES := 48
const FULL_PARTICLE_BUDGET := 384
const LOW_PARTICLE_BUDGET := 144
# Recovered MASK_ON bindings from the APK material bundle; import catalog stays intact.
const MATERIAL_MASKS = {
	"mat_fx_23082401_blast_blast_3.mat": {"texture": "res://assets/combat_presentation/9cafdfac0c122c38f74b.png", "offset": Vector2(-0.05, 0), "power": 0.8},
	"mat_fx_24091101_launch_diffusion.mat": {"texture": "res://assets/combat_presentation/449318b4ac3ba8d511e8.png"},
	"mat_fx_24091101_launch_flash.mat": {"texture": "res://assets/combat_presentation/53750ca0c17485c51e07.png"},
	"mat_fx_24091101_shrinkring.mat": {"texture": "res://assets/combat_presentation/449318b4ac3ba8d511e8.png"},
	"mat_fx_24091101_accumulation_line.mat": {"texture": "res://assets/combat_presentation/603e1340b0db06fc1a2b.png"},
	"mat_fx_24091101_accumulation_prickring.mat": {"texture": "res://assets/combat_presentation/449318b4ac3ba8d511e8.png", "power": 0.5},
	"mat_fx_24091101_blackhole_helix.mat": {"texture": "res://assets/combat_presentation/9cc55f2d30ccb495c974.png", "scale": Vector2(2, 0.3), "offset": Vector2(0, 0.25), "power": 5.0},
	"mat_fx_23090801_smoke.mat": {"texture": "res://assets/combat_presentation/641317696bfc904d13c7.png"},
	"mat_fx_23090801_launch_sidsmoke.mat": {"texture": "res://assets/combat_presentation/7cf02b384ffc2c006b64.png"},
	"mat_fx_26072501_accumulation1_qiliu.mat": {"texture": "res://assets/combat_presentation/36fb0793880a59c4c2e5.png", "power": 1.05}
}
const SOFT_BOUNDARY_MATERIALS = {
	"mat_fx_25011001_slash_fog.mat": Vector2(0.18, 0.24),
	"mat_fx_23090801_smoke.mat": Vector2(0.12, 0.16),
	"mat_fx_23090801_launch_sidsmoke.mat": Vector2(0.12, 0.16),
	"mat_fx_26072501_accumulation1_qiliu.mat": Vector2(0.12, 0.16),
	"mat_fx_24091101_around_airwave.mat": Vector2(0.12, 0.16),
	"mat_fx_24091101_blackhole_helix.mat": Vector2(0.12, 0.16),
	"mat_fx_24040801_smokewhite.mat": Vector2(0.45, 0.45),
	"mat_fx_25123101_sprint_airflow.mat": Vector2(0.3, 0.3),
	"mat_fx_25123101_spear_floorsmoke.mat": Vector2(0.3, 0.3),
	"mat_fx_25123101_sprint_sidesmoke.mat": Vector2(0.3, 0.3)
}
var particle_count := 0

static func scalar(value: Variant, fallback := 0.0) -> float:
	if value is float or value is int: return float(value)
	if value is Dictionary: return float(value.get("scalar", fallback))
	return fallback

static func lower_scalar(value: Variant, fallback := 0.0) -> float:
	if value is Dictionary and int(value.get("minMaxState", 0)) in [2, 3]: return float(value.get("minScalar", value.get("scalar", fallback)))
	return scalar(value, fallback)

static func scalar_range(value: Variant, fallback := 0.0) -> Vector2:
	var first := lower_scalar(value, fallback)
	var second := scalar(value, fallback)
	return Vector2(minf(first, second), maxf(first, second))

static func rgba(value: Dictionary, fallback := Color.WHITE) -> Color:
	return Color(float(value.get("r", fallback.r)), float(value.get("g", fallback.g)), float(value.get("b", fallback.b)), float(value.get("a", fallback.a)))

static func curve(value: Dictionary, multiplier := 1.0) -> Curve:
	var keys: Array = value.get("maxCurve", value).get("m_Curve", [])
	if keys.is_empty(): return null
	var result = Curve.new()
	var gain = scalar(value, 1.0) * multiplier
	result.min_value = -1024
	result.max_value = 1024
	for key in keys:
		result.add_point(Vector2(clampf(float(key.get("time", 0)), 0, 1), clampf(float(key.get("value", 1)) * gain, -1024, 1024)), float(key.get("inSlope", 0)) * gain, float(key.get("outSlope", 0)) * gain)
	return result

static func constant_curve(value: float) -> Curve:
	var result = Curve.new()
	result.min_value = minf(-1024, value)
	result.max_value = maxf(1024, value)
	result.add_point(Vector2(0, value))
	result.add_point(Vector2(1, value))
	return result

static func value_curve(value: Dictionary, fallback := 0.0) -> Curve:
	var result = curve(value)
	return result if result else constant_curve(scalar(value, fallback))

static func custom_stream(module: Dictionary, index: int) -> ImageTexture:
	var curves: Array[Curve] = []
	for component in 4:
		curves.append(value_curve(module.get("vector%d_%d" % [index, component], {})))
	var image := Image.create(CURVE_SAMPLES + 1, 1, false, Image.FORMAT_RGBAF)
	for sample_index in CURVE_SAMPLES + 1:
		var phase := float(sample_index) / CURVE_SAMPLES
		image.set_pixel(sample_index, 0, Color(curves[0].sample(phase), curves[1].sample(phase), curves[2].sample(phase), curves[3].sample(phase)))
	return ImageTexture.create_from_image(image)

static func _integrated_motion(module: Dictionary, duration: float) -> CurveXYZTexture:
	var texture = CurveXYZTexture.new()
	var modifier = value_curve(module.get("speedModifier", {}), 1.0)
	var axes: Array[Curve] = []
	for name in ["x", "y", "z"]:
		var source = value_curve(module.get(name, {}))
		var integrated = Curve.new()
		integrated.min_value = -1024
		integrated.max_value = 1024
		var distance := 0.0
		integrated.add_point(Vector2.ZERO)
		for i in range(1, CURVE_SAMPLES + 1):
			var t = float(i) / CURVE_SAMPLES
			var midpoint = (float(i) - 0.5) / CURVE_SAMPLES
			distance += source.sample(midpoint) * modifier.sample(midpoint) * duration / CURVE_SAMPLES
			integrated.add_point(Vector2(t, clampf(distance, -1024, 1024)))
		axes.append(integrated)
	texture.curve_x = axes[0]
	texture.curve_y = axes[1]
	texture.curve_z = axes[2]
	return texture

static func _layer_priority(layer: Dictionary) -> int:
	if RetainedParticle.handles(layer): return 3
	var name = str(layer.get("name", "")).to_lower()
	# Retain the attack silhouette before optional haze and scatter in reduced mode.
	if "smoke" in name or "dust" in name or "glow" in name: return 0
	if "particle" in name or "spark" in name or "debris" in name: return 1
	return 2

static func _uses_reconstructed_ribbon(layer: Dictionary, source: Dictionary) -> bool:
	if int(layer.get("renderer", {}).get("render_mode", 0)) != 4: return false
	if not bool(source.get("alpha_from_luminance", false)) or source.get("blend", "") == "add": return false
	var name = str(layer.get("name", "")).to_lower()
	return "slash" in name or "swept" in name or "trail" in name

static func _uses_reconstructed_water_shell(layer: Dictionary, source: Dictionary) -> bool:
	if int(layer.get("renderer", {}).get("render_mode", 0)) != 4 or source.get("blend", "") != "alpha": return false
	return _material_name(source) in ["mat_fx_23102601_bomb.mat", "mat_fx_23102601_bomblight.mat"]

static func _uses_reconstructed_water_splash(source: Dictionary) -> bool:
	if source.get("blend", "") != "alpha": return false
	return _material_name(source) in ["mat_fx_23110201_hit_prick.mat", "mat_fx_23102601_explode_prick.mat"]

static func _material_name(source: Dictionary) -> String:
	var name = str(source.get("name", ""))
	return name + ("" if name.ends_with(".mat") else ".mat") if not name.is_empty() else str(source.get("source", "")).get_file()

static func material_library(definition: Dictionary) -> Dictionary:
	definition = Descriptors.resolve(definition)
	var path = str(definition.get("material_library", ""))
	if path.is_empty(): return {}
	if Descriptors.handles_materials(path): return Descriptors.materials_for(definition)
	if not _material_libraries.has(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		_material_libraries[path] = parsed if parsed is Dictionary else {}
	return _material_libraries[path]

static func resolved_layers(definition: Dictionary) -> Array:
	definition = Descriptors.resolve(definition)
	var library = material_library(definition)
	var result: Array = []
	for source in definition.get("layers", []):
		var layer: Dictionary = source.duplicate()
		var materials: Array = []
		for value in source.get("materials", []):
			var material: Dictionary = library.get(str(value.get("reference", "")), {}) if value.has("reference") else value
			if not material.is_empty(): materials.append(material)
		layer["materials"] = materials
		result.append(layer)
	return result

static func gradient(value: Dictionary) -> Gradient:
	var raw: Dictionary = value.get("maxGradient", value.get("gradient", {}))
	var count = int(raw.get("m_NumColorKeys", 0))
	if count <= 0: return null
	var result = Gradient.new()
	if int(raw.get("m_Mode", 0)) == 1: result.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var offsets = PackedFloat32Array()
	var colors = PackedColorArray()
	for i in count:
		var color = rgba(raw.get("key%d" % i, {}))
		var t = float(raw.get("ctime%d" % i, 0)) / 65535.0
		var alpha_count = int(raw.get("m_NumAlphaKeys", 0))
		if alpha_count > 0:
			var previous_t := 0.0
			var previous_alpha = float(raw.get("key0", {}).get("a", 1))
			for j in alpha_count:
				var next_t = float(raw.get("atime%d" % j, 0)) / 65535.0
				var next_alpha = float(raw.get("key%d" % j, {}).get("a", 1))
				if t <= next_t:
					color.a = lerpf(previous_alpha, next_alpha, clampf((t - previous_t) / maxf(0.0001, next_t - previous_t), 0, 1))
					break
				color.a = next_alpha
				previous_t = next_t
				previous_alpha = next_alpha
		offsets.append(clampf(t, 0, 1))
		colors.append(color)
	result.offsets = offsets
	result.colors = colors
	# Unity alpha keys have their own times, independent of the RGB keys.
	var alpha_count = int(raw.get("m_NumAlphaKeys", 0))
	if alpha_count > 0:
		var rgb = result.duplicate()
		var times: Array[float] = []
		for offset in offsets: times.append(offset)
		for i in alpha_count:
			var at = clampf(float(raw.get("atime%d" % i, 0)) / 65535.0, 0, 1)
			if not times.has(at): times.append(at)
		times.sort()
		offsets.clear()
		colors.clear()
		for at in times:
			var color: Color = rgb.sample(at)
			color.a = float(raw.get("key0", {}).get("a", 1))
			for i in range(1, alpha_count):
				var left = float(raw.get("atime%d" % (i - 1), 0)) / 65535.0
				var right = float(raw.get("atime%d" % i, 0)) / 65535.0
				color.a = lerpf(float(raw.get("key%d" % (i - 1), {}).get("a", 1)), float(raw.get("key%d" % i, {}).get("a", 1)), clampf((at - left) / maxf(0.0001, right - left), 0, 1))
				if at <= right: break
			offsets.append(at)
			colors.append(color)
		result.offsets = offsets
		result.colors = colors
	return result

func configure(definition: Dictionary, low_quality: bool, textures: Dictionary, suppressed_layers: Array = []) -> void:
	definition = Descriptors.resolve(definition)
	var wolf_embedded := str(definition.get("source", "")).ends_with("/monster_senlinlangwang.prefab")
	unsupported = definition.get("unsupported", [])
	for model in definition.get("models", []):
		var path = str(model.get("scene", ""))
		if not ResourceLoader.exists(path): continue
		var packed = load(path)
		if not packed is PackedScene: continue
		var visual: Node3D = packed.instantiate()
		add_child(visual)
		if model.has("material_animation"):
			var runtime = ModelMaterialAnimation.new()
			runtime.configure(visual, model.material_animation, textures)
			model_styles.append({"path": get_path_to(visual), "definition": model.material_animation, "runtime": runtime})
		lifetime = maxf(lifetime, float(model.get("duration", 0.5)))
		for player: AnimationPlayer in visual.find_children("*", "AnimationPlayer", true, false):
			player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			for clip in model.get("animations", []):
				for name in player.get_animation_list():
					if str(name).get_file() == str(clip.get("name", "")):
						player.get_animation(name).loop_mode = Animation.LOOP_LINEAR if clip.get("loop", false) else Animation.LOOP_NONE
			model_players.append({"node": player, "path": get_path_to(player), "default": str(model.get("default_animation", "")), "aliases": model.get("aliases", {})})
	var layers: Array = resolved_layers(definition)
	layers.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return _layer_priority(left) > _layer_priority(right))
	var budget = LOW_PARTICLE_BUDGET if low_quality else FULL_PARTICLE_BUDGET
	var logical_emitter_count := 0
	for layer in layers:
		if str(layer.get("name", "")) in suppressed_layers: continue
		if not layer.get("active", true): continue
		if layer.get("materials", []).is_empty() or not layer.get("renderer", {}).get("enabled", true): continue
		if int(layer.get("renderer", {}).get("render_mode", 0)) == 5: continue
		if int(layer.get("renderer", {}).get("render_mode", 0)) == 4 and str(layer.get("mesh", "")).is_empty(): continue
		if logical_emitter_count >= (8 if low_quality else 18): break
		if particle_count >= budget: break
		var emission: Dictionary = layer.get("emission", {})
		if not emission.get("enabled", true): continue
		var node = Node3D.new()
		node.set_meta("source_layer", str(layer.get("name", "")))
		add_child(node)
		var transform_value = Transform3D.IDENTITY
		for item in layer.get("transform_chain", []):
			var q: Dictionary = item.get("rotation", {})
			var rotation_value = Quaternion(float(q.get("x", 0)), float(q.get("y", 0)), float(q.get("z", 0)), float(q.get("w", 1))).normalized()
			var scale_value = DungeonWorld.vector(item.get("scale", {"x": 1, "y": 1, "z": 1}))
			transform_value *= Transform3D(Basis(rotation_value).scaled(scale_value), DungeonWorld.vector(item.get("position", {})))
		node.transform = transform_value
		var initial: Dictionary = layer.get("initial", {})
		var particle = CPUParticles3D.new()
		particle.emitting = false
		particle.one_shot = not bool(layer.get("looping", false))
		var lifetime_range := scalar_range(initial.get("startLifetime", {}), 0.3)
		particle.lifetime = clampf(lifetime_range.y, 0.02, 8)
		particle.lifetime_randomness = clampf(1.0 - lifetime_range.x / particle.lifetime, 0, 1)
		if (wolf_embedded or str(layer.get("name", "")) == "24071901_void_helixline") and bool(layer.get("prewarm", false)) and bool(layer.get("looping", false)):
			particle.preprocess = maxf(particle.lifetime, float(layer.get("duration", particle.lifetime)))
		var count := 0.0
		for burst in emission.get("m_Bursts", []): count += scalar(burst.get("countCurve", {}), 1)
		var rate = scalar(emission.get("rateOverTime", {}))
		var layer_budget = mini(budget - particle_count, 32 if low_quality else 96)
		if int(initial.get("maxNumParticles", 0)) > 0: layer_budget = mini(layer_budget, int(initial.maxNumParticles))
		particle.amount = clampi(int(ceil(maxf(count, rate * particle.lifetime))), 1, layer_budget)
		particle.explosiveness = 1.0 if count > 0 and rate <= 0 else 0.0
		particle.local_coords = int(layer.get("simulation_space", 0)) == 0
		particle.direction = Vector3(0, 0, 1)
		var shape: Dictionary = layer.get("shape", {})
		particle.spread = float(shape.get("angle", 0))
		var speed_range := scalar_range(initial.get("startSpeed", {}))
		particle.initial_velocity_min = speed_range.x
		particle.initial_velocity_max = speed_range.y
		particle.gravity = Vector3(0, -9.81, 0) * scalar(initial.get("gravityModifier", {}))
		var size_range := scalar_range(initial.get("startSize", {}), 1)
		var size_value = maxf(0.001, size_range.y)
		particle.scale_amount_min = maxf(0.001, size_range.x)
		particle.scale_amount_max = size_value
		var angle_range := scalar_range(initial.get("startRotation", {}))
		particle.angle_min = rad_to_deg(angle_range.x)
		particle.angle_max = rad_to_deg(angle_range.y)
		if shape.get("enabled", false):
			var radius_data: Variant = shape.get("radius", {})
			var radius = float(radius_data.get("value", 0.1)) if radius_data is Dictionary else float(radius_data)
			match int(shape.get("type", 0)):
				0:
					particle.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
					particle.emission_sphere_radius = radius
				1:
					particle.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE_SURFACE
					particle.emission_sphere_radius = radius
				5, 15, 16:
					particle.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
					particle.emission_box_extents = DungeonWorld.vector(shape.get("m_Scale", {"x": 1, "y": 1, "z": 1})) * 0.5
				2, 3, 4, 7, 8, 9, 10, 11, 12, 17:
					particle.emission_shape = CPUParticles3D.EMISSION_SHAPE_DIRECTED_POINTS
					var points = PackedVector3Array()
					var normals = PackedVector3Array()
					var shape_type = int(shape.type)
					var cone = shape_type in [4, 7, 8, 9]
					var cone_angle = deg_to_rad(float(shape.get("angle", 0)))
					particle.spread = 0
					for point_index in 64:
						var angle = point_index * 2.39996323
						var fraction = (point_index + 0.5) / 64.0
						var r = radius * (1.0 if shape_type in [3, 7, 9, 11, 17] else sqrt(fraction))
						var point = Vector3(cos(angle) * r, sin(angle) * r, 0)
						var normal = Vector3(cos(angle) * sin(cone_angle), sin(angle) * sin(cone_angle), cos(cone_angle)) if cone else point.normalized()
						if shape_type in [2, 3]:
							point = Vector3(cos(angle) * sqrt(1 - fraction * fraction), sin(angle) * sqrt(1 - fraction * fraction), fraction) * radius
							normal = point.normalized()
						elif shape_type == 12:
							point = Vector3(lerpf(-radius, radius, fraction), 0, 0)
							normal = Vector3(0, 0, 1)
						elif wolf_embedded and shape_type in [8, 9]:
							# ConeVolume starts throughout the cone, including its authored length.
							var cone_length := maxf(0, float(shape.get("length", 0)))
							var slope := tan(cone_angle)
							var end_radius: float = radius + cone_length * slope
							var volume_fraction := fmod((point_index + 0.5) * 0.61803398875, 1.0)
							var depth: float = (pow(lerpf(pow(radius, 3), pow(end_radius, 3), volume_fraction), 1.0 / 3.0) - radius) / slope if absf(slope) > 0.000001 else cone_length * volume_fraction
							var radial_fraction := 1.0 if shape_type == 9 else sqrt(fraction)
							r = (radius + depth * slope) * radial_fraction
							point = Vector3(cos(angle) * r, sin(angle) * r, depth)
							normal = Vector3(cos(angle) * slope * radial_fraction, sin(angle) * slope * radial_fraction, 1).normalized()
						points.append(point)
						normals.append(normal)
					particle.emission_points = points
					particle.emission_normals = normals
			particle.position = DungeonWorld.vector(shape.get("m_Position", {}))
			particle.rotation_degrees = DungeonWorld.vector(shape.get("m_Rotation", {}))
		particle.color = rgba(initial.get("startColor", {}).get("maxColor", {}))
		var start_color: Dictionary = initial.get("startColor", {})
		if int(start_color.get("minMaxState", 0)) == 3:
			particle.color = Color.WHITE
			var start_ramp = Gradient.new()
			start_ramp.colors = PackedColorArray([rgba(start_color.get("minColor", {})), rgba(start_color.get("maxColor", {}))])
			particle.color_initial_ramp = start_ramp
		elif int(start_color.get("minMaxState", 0)) == 4:
			particle.color = Color.WHITE
			particle.color_initial_ramp = gradient(start_color)
		var modules: Dictionary = layer.get("modules", {})
		var size_module: Dictionary = modules.get("SizeModule", {})
		if bool(initial.get("size3D", false)) or bool(size_module.get("separateAxes", false)):
			particle.split_scale = true
			for axis in ["x", "y", "z"]:
				var start_size = scalar(initial.get("startSize" + axis.to_upper() if axis != "x" else "startSize", {}), size_value) if bool(initial.get("size3D", false)) else size_value
				var axis_value: Dictionary = size_module.get(axis if bool(size_module.get("separateAxes", false)) and axis != "x" else "curve", {})
				var axis_curve = curve(axis_value, start_size / size_value)
				particle.set("scale_curve_" + axis, axis_curve if axis_curve else constant_curve(start_size / size_value))
		elif modules.has("SizeModule"):
			particle.scale_amount_curve = curve(size_module.get("curve", {}))
		if modules.has("ColorModule"): particle.color_ramp = gradient(modules.ColorModule.get("gradient", {}))
		if modules.has("RotationModule"):
			var rotation_module: Dictionary = modules.RotationModule
			particle.angular_velocity_min = rad_to_deg(lower_scalar(rotation_module.get("curve", {})))
			particle.angular_velocity_max = rad_to_deg(scalar(rotation_module.get("curve", {})))
			particle.angular_velocity_curve = curve(rotation_module.get("curve", {}), 1.0 / maxf(absf(scalar(rotation_module.get("curve", {}), 1)), 0.00001))
		var material = StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.vertex_color_use_as_albedo = true
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		var materials: Array = layer.get("materials", [])
		var ground_fade: bool = not materials.is_empty() and _material_name(materials[0]) == "mat_fx_25011001_slash_fog.mat"
		if not materials.is_empty():
			var source: Dictionary = materials[0]
			material.albedo_texture = textures.get(str(source.get("texture", "")))
			material.albedo_color = rgba(source.get("color", {}))
			material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if source.get("blend", "") == "add" else BaseMaterial3D.BLEND_MODE_MIX
			var uv_scale: Dictionary = source.get("texture_scale", {})
			var uv_offset: Dictionary = source.get("texture_offset", {})
			material.uv1_scale = Vector3(float(uv_scale.get("x", 1)), float(uv_scale.get("y", 1)), 1)
			material.uv1_offset = Vector3(float(uv_offset.get("x", 0)), float(uv_offset.get("y", 0)), 0)
		var renderer: Dictionary = layer.get("renderer", {})
		if int(renderer.get("render_mode", 0)) == 1:
			particle.particle_flag_align_y = true
		if modules.has("UVModule"):
			var uv: Dictionary = modules.UVModule
			material.particles_anim_h_frames = maxi(1, int(uv.get("tilesX", 1)))
			material.particles_anim_v_frames = maxi(1, int(uv.get("tilesY", 1)))
			material.particles_anim_loop = int(uv.get("cycles", 1)) > 1
			particle.anim_speed_min = float(uv.get("cycles", 1)) / particle.lifetime
			particle.anim_speed_max = particle.anim_speed_min
			particle.anim_offset_min = scalar(uv.get("startFrame", {}))
			particle.anim_offset_max = particle.anim_offset_min
		var mesh_path = str(layer.get("mesh", ""))
		if not mesh_path.is_empty() and ResourceLoader.exists(mesh_path):
			var mesh_resource = load(mesh_path)
			if mesh_resource is Mesh:
				particle.mesh = mesh_resource
			elif mesh_resource is PackedScene:
				var model = mesh_resource.instantiate()
				var meshes = model.find_children("*", "MeshInstance3D", true, false)
				if not meshes.is_empty(): particle.mesh = meshes[0].mesh
				model.free()
		if particle.mesh == null:
			var quad = QuadMesh.new()
			quad.size = Vector2.ONE
			particle.mesh = quad
			match int(renderer.get("render_mode", 0)):
				0, 1: material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
				2: node.rotate_x(-PI / 2)
				3: material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		particle.material_override = material
		if not materials.is_empty():
			var source: Dictionary = materials[0]
			var recovered = ShaderMaterial.new()
			if source.get("blend", "") == "add":
				if _additive_shader == null:
					_additive_shader = Shader.new()
					_additive_shader.code = preload("res://scripts/presentation/recovered_particle.gdshader").code.replace("blend_mix", "blend_add")
				recovered.shader = _additive_shader
			else: recovered.shader = preload("res://scripts/presentation/recovered_particle.gdshader")
			recovered.set_shader_parameter("main_texture", material.albedo_texture)
			var tint = rgba(source.get("shape_color", {})) * rgba(source.get("color", {}))
			tint.a *= float(source.get("alpha", 1))
			recovered.set_shader_parameter("tint", tint)
			recovered.set_shader_parameter("luminance_alpha", bool(source.get("alpha_from_luminance", false)))
			recovered.set_shader_parameter("shape_alpha_weight", clampf(float(source.get("shape_alpha_weight", 1)), 0, 2))
			recovered.set_shader_parameter("shape_brightness", float(source.get("shape_brightness", 0)))
			var opacity_mask: Dictionary = MATERIAL_MASKS.get(_material_name(source), {})
			if not opacity_mask.is_empty():
				var mask_path = str(opacity_mask.texture)
				recovered.set_shader_parameter("opacity_mask", textures[mask_path] if textures.has(mask_path) else load(mask_path))
				recovered.set_shader_parameter("use_opacity_mask", true)
				recovered.set_shader_parameter("mask_uv_scale", opacity_mask.get("scale", Vector2.ONE))
				recovered.set_shader_parameter("mask_uv_offset", opacity_mask.get("offset", Vector2.ZERO))
				recovered.set_shader_parameter("mask_power", float(opacity_mask.get("power", 1)))
			# The original custom-stream erosion is unavailable on these recovered smoke meshes.
			recovered.set_shader_parameter("edge_feather", SOFT_BOUNDARY_MATERIALS.get(_material_name(source), Vector2.ZERO))
			recovered.set_shader_parameter("ground_feather", 0.5 if ground_fade else 0.0)
			# Original erosion controllers are unavailable; keep broad slash meshes translucent.
			recovered.set_shader_parameter("reconstructed_ribbon", _uses_reconstructed_ribbon(layer, source))
			recovered.set_shader_parameter("reconstructed_water_shell", _uses_reconstructed_water_shell(layer, source))
			recovered.set_shader_parameter("reconstructed_water_splash", _uses_reconstructed_water_splash(source))
			recovered.set_shader_parameter("billboard", int(renderer.get("render_mode", 0)) == 0 and int(renderer.get("alignment", 0)) in [0, 3])
			recovered.set_shader_parameter("vertical_billboard", int(renderer.get("render_mode", 0)) == 3)
			recovered.set_shader_parameter("stretched_billboard", int(renderer.get("render_mode", 0)) == 1)
			recovered.set_shader_parameter("stretch_length", maxf(0 if wolf_embedded else 1, float(renderer.get("length_scale", 1))))
			if wolf_embedded:
				recovered.set_shader_parameter("stretch_velocity", maxf(0, float(renderer.get("velocity_scale", 0))))
				# CPU particle velocity magnitude is not exposed to spatial shaders.
				# Use the authored range midpoint; direction still follows each particle.
				recovered.set_shader_parameter("stretch_speed", (speed_range.x + speed_range.y) * 0.5)
			recovered.set_shader_parameter("initial_rotation", Vector2(scalar(initial.get("startRotationX", {})), scalar(initial.get("startRotationY", {}))) if bool(initial.get("rotation3D", false)) else Vector2.ZERO)
			recovered.set_shader_parameter("uv_scale", Vector2(material.uv1_scale.x, material.uv1_scale.y))
			recovered.set_shader_parameter("uv_offset", Vector2(material.uv1_offset.x, material.uv1_offset.y))
			recovered.set_shader_parameter("sheet", Vector2(material.particles_anim_h_frames, material.particles_anim_v_frames))
			if modules.has("UVModule"):
				var uv: Dictionary = modules.UVModule
				var frames = CurveTexture.new()
				frames.curve = value_curve(uv.get("frameOverTime", {}), 1.0)
				recovered.set_shader_parameter("frame_curve", frames)
				recovered.set_shader_parameter("use_frame_curve", true)
				recovered.set_shader_parameter("sheet_cycles", maxf(1, float(uv.get("cycles", 1))))
				recovered.set_shader_parameter("sheet_start", scalar(uv.get("startFrame", {})))
			if modules.has("VelocityModule"):
				var velocity_module: Dictionary = modules.VelocityModule
				recovered.set_shader_parameter("motion_curve", _integrated_motion(velocity_module, particle.lifetime))
				recovered.set_shader_parameter("use_motion_curve", true)
				recovered.set_shader_parameter("world_motion", bool(velocity_module.get("inWorldSpace", false)))
			preload("res://scripts/presentation/recovered_effect_material.gd").apply_source(recovered, source, textures)
			if modules.has("CustomDataModule"):
				var custom: Dictionary = modules.CustomDataModule
				for stream_index in 2:
					if int(custom.get("mode%d" % stream_index, 0)) != 1: continue
					recovered.set_shader_parameter("custom_stream%d" % stream_index, custom_stream(custom, stream_index))
					recovered.set_shader_parameter("use_custom_stream%d" % stream_index, true)
			particle.material_override = recovered
		particle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		particle.extra_cull_margin = 8
		if RetainedParticle.handles(layer):
			# Unity PauseUntilReplaced keeps this stationary single-burst particle alive.
			var retained := RetainedParticle.create(particle, layer)
			node.add_child(retained)
			var burst: Dictionary = emission.m_Bursts[0]
			var speed := maxf(0.01, float(layer.get("simulation_speed", 1.0)))
			retained_particles.append({"node": retained, "path": get_path_to(retained), "delay": (scalar(layer.get("start_delay", {})) + float(burst.get("time", 0.0))) / speed, "duration": particle.lifetime / speed, "angle": deg_to_rad(particle.angle_min)})
			lifetime = maxf(lifetime, float(retained_particles.back().delay) + float(retained_particles.back().duration))
			particle_count += 1
			logical_emitter_count += 1
			particle.free()
			continue
		node.add_child(particle)
		var delay = maxf(0, scalar(layer.get("start_delay", {})))
		var duration = maxf(particle.lifetime, float(layer.get("duration", particle.lifetime)))
		var speed_scale = maxf(0.01, float(layer.get("simulation_speed", 1)))
		var burst_period = maxf(0.02, float(layer.get("duration", particle.lifetime))) / speed_scale if bool(layer.get("looping", false)) else 0.0
		var bursts: Array = emission.get("m_Bursts", [])
		if not bursts.is_empty() and rate <= 0:
			var first := true
			for burst in bursts:
				if float(burst.get("probability", 1)) <= 0: continue
				for cycle in clampi(int(burst.get("cycleCount", 1)), 1, 6):
					if logical_emitter_count >= (8 if low_quality else 18): break
					if particle_count >= budget: break
					var instance = particle if first else particle.duplicate()
					if not first: node.add_child(instance)
					first = false
					instance.one_shot = true
					instance.amount = clampi(int(scalar(burst.get("countCurve", {}), 1)), 1, mini(layer_budget, budget - particle_count))
					particle_count += instance.amount
					instance.explosiveness = 1.0
					var at = delay + float(burst.get("time", 0)) + cycle * float(burst.get("repeatInterval", 0))
					var maximum_lifetime: float = instance.lifetime
					var instances: Array[CPUParticles3D] = [instance]
					if ChestSmokeVelocity.handles(layer):
						instances = ChestSmokeVelocity.split_burst(instance, layer, value_curve(modules.ClampVelocityModule.magnitude))
					for current in instances:
						emitters.append({"node": current, "delay": at / speed_scale, "started": false, "speed": speed_scale, "loop": burst_period > 0.0, "burst_period": burst_period, "duration": duration / speed_scale, "ground_fade": ground_fade})
					logical_emitter_count += 1
					lifetime = maxf(lifetime, (at + maximum_lifetime) / speed_scale)
		else:
			particle.one_shot = false
			particle_count += particle.amount
			emitters.append({"node": particle, "delay": delay / speed_scale, "started": false, "speed": speed_scale, "loop": bool(layer.get("looping", false)), "duration": duration / speed_scale, "ground_fade": ground_fade})
			logical_emitter_count += 1
		lifetime = maxf(lifetime, (delay + (duration if rate > 0 else 0.0) + particle.lifetime) / speed_scale)

func set_visual_gain(value: float, crimson := false) -> void:
	for emitter in emitters + retained_particles:
		if emitter.node.material_override is ShaderMaterial:
			emitter.node.material_override.set_shader_parameter("visual_gain", clampf(value, 0, 1))
			emitter.node.material_override.set_shader_parameter("crimson_blade", crimson)

func instantiate_effect() -> Node3D:
	# Share meshes, textures and baked curves; each emitter owns its mutable uniforms.
	var instance = get_script().new()
	instance.lifetime = lifetime
	instance.particle_count = particle_count
	instance.unsupported = unsupported
	for child in get_children(): instance.add_child(child.duplicate(0))
	for source in retained_particles:
		var entry = source.duplicate()
		entry.node = instance.get_child(source.node.get_parent().get_index()).get_child(source.node.get_index())
		entry.node.multimesh = RetainedParticle.duplicate_mesh(entry.node.multimesh)
		entry.node.material_override = entry.node.material_override.duplicate()
		instance.retained_particles.append(entry)
	for source in model_players:
		var entry = source.duplicate()
		entry.node = instance.get_node(source.path)
		instance.model_players.append(entry)
	for source in model_styles:
		var runtime = ModelMaterialAnimation.new()
		runtime.configure(instance.get_node(source.path), source.definition, {})
		instance.model_styles.append({"path": source.path, "definition": source.definition, "runtime": runtime})
	for emitter in emitters:
		var entry = emitter.duplicate()
		var particle: CPUParticles3D = instance.get_child(emitter.node.get_parent().get_index()).get_child(emitter.node.get_index())
		particle.material_override = emitter.node.material_override.duplicate()
		entry.node = particle
		instance.emitters.append(entry)
	return instance

func restart() -> void:
	age = 0
	_running = true
	show()
	play_model_animation("")
	for retained in retained_particles: retained.node.hide()
	for emitter in emitters:
		emitter.started = false
		emitter.erase("next_burst")
		emitter.erase("last_speed")
		emitter.erase("last_basis")
		emitter.node.emitting = false
		ChestSmokeVelocity.restart_particle(emitter.node)
		emitter.node.restart()
		emitter.node.emitting = false

func advance(delta: float, paused: bool, playback_rate := 1.0) -> void:
	if not paused and _running:
		for entry in model_players: entry.node.advance(delta)
		for entry in model_styles: entry.runtime.advance(delta)
	for emitter in emitters:
		var speed = 0.0 if paused else emitter.speed * maxf(0, playback_rate)
		if emitter.get("last_speed", -1.0) != speed:
			emitter.node.speed_scale = speed
			emitter.last_speed = speed
		if not paused and emitter.node.material_override is ShaderMaterial:
			emitter.node.material_override.set_shader_parameter("clock", age)
			if emitter.get("ground_fade", false): emitter.node.material_override.set_shader_parameter("ground_level", global_position.y - 0.08)
			var basis_value: Basis = emitter.node.global_basis
			if not emitter.has("last_basis") or not basis_value.is_equal_approx(emitter.last_basis):
				emitter.node.material_override.set_shader_parameter("emitter_basis", basis_value)
				emitter.last_basis = basis_value
	if paused or not _running: return
	age += delta
	for retained in retained_particles:
		retained.node.visible = age >= float(retained.delay)
		var phase := clampf((age - float(retained.delay)) / maxf(0.0001, float(retained.duration)), 0.0, 1.0)
		retained.node.multimesh.set_instance_custom_data(0, Color(float(retained.angle), phase, 0.0, 0.0))
		if retained.node.material_override is ShaderMaterial:
			retained.node.material_override.set_shader_parameter("clock", age)
	for emitter in emitters:
		if (not emitter.started and age >= float(emitter.delay)) or (emitter.has("next_burst") and age >= float(emitter.next_burst)):
			emitter.started = true
			emitter.node.restart()
			emitter.node.emitting = true
			var period := float(emitter.get("burst_period", 0.0))
			if period > 0.0:
				# Burst-only layers still repeat on each authored system cycle.
				emitter.next_burst = float(emitter.delay) + (floorf((age - float(emitter.delay)) / period) + 1.0) * period
		if emitter.started and not emitter.loop and age > float(emitter.delay) + float(emitter.duration): emitter.node.emitting = false

func stop() -> void:
	_running = false
	hide()
	for emitter in emitters: emitter.node.emitting = false
	for retained in retained_particles: retained.node.hide()
	for entry in model_players: entry.node.stop()

func play_model_animation(source_name: String) -> void:
	for entry in model_styles: entry.runtime.play(source_name)
	for entry in model_players:
		var wanted = str(entry.aliases.get(source_name.to_lower(), source_name)) if not source_name.is_empty() else str(entry.default)
		for name in entry.node.get_animation_list():
			if str(name).get_file() == wanted:
				entry.node.play(name)
				entry.node.advance(0)
				break
