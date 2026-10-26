extends SceneTree

var checks := 0
var failures: Array[String] = []
var observations: Array = []

# CPU skinning of the original Unity meshes, bone world transforms and bind poses.
const SOURCE_BOSS_REST_BOUNDS := {
	13002: AABB(Vector3(-7.564566, -0.045964, -2.410549), Vector3(15.129134, 8.464409, 3.763420)),
	23002: AABB(Vector3(-1.972192, -0.002575, -7.452678), Vector3(3.944386, 4.332931, 11.282354))
}

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for action in ["move_left", "move_right", "move_up", "move_down"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	var canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.own_world_3d = true
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var world = DungeonWorld.new()
	canvas.add_child(world)
	world.set_physics_process(false)
	world.presentation.audio_enabled = false
	var imports: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://reports/region-actor-import.json")).actors
	var imported := 0
	for key in imports:
		if imports[key].status != "imported": continue
		imported += 1
		var id = int(key)
		var actor = DungeonActor.new()
		actor.actor_id = id
		world.add_child(actor)
		actor.set_process(false)
		actor.set_visual(world.asset_path("enemies", id), world.catalog.enemies.get(key, {}))
		check(actor.visual_loaded and not actor.flash_meshes.is_empty(), "Recovered model loads without fallback: %d" % id)
		check(is_instance_valid(actor.animation) and actor.animations.size() >= imports[key].animations.size(), "Recovered animation library loads: %d" % id)
		for frame in 2: await process_frame
		var rest = _posed_bounds(actor.visual, actor.global_transform.affine_inverse())
		check(rest.meshes > 0 and rest.bounds.size.is_finite() and rest.bounds.size.length() > 0.1, "Recovered posed mesh has finite dimensions: %d" % id)
		if DisplayServer.get_name() != "headless":
			check(rest.baked_meshes == rest.skinned_meshes and rest.bake_error < 0.002, "CPU skin bounds match rendered skeleton vertices: %d" % id)
		if SOURCE_BOSS_REST_BOUNDS.has(id):
			var expected: AABB = SOURCE_BOSS_REST_BOUNDS[id]
			check(rest.bounds.position.distance_to(expected.position) < 0.002 and rest.bounds.end.distance_to(expected.end) < 0.002, "Boss posed dimensions match original Unity bind transforms: %d" % id)
			observations.append({"enemy_id": id, "source_rest_bounds": _bounds_json(expected), "runtime_rest_bounds": _bounds_json(rest.bounds), "rendered_skin_max_error": rest.bake_error})
		if is_instance_valid(actor.animation):
			actor.play_animation(str(imports[key].animations[0].name), true)
			actor.animation.advance(0.35)
			check(actor.animation.current_animation_position > 0.0, "Recovered model animation advances: %d" % id)
		actor.queue_free()
		await process_frame
	check(imported == 20, "All twenty new source models are imported")
	for pair in [[1069101, 13002], [1079101, 23002]]:
		var scene_id = int(pair[0])
		var enemy_id = int(pair[1])
		var campaign = DungeonCampaign.new()
		check(campaign.configure() and campaign.start_practice(scene_id, 123).success, "Authored boss room can start: %d" % scene_id)
		var room = campaign.current_room()
		var spawns = campaign.wave_spawns(1)
		check(spawns.size() == 1 and int(spawns[0].enemy_id) == enemy_id and int(spawns[0].spawn_index) == 1, "Campaign selects the exact source boss and spawn marker")
		world.load_environment(scene_id)
		check(is_instance_valid(world.environment_root) and not world.environment_entry.is_empty(), "Recovered boss environment loads: %d" % scene_id)
		var combat = preload("res://scripts/domain/combat.gd").new()
		combat.configure()
		world.create_player(combat, 1, room.PlayerStart)
		world.player.invulnerability = 10000
		world.spawn_wave(spawns, int(campaign.state.difficulty), 123)
		var actor: DungeonActor = world.actors.back()
		check(actor.actor_id == enemy_id and actor.visual_loaded, "Actual world uses the distinct source boss model")
		check(actor.position.distance_to(world.vector(spawns[0].position) + Vector3.UP * 0.05) < 0.001, "Boss retains its authored world spawn")
		# Position the player around the authored spawn for a model inspection.
		# Keep the source model scale and gameplay camera projection unchanged.
		var entry_position: Vector3 = world.player.position
		actor.play_animation("idle", true)
		actor.animation.advance(0.35)
		world.snap_camera()
		var posed_center: Vector3 = _posed_bounds(actor.visual).bounds.get_center()
		var ray: Vector3 = world.camera.project_ray_normal(Vector2(canvas.size) * Vector2(0.5, 0.45))
		var camera_offset: Vector3 = world.camera.position - world.player.position
		var distance: float = (posed_center.y - camera_offset.y - entry_position.y) / ray.y
		world.player.position = posed_center - camera_offset - ray * distance
		world.player.previous_position = world.player.position
		world.snap_camera()
		for frame in 12: await process_frame
		for dimensions in [Vector2i(1600, 900), Vector2i(844, 390)]:
			canvas.size = dimensions
			for frame in 4: await process_frame
			world.snap_camera()
			var posed = _posed_bounds(actor.visual)
			var projected = _projected_bounds(world.camera, posed.bounds)
			var frame_rect = Rect2(Vector2.ZERO, Vector2(dimensions))
			var visible_rect = projected.intersection(frame_rect)
			check(visible_rect.get_area() > frame_rect.get_area() * 0.04, "Actual boss mesh is framed at %s" % dimensions)
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				var visible = canvas.get_texture().get_image()
				actor.visual.hide()
				await RenderingServer.frame_post_draw
				var hidden = canvas.get_texture().get_image()
				actor.visual.show()
				var pixels := 0
				for y in range(0, dimensions.y, 3):
					for x in range(0, dimensions.x, 3):
						if visible.get_pixel(x, y).to_rgba32() != hidden.get_pixel(x, y).to_rgba32(): pixels += 1
				check(pixels > 80, "Source boss contributes visible pixels: %d" % enemy_id)
				var path = "res://reports/region-boss-%d-%dx%d.png" % [enemy_id, dimensions.x, dimensions.y]
				visible.save_png(path)
				observations.append({"enemy_id": enemy_id, "scene_id": scene_id, "dimensions": [dimensions.x, dimensions.y], "authored_spawn": _vector_json(actor.position), "authored_entry": _vector_json(entry_position), "capture_player": _vector_json(world.player.position), "posed_world_bounds": _bounds_json(posed.bounds), "projected_mesh_rect": [projected.position.x, projected.position.y, projected.size.x, projected.size.y], "changed_pixel_samples": pixels, "capture": path})
		world.release_environment()
		await process_frame
	world.queue_free()
	await process_frame
	canvas.queue_free()
	await process_frame
	var report = {"checks": checks, "passed": failures.is_empty(), "failures": failures, "observations": observations}
	FileAccess.open("res://reports/region-actor-runtime-validation.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("REGION_ACTOR_RUNTIME ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func _posed_bounds(model: Node3D, target_transform := Transform3D.IDENTITY) -> Dictionary:
	var result := {"bounds": AABB(), "meshes": 0, "skinned_meshes": 0, "baked_meshes": 0, "bake_error": 0.0}
	for skeleton in model.find_children("*", "Skeleton3D", true, false): skeleton.force_update_all_bone_transforms()
	for instance in model.find_children("*", "MeshInstance3D", true, false):
		if not instance.mesh: continue
		var bounds := AABB()
		var found := false
		var skeleton = instance.get_node_or_null(instance.skeleton) as Skeleton3D
		if skeleton and instance.skin:
			result.skinned_meshes += 1
			var binds: Array[Transform3D] = []
			var valid_binds := true
			for index in instance.skin.get_bind_count():
				var bone: int = instance.skin.get_bind_bone(index)
				if bone < 0: bone = skeleton.find_bone(instance.skin.get_bind_name(index))
				valid_binds = valid_binds and bone >= 0
				binds.append(skeleton.get_bone_global_pose(bone) * instance.skin.get_bind_pose(index) if bone >= 0 else Transform3D.IDENTITY)
			check(valid_binds, "Imported skin binds resolve to their source bones")
			var transform: Transform3D = target_transform * skeleton.global_transform
			for surface in instance.mesh.get_surface_count():
				var arrays: Array = instance.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
				var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
				var influences: int = weights.size() / vertices.size()
				for index in vertices.size():
					var point := Vector3.ZERO
					for influence in influences:
						var offset: int = index * influences + influence
						if weights[offset] > 0: point += (binds[joints[offset]] * vertices[index]) * weights[offset]
					point = transform * point
					bounds = bounds.expand(point) if found else AABB(point, Vector3.ZERO)
					found = true
			if DisplayServer.get_name() != "headless":
				var baked: ArrayMesh = instance.bake_mesh_from_current_skeleton_pose()
				if baked:
					result.baked_meshes += 1
					var baked_bounds := AABB()
					var baked_found := false
					for surface in baked.get_surface_count():
						for vertex in baked.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
							var point: Vector3 = target_transform * instance.global_transform * vertex
							baked_bounds = baked_bounds.expand(point) if baked_found else AABB(point, Vector3.ZERO)
							baked_found = true
					result.bake_error = maxf(result.bake_error, maxf(bounds.position.distance_to(baked_bounds.position), bounds.end.distance_to(baked_bounds.end)))
		else:
			bounds = target_transform * instance.global_transform * instance.get_aabb()
		result.bounds = result.bounds.merge(bounds) if result.meshes else bounds
		result.meshes += 1
	return result

func _projected_bounds(camera: Camera3D, bounds: AABB) -> Rect2:
	var result := Rect2()
	for index in 8:
		var point = camera.unproject_position(bounds.get_endpoint(index))
		result = result.expand(point) if index else Rect2(point, Vector2.ZERO)
	return result

func _vector_json(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func _bounds_json(value: AABB) -> Dictionary:
	return {"min": _vector_json(value.position), "max": _vector_json(value.end), "size": _vector_json(value.size)}
