extends SceneTree

var checks := 0
var failures: Array[String] = []
var canvas: SubViewport
var game: Node
var render_check := false

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("ROLE PAGE FAILURE: " + message)

func settle() -> void:
	for step in 8: await process_frame

func view_for(page: String) -> Control:
	match page:
		"characters": return game.hud.page.character_view
		"weapons": return game.hud.page.weapon_view
		_: return game.hud.page.inventory_view

func snapshot(page: String, mode: String, dimensions: Vector2i) -> void:
	canvas.size = dimensions
	game.menus.open(page)
	game.hud._layout()
	await settle()
	var host = game.hud.page
	var view = view_for(page)
	check(is_instance_valid(view) and host.special == null, "Dedicated APK page opens: %s/%s" % [mode, page])
	check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(host.get_global_rect()), "Host fits %s/%s %s" % [mode, page, dimensions])
	check(host.get_global_rect().encloses(view.get_global_rect()), "Page fits host %s/%s %s" % [mode, page, dimensions])
	check(host.page_context.in_run == (mode == "run"), "Actual scene determines the role-page mode")
	var expected_labels: Array = host.page_context.role_navigation.map(func(entry): return str(entry.label))
	check(view.navigation.map(func(button): return button.text) == expected_labels, "Visible navigation matches APK mode %s/%s" % [mode, page])
	if render_check:
		var deadline := Time.get_ticks_msec() + 2000
		while host.modulate.a < 0.999 and Time.get_ticks_msec() < deadline: await process_frame
		check(host.modulate.a >= 0.999, "Page finishes opening before capture")
		await RenderingServer.frame_post_draw
		var frame = canvas.get_texture().get_image()
		check(not frame.is_empty(), "Rendered image exists for " + page)
		frame.save_png("res://reports/role-%s-%s-%dx%d.png" % [mode, page, dimensions.x, dimensions.y])

