extends SceneTree

var checks := 0
var failures: Array[String] = []
var captures: Array[String] = []
var urls: Array[String] = []
var launch_error := ERR_CANT_OPEN
var game: Node
var canvas: SubViewport

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr(message)

func _run() -> void:
	create_timer(90).timeout.connect(func(): quit(2))
	canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	game = load("res://scenes/main.tscn").instantiate()
	game.save_store = DungeonSaveStore.new("/private/tmp/hud-actions-flow-%d.json" % Time.get_ticks_usec())
	canvas.add_child(game)
	game.set_process(false)
	game.world.set_process(false)
	game.world.set_physics_process(false)
	game.world.player.set_physics_process(false)
	game.audio.stop()
	game._open_external_url = func(url: String):
		urls.append(url)
		return launch_error
	for frame in 5: await process_frame
	check(game.world._camp_camera and game.hud.skill_cluster.visible, "Fresh camp shows combat controls immediately")
	check(game.hud.skill_by_slot.values().all(func(key): return not key.disabled) and not game.hud.attack_mode_button.disabled, "Camp enables attack, dodge, skills and the automatic attack switch")
	_check_camp_combat()
	check(game.systems.stat("wins") == 0 and game.hud.navigation_buttons.menu_adventure.visible, "Start adventure is visible before a first victory")
	game.hud.navigation_buttons.menu_adventure.pressed.emit()
	check(game.hud.modal_open and is_instance_valid(game.hud.page.prepare_view), "Actual quick-start button opens adventure preparation")
	check(not game.hud.page.page_context.in_run and not game.profile.data.run.active, "Quick start waits for explicit preparation confirmation")
	check(game.systems.stat("ui:read:Btn_QuickStart") == 1 and not game.hud._navigation_badges.menu_adventure.visible, "Quick-start acknowledgement persists and clears only its badge")
	check(int(game.save_store.load_profile().stats.get("ui:read:Btn_QuickStart", 0)) == 1, "Quick-start acknowledgement is written to the real save store")
	game._action("close_page", 0, 0)
	check(game.hud.skill_cluster.visible, "Closing adventure preparation restores camp combat controls")
	check(not game.hud.navigation_buttons.has("menu_cloud"), "Camp navigation excludes cloud saving")
	game._action("cloud_save", 0, 0)
	game._action("confirm_cloud_save", 0, 0)
	check(not game.hud.modal_open, "Removed cloud commands cannot open a placeholder page")
	game.systems.set_record("difficulty:win:0", 1)
	game.hud.update_navigation(game.systems)
	var currency_before: int = game.systems.material(90002)
	game.hud.navigation_buttons.menu_comment.pressed.emit()
	check(game.hud.page_title.text == "分享评价" and urls.is_empty(), "Review entry opens confirmation without launching externally")
	check(not game.hud._navigation_badges.menu_comment.visible and game.systems.stat("ui:read:Btn_GoComment") == 0, "Opening review dismisses the transient badge without claiming the reward")
	game._action("close_page", 0, 0)
	check(game.hud.navigation_buttons.menu_comment.visible and game.systems.material(90002) == currency_before, "Canceling review retains the entry and grants no reward")
	game.hud.navigation_buttons.menu_comment.pressed.emit()
	game._action("confirm_go_comment", 0, 0)
	check(urls == [game.COMMENT_URL] and game._comment_confirmation_pending, "A failed external launch keeps the review confirmation retryable")
	check(game.systems.material(90002) == currency_before and game.systems.stat("ui:read:Btn_GoComment") == 0, "Failed launch cannot falsely consume the review reward")
	launch_error = OK
	game._action("confirm_go_comment", 0, 0)
	check(game.systems.material(90002) == currency_before + 200 and game.hud.page_title.text == "获得奖励", "Accepted review launch grants the native reward and shows it")
	check(game.systems.stat("ui:read:Btn_GoComment") == 1 and not game.hud.navigation_buttons.menu_comment.visible, "Completed review persists its acknowledgement and hides its entry")
	game._action("confirm_go_comment", 0, 0)
	check(game.systems.material(90002) == currency_before + 200 and urls.size() == 2, "Repeated confirmation cannot duplicate a review reward")
	var saved: Dictionary = game.save_store.load_profile()
	check(int(saved.stats.get("ui:read:Btn_GoComment", 0)) == 1 and int(saved.materials.get("90002", 0)) == currency_before + 200, "Reward and review acknowledgement persist together")
	game._action("close_page", 0, 0)
	game.hud.navigation_buttons.menu_store.pressed.emit()
	check(game.menus.current_page == "mall" and game.hud.page._layout == "shop" and game.hud.page.displayed_row_count() > 0, "Store entry opens enabled packaged offers")
	check(is_instance_valid(game.hud.page.shop_view) and is_instance_valid(game.hud.page.shop_view.canvas), "Integrated store finishes configuring its actual controls")
	game._action("close_page", 0, 0)
	game.hud.navigation_buttons.menu_character.pressed.emit()
	check(game.menus.current_page == "characters" and game.hud.page._layout == "character" and game.hud.page.displayed_row_count() > 0, "Character entry opens actual character details")
	check(is_instance_valid(game.hud.page.character_view) and is_instance_valid(game.hud.page.character_view.portrait), "Integrated character detail finishes configuring its actual controls")
	game._action("close_page", 0, 0)
	game.hud.navigation_buttons.menu_settings.pressed.emit()
	check(game.menus.current_page == "settings" and game.hud.page._layout == "settings", "Settings icon opens its settings page")
	check(not game.hud.page._rows.any(func(row): return row.title == "云存档"), "Account settings omit cloud saving")
	game._action("auto_attack_mode", "heavy", 0)
	check(game.world.auto_attack_mode == "heavy" and game.hud.attack_mode == "heavy", "Actual settings command updates gameplay and the skill switch")
	game._action("close_page", 0, 0)
	check(game.hud.skill_cluster.visible and game.hud.joystick.visible, "Closing settings restores movement and camp combat controls")
	game.hud.begin_touch_customization()
	game.hud.cancel_touch_customization()
	check(game.hud.skill_cluster.visible and game.hud.joystick.visible, "Canceling touch customization restores camp combat controls")
	check(game.systems.begin_run(20261026, 1, 100, 0).success, "Integrated fixture starts a real run")
	game.hud.set_adventure_mode(true)
	game.hud.update_navigation(game.systems)
	game.hud.navigation_buttons.menu_difficulty.pressed.emit()
	check(game.hud.page.page_context.in_run and game.hud.page.prepare_view.start.disabled, "Run difficulty opens the read-only presentation")
	var before_difficulty: int = game.difficulty
	game._action("difficulty", 1, 0)
	check(game.difficulty == before_difficulty, "Read-only run difficulty cannot mutate the active difficulty")
	game._action("close_page", 0, 0)
	var meal: Dictionary = game.catalog.rows("CatMealData")[0]
	game.profile.data.purchased_meals = {str(meal.Id): 1}
	game.hud.update_navigation(game.systems)
	game.hud.navigation_buttons.menu_meal_buffs.pressed.emit()
	check(game.menus.current_page == "meal_buffs" and game.hud.page._rows[0].meal_id == meal.Id, "Actual meal entry opens this run's purchased effect")
	check(game.hud.page._rows[0].buttons.is_empty(), "Meal effect popup has no purchase or research mutation")
	game._action("close_page", 0, 0)
	check(DungeonStyle.texture("menu_comment") != null and DungeonStyle.texture("menu_meal_buffs") != null, "Recovered APK menu icons load")
	await _capture_hud_states()
	var report := {"checks": checks, "passed": failures.is_empty(), "failures": failures, "captures": captures}
	FileAccess.open("res://reports/hud-actions-flow-tests.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("HUD_ACTIONS_FLOW ", JSON.stringify(report))
	game.systems.decorations = null
	game.queue_free()
	await process_frame
	canvas.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _check_camp_combat() -> void:
	var combat: RefCounted = game.world.player.combat
	var saved: Dictionary = combat.snapshot().duplicate(true)
	game.world._background = false
	game.world.paused = false
	for slot in range(5):
		game.world.clear_input()
		combat.restore(saved)
		for index in range(5):
			combat.energy[index] = combat.skill_capacity(index)
			combat.cooldowns[index] = 0.0
		combat.drain_events()
		if slot == 0:
			var key: DungeonTouchButton = game.hud.skill_by_slot[0]
			var event := InputEventScreenTouch.new()
			event.index = 10
			event.position = key.get_global_transform_with_canvas() * (key.size * 0.5)
			event.pressed = true
			key._input(event)
			check(game.world.intent.attack_held, "Camp attack touch reaches the gameplay controller")
			event.pressed = false
			key._input(event)
		else:
			var event := InputEventAction.new()
			event.action = ["", "dodge", "skill", "burst", "heavy"][slot]
			event.pressed = true
			game._unhandled_input(event)
		check(int(game.world.intent.pending.get("slot", -1)) == slot, "Camp accepts buffered input for slot " + str(slot))
		game.world._tick_player_input(1.0 / 60.0)
		check(combat._current_slot == slot and not combat.current_action.is_empty(), "Camp executes the actual action for slot " + str(slot))
	game.world.clear_input()
	combat.restore(saved)
	combat.drain_events()
	game.hud.update_combat(combat, true)

func _capture_hud_states() -> void:
	if DisplayServer.get_name() == "headless": return
	game.profile.data.run.active = false
	game.profile.data.stats.erase("ui:read:Btn_GoComment")
	game.hud.set_adventure_mode(false)
	game.hud.update_navigation(game.systems)
	game.hud.update_combat(game.world.player.combat, true)
	game.hud.message_label.text = ""
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390)]:
		canvas.size = dimensions
		game.hud._layout()
		for counter in game.hud.counter_buttons:
			counter.set_process(false)
			counter.advance(6)
		await _capture("camp-hidden-%dx%d" % [dimensions.x, dimensions.y])
		check(game.hud.skill_cluster.visible and game.hud.navigation_buttons.menu_adventure.visible, "Camp shows start adventure and combat controls at " + str(dimensions))
		for id in [101, 102, 103, 90002, 108]: game.systems.grant_material(id, 1)
		for counter in game.hud.counter_buttons: counter.advance(0.5)
		await _capture("camp-resources-%dx%d" % [dimensions.x, dimensions.y])
		for counter in game.hud.counter_buttons:
			if counter.visible: check(not counter.get_global_rect().intersects(game.hud.camp_button.get_global_rect()), "Transient resource rows avoid the camp entry at " + str(dimensions))

func _capture(label: String) -> void:
	for frame in 4: await process_frame
	await RenderingServer.frame_post_draw
	var screenshot: Image = canvas.get_texture().get_image()
	var path := "res://reports/hud-%s.png" % label
	check(not screenshot.is_empty(), "Integrated HUD capture contains pixels: " + label)
	screenshot.save_png(path)
	captures.append(path)
