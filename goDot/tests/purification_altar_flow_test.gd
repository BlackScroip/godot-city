extends SceneTree

var game: Node
var canvas: SubViewport
var save_path := ""
var checks := 0
var failures: Array[String] = []
var captures: Array[String] = []
var layouts: Array[Dictionary] = []
var loading_observations: Array[Dictionary] = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr(message)

func _initialize() -> void:
	_run.call_deferred()

func _new_game() -> Node:
	var instance = load("res://scenes/main.tscn").instantiate()
	instance.save_store = DungeonSaveStore.new(save_path)
	canvas.add_child(instance)
	instance.set_process(false)
	instance.world.set_process(false)
	instance.world.set_physics_process(false)
	instance.world.presentation.audio_enabled = false
	instance.world.auto_attack_enabled = false
	instance.audio.stop()
	return instance

func _wait_loading() -> void:
	game.world.set_physics_process(false)
	game.world.set_process(true)
	var started := Time.get_ticks_msec()
	var deadline := Time.get_ticks_msec() + 60000
	var observed := false
	while game._transitioning and Time.get_ticks_msec() < deadline:
		# Desktop focus changes must not pause the fixture's authored arrival animation.
		game.world._background = false
		if not observed and Time.get_ticks_msec() - started > 5000:
			_observe_loading("slow", started)
			observed = true
		await process_frame
	if game._transitioning: _observe_loading("timeout", started)
	check(not game._transitioning, "Authored boss room finishes loading")
	game.set_process(false)
	game.world.set_process(false)
	game.world.set_physics_process(false)
	game.world.paused = false
	game.hud.close_page()

func _observe_loading(reason: String, started: int) -> void:
	var transfer: Node = game.world.player_transfer
	var record := {"reason": reason, "room": game._room_key, "elapsed_ms": Time.get_ticks_msec() - started, "transitioning": game._transitioning, "loading": game._loading, "world_processing": game.world.is_processing(), "game_processing": game.is_processing(), "paused": game.world.paused, "background": game.world._background, "tree_paused": paused, "simulation_scale": game.world.simulation_scale, "pending_preparation": game.world.presentation.has_pending_preparation(), "transfer_active": transfer.active, "transfer_elapsed": transfer.elapsed, "transfer_duration": transfer.duration, "transfer_action": transfer.action}
	loading_observations.append(record)
	print("PURIFICATION_ALTAR_LOADING ", JSON.stringify(record))

func _fixture() -> void:
	if is_instance_valid(game):
		game.queue_free()
		await process_frame
	save_path = "/private/tmp/city-purification-altar-flow-%d.json" % Time.get_ticks_usec()
	game = _new_game()
	await process_frame
	game.profile.data.talents["221"] = 1
	check(game.systems.begin_run(90317, game.selected_character, 500, 0).success, "Purification run starts")
	check(game.campaign.start_practice(1019101, 90317).success, "Source boss room enters")
	game._load_room()
	await _wait_loading()

func _resume() -> void:
	game.queue_free()
	await process_frame
	game = _new_game()
	await _wait_loading()

func _altar() -> Dictionary:
	for item in game.world.interactions._items.values():
		if str(item.data.get("UIBtnName", "")) == DungeonWorldInteractions.SACRIFICIAL_ALTAR: return item
	return {}

func _parts_hidden(item: Dictionary) -> bool:
	return not item.get("curse_parts", []).is_empty() and item.curse_parts.all(func(part): return not part.node.visible)

func _candidate_identity(options: Array) -> Array:
	return options.map(func(option): return [int(option.id), int(option.hp_cost), bool(option.get("locked", false))])

func _complete_boss(elapsed: float) -> void:
	# Advance the authored wave lifecycle without simulating the boss's AI or damage.
	while not game.campaign.room_ready():
		if not game.campaign.clear_wave().success: break
	game.world.elapsed = elapsed
	game.world.room_stage = "open"
	game._finish_room()
	check(game.campaign.state.phase == "reward", "Boss completion reaches the actual reward phase")

func _verify_leave_warning(label: String) -> void:
	game._leave_room()
	var rows: Array = game.hud.page._rows.filter(func(row): return str(row.get("title", "")) == "净化石坛")
	check(game.hud.modal_open and game.hud.page._layout == "unclaimed" and rows.size() == 1 and int(rows[0].count) == 1, label + " is counted once in the leave confirmation")
	check(game.campaign.state.phase == "reward", "Leave confirmation preserves the current completed room")
	if game.hud.page._layout == "unclaimed": game.hud.page.unclaimed_view.return_button.pressed.emit()
	else: game.hud.close_page()
	check(not game.hud.modal_open and game.campaign.state.phase == "reward", "Returning from the leave confirmation preserves purification availability")

