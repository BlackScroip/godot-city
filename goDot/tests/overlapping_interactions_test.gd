extends SceneTree

var checks := 0
var failures: Array[String] = []
var game: Node
var canvas: SubViewport
var visual := false
var captures: Array[String] = []
var overlaps: Dictionary = {}
var overlap_points: Dictionary = {}
var dispatched: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("OVERLAPPING INTERACTIONS: ", message)

func refresh() -> void:
	game.world._background = false
	game.world._event_refresh_at = 0
	game._process(0.0)

func capture(label: String) -> void:
	if not visual: return
	await RenderingServer.frame_post_draw
	var image := canvas.get_texture().get_image()
	var colors: Dictionary = {}
	for y in range(0, image.get_height(), 20):
		for x in range(0, image.get_width(), 20): colors[image.get_pixel(x, y).to_rgba32()] = true
	check(colors.size() > 30, "Rendered overlap has nonblank pixels: " + label)
	var path := "res://reports/overlapping-interactions-%s-%dx%d.png" % [label, canvas.size.x, canvas.size.y]
	image.save_png(path)
	captures.append(path)

func _run() -> void:
	create_timer(60).timeout.connect(func(): quit(2))
	visual = "--visual" in OS.get_cmdline_user_args()
	DungeonLocale.set_locale("zh_CN", false)
	canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	game = load("res://scenes/main.tscn").instantiate()
	game.save_store = DungeonSaveStore.new("/private/tmp/overlapping-interactions-%d.json" % Time.get_ticks_usec())
	canvas.add_child(game)
	while not game.initialized: await process_frame
	game.set_process(false)
	game.world.set_process(false)
	game.world.set_physics_process(false)
	game.world.player.set_physics_process(false)
	game.audio.stop()
	for row in game.catalog.rows("Buildings"): game.profile.data.buildings[str(row.id)] = int(row.max_level)
	game.world.refresh_camp_progression()
	game.world.interactions.message_requested.connect(func(_message, context): dispatched.append(str(context.marker_id)))
	game.world.interactions.npc_requested.connect(func(_npc_id, context): dispatched.append(str(context.marker_id)))
	var items: Array = game.world.interactions._items.values()
	for first in items:
		for second in items:
			if str(first.id) >= str(second.id): continue
			var point: Vector3 = (first.position + second.position) * 0.5
			point.y = 0.0
			var nearby: Array = game.world.interactions.available_interactions(point)
			if nearby.size() < 2: continue
			var pair := str(nearby[0].id) + "-" + str(nearby[1].id)
			if overlaps.has(pair): continue
			overlaps[pair] = nearby.map(func(item): return str(item.id))
			overlap_points[pair] = point
			game.world.player.position = point
			refresh()
			check(game.hud.primary.visible and game.hud.interaction_secondary.visible, "Every authored overlap shows two buttons: " + pair)
			var shown: Array = [str(game.hud.primary.get_meta("interaction_marker_id")), str(game.hud.interaction_secondary.get_meta("interaction_marker_id"))]
			check(shown[0] != shown[1] and overlaps[pair].has(shown[0]) and overlaps[pair].has(shown[1]), "Buttons address two distinct in-range markers: " + pair)
			check(game.hud.primary.icon != null and game.hud.interaction_secondary.icon != null, "Both overlapping entrances resolve their artwork: " + pair)
	check(overlaps.size() >= 5, "Coverage includes multiple non-task camp overlaps")
	var weapon: Dictionary
	var smith: Dictionary
	for item in items:
		if int(item.data.get("NpcId", 0)) == 1100: smith = item
		if str(item.data.get("UIBtnName", "")) == "EnvUnit_MonoData_BtnDisplayName_SelectWeapon": weapon = item
	var weapon_point := Vector3.INF
	for pair in overlaps:
		if overlaps[pair].has(str(weapon.id)) and overlaps[pair].has(str(smith.id)):
			weapon_point = overlap_points[pair]
			break
	check(weapon_point.is_finite(), "Weapon rack and smith have a reachable shared trigger position")
	game.world.player.position = weapon_point
	game.world.snap_camera()
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390)]:
		canvas.size = dimensions
		await process_frame
		game.hud._layout()
		refresh()
		await process_frame
		var upper: Rect2 = game.hud.primary.get_global_rect()
		var lower: Rect2 = game.hud.interaction_secondary.get_global_rect()
		check(game.hud.interaction_secondary.visible and upper.end.y < lower.position.y and is_equal_approx(upper.position.x, lower.position.x), "Non-task overlap uses the same vertical layout %s" % dimensions)
		check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(upper.merge(lower)), "Both generic rows fit the viewport %s" % dimensions)
		await capture("weapon-smith")
	var selected := str(game.hud.primary.get_meta("interaction_marker_id"))
	game.hud.primary.pressed.emit()
	check(not dispatched.is_empty() and dispatched.back() == selected, "Upper non-task button directly executes its own marker")
	game._close_page()
	refresh()
	selected = str(game.hud.interaction_secondary.get_meta("interaction_marker_id"))
	game.hud.interaction_secondary.pressed.emit()
	check(dispatched.back() == selected, "Lower non-task button directly executes its own marker")
	game._close_page()
	refresh()
	var before := dispatched.size()
	game.world.player.position = Vector3(100, 0, 100)
	game.hud.interaction_secondary.pressed.emit()
	check(dispatched.size() == before, "A stale lower button cannot execute after leaving its interaction volume")
	refresh()
	check(not game.hud.primary.visible and not game.hud.interaction_secondary.visible, "Leaving overlapping facilities hides both rows")
	_test_adventure_targets()
	var report := {"checks": checks, "passed": failures.is_empty(), "failures": failures, "overlaps": overlaps, "captures": captures}
	FileAccess.open("res://reports/overlapping-interactions-tests.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("OVERLAPPING_INTERACTIONS ", JSON.stringify(report))
	game.queue_free()
	await process_frame
	canvas.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _test_adventure_targets() -> void:
	var environment := Node3D.new()
	root.add_child(environment)
	var markers: Array = []
	for id in ["switch-a", "switch-b", "door-a", "door-b"]:
		var node := Node3D.new()
		node.name = id
		environment.add_child(node)
		var index := 1 if id.ends_with("a") else 2
		var data := {"ControllDoorId": index} if id.begins_with("switch") else {"DoorId": index}
		markers.append({"SourceGameObjectId": id, "Type": "EEUT_DoorController" if id.begins_with("switch") else "EEUT_Door", "DataJson": JSON.stringify(data), "exported_node_name": id, "world_position": [0, 0, 0]})
	var interactions = preload("res://scripts/world_interactions.gd").new()
	interactions.setup(environment, markers, {"rules": {"Bindings": [], "Definitions": []}})
	var original: RefCounted = game.world.interactions
	game.world.interactions = interactions
	game.profile.data.run.active = true
	game.world.player.position = Vector3.ZERO
	game.world.paused = false
	game.hud.show_interaction_prompts(game._interaction_prompts(interactions.available_interactions(Vector3.ZERO)))
	game.hud.interaction_secondary.pressed.emit()
	check(interactions._items["switch-b"].state.used and not interactions._items["switch-a"].state.used, "Lower adventure button executes its selected switch rather than the nearest switch")
	check(not interactions._items["door-b"].state.enabled and interactions._items["door-a"].state.enabled, "Selected switch changes only its own door")
	game.world.player.position = Vector3(20, 0, 0)
	game.hud.primary.pressed.emit()
	check(not interactions._items["switch-a"].state.used, "Adventure button rejects an out-of-range target")
	game.world.player.position = Vector3.ZERO
	game.hud.show_interaction_prompts(game._interaction_prompts(interactions.available_interactions(Vector3.ZERO)))
	check(not game.hud.interaction_secondary.visible, "Consuming one overlapping interaction collapses back to one row")
	game.hud.primary.pressed.emit()
	check(interactions._items["switch-a"].state.used, "Remaining adventure row still executes its own target")
	game.profile.data.run.active = false
	game.world.interactions = original
	environment.free()
