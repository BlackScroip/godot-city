extends SceneTree

var checks := 0
var failures: Array[String] = []
var canvas: SubViewport
var game: Node
var visual := false
var captures: Array[String] = []
var commands: Array = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("CAMP TASK PROMPTS: ", message)

func refresh() -> void:
	game.world._background = false
	game.world._event_refresh_at = 0
	game._process(0.0)

func _run() -> void:
	create_timer(60).timeout.connect(func(): quit(2))
	visual = "--visual" in OS.get_cmdline_user_args()
	DungeonLocale.set_locale("zh_CN", false)
	canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	game = load("res://scenes/main.tscn").instantiate()
	game.save_store = DungeonSaveStore.new("/private/tmp/camp-task-prompts-%d.json" % Time.get_ticks_usec())
	canvas.add_child(game)
	while not game.initialized: await process_frame
	game.set_process(false)
	game.world.set_process(false)
	game.world.set_physics_process(false)
	game.world.player.set_physics_process(false)
	game.audio.stop()
	game.hud.action.connect(func(kind, id, _extra): commands.append([kind, id]))
	for row in game.catalog.rows("Buildings"): game.profile.data.buildings[str(row.id)] = int(row.max_level)
	game.world.refresh_camp_progression()
	game.systems.grant_material(10101, 2)
	var board: Dictionary
	var bounty: Dictionary
	for item in game.world.interactions._items.values():
		match str(item.data.get("UIBtnName", "")):
			"EnvUnit_MonoData_BtnDisplayName_Quest": board = item
			"Keyword_ExtraChallenge": bounty = item
	check(not board.is_empty() and not bounty.is_empty(), "Both task entrances resolve real camp markers")
	game.world.player.position = (board.position + bounty.position) * 0.5
	game.world.snap_camera()
	await process_frame
	refresh()
	check(game.hud.primary.visible and game.hud.interaction_secondary.visible, "Overlapping task triggers expose two separate buttons")
	check(game.hud.primary.text == "悬赏委托" and game.hud.interaction_secondary.text == "委托板", "Bounty is first even when the board is closer")
	check(game.hud.primary.icon == DungeonStyle.texture("sprite_conversation_Extra challenges") and game.hud.interaction_secondary.icon == DungeonStyle.texture("sprite_conversation_mission"), "Each entrance uses its own reference artwork")
	var marker: Sprite3D = game.world._event_markers.get("camp:tasks")
	check(is_instance_valid(marker) and marker.visible, "Completing an unclaimed task shows the shared world marker")
	check(marker.texture == DungeonStyle.texture("interaction_quest"), "World marker uses the reference exclamation artwork")
	check(not game.world._event_markers.has(board.id) and not game.world._event_markers.has(bounty.id), "The two task triggers never create duplicate exclamations")
	for item in game.world.interactions._items.values():
		if int(item.data.get("NpcId", 0)) == 1300:
			check(not game.world._event_markers.has(item.id), "The task receptionist shares the board exclamation")
	check(game.hud.primary.get_node("Notification").visible and game.hud.interaction_secondary.get_node("Notification").visible, "Available task rewards show red dots on both entrances")
	for dimensions in [Vector2i(640, 360), Vector2i(844, 390), Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(2460, 1080), Vector2i(1200, 900)]:
		canvas.size = dimensions
		await process_frame
		game.hud._layout()
		refresh()
		await process_frame
		var upper: Rect2 = game.hud.primary.get_global_rect()
		var lower: Rect2 = game.hud.interaction_secondary.get_global_rect()
		check(is_equal_approx(upper.position.x, lower.position.x) and upper.end.y < lower.position.y, "Task rows align vertically without overlap %s" % dimensions)
		for bounds in [upper, lower]:
			check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(bounds), "Task button stays within viewport %s" % dimensions)
			for key in game.hud.skill_buttons + [game.hud.attack_mode_button]:
				var padding: float = key.hit_padding * key.get_global_transform_with_canvas().get_scale().x
				check(not bounds.intersects(key.get_global_rect().grow(padding)), "Task button avoids skill hit targets %s" % dimensions)
		for key in [game.hud.primary, game.hud.interaction_secondary]:
			check(game.hud.joystick.excluded_controls.has(key), "Task button cannot start joystick movement")
		if visual and dimensions in [Vector2i(844, 390), Vector2i(1600, 900), Vector2i(2460, 1080)]:
			await RenderingServer.frame_post_draw
			var image := canvas.get_texture().get_image()
			var distinct: Dictionary = {}
			for y in range(0, image.get_height(), 20):
				for x in range(0, image.get_width(), 20): distinct[image.get_pixel(x, y).to_rgba32()] = true
			check(distinct.size() > 30, "Rendered camp pixels are nonblank %s" % dimensions)
			var path := "res://reports/camp-task-prompts-%dx%d.png" % [dimensions.x, dimensions.y]
			image.save_png(path)
			captures.append(path)
	game.hud.primary.pressed.emit()
	check(commands.back() == ["camp_interact", str(bounty.id)] and game.menus.current_page == "extra_challenges", "Bounty click directly dispatches its own marker")
	check(not game.hud.primary.visible and not game.hud.interaction_secondary.visible, "Opening a page hides both task buttons immediately")
	game._close_page()
	refresh()
	game.hud.interaction_secondary.pressed.emit()
	check(commands.back() == ["camp_interact", str(board.id)] and game.menus.current_page == "tasks", "Board click directly dispatches its own marker")
	game._close_page()
	game.world.player.position = Vector3(100, 0, 100)
	refresh()
	check(not game.hud.primary.visible and not game.hud.interaction_secondary.visible, "Leaving both trigger volumes hides both task buttons")
	check(str(game.hud.primary.get_meta("interaction_marker_id", "")).is_empty(), "Leaving the board clears the task action from the generic button")
	game.world.player.position = board.position
	bounty.state.enabled = false
	refresh()
	check(game.hud.primary.visible and not game.hud.interaction_secondary.visible and str(game.hud.primary.get_meta("interaction_marker_id")) == str(board.id), "An unavailable bounty leaves one working board button")
	for row in game.catalog.rows("SubAchieveData"): game.profile.data.claimed_tasks.append(int(row.id))
	for row in game.catalog.rows("NPCFunctionData"):
		if int(row.get("npc_index", 0)) == 1300 and row.get("is_onetime_option", false):
			game.systems.set_record("npc:finished:" + str(int(row.id)), 1)
	refresh()
	check(not marker.visible and not game.hud.primary.get_node("Notification").visible, "Claiming every task clears the shared exclamation and reward dots")
	var report := {"checks": checks, "passed": failures.is_empty(), "failures": failures, "captures": captures}
	FileAccess.open("res://reports/camp-task-prompts-tests.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("CAMP_TASK_PROMPTS ", JSON.stringify(report))
	game.queue_free()
	await process_frame
	canvas.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
