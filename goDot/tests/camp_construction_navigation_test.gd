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
				check(region.navigation_mesh != old_mesh, "Changed colliders select a different mesh")
			await process_frame
	check(changed > 0, "Construction exercises collider changes")
	check(reused > 0, "Later construction stages reuse navigation")
	print("CAMP CONSTRUCTION NAVIGATION: changed=%d reused=%d failures=%s" % [changed, reused, failures])
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
