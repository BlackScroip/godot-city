extends SceneTree

var failures: Array[String] = []
var checks := 0
var commands: Array[String] = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("PREPARE LAYOUT: " + message)

func _initialize() -> void:
	_run.call_deferred()

func settle() -> void:
	for frame in 10: await process_frame

func click(canvas: SubViewport, control: Control) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = control.get_global_rect().get_center()
	canvas.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = motion.position
		event.pressed = pressed
		canvas.push_input(event, true)
		await process_frame

func inspect_layout(page: Control, dimensions: Vector2i, state: String) -> void:
	var label := "%s %s" % [dimensions, state]
	for control in [page.header, page.left, page.right, page.footer, page.start, page.list]:
		check(page.get_global_rect().encloses(control.get_global_rect()), "Preparation control fits %s: %s" % [label, control.get_class()])
	check(page.list.size.y >= 80, "Difficulty list retains at least 80px %s actual %.1f" % [label, page.list.size.y])
	check(page.right.get_global_rect().end.y <= page.footer.get_global_rect().position.y, "Difficulty list and footer do not overlap " + label)
	check(page.start.size.y >= 44, "Entry target remains at least 44px " + label)
	check(page.start.get_theme_color("font_focus_color") == page.start.get_theme_color("font_color"), "Entry focus preserves readable label color " + label)
	check(not page.reason.visible if state == "enabled" else page.reason.visible, "Empty reason reserves no footer space " + label)
	var skin: StyleBoxTexture = page.start.get_theme_stylebox("disabled" if page.start.disabled else "normal")
	var expected_key := "主城建造离开按钮" if page.start.disabled else "几何ui-异形白色按钮"
	check(skin.texture.resource_path == page.assets[expected_key], "Entry uses the original state-specific skin " + label)
	var text_size = page.start.get_theme_font("font").get_string_size(page.start.text, HORIZONTAL_ALIGNMENT_LEFT, -1, page.start.get_theme_font_size("font_size"))
	check(text_size.y <= page.start.size.y - skin.get_content_margin(SIDE_TOP) - skin.get_content_margin(SIDE_BOTTOM) + 1, "Entry caption fits its inner height " + label)
	var text_width = page.start.size.x - skin.get_content_margin(SIDE_LEFT) - skin.get_content_margin(SIDE_RIGHT) - page.start.get_theme_constant("icon_max_width") - page.start.get_theme_constant("h_separation")
	check(text_size.x <= text_width, "Entry icon and caption fit its inner width " + label)
	for key in page.equipment.get_children():
		var stack: VBoxContainer = key.get_child(0)
		check(key.get_global_rect().encloses(stack.get_global_rect()), "Equipment content stays inside its paper frame " + label)
		for child in stack.get_children():
			if not child.visible: continue
			check(stack.get_global_rect().encloses(child.get_global_rect()), "Equipment descendant fits: " + child.get_class() + " " + label)
			if child is Label:
				check(child.text.is_empty() or child.get_visible_line_count() > 0, "Equipment caption has a visible rendered line " + label)
				var measured = child.get_theme_font("font").get_multiline_string_size(child.text, HORIZONTAL_ALIGNMENT_CENTER, child.size.x, child.get_theme_font_size("font_size"), -1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE)
				check(measured.y <= child.size.y + 1, "Equipment caption is fully visible " + label)
	for control in [page.equipment, page.token_title, page.token_scroll, page.left.get_child(0).get_child(-1)]:
		check(page.left.get_global_rect().encloses(control.get_global_rect()), "Left preparation section fits " + label)
	check(page.token_title.get_visible_line_count() > 0, "Loadout title has a visible rendered line " + label)
	for slot in page.token_slots.get_children(): check(slot.size.x >= 44 and slot.size.y >= 44, "Seven-slot loadout retains usable targets " + label)
	for index in page.row_buttons.size():
		var row: Button = page.row_buttons[index]
		var line: HBoxContainer = row.get_child(0)
		check(line.get_node("DifficultyLock").visible == not page.systems.difficulty_unlocked(index), "Difficulty lock follows the live unlock state " + label)
		check(row.get_global_rect().encloses(line.get_global_rect()), "Difficulty row content fits its frame " + label)
		for child in line.get_children():
			if child.visible: check(line.get_global_rect().encloses(child.get_global_rect()), "Difficulty descendant fits: " + child.get_class() + " " + label)
	for control in page.footer.get_children():
		if control.visible: check(page.footer.get_global_rect().encloses(control.get_global_rect()), "Footer child fits " + label)
	if page.chaos.visible:
		for child in page.chaos.get_children(): check(page.chaos.get_global_rect().encloses(child.get_global_rect()), "Chaos descendant fits " + label)
		check(page.chaos.get_child(-1).size.x >= 132, "Chaos claim action stays visible " + label)

