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
		"talents": return game.hud.page.guild_view
		_: return game.hud.page.inventory_view

func snapshot(page: String, mode: String, dimensions: Vector2i, character_id := 0) -> void:
	canvas.size = dimensions
	game.menus.open(page, character_id)
	game.hud._layout()
	await settle()
	var host = game.hud.page
	var view = view_for(page)
	check(is_instance_valid(view) and host.special == null, "Dedicated APK page opens: %s/%s" % [mode, page])
	check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(host.get_global_rect()), "Host fits %s/%s %s" % [mode, page, dimensions])
	check(host.get_global_rect().encloses(view.get_global_rect()), "Page fits host %s/%s %s" % [mode, page, dimensions])
	check(bool(host.page_context.get("in_run", false)) == (mode == "run"), "Actual scene determines the role-page mode")
	if page != "talents":
		var expected_labels: Array = host.page_context.role_navigation.map(func(entry): return str(entry.label))
		check(view.navigation.map(func(button): return button.text) == expected_labels, "Visible navigation matches APK mode %s/%s" % [mode, page])
	else:
		view.detail_scroll.ensure_control_visible(view.upgrade_button)
		await settle()
		var button_size: Vector2 = view.upgrade_button.size
		check(absf(button_size.y - maxf(44.0, button_size.x * 75.0 / 250.0)) <= 1.0, "Guild action preserves the original oval aspect ratio %s" % dimensions)
		check(button_size.y >= 44 and button_size.x >= 44, "Guild action retains a usable touch target %s" % dimensions)
		check(view.detail_scroll.get_global_rect().grow(1).encloses(view.upgrade_button.get_global_rect()), "Guild action can scroll fully into its detail viewport %s" % dimensions)
	if render_check:
		var deadline := Time.get_ticks_msec() + 2000
		while host.modulate.a < 0.999 and Time.get_ticks_msec() < deadline: await process_frame
		check(host.modulate.a >= 0.999, "Page finishes opening before capture")
		await RenderingServer.frame_post_draw
		var frame = canvas.get_texture().get_image()
		check(not frame.is_empty(), "Rendered image exists for " + page)
		frame.save_png("res://reports/role-%s-%s-%dx%d.png" % [mode, page, dimensions.x, dimensions.y])