func _has_pixels(image: Image) -> bool:
	if image.is_empty(): return false
	var colors: Dictionary = {}
	for y in range(0, image.get_height(), maxi(1, image.get_height() / 18)):
		for x in range(0, image.get_width(), maxi(1, image.get_width() / 32)):
			colors[image.get_pixel(x, y).to_rgba32()] = true
	return colors.size() > 32

func _capture_altar_map(label: String, consumed: bool) -> void:
	if DisplayServer.get_name() == "headless" or "--capture" not in OS.get_cmdline_user_args(): return
	var altar := _altar()
	var models: Array[Node] = altar.visual.find_children("EnvUnit_CurseAltar*", "MeshInstance3D", true, false)
	var pickups: Array[Node] = altar.visual.find_children("SourceAltarPickup", "Sprite3D", true, false)
	check(models.size() == 1 and models[0].is_visible_in_tree(), "Purification source stone remains visible: " + label)
	check(pickups.size() == 1 and pickups[0].is_visible_in_tree() != consumed, "Purification pickup visibility matches its consumed state: " + label)
	if models.is_empty(): return
	var camera: Camera3D = game.world.camera
	var previous_transform := camera.global_transform
	var previous_projection := camera.projection
	var previous_size := camera.size
	var hud_visible: bool = game.hud.visible
	game.hud.hide()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 5.6
	camera.global_position = altar.visual.global_position + Vector3(3.7, 4.8, -4.4)
	camera.look_at(altar.visual.global_position + Vector3.UP * 0.65)
	var effects: Node = game.world.environment_root.get_node("EnvironmentEffects")
	for frame in 90: effects._process(1.0 / 60.0)
	for size in [Vector2i(1600, 900), Vector2i(844, 390)]:
		canvas.size = size
		for frame in 5: await process_frame
		await RenderingServer.frame_post_draw
		var shown := canvas.get_texture().get_image()
		check(_has_pixels(shown), "Purification map renders nonblank pixels: " + label + str(size))
		var path := "res://reports/purification-altar-map-%s-%dx%d.png" % [label, size.x, size.y]
		shown.save_png(path)
		captures.append(path)
		models[0].hide()
		await process_frame
		await RenderingServer.frame_post_draw
		var hidden := canvas.get_texture().get_image()
		models[0].show()
		var changed := 0
		for y in range(size.y / 4, size.y * 3 / 4):
			for x in range(size.x / 4, size.x * 3 / 4):
				var a := shown.get_pixel(x, y)
				var b := hidden.get_pixel(x, y)
				if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.1: changed += 1
		check(changed > 80, "Authored stone platform contributes visible pixels: " + label + str(size))
	camera.global_transform = previous_transform
	camera.projection = previous_projection
	camera.size = previous_size
	game.hud.visible = hud_visible
	canvas.size = Vector2i(1600, 900)

func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless" or "--capture" not in OS.get_cmdline_user_args(): return
	for size in [Vector2i(1600, 900), Vector2i(844, 390)]:
		canvas.size = size
		await process_frame
		game.hud._layout()
		for frame in 6: await process_frame
		await create_timer(0.35).timeout
		var view = game.hud.page.special.get_child(0)
		var viewport := Rect2(Vector2.ZERO, Vector2(size))
		var heading: Rect2 = view.heading.get_global_rect()
		var back: Rect2 = view.back_button.get_global_rect()
		check(is_equal_approx(heading.position.y, back.position.y) and heading.size.y <= back.size.y + 0.5, "Purification title aligns with the back control %s %s" % [label, size])
		check(view.heading.autowrap_mode == TextServer.AUTOWRAP_OFF and not heading.intersects(view.toolbar.get_global_rect()), "Purification title stays on one line clear of the toolbar %s %s" % [label, size])
		var layout := {"state": label, "viewport": [size.x, size.y], "heading": str(heading), "back": str(back), "font_size": view.heading.get_theme_font_size("font_size"), "autowrap": view.heading.autowrap_mode, "cards": []}
		check(viewport.grow(0.5).encloses(view.toolbar.get_global_rect()), "Purification toolbar fits " + str(size))
		for part in view.parts:
			layout.cards.append({"health": str(part.health.get_global_rect()), "icon": str(part.icon_frame.get_global_rect()), "title": str(part.title.get_global_rect()), "description": str(part.scroll.get_global_rect()), "confirm": str(part.footer.get_global_rect())})
			check(viewport.grow(0.5).encloses(part.panel.get_global_rect()), "Purification card fits " + str(size))
			check(part.panel.get_global_rect().grow(0.5).encloses(part.health.get_global_rect()), "Maximum HP price stays within its card " + str(size))
			check(not part.health.get_global_rect().grow(4).intersects(part.title.get_global_rect().grow(4)), "Maximum HP price clears the item name and outlines %s %s: health=%s title=%s" % [label, size, part.health.get_global_rect(), part.title.get_global_rect()])
			check(not part.health.get_global_rect().grow(4).intersects(part.icon_frame.get_global_rect()), "Maximum HP price outline clears the item icon %s %s: health=%s icon=%s" % [label, size, part.health.get_global_rect(), part.icon_frame.get_global_rect()])
			check(not part.title.get_global_rect().grow(4).intersects(part.scroll.get_global_rect()), "Item name clears its description %s %s" % [label, size])
			check(not part.scroll.get_global_rect().intersects(part.footer.get_global_rect()), "Description clears the confirmation control %s %s" % [label, size])
			check(part.scroll.size.y >= 40, "Source description retains readable scrolling space %s %s" % [label, size])
		layouts.append(layout)
		await RenderingServer.frame_post_draw
		var image := canvas.get_texture().get_image()
		check(_has_pixels(image), "Purification selection renders nonblank pixels " + str(size))
		var path := "res://reports/purification-altar-%s-%dx%d.png" % [label, size.x, size.y]
		image.save_png(path)
		captures.append(path)
		if label == "selection-fixed":
			image.save_png("res://reports/purification-altar-selection-%dx%d.png" % [size.x, size.y])
	canvas.size = Vector2i(1600, 900)

