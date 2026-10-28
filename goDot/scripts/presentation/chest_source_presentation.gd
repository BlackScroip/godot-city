extends RefCounted

const CATALOG_PATH := "res://assets/chests/catalog.json"
const SOURCE_SHADER = preload("res://scripts/presentation/chest_source_material.gdshader")

var catalog: Dictionary = {}
var scenes: Dictionary = {}

func configure() -> void:
	var source = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if source is Dictionary: catalog = source

func attach(anchor: Node3D, entry: Dictionary) -> void:
	var quality := str(entry.item.data.get("TreasureType", "Normal"))
	var source: Dictionary = catalog.get("models", {}).get(quality, {})
	if source.is_empty():
		push_error("Missing source chest model: " + quality)
		return
	var path := str(source.path)
	if not scenes.has(path): scenes[path] = load(path)
	var scene: PackedScene = scenes[path]
	if scene == null: return
	var model := scene.instantiate() as Node3D
	model.name = "ChestSourceModel"
	anchor.add_child(model)
	entry["source_model"] = model
	entry["source_quality"] = quality
	entry["source_lid"] = model.find_child("Top", true, false)
	entry["source_materials"] = []
	var materials: Dictionary = {}
	for data: Dictionary in source.get("materials", []):
		var material := _material(data)
		materials[str(data.name)] = material
		entry.source_materials.append(material)
	for node: Node3D in model.find_children("*", "Node3D", true, false):
		node.visible = bool(node.get_meta("unityActive", true))
		if not node is MeshInstance3D or node.mesh == null: continue
		for surface in node.mesh.get_surface_count():
			var imported: Material = node.get_active_material(surface)
			if imported == null: continue
			# glTF keeps the source material name; every chest uses one material.
			var recovered: Material = materials.get(imported.resource_name)
			if recovered == null and materials.size() == 1: recovered = materials.values()[0]
			if recovered != null: node.set_surface_override_material(surface, recovered)
	if bool(entry.item.state.opened):
		var duration := float(entry.item.get("chest_disappear_seconds", 1.0))
		var remaining := clampf(float(entry.item.get("chest_open_remaining", 0.0)), 0.0, duration)
		apply_pose(entry, duration - remaining)

func apply_pose(entry: Dictionary, elapsed: float) -> void:
	if not entry.has("source_model"): return
	for curve: Dictionary in catalog.get("animation", {}).get("euler_curves", []):
		var node: Node3D = _source_node(entry.source_model, str(curve.path))
		if node == null: continue
		var euler := _sample_vector_curve(curve.curve.get("m_Curve", []), elapsed) * PI / 180.0
		var source_scale := node.scale
		# Unity ZXY applies Z first: Ry * Rx * Rz. Godot's names are intrinsic.
		var rotation := Basis(Vector3.UP, euler.y) * Basis(Vector3.RIGHT, euler.x) * Basis(Vector3.BACK, euler.z)
		node.basis = rotation.scaled_local(source_scale)
	for curve: Dictionary in catalog.get("animation", {}).get("float_curves", []):
		if str(curve.get("attribute", "")) != "m_IsActive": continue
		var node: Node3D = _source_node(entry.source_model, str(curve.path))
		if node == null: continue
		var value := 1.0
		for key: Dictionary in curve.curve.get("m_Curve", []):
			if elapsed < float(key.time): break
			value = float(key.value)
		node.visible = value > 0.0

func tick(entry: Dictionary, delta: float) -> void:
	var duration := float(entry.item.get("chest_disappear_seconds", 1.0))
	var remaining := maxf(0.0, float(entry.item.get("chest_open_remaining", 0.0)) - delta)
	entry.item["chest_open_remaining"] = remaining
	apply_pose(entry, duration - remaining)
	if remaining <= 0.0: entry.item.visual.hide()

func _source_node(model: Node3D, path: String) -> Node3D:
	var node := model.get_node_or_null(NodePath(path)) as Node3D
	if node != null: return node
	var components := path.split("/")
	var first := model.find_child(components[0], true, false)
	if first == null: return null
	return first as Node3D if components.size() == 1 else first.get_node_or_null(NodePath("/".join(components.slice(1)))) as Node3D

func _sample_vector_curve(keys: Array, time: float) -> Vector3:
	if keys.is_empty(): return Vector3.ZERO
	if time <= float(keys[0].time): return DungeonWorld.vector(keys[0].value)
	for index in range(1, keys.size()):
		var end: Dictionary = keys[index]
		if time > float(end.time): continue
		var start: Dictionary = keys[index - 1]
		var duration := float(end.time) - float(start.time)
		var t := (time - float(start.time)) / duration
		var t2 := t * t
		var t3 := t2 * t
		return DungeonWorld.vector(start.value) * (2.0 * t3 - 3.0 * t2 + 1.0) + DungeonWorld.vector(start.outSlope) * duration * (t3 - 2.0 * t2 + t) + DungeonWorld.vector(end.value) * (-2.0 * t3 + 3.0 * t2) + DungeonWorld.vector(end.inSlope) * duration * (t3 - t2)
	return DungeonWorld.vector(keys[-1].value)

func _material(source: Dictionary) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SOURCE_SHADER
	material.resource_name = str(source.name)
	var floats: Dictionary = source.get("floats", {})
	var colors: Dictionary = source.get("colors", {})
	for mapping in [["source_brightness", "_Brightness"], ["source_contrast", "_Contrast"], ["diffuse_wrap", "_DiffuseWrap"], ["diffuse_brightness", "_DiffuseBrightness"], ["diffuse_contrast", "_DiffuseContrast"], ["rim_amount", "_RimAmount"], ["rim_contrast", "_RimContrast"], ["normal_strength", "_NormalStrength"]]:
		material.set_shader_parameter(mapping[0], float(floats.get(mapping[1], 1.0)))
	material.set_shader_parameter("rim_inverse", float(floats.get("_RimInverse", 0.0)) != 0.0)
	for mapping in [["base_tint", "_Color"], ["rim_color", "_RimColor"], ["emissive_color", "_Emissive"]]:
		var color: Dictionary = colors.get(mapping[1], {})
		material.set_shader_parameter(mapping[0], Color(float(color.get("r", 0)), float(color.get("g", 0)), float(color.get("b", 0)), float(color.get("a", 1))))
	for mapping in [["base", "_MainTex"], ["emissive", "_EmissiveTex"], ["normal", "_NormalTex"]]:
		var texture: Dictionary = source.get("textures", {}).get(mapping[1], {})
		if texture.is_empty(): continue
		material.set_shader_parameter(mapping[0] + "_texture", load(str(texture.path)))
		var scale_value: Dictionary = texture.get("scale", {})
		var offset: Dictionary = texture.get("offset", {})
		material.set_shader_parameter(mapping[0] + "_st", Vector4(float(scale_value.get("x", 1)), float(scale_value.get("y", 1)), float(offset.get("x", 0)), float(offset.get("y", 0))))
	material.set_shader_parameter("use_normal_map", source.get("keywords", []).has("NORMAL_MAP"))
	return material
