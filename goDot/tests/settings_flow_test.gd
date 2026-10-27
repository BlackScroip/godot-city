extends SceneTree

var checks := 0
var failures: Array[String] = []
var captures: Array[String] = []
var game
var viewport: SubViewport
var fixture := "/private/tmp/city-settings-%d" % Time.get_ticks_usec()
var previous_settings_path := DungeonSettings.settings_path
var previous_locale := DungeonLocale.current_locale()
var launch_urls: Array[String] = []
var launch_error := ERR_CANT_OPEN
var returned := false

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr(message)

func _run() -> void:
	create_timer(120).timeout.connect(func(): quit(2))
	_test_persistence()
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
	game.world.set_process(false)
	game.world.set_physics_process(false)
	game.world.player.set_physics_process(false)
	game.audio.stop()
	game._open_external_url = func(url: String):
		launch_urls.append(url)
		return launch_error
	game._return_to_title = func(): returned = true
	for frame in 5: await process_frame
	game.menus.open("settings")
	await process_frame
	var view = game.hud.page.special.settings_view
	check(view != null and view.section == "游戏性", "Settings opens the native gameplay category")
	check(view.rail.get_child_count() == 5, "Settings exposes the five APK categories")
	check(view.controls.has("dodge_priority") and view.controls.has("flash_strength"), "Gameplay includes native priority and flash controls")
	var number_choices = view.controls.damage_numbers
	number_choices.get_child(2).pressed.emit()
	check(DungeonSettings.read_options().damage_numbers == 2, "Actual damage selector persists its selected value")
	check(game.world.runtime_settings.damage_numbers == 2, "Damage selector updates the running world")
	view.show_section("画面")
	await process_frame
	check(view.controls.has("effects_opacity") and not view.controls.has("ssao"), "Graphics includes native opacity and excludes unshipped SSAO")
	view.scroll.scroll_vertical = 240
	await process_frame
	var slider: HSlider = view.controls.brightness.slider
	var scroll_before: int = view.scroll.scroll_vertical
	slider.value = 23
	check(view.controls.brightness.slider == slider and view.scroll.scroll_vertical == scroll_before, "Slider updates keep the same control and scrolling position")
	check(DungeonSettings.read_options().brightness == 23, "Graphics slider writes its native integer range")
	view.show_section("游戏性")
	view.show_section("画面")
	check(view.controls.brightness.slider.value == 23, "Category re-entry reads current values")
	game._action("customize_controls", 0, 0)
	check(is_instance_valid(game.hud.touch_editor), "Settings command opens the actual touch editor")
	var escape := InputEventAction.new()
	escape.action = "pause_game"
	escape.pressed = true
	game._unhandled_input(escape)
	check(not is_instance_valid(game.hud.touch_editor) and game.hud.modal_open, "Escape cancels touch editing and returns to settings")
	view.show_section("声音")
	await process_frame
	for entry in [["volume_master", "Master", 63], ["volume_music", "Music", 34], ["volume_effects", "Effects", 51], ["volume_voice", "Voice", 0]]:
		view.controls[entry[0]].slider.value = entry[2]
		var bus := AudioServer.get_bus_index(entry[1])
		check(bus >= 0, "Audio bus exists: " + entry[1])
		if bus >= 0:
			check(AudioServer.is_bus_mute(bus) if entry[2] == 0 else is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(bus)), entry[2] / 100.0), "Independent audio gain applies: " + entry[1])
	_test_guides(view)
	await process_frame
	view.show_section("账户")
	view.open_dialog("redeem")
	check(view.dialog_input.placeholder_text == "请输入您的兑换码", "Redemption uses the APK placeholder")
	view._submit_dialog()
	check(view.dialog_status.text.contains("请输入"), "Empty redemption remains in the dialog with validation")
	var materials_before: Dictionary = game.profile.data.materials.duplicate(true)
	view.dialog_input.text = "TEST-NO-SERVICE"
	view._submit_dialog()
	check(view.dialog_status.text.contains("尚未接入") and game.profile.data.materials == materials_before, "Unavailable redemption does not invent a reward")
	view.close_dialog()
	view.open_dialog("cloud")
	check(view.dialog_status.text.contains("尚未接入"), "Cloud entry reports its actual missing service")
	var disabled_actions := 0
	for button in view.dialog.find_children("*", "Button", true, false):
		if button.disabled: disabled_actions += 1
	check(disabled_actions == 4, "Native cloud upload, download, history and refresh remain unavailable without a service")
	view.close_dialog()
	game.hud.page.page_context.in_run = true
	view.open_dialog("cloud")
	check(view.dialog_status.text.contains("战斗中"), "Cloud entry blocks use during an active run")
	view.close_dialog()
	game.hud.page.page_context.in_run = false
	view.show_section("操作配置")
	var bindings_before: Dictionary = game.profile.data.get("key_bindings", {}).duplicate(true)
	game._action("bind_key", "skill", 0)
	var key_event := InputEventKey.new()
	key_event.physical_keycode = KEY_ESCAPE
	key_event.pressed = true
	game._input(key_event)
	check(game._binding_action.is_empty() and game.profile.data.get("key_bindings", {}) == bindings_before, "Escape cancels key capture without changing the binding")
	game._action("bind_key", "skill", 0)
	view.show_section("账户")
	key_event.physical_keycode = KEY_A
	game._input(key_event)
	check(game._binding_action.is_empty() and game.profile.data.get("key_bindings", {}) == bindings_before, "Leaving controls cannot capture later gameplay keys")
	for action in ["settings_support", "settings_forum", "settings_group"]: game._action(action, 0, 0)
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/settings/community.json"))
	check(launch_urls == [config.URL_ContactService, config.URL_TapTap, config.URL_QQGroup], "Account and footer route to this APK's actual community URLs")
	check(game.profile.data.materials == materials_before, "Failed external launches cannot grant account rewards")
	launch_error = OK
	game._action("settings_group", 0, 0)
	check(launch_urls.back() == config.URL_QQGroup and game.profile.data.materials == materials_before, "Accepted community launch preserves game progress")
	view.open_dialog("logout")
	view._submit_dialog()
	await process_frame
	check(returned and FileAccess.file_exists(fixture + ".json"), "Logout saves local progress before returning to title")
	view.close_dialog()
	if DisplayServer.get_name() != "headless": await _capture_layouts(view)
	game.systems.decorations = null
	game.queue_free()
	await process_frame
	viewport.queue_free()
	await process_frame
	DungeonSettings.settings_path = previous_settings_path
	DungeonSettings._loaded_path = ""
	DungeonLocale.set_locale(previous_locale, false)
	for suffix in [".cfg", ".cfg.tmp", ".json", ".json.bak", ".json.tmp", "-model.cfg", "-model.cfg.tmp"]:
		if FileAccess.file_exists(fixture + suffix): DirAccess.remove_absolute(fixture + suffix)
	var report := {"checks": checks, "passed": failures.is_empty(), "failures": failures, "captures": captures, "display": DisplayServer.get_name()}
	var report_path := "res://reports/settings-flow-headless-tests.json" if DisplayServer.get_name() == "headless" else "res://reports/settings-flow-tests.json"
	FileAccess.open(report_path, FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("SETTINGS_FLOW ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func _test_persistence() -> void:
	DungeonSettings.settings_path = fixture + "-model.cfg"
	DungeonSettings._loaded_path = ""
	var defaults := DungeonSettings.read_options()
	check(defaults.quality == 2 and defaults.fps == 45 and not defaults.show_timer, "Defaults follow native quality, frame cap and timer values")
	check(not defaults.auto_pickup_relic and not defaults.auto_pickup_ornament and not defaults.auto_pickup_consumable, "Native pickup mask zero disables all optional item classes")
	defaults.volume_master = 1
	check(DungeonSettings.read_options().volume_master == 100, "Returned settings cannot mutate cached values")
	DungeonSettings.migrate_legacy({"volume": 0.37, "camera_shake": false})
	check(DungeonSettings.read_options().volume_master == 37 and DungeonSettings.read_options().camera_shake == 50, "Legacy user preferences migrate before the first save")
	check(DungeonSettings.set_option("volume_music", 31), "Settings atomically save to a writable path")
	DungeonSettings._loaded_path = ""
	check(DungeonSettings.read_options().volume_music == 31 and DungeonSettings.read_options().volume_master == 37, "Saved preferences survive cache reload")
	DungeonSettings.migrate_legacy({"volume": 0.99})
	check(DungeonSettings.read_options().volume_master == 37, "Legacy profile does not overwrite stored settings")
	check(DungeonSettings.normalize("brightness", 500) == 100 and DungeonSettings.normalize("ui_height", -1) == 0, "Native numeric ranges clamp corrupted values")
	check(DungeonSettings.normalize("quality", 88) == 2 and DungeonSettings.normalize("bloom", "true") == false, "Malformed choices and booleans recover native defaults")
	check(not DungeonSettings.set_option("unknown_setting", 1), "Unknown keys cannot enter persisted settings")
	DungeonSettings.settings_path = fixture + "-missing/settings.cfg"
	DungeonSettings._loaded_path = ""
	var before := DungeonSettings.read_options()
	check(not DungeonSettings.set_option("fps", 60) and DungeonSettings.read_options() == before, "Failed disk writes retain the previous in-memory setting")

func _test_guides(view: Control) -> void:
	view.show_section("指南")
	check(view.guide_data.size() == 38 and view.rail.get_child_count() == 3, "Guides contain all 38 APK articles and three categories")
	var images := {}
	var page_count := 0
	for article in view.guide_data:
		for page_data in article.pages:
			page_count += 1
			var path := str(page_data.image)
			if path.is_empty(): continue
			images[path] = true
			check(ResourceLoader.exists(path), "Guide image imports: " + path.get_file())
	check(images.size() == 91, "Guide pages reference all 91 recovered image assets")
	check(page_count == 91, "Trailing delimiters cannot create empty guide pages")
	check(view.detail.get_child(0).text == "击败怪物！", "Combat guide ordering matches the supplied screen")
	view.open_guide(str(view.guide_data[0].id))
	check(view.guide_page_index == 0 and view.find_child("GuideImage", true, false).texture != null, "Opening an article loads the actual first guide image")
	view.change_guide_page(1)
	check(view.guide_page_index == mini(1, view._guide_pages.size() - 1), "Guide next advances within its article")
	view.change_guide_page(-100)
	check(view.guide_page_index == 0, "Guide previous clamps at the first page")
	view.change_guide_page(100)
	check(view.guide_page_index == view._guide_pages.size() - 1, "Guide next clamps at the last page")
	view.open_guide("15")
	var body: RichTextLabel = view.find_child("GuideBody", true, false)
	check(body.text.contains("[color=") and not body.get_parsed_text().contains("<color"), "Guide source colors render as rich text rather than raw tags")
	view.go_back()
	check(not is_instance_valid(view.dialog) and view.section == "指南", "Back closes an article while retaining the guide list")
	view.go_back()
	check(view.section == "声音", "Back from guides restores the previous settings category")

func _capture_layouts(view: Control) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://reports/settings"))
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390), Vector2i(2460, 1080)]:
		viewport.size = dimensions
		for section in ["游戏性", "画面", "声音", "账户", "指南"]:
			view.show_section(section)
			await create_timer(0.35).timeout
			await RenderingServer.frame_post_draw
			var root_bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
			for control in [view.back, view.rail_scroll, view.scroll]:
				check(root_bounds.encloses(control.get_global_rect()), "Settings control remains inside %s: %s" % [dimensions, control.name])
			await _capture("%dx%d-%s" % [dimensions.x, dimensions.y, section])
		view.show_section("画面")
		view.scroll.scroll_vertical = 10000
		await process_frame
		await _capture("%dx%d-graphics-bottom" % [dimensions.x, dimensions.y])
		view.show_section("指南")
		view.open_guide(str(view.guide_data[0].id))
		for frame in 4: await process_frame
		check(Rect2(Vector2.ZERO, view._logical_size).encloses(view._dialog_panel.get_rect()), "Guide dialog fits the logical viewport at %s" % dimensions)
		await _capture("%dx%d-guide-article" % [dimensions.x, dimensions.y])
		view.close_dialog()
		view.show_section("账户")
		for kind in ["cloud", "redeem"]:
			view.open_dialog(kind)
			for frame in 3: await process_frame
			check(Rect2(Vector2.ZERO, view._logical_size).encloses(view._dialog_panel.get_rect()), "Account dialog fits %s at %s" % [kind, dimensions])
			await _capture("%dx%d-%s" % [dimensions.x, dimensions.y, kind])
			view.close_dialog()

func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	check(image != null and not image.is_empty(), "Rendered viewport is nonblank: " + label)
	if image == null or image.is_empty(): return
	var colors := {}
	for row in 12:
		for column in 20:
			var pixel := image.get_pixel((column * 2 + 1) * image.get_width() / 40, (row * 2 + 1) * image.get_height() / 24)
			colors[Vector3i(roundi(pixel.r * 31), roundi(pixel.g * 31), roundi(pixel.b * 31))] = true
	check(colors.size() >= 12, "Rendered pixels contain scene and interface detail: " + label)
	var path := "res://reports/settings/" + label + ".png"
	check(image.save_png(path) == OK, "Screenshot saves: " + label)
	captures.append(path)