func _run() -> void:
	render_check = "--render-check" in OS.get_cmdline_user_args()
	canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	game = load("res://scenes/main.tscn").instantiate()
	game.save_store = DungeonSaveStore.new("/private/tmp/role-pages-%d.json" % Time.get_ticks_usec())
	canvas.add_child(game)
	var deadline := Time.get_ticks_msec() + 60000
	while not game.initialized and Time.get_ticks_msec() < deadline: await process_frame
	check(game.initialized, "Real game initializes with an isolated save")
	if not game.initialized:
		game.queue_free()
		await process_frame
		quit(1)
		return
	game.set_process(false)
	game.world.set_physics_process(false)
	game.world._background = false
	game.audio.stop()
	for id in range(1, 8): game.profile.data.buildings[str(id)] = 3
	game.world.refresh_camp_progression()
	game.profile.data.materials.merge({"101": 1378, "102": 77, "10101": 10, "10102": 5, "801": 3, "50011": 1}, true)
	game.systems.set_record("weapon:102", 1)
	game.menus.open("characters")
	check(game.hud.page.page_context.role_navigation.map(func(entry): return entry.page) == ["characters", "weapons", "storage"], "Camp has exactly the three source navigation entries")
	game.hud.page.character_view.navigation[1].pressed.emit()
	check(game.menus.current_page == "weapons" and game.hud.page.weapon_view != null, "Character navigation reaches the dedicated weapon page")
	game.hud.page.weapon_view.select_weapon(102)
	game.hud.page.weapon_view.open_selector()
	var equip_buttons: Array = game.hud.page.weapon_view.action_buttons.filter(func(button): return button.text == "装备")
	check(equip_buttons.size() == 1 and not equip_buttons[0].disabled, "Owned weapon exposes an enabled real equip button")
	if not equip_buttons.is_empty(): equip_buttons[0].pressed.emit()
	check(game.selected_weapon == 102 and int(game.profile.data.selected_weapon) == 102, "Weapon page command updates actual equipment")
	check(int(game.save_store.load_profile().selected_weapon) == 102, "Weapon page equipment is persisted immediately")
	check(int(game.hud.page.page_context.get("selected_weapon", 0)) == 102, "Equipment refresh preserves the viewed weapon")
	game.hud.page.weapon_view.set_selector_open(false)
	game.hud.page.weapon_view.navigation[2].pressed.emit()
	check(game.menus.current_page == "storage" and game.hud.page.inventory_view != null, "Weapon navigation reaches the dedicated warehouse")
	game.hud.page.page_context.selected_inventory_key = "material:801"
	game.menus.open("storage")
	var boxes_before: int = game.systems.material(801)
	game.hud.page.inventory_view.select_item("material:801")
	check(game.hud.page.inventory_view.action_bar.get_child_count() == 1, "Owned warehouse box exposes its real opening button")
	if game.hud.page.inventory_view.action_bar.get_child_count() > 0: game.hud.page.inventory_view.action_bar.get_child(0).pressed.emit()
	check(game.systems.material(801) == boxes_before - 1, "Warehouse box command spends exactly one owned box")
	check(game.menus.current_page == "storage" and game.hud.page.page_context.selected_inventory_key == "material:801", "Box refresh keeps the selected warehouse item")
	check(not game.hud.page._rows.any(func(row): return int(row.get("material_id", 0)) in [102, 50011]), "Real warehouse follows source material visibility")
	var quote: Dictionary = game.systems.character_upgrade_status(1)
	for key in quote.price: game.systems.grant_material(int(key), maxi(0, int(quote.price[key]) - game.systems.material(int(key))))
	var old_level: int = game.systems.rank(game.profile.data.character_levels, 1)
	game.menus.open("characters", 1)
	game.hud.page.character_view.action_bar.get_child(0).pressed.emit()
	check(game.systems.rank(game.profile.data.character_levels, 1) == old_level, "Opening upgrade quote leaves real level unchanged")
	check(is_instance_valid(game.hud.page.character_view._upgrade_overlay), "Upgrade opens its confirmation in the real menu")
	game.hud.page.character_view._upgrade_overlay.confirm_button.pressed.emit()
	check(game.systems.rank(game.profile.data.character_levels, 1) == old_level + 1, "Character upgrade reaches the real progression transaction")
	check(game.hud.page.character_view != null and int(game.hud.page.page_context.selected_character) == 1, "Upgrade returns to the selected character")
	game.systems.grant_material(502, 10)
	var fashion_currency_before: int = game.systems.material(502)
	game.hud.page.character_view.command.emit("op:unlock_character_fashion", 1002, 1)
	check(1002 in game.systems.character_fashion_owned() and game.systems.material(502) == fashion_currency_before - 10, "Character fashion command spends its source price and unlocks the selected fashion")
	game.hud.page.character_view.command.emit("op:equip_character_fashion", 1002, 1)
	check(int(game.hud.page.page_context.fashion_equipped["1"]) == 1002, "Fashion operation refreshes the actual role-page context")
	check(int(game.save_store.load_profile().fashion_equipped["1"]) == 1002, "Equipped fashion is saved immediately")
	game.hud.page.character_view.command.emit("op:equip_character_fashion", 1001, 1)
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390), Vector2i(2460, 1080)]:
		for page in ["characters", "weapons", "storage"]: await snapshot(page, "camp", dimensions)
	game.hud.page.inventory_view.back_requested.emit()
	check(not game.hud.modal_open and not game.world.paused and game.world._camp_camera, "Warehouse back closes the overlay and restores the actual camp")
	game._primary()
	var regions: Array = game.campaign.region_choices()
	check(not regions.is_empty(), "A real adventure has an entrance choice")
	if not regions.is_empty(): game._select_region(int(regions[0].node_id))
	deadline = Time.get_ticks_msec() + 60000
	while game._transitioning and Time.get_ticks_msec() < deadline: await process_frame
	check(not game._transitioning and not game.world._camp_camera and game.profile.data.run.active, "Transition reaches an actual level")
	game.world.set_physics_process(false)
	game.world._background = false
	game.profile.data.run.inventory = {"10000": 2, "10100": 1}
	game.menus.open("characters")
	check(game.hud.page.page_context.role_navigation.map(func(entry): return entry.page) == ["characters", "weapons", "inventory", "storage", "partners"], "Level navigation includes backpack and institute-gated monster partners")
	check(game.hud.page._rows.size() == 1 and not game.hud.page._rows[0].buttons.any(func(button): return str(button.action).begins_with("op:")), "Level character detail has no persistent growth operation")
	game.hud.page.character_view.navigation[2].pressed.emit()
	check(game.hud.page.inventory_view != null and game.hud.page._rows.size() == 1 and int(game.hud.page._rows[0].loot_id) == 10000, "Level backpack shows the owned visible relic instead of warehouse materials")
	game.hud.page.inventory_view.navigation[1].pressed.emit()
	check(game.hud.page._rows.all(func(row): return row.buttons.is_empty()), "Level weapon detail has no equip or craft commands")
	var equipment_before: int = game.selected_weapon
	game.hud.page.weapon_view.command.emit("equip_weapon", 101, 0)
	check(game.selected_weapon == equipment_before, "Execution layer rejects a forged camp equipment command in a level")
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390), Vector2i(2460, 1080)]:
		for page in ["characters", "weapons", "inventory", "storage"]: await snapshot(page, "run", dimensions)
	game.hud.page.inventory_view.back_requested.emit()
	check(not game.hud.modal_open and not game.world.paused and not game.world._camp_camera, "Level warehouse back resumes the current room")
	game.menus.open("weapons")
	game.hud.page.weapon_view.back_requested.emit()
	check(not game.hud.modal_open and not game.world._camp_camera, "Level weapon back returns to the room without opening a camp menu")
	game.queue_free()
	await process_frame
	canvas.queue_free()
	await process_frame
	var result = {"checks": checks, "failures": failures, "rendered": render_check}
	var file = FileAccess.open("res://reports/role-pages-integration-20261027.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("ROLE_PAGES_INTEGRATION ", JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
