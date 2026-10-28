extends Node3D

var world: Node3D
var props: Array[Dictionary] = []
var clock := 0.0
var door_materials = preload("res://scripts/presentation/door_materials.gd").new()
var chest_sources: Dictionary = {}
var chest_presentation = preload("res://scripts/presentation/chest_source_presentation.gd").new()
const CHEST_CATALOG := "res://assets/environment_effects/chest_catalog.json"

# Box_Effect children in the APK's EnvUnit_TreasureBox_* subprefabs.
const CHEST_EFFECTS := {
	"Normal": "23121501_fx_other_propblue",
	"Unusual": "23121501_fx_other_proppurple",
	"Luxury": "23122101_fx_other_treasureboxyellow",
	"Curse": "23122101_fx_other_treasureboxcurse",
	"Curse_Final": "23122101_fx_other_treasureboxcurse"
}

func configure(source: Node3D) -> void:
	world = source
	chest_presentation.configure()
	if FileAccess.file_exists(CHEST_CATALOG):
		var catalog = JSON.parse_string(FileAccess.get_file_as_string(CHEST_CATALOG))
		if catalog is Dictionary: chest_sources = catalog.get("chests", {})
	door_materials.configure(world.environment_root)
	for item in world.interactions._items.values():
		var kind := str(item.marker.get("Type", ""))
		if kind not in ["EEUT_StageChangeDoor", "EEUT_Protal"]: continue
		if not is_instance_valid(item.visual): continue
		var anchor = Node3D.new()
		anchor.name = "InteractionPresentation"
		item.visual.add_child(anchor)
		var entry := {"item": item, "anchor": anchor, "opened": false}
		if kind in ["EEUT_StageChangeDoor", "EEUT_Protal"]:
			_portal(anchor, item.visual.find_children("*", "MeshInstance3D", true, false).is_empty(), entry)
			entry["door_details"] = []
			for child in item.visual.find_children("*", "Node3D", true, false):
				for prefix in ["Box_DoorEffect", "Box_StageInfo", "Sprite_StageType", "Text_StageName"]:
					if str(child.name).begins_with(prefix):
						entry.door_details.append(child)
						break
			if kind == "EEUT_StageChangeDoor" and not entry.door_details.any(func(child): return str(child.name).begins_with("Box_DoorEffect")):
				# Missing exported effect socket: place the APK's exit prefab at the door root.
				# This source-art reconstruction does not claim the original runtime binding.
				var exit_effect := Node3D.new()
				exit_effect.name = "24040202_fx_env_protal_exit"
				anchor.add_child(exit_effect)
				entry["effect_address"] = "24040202_fx_env_protal_exit"
				entry["effect_anchor"] = exit_effect
				var surface := ShaderMaterial.new()
				surface.shader = preload("res://scripts/presentation/door_exit_surface.gdshader")
				surface.set_shader_parameter("wave_texture", load("res://assets/environment_effects/texture_cb924483d88815c6cdf5.png"))
				var opening := QuadMesh.new()
				opening.size = Vector2(2.4, 3.4)
				_mesh(anchor, opening, surface, Vector3(0, 1.7, 0.06)).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				entry["exit_surface"] = surface
		props.append(entry)
	refresh_chests()

