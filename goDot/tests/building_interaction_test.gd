extends SceneTree

var checks := 0
var failures: Array[String] = []
var captures: Array[String] = []
var viewport: SubViewport
var game

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr(message)

func settle() -> void:
	for frame in 4: await process_frame

func point(control: Control, fraction := Vector2(0.5, 0.5)) -> Vector2:
	return control.get_global_transform_with_canvas() * (control.size * fraction)

func mouse(at: Vector2, pressed: bool, button := MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = button
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and button == MOUSE_BUTTON_LEFT else 0
	viewport.push_input(event, true)

func move_mouse(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	viewport.push_input(event, true)

func touch(at: Vector2, pressed: bool, canceled := false) -> void:
	var event := InputEventScreenTouch.new()
	event.position = at
	event.index = 3
	event.pressed = pressed
	event.canceled = canceled
	viewport.push_input(event, true)

func drag_touch(at: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = 3
	event.position = at
	viewport.push_input(event, true)

func click(control: Control) -> void:
	var at := point(control)
	mouse(at, true)
	mouse(at, false)
	await settle()

func capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var picture := viewport.get_texture().get_image()
	check(not picture.is_empty(), "Rendered building view has pixels: " + name)
	var path := "res://reports/construction-" + name + ".png"
	picture.save_png(path)
	captures.append(path)

func _run() -> void:
	create_timer(120).timeout.connect(func(): quit(2))
	var previous_locale := DungeonLocale.current_locale()
	DungeonLocale.set_locale("zh_CN", false)
	viewport = SubViewport.new()
	viewport.size = Vector2i(1600, 900)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	game = load("res://scripts/main.gd").new()
	game.save_store = DungeonSaveStore.new("/private/tmp/construction-test-%d.json" % Time.get_ticks_usec())
	viewport.add_child(game)
	game.set_process(false)
	game.world.set_process(false)
	game.world.set_physics_process(false)
	game.world.player.set_physics_process(false)
	game.audio.stop()
	game.profile.data.buildings["3"] = 1
	await settle()
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390), Vector2i(2460, 1080)]:
		viewport.size = dimensions
		game.menus.open("buildings", 2)
		game.hud._layout()
		await create_timer(0.55).timeout
		await settle()
		var view = game.hud.page.building_view
		check(view.nodes.size() == 21, "All construction stages exist: %s" % dimensions)
		check(is_equal_approx(view._open_progress, 1.0) and view.canvas.position.y == 0, "Source entrance animation finishes: %s" % dimensions)
		check(view.scroll.get_v_scroll_bar().max_value > view.scroll.size.y, "Building list has scrollable content: %s" % dimensions)
		check(view.nodes.filter(func(node): return node.selection.visible).size() == 1, "Only selected building has arrows: %s" % dimensions)
		check(view._selected_node.left.texture != null, "Original APK arrow texture loads: %s" % dimensions)
		view.set_process(false)
		view._selection_time = 0.0
		view._animate_selection()
		var left_start: float = view._selected_node.left.position.x
		var right_start: float = view._selected_node.right.position.x
		view._selection_time = 0.5
		view._animate_selection()
		check(is_equal_approx(view._selected_node.left.position.x - left_start, -12.8) and is_equal_approx(view._selected_node.right.position.x - right_start, 12.8), "APK arrow half-cycle moves symmetrically: %s" % dimensions)
		view._animate_decorations(0.0)
		check(absf(rad_to_deg(view.hammer.rotation) - 124.266) < 0.1, "Hammer starts at the recovered APK angle: %s" % dimensions)
		if dimensions == Vector2i(1600, 900):
			view._apply_open(0.0)
			await capture("entrance-start")
			view._apply_open(0.133333 * 3.0)
			view._animate_decorations(0.133333)
			await capture("entrance-mid")
		view._animate_decorations(0.35)
		check(absf(rad_to_deg(view.hammer.rotation) + 13.162) < 0.1 and absf(rad_to_deg(view.wood.rotation) - 4.60147) < 0.1, "Wood and hammer use the source rotation rebound: %s" % dimensions)
		view._apply_open(1.0)
		view._animate_decorations(0.5)
		check(absf(rad_to_deg(view.hammer.rotation) - 0.368) < 0.1 and absf(view.wood.rotation) < 0.001, "Source decoration animation settles: %s" % dimensions)
		view.set_process(true)
		var selected: int = view.selected_id
		var selected_stage: int = view.selected_stage
		var start := point(view.nodes[0].button)
		var finish := start - Vector2(0, 90)
		mouse(start, true)
		move_mouse(finish)
		mouse(finish, false)
		await settle()
		check(view.scroll.scroll_vertical > 60, "Mouse drag starting on a building scrolls: %s" % dimensions)
		check(view.selected_id == selected and view.selected_stage == selected_stage, "Dragging a building does not select it: %s" % dimensions)
		var before: int = view.scroll.scroll_vertical
		var at := point(view.scroll)
		touch(at, true)
		drag_touch(at - Vector2(0, 70))
		touch(at - Vector2(0, 70), false)
		await settle()
		check(view.scroll.scroll_vertical > before, "Touch drag scrolls at the page scale: %s" % dimensions)
		var stopped: int = view.scroll.scroll_vertical
		await create_timer(0.1).timeout
		check(view.scroll.scroll_vertical == stopped, "APK scroll stops on release without inertia: %s" % dimensions)
		mouse(point(view.scroll), true, MOUSE_BUTTON_WHEEL_DOWN)
		mouse(point(view.scroll), false, MOUSE_BUTTON_WHEEL_DOWN)
		await settle()
		check(view.scroll.scroll_vertical > stopped, "Mouse wheel reaches the construction scroll: %s" % dimensions)
		touch(point(view.scroll), true)
		touch(point(view.scroll), false, true)
		check(view._pointer == -1, "Canceled touch releases the scroll pointer: %s" % dimensions)
		view.scroll.scroll_vertical = 0
		await settle()
		await click(view.nodes[1].button)
		check(view.selected_id == int(view.nodes[1].id) and view.selected_stage == 1, "A click after dragging selects the intended stage: %s" % dimensions)
		check(view.build_button.disabled, "Future stage still follows real construction prerequisites: %s" % dimensions)
		view.select_stage(3, 0)
		await capture("list-%dx%d" % [dimensions.x, dimensions.y])
		view.scroll.scroll_vertical = 180
		await settle()
		var scroll_before: int = view.scroll.scroll_vertical
		var title_before: String = view.detail_title.text
		var wallet: Dictionary = game.profile.data.materials.duplicate(true)
		await click(view.help_button)
		await create_timer(0.35).timeout
		var dialog = view.help_dialog
		check(is_instance_valid(dialog), "Top-right question mark opens a modal: %s" % dimensions)
		if is_instance_valid(dialog):
			check(dialog.body.text.contains("阿尔托") and dialog.body.text.contains("重建冒险营地"), "Help uses the source GuideData article: %s" % dimensions)
			check(dialog.get_global_rect().encloses(dialog.panel.get_global_rect()) and dialog.get_global_rect().encloses(dialog.close_button.get_global_rect()), "Help frame and close button fit: %s" % dimensions)
			await capture("help-%dx%d" % [dimensions.x, dimensions.y])
			var old_stage: int = view.selected_stage
			await click(view.nodes[0].button)
			check(view.selected_id == 3 and view.selected_stage == old_stage and view.scroll.scroll_vertical == scroll_before, "Help blocks clicks through to the list: %s" % dimensions)
			await click(dialog.close_button)
			await create_timer(0.35).timeout
			check(not is_instance_valid(view.help_dialog) and view.detail_title.text == title_before and view.scroll.scroll_vertical == scroll_before, "Closing help preserves selection, details and scroll: %s" % dimensions)
			check(game.profile.data.materials == wallet, "Help and drag never mutate construction resources: %s" % dimensions)
		game.menus.open("buildings")
		await create_timer(0.55).timeout
		view = game.hud.page.building_view
		check(view.selected_id == 3 and view.selected_stage == 0 and view.scroll.scroll_vertical == scroll_before, "Same-page refresh restores stage and scroll: %s" % dimensions)
		view.scroll.scroll_vertical = 100000
		await settle()
		check(view.scroll.scroll_vertical <= int(view.scroll.get_v_scroll_bar().max_value - view.scroll.get_v_scroll_bar().page), "List clamps to its last row: %s" % dimensions)
		await capture("bottom-%dx%d" % [dimensions.x, dimensions.y])
		game._close_page()
	game.menus.open("buildings", 2)
	await create_timer(0.55).timeout
	var view = game.hud.page.building_view
	await click(view.help_button)
	await create_timer(0.35).timeout
	var escape := InputEventAction.new()
	escape.action = "pause_game"
	escape.pressed = true
	game._unhandled_input(escape)
	await create_timer(0.35).timeout
	check(game.hud.modal_open and not is_instance_valid(view.help_dialog), "Escape closes help before the construction page")
	await click(view.help_button)
	await create_timer(0.35).timeout
	await click(view.help_dialog.side_close)
	await create_timer(0.35).timeout
	check(game.hud.modal_open and not is_instance_valid(view.help_dialog), "Side close dismisses the single-page guide")
	game._unhandled_input(escape)
	check(view._closing and game.hud.modal_open, "Construction close keeps its source fade before leaving")
	await create_timer(0.35).timeout
	check(not game.hud.modal_open, "Escape closes construction after the fade")
	game.queue_free()
	await settle()
	DungeonLocale.set_locale(previous_locale, false)
	var result := {"checks": checks, "failures": failures, "captures": captures, "passed": failures.is_empty()}
	var output := FileAccess.open("res://reports/construction-interaction-test.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(result, "\t") + "\n")
	print("CONSTRUCTION_INTERACTION_TEST ", JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
