extends SceneTree

var rows: Array = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for action in ["move_left", "move_right", "move_up", "move_down"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	Engine.max_fps = 0
	OS.low_processor_usage_mode = false
	if DisplayServer.get_name() != "headless": DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var canvas := SubViewport.new()
	canvas.size = Vector2i(2460, 1080)
	canvas.own_world_3d = true
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	if DisplayServer.get_name() != "headless":
		var display := TextureRect.new()
		display.texture = canvas.get_texture()
		display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		root.add_child(display)
	var world := DungeonWorld.new()
	canvas.add_child(world)
	for id in [1010107]:
		world.load_environment(id)
		Engine.max_fps = 0
		var combat := DungeonCombat.new()
		combat.configure()
		world.create_player(combat, 1)
		world.player.position = Vector3(38.3509407, -0.0498943, 74.3497009)
		world.player.reset_physics_interpolation()
		world.auto_attack_enabled = false
		world.presentation.audio_enabled = false
		world.snap_camera()
		var inventory := _inventory(world.environment_root, world.camera)
		var static_batch := world.environment_root.get_node_or_null("StaticEnvironmentBatch")
		var variants: Array = []
		if DisplayServer.get_name() != "headless":
			RenderingServer.viewport_set_measure_render_time(canvas.get_viewport_rid(), true)
			for option in [
				{"label": "native_msaa2_shadows", "scale": 1.0, "msaa": Viewport.MSAA_2X, "shadow": true, "batched": false},
				{"label": "mobile1600_msaa2_shadows", "scale": DungeonStyle.render_scale(canvas.size, 1, true), "msaa": Viewport.MSAA_2X, "shadow": true, "batched": false},
				{"label": "mobile1600_no_msaa_shadows", "scale": DungeonStyle.render_scale(canvas.size, 1, true), "msaa": Viewport.MSAA_DISABLED, "shadow": true, "batched": false},
				{"label": "mobile1600_msaa2_no_shadows", "scale": DungeonStyle.render_scale(canvas.size, 1, true), "msaa": Viewport.MSAA_2X, "shadow": false, "batched": false},
				{"label": "mobile1600_msaa2_shadows_batched", "scale": DungeonStyle.render_scale(canvas.size, 1, true), "msaa": Viewport.MSAA_2X, "shadow": true, "batched": true},
			]:
				if static_batch != null: static_batch.set_enabled(option.batched)
				canvas.scaling_3d_scale = option.scale
				canvas.msaa_3d = option.msaa
				Engine.max_fps = 0
				for child in world.get_children():
					if child is DirectionalLight3D: child.shadow_enabled = option.shadow
				for frame in 45: await process_frame
				var values: Array = []
				var cpu: Array = []
				var gpu: Array = []
				var process_ms: Array = []
				var physics_ms: Array = []
				for frame in 120:
					var started := Time.get_ticks_usec()
					await process_frame
					values.append((Time.get_ticks_usec() - started) / 1000.0)
					cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(canvas.get_viewport_rid()))
					gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(canvas.get_viewport_rid()))
					process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
					physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
				var rid := canvas.get_viewport_rid()
				print("ENVIRONMENT_VARIANT ", id, " ", option.label)
				var capture := ""
				if option.label in ["mobile1600_msaa2_shadows", "mobile1600_msaa2_shadows_batched"]:
					await RenderingServer.frame_post_draw
					capture = "/private/tmp/city-environment-" + option.label + ("-source-modes" if world.environment_root.has_meta("source_renderer_modes") else "") + ".png"
					canvas.get_texture().get_image().save_png(capture)
				variants.append({"option": option, "actual_scale": canvas.scaling_3d_scale,
					"viewport_size": [canvas.size.x, canvas.size.y], "capture": capture, "frame_ms": _timing(values),
					"render_cpu_ms": _timing(cpu), "render_gpu_ms": _timing(gpu),
					"process_ms": _timing(process_ms), "physics_ms": _timing(physics_ms),
					"visible_draws": RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
					"shadow_draws": RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
					"visible_objects": RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME),
					"visible_primitives": RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)})
		rows.append({"environment": id, "inventory": inventory, "renderer_modes": world.environment_root.get_meta("source_renderer_modes", {}), "batch": static_batch.statistics if static_batch != null else {}, "variants": variants})
		world.release_environment()
		await process_frame
	var report := {"display": DisplayServer.get_name(), "renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(), "rows": rows}
	var output := "/private/tmp/city-environment-performance-" + RenderingServer.get_current_rendering_method() + ".json"
	FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("ENVIRONMENT_PERFORMANCE ", JSON.stringify(report))
	world.queue_free()
	canvas.queue_free()
	await process_frame
	quit()

func _timing(values: Array) -> Dictionary:
	values.sort()
	var total := 0.0
	for value: float in values: total += value
	return {"mean": total / maxf(1, values.size()), "p50": values[values.size() / 2], "p95": values[ceili(values.size() * 0.95) - 1]}

func _inventory(scene: Node3D, camera: Camera3D) -> Dictionary:
	var meshes: Dictionary = {}
	var materials: Dictionary = {}
	var groups: Dictionary = {}
	var names: Dictionary = {}
	var triangles := 0
	var surfaces := 0
	var instances := 0
	var shadows := 0
	var shadow_modes: Dictionary = {}
	var approximate_visible := 0
	var transparent_surfaces := 0
	var double_sided_surfaces := 0
	for instance: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		if not instance.mesh or not instance.is_visible_in_tree(): continue
		instances += 1
		var mesh_id := instance.mesh.get_instance_id()
		if not meshes.has(mesh_id): meshes[mesh_id] = instance.mesh.get_faces().size() / 3
		triangles += meshes[mesh_id]
		var key := str(mesh_id) + ":" + str(instance.cast_shadow)
		if instance.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF: shadows += 1
		shadow_modes[str(instance.cast_shadow)] = int(shadow_modes.get(str(instance.cast_shadow), 0)) + 1
		if camera.is_position_in_frustum(instance.global_transform * instance.get_aabb().get_center()): approximate_visible += 1
		for index in instance.mesh.get_surface_count():
			surfaces += 1
			var material := instance.get_active_material(index)
			if material:
				materials[material.get_instance_id()] = true
				key += ":" + str(material.get_instance_id())
				names[material.resource_name] = int(names.get(material.resource_name, 0)) + 1
				if material is BaseMaterial3D:
					if material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED: transparent_surfaces += 1
					if material.cull_mode == BaseMaterial3D.CULL_DISABLED: double_sided_surfaces += 1
		groups[key] = int(groups.get(key, 0)) + 1
	var duplicated_instances := 0
	var largest_group := 0
	for count: int in groups.values():
		if count > 1: duplicated_instances += count
		largest_group = maxi(largest_group, count)
	return {"mesh_instances": instances, "unique_meshes": meshes.size(), "unique_materials": materials.size(),
		"surfaces": surfaces, "triangles": triangles, "shadow_casters": shadows, "shadow_modes": shadow_modes,
		"approximate_visible_centers": approximate_visible, "transparent_surfaces": transparent_surfaces,
		"double_sided_surfaces": double_sided_surfaces, "mesh_material_groups": groups.size(),
		"repeated_group_instances": duplicated_instances, "largest_repeated_group": largest_group, "material_usage": names}
