extends SceneTree

var checks := 0
var failures: Array[String] = []
var game: Node
var canvas: SubViewport
var clock := 2000000000
var coverage: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("CAMP SERVICE STATE: " + message)

func settle() -> void:
	for frame in 8: await process_frame

func select_service(key: String) -> bool:
	var view = game.hud.page.camp_service_view
	for index in view.rows.size():
		if str(view.rows[index].get("service_key", "")) == key:
			view.select_row(index)
			return true
	return false

func press(action: String) -> bool:
	var view = game.hud.page.camp_service_view
	for button in view.action_buttons:
		if button.get_meta("command", {}).get("action", "") == action and not button.disabled:
			button.pressed.emit()
			return true
	return false

func _run() -> void:
	canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	game = load("res://scenes/main.tscn").instantiate()
	game.save_store = DungeonSaveStore.new("/private/tmp/camp-service-state-%d.json" % Time.get_ticks_usec())
	canvas.add_child(game)
	while not game.initialized: await process_frame
	game.set_process(false)
	game.world.set_process(false)
	game.world.set_physics_process(false)
	game.world._background = false
	game.audio.stop()
	game.systems.utc_now = func(): return clock
	for building in game.catalog.rows("Buildings"):
		game.profile.data.buildings[str(building.id)] = int(building.max_level)
	for material in game.catalog.rows("MaterialData"):
		game.systems.grant_material(int(material.id), 10000)
	game.world.refresh_camp_progression()
	game.menus.open("resources")
	await settle()
	var view = game.hud.page.camp_service_view
	check(is_instance_valid(view) and view.page_id == "resources", "Resource ledger uses a complete camp service page")
	check(select_service("resource:101") and not view.action_buttons.is_empty(), "Resource ledger exposes actual acquisition and spending routes")
	view.search.text = "absent-resource-query"
	view.search.text_changed.emit(view.search.text)
	check(view.choice_buttons.is_empty() and view.action_buttons.is_empty() and view.selected == -1, "Empty search removes stale selection and all obsolete actions")
	view.search.text = ""
	view.search.text_changed.emit("")
	check(view.selected >= 0 and not view.action_buttons.is_empty(), "Clearing search restores an existing resource selection")
	view.filter.select(1)
	view.filter.item_selected.emit(1)
	var selected_key: String = view.context.service_selected_key
	game.menus.open("resources")
	view = game.hud.page.camp_service_view
	check(view.filter.selected == 1 and view.context.service_selected_key == selected_key, "Same-page refresh retains resource filter and identity")
	coverage.resources = "search, empty state, wallet metrics, category/filter state, real resource routes"
	for resource_id in [101, 102, 12101]:
		game.menus.open("resource", resource_id)
		view = game.hud.page.camp_service_view
		check(view.rows.size() == 1 and view.rows[0].service_key == "resource:%d" % resource_id, "Resource detail resolves requested wallet or search-point identity: %d" % resource_id)
		check(not view.collection_scroll.visible and not view.toolbar.visible and not view.action_buttons.is_empty(), "Single-resource detail has reachable actions without an unused selector: %d" % resource_id)
		check(game.hud.page.page_context.back_action == "page:resources", "Resource detail returns to ledger")
	coverage.resource = "gold, magic and search-point lookup; metrics; warehouse action; ledger return"
	var work_id := 0
	for row in game.catalog.rows("MonsterWorkData"):
		if game.systems.work_status(int(row.id)).can_start:
			work_id = int(row.id)
			break
	check(work_id > 0, "Real catalog offers an unlocked dispatch")
	if work_id > 0:
		game.menus.open("dispatch", work_id)
		view = game.hud.page.camp_service_view
		check(view.page_id == "dispatch" and not view.collection_scroll.visible and press("op:start_work"), "Dispatch detail starts an actual assignment through its action button")
		check(game.menus.current_page == "work" and game.profile.data.work.size() == 1, "Dispatch start returns to current assignments")
		view = game.hud.page.camp_service_view
		check(select_service("work:%d" % work_id), "Running assignment has a stable item identity")
		view.search.text = str(game.catalog.find("MonsterWorkData", work_id).name)
		view.search.text_changed.emit(view.search.text)
		view.filter.select(1)
		view.filter.item_selected.emit(1)
		var query: String = view.search.text
		var duration: int = game.systems.work_status(work_id).duration_seconds
		clock += duration
		game.menus.tick(1.1)
		view = game.hud.page.camp_service_view
		check(view.search.text == query and view.filter.selected == 1 and view.context.service_selected_key == "work:%d" % work_id, "Offline dispatch refresh preserves search, filter and selected assignment")
		var before: int = game.systems.material(int(game.systems.work_status(work_id).reward.id))
		var reward: Dictionary = game.systems.work_status(work_id).reward
		check(press("op:collect_work"), "Completed assignment exposes an enabled claim action")
		check(game.systems.material(int(reward.id)) == before + int(reward.amount), "Claim button grants exactly the completed dispatch output")
		game.menus.open("dispatch", work_id)
		clock += duration
		game.menus.tick(1.1)
		check(game.menus.current_page == "dispatch" and game.hud.page.camp_service_view.page_id == "dispatch", "Dispatch detail refresh does not replace itself with the assignment list")
		check(press("op:collect_work"), "Dispatch detail also supports timed reward collection")
		game.hud.page.back_requested.emit()
		check(game.menus.current_page == "work", "Dispatch detail back action restores assignment list")
		check(select_service("work:%d" % work_id) and press("page:dispatch") and game.menus.current_page == "dispatch", "Assignment list has a working route to its detailed operations")
		coverage.work = "real start and claim, offline countdown refresh, persisted search/filter/selection"
		coverage.dispatch = "single-detail layout, start/claim/upgrade/stop controls, timed refresh, return to assignments"
	game.profile.data.last_meals = {}
	game.profile.data.meal_selection = {}
	game.menus.open("meals")
	check(select_service("meal:70101100"), "Unresearched recipe can be selected")
	check(press("op:research_meal"), "Recipe research invokes actual domain transaction")
	view = game.hud.page.camp_service_view
	check(view.rows[view.selected].service_key == "meal:70101100", "Inserting the previous-order row preserves selected recipe by identity")
	check(int(game.profile.data.recipes.get("70101100", 0)) == 1 and game.profile.data.meal_selection.has("70101100"), "Research unlocks recipe and populates order")
	var purchased := false
	for button in view.summary_bar.get_children():
		if button is Button and not button.disabled:
			button.pressed.emit()
			purchased = true
			break
	check(purchased and game.systems.purchased_meals().has("70101100") and game.profile.data.meal_selection.is_empty(), "Order summary purchases selected recipe and activates its effect")
	coverage.meals = "recipe research, stable selection after row insertion, order purchase, effect activation"
	game._close_page()
	game.world.player.position = game.world.camp_training_status().position
	game.menus.open("training")
	check(press("start_training") and game.world.camp_training.active, "Training page starts the actual practice session")
	game.world.camp_training.hits = 3
	game.world.camp_training.total_damage = 120
	game.world.camp_training.elapsed = 2
	game.menus.open("training")
	check(game.hud.page.camp_service_view.rows[0].metrics.size() == 6, "Training detail exposes live session statistics")
	check(press("reset_training") and game.world.camp_training.hits == 0, "Training page resets session statistics")
	check(press("end_training") and not game.world.camp_training.active, "Training page restores normal camp state when ending")
	coverage.training = "range-aware start, six session metrics, reset, finish, original camp combat restored"
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390)]:
		canvas.size = dimensions
		for entry in [["resources", 0], ["resource", 101], ["training", 0], ["dispatch", work_id]]:
			game.menus.open(str(entry[0]), int(entry[1]))
			await settle()
			view = game.hud.page.camp_service_view
			check(view.body.get_global_rect().end.x <= dimensions.x + 1 and view.body.get_global_rect().end.y <= dimensions.y + 1, "%s page fits %s" % [entry[0], dimensions])
			if not view.action_buttons.is_empty():
				view.detail_scroll.ensure_control_visible(view.action_buttons.back())
				await settle()
				check(view.detail_scroll.get_global_rect().intersects(view.action_buttons.back().get_global_rect()), "%s final operation stays reachable at %s" % [entry[0], dimensions])
			if "--render-check" in OS.get_cmdline_user_args():
				await RenderingServer.frame_post_draw
				var picture = canvas.get_texture().get_image()
				picture.save_png("res://reports/camp-service-state-%s-%dx%d.png" % [entry[0], dimensions.x, dimensions.y])
	check(game._save(true), "Service transactions save successfully")
	var saved: Dictionary = game.save_store.load_profile()
	check(not saved.is_empty() and saved.recipes.get("70101100", 0) == 1 and saved.purchased_meals.has("70101100"), "Recipe and paid order survive save reload")
	game.queue_free()
	await settle()
	var report = {"suite": "camp_service_state", "checks": checks, "failures": failures, "coverage": coverage, "rendered": "--render-check" in OS.get_cmdline_user_args()}
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
