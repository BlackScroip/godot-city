extends Node3D

var world: Node3D
var props: Array[Dictionary] = []
var clock := 0.0

# Box_Effect children in the APK's EnvUnit_TreasureBox_* subprefabs.
const CHEST_EFFECTS := {
	"Normal": "23121501_fx_other_propblue",
	"Unusual": "23121501_fx_other_proppurple",
	"Luxury": "23122101_fx_other_treasureboxyellow",
	"Curse": "23122101_fx_other_treasureboxcurse"
}

func configure(source: Node3D) -> void:
	world = source
	for item in world.interactions._items.values():
		var kind := str(item.marker.get("Type", ""))
		if kind not in ["EEUT_AbilityItemTreasureBox", "EEUT_StageChangeDoor", "EEUT_Protal"]: continue
		if not is_instance_valid(item.visual): continue
		var anchor = Node3D.new()
		anchor.name = "InteractionPresentation"
		item.visual.add_child(anchor)
		var entry := {"item": item, "anchor": anchor, "opened": false}
		if kind == "EEUT_AbilityItemTreasureBox":
			entry["effect_address"] = CHEST_EFFECTS.get(str(item.data.get("TreasureType", "")), "")
			var effect_anchor: Node3D
			if not entry.effect_address.is_empty():
				for child in item.visual.find_children("*", "Node3D", true, false):
					if str(child.name) == entry.effect_address or str(child.name).begins_with(entry.effect_address + "_"):
						effect_anchor = child
						break
			if effect_anchor == null:
				effect_anchor = Node3D.new()
				effect_anchor.name = "ChestSourceEffect"
				anchor.add_child(effect_anchor)
			entry["effect_anchor"] = effect_anchor
			# Exported treasure markers may contain only an empty artmodel socket.
			var existing: Array = item.visual.find_children("*", "MeshInstance3D", true, false)
			if existing.is_empty(): _chest(anchor, entry)
			DungeonWorldStyle.effect(anchor, Vector3.ZERO, Color(0.12, 0.42, 1, 0.48), 2.6, -1)
		else:
			_portal(anchor, item.visual.find_children("*", "MeshInstance3D", true, false).is_empty(), entry)
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

func _box(parent: Node3D, dimensions: Vector3, point: Vector3, material: Material) -> MeshInstance3D:
	var geometry = BoxMesh.new()
	geometry.size = dimensions
	return _mesh(parent, geometry, material, point)

func _chest(anchor: Node3D, entry: Dictionary) -> void:
	var wood = _material(Color("596665"))
	var dark = _material(Color("283c42"))
	var steel = _material(Color("a5b9b5"), 0, 0.45)
	var glow = _material(Color("66dcff"), 1.2)
	_box(anchor, Vector3(1.38, 0.55, 0.86), Vector3(0, 0.34, 0), wood)
	for y in [0.12, 0.57]:
		_box(anchor, Vector3(1.45, 0.07, 0.92), Vector3(0, y, 0), steel)
	for x in [-0.51, 0.51]:
		_box(anchor, Vector3(0.09, 0.51, 0.91), Vector3(x, 0.35, 0), steel)
	for y in [0.27, 0.43]:
		_box(anchor, Vector3(1.29, 0.015, 0.012), Vector3(0, y, 0.437), dark)
	var lid = Node3D.new()
	lid.position = Vector3(0, 0.63, -0.43)
	anchor.add_child(lid)
	_box(lid, Vector3(1.43, 0.18, 0.9), Vector3(0, 0.04, 0.43), wood)
	_box(lid, Vector3(1.35, 0.1, 0.7), Vector3(0, 0.16, 0.43), wood)
	for x in [-0.51, 0.51]:
		_box(lid, Vector3(0.095, 0.075, 0.91), Vector3(x, 0.19, 0.43), steel)
	_box(lid, Vector3(1.46, 0.06, 0.94), Vector3(0, -0.035, 0.43), steel)
	_box(lid, Vector3(0.19, 0.24, 0.065), Vector3(0, -0.08, 0.91), steel)
	_box(lid, Vector3(0.045, 0.08, 0.016), Vector3(0, -0.08, 0.95), dark)
	_box(anchor, Vector3(1.22, 0.018, 0.8), Vector3(0, 0.625, 0), glow)
	entry["lid"] = lid
	entry["glow"] = glow

func _portal(anchor: Node3D, missing: bool, entry: Dictionary) -> void:
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
	for entry in props:
		var state: Dictionary = entry.item.state
		entry.anchor.visible = state.enabled and not state.broken
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
		if entry.has("lid"):
			entry.lid.rotation.x = move_toward(entry.lid.rotation.x, -1.65 if state.opened else 0.0, delta * 3.5)
			entry.glow.emission_energy_multiplier = 0.12 if state.opened else 1.1 + sin(clock * 2.2) * 0.2
		if bool(state.opened) != bool(entry.opened):
			entry.opened = state.opened
			for child in entry.anchor.get_children():
				if child is MeshInstance3D and child.mesh is PlaneMesh:
					child.visible = not state.opened
