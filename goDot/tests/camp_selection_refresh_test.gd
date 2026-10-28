extends SceneTree

var game: Node
var canvas: SubViewport
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("CAMP SELECTION: " + message)

func settle() -> void:
	for frame in 12: await process_frame

func press(buttons: Array, action: String, extra: int = -1) -> bool:
	for button in buttons:
		var data: Dictionary = button.get_meta("command", {})
		if str(data.get("action", "")) != action or button.disabled: continue
		if extra >= 0 and int(data.get("extra", -1)) != extra: continue
		button.pressed.emit()
		return true
	return false

func _run() -> void:
	create_timer(60).timeout.connect(func(): quit(2))
	DungeonLocale.set_locale("zh_CN", false)
	canvas = SubViewport.new()
	canvas.size = Vector2i(844, 390)
	root.add_child(canvas)
	game = load("res://scenes/main.tscn").instantiate()
	game.save_store = DungeonSaveStore.new("/private/tmp/camp-selection-%d.json" % Time.get_ticks_usec())
	canvas.add_child(game)
	while not game.initialized: await process_frame
	game.set_process(false)
	game.world.set_process(false)
	game.world.set_physics_process(false)
	game.audio.stop()
	for building in game.catalog.rows("Buildings"):
		game.profile.data.buildings[str(building.id)] = int(building.max_level)
	for material in game.catalog.rows("MaterialData"):
		game.systems.grant_material(int(material.id), 100000)
	game.systems.grant_material(60001, 2)
	game.profile.data.character_levels["2"] = 1
	game.systems.set_record("entitlement:awake_pack", 1)
	game.systems.set_record("token:50001", 3)
	game.systems.set_record("token:50011", 3)
	game.systems.set_record("token:slots", 3)
	game.menus.open("tokens", 50011)
	await settle()
	var view = game.hud.page.camp_service_view
	for index in view.rows.size():
		if int(view.rows[index].get("token_id", 0)) == 50001: view.select_row(index); break
	check(press(view.action_buttons, "op:equip_token"), "different token can be equipped after opening a specific token")
	await settle()
	view = game.hud.page.camp_service_view
	check(game.systems.relationship_tokens.equipped().has(50001), "token action changes the actual loadout")
	check(view.token_state.selected_token_id == 50001 and int(view.rows[view.selected].token_id) == 50001, "transaction refresh retains selected token rather than original entry id")
	for slot in [1, 2]:
		check(game.systems.unlock_amplifier_slot(50001, slot).success, "fixture unlocks target socket " + str(slot))
		game.menus.open("tokens", 50001)
		await settle()
		view = game.hud.page.camp_service_view
		check(press(view.socket_buttons, "page:amplifiers", slot), "direct socket entry is actionable " + str(slot))
		await settle()
		view = game.hud.page.camp_service_view
		check(game.menus.current_page == "amplifiers" and int(view.token_state.selected_slot_index) == slot, "direct entry selects its own socket " + str(slot))
		for index in view.rows.size():
			if int(view.rows[index].buttons[0].id) == 60001: view.select_row(index); break
		check(press(view.action_buttons, "op:equip_amplifier"), "amplifier command uses requested socket " + str(slot))
		await settle()
		check(int(game.systems.relationship_tokens.slots(50001)[slot]) == 60001, "amplifier is installed in requested socket " + str(slot))
		check(int(game.systems.relationship_tokens.slots(50001)[0]) == 0, "direct socket entry does not alter first socket")
	game.menus.open("characters", 1)
	game._action("page:awakening", 1, 0)
	await settle()
	var awakening = game.hud.page.awakening_view
	awakening.select_character(2)
	await settle()
	var node_id: int = awakening.selected_awakening
	awakening.collection_scroll.ensure_control_visible(awakening.node_buttons[int(awakening.node_rows.back().id)])
	awakening.detail_scroll.ensure_control_visible(awakening.unlock_button)
	await settle()
	var collection_position: int = awakening.collection_scroll.scroll_vertical
	check(collection_position > 0, "phone awakening fixture scrolls to later nodes")
	check(not awakening.unlock_button.disabled, "second character has a real unlockable node")
	awakening.unlock_button.pressed.emit()
	await settle()
	awakening = game.hud.page.awakening_view
	check(game.systems.stat("awake:unlocked:" + str(node_id)) == 1, "actual host unlocks second character node")
	check(awakening.selected_character == 2 and awakening.selected_awakening == node_id, "unlock refresh retains browsed character and node")
	check(awakening.collection_scroll.scroll_vertical == collection_position, "host refresh retains awakening collection position")
	awakening.detail_scroll.ensure_control_visible(awakening.toggle_button)
	await settle()
	var detail_position: int = awakening.detail_scroll.scroll_vertical
	awakening.toggle_button.pressed.emit()
	await settle()
	awakening = game.hud.page.awakening_view
	check(game.profile.data.active_awakenings.has(node_id), "actual host activates second character node")
	check(awakening.selected_character == 2 and awakening.selected_awakening == node_id, "activation refresh retains browsed character and node")
	check(awakening.detail_scroll.scroll_vertical == detail_position, "host refresh retains detail position")
	awakening.back_requested.emit()
	check(game.menus.current_page == "characters" and game.hud.page.character_view._character_id() == 1, "awakening returns to original character after browsing another character")
	game._save(true)
	var saved = game.save_store.load_profile()
	check(saved.get("char_token_amplifier_slots", {}).get("1", {}).get("50001", []) == [0, 60001, 60001], "requested socket assignments survive actual save reload")
	check(saved.get("active_awakenings", []).has(node_id), "browsed character awakening survives actual save reload")
	game.free()
	canvas.free()
	print("CAMP_SELECTION_REFRESH ", JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
