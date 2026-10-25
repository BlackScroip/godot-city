extends SceneTree

var failures: Array[String] = []
var game: Node
var canvas: SubViewport

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func capture(name: String) -> void:
	for frame in 3: await process_frame
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var image = canvas.get_texture().get_image()
	check(not image.is_empty(), "Screenshot has pixels: " + name)
	image.save_png("/private/tmp/level-navigation-" + name + ".png")

func _run() -> void:
	canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	game = load("res://scripts/main.gd").new()
	game.save_store = DungeonSaveStore.new("/private/tmp/level-navigation-profile-%d.json" % Time.get_ticks_usec())
	canvas.add_child(game)
	game.audio.stop()
	await process_frame
	game._primary()
	var deadline = Time.get_ticks_msec() + 60000
	while game._transitioning and Time.get_ticks_msec() < deadline: await process_frame
	check(not game._transitioning and game.profile.data.run.active, "Enters actual adventure")
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390)]:
		canvas.size = dimensions
		await process_frame
		game.hud._layout()
		var suffix = "%dx%d" % [dimensions.x, dimensions.y]
		await capture("hud-" + suffix)
		game.set_process(false)
		var charge_fixture = DungeonCombat.new()
		charge_fixture.configure(null, null, game.selected_character)
		charge_fixture.request_attack(1)
		charge_fixture.tick(0.3)
		game.hud.update_combat(charge_fixture, false)
		await capture("dodge-one-" + suffix)
		charge_fixture.request_attack(1)
		charge_fixture.tick(0.3)
		game.hud.update_combat(charge_fixture, false)
		await capture("dodge-zero-" + suffix)
		game.set_process(true)
		game.hud.adventure_button.pressed.emit()
		check(game.menus.current_page == "difficulty" and game.hud.page._layout == "prepare", "Difficulty navigation opens preparation page")
		check(game.hud.page.page_context.get("in_run", false), "Difficulty page knows adventure is active")
		for row in game.hud.page._rows:
			for command in row.get("buttons", []): check(command.get("disabled", false), "Adventure difficulty is read only")
		check(game.hud.page.find_children("*", "Button", true, false).all(func(key): return key.text != "进入迷宫"), "In-run page has no enter labyrinth action")
		await capture("difficulty-" + suffix)
		game.hud.page.closed.emit()
		check(not game.hud.modal_open, "Difficulty close restores gameplay")
		game.hud.navigation.get_node("menu_character").pressed.emit()
		check(game.menus.current_page == "characters", "Character navigation opens actual character page")
		game.hud.page.closed.emit()
		game.hud.navigation.get_node("menu_settings").pressed.emit()
		check(game.menus.current_page == "settings", "Settings navigation opens settings page")
		await capture("settings-" + suffix)
		game.hud.page.closed.emit()
		check(not game.hud.modal_open and game.hud.navigation.visible, "Settings close restores navigation")
	game.hud.navigation.get_node("menu_settings").pressed.emit()
	var commands: Array = []
	for row in game.hud.page._rows: commands.append_array(row.get("buttons", []))
	check(commands.any(func(command): return command.action == "retreat"), "Settings includes return to camp action")
	game.hud.action.emit("retreat", 0, 0)
	check(game.hud.page_title.text == "结束本次冒险？", "Return requests existing adventure-end confirmation")
	game.hud.action.emit("confirm_retreat", 0, 0)
	game.hud.action.emit("result_next", 0, 0)
	game.hud.action.emit("result_camp", 0, 0)
	await process_frame
	check(not game.profile.data.run.active and not game.hud.adventure_mode, "Settings return action restores camp")
	check(game.hud.navigation.get_children().filter(func(key): return key.visible).size() == 5, "Camp navigation restored after settings return")
	game.queue_free()
	canvas.queue_free()
	await process_frame
	print("LEVEL NAVIGATION VISUAL ", "PASS" if failures.is_empty() else "FAIL ", failures)
	quit(0 if failures.is_empty() else 1)
