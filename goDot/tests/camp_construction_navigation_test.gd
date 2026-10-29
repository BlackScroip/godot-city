extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func _run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.save_store = DungeonSaveStore.new("/private/tmp/camp-construction-navigation-%d.json" % Time.get_ticks_usec())
	root.add_child(game)
	await process_frame
	await physics_frame
	var world = game.world
	var region = world.navigation_region
	var changed := 0
	var reused := 0
	for id in range(1, 8):
		for level in range(1, 4):
			var old_key: String = world._camp_navigation_key()
			var old_mesh: NavigationMesh = region.navigation_mesh
			game.profile.data.buildings[str(id)] = level
			world.refresh_camp_progression()
			var new_key: String = world._camp_navigation_key()
			check(world.navigation_region == region, "Construction retains its navigation region")
			check(region.navigation_mesh != null and region.navigation_mesh.get_polygon_count() > 0, "Construction retains usable navigation")
			if new_key == old_key:
				reused += 1
				check(region.navigation_mesh == old_mesh, "Unchanged colliders reuse the existing mesh")
			else:
				changed += 1
				check(world._camp_navigation_pending and region.navigation_mesh == old_mesh, "Changed colliders bake asynchronously while retaining the old mesh")
				world._camp_destination = "pending-test"
				world._camp_stall_time = 0.0
				check(world._camp_navigation_velocity(2.0) == Vector3.ZERO and world._camp_destination == "pending-test" and world._camp_stall_time == 0.0, "Automatic navigation waits without accumulating stall time")
				world._cancel_camp_navigation()
				var deadline := Time.get_ticks_msec() + 30000
				while world._camp_navigation_pending and Time.get_ticks_msec() < deadline:
					await process_frame
				check(not world._camp_navigation_pending, "Background navigation bake finishes")
				check(region.navigation_mesh != old_mesh, "Changed colliders select a different mesh")
			await process_frame
	check(changed > 0, "Construction exercises collider changes")
	check(reused > 0, "Later construction stages reuse navigation")
	game.profile.data.buildings["1"] = 0
	world.refresh_camp_progression()
	game.profile.data.buildings["2"] = 0
	world.refresh_camp_progression()
	var latest_key: String = world._camp_navigation_key()
	var deadline := Time.get_ticks_msec() + 30000
	while world._camp_navigation_pending and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not world._camp_navigation_pending and region.navigation_mesh == world._navigation_cache.get(latest_key), "Rapid construction changes apply only the latest navigation")
	var latest_mesh: NavigationMesh = region.navigation_mesh
	world._finish_camp_navigation("stale", NavigationMesh.new(), world._navigation_generation - 1, world.environment_root)
	check(region.navigation_mesh == latest_mesh and not world._navigation_cache.has("stale"), "A stale bake cannot replace or cache the latest mesh")
	game.profile.data.buildings["3"] = 0
	world.refresh_camp_progression()
	var old_root: Node3D = world.environment_root
	var old_generation: int = world._navigation_generation
	world.release_environment()
	world._finish_camp_navigation("released", NavigationMesh.new(), old_generation, old_root)
	check(not world._camp_navigation_pending and world.navigation_region == null and not world._navigation_cache.has("released"), "A bake cannot update a released environment")
	print("CAMP CONSTRUCTION NAVIGATION: changed=%d reused=%d failures=%s" % [changed, reused, failures])
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
