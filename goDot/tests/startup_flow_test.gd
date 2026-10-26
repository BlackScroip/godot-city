extends SceneTree

var failures: Array[String] = []
var checks := 0
var canvas: SubViewport
var values: Array[float] = []
var render_check := false
var captured_progress := false
var saved_node := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("STARTUP FAILURE: " + message)

func _capture(filename: String) -> void:
	if not render_check or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var frame := canvas.get_texture().get_image()
	check(not frame.is_empty(), "Rendered frame exists: " + filename)
	check(frame.get_pixel(frame.get_width() / 2, frame.get_height() / 2).a > 0.9, "Artwork covers center: " + filename)
	frame.save_png("/private/tmp/" + filename + ".png")

func _wait_start(boot: Node) -> void:
	var deadline := Time.get_ticks_msec() + 65000
	while boot.starting and Time.get_ticks_msec() < deadline:
		await process_frame
		if render_check and not captured_progress and boot.progress >= 0.45 and boot.progress < 1.0:
			captured_progress = true
			await _capture("startup-loading-844x390")
	check(not boot.starting, "Startup completes within deadline")
	check(is_instance_valid(boot.game) and boot.game.initialized, "Main game finishes initialization")

func _run() -> void:
	render_check = "--render-check" in OS.get_cmdline_user_args()
	canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var boot = load("res://scenes/startup.tscn").instantiate()
	var path := "/private/tmp/startup-flow-%d.json" % Time.get_ticks_usec()
	boot.game_save_store = DungeonSaveStore.new(path)
	boot.progress_changed.connect(func(value: float): values.append(value))
	canvas.add_child(boot)
	await process_frame
	check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/startup.tscn", "Cold launch uses homepage")
	check(boot.home.visible and not is_instance_valid(boot.game), "Home waits for explicit start without constructing gameplay")
	check(not FileAccess.file_exists(path), "Home does not create or replace a save")
	check(boot.home.logo.texture != null, "Original Chinese logo is loaded")
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390), Vector2i(2460, 1080)]:
		canvas.size = dimensions
		await process_frame
		await process_frame
		var bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
		check(bounds.encloses(boot.home.logo.get_global_rect()), "Logo fits %s" % dimensions)
		check(bounds.encloses(boot.home.start_button.get_global_rect()), "Start button fits %s" % dimensions)
		check(boot.home.logo.get_global_rect().end.y < boot.home.start_button.position.y, "Logo stays clear of start button %s" % dimensions)
		await _capture("startup-home-%dx%d" % [dimensions.x, dimensions.y])
	boot.home.show_error("游戏资源加载失败，请重试")
	canvas.size = Vector2i(844, 390)
	await process_frame
	await process_frame
	check(Rect2(Vector2.ZERO, Vector2(canvas.size)).encloses(boot.home.error_label.get_global_rect()), "Retry message fits mobile")
	boot.home.start_button.text = "开始游戏"
	boot.home.error_label.text = ""
	var center: Vector2 = boot.home.start_button.get_global_rect().get_center()
	var press := InputEventMouseButton.new()
	press.position = center
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	canvas.push_input(press, true)
	var release := press.duplicate()
	release.pressed = false
	canvas.push_input(release, true)
	check(boot.starting and boot.loading.visible and not boot.home.visible, "Actual start button shows loading immediately")
	boot.start_game()
	check(boot.get_child_count() == 2, "Repeated start does not create a second game or loader")
	await process_frame
	await _capture("startup-loading-844x390")
	await _wait_start(boot)
	if is_instance_valid(boot.game) and boot.game.initialized:
		check(not boot.loading.visible and is_instance_valid(boot.game.world.player), "Loading releases only after playable world exists")
		check(not boot.game.startup_loading, "Completion releases startup gameplay lock")
		check(not boot.game.profile.data.run.active, "Fresh start enters camp")
		check(is_equal_approx(boot.progress, 1.0), "Loading reaches 100 percent")
		check(values.size() >= 6, "Progress includes resource and initialization milestones")
		for index in range(1, values.size()):
			check(values[index] >= values[index - 1], "Progress stays monotonic at milestone %d" % index)
		boot.game._primary()
		var regions: Array = boot.game.campaign.region_choices()
		check(not regions.is_empty(), "Resume fixture offers an adventure region")
		if not regions.is_empty(): boot.game._select_region(int(regions[0].node_id))
		var transition_deadline := Time.get_ticks_msec() + 60000
		while boot.game._transitioning and Time.get_ticks_msec() < transition_deadline:
			await process_frame
		check(boot.game.profile.data.run.active and not boot.game._transitioning, "Adventure fixture reaches its first room")
		saved_node = boot.game.campaign.state.current_node_id
		boot.game.profile.data.materials["101"] = 4321
		boot.game._save(true)
	boot.queue_free()
	await process_frame
	await process_frame
	var resumed = load("res://scenes/startup.tscn").instantiate()
	resumed.game_save_store = DungeonSaveStore.new(path)
	canvas.add_child(resumed)
	await process_frame
	check(resumed.home.visible and not is_instance_valid(resumed.game), "Existing save still opens homepage first")
	var event := InputEventKey.new()
	event.keycode = KEY_ENTER
	event.pressed = true
	canvas.push_input(event, true)
	check(resumed.starting, "Enter key starts the game")
	await _wait_start(resumed)
	if is_instance_valid(resumed.game) and resumed.game.initialized:
		check(resumed.game.systems.material(101) == 4321, "Start restores existing save without resetting progress")
		check(resumed.game.profile.data.run.active and resumed.game.campaign.state.current_node_id == saved_node, "Startup restores the saved adventure room")
		check(not resumed.game._transitioning and not resumed.game.room_loading.visible, "Startup waits for the restored room transition")
	resumed.queue_free()
	await process_frame
	await process_frame
	var retry = load("res://scenes/startup.tscn").instantiate()
	canvas.add_child(retry)
	retry.game_scene_path = "res://scenes/startup-missing-fixture.tscn"
	retry.home.request_start()
	var deadline := Time.get_ticks_msec() + 5000
	while retry.starting and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not retry.starting and retry.home.visible and not retry.loading.visible, "Missing resource returns to homepage")
	check(not retry.home.start_button.disabled and not retry.home.error_label.text.is_empty(), "Failure offers an enabled retry action")
	retry.game_scene_path = "res://scenes/main.tscn"
	retry.game_save_store = DungeonSaveStore.new("/private/tmp/startup-retry-%d.json" % Time.get_ticks_usec())
	retry.home.request_start()
	await _wait_start(retry)
	check(not retry.loading.visible, "Retry successfully enters the game")
	canvas.queue_free()
	await process_frame
	print("STARTUP_FLOW_TEST ", JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty(), "rendered": render_check}))
	quit(0 if failures.is_empty() else 1)
