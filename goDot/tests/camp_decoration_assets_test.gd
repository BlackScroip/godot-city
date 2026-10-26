extends SceneTree

var checks = 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

func _world_transform(node: Node3D) -> Transform3D:
	var result = node.transform
	var parent = node.get_parent()
	while parent is Node3D:
		result = parent.transform * result
		parent = parent.get_parent()
	return result

func _geometry_bounds(root: Node, outer: Transform3D = Transform3D.IDENTITY) -> Dictionary:
	var minimum = Vector3(INF, INF, INF)
	var maximum = Vector3(-INF, -INF, -INF)
	var meshes = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D: meshes.append(root)
	var point_count = 0
	for mesh_instance in meshes:
		if mesh_instance.mesh == null: continue
		var transform = outer * _world_transform(mesh_instance)
		for surface in mesh_instance.mesh.get_surface_count():
			var arrays = mesh_instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices = arrays[Mesh.ARRAY_INDEX]
			var selected = indices if indices != null and not indices.is_empty() else range(vertices.size())
			for index in selected:
				var point = transform * vertices[index]
				minimum = minimum.min(point)
				maximum = maximum.max(point)
				point_count += 1
	if point_count == 0: return {}
	return {"min": [minimum.x, minimum.y, minimum.z], "max": [maximum.x, maximum.y, maximum.z], "vertices": point_count}

func _same_bounds(actual: Dictionary, expected: Dictionary) -> bool:
	return not actual.is_empty() and not expected.is_empty() and _vector(actual.min).distance_to(_vector(expected.min)) < 0.001 and _vector(actual.max).distance_to(_vector(expected.max)) < 0.001

func _overlaps_baseline(actual: Dictionary, originals: Array) -> bool:
	if actual.is_empty(): return false
	var minimum = Vector3(INF, INF, INF)
	var maximum = Vector3(-INF, -INF, -INF)
	for original in originals:
		if original.bounds == null: continue
		minimum = minimum.min(_vector(original.bounds.min))
		maximum = maximum.max(_vector(original.bounds.max))
	var actual_min = _vector(actual.min)
	var actual_max = _vector(actual.max)
	return maxf(minimum.x, actual_min.x) <= minf(maximum.x, actual_max.x) and maxf(minimum.z, actual_min.z) <= minf(maximum.z, actual_max.z)

func _run() -> void:
	var index = JSON.parse_string(FileAccess.get_file_as_string("res://assets/environments/camp_decorations/index.json"))
	check(index.decorations.size() == 25 and index.scene_placement.slots.size() == 9, "source index covers every configured decoration and slot")
	var camp: Node = load("res://assets/environments/EnvDesignMap_MainCity.glb").instantiate()
	var renderers = {}
	var world_bounds = {}
	for key in index.decorations:
		var entry: Dictionary = index.decorations[key]
		var packed = load(entry.path)
		check(packed is PackedScene, "source prefab imports as a scene: " + key)
		if not packed is PackedScene: continue
		var instance = packed.instantiate()
		var meshes = instance.find_children("*", "MeshInstance3D", true, false)
		var conversion = JSON.parse_string(FileAccess.get_file_as_string(str(entry.path).get_basename() + ".conversion.json"))
		check(meshes.size() == conversion.renderers.size() and meshes.size() > 0, "every active source mesh renderer survives import: " + key)
		var valid = true
		for mesh_instance in meshes:
			valid = valid and mesh_instance.mesh != null and mesh_instance.get_aabb().size.length_squared() > 0.00001
		check(valid, "imported appearance has nonblank source geometry: " + key)
		renderers[key] = meshes.size()
		var slot: Dictionary = index.scene_placement.slots[str(int(entry.slot_id))]
		var container: Node3D = camp.find_child(str(slot.baseline.exported_node_name), true, false)
		if container != null:
			var actual = _geometry_bounds(instance, _world_transform(container))
			world_bounds[key] = actual
			check(_same_bounds(actual, entry.world_bounds), "imported indexed vertices preserve authored source world bounds: " + key)
			check(_overlaps_baseline(actual, slot.baseline.original_world_bounds), "actual building geometry overlaps original facility area: " + key)
		instance.free()
	for key in index.scene_placement.slots:
		var slot: Dictionary = index.scene_placement.slots[key]
		var container: Node3D = camp.find_child(str(slot.baseline.exported_node_name), true, false)
		check(container != null, "source ArtLayer decoration container maps to baseline: " + key)
		if container == null: continue
		var transform = _world_transform(container)
		var source: Array = slot.world_matrix
		var expected = Vector3(float(source[3]), float(source[7]), float(source[11]))
		check(transform.origin.distance_to(expected) < 0.0001, "baseline placement matches new source world position: " + key)
		var expected_basis = Basis(Vector3(source[0], source[4], source[8]), Vector3(source[1], source[5], source[9]), Vector3(source[2], source[6], source[10]))
		check(transform.basis.is_equal_approx(expected_basis), "baseline placement matches source rotation and scale: " + key)
		check(slot.baseline.replace_children.size() == 2, "legacy ruins and repaired geometry have explicit replacement roots: " + key)
		for original in slot.baseline.original_world_bounds:
			var original_root = camp.find_child(str(original.exported_node_name), true, false)
			check(original_root != null, "baseline building subtree exists: " + str(original.exported_node_name))
			if original_root != null:
				var original_actual = _geometry_bounds(original_root)
				var matches = original_actual.is_empty() if original.bounds == null else _same_bounds(original_actual, original.bounds)
				check(matches, "baseline indexed world geometry matches source evidence: " + str(original.exported_node_name))
	for anchor in [["1000", "1", 0], ["2000", "2", 0], ["8000", "8", 0], ["8001", "8", 1]]:
		var original = index.scene_placement.slots[anchor[1]].baseline.original_world_bounds[anchor[2]].bounds
		check(_same_bounds(world_bounds.get(anchor[0], {}), original), "unchanged original appearance has identical world geometry: " + anchor[0])
	camp.free()
	var result = {"checks": checks, "failures": failures, "passed": failures.is_empty(), "mesh_instances": renderers, "world_bounds": world_bounds, "scope": "Godot imports all 25 recovered prefab GLBs with every active source mesh renderer. Actual indexed world vertices match source bounds and original facility areas, including four unchanged appearance anchors; all nine container transforms and 18 original subtrees are verified. Distant authored pivots are preserved. Does not verify original Unity shader or particle parity."}
	var file = FileAccess.open("res://reports/camp-decoration-assets-tests.json", FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(result, "\t"))
	print("CAMP_DECORATION_ASSETS_TEST ", JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
