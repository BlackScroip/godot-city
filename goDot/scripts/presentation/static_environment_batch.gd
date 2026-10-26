extends Node3D

const CELL_SIZE := 12.0
const MIN_INSTANCES := 3
const INSTANCE_PROPERTIES := ["cast_shadow", "layers", "gi_mode", "extra_cull_margin", "lod_bias", "ignore_occlusion_culling"]

var sources: Array[MeshInstance3D] = []
var source_layers: Array[int] = []
var batches: Array[MultiMeshInstance3D] = []
var statistics: Dictionary = {}
var enabled := false

func configure(world: Node3D, source_root: Node3D) -> void:
	if source_root == null or not sources.is_empty(): return
	var protected: Array[Node] = []
	if world.interactions:
		for item: Dictionary in world.interactions._items.values():
			var visual: Variant = item.get("visual")
			if visual is Node: protected.append(visual)
	for animator: AnimationMixer in source_root.find_children("*", "AnimationMixer", true, false):
		var animated_root := animator.get_node_or_null(animator.root_node)
		if animated_root != null: protected.append(animated_root)
	var groups: Dictionary = {}
	var skipped: Dictionary = {}
	for source: MeshInstance3D in source_root.find_children("*", "MeshInstance3D", true, false):
		var reason := _skip_reason(source, source_root, protected)
		if not reason.is_empty():
			skipped[reason] = int(skipped.get(reason, 0)) + 1
			continue
		var point := to_local(source.global_position)
		var cell := Vector2i(floori(point.x / CELL_SIZE), floori(point.z / CELL_SIZE))
		var key := str(source.mesh.get_instance_id()) + ":" + str(cell)
		for property in INSTANCE_PROPERTIES: key += ":" + str(source.get(property))
		for surface in source.mesh.get_surface_count(): key += ":" + str(source.get_active_material(surface).get_instance_id())
		if not groups.has(key): groups[key] = {"cell": cell, "sources": []}
		groups[key].sources.append(source)
	var prepared_meshes: Dictionary = {}
	for group: Dictionary in groups.values():
		var instances: Array = group.sources
		if instances.size() < MIN_INSTANCES: continue
		var first: MeshInstance3D = instances[0]
		var material_key := str(first.mesh.get_instance_id())
		for surface in first.mesh.get_surface_count(): material_key += ":" + str(first.get_active_material(surface).get_instance_id())
		if not prepared_meshes.has(material_key):
			var mesh: ArrayMesh = first.mesh.duplicate()
			for surface in mesh.get_surface_count(): mesh.surface_set_material(surface, first.get_active_material(surface))
			prepared_meshes[material_key] = mesh
		var instance := MultiMeshInstance3D.new()
		instance.name = "StaticCell_%s_%s_%s" % [group.cell.x, group.cell.y, batches.size()]
		for property in INSTANCE_PROPERTIES: instance.set(property, first.get(property))
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = prepared_meshes[material_key]
		multimesh.instance_count = instances.size()
		instance.multimesh = multimesh
		add_child(instance)
		instance.position = Vector3(group.cell.x * CELL_SIZE, 0, group.cell.y * CELL_SIZE)
		for index in instances.size():
			var source: MeshInstance3D = instances[index]
			multimesh.set_instance_transform(index, instance.global_transform.affine_inverse() * source.global_transform)
			sources.append(source)
			source_layers.append(source.layers)
		batches.append(instance)
	statistics = {"source_instances": sources.size(), "batches": batches.size(), "cell_size": CELL_SIZE, "skipped": skipped}
	set_enabled(true)

func set_enabled(value: bool) -> void:
	enabled = value
	for index in sources.size():
		if is_instance_valid(sources[index]): sources[index].layers = 0 if enabled else source_layers[index]
	for batch in batches: batch.visible = enabled

func _skip_reason(source: MeshInstance3D, source_root: Node3D, protected: Array[Node]) -> String:
	if not source.is_visible_in_tree(): return "hidden"
	if not source.mesh is ArrayMesh or source.skin != null or source.mesh.get_blend_shape_count() > 0: return "deforming_mesh"
	if source.global_transform.basis.determinant() <= 0.0: return "mirrored_transform"
	if source.visibility_range_begin != 0.0 or source.visibility_range_end != 0.0 or source.transparency != 0.0 or source.material_overlay != null or not source.visibility_parent.is_empty(): return "instance_effect"
	for node in protected:
		if node == source or node.is_ancestor_of(source) or source.is_ancestor_of(node): return "interactive_or_animated"
	var ancestor: Node = source
	while ancestor != source_root:
		if ancestor.get_script() != null: return "scripted_branch"
		ancestor = ancestor.get_parent()
	for surface in source.mesh.get_surface_count():
		var material := source.get_active_material(surface)
		if not material is StandardMaterial3D: return "shader_material"
		if material.transparency not in [BaseMaterial3D.TRANSPARENCY_DISABLED, BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR] or material.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED or material.next_pass != null: return "sorted_or_animated_material"
	return ""
