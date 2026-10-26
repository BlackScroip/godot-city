extends SceneTree

const Batch = preload("res://scripts/presentation/static_environment_batch.gd")
var checks := 0
var failures: Array[String] = []

class ProbeWorld extends Node3D:
	var interactions := DungeonWorldInteractions.new()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var world := ProbeWorld.new()
	root.add_child(world)
	world.position = Vector3(13, 0, -9)
	var source_root := Node3D.new()
	world.add_child(source_root)
	var mesh := ArrayMesh.new()
	var cube := BoxMesh.new()
	for surface in 2: mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, cube.get_mesh_arrays())
	var original := StandardMaterial3D.new()
	mesh.surface_set_material(0, original)
	mesh.surface_set_material(1, original)
	var first := StandardMaterial3D.new()
	first.albedo_color = Color.RED
	var second := StandardMaterial3D.new()
	second.albedo_color = Color.GREEN
	second.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	var static_sources: Array[MeshInstance3D] = []
	for index in 6:
		var source := _mesh(source_root, mesh, first, second)
		source.position = Vector3((index % 3) * 2 + (24 if index >= 3 else 0), 0, 2)
		source.rotation.y = index * 0.17
		source.scale = Vector3.ONE * (1.0 + index * 0.04)
		source.add_child(Node3D.new())
		static_sources.append(source)
	var protected_sources: Array[MeshInstance3D] = []
	var interactive := Node3D.new()
	source_root.add_child(interactive)
	world.interactions._items["breakable"] = {"visual": interactive}
	for index in 3: protected_sources.append(_mesh(interactive, mesh, first, second))
	var animated := Node3D.new()
	source_root.add_child(animated)
	var animator := AnimationPlayer.new()
	animated.add_child(animator)
	for index in 3: protected_sources.append(_mesh(animated, mesh, first, second))
	for index in 3:
		var hidden := _mesh(source_root, mesh, first, second)
		hidden.visible = false
		protected_sources.append(hidden)
	for index in 3:
		var mirrored := _mesh(source_root, mesh, first, second)
		mirrored.scale.x = -1
		protected_sources.append(mirrored)
	var transparent := StandardMaterial3D.new()
	transparent.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for index in 3: protected_sources.append(_mesh(source_root, mesh, transparent, second))
	var shader := ShaderMaterial.new()
	for index in 3:
		var custom := _mesh(source_root, mesh, first, second)
		custom.set_surface_override_material(0, shader)
		protected_sources.append(custom)
	var batch := Batch.new()
	world.add_child(batch)
	batch.configure(world, source_root)
	await process_frame
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw
	check(batch.sources.size() == 6, "Only static opaque or alpha-cutout source geometry is batched")
	check(batch.batches.size() == 2, "Repeated geometry stays in separate 12-meter spatial cells")
	check(batch.statistics.skipped.get("interactive_or_animated", 0) == 6, "Both semantic interaction and AnimationPlayer roots are protected")
	check(mesh.surface_get_material(0) == original and mesh.surface_get_material(1) == original, "Preparing surface overrides never mutates the shared source mesh")
	for source in static_sources:
		check(source.visible and source.get_child(0).is_visible_in_tree(), "Batching preserves source and descendant visibility")
		check(source.layers == 0, "Batched source draws are disabled without hiding their node hierarchy")
		# The headless dummy renderer does not retain MultiMesh instance transforms.
		if DisplayServer.get_name() != "headless":
			var matches := 0
			for instance: MultiMeshInstance3D in batch.batches:
				for index in instance.multimesh.instance_count:
					if (instance.global_transform * instance.multimesh.get_instance_transform(index)).is_equal_approx(source.global_transform): matches += 1
			check(matches == 1, "Every source transform appears exactly once in the rendered batches")
	for source in protected_sources: check(source.layers == 4, "Excluded interactive, hidden, animated, mirrored and sorted source nodes retain their render layers")
	for instance: MultiMeshInstance3D in batch.batches:
		check(instance.layers == 4 and instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED, "Each batch preserves source render and shadow settings")
		check(instance.multimesh.mesh.surface_get_material(0) == first and instance.multimesh.mesh.surface_get_material(1) == second, "Every surface retains its exact material reference and cutout mode")
	batch.set_enabled(false)
	for source in static_sources: check(source.layers == 4, "Disabling the diagnostic comparison restores every original render layer")
	for instance: MultiMeshInstance3D in batch.batches: check(not instance.visible, "Disabled batches do not duplicate original draws")
	batch.set_enabled(true)
	check(batch.enabled and static_sources[0].layers == 0, "Batching can be enabled again without rebuilding source geometry")
	world.queue_free()
	await process_frame
	print("STATIC_ENVIRONMENT_BATCH ", JSON.stringify({"checks": checks, "failures": failures, "rendered_transform_checks": DisplayServer.get_name() != "headless"}))
	quit(0 if failures.is_empty() else 1)

func _mesh(parent: Node3D, mesh: ArrayMesh, first: StandardMaterial3D, second: StandardMaterial3D) -> MeshInstance3D:
	var source := MeshInstance3D.new()
	source.mesh = mesh
	parent.add_child(source)
	source.layers = 4
	source.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	source.set_surface_override_material(0, first)
	source.set_surface_override_material(1, second)
	return source