func refresh_chests() -> void:
	var controller = world.environment_root.get_node_or_null("EnvironmentEffects")
	for entry in props.duplicate():
		if str(entry.item.marker.get("Type", "")) == "EEUT_AbilityItemTreasureBox": props.erase(entry)
	for item in world.interactions._items.values():
		if str(item.marker.get("Type", "")) != "EEUT_AbilityItemTreasureBox" or not is_instance_valid(item.visual): continue
		# Trial boxes clone the source visual after its first presentation setup.
		if controller != null:
			for binding in controller.bindings.duplicate():
				if item.visual.is_ancestor_of(binding.anchor) and CHEST_EFFECTS.values().has(binding.address): controller.remove_binding(binding)
		for child in item.visual.get_children():
			if str(child.name).begins_with("InteractionPresentation"):
				item.visual.remove_child(child)
				child.queue_free()
		for child in item.visual.find_children("*", "Node3D", true, false):
			for address in CHEST_EFFECTS.values():
				if str(child.name) == address or str(child.name).begins_with(address + "_"):
					child.hide()
					child.set_meta("unityActive", false)
		# Scene markers may contain an older quality's art. Render the exact
		# selected subprefab while leaving the interaction root and sockets alive.
		if item.visual is MeshInstance3D: item.visual.layers = 0
		for mesh: MeshInstance3D in item.visual.find_children("*", "MeshInstance3D", true, false): mesh.layers = 0
		var anchor := Node3D.new()
		anchor.name = "InteractionPresentation"
		item.visual.add_child(anchor)
		item["chest_presentation"] = true
		var quality := str(item.data.get("TreasureType", "Normal"))
		var source: Dictionary = chest_sources.get("Curse" if quality == "Curse_Final" else quality, {})
		item["chest_disappear_seconds"] = float(source.get("disappear_time_seconds", 1.0))
		var entry := {"item": item, "anchor": anchor, "opened": bool(item.state.opened), "effect_address": str(source.get("ambient_effect", CHEST_EFFECTS.get(quality, "")))}
		chest_presentation.attach(anchor, entry)
		var effect_anchor := Node3D.new()
		effect_anchor.name = "ChestSourceEffect"
		anchor.add_child(effect_anchor)
		for component in source.get("ambient_transform_chain", []):
			var q: Dictionary = component.get("rotation", {})
			var rotation_value := Quaternion(float(q.get("x", 0)), float(q.get("y", 0)), float(q.get("z", 0)), float(q.get("w", 1))).normalized()
			var scale_value := DungeonWorld.vector(component.get("scale", {"x": 1, "y": 1, "z": 1}))
			effect_anchor.transform *= Transform3D(Basis(rotation_value).scaled(scale_value), DungeonWorld.vector(component.get("position", {})))
		effect_anchor.visible = bool(source.get("ambient_active", true)) and not bool(item.state.opened)
		entry["effect_anchor"] = effect_anchor
		if controller != null and not entry.effect_address.is_empty():
			var binding: Dictionary = controller.register_anchor(effect_anchor, entry.effect_address)
			if not binding.is_empty(): entry["effect_binding"] = binding
		props.append(entry)

func _material(color: Color, glow := 0.0, metallic := 0.0) -> StandardMaterial3D:
	var material = StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = 0.65
	if glow > 0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = glow
	return material

func _mesh(parent: Node3D, geometry: Mesh, material: Material, point: Vector3) -> MeshInstance3D:
	var mesh = MeshInstance3D.new()
	mesh.mesh = geometry
	mesh.material_override = material
	mesh.position = point
	parent.add_child(mesh)
	return mesh

func _portal(anchor: Node3D, missing: bool, entry: Dictionary) -> void:
	# Recovered stone portals retain their source silhouette without generic rings.
	if not missing: return
	var cyan = _material(Color("57cfff"), 0.75)
	var violet = _material(Color("ae8aef"), 0.8)
	if missing:
		var egg = SphereMesh.new()
		egg.radius = 0.32
		egg.height = 0.96
		entry["orb"] = _mesh(anchor, egg, cyan, Vector3(0, 1.05, 0))
	for index in 3:
		var ring = TorusMesh.new()
		ring.inner_radius = 0.56 + index * 0.12
		ring.outer_radius = ring.inner_radius + 0.025
		var instance = _mesh(anchor, ring, violet if index % 2 == 0 else cyan, Vector3(0, 0.35 + index * 0.12, 0))
		instance.rotation.x = index * 0.17
	DungeonWorldStyle.effect(anchor, Vector3.ZERO, Color(0.34, 0.22, 0.9, 0.5), 2.2, -1)

func _process(delta: float) -> void:
	if not is_instance_valid(world) or world.paused or world._background: return
	clock += delta
	door_materials.tick(clock)
	for entry in props:
		var state: Dictionary = entry.item.state
		entry.anchor.visible = state.enabled and not state.broken
		if entry.has("exit_surface"): entry.exit_surface.set_shader_parameter("clock", clock)
		for detail in entry.get("door_details", []):
			detail.visible = state.enabled and not state.broken
			detail.set_meta("unityActive", detail.visible)
		if entry.has("effect_anchor"):
			entry.effect_anchor.visible = not state.opened
			if not entry.has("effect_binding") and not entry.effect_address.is_empty():
				var controller = world.environment_root.get_node_or_null("EnvironmentEffects")
				if controller != null:
					var binding: Dictionary = controller.register_anchor(entry.effect_anchor, entry.effect_address)
					if not binding.is_empty(): entry["effect_binding"] = binding
		if entry.has("orb"):
			entry.orb.position.y = 1.05 + sin(clock * 1.8) * 0.08
			entry.orb.rotation.y += delta * 0.35
		if bool(state.opened) != bool(entry.opened):
			entry.opened = state.opened
			for child in entry.anchor.get_children():
				if child is MeshInstance3D and child.mesh is PlaneMesh:
					child.visible = not state.opened
		if entry.item.get("chest_presentation", false) and state.opened:
			chest_presentation.tick(entry, delta)
