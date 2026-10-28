extends SceneTree

var checks := 0
var failures: Array[String] = []
var game: Node
var canvas: SubViewport

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr(message)

func _initialize() -> void:
	_run.call_deferred()

func _settle() -> void:
	for frame in 8: await process_frame

func _run() -> void:
	canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	game = load("res://scenes/main.tscn").instantiate()
	game.save_store = DungeonSaveStore.new("/private/tmp/adventure-prepare-flow-%d.json" % Time.get_ticks_usec())
	canvas.add_child(game)
	game.set_process(false)
	game.world.set_physics_process(false)
	game.audio.stop()
	await _settle()
	var portal: Dictionary = game.world.camp_facility("difficulty")
	check(not portal.is_empty(), "Camp has its source adventure portal")
	if not portal.is_empty(): check(game.world.interactions.interact(str(portal.id)).success, "Actual portal interaction succeeds")
	check(game.hud.modal_open and is_instance_valid(game.hud.page.prepare_view) and not game.profile.data.run.active, "Portal opens preparation before creating a run")
	var page = game.hud.page.prepare_view
	check(page.context.resources.size() == 2, "Preparation receives current gold and premium currency")
	page._select(1)
	check(page.selected == 1 and page.start.disabled and game.difficulty == 0, "Locked preview leaves selected game difficulty intact")
	game._close_page()
	game.systems.set_record("wins", 1)
	game.hud.update_navigation(game.systems)
	game.hud.adventure_button.pressed.emit()
	check(is_instance_valid(game.hud.page.prepare_view) and not game.profile.data.run.active, "Victory-unlocked quick start opens preparation")
	game._close_page()
	game._environment_action("transition", {})
	check(is_instance_valid(game.hud.page.prepare_view) and not game.profile.data.run.active, "Camp transition also opens preparation")
	game.systems.set_record("difficulty:win:0", 1)
	game.menus.open("difficulty")
	page = game.hud.page.prepare_view
	await _settle()
	page.list.scroll_vertical = 100
	page._select(1)
	await _settle()
	check(page == game.hud.page.prepare_view and page.list.scroll_vertical == 100, "Selecting unlocked difficulty preserves the page and scroll offset")
	check(page.selection_tween != null, "Difficulty selection starts transition feedback")
	page.header.get_child(2).pressed.emit()
	check(is_instance_valid(page.help_overlay), "Question button opens difficulty help")
	page.help_overlay.get_child(1).get_child(0).get_child(3).get_child(1).pressed.emit()
	check(page.help_page == 1 and is_instance_valid(page.help_overlay), "Difficulty help supports the second page")
	page._close_help()
	check(not is_instance_valid(page.help_overlay) and game.hud.modal_open, "Closing help keeps preparation open")
	page.token_slots.get_child(0).pressed.emit()
	check(game.menus.current_page == "tokens" and game.hud.page.page_context.get("back_action") == "page:difficulty", "Token slot opens real equipment with preparation return path")
	game.profile.data.buildings["1"] = 3
	game.profile.data.buildings["2"] = 3
	var token_id = int(game.systems.relationship_tokens.ids()[0])
	game.systems.set_record("token:" + str(token_id), 1)
	game._action("op:equip_token", token_id, 0)
	check(game.systems.relationship_tokens.equipped().has(token_id), "Token equipment action equips an owned token")
	game.hud.page.back_requested.emit()
	check(is_instance_valid(game.hud.page.prepare_view), "Token equipment returns to preparation")
	check(game.hud.page.prepare_view.token_slots.get_child(0).tooltip_text == game.systems.token_status(token_id).name, "Preparation displays the equipped token after returning")
	check(game.difficulty == 1 and not game.hud.page.prepare_view.start.disabled, "Winning previous difficulty enables selection and entry")
	game._save(true)
	check(int(game.save_store.load_profile().get("selected_difficulty", -1)) == 1, "Selected difficulty persists through actual menu action")
	for level in range(10): game.systems.set_record("difficulty:win:" + str(level), 1)
	game.systems.set_record("chaos:clear:1", 1)
	game._action("difficulty", 10, 0)
	game._action("chaos_level", 2, 0)
	check(game.difficulty == 10 and game.systems.selected_chaos_level(1) == 2, "Chaos layer control selects the next unlocked layer")
	var before = game.systems.material(90002)
	game._action("claim_chaos_rewards", 0, 0)
	game._action("claim_chaos_rewards", 0, 0)
	check(game.systems.material(90002) == before + 500 and game.systems.stat("chaos:claimed:1") == 1, "Repeated UI claim grants source first-clear reward once")
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390)]:
		canvas.size = dimensions
		game.hud._layout()
		await _settle()
		page = game.hud.page.prepare_view
		check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(page.get_global_rect()), "Integrated preparation fills viewport %s" % dimensions)
		for control in [page.header, page.left, page.right, page.chaos, page.start, page.list]:
			check(page.get_global_rect().encloses(control.get_global_rect()), "Integrated chaos controls fit %s" % dimensions)
		check(page.list.size.y >= 80, "Chaos retains a usable difficulty list %s" % dimensions)
		check(page.list.get_global_rect().has_point(page.row_buttons[10].get_global_rect().get_center()), "Selected chaos row stays visible after resize %s" % dimensions)
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			canvas.get_texture().get_image().save_png("res://reports/adventure-prepare-integrated-%dx%d.png" % [dimensions.x, dimensions.y])
	game.hud.page.prepare_view.start.pressed.emit()
	check(game.profile.data.run.active and game.campaign.state.region_selection, "Preparation confirmation opens world selection")
	check(game.hud.page.route_view.is_world_map() and game.hud.page.route_view.selected_id == 0, "First world region waits for explicit selection")
	check(int(game.profile.data.run.counters.chaos_level) == 2, "New run captures the prepared chaos layer")
	game.systems.decorations = null
	game.queue_free()
	await process_frame
	canvas.queue_free()
	await process_frame
	print("ADVENTURE_PREPARE_FLOW ", JSON.stringify({"checks": checks, "passed": failures.is_empty(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)
