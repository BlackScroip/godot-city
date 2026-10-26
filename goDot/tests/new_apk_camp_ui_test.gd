extends SceneTree

var game: Node
var canvas: SubViewport
var checks := 0
var failures: Array[String] = []
var rendered := false

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("NEW APK CAMP UI: " + message)

func settle() -> void:
	for frame in 4: await process_frame

func capture(name: String) -> void:
	if not rendered: return
	await RenderingServer.frame_post_draw
	var image = canvas.get_texture().get_image()
	var distinct: Dictionary = {}
	for y in range(0, image.get_height(), 20):
		for x in range(0, image.get_width(), 20): distinct[image.get_pixel(x, y).to_rgba32()] = true
	check(distinct.size() > 20, "nonblank rendered pixels: " + name)
	image.save_png("res://reports/new-apk-camp-%s-%dx%d.png" % [name, canvas.size.x, canvas.size.y])

func inspect_decoration(slot_id: int, id: int) -> void:
	var state: Dictionary = game.world.camp_decorations.installed.get(slot_id, {})
	check(not state.is_empty() and int(state.get("id", 0)) == id, "selected prefab installed in matching slot %d" % slot_id)
	if state.is_empty(): return
	var meshes = state.node.find_children("*", "MeshInstance3D", true, false)
	check(not meshes.is_empty() and state.node.is_visible_in_tree(), "decoration has visible source meshes %d" % id)
	for child_name in state.children:
		var child = state.container.get_node_or_null(NodePath(str(child_name)))
		check(child is Node3D and not child.visible, "baseline variant hidden for %d: %s" % [id, child_name])
	var bounds: AABB = meshes[0].global_transform * meshes[0].get_aabb()
	for mesh in meshes: bounds = bounds.merge(mesh.global_transform * mesh.get_aabb())
	var baseline_bounds := AABB()
	var baseline_found := false
	for child_name in state.children:
		var child = state.container.get_node_or_null(NodePath(str(child_name)))
		for mesh in child.find_children("*", "MeshInstance3D", true, false):
			var box: AABB = mesh.global_transform * mesh.get_aabb()
			baseline_bounds = baseline_bounds.merge(box) if baseline_found else box
			baseline_found = true
	check(baseline_found and bounds.intersects(baseline_bounds), "new appearance overlaps the original facility's world bounds %d" % id)
	game._close_page()
	game.world.camera.position = bounds.get_center() + Vector3(12, 16, -16)
	game.world.camera.look_at(bounds.get_center())
	await settle()
	await capture("appearance-%d" % id)

func _run() -> void:
	rendered = "--render-check" in OS.get_cmdline_user_args()
	canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	game = load("res://scripts/main.gd").new()
	game.save_store = DungeonSaveStore.new("/private/tmp/new-apk-camp-ui-%d.json" % Time.get_ticks_usec())
	canvas.add_child(game)
	game.set_process(false)
	game.world.set_process(false)
	game.world.set_physics_process(false)
	game.audio.stop()
	await settle()
	for row in game.catalog.rows("Buildings"): game.profile.data.buildings[str(row.id)] = int(row.max_level)
	for row in game.catalog.rows("EnemyData"):
		if str(row.get("enemy_rate", "")) == "Normal":
			game.systems.record("kill:" + str(int(row.id)), 100)
			break
	game.systems.record("runs", 5)
	game.systems.grant_material(101, 100000)
	game.hud.update_counters(game.systems, 0)
	game.world.refresh_camp_progression()
	game.menus.open("decorations")
	var before: int = game.systems.material(101)
	game._action("op:unlock_camp_decoration", 1002, 0)
	check(game.systems.material(101) == before - 100, "appearance UI charges the source unlock fee once")
	game._action("op:equip_camp_decoration", 1, 1002)
	await inspect_decoration(1, 1002)
	game._action("op:equip_camp_decoration", 1, 1001)
	check(not game.world.camp_decorations.installed.has(1), "default selection removes the previous prefab")
	var built_visible := false
	for variant in game.world.camp_progression.variants:
		if int(variant.building_id) == 1 and variant.built and variant.node.is_visible_in_tree(): built_visible = true
	check(built_visible, "default selection restores the built source appearance")
	game._action("op:equip_camp_decoration", 1, 1002)
	game._action("op:unlock_camp_decoration", 4002, 0)
	game._action("op:equip_camp_decoration", 4, 4002)
	await inspect_decoration(4, 4002)
	game.world.refresh_camp_progression()
	check(game.world.camp_decorations.installed.size() == 2 and game.world.camp_decorations.diagnostics.is_empty(), "repeated refresh keeps exactly two selected appearances without errors")
	var saved: Dictionary = game.save_store.load_profile()
	check(int(saved.get("camp_decorations", {}).get("1", 0)) == 1002 and int(saved.get("camp_decorations", {}).get("4", 0)) == 4002, "UI appearance selections persist")
	game._camp()
	game.audio.stop()
	await settle()
	check(game.world.camp_decorations.installed.size() == 2, "camp scene rebuild restores both selected appearances")
	await inspect_decoration(1, 1002)
	await inspect_decoration(4, 4002)
	for row in game.catalog.rows("MaterialData"): game.systems.grant_material(DungeonCatalog.row_id(row), 1000)
	var meal_id := DungeonCatalog.row_id(game.catalog.rows("CatMealData")[0])
	game._action("op:research_meal", meal_id, 0)
	game._action("op:select_meal", meal_id, 1)
	game._action("op:buy_meal", 0, 0)
	check(game.profile.data.purchased_meals.has(str(meal_id)), "UI researches, selects and purchases a meal through separate commands")
	game.hud.update_counters(game.systems, 0)
	game.world.snap_camera()
	for size in [Vector2i(1600, 900), Vector2i(844, 390), Vector2i(2460, 1080)]:
		canvas.size = size
		game.hud._layout()
		for page in ["work", "awakening", "decorations", "meals"]:
			game.menus.open(page)
			await settle()
			check(game.hud.page.displayed_row_count() > 0 and Rect2(Vector2.ZERO, Vector2(size)).encloses(game.hud.page.get_global_rect()), "page remains populated and within viewport: %s %s" % [page, size])
			await capture(page)
	var report = {"checks": checks, "failures": failures, "rendered": rendered, "scope": "Reconstructed Godot host transactions, scene decoration replacement, save persistence and responsive camp pages; no original APK runtime comparison."}
	var output = FileAccess.open("res://reports/new-apk-camp-ui-tests.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t"))
	print("NEW_APK_CAMP_UI ", JSON.stringify(report))
	game.queue_free()
	await process_frame
	canvas.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