func verify_forge_selector() -> void:
	game.hud.close_page()
	game.world.world_message.emit("camp_page", {"page": "weapons"})
	check(game.menus.current_page == "weapons" and game.hud.page.weapon_view.selector_open, "Forge interaction opens the weapon selector directly")
	check(game.hud.page.weapon_view.selector.is_visible_in_tree() and not game.hud.page.weapon_view.navigation[0].is_visible_in_tree(), "Forge entry shows the selection view instead of the role homepage")
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390), Vector2i(2460, 1080)]:
		await snapshot("weapons", "forge", dimensions, 1)
		var view = game.hud.page.weapon_view
		check(view._selector_strip is VBoxContainer and view._selector_scroll.visible, "Forge uses the reference vertical weapon roster")
		var first_frame: Control = view.weapon_buttons[101].get_node("Selected")
		var first_tile: Control = view.weapon_buttons[101].get_node("SlotFrame")
		var inner := Rect2(first_frame.position + first_frame.size * Vector2(8.0 / 68.0, 9.0 / 68.0), first_frame.size * Vector2(52.0 / 68.0, 51.0 / 68.0))
		check(inner.is_equal_approx(first_tile.get_rect()), "Forge highlight's bright inner edge surrounds the whole weapon tile")
		check(view._selector_scroll.get_global_rect().grow(1).encloses(first_frame.get_global_rect()), "First forge highlight and glow stay inside the scroll viewport")
		check(view._paper_parts.all(func(part): return not part.visible), "Forge detail does not show the old paper panel")
		check("等级5" in view.selector_effect.text, "Forge shows the complete weapon level progression")
		check(view._selector_resources.get_child_count() == 2, "Forge header shows gold and weapon ore")
		for control in [view._selector_scroll, view.selector_preview, view._selector_inside, view.selector_actions]:
			check(view.get_global_rect().grow(1).encloses(control.get_global_rect()), "Forge section fits " + str(dimensions))
		for button in view.action_buttons:
			check(button.get_global_rect().size.y >= 43.9, "Forge actions retain a 44px touch target " + str(dimensions))
		var last: Control = view._selector_strip.get_child(-1)
		var last_id: int = int(view.weapon_buttons.keys().back())
		view.select_weapon(last_id)
		await settle()
		check(view._selector_scroll.get_global_rect().grow(1).encloses(last.get_global_rect()), "Final forge weapon is reachable by vertical scrolling")
		check(view._selector_scroll.get_global_rect().grow(1).encloses(last.get_node("Selected").get_global_rect()), "Final forge highlight and glow remain visible")
		view.select_weapon(101)
		await settle()
		view._selector_scroll.scroll_vertical = 0
	game.hud.page.weapon_view.select_weapon(102)
	for button in game.hud.page.weapon_view.action_buttons:
		if button.text == "装备":
			button.pressed.emit()
			break
	check(game.selected_weapon == 102 and game.hud.page.weapon_view.selector_open, "Forge equipment refresh stays in the selector")
	game.hud.page.weapon_view.select_weapon(101)
	var quote: Dictionary = game.systems.weapon_upgrade_status(101)
	for key in quote.price: game.systems.grant_material(int(key), maxi(0, int(quote.price[key]) - game.systems.material(int(key))))
	game.menus.open("weapons", 1)
	var rank: int = game.systems.stat("weapon:101")
	for button in game.hud.page.weapon_view.action_buttons:
		if button.text == "升级":
			check(not button.disabled, "Forge upgrade is available when its actual costs are covered")
			button.pressed.emit()
			break
	check(game.systems.stat("weapon:101") == rank + 1 and game.hud.page.weapon_view.selector_open, "Forge upgrade applies and retains the selector")
	check(game.hud.page.weapon_view.selected_weapon == 101, "Forge upgrade retains the selected weapon")
	game._action("equip_weapon", 101, 1)
	game.hud.page.weapon_view.selector.get_node("RoleBackButton").pressed.emit()
	check(not game.hud.modal_open and game.world._camp_camera, "Forge selector back returns directly to camp")
	game.world.world_message.emit("camp_page", {"page": "weapons"})
	var cancel = InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	game.hud.page.weapon_view._unhandled_input(cancel)
	check(not game.hud.modal_open, "Forge selector cancel returns directly to camp")
	game.menus.open("weapons", 1)
	check(not game.hud.page.weapon_view.selector_open, "Regular role weapon entry keeps its existing detail view")
	game.hud.page.weapon_view.open_selector()
	game.hud.page.weapon_view.selector.get_node("RoleBackButton").pressed.emit()
	check(game.hud.modal_open and not game.hud.page.weapon_view.selector_open, "Nested selector back retains the role weapon detail view")
	game.hud.close_page()