func _run() -> void:
	create_timer(150).timeout.connect(func(): quit(2))
	canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	await _fixture()
	var altar := _altar()
	check(not altar.is_empty(), "Source boss map includes the purification stone altar")
	if altar.is_empty():
		_finish()
		return
	var marker := str(altar.id)
	var key: String = "sacrifice:" + game._room_key + ":" + marker
	var decision_key: String = "purification-altar:" + game._room_key
	var threshold := float(game.campaign.current_room().FightData.BossBattleRankTime[0])
	check(threshold == 45, "First source boss's strict fast-clear threshold is 45 seconds")
	check(not altar.state.enabled and not altar.visual.is_visible_in_tree(), "Purification altar stays hidden before boss completion")
	check(not game.world.interactions.interact(marker).success, "Hidden altar cannot be activated before boss completion")
	check(not game.profile.data.run.counters.has(decision_key), "Entering the fight does not prematurely decide fast-clear eligibility")
	_complete_boss(threshold - 0.001)
	altar = _altar()
	check(altar.state.enabled and altar.visual.is_visible_in_tree(), "Finishing below the native threshold reveals the altar")
	check(game.profile.data.run.counters.get(decision_key, false), "Eligibility is persisted for this exact room occurrence")
	check(str(game.world.interactions.prompt_for(altar)[0]) == "净化石坛", "Interaction prompt uses the APK purification stone name")
	_verify_leave_warning("Unopened purification altar")
	check(game._save(true), "Unopened eligible purification altar saves")
	await _resume()
	altar = _altar()
	check(altar.state.enabled and not altar.state.used and altar.visual.is_visible_in_tree(), "Eligible unopened altar survives full restore despite its source inactive default")
	await _capture_altar_map("ready", false)
	var before_inventory: Dictionary = game.profile.data.run.inventory.duplicate(true)
	check(game.world.interactions.interact(marker).success, "Source marker opens the real purification selection")
	var state: Dictionary = game._room_choices().open_sacrifice(key)
	check(game.hud.modal_open and not state.options.is_empty(), "Purification selection contains priced source reward candidates")
	check(game.profile.data.run.inventory == before_inventory, "Opening the stone altar does not grant a candidate")
	check(game.hud.page_title.text == "净化石坛", "Purification page uses the source altar name")
	check(altar.state.used and _parts_hidden(altar) and altar.visual.is_visible_in_tree(), "Activation hides interaction sections while retaining the altar stone")
	check(int(game.profile.data.run.counters.get("SelectLootRemainCount_Reward", 0)) == 1, "Activation creates exactly one pending sacrifice counter")
	if state.options.is_empty():
		_finish()
		return
	var selected := int(state.options[0].id)
	var price := int(state.options[0].hp_cost)
	var view = game.hud.page.special.get_child(0)
	view._select(0)
	check(game.profile.data.run.inventory == before_inventory and view.parts[0].choose.visible, "Preview reveals confirmation without purchasing the candidate")
	view.parts[0].lock.pressed.emit()
	game.profile.data.run.counters["SelectRefreshTime"] = 1
	game._action("refresh_sacrifice", key, 0)
	state = game._room_choices().open_sacrifice(key)
	check(int(state.options[0].id) == selected and int(state.options[0].hp_cost) == price and bool(state.options[0].locked), "Refresh preserves the locked candidate and displayed maximum HP price")
	check(int(game.profile.data.run.counters.SelectRefreshTime) == 0, "Refresh consumes its available charge once")
	await _capture("selection-fixed")
	view = game.hud.page.special.get_child(0)
	view._select(0)
	await _capture("selection-fixed-selected")
	var options: Array = _candidate_identity(state.options)
	game.hud.close_page()
	_verify_leave_warning("Pending purification choice")
	await _capture_altar_map("consumed", true)
	var random_step := int(game.profile.data.run.random_step)
	game._request_sacrificial_altar({"marker_id": marker})
	check(not game.hud.modal_open and int(game.profile.data.run.random_step) == random_step, "Repeated consumed-marker messages neither reopen nor reroll the altar")
	check(game._save(true), "Pending purification selection saves")
	await _resume()
	altar = _altar()
	check(altar.state.used and _parts_hidden(altar) and not game.world.interactions.interact(marker).success, "Full game restore keeps the source marker consumed")
	check(_candidate_identity(game._room_choices().open_sacrifice(key).options) == options, "Full game restore retains exact candidates, locked state, and HP prices")
	game._process(0.016)
	check(game.hud.primary.visible and game.hud.primary.text == "继续净化", "A restored pending selection exposes a usable continuation prompt")
	game._interact()
	check(game.hud.modal_open, "Continuation reopens the saved purification page")
	var combat: DungeonCombat = game.world.player.combat
	combat.health = combat.max_health * 0.25
	var previous_max := combat.max_health
	var previous_health := combat.health
	view = game.hud.page.special.get_child(0)
	view._select(0)
	view.parts[0].choose.pressed.emit()
	check(int(game.profile.data.run.inventory.get(str(selected), 0)) == int(before_inventory.get(str(selected), 0)) + 1, "Confirm grants the selected source reward exactly once")
	check(is_equal_approx(combat.max_health, previous_max - price), "Confirm applies its displayed HP price to live maximum health")
	check(is_equal_approx(combat.health, minf(previous_health, combat.max_health)), "Confirm preserves current HP below the reduced cap")
	check(game.hud.modal_open and not game._room_choices().open_sacrifice(key).closed, "One purchase leaves other purification candidates available")
	var maximum_after := combat.max_health
	game._action("choose_sacrifice", selected, key)
	check(is_equal_approx(combat.max_health, maximum_after) and int(game.profile.data.run.inventory.get(str(selected), 0)) == int(before_inventory.get(str(selected), 0)) + 1, "Repeated purchase cannot charge health or grant the same candidate twice")
	game._apply_growth()
	check(is_equal_approx(combat.max_health, maximum_after), "Maximum HP payment survives combat attribute recalculation")
	game._action("finish_sacrifice", key, 0)
	check(not game.hud.modal_open and not game.profile.data.run.counters.has("pending-room-choice:" + game._room_key), "Finishing clears the pending purification page")
	check(int(game.profile.data.run.counters.get("SelectLootRemainCount_Reward", 0)) == 0 and int(game.profile.data.run.counters.get("SacrificialAltarRefreshCount", 0)) == 1, "Finishing commits the purchase count and consumes one pending opportunity")
	check(game._save(true), "Finished purification state saves")
	await _resume()
	altar = _altar()
	check(altar.state.used and _parts_hidden(altar) and game._room_choices().open_sacrifice(key).closed, "Finished purification and consumed appearance survive a full reload")
	check(is_equal_approx(game.world.player.combat.max_health, maximum_after), "Paid maximum HP survives a full reload")
	check(not game._resume_room_choice() and not game.world.interactions.interact(marker).success, "A finished altar cannot restart from the prompt or marker")
	game._action("finish_sacrifice", key, 0)
	check(int(game.profile.data.run.counters.get("SelectLootRemainCount_Reward", 0)) == 0, "Repeated finish cannot subtract another pending opportunity")
	await _fixture()
	_complete_boss(threshold)
	altar = _altar()
	check(not altar.state.enabled and not altar.visual.is_visible_in_tree(), "Finishing exactly at the native threshold does not reveal the altar")
	check(not game.world.interactions.interact(str(altar.id)).success, "Threshold failure cannot create a purification opportunity")
	check(game._save(true), "Failed fast-clear decision saves")
	await _resume()
	altar = _altar()
	check(not altar.state.enabled and not altar.visual.is_visible_in_tree(), "A failed fast-clear decision remains hidden after full reload")
	_finish()

func _finish() -> void:
	var report := {"checks": checks, "passed": failures.is_empty(), "failures": failures, "captures": captures, "layouts": layouts, "loading_observations": loading_observations, "method": "Real Godot source boss map, world marker, UI commands and full save reload; wave completion is accelerated and does not measure boss combat or observe APK execution."}
	var file := FileAccess.open("res://reports/purification-altar-flow-test.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	var summary := report.duplicate()
	summary.erase("layouts")
	print("PURIFICATION_ALTAR_FLOW_TEST ", JSON.stringify(summary))
	if is_instance_valid(game): game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
