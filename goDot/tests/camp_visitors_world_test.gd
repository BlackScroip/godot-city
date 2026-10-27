extends SceneTree

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _run() -> void:
	var catalog := DungeonCatalog.new()
	catalog.load_all()
	var profile := DungeonProfile.new()
	profile.data.buildings["1"] = 3
	var systems := DungeonSystems.new(catalog, profile)
	var world := DungeonWorld.new()
	world.systems = systems
	root.add_child(world)
	world.set_physics_process(false)
	world.camp_visitors._level = 3
	world.camp_visitors.choices = [{"seat": 1, "character_id": 2}, {"seat": 2, "character_id": 3}, {"seat": 3, "character_id": 4}]
	world.camp_visitors.preserve_once = true
	world.load_environment(10000, true)
	for label in world.environment_root.find_children("CampNpcService*", "Label3D", false, false):
		check(label.text != "<>", "empty NPC service title omitted")
	for seat in range(1, 4):
		var item: Dictionary = world.interactions._items.get("camp:visitor:%d" % seat, {})
		check(not item.is_empty(), "original seat anchor bound " + str(seat))
		if item.is_empty(): continue
		check(world.interactions.is_interaction_available(item), "visitor opens actual NPC interaction " + str(seat))
		var actor = item.visual.get_node_or_null("CampVisitor")
		check(actor != null and actor.visual_loaded, "original character model loaded " + str(seat))
		check(actor != null and actor.animation != null and actor.animation.is_playing(), "visitor idle animation plays " + str(seat))
	profile.data.selected_character = 2
	world.camp_visitors.refresh(world)
	check(not world.interactions.is_interaction_available(world.interactions._items["camp:visitor:1"]), "selected visitor hidden")
	profile.data.selected_character = 1
	world.camp_visitors.refresh(world)
	check(world.interactions.is_interaction_available(world.interactions._items["camp:visitor:1"]), "switching away restores same visitor")
	var positions: Array = []
	for seat in range(1, 4): positions.append(world.interactions._items["camp:visitor:%d" % seat].position)
	world.camp_visitors.preserve_once = true
	world.load_environment(10000, true)
	for seat in range(1, 4):
		var item: Dictionary = world.interactions._items["camp:visitor:%d" % seat]
		check(item.position == positions[seat - 1], "recreated camp retains original anchor")
		check(item.visual.find_children("CampVisitor", "CharacterBody3D", false, false).size() == 1, "visitor model not duplicated")
	var capture_path := ""
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1600, 900)
		world.set_process(false)
		var focus := Vector3.ZERO
		for position in positions: focus += position
		focus /= float(positions.size())
		world.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		world.camera.size = 17.0
		world.camera.position = focus + Vector3(0, 13, -14)
		world.camera.look_at(focus)
		for frame in range(8): await process_frame
		await RenderingServer.frame_post_draw
		var picture := root.get_texture().get_image()
		capture_path = "res://reports/camp-visitors-1600x900.png"
		check(picture.save_png(capture_path) == OK, "visitor screenshot saved")
		var colors := {}
		for y in range(0, picture.get_height(), 20):
			for x in range(0, picture.get_width(), 20): colors[picture.get_pixel(x, y).to_html()] = true
		check(colors.size() > 100, "camp rendering nonblank")
		for position in positions:
			check(Rect2(Vector2.ZERO, Vector2(root.size)).has_point(world.camera.unproject_position(position)), "visitor seat in screenshot")
	world.queue_free()
	await process_frame
	var report := {"checks": checks, "failures": failures, "passed": failures.is_empty(), "capture": capture_path, "scope": "Godot camp scene with original character models and seat anchors; original APK runtime and dedicated resting animation remain unverified."}
	FileAccess.open("res://reports/camp-visitors-world-test.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("CAMP_VISITORS_WORLD_TEST ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
