extends RefCounted

const TERRAIN_SHADER = preload("res://scripts/presentation/recovered_terrain.gdshader")
const WATER_SHADER = preload("res://scripts/presentation/recovered_water.gdshader")
static var _water: Dictionary = {}
static var _terrain: Dictionary = {}
static var _properties: Dictionary = {}
static var _surfaces: Dictionary = {}

static func material(source: StandardMaterial3D) -> Material:
	if _water.is_empty():
		_water = JSON.parse_string(FileAccess.get_file_as_string("res://assets/environment_recovered/water_materials.json"))
	if _water.has(source.resource_name):
		return _water_material(_water[source.resource_name], source.resource_name)
	if _terrain.is_empty():
		_terrain = JSON.parse_string(FileAccess.get_file_as_string("res://assets/environment_recovered/terrain/materials.json")).materials
	if _properties.is_empty():
		_properties = JSON.parse_string(FileAccess.get_file_as_string("res://assets/environment_recovered/materials.json"))
	if _surfaces.is_empty():
		_surfaces = JSON.parse_string(FileAccess.get_file_as_string("res://assets/environment_recovered/surfaces/materials.json")).materials
	if _terrain.has(source.resource_name):
		return _terrain_material(_terrain[source.resource_name], source.resource_name)
	if not _properties.has(source.resource_name): return null
	var data: Dictionary = _properties[source.resource_name]
	if data.shader != "OmniShade/Standard URP": return null
	# This auxiliary source material has no texture and uses _ZTest=1 (Never).
	if source.resource_name == "EnvDetail_[CommonOriginModel]_FakeShadow":
		var invisible := StandardMaterial3D.new()
		invisible.resource_name = "UnityHidden/" + source.resource_name
		invisible.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		invisible.albedo_color = Color(0, 0, 0, 0)
		return invisible
	var result: StandardMaterial3D = source.duplicate()
	result.resource_name = "UnityPaint/" + source.resource_name
	result.albedo_color = _color(data.color)
	if _surfaces.has(source.resource_name):
		var surface: Dictionary = _surfaces[source.resource_name]
		result.albedo_texture = load(surface.texture.path)
		var uv: Array = surface.uv_scale_offset
		result.uv1_scale = Vector3(uv[0], uv[1], 1.0)
		result.uv1_offset = Vector3(uv[2], uv[3], 0.0)
	result.cull_mode = BaseMaterial3D.CULL_DISABLED if data.cull == 0 else BaseMaterial3D.CULL_FRONT if data.cull == 1 else BaseMaterial3D.CULL_BACK
	result.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	result.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	result.metallic = 0.0
	result.roughness = 1.0
	result.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX if data.vertex_lit else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	result.disable_receive_shadows = not data.shadows
	result.vertex_color_use_as_albedo = false
	result.emission_enabled = false
	if data.cutout:
		result.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		result.alpha_scissor_threshold = data.cutoff
		result.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
		result.alpha_antialiasing_edge = 0.3
	elif data.transparent:
		result.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return result

static func _terrain_material(data: Dictionary, label: String) -> ShaderMaterial:
	var result = ShaderMaterial.new()
	result.resource_name = "UnityTerrain/" + label
	result.shader = TERRAIN_SHADER
	result.set_shader_parameter("control_map", load(data.controls[0].path))
	result.set_shader_parameter("layer_count", data.layer_count)
	for i in 3:
		var layer: Dictionary = data.layers[mini(i, data.layers.size() - 1)]
		var transform: Array = layer.godot_uv_scale_offset
		result.set_shader_parameter("layer_" + str(i), load(layer.diffuse.path))
		result.set_shader_parameter("uv_" + str(i), Vector4(transform[0], transform[1], transform[2], transform[3]))
		result.set_shader_parameter("tint_" + str(i), _color(layer.tint))
	return result

static func _color(values: Array) -> Color:
	return Color(values[0], values[1], values[2], values[3])

static func _water_material(data: Dictionary, label: String) -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.resource_name = "UnityWater/" + label
	result.shader = WATER_SHADER
	var colors: Dictionary = data.colors
	var values: Dictionary = data.floats
	var island := colors.has("_FlowSpeed")
	result.set_shader_parameter("original_unlit", not island)
	var flow: Dictionary = colors.get("_FlowSpeed", colors.get("_GlobalSpeed", {}))
	var tiling: Dictionary = colors.get("_WaveTiling", {"r": 3.0, "g": 3.0})
	result.set_shader_parameter("flow_speed", Vector2(flow.get("r", 0.3), flow.get("g", 0.0)))
	result.set_shader_parameter("wave_tiling", Vector2(tiling.r, tiling.g))
	result.set_shader_parameter("deep_color", _water_color(colors.get("_ColorDeep", colors.get("Color_A271762B", {}))))
	result.set_shader_parameter("shallow_color", _water_color(colors.get("_ColorShallow", colors.get("Color_E0824245", {}))))
	result.set_shader_parameter("foam_color", _water_color(colors.get("_FoamColor", colors.get("Color_AFFD055F", {}))))
	result.set_shader_parameter("waterfall", "WaterFall" in label)
	if "WaterFall" in label:
		result.set_shader_parameter("foam_mask", load("res://assets/environment_recovered/waterfall_mask.png"))
	result.set_shader_parameter("world_uv", island and float(values.get("_WorldSpaceUV", 0.0)) > 0.0)
	result.set_shader_parameter("opacity", float(values.get("_Opacity", colors.get("Color_A271762B", {}).get("a", 0.9))))
	result.set_shader_parameter("foam_strength", float(values.get("_FoamIntensity", values.get("_FoamTextureStrenth", 1.0))))
	return result

static func _water_color(value: Dictionary) -> Color:
	return Color(value.get("r", 1.0), value.get("g", 1.0), value.get("b", 1.0), value.get("a", 1.0))

# The scene controller owns time so paused menus and transitions freeze water too.
static func advance_water(scene: Node, delta: float) -> void:
	if delta <= 0.0: return
	if not scene.has_meta("water_materials"):
		var materials: Array[ShaderMaterial] = []
		_collect_water(scene, materials)
		scene.set_meta("water_materials", materials)
	var elapsed := float(scene.get_meta("water_elapsed", 0.0)) + delta
	scene.set_meta("water_elapsed", elapsed)
	for surface: ShaderMaterial in scene.get_meta("water_materials"):
		surface.set_shader_parameter("elapsed", elapsed)

static func _collect_water(node: Node, materials: Array[ShaderMaterial]) -> void:
	if node is MeshInstance3D and node.mesh:
		for index in node.mesh.get_surface_count():
			var surface: Material = node.get_active_material(index)
			if surface is ShaderMaterial and surface.shader == WATER_SHADER and not materials.has(surface):
				materials.append(surface)
	for child in node.get_children(): _collect_water(child, materials)
