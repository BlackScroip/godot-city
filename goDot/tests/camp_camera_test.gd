extends SceneTree

var failures: Array[String] = []
var checks := 0
var canvas: SubViewport
var visual := false
var _foreground_simulation: Callable

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		push_error(description)

func _run() -> void:
	visual = "--visual" in OS.get_cmdline_user_args()
	var controller = preload("res://scripts/presentation/camp_camera.gd").new()
	var camera := Camera3D.new()
	controller.configure(camera, {"camera_rotation": [45.0, -45.0]})
	check(camera.projection == Camera3D.PROJECTION_PERSPECTIVE and is_equal_approx(camera.fov, 45.0), "Camp uses source perspective and field of view")
	check(controller.offset().is_equal_approx(Vector3(6.5, sqrt(0.5) * 13.0, -6.5)), "Camp uses source 45/-45 orientation and 13-unit baseline")
	controller.zoom(-100)
	check(controller.target_distance == 8.0, "Zoom cannot cross source minimum")
	controller.zoom(100)
	check(controller.target_distance == 15.0, "Zoom cannot cross source maximum")
	controller.focus(Vector3(1, 2, 3), 2.4)
	controller.step(1.0, true)
	check(controller.focus_remaining == 2.4, "Open modal preserves construction focus duration")
	controller.step(3.0)
	check(controller.target(Vector3(4, 0, 5)).is_equal_approx(Vector3(4, 0.4, 5)), "Expired focus returns to the player")
	check(is_equal_approx(controller.follow_weight(1.0 / 60.0), 0.08), "Follow smoothing agrees with source at 60 Hz")
	camera.free()
	var game = load("res://scenes/main.tscn").instantiate()
	game.save_store = DungeonSaveStore.new("/tmp/camp-camera-test-%d.json" % Time.get_ticks_usec())
	if visual:
		canvas = SubViewport.new()
		canvas.size = Vector2i(1600, 900)
		canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(canvas)
		var display := TextureRect.new()
		display.texture = canvas.get_texture()
		display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.add_child(display)
		canvas.add_child(game)
	else: root.add_child(game)
	await process_frame
	await physics_frame
	var world = game.world
	if visual:
		# Concurrent graphical test windows can steal OS focus; simulate the active
		# window here while product background suspension remains covered separately.
		_foreground_simulation = func():
			if is_instance_valid(world): world._background = false
		process_frame.connect(_foreground_simulation)
		world._background = false
	check(world.camera.projection == Camera3D.PROJECTION_PERSPECTIVE and is_equal_approx(world._camera_offset.length(), 13.0), "World installs camp controller on entry")
	var initial_levels: Dictionary = game.profile.data.buildings.duplicate(true)
	for entry in world.camp_progression.variants:
		check(entry.active == (entry.built == (int(initial_levels.get(str(entry.building_id), 0)) > 0)), "Initial scene variant follows saved building rank")
		if "ArtLayer" in str(entry.node.get_path()):
			check(not entry.node.find_children("*", "MeshInstance3D", true, false).is_empty(), "Each original art branch contains restored source geometry: " + str(entry.node.name))
	var original_layers: Dictionary = {}
	for marker in world.markers:
		var body = world.environment_root.get_node_or_null("Collider_" + str(marker.get("fileID", "")))
		if body is StaticBody3D: original_layers[str(body.name)] = body.collision_layer
	for id in range(1, 8): game.profile.data.buildings[str(id)] = 1
	world.refresh_camp_progression()
	check(world.camp_progression.variants.size() >= 28, "Both source art and functionality variants are found for all seven facilities")
	for entry in world.camp_progression.variants:
		check(entry.node.visible == entry.built, "Built facilities hide ruins and show repaired source branches")
	_check_npc_labels(world)
	var changed_colliders := 0
	for marker in world.markers:
		var body = world.environment_root.get_node_or_null("Collider_" + str(marker.get("fileID", "")))
		if not body is StaticBody3D: continue
		if world.camp_progression.controls(str(marker.get("exported_node_name", ""))):
			check(body.collision_layer == (1 if world.camp_progression.collider_active(marker) else 0), "Variant collision matches source branch visibility")
			if original_layers.get(str(body.name), body.collision_layer) != body.collision_layer: changed_colliders += 1
		else: check(body.collision_layer == original_layers[str(body.name)], "Shared whitebox collision is unchanged by construction")
	check(changed_colliders > 0, "Construction removes abandoned signpost blockers")
	check(world.navigation_region.navigation_mesh.get_polygon_count() > 0, "Construction refresh preserves a usable navigation mesh")
	game.profile.data.buildings = initial_levels.duplicate(true)
	world.refresh_camp_progression()
	_check_npc_labels(world)
	for marker in world.markers:
		var body = world.environment_root.get_node_or_null("Collider_" + str(marker.get("fileID", "")))
		if body is StaticBody3D: check(body.collision_layer == original_layers[str(body.name)], "Restoring saved rank restores exact collision activation")
	for page in ["buildings", "characters", "weapons", "archive", "partners", "tasks", "meals", "awakening", "primary", "work", "talents"]:
		check(not world.camp_facility(page).is_empty(), "Recovered camp facility resolves: " + page)
	check(world.camp_facility("difficulty").id == world.camp_facility("primary").id, "Hidden below-ground difficulty marker routes to departure gate")
	for building_id in range(1, 8):
		for stage in range(1, 4):
			check(world.focus_camp_building(building_id, stage), "Authored construction focus resolves %d/%d" % [building_id, stage])
	check(not world.focus_camp_building(1, 0) and not world.focus_camp_building(1, 4), "Construction focus rejects invalid stages")
	world.camp_camera.focus_remaining = 0.0
	world.snap_camera()
	if visual:
		for dimensions in [Vector2i(1600, 900), Vector2i(844, 390)]:
			canvas.size = dimensions
			for frame in 12: await process_frame
			world.snap_camera()
			await _capture(world, "%dx%d" % [dimensions.x, dimensions.y], true)
		world.focus_camp_building(3, 1, 30.0)
		for frame in 80: await process_frame
		await _capture(world, "smith-focus", false)
		game.profile.data.buildings["3"] = 1
		world.refresh_camp_progression()
		world.focus_camp_building(3, 1, 30.0)
		for frame in 12: await process_frame
		await _capture(world, "smith-built", false)
		game.profile.data.buildings = initial_levels.duplicate(true)
		world.refresh_camp_progression()
		world.camp_camera.focus_remaining = 0.0
		world.snap_camera()
	var task: Dictionary = world.camp_facility("tasks")
	world.player.position = task.position + Vector3(2, 0.05, -4)
	world.snap_camera()
	var screen: Vector2 = world.camera.unproject_position(task.position + Vector3.UP * 0.7)
	check(world.camp_marker_at_screen(screen) == str(task.id), "Facility screen projection selects authored marker")
	check(world.camp_marker_at_screen(Vector2(-100, -100)).is_empty(), "Offscreen clicks do not select a facility")
	var press := InputEventScreenTouch.new()
	press.index = 2
	press.position = screen
	press.pressed = true
	world._unhandled_input(press)
	var release := InputEventScreenTouch.new()
	release.index = 2
	release.position = screen + Vector2(40, 0)
	world._unhandled_input(release)
	check(world._camp_destination.is_empty(), "Dragging across a facility does not activate navigation")
	world._unhandled_input(press)
	release.position = screen
	world._unhandled_input(release)
	check(world._camp_destination == str(task.id), "Touch release selects the same authored facility")
	check(world.navigate_to_camp_facility("tasks"), "Camp navigation accepts valid facility")
	for frame in 360:
		await physics_frame
		if game.hud.modal_open: break
	check(game.hud.modal_open and game.menus.current_page == "tasks", "Click navigation walks into range and opens exact facility")
	check(world._camp_destination.is_empty(), "Arrival consumes navigation target")
	game._close_page()
	await physics_frame
	check(world.navigate_to_camp_facility("weapons"), "Another facility can be selected")
	world.clear_input()
	check(world._camp_destination.is_empty(), "Input suspension cancels navigation")
	world._camp_camera = false
	check(not world.navigate_to_camp_facility("tasks") and not world.focus_camp_facility("tasks"), "Camp controls cannot activate in a dungeon")
	print("Camp camera/navigation: %d checks, failures=%s" % [checks, failures])
	if _foreground_simulation.is_valid(): process_frame.disconnect(_foreground_simulation)
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _check_npc_labels(world: Node3D) -> void:
	var count := 0
	for label in world.environment_root.find_children("*", "Label3D", true, false):
		if not label.has_meta("camp_marker_id"): continue
		count += 1
		var item: Dictionary = world.interactions._items.get(str(label.get_meta("camp_marker_id")), {})
		check(label.visible == (not item.is_empty() and bool(item.get("visible", false))), "NPC labels follow construction interaction visibility")
	check(count > 0, "Source NPC labels retain their interaction marker binding")

func _capture(world: Node3D, suffix: String, check_player: bool) -> void:
	await RenderingServer.frame_post_draw
	var frame := canvas.get_texture().get_image()
	check(frame != null and not frame.is_empty(), "Rendered camp frame exists: " + suffix)
	if frame == null or frame.is_empty(): return
	var colors: Dictionary = {}
	for y in range(frame.get_height() / 4, frame.get_height() * 3 / 4, 12):
		for x in range(frame.get_width() / 4, frame.get_width() * 3 / 4, 12):
			colors[frame.get_pixel(x, y).to_html(false)] = true
	check(colors.size() > 80, "Camp scene contains rendered geometry and textures: " + suffix)
	if check_player:
		var point: Vector2 = world.camera.unproject_position(world.player.position + Vector3.UP * 0.7)
		var safe := Rect2(Vector2(canvas.size) * Vector2(0.15, 0.18), Vector2(canvas.size) * Vector2(0.7, 0.56))
		check(safe.has_point(point), "Player remains in central safe region: " + suffix)
	var path := "/tmp/camp-camera-" + suffix + ".png"
	check(frame.save_png(path) == OK, "Screenshot saves: " + suffix)
	print("CAMP CAMERA CAPTURE ", path, " colors=", colors.size())