func _run() -> void:
	var catalog = DungeonCatalog.new()
	check(catalog.load_all(), "Catalog loads")
	var systems = DungeonSystems.new(catalog, DungeonProfile.new())
	systems.set_record("token:slots", 6)
	var canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var page = preload("res://scripts/presentation/adventure_prepare.gd").new()
	page.theme = DungeonStyle.theme()
	canvas.add_child(page)
	page.command.connect(func(kind, _id, _extra): commands.append(kind))
	var rows: Array = []
	for level in range(11): rows.append({"difficulty_status": systems.difficulty_status(level)})
	page.configure(null, rows, {"difficulty": 0, "systems": systems, "catalog": catalog, "preparation": systems.adventure_preparation_status(0), "resources": [["sprite_materialicon_101", "229"], ["sprite_materialicon_90002", "0"]]})
	check(not page.start.disabled and page.row_buttons.size() == 11, "Default difficulty has an entry button and all tiers")
	page._select(1)
	check(page.start.disabled and not page.reason.text.is_empty(), "Locked tier can be inspected but cannot start")
	check(not systems.begin_run(12, 1, 100, 1).success, "UI gate is enforced by actual begin_run")
	for dimensions in [Vector2i(2460, 1080), Vector2i(1600, 900), Vector2i(844, 390), Vector2i(740, 360), Vector2i(667, 375)]:
		canvas.size = dimensions
		page.size = Vector2(dimensions)
		for state in ["enabled", "locked", "chaos"]:
			systems.set_record("difficulty:win:9", 1 if state == "chaos" else 0)
			page._select(0 if state == "enabled" else 1 if state == "locked" else 10)
			await settle()
			inspect_layout(page, dimensions, state)
			var before := commands.count("primary")
			await click(canvas, page.start)
			check(commands.count("primary") == before + (0 if state == "locked" else 1), "Entry pointer click obeys the actual gate %s %s" % [dimensions, state])
			page.token_scroll.ensure_control_visible(page.token_slots.get_child(-1))
			await settle()
			check(page.token_scroll.get_global_rect().encloses(page.token_slots.get_child(-1).get_global_rect()), "Final token slot is reachable %s %s" % [dimensions, state])
			page.token_scroll.scroll_horizontal = 0
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				var picture = canvas.get_texture().get_image()
				check(not picture.is_empty(), "Rendered preparation pixels")
				picture.save_png("res://reports/adventure-prepare-%s-%dx%d.png" % [state, dimensions.x, dimensions.y])
				if state == "enabled" and dimensions == Vector2i(844, 390): picture.save_png("res://reports/camp-navigation-difficulty-844x390.png")
		page._show_help()
		for frame in 3: await process_frame
		check(page.get_global_rect().encloses(page.help_overlay.get_child(1).get_global_rect()), "Help panel fits %s" % dimensions)
		if DisplayServer.get_name() != "headless":
			await create_timer(0.2).timeout
			await RenderingServer.frame_post_draw
			canvas.get_texture().get_image().save_png("/private/tmp/adventure-help-%dx%d.png" % [dimensions.x, dimensions.y])
		page._close_help()
	page._select(1)
	await settle()
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
	await settle()
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
