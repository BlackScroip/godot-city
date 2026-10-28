extends SceneTree

var game: Node
var failures: Array[String] = []
var checks := 0
var actions: Array = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("PAGE BACK FLOW: ", message)

func back_button() -> Button:
	var page: DungeonMenuPage = game.hud.page
	if page._layout in ["tokens", "camp_service"]:
		return page.camp_service_view.heading.get_child(0)
	if page._layout == "awakening":
		return page.awakening_view.find_child("AwakeningBack", true, false)
	if page._layout == "shop":
		for child in page.shop_view.canvas.get_children():
			if child is Button and child.tooltip_text == "返回": return child
		return null
	return page.stack.get_child(0).get_child(0)

func press_back() -> void:
	var button := back_button()
	check(is_instance_valid(button) and button.visible, "Current page exposes its back button")
	if is_instance_valid(button): button.pressed.emit()

func press_escape() -> void:
	var event := InputEventAction.new()
	event.action = "pause_game"
	event.pressed = true
	game._unhandled_input(event)

func _run() -> void:
	create_timer(60).timeout.connect(func(): quit(2))
	DungeonLocale.set_locale("zh_CN", false)
	var canvas := SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	root.add_child(canvas)
	game = load("res://scenes/main.tscn").instantiate()
	game.save_store = DungeonSaveStore.new("/private/tmp/page-back-flow-%d.json" % Time.get_ticks_usec())
	canvas.add_child(game)
	while not game.initialized: await process_frame
	game.set_process(false)
	game.world.set_process(false)
	game.world.set_physics_process(false)
	game.world.player.set_physics_process(false)
	game.audio.stop()
	game.hud.action.connect(func(kind, id, extra): actions.append([kind, id, extra]))
	for row in game.catalog.rows("Buildings"): game.profile.data.buildings[str(row.id)] = int(row.max_level)
	game.world.refresh_camp_progression()
	game.world._background = false
	var token_marker: Dictionary = {}
	for item in game.world.interactions._items.values():
		if str(item.data.get("UIBtnName", "")) == "ATPanel_RelationshipToken_Title":
			token_marker = item
			break
	check(not token_marker.is_empty(), "Relationship token facility exists in the camp")
	if not token_marker.is_empty():
		game.world.player.position = token_marker.position
		for attempt in 2:
			game._action("camp_interact", str(token_marker.id), 0)
			check(game.hud.modal_open and game.menus.current_page == "tokens", "Facility opens relationship tokens: %d" % attempt)
			press_back()
			check(not game.hud.modal_open and not game.world.paused, "Facility exit returns to camp: %d" % attempt)
	var awakening_marker: Dictionary = {}
	for item in game.world.interactions._items.values():
		if str(item.data.get("UIBtnName", "")) == "EnvUnit_MonoData_BtnDisplayName_TalentTree":
			awakening_marker = item
			break
	check(not awakening_marker.is_empty(), "Awakening facility exists in the camp")
	if not awakening_marker.is_empty():
		game.world.player.position = awakening_marker.position
		game._action("camp_interact", str(awakening_marker.id), 0)
		check(game.hud.modal_open and game.menus.current_page == "awakening", "Facility opens awakening directly")
		press_back()
		check(not game.hud.modal_open and not game.world.paused, "Awakening facility exit returns to camp")

	for destination in ["camp", "resources", "resource", "training", "awakening", "meal_buffs", "tasks", "achievements", "talents", "partners", "work", "meals", "npcs", "decorations", "archive", "history", "extra_challenges", "tokens", "amplifiers", "mall"]:
		game.menus.open(destination, 101 if destination == "resource" else 0)
		check(game.hud.modal_open and game.menus.current_page == destination, "Top-level page opens: " + destination)
		game.world.paused = true
		press_back()
		check(not actions.is_empty() and actions.back() == ["close_page", 0, 0], "Back closes directly: " + destination)
		check(not game.hud.modal_open and not game.world.paused, "Back restores the playable world: " + destination)

	var token_id = int(game.catalog.rows("RelationshipTokenData")[0].id)
	var bounty_id = int(game.catalog.rows("ExtraChallengeData")[0].id)
	var work_id = int(game.catalog.rows("MonsterWorkData")[0].id)
	for entry in [["token_compose_preview", "amplifiers", 0], ["token_reroll_preview", "amplifiers", 0], ["extra_challenges_receive", "extra_challenges", 0], ["extra_challenge_delete", "extra_challenges", bounty_id], ["dispatch", "work", work_id], ["resource", "resources", 101]]:
		var child: String = entry[0]
		var parent: String = entry[1]
		game.menus.open(parent, token_id if parent == "amplifiers" else 0)
		game.menus.open(child, int(entry[2]))
		press_back()
		check(game.hud.modal_open and game.menus.current_page == parent, "Nested back returns to parent: " + child)
		check(actions.back() == ["page:" + parent, 0, 0], "Nested back emits parent action: " + child)
		if parent == "amplifiers": check(int(game.hud.page.page_context.get("token_selected", 0)) == token_id, "Nested token back preserves selection: " + child)
		game.menus.open(child, int(entry[2]))
		press_escape()
		check(game.hud.modal_open and game.menus.current_page == parent, "Nested keyboard back returns to parent: " + child)
		game._close_page()
	game.profile.data.character_levels["2"] = 1
	game.menus.open("characters", 2)
	game.menus.open("awakening", 2)
	game.menus.open("awakening", 2)
	press_back()
	check(game.hud.modal_open and game.menus.current_page == "characters" and int(game.hud.page.page_context.get("selected_character", 0)) == 2, "Awakening refresh retains the browsed character parent")
	game._close_page()

	game.menus.open("tokens", token_id)
	var service = game.hud.page.camp_service_view
	var close: Button = service.heading.get_child(service.heading.get_child_count() - 1)
	close.pressed.emit()
	check(not game.hud.modal_open and actions.back() == ["close_page", 0, 0], "Token close button returns to the world")
	game.menus.open("tokens", token_id)
	press_escape()
	check(not game.hud.modal_open and not game.world.paused, "Keyboard back closes the token page")
	game.menus.open("amplifiers", token_id)
	game.menus.open("token_compose_preview")
	press_escape()
	check(game.hud.modal_open and game.menus.current_page == "amplifiers", "Keyboard back from token preview returns to its parent")
	game._close_page()
	game.menus.open("amplifiers", token_id)
	game.menus.open("token_compose_preview")
	service = game.hud.page.camp_service_view
	close = service.heading.get_child(service.heading.get_child_count() - 1)
	close.pressed.emit()
	check(not game.hud.modal_open and actions.back() == ["close_page", 0, 0], "Token preview close button exits instead of opening its parent")

	var start: Dictionary = game.systems.start_work(work_id)
	check(start.success, "Dispatch confirmation fixture starts an actual order")
	if start.success:
		for use_keyboard in [false, true]:
			game.menus.open("work")
			game._action("confirm_stop_work", work_id, 0)
			check(game.hud.modal_open and game.hud.page.page_context.get("back_action") == "page:work", "Stop confirmation retains its parent")
			if use_keyboard: press_escape()
			else: press_back()
			check(game.hud.modal_open and game.menus.current_page == "work", "Stop confirmation back returns to dispatch")
			game._close_page()

	game.systems.begin_run(817, game.selected_character, 100)
	game.campaign.generate(817, 0)
	game.hud.set_adventure_mode(true)
	game.menus.open("partners")
	game.world.paused = true
	press_back()
	check(game.profile.data.run.active and not game.hud.modal_open and not game.world.paused, "In-run partner back returns to the current adventure")
	var region_id = int(game.campaign.region_map()[0].node_id)
	for use_keyboard in [false, true]:
		game._region_info(region_id)
		check(game.hud.page.page_context.get("back_action") == "route_world", "Region details retain the world route parent")
		if use_keyboard: press_escape()
		else: press_back()
		check(game.hud.modal_open and game.hud.page._layout == "route" and game.hud.page.page_context.get("map_scope") == "world", "Region details back returns to the world route")
	var choices: Array = game.campaign.region_choices()
	check(not choices.is_empty(), "World route provides a high-risk confirmation fixture")
	if not choices.is_empty():
		var risk_id = int(choices[0].node_id)
		for slot in game.campaign._world_modules[0].SlotList:
			if int(slot.Id) == risk_id:
				slot.IsHighRisk = true
				slot.ClearBossEnemyIdList = [999999]
				break
		for use_keyboard in [false, true]:
			game._select_region(risk_id)
			check(game.hud.page_title.text == "高危区域" and game.hud.page.page_context.get("back_action") == "route_world", "High-risk confirmation retains the world route parent")
			if use_keyboard: press_escape()
			else: press_back()
			check(game.hud.modal_open and game.hud.page._layout == "route" and game.hud.page.page_context.get("map_scope") == "world", "High-risk confirmation back returns to the world route")
	game._close_page()

	print("PAGE_BACK_FLOW ", JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	game.queue_free()
	await process_frame
	canvas.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
