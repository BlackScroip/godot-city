extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var canvas := SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var world := DungeonWorld.new()
	canvas.add_child(world)
	world.load_environment(1010101)
	world.set_process(false)
	world.set_physics_process(false)
	var presentation = world.environment_root.get_node("RoomProps")
	if presentation.door_materials.materials.size() < 8: failures.append("Both source barriers must recover all four layers")
	for material in presentation.door_materials.materials:
		if not material.get_shader_parameter("source_shapes"): failures.append("Barrier must use recovered source shader properties")
	presentation.set_process(false)
	var environment_effects = world.environment_root.get_node("EnvironmentEffects")
	environment_effects.set_process(false)
	world.interactions.set_battle_boundaries_active(true)
	var target := world.environment_root.to_global(Vector3(88, 0, 46))
	world.camera.global_position = target + Vector3(0, 10, -14)
	world.camera.look_at(target + Vector3.UP * 1.5)
	world.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	world.camera.size = 14
	for size in [Vector2i(1600, 900), Vector2i(844, 390)]:
		canvas.size = size
		var closed_picture: Image
		for closed in [true, false]:
			world.interactions.set_battle_boundaries_active(closed)
			for item in world.interactions._items.values():
				if item.marker.Type != "EEUT_CloseArea": continue
				if item.state.enabled != closed or item.visual.is_visible_in_tree() != closed:
					failures.append("Boundary state and actual visibility must follow battle closure")
				var visible_layers := 0
				for mesh in item.visual.find_children("*", "MeshInstance3D", true, false):
					if mesh.is_visible_in_tree(): visible_layers += 1
				if closed and visible_layers < 4: failures.append("Closed boundary must display all four source mesh layers")
				if not closed and visible_layers != 0: failures.append("Open boundary must remove every source mesh layer")
				for body in item.bodies:
					var expected: int = int(body.layer) if closed else 0
					if body.node.collision_layer != expected: failures.append("Visible closure and actual collision must switch together")
			for frame in 4: await process_frame
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				var picture := canvas.get_texture().get_image()
				if picture.is_empty(): failures.append("Empty door capture")
				picture.save_png("/private/tmp/door-%s-%dx%d.png" % ["closed" if closed else "open", size.x, size.y])
				if closed:
					closed_picture = picture
					presentation.door_materials.tick(1.5)
					for frame in 4: await process_frame
					await RenderingServer.frame_post_draw
					for material in presentation.door_materials.materials:
						if not is_equal_approx(float(material.get_shader_parameter("clock")), 1.5):
							failures.append("Source material clocks must advance")
					presentation.door_materials.tick(0)
				else:
					var changed := 0
					for y in range(size.y / 3, size.y * 2 / 3, 2):
						for x in range(size.x / 3, size.x * 2 / 3, 2):
							var before := closed_picture.get_pixel(x, y)
							var after := picture.get_pixel(x, y)
							if before.r - after.r > 0.05 and before.b - after.b > 0.05: changed += 1
					if changed < 100: failures.append("Opening must visibly remove the purple barrier from the passage")
	var door: Dictionary = {}
	for item in world.interactions._items.values():
		if item.marker.Type == "EEUT_StageChangeDoor": door = item
	if door.is_empty():
		failures.append("Reference room must contain its stage door")
	else:
		target = world.environment_root.to_global(door.position)
		world.camera.global_position = target + Vector3(0, 11, -14)
		world.camera.look_at(target + Vector3.UP * 1.5)
		world.camera.size = 12
		for size in [Vector2i(1600, 900), Vector2i(844, 390)]:
			canvas.size = size
			for enabled in [false, true]:
				world.interactions.set_exit_enabled(enabled)
				presentation._process(0.01)
				if not door.visual.visible: failures.append("Stage door stone frame remains visible when locked")
				for frame in 20: await process_frame
				var effects = world.environment_root.get_node("EnvironmentEffects")
				for frame in 30: effects._process(1.0 / 60.0)
				for binding in effects.bindings:
					if binding.address == "24040202_fx_env_protal_exit":
						if binding.active != enabled: failures.append("Exit particles follow door unlock state")
				if DisplayServer.get_name() != "headless":
					await RenderingServer.frame_post_draw
					canvas.get_texture().get_image().save_png("/private/tmp/door-portal-%s-%dx%d.png" % ["open" if enabled else "locked", size.x, size.y])
	world.free()
	canvas.free()
	print("DOOR PRESENTATION ", "PASS" if failures.is_empty() else "FAIL", failures)
	quit(0 if failures.is_empty() else 1)
