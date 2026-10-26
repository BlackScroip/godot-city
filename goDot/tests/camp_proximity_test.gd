extends SceneTree

const Interactions = preload("res://scripts/world_interactions.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func _marker(id: String, kind: String, data: Dictionary, point := Vector3.ZERO) -> Dictionary:
	return {"SceneName": "Camp", "SourceGameObjectId": id, "Type": kind, "Path": [id], "DataJson": JSON.stringify(data), "exported_node_name": id, "world_position": [point.x, point.y, point.z]}

func _volume(id: String, size: Vector3, point := Vector3.ZERO) -> Dictionary:
	return {"kind": 65, "fileID": id, "path": "Camp/" + id + "/Box_TiggerEnter", "active": true,
		"world_matrix": [1, 0, 0, point.x, 0, 1, 0, point.y, 0, 0, 1, point.z, 0, 0, 0, 1],
		"properties": {"m_IsTrigger": 1, "m_Enabled": 1, "m_Size": {"x": size.x, "y": size.y, "z": size.z}}}

func _unit_ranges() -> void:
	var environment := Node3D.new()
	root.add_child(environment)
	var markers := [_marker("meal", "EEUT_UIInteractable", {"UIBtnName": "EnvUnit_MonoData_BtnDisplayName_CatMeal"}),
		_marker("work", "EEUT_Special_MonsterWork", {}, Vector3(10, -0.477, 0)),
		_marker("unknown", "EEUT_NPC", {"NpcId": "not-configured"}),
		_marker("2", "EEUT_UIInteractable", {"UIBtnName": "ATPanel_RelationshipToken_Title"}, Vector3(20, 0, 0)),
		_marker("10", "EEUT_UIInteractable", {"UIBtnName": "keyword_Records"}, Vector3(20, 0, 0))]
	for marker in markers:
		var node := Node3D.new()
		node.name = marker.exported_node_name
		environment.add_child(node)
	var interactions := Interactions.new()
	interactions.setup(environment, markers, {"camp": true, "rules": {"Bindings": [], "Definitions": []}, "colliders": [
		_volume("meal", Vector3(7, 1, 4)), _volume("work", Vector3(5, 1, 5), Vector3(10, -0.477, 0))]})
	check(interactions.can_interact_at("meal", Vector3(3.4, 0, 0)), "Authored wide meal trigger extends beyond a generic three-unit radius")
	check(not interactions.can_interact_at("meal", Vector3(0, 0, 2.36)), "Narrow meal trigger edge rejects positions still within three-unit radius")
	check(interactions.can_interact_at("work", Vector3(10, 0, 0)), "Player feet overlap the original work stone's low trigger")
	check(not interactions.can_interact_at("work", Vector3(13, 0, 0)), "Work stone refuses interaction beyond its source volume")
	check(not interactions.can_interact_at("unknown", Vector3.ZERO), "An unconfigured NPC never offers an unusable prompt")
	check(interactions.available_interactions(Vector3.INF).is_empty(), "Non-finite player position is rejected")
	check(interactions.available_interactions(Vector3.ZERO, -1).is_empty(), "Negative fallback radius is rejected")
	var overlap := interactions.available_interactions(Vector3(20, 0, 0))
	check(overlap.size() == 2 and overlap[0].id == "2" and overlap[1].id == "10", "Overlapping facilities are all returned in stable natural identity order")
	var pages: Array = []
	interactions.message_requested.connect(func(name, context): pages.append([name, context.get("page", "")]))
	check(interactions.interact_nearest(Vector3(10, 0, 0)).success and pages == [["camp_page", "work"]], "Approaching the actual work marker opens its work service")
	check(not interactions.diagnostics.any(func(entry): return entry.marker_id == "work" and entry.code == "unsupported_marker"), "Source work marker is a supported interaction")
	interactions._items.work.state.enabled = false
	check(not interactions.can_interact_at("work", Vector3(10, 0, 0)), "A locked work facility rejects prompt and execution")
	environment.free()

func _run() -> void:
	_unit_ranges()
	var game = load("res://scenes/main.tscn").instantiate()
	game.save_store = DungeonSaveStore.new("/tmp/camp-proximity-%d.json" % Time.get_ticks_usec())
	root.add_child(game)
	while not game.initialized: await process_frame
	game.set_process(false)
	game.world.set_physics_process(false)
	var world: DungeonWorld = game.world
	world._background = false
	world.paused = false
	game.profile.data.buildings = {}
	world.refresh_camp_progression()
	for page in ["characters", "weapons", "talents", "archive", "partners", "work", "meals", "tokens", "treasure"]:
		check(world.camp_facility(page).is_empty(), "Unbuilt facility has no active interaction: " + page)
	for page in ["buildings", "tasks", "primary"]:
		check(not world.camp_facility(page).is_empty(), "Unbuilt camp retains authored management/commission/departure access: " + page)
	for id in range(1, 8): game.profile.data.buildings[str(id)] = 1
	world.refresh_camp_progression()
	check(world.camp_facility("partners").is_empty(), "Monster partners stay locked at archive facility rank one")
	game.profile.data.buildings["4"] = 2
	world.refresh_camp_progression()
	for page in ["characters", "weapons", "talents", "archive", "partners", "work", "meals", "tokens", "treasure", "storage", "history"]:
		check(not world.camp_facility(page).is_empty(), "Built facility service resolves a real interaction: " + page)
	var work := world.camp_facility("work")
	check(str(work.marker.Type) == "EEUT_Special_MonsterWork" and str(work.id) == "2723", "Work navigation targets the original APK interaction identity")
	world.player.position = Vector3(work.position.x, 0, work.position.z)
	check(world.interactions.can_interact_at(str(work.id), world.player.position), "Actual work stone trigger can be reached from the camp floor")
	game._close_page()
	world.paused = false
	check(world.interact_camp_marker(str(work.id)).success and game.menus.current_page == "work", "World range-checked work interaction opens the live service page")
	check(not world.navigate_to_camp_facility("tasks"), "Open menu blocks facility navigation")
	check(not world.interact_camp_marker(str(work.id)).success, "Open menu blocks duplicate world interaction")
	game._close_page()
	world.paused = false
	world.player.position = Vector3(100, 0, 100)
	check(world.interact_camp_marker(str(work.id)).get("reason", "") == "out_of_range", "A stale selected facility is rejected after the player leaves its range")
	check(world.navigate_to_camp_facility("work"), "Unlocked work navigation starts")
	world.clear_input()
	check(world._camp_destination.is_empty(), "Input suspension cancels pending automatic interaction")
	var task := world.camp_facility("tasks")
	world.player.position = task.position + Vector3(2, 0.05, -4)
	world.snap_camera()
	var screen := world.camera.unproject_position(task.position + Vector3.UP * 0.7)
	var press := InputEventScreenTouch.new()
	press.index = 2
	press.position = screen
	press.pressed = true
	world._unhandled_input(press)
	var other := InputEventScreenTouch.new()
	other.index = 3
	other.position = screen
	other.pressed = true
	world._unhandled_input(other)
	check(world._camp_pointer_id == 2, "A second touch cannot replace the original facility press")
	var drag := InputEventScreenDrag.new()
	drag.index = 2
	drag.position = screen + Vector2(60, 0)
	world._unhandled_input(drag)
	var release := InputEventScreenTouch.new()
	release.index = 2
	release.position = screen
	world._unhandled_input(release)
	check(world._camp_destination.is_empty(), "Dragging away and returning to the facility cannot activate it")
	world._unhandled_input(press)
	release.canceled = true
	world._unhandled_input(release)
	check(world._camp_destination.is_empty(), "Canceled OS touch cannot activate a facility")
	world._unhandled_input(press)
	release.canceled = false
	world._unhandled_input(release)
	check(world._camp_destination == str(task.id), "A regular facility tap still starts navigation")
	game.queue_free()
	await process_frame
	var report := {"checks": checks, "failures": failures}
	var output := FileAccess.open("res://reports/camp-proximity-tests.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t"))
	print("Camp proximity: %d checks; failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)
