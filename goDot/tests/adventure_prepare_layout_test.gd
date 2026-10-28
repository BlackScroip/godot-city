extends SceneTree

var failures: Array[String] = []
var checks := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var catalog = DungeonCatalog.new()
	check(catalog.load_all(), "Catalog loads")
	var systems = DungeonSystems.new(catalog, DungeonProfile.new())
	var canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var page = preload("res://scripts/presentation/adventure_prepare.gd").new()
	page.theme = DungeonStyle.theme()
	canvas.add_child(page)
	var rows: Array = []
	for level in range(11): rows.append({"difficulty_status": systems.difficulty_status(level)})
	page.configure(null, rows, {"difficulty": 0, "systems": systems, "catalog": catalog, "preparation": systems.adventure_preparation_status(0), "resources": [["sprite_materialicon_101", "229"], ["sprite_materialicon_90002", "0"]]})
	check(not page.start.disabled and page.row_buttons.size() == 11, "Default difficulty has an entry button and all tiers")
	page._select(1)
	check(page.start.disabled and not page.reason.text.is_empty(), "Locked tier can be inspected but cannot start")
	check(not systems.begin_run(12, 1, 100, 1).success, "UI gate is enforced by actual begin_run")
	for dimensions in [Vector2i(2460, 1080), Vector2i(1600, 900), Vector2i(844, 390)]:
		canvas.size = dimensions
		page.size = Vector2(dimensions)
		for frame in 10: await process_frame
		for control in [page.header, page.left, page.right, page.start, page.list]:
			check(page.get_global_rect().encloses(control.get_global_rect()), "Preparation control fits %s: %s" % [dimensions, control.get_class()])
		check(page.list.size.y > 90, "Difficulty list remains scrollable %s" % dimensions)
		check(page.equipment.get_child(0).get_child(0).get_global_rect().end.y <= page.equipment.get_global_rect().end.y, "Equipment content fits its card %s" % dimensions)
		check(page.left.get_global_rect().encloses(page.token_slots.get_global_rect()), "Token slots fit the preparation panel %s" % dimensions)
		page._show_help()
		for frame in 3: await process_frame
		check(page.get_global_rect().encloses(page.help_overlay.get_child(1).get_global_rect()), "Help panel fits %s" % dimensions)
		if DisplayServer.get_name() != "headless":
			await create_timer(0.2).timeout
			await RenderingServer.frame_post_draw
			canvas.get_texture().get_image().save_png("/private/tmp/adventure-help-%dx%d.png" % [dimensions.x, dimensions.y])
		page._close_help()
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var picture = canvas.get_texture().get_image()
			check(not picture.is_empty(), "Rendered preparation pixels")
			picture.save_png("/private/tmp/adventure-prepare-%dx%d.png" % [dimensions.x, dimensions.y])
	page.list.scroll_vertical = 0
	var origin: Vector2 = page.list.get_global_rect().get_center()
	var press = InputEventScreenTouch.new()
	press.index = 0
	press.position = origin
	press.pressed = true
	page._input(press)
	var drag = InputEventScreenDrag.new()
	drag.index = 0
	drag.position = origin - Vector2(0, 60)
	drag.relative = Vector2(0, -60)
	page._input(drag)
	var release = InputEventScreenTouch.new()
	release.index = 0
	release.position = drag.position
	page._input(release)
	check(page.selected == 1 and page.list.scroll_vertical == 60, "Touch drag scrolls without selecting a difficulty")
	page._process(0.016)
	check(page.list.scroll_vertical > 60, "Released drag continues with inertia")
	page._set_scroll(100000)
	check(page.list.scroll_vertical <= page.list.get_v_scroll_bar().max_value - page.list.get_v_scroll_bar().page + 1, "Inertial scroll clamps at list bounds")
	page.scroll_velocity = 0
	page._set_scroll(0)
	var mouse_press = InputEventMouseButton.new()
	mouse_press.button_index = MOUSE_BUTTON_LEFT
	mouse_press.pressed = true
	mouse_press.position = page.row_buttons[0].get_global_rect().get_center()
	canvas.push_input(mouse_press)
	var mouse_drag = InputEventMouseMotion.new()
	mouse_drag.button_mask = MOUSE_BUTTON_MASK_LEFT
	mouse_drag.relative = Vector2(0, -40)
	mouse_drag.position = mouse_press.position + mouse_drag.relative
	canvas.push_input(mouse_drag)
	var mouse_release = InputEventMouseButton.new()
	mouse_release.button_index = MOUSE_BUTTON_LEFT
	mouse_release.position = mouse_drag.position
	canvas.push_input(mouse_release)
	check(page.selected == 1 and page.list.scroll_vertical == 40, "Actual mouse drag over a button scrolls without a click")
	canvas.queue_free()
	await process_frame
	systems.decorations = null
	print("ADVENTURE_PREPARE_LAYOUT ", JSON.stringify({"checks": checks, "passed": failures.is_empty(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)
