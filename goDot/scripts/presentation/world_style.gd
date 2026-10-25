class_name DungeonWorldStyle
extends RefCounted

const PROFILES = {
	0: [Color("142b32"), Color("527fba"), Color("6479d9"), 0.38, 0.52],
	1: [Color("203b40"), Color("527fba"), Color("6479d9"), 0.38, 0.52],
	2: [Color("786953"), Color("c3c3ab"), Color("ffe2b1"), 0.45, 0.55],
	3: [Color("424a60"), Color("b4bad5"), Color("c8dcff"), 0.50, 0.55],
	4: [Color("554953"), Color("c6b8cb"), Color("e4bad5"), 0.45, 0.55],
	5: [Color("384b53"), Color("a2c6cb"), Color("acdaed"), 0.55, 0.55]
}
static var _materials: Dictionary = {}

static func environment(world: Node3D, region: int, camp: bool) -> void:
	DungeonStyle.apply_options(world)
	var profile: Array = PROFILES.get(0 if camp else clampi(region, 1, 5), PROFILES[1])
	for child in world.get_children():
		if child is WorldEnvironment:
			child.environment.background_color = profile[0]
			child.environment.ambient_light_color = profile[1]
			child.environment.ambient_light_energy = profile[3]
			child.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		if child is DirectionalLight3D:
			child.light_color = profile[2]
			child.light_energy = profile[4]
			child.shadow_blur = 1.5
			child.shadow_bias = 0.08
			child.shadow_normal_bias = 1.5
	apply_models(world.environment_root, camp)
	var room_props = preload("res://scripts/presentation/room_props.gd").new()
	room_props.name = "RoomProps"
	world.environment_root.add_child(room_props)
	room_props.configure(world)
	var environment_effects = preload("res://scripts/presentation/environment_effects.gd").new()
	environment_effects.name = "EnvironmentEffects"
	world.environment_root.add_child(environment_effects)
	environment_effects.configure(world, camp)
	if camp:
		var ambience = preload("res://scripts/presentation/camp_effects.gd").new()
		ambience.name = "CampEffects"
		world.environment_root.add_child(ambience)
		ambience.configure(world)
		for marker in world.semantic_markers:
			var data = JSON.parse_string(str(marker.get("DataJson", "{}")))
			if not data is Dictionary: continue
			if marker.get("Type", "") == "EEUT_NPC" and world.systems:
				var npc = world.systems.catalog.find("NPCData", str(data.get("NpcId", "")))
				if npc.is_empty(): continue
				var source = world.interactions._items.get(str(marker.get("SourceGameObjectId", "")), {}) if world.interactions else {}
				for index in 2:
					var label = Label3D.new()
					label.name = "CampNpcName" if index == 0 else "CampNpcService"
					label.set_meta("camp_marker_id", str(marker.get("SourceGameObjectId", "")))
					label.text = str(npc.get("name", "")) if index == 0 else "<" + str(npc.get("title", "")) + ">"
					label.font = DungeonStyle.theme().default_font
					label.font_size = 32
					label.pixel_size = 0.007
					label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
					label.modulate = Color.WHITE if index == 0 else Color("48f018")
					label.outline_size = 8
					world.environment_root.add_child(label)
					label.position = world.vector(marker.get("world_position", [])) + Vector3.UP * (2.9 if index == 0 else 2.48)
					if not source.is_empty(): label.visible = source.get("visible", true)
			if str(data.get("UIBtnName", "")).ends_with("StartNewRun"):
				effect(world.environment_root, world.vector(marker.get("world_position", [])), Color.WHITE, 3.2, -1)

static func apply_models(root: Node, camp := false) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		if not node.mesh: continue
		for surface in node.mesh.get_surface_count():
			var source = node.get_active_material(surface)
			if not source is StandardMaterial3D: continue
			var kind = _surface_kind(source.resource_name)
			var prop_name := str(node.name).to_lower()
			var accent := "crystal" if "talenttree_crystal" in prop_name else "egg" if "egg" in prop_name else ""
			var key = str(source.get_instance_id()) + (":camp" if camp else ":day") + ":" + str(kind) + accent
			if not _materials.has(key):
				var recovered = preload("res://scripts/presentation/recovered_environment.gd").material(source)
				if recovered:
					_materials[key] = recovered
					node.set_surface_override_material(surface, _materials[key])
					continue
				var material: StandardMaterial3D = source.duplicate()
				material.metallic = 0
				material.roughness = 1
				material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
				material.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
				if camp: material.albedo_color *= Color(0.55, 0.78, 0.95, 1)
				if not accent.is_empty():
					material.albedo_color = Color("80d6fa") if accent == "crystal" else Color("b6b9ff")
					material.emission_enabled = true
					material.emission = Color("247bc0") if accent == "crystal" else Color("7654c2")
					material.emission_energy_multiplier = 0.42
					material.roughness = 0.42
				if "water" in source.resource_name.to_lower():
					material.albedo_color = Color(0.025, 0.16, 0.24, 0.8)
					material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				_materials[key] = material
			node.set_surface_override_material(surface, _materials[key])

static func _surface_kind(resource_name: String) -> int:
	var name = resource_name.to_lower()
	if "fakeshadow" in name or "mat_fx" in name or "envunit" in name: return -1
	if "splatmap" in name or "[plane]_[top]" in name: return 0
	if "treetrunk" in name or "deadwood" in name or "stump" in name or "brank" in name: return 1
	if "leaves" in name or "foliage" in name or "bush" in name: return 3
	if "[tree]" in name: return 4
	if "grass" in name: return 5
	if "cliff" in name or "[rock]" in name or "[stone]" in name: return 2
	return -1

static func effect(parent: Node3D, point: Vector3, tint: Color, radius: float, life: float) -> void:
	var texture = DungeonStyle.texture("res://assets/art_generated/rune-v1.png")
	if not texture: return
	var plane = MeshInstance3D.new()
	var quad = PlaneMesh.new()
	quad.size = Vector2.ONE * radius
	plane.mesh = quad
	var material = StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = texture
	material.albedo_color = tint
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	plane.material_override = material
	plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(plane)
	plane.position = point + Vector3.UP * 0.06
	if life > 0:
		var tween = parent.create_tween().set_parallel(true)
		tween.tween_property(material, "albedo_color:a", 0.0, life)
		tween.tween_property(plane, "scale", Vector3.ONE * 1.25, life)
		tween.chain().tween_callback(plane.queue_free)
