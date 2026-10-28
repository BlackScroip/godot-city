extends SceneTree

var checks := 0
var failures: Array[String] = []
var material_counts: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _run() -> void:
	var world := DungeonWorld.new()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.presentation.set_process(false)
	world.presentation.audio_enabled = false
	world.paused = true
	for id in [1010101, 1010102, 1010101, 1010102]:
		world.load_environment(id)
		check(is_instance_valid(world.environment_root), "Room %d loads after the previous release" % id)
		var references := _room_resources(world)
		check(not references.materials.is_empty(), "Room %d creates styled surface materials" % id)
		var count := DungeonWorldStyle._materials.size()
		if material_counts.has(id):
			check(count == int(material_counts[id]), "Reloading room %d does not grow the material cache" % id)
		material_counts[id] = count
		var probe := _texture_probe(world)
		world.release_environment()
		check(DungeonWorldStyle._materials.is_empty(), "Room release drops all global material references")
		check(world.environment_root == null and world.interactions == null, "Released room detaches its scene and interactions")
		await process_frame
		check(references.root.get_ref() == null, "Released environment nodes are freed")
		for reference: WeakRef in references.materials:
			check(reference.get_ref() == null, "A released room material is no longer retained")
		check(probe.material.get_ref() == null, "The styled probe material is freed")
		check(probe.texture.get_ref() == null, "The previous room's unique texture is freed")
	world.release_environment()
	check(DungeonWorldStyle._materials.is_empty(), "Repeated release is safe")
	world.queue_free()
	await process_frame
	print("WORLD_RESOURCE_RELEASE_TEST ", JSON.stringify({"checks": checks, "failures": failures, "material_counts": material_counts, "passed": failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)

func _room_resources(world: DungeonWorld) -> Dictionary:
	var materials: Array[WeakRef] = []
	for material: Material in DungeonWorldStyle._materials.values():
		materials.append(weakref(material))
	for node: MeshInstance3D in world.environment_root.find_children("*", "MeshInstance3D", true, false):
		if not node.mesh: continue
		for surface in node.mesh.get_surface_count():
			check(node.get_active_material(surface) != null, "Reloaded geometry retains its material bindings")
	return {"root": weakref(world.environment_root), "materials": materials}

func _texture_probe(world: DungeonWorld) -> Dictionary:
	var probe := Node3D.new()
	world.environment_root.add_child(probe)
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.GREEN)
	var texture := ImageTexture.create_from_image(image)
	var source := StandardMaterial3D.new()
	source.resource_name = "RoomReleaseProbe"
	source.albedo_texture = texture
	var mesh := BoxMesh.new()
	mesh.material = source
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	probe.add_child(visual)
	DungeonWorldStyle.apply_models(probe)
	var styled := visual.get_active_material(0)
	check(styled != source and styled.albedo_texture == texture, "Styled material preserves the source texture")
	return {"material": weakref(styled), "texture": weakref(texture)}
