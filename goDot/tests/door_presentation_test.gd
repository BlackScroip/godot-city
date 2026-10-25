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
	world.interactions.set_trigger_active(2, true)
	var target := world.environment_root.to_global(Vector3(88, 0, 46))
	world.camera.global_position = target + Vector3(0, 10, -14)
	world.camera.look_at(target + Vector3.UP * 1.5)
	world.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	world.camera.size = 14
	for size in [Vector2i(1600, 900), Vector2i(844, 390)]:
		canvas.size = size
		for closed in [true, false]:
			world.interactions.set_trigger_active(2, closed)
			for frame in 4: await process_frame
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				var picture := canvas.get_texture().get_image()
				if picture.is_empty(): failures.append("Empty door capture")
				picture.save_png("/private/tmp/door-%s-%dx%d.png" % ["closed" if closed else "open", size.x, size.y])
				if closed:
					presentation.door_materials.tick(1.5)
					for frame in 4: await process_frame
					await RenderingServer.frame_post_draw
					var moving := canvas.get_texture().get_image()
					var changed := 0
					for y in range(size.y / 3, size.y * 2 / 3, 2):
						for x in range(size.x / 3, size.x * 2 / 3, 2):
							if moving.get_pixel(x, y) != picture.get_pixel(x, y): changed += 1
					if changed < 20: failures.append("Source barrier flow must animate on screen")
					presentation.door_materials.tick(0)
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