func verify_inactive_character_weapon() -> void:
	game.profile.data.character_levels["2"] = 3
	game.systems.set_record("weapon:201", 1)
	game.systems.set_record("weapon:202", 1)
	game.systems.grant_material(103, 100)
	game.menus.open("weapons", 2)
	check(game.hud.page.page_context.character_id == 2 and game.hud.page.weapon_view.selected_weapon == 201, "Other character weapon page starts from its own equipment")
	game.hud.page.weapon_view.select_weapon(202)
	game.hud.page.weapon_view.open_selector()
	var equip_buttons: Array = game.hud.page.weapon_view.action_buttons.filter(func(button): return button.text == "装备")
	check(equip_buttons.size() == 1 and not equip_buttons[0].disabled, "Owned inactive character can equip a compatible crafted weapon")
	if not equip_buttons.is_empty(): equip_buttons[0].pressed.emit()
	check(game.selected_character == 1 and game.selected_weapon == 102, "Equipping the browsed character preserves the active actor and weapon")
	check(game.systems.equipped_weapon(2) == 202 and int(game.save_store.load_profile().selected_weapons["2"]) == 202, "Inactive character equipment is applied and immediately persisted")
	check(game.menus.current_id == 2 and game.hud.page.page_context.character_id == 2 and game.hud.page.weapon_view.selected_weapon == 202, "Equipment refresh retains the viewed character and selected weapon")
	var quote: Dictionary = game.systems.weapon_upgrade_status(202)
	var ore_before: int = game.systems.material(103)
	var upgrade_buttons: Array = game.hud.page.weapon_view.action_buttons.filter(func(button): return button.text == "升级")
	check(upgrade_buttons.size() == 1 and not upgrade_buttons[0].disabled, "Source level-three character gate enables the viewed weapon upgrade")
	if not upgrade_buttons.is_empty(): upgrade_buttons[0].pressed.emit()
	check(game.systems.stat("weapon:202") == 2 and game.systems.material(103) == ore_before - int(quote.price["103"]), "Other character weapon upgrade consumes the exact source cost once")
	check(game.menus.current_id == 2 and game.hud.page.page_context.character_id == 2 and game.hud.page.weapon_view.selected_weapon == 202, "Upgrade refresh retains the viewed character and weapon")
	check(int(game.save_store.load_profile().stats["weapon:202"]) == 2, "Viewed weapon upgrade is saved immediately")
	game.hud.page.weapon_view.set_selector_open(false)
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390)]: await snapshot("weapons", "camp-other", dimensions, 2)
	game.menus.open("characters", 1)
	game.hud.page.character_view.picker_button.pressed.emit()
	game.hud.page.character_view.selections[1].pressed.emit()
	check(game.selected_character == 2 and game.selected_weapon == 202, "Real roster selection restores the browsed character's remembered weapon")
	var saved: Dictionary = game.save_store.load_profile()
	check(int(saved.selected_character) == 2 and int(saved.selected_weapon) == 202, "Roster selection saves both actor and remembered equipment")
	game.hud.page.character_view.picker_button.pressed.emit()
	game.hud.page.character_view.selections[0].pressed.emit()
	check(game.selected_character == 1 and game.selected_weapon == 102, "Switching back preserves the original character equipment")
	game.systems.set_record("weapon:302", 1)
	game.menus.open("weapons", 3)
	game.hud.page.weapon_view.select_weapon(302)
	game.hud.page.weapon_view.open_selector()
	equip_buttons = game.hud.page.weapon_view.action_buttons.filter(func(button): return button.text == "装备")
	check(equip_buttons.size() == 1 and equip_buttons[0].disabled, "A crafted weapon cannot be equipped on an unowned character")
	var recruitment: Dictionary = game.systems.character_recruit_status(3)
	for key in recruitment.price: game.systems.grant_material(int(key), maxi(0, int(recruitment.price[key]) - game.systems.material(int(key))))
	game.menus.open("characters", 1)
	game.hud.page.character_view.picker_button.pressed.emit()
	game.hud.page.character_view.selections[2].pressed.emit()
	check(game.selected_character == 1 and game.hud.page.page_context.selected_character == 3, "Browsing an unowned character retains the active actor")
	game.hud.page.character_view.action_bar.get_child(0).pressed.emit()
	check(is_instance_valid(game.hud.page.character_view._recruit_overlay) and game.systems.rank(game.profile.data.character_levels, 3) == 0, "Recruitment opens a confirmation before spending materials")
	if is_instance_valid(game.hud.page.character_view._recruit_overlay): game.hud.page.character_view._recruit_overlay.confirm_button.pressed.emit()
	check(game.systems.rank(game.profile.data.character_levels, 3) == 1 and int(game.save_store.load_profile().character_levels["3"]) == 1, "Browsed character recruitment is applied and saved")
	check(game.hud.page.page_context.selected_character == 3 and game.selected_character == 1, "Recruitment refresh retains the browsed character without changing the active actor")
	var growth: Dictionary = game.systems.character_upgrade_status(3)
	for key in growth.price: game.systems.grant_material(int(key), maxi(0, int(growth.price[key]) - game.systems.material(int(key))))
	game.menus.open("characters")
	game.hud.page.character_view.action_bar.get_child(0).pressed.emit()
	check(is_instance_valid(game.hud.page.character_view._upgrade_overlay), "Newly recruited inactive character opens its upgrade confirmation")
	if is_instance_valid(game.hud.page.character_view._upgrade_overlay): game.hud.page.character_view._upgrade_overlay.confirm_button.pressed.emit()
	check(game.systems.rank(game.profile.data.character_levels, 3) == 2 and int(game.save_store.load_profile().character_levels["3"]) == 2, "Newly recruited character upgrade changes and saves the browsed target")
	check(game.hud.page.page_context.selected_character == 3 and game.selected_character == 1, "Character upgrade refresh preserves the browsed target and active actor")
	game.menus.open("weapons", 1)

