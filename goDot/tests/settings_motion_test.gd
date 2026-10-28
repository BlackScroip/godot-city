extends SceneTree

var failures: Array[String] = []
var checks := 0
var viewport: SubViewport
var game
var fixture := "/private/tmp/city-settings-motion-%d" % Time.get_ticks_usec()

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr(message)

func _run() -> void:
	create_timer(80).timeout.connect(func(): quit(2))
	DungeonSettings.settings_path = fixture + ".cfg"
	DungeonSettings._loaded_path = ""
	DungeonLocale.set_locale("zh_CN", false)
	viewport = SubViewport.new()
	viewport.size = Vector2i(1600, 900)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	game = load("res://scenes/main.tscn").instantiate()
	game.save_store = DungeonSaveStore.new(fixture + ".json")
	viewport.add_child(game)
	game.set_process(false)
	game.world.process_mode = Node.PROCESS_MODE_DISABLED
	game.audio.stop()
	game.menus.open("settings")
	await _settle()
	var view = game.hud.page.special.settings_view
	var choices = view.controls.damage_numbers
	var target: Button = choices.get_child(2)
	var before: Rect2 = choices._selection_rect
	await _click(target.get_global_rect().get_center())
	check(DungeonSettings.read_options().damage_numbers == 2, "Real pointer click persists the segment value")
	check(view.controls.damage_numbers == choices, "Selecting an option preserves the segment nodes")
	check(choices._selection_rect.position.x > before.position.x and choices._selection_rect.position.x < target.position.x, "Selected background moves through intermediate positions")
	await _click(choices.get_child(1).get_global_rect().get_center())
	await _click(choices.get_child(0).get_global_rect().get_center())
	await create_timer(0.36).timeout
	check(choices.selected_index == 0 and choices._selection_rect.is_equal_approx(choices.get_child(0).get_rect()), "Rapid selection changes finish on the latest choice")
	DungeonSettings.set_option("ui_speed", 2)
	await _click(target.get_global_rect().get_center())
	await create_timer(0.22).timeout
	check(choices._selection_rect.is_equal_approx(target.get_rect()), "Double UI speed completes segment transitions sooner")
	DungeonSettings.set_option("ui_speed", 1)
	await _click(choices.get_child(0).get_global_rect().get_center())
	await create_timer(0.36).timeout
	view.scroll.reset_motion(180)
	await process_frame
	var position_before: int = view.scroll.scroll_vertical
	view.show_section("游戏性")
	check(view.scroll.scroll_vertical == position_before and view.controls.damage_numbers == choices, "Clicking the active category preserves nodes and scroll position")
	view.show_section("画面")
	await _settle()
	view.scroll.reset_motion(250)
	view.show_section("游戏性")
	await _settle()
	check(view.scroll.scroll_vertical == position_before, "Returning to a category restores its scroll position")
	view.show_section("画面")
	await _settle()
	check(view.scroll.scroll_vertical == 250, "Graphics remembers an independent scroll position")
	view.scroll.reset_motion()
	var wheel := InputEventMouseButton.new()
	wheel.position = view.scroll.get_global_rect().get_center()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	viewport.push_input(wheel, true)
	await process_frame
	check(view.scroll.scroll_vertical > 0 and view.scroll.scroll_vertical < 110, "Wheel scrolling advances smoothly over multiple frames")
	await create_timer(0.35).timeout
	check(abs(view.scroll.scroll_vertical - 110) <= 1, "Wheel scrolling reaches its accumulated target")
	var pan := InputEventPanGesture.new()
	pan.position = wheel.position
	pan.delta = Vector2(0, 1)
	viewport.push_input(pan, true)
	await create_timer(0.35).timeout
	check(view.scroll.scroll_vertical > 110, "Trackpad pan gestures scroll the settings list")
	view.scroll.reset_motion(100000)
	var bottom: int = view.scroll.scroll_vertical
	viewport.push_input(wheel, true)
	await create_timer(0.15).timeout
	check(view.scroll.scroll_vertical == bottom, "Scrolling stops at the final reachable row")
	view.scroll.reset_motion()
	await _settle()
	var slider: HSlider = view.controls.ui_width.slider
	var slider_value := slider.value
	var start := slider.get_global_rect().get_center()
	await _drag(start, start - Vector2(0, 140))
	check(slider.value == slider_value and DungeonSettings.read_options().ui_width == slider_value, "Vertical drag over a slider never changes its saved value")
	var released: int = view.scroll.scroll_vertical
	await create_timer(0.12).timeout
	check(view.scroll.scroll_vertical > released, "A released vertical drag continues with inertia")
	view.scroll.reset_motion()
	await _settle()
	start = slider.get_global_rect().get_center()
	await _drag(start, start + Vector2(80, 0))
	check(slider.value > slider_value and DungeonSettings.read_options().ui_width == slider.value, "Horizontal slider drag continuously saves the adjusted value")
	view.show_section("游戏性")
	await _settle()
	view.scroll.reset_motion()
	await process_frame
	choices = view.controls.damage_numbers
	var saved: Variant = DungeonSettings.read_options().damage_numbers
	start = choices.get_child(2).get_global_rect().get_center()
	await _drag(start, start - Vector2(0, 130))
	check(DungeonSettings.read_options().damage_numbers == saved, "Dragging from a segment cancels the pending button click")
	view.scroll.reset_motion()
	ProjectSettings.set_setting("input_devices/pointing/emulate_mouse_from_touch", false)
	var touch := InputEventScreenTouch.new()
	touch.index = 3
	touch.position = view.scroll.get_global_rect().get_center()
	touch.pressed = true
	viewport.push_input(touch, true)
	var finger := InputEventScreenDrag.new()
	finger.index = 3
	finger.position = touch.position - Vector2(0, 90)
	finger.relative = Vector2(0, -90)
	viewport.push_input(finger, true)
	touch.position = finger.position
	touch.pressed = false
	viewport.push_input(touch, true)
	check(view.scroll.scroll_vertical > 0, "Direct touchscreen drag scrolls when mouse emulation is disabled")
	ProjectSettings.set_setting("input_devices/pointing/emulate_mouse_from_touch", true)
	view.scroll.reset_motion()
	view.show_section("操作配置")
	await _settle()
	var attack_choices = view._segments[0]
	await _click(attack_choices.get_child(1).get_global_rect().get_center())
	check(game.hud.page.special.settings_view == view and view._segments[0] == attack_choices, "Auto attack updates without rebuilding the settings page")
	check(game.profile.data.auto_attack_mode == "heavy" and attack_choices.selected_index == 1, "Auto attack updates runtime state and the animated selection")
	view.show_section("游戏性")
	await _settle()
	var moving = view.controls.damage_numbers
	view.scroll.reset_motion()
	await process_frame
	DungeonSettings.settings_path = fixture + "-missing/settings.cfg"
	DungeonSettings._loaded_path = ""
	view.refresh_values()
	await _click(moving.get_child(2).get_global_rect().get_center())
	check(DungeonSettings.read_options().damage_numbers == 0 and moving.selected_index == 0, "Failed saving retains the actual selected value")
	DungeonSettings.settings_path = fixture + ".cfg"
	DungeonSettings._loaded_path = ""
	view.show_section("账户")
	await _settle()
	view.open_dialog("cloud")
	check(not view.scroll.is_processing_input(), "Account dialogs suspend background scroll gestures")
	view.close_dialog()
	check(view.scroll.is_processing_input(), "Closing a dialog restores scrolling")
	await _layouts(view)
	game.systems.decorations = null
	game.queue_free()
	await process_frame
	viewport.queue_free()
	await process_frame
	for suffix in [".cfg", ".cfg.tmp", ".json", ".json.bak", ".json.tmp"]:
		if FileAccess.file_exists(fixture + suffix): DirAccess.remove_absolute(fixture + suffix)
	var report := {"checks": checks, "passed": failures.is_empty(), "failures": failures, "display": DisplayServer.get_name()}
	FileAccess.open("res://reports/settings-motion-test.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("SETTINGS_MOTION ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func _settle() -> void:
	for frame in 8: await process_frame

func _button(point: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	event.pressed = down
	viewport.push_input(event, true)

func _click(point: Vector2) -> void:
	_button(point, true)
	await process_frame
	_button(point, false)
	await process_frame

func _drag(from: Vector2, to: Vector2) -> void:
	_button(from, true)
	await process_frame
	var previous := from
	for step in 6:
		var point := from.lerp(to, float(step + 1) / 6.0)
		var event := InputEventMouseMotion.new()
		event.position = point
		event.relative = point - previous
		event.button_mask = MOUSE_BUTTON_MASK_LEFT
		viewport.push_input(event, true)
		previous = point
		await process_frame
	_button(to, false)

func _layouts(view: Control) -> void:
	var capture_dir := "res://reports/settings-motion"
	if DisplayServer.get_name() != "headless": DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(capture_dir))
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390), Vector2i(1280, 900), Vector2i(2460, 1080)]:
		viewport.size = dimensions
		for category in ["游戏性", "画面", "声音", "账户"]:
			view.show_section(category)
			await _settle()
			view.scroll.reset_motion()
			for row in view.detail.get_children():
				check(row.size.x <= view.scroll.size.x + 1, "Setting row fits %s at %s" % [category, dimensions])
				for segments in row.find_children("*", "HBoxContainer", true, false):
					if not segments in view._segments: continue
					check(row.get_global_rect().encloses(segments.get_global_rect()), "Segments fit their row at %s" % dimensions)
			check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(view.footer.get_global_rect()), "Footer fits %s" % dimensions)
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				var path := capture_dir + "/%dx%d-%s.png" % [dimensions.x, dimensions.y, category]
				viewport.get_texture().get_image().save_png(path)
	DungeonLocale.set_locale("en", false)
	viewport.size = Vector2i(1280, 900)
	for category in ["游戏性", "画面", "账户"]:
		view.show_section(category)
		await _settle()
		for row in view.detail.get_children():
			check(row.size.x <= view.scroll.size.x + 1, "Translated row fits: " + category)
		for button in view.rail.get_children():
			var width: float = button.get_theme_font("font").get_string_size(button.tr(button.text), HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size("font_size")).x
			var style: StyleBox = button.get_theme_stylebox("normal")
			var available: float = button.size.x - style.content_margin_left - style.content_margin_right - button.get_theme_constant("icon_max_width") - button.get_theme_constant("h_separation")
			check(width <= available + 1, "Translated category text fits: " + button.text)
		for segments in view._segments:
			for button in segments.get_children():
				var width: float = button.get_theme_font("font").get_string_size(button.tr(button.text), HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size("font_size")).x
				check(width <= button.size.x + 1, "Translated segment text fits: " + button.text)
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			viewport.get_texture().get_image().save_png(capture_dir + "/1280x900-%s-en.png" % category)
	DungeonLocale.set_locale("zh_CN", false)
