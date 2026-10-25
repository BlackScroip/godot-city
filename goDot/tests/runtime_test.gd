extends SceneTree

var assertions := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition: failures.append(message)

func _run() -> void:
	_test_save()
	_test_dialogue()
	for suffix in ["", ".bak", ".tmp"]:
		var path = "res://reports/host-test-profile.json" + suffix
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	var scene = load("res://scenes/main.tscn").instantiate()
	scene.save_store = DungeonSaveStore.new("res://reports/host-test-profile.json")
	root.add_child(scene)
	await process_frame
	check(is_instance_valid(scene.world.player), "Camp creates player")
	check(scene.world.player.visual_loaded, "Camp uses original character")
	check(is_instance_valid(scene.world.player.weapon), "Weapon attaches to skeleton")
	check(scene.world.player.position.distance_to(DungeonWorld.vector(scene.world.environment_entry.player_start)) < 1, "Camp uses original spawn")
	check(scene.world.collision_report.loaded > 100, "Camp imports physical colliders")
	check(scene.world.collision_report.missing_mesh.is_empty(), "Camp mesh colliders resolve")
	_test_touch(scene)
	scene._action("volume", 0.4, 0)
	scene._action("auto_attack", false, 0)
	check(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(0)), 0.4), "Volume slider changes audio bus")
	check(not scene.world.auto_attack_enabled, "Automatic attack setting applies")
	scene._apply_settings()
	check(not scene.world.auto_attack_enabled, "Automatic attack setting reapplies at startup")
	for page in ["camp", "characters", "weapons", "talents", "partners", "work", "dispatch", "meals", "buildings", "npcs", "npc", "awakening", "tokens", "amplifiers", "achievements", "tasks", "inventory", "archive", "mall", "difficulty", "settings"]:
		scene.menus.open(page, 1 if page in ["weapons", "npc"] else 100 if page == "tasks" else 0)
		check(scene.hud.modal_open and scene.hud.page.displayed_row_count() > 0, "Menu opens: " + page)
		check(not scene.hud.navigation.visible, "Menu hides camp navigation: " + page)
		if page == "buildings":
			for row in scene.hud.page._rows:
				check(not str(row.title).contains("|"), "Building shows one stage title")
				check(not str(row.get("icon", "")).contains("|"), "Building icon is a single resource key")
		if page == "awakening":
			for row in scene.hud.page._rows:
				if row.get("presentation_role", "") == "awakening_summary": continue
				var source = scene.catalog.find("CharaTalentAwakeTreeData", int(row.config_id))
				check(int(row.get("node_level", -1)) == int(source.unlock_awake_tree_level), "Awakening node uses configured level")
		await process_frame
	scene.hud.close_page()
	scene._primary()
	check(scene.campaign.state.region_selection and scene.hud.page.route_view.context.map_scope == "world", "Camp opens world selection before the first room")
	scene._action("select_region", 2, 0)
	var started = Time.get_ticks_msec()
	while scene._transitioning and Time.get_ticks_msec() - started < 20000: await process_frame
	check(scene.profile.data.run.active and scene.campaign.state.phase == "room", "World confirmation enters the seeded first room")
	check(not scene._transitioning, "First room loading finishes")
	if scene.campaign.state.phase == "room":
		check(scene.campaign.state.phase == "room", "Route enters original room")
		check(scene.world.collision_report.missing_mesh.is_empty(), "Room mesh colliders resolve")
		if not scene.campaign.current_room().get("combat", false):
			scene._finish_noncombat()
			check(scene.campaign.state.phase == "reward", "Noncombat room settles")
			check(scene._save(true), "Run snapshot saves")
			scene._action("next", 0, 0)
			if scene.campaign.state.phase == "reward": scene._action("leave_unclaimed", 0, 0)
			started = Time.get_ticks_msec()
			while scene._transitioning and Time.get_ticks_msec() - started < 20000: await process_frame
			check(scene.campaign.state.phase in ["route", "won"], "Rewards advance adventure")
	var snapshot = scene.save_store.load_profile()
	check(snapshot.get("run", {}).get("active", false), "Saved adventure remains active")
	check(not snapshot.get("run", {}).get("route", {}).is_empty(), "Saved route survives JSON")
	var clone = load("res://scripts/domain/campaign.gd").new()
	clone.configure()
	check(clone.restore(snapshot.get("run", {}).get("route", {})), "Campaign resumes persisted route")
	scene.queue_free()
	await process_frame
	var report = {"assertions": assertions, "failures": failures, "passed": failures.is_empty(), "display": DisplayServer.get_name(), "scope": "save recovery, dialogue predicates, menus, camp, adventure entry, noncombat settlement, route persistence; no visual or device acceptance"}
	var file = FileAccess.open("res://reports/runtime-tests.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("RUNTIME_TESTS ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func _test_touch(scene: Node) -> void:
	var joystick = scene.hud.joystick
	var key = scene.hud.skill_by_slot[0]
	var down = InputEventScreenTouch.new()
	down.index = 3
	down.pressed = true
	down.position = joystick.get_global_rect().get_center() + Vector2(48, 0)
	joystick._input(down)
	var drag = InputEventScreenDrag.new()
	drag.index = down.index
	drag.position = down.position + Vector2(48, 0)
	joystick._input(drag)
	check(joystick.value.x > 0.5, "First finger moves joystick")
	var skill_touch = InputEventScreenTouch.new()
	skill_touch.index = 7
	skill_touch.pressed = true
	skill_touch.position = key.get_global_rect().get_center()
	key._input(skill_touch)
	check(key.finger == 7 and joystick.finger == 3, "Second finger holds skill independently")
	skill_touch.pressed = false
	skill_touch.position = Vector2(-100, -100)
	key._input(skill_touch)
	check(key.finger == -1 and joystick.value.x > 0.5, "Skill release outside retains moving finger")
	down.pressed = false
	down.position = Vector2(-100, -100)
	joystick._input(down)
	check(joystick.finger == -1 and joystick.value == Vector2.ZERO, "Joystick release outside clears movement")

func _test_save() -> void:
	var path = "res://reports/save-recovery-test.json"
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	var store = DungeonSaveStore.new(path)
	var profile = load("res://scripts/domain/profile.gd").new()
	profile.data.materials["101"] = 15
	check(store.save(profile.data), "First profile save")
	profile.data.materials["101"] = 22
	check(store.save(profile.data), "Atomic replacement with backup")
	check(int(store.load_profile().materials["101"]) == 22, "Read latest save")
	var corrupt = FileAccess.open(path, FileAccess.WRITE)
	corrupt.store_string("{broken")
	corrupt.close()
	check(int(store.load_profile().get("materials", {}).get("101", -1)) == 15, "Corrupt primary recovers previous backup")
	profile.data.materials["101"] = -5
	check(not store.save(profile.data), "Invalid negative material does not replace save")
	check(int(store.load_profile().get("materials", {}).get("101", -1)) == 15, "Invalid write preserves backup")
	profile.data.materials["101"] = 30
	check(store.save(profile.data), "Healthy state replaces corrupt primary")
	check(int(store.load_profile().materials["101"]) == 30, "Recovery can continue saving")

func _test_dialogue() -> void:
	var dialogue = load("res://scripts/domain/dialogue.gd").new()
	check(dialogue.load_all(), "Original dialogue catalog loads")
	check(dialogue.stories.size() == 335, "All 335 original dialogue stories present")
	for id in dialogue.stories:
		for seed_value in [1, 42, 987]:
			var lines = dialogue.read_story(id, seed_value)
			check(lines == dialogue.read_story(id, seed_value), "Deterministic story: " + id)
			check(not lines.is_empty() or dialogue.stories[id].Lines.is_empty(), "Reachable dialogue lines: " + id)
	check(dialogue.diagnostics.is_empty(), "All shipped dialogue conditions interpreted")