func verify_guild_upgrade() -> void:
	game.menus.open("talents")
	check(game.hud.page.guild_view != null and game.hud.page.special == null, "Real camp opens the dedicated guild page")
	var guild = game.hud.page.guild_view
	guild.select_talent(102)
	check(guild.upgrade_button.disabled, "Guild child node initially respects its source prerequisite")
	guild.select_talent(101)
	var quote: Dictionary = game.systems.global_talent_status(101)
	for key in quote.price: game.systems.grant_material(int(key), maxi(0, int(quote.price[key]) - game.systems.material(int(key))))
	game.menus.open("talents")
	guild = game.hud.page.guild_view
	check(not guild.upgrade_button.disabled, "Funded guild parent has an enabled upgrade action")
	guild.upgrade_button.pressed.emit()
	check(game.systems.rank(game.profile.data.talents, 101) == 1 and int(game.save_store.load_profile().talents["101"]) == 1, "Guild upgrade applies and saves the selected parent talent")
	guild = game.hud.page.guild_view
	check(guild.selected_category == 1 and guild.selected_talent == 101, "Guild transaction preserves category and selected node")
	guild.select_talent(102)
	quote = game.systems.global_talent_status(102)
	for key in quote.price: game.systems.grant_material(int(key), maxi(0, int(quote.price[key]) - game.systems.material(int(key))))
	game.menus.open("talents")
	guild = game.hud.page.guild_view
	check(guild.selected_talent == 102 and not guild.upgrade_button.disabled, "Learning the parent enables the selected child after refresh")
	guild.upgrade_button.pressed.emit()
	check(game.systems.rank(game.profile.data.talents, 102) == 1 and int(game.save_store.load_profile().talents["102"]) == 1, "Guild child upgrade is applied and saved")
	game.hud.page.guild_view.select_category(3)
	check(game.hud.page.guild_view.node_buttons.size() == 19 and game.hud.page.guild_view.selected_talent == 301, "Actual guild page can navigate to its complete third source branch")
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390), Vector2i(2460, 1080)]: await snapshot("talents", "camp", dimensions)

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
	await verify_forge_selector()
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
	await verify_inactive_character_weapon()
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
	await verify_guild_upgrade()
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390), Vector2i(2460, 1080)]:
		for page in ["characters", "weapons", "storage"]: await snapshot(page, "camp", dimensions)
	game.hud.page.inventory_view.back_requested.emit()
	check(not game.hud.modal_open and not game.world.paused and game.world._camp_camera, "Warehouse back closes the overlay and restores the actual camp")
	game._primary()
	var regions: Array = game.campaign.region_choices()
	check(not regions.is_empty(), "A real adventure has an entrance choice")
	if not regions.is_empty(): game._select_region(int(regions[0].node_id))
	deadline = Time.get_ticks_msec() + 60000
	while game._transitioning and Time.get_ticks_msec() < deadline:
		game.world._background = false
		await process_frame
	var entered_level: bool = not game._transitioning and not game.world._camp_camera and game.profile.data.run.active
	check(entered_level, "Transition reaches an actual level")
	if not entered_level:
		await finish()
		return
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
	await finish()

func finish() -> void:
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
