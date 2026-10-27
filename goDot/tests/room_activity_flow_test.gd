extends SceneTree

var game: Node
var canvas: SubViewport
var checks := 0
var failures: Array[String] = []
var captures: Array[String] = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr(message)

func _initialize() -> void:
	_run.call_deferred()

func _fixture(flow: String, scene := "", partner_ready := false) -> void:
	if is_instance_valid(game):
		game.queue_free()
		await process_frame
	game = load("res://scenes/main.tscn").instantiate()
	game.save_store = DungeonSaveStore.new("/private/tmp/city-room-activities-%d.json" % Time.get_ticks_usec())
	canvas.add_child(game)
	game.set_process(false)
	game.world.set_physics_process(false)
	game.world.presentation.audio_enabled = false
	game.world.auto_attack_enabled = false
	game.audio.stop()
	var rooms: Array = game.campaign.database.Nodes.filter(func(row): return str(row.Flow) == flow and (scene.is_empty() or str(row.SceneName) == scene))
	check(not rooms.is_empty(), "APK room fixture exists: " + flow + scene)
	if rooms.is_empty(): return
	var room: Dictionary = rooms[0]
	if partner_ready:
		game.profile.data.buildings["4"] = 3
		game.profile.data.partners["12003"] = 1
		game.profile.data.partners["13001"] = 1
	game.systems.begin_run(90317, game.selected_character, 100, 0)
	check(game.campaign.start_practice(int(room.Id), 90317).success, "Source room enters: " + str(room.Id))
	if partner_ready:
		var appearance = preload("res://scripts/domain/room_appearance.gd").new(game.systems, func(_maximum): return 0)
		appearance.node_increments("%d:%d:%d" % [90317, int(game.campaign.state.layer_index), int(room.Id)], room)
	game._load_room()
	await _wait()

func _wait() -> void:
	game.world.set_physics_process(false)
	game.world.set_process(true)
	var deadline := Time.get_ticks_msec() + 60000
	while game._transitioning and Time.get_ticks_msec() < deadline: await process_frame
	check(not game._transitioning, "Room finishes loading")
	game.set_process(false)
	game.world.set_process(false)
	game.world.set_physics_process(false)
	game.world.paused = false
	game.hud.close_page()

func _item(button: String) -> Dictionary:
	for item in game.world.interactions._items.values():
		if str(item.data.get("UIBtnName", "")) == button: return item
	return {}

func _stand_at(item: Dictionary) -> void:
	var volumes: Array = game.world.interactions._volumes(item, "Box_TiggerEnter")
	if volumes.is_empty():
		game.world.player.position = game.world.interactions._world_position(item.position)
	else:
		var volume: Dictionary = volumes[0]
		var point: Vector3 = game.world.interactions._matrix(volume.world_matrix) * game.world.interactions._vector(volume.properties.get("m_Center", {}))
		game.world.player.position = game.world.interactions._world_position(point) - Vector3.UP * 0.8
	game.world.camera.global_position = game.world.player.global_position + game.world._camera_offset
	game.world.camera.look_at(game.world.player.global_position)

func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless" or "--capture" not in OS.get_cmdline_user_args(): return
	for size in [Vector2i(1600, 900), Vector2i(844, 390)]:
		canvas.size = size
		await process_frame
		game.hud._layout()
		for frame in 4: await process_frame
		if label == "partner-combat":
			for button in game.hud.partner_skill_bar.buttons:
				if not button.visible: continue
				var bounds: Rect2 = button.get_global_rect()
				check(Rect2(Vector2.ZERO, Vector2(size)).encloses(bounds), "Partner control stays inside viewport: " + str(size))
				check(not game.hud.primary.visible or not bounds.intersects(game.hud.primary.get_global_rect()), "Partner control clears the interaction prompt: " + str(size))
		if label == "meals":
			var buy_buttons: Array = game.hud.page.detail.find_children("*", "Button", true, false).filter(func(button): return button.text == "点餐")
			check(buy_buttons.size() == 1 and game.hud.page.detail_scroll.get_global_rect().encloses(buy_buttons[0].get_global_rect()), "Meal purchase remains visible inside its scrolling panel: " + str(size))
		await RenderingServer.frame_post_draw
		var image := canvas.get_texture().get_image()
		check(not image.is_empty() and _has_visual_content(image), "Rendered activity has nonblank pixels: " + label)
		var path := "res://reports/room-activity-%s-%dx%d.png" % [label, size.x, size.y]
		image.save_png(path)
		captures.append(path)
	canvas.size = Vector2i(1600, 900)

func _has_visual_content(image: Image) -> bool:
	var colors: Dictionary = {}
	for y in range(0, image.get_height(), maxi(1, image.get_height() / 18)):
		for x in range(0, image.get_width(), maxi(1, image.get_width() / 32)):
			colors[image.get_pixel(x, y).to_rgba32()] = true
	return colors.size() > 32

func _run() -> void:
	create_timer(180).timeout.connect(func(): quit(2))
	canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	await _fixture("Rest", "LevelMap_1010301")
	var pool := _item(DungeonWorldInteractions.SPRING)
	check(not pool.is_empty(), "Real rest room exposes packaged spring marker")
	var combat: DungeonCombat = game.world.player.combat
	combat.health = combat.max_health * 0.1
	game.profile.data.run.health = combat.health
	var before := combat.health
	game._room_action()
	check(is_equal_approx(combat.health, before), "Opening rest menu does not grant health")
	game.hud.close_page()
	if not pool.is_empty():
		check(not game.world.interactions.can_interact_at(str(pool.id), Vector3(10000, 0, 10000)), "Spring prompt respects actual trigger bounds")
		_stand_at(pool)
		check(game.world.interactions.can_interact_at(str(pool.id), combat_position()), "Spring prompt appears inside source trigger")
		await _capture("spring")
		combat.set_external_attributes({"HealRate": 1000})
		var expected := float(int(combat.max_health * (300 + float(game.systems.attributes().get("SpringRecoverHpRatio", 0))) / 1000.0))
		check(game.world.interactions.interact(str(pool.id)).success, "Actual spring interaction reaches drink handler")
		check(is_equal_approx(combat.health, minf(combat.max_health, before + expected)), "Spring applies truncated source ratio without unrelated HealRate")
		check(pool.state.used and pool.visual.is_visible_in_tree(), "Drunk spring keeps water model and removes interaction")
		for part in pool.curse_parts:
			check(not part.node.visible, "Drunk spring hides only its source symbol and trigger")
		check(not game.world.interactions.interact(str(pool.id)).success, "Spring cannot be drunk twice")
		check(game.campaign.state.phase == "room", "Drinking never completes or advances rest room")
		game._save(true)
		game._load_room(true)
		await _wait()
		pool = _item(DungeonWorldInteractions.SPRING)
		check(pool.state.used and not game.world.interactions.interact(str(pool.id)).success, "Used spring persists through room save restoration")
	await _fixture("Rest", "LevelMap_1020301")
	pool = _item(DungeonWorldInteractions.SPRING)
	combat = game.world.player.combat
	combat.health = combat.max_health * 0.1
	game.profile.data.run.health = combat.health
	before = combat.health
	combat._anti_heal_time = 5.0
	if not pool.is_empty():
		game.world.interactions.interact(str(pool.id))
		check(is_equal_approx(combat.health, before) and pool.state.used, "Anti heal blocks recovery while consuming the spring opportunity")
	await _fixture("Curse", "LevelMap_1010901")
	var altar := _item(DungeonWorldInteractions.OLD_DAY_ALTAR)
	check(not altar.is_empty() and altar.state.enabled, "Old day room contains its active source altar")
	if not altar.is_empty():
		check(game.world.interactions.interact(str(altar.id)).success, "Old day altar routes through its source identity")
		var key: String = "old_day:" + game._room_key
		var pending: Array = game.profile.data.run.rewards.filter(func(reward): return str(reward.key) == key)
		check(pending.size() == 1 and altar.state.used, "Old day activation consumes source marker and queues one choice")
		await _capture("old-day")
		game.hud.close_page()
		game._interact()
		check(game.hud.modal_open and game.profile.data.run.rewards.size() == 1, "Closing and reopening preserves pending old day choices")
		if not pending.is_empty() and not pending[0].choices.is_empty():
			game._action("choose_loot", int(pending[0].choices[0]), key)
			check(game.campaign.state.phase == "reward" and game.world.room_stage == "open", "Successful old day choice opens required room exit")
	await _fixture("Battle", "LevelMap_1010101")
	var event := _item(DungeonWorldInteractions.ADVENTURE_EVENT)
	check(not event.is_empty(), "Ordinary combat scene contains source adventure event")
	if not event.is_empty():
		var stage: String = game.world.room_stage
		before = game.world.player.combat.max_health * 0.6
		game.world.player.combat.health = before
		game.world.player.combat.armor = 13
		game.world.interactions.interact(str(event.id))
		check(is_equal_approx(game.world.player.combat.health, before) and game.world.player.combat.armor == 13, "Opening an event preserves live HP and armor even before the next save frame")
		check(game.hud.modal_open and game.profile.data.run.events.size() == 1, "Ordinary-room event opens real event choices")
		await _capture("event")
		var encounter: Dictionary = game.profile.data.run.events[0]
		for iteration in 12:
			var view: Dictionary = game.systems.event_view(encounter)
			if view.get("finished", true): break
			var available: Array = view.get("choices", []).filter(func(choice): return choice.enabled)
			check(not available.is_empty(), "Live event keeps an available choice")
			if available.is_empty(): break
			var selected: Dictionary = available.back()
			game._action("event_choice", int(selected.id), {"key": encounter.key, "marker_id": str(event.id)})
		check(encounter.finished and event.state.used, "Finishing optional event consumes its own marker")
		check(game.campaign.state.phase == "room" and game.world.room_stage == stage, "Optional event does not resolve combat or change gates")
		var count: int = game.profile.data.run.events.size()
		game.world.interactions.interact(str(event.id))
		check(game.profile.data.run.events.size() == count, "Consumed optional event never generates a second encounter")
	await _fixture("Event", "LevelMap_1010801")
	event = _item(DungeonWorldInteractions.SPECIAL_EVENT)
	check(not event.is_empty(), "Special event room contains the packaged special marker")
	if not event.is_empty():
		game.world.interactions.interact(str(event.id))
		check(game.hud.modal_open and game.profile.data.run.events.size() == 1, "Special marker opens an encounter")
		if not game.profile.data.run.events.is_empty():
			var special_row: Dictionary = game.catalog.find("AdvantureEventData", int(game.profile.data.run.events[0].event_id))
			check(special_row.get("EventType", "") == "Spacial", "Special marker uses only APK special events")
		await _capture("special-event")
	await _fixture("Boss", "LevelMap_1019101")
	altar = _item(DungeonWorldInteractions.SACRIFICIAL_ALTAR)
	check(not altar.is_empty(), "Boss room contains source sacrificial altar")
	if not altar.is_empty():
		combat = game.world.player.combat
		game.profile.data.run.counters["rogue-event-buff:100200101"] = 1
		game._apply_growth()
		check(float(game.systems.attributes().get("HpAddRate", 0)) > 0, "Sacrifice fixture includes a source percentage health buff")
		combat.health = combat.max_health * 0.4
		game.profile.data.run.health = combat.health
		game.world.interactions.interact(str(altar.id))
		var key: String = "sacrifice:" + game._room_key + ":" + str(altar.id)
		var state: Dictionary = game._room_choices().open_sacrifice(key)
		check(game.hud.modal_open and altar.state.used and not state.options.is_empty(), "Sacrifice source activation consumes marker and opens priced choices")
		var locks: Array = game.hud.page.find_children("SacrificeLock", "Button", true, false)
		check(locks.size() == state.options.size(), "Each sacrifice candidate exposes a separate lock control")
		if not locks.is_empty():
			var locked_id := int(state.options[0].id)
			var locked_cost := int(state.options[0].hp_cost)
			locks[0].pressed.emit()
			check(game._room_choices().open_sacrifice(key).options[0].locked, "Sacrifice lock button reaches the persisted source state")
			game.profile.data.run.counters["SelectRefreshTime"] = 1
			game._action("refresh_sacrifice", key, 0)
			state = game._room_choices().open_sacrifice(key)
			check(int(state.options[0].id) == locked_id and int(state.options[0].hp_cost) == locked_cost and state.options[0].locked, "Live altar refresh preserves the locked item and its displayed price")
			check(int(game.profile.data.run.counters.SelectRefreshTime) == 0, "Non-first-room refresh consumes one source refresh charge")
		await _capture("sacrifice")
		var candidates: Array = state.options.duplicate(true)
		game._save(true)
		game._load_room(true)
		await _wait()
		game._process(0.016)
		check(game.hud.primary.visible and game.hud.primary.text == "继续献祭", "Pending sacrifice has a visible usable interaction prompt after reload")
		game._interact()
		state = game._room_choices().open_sacrifice(key)
		check(game.hud.modal_open and state.options == candidates, "Pending sacrifice restores identical candidates and prices after save reload")
		combat = game.world.player.combat
		if not state.options.is_empty():
			var option: Dictionary = state.options[0]
			var previous_max := combat.max_health
			before = combat.health
			game._action("choose_sacrifice", int(option.id), key)
			check(is_equal_approx(combat.max_health, previous_max - int(option.hp_cost)), "Sacrifice pays the displayed maximum HP cost in actual combat stats")
			check(is_equal_approx(combat.health, minf(before, combat.max_health)), "Sacrifice preserves current HP below the new cap")
			check(game.hud.modal_open and not game._room_choices().open_sacrifice(key).closed, "Sacrifice allows taking further candidates before finishing")
			var max_after := combat.max_health
			game._apply_growth()
			check(is_equal_approx(combat.max_health, max_after), "Sacrifice maximum HP payment survives attribute recalculation")
		game._action("finish_sacrifice", key, 0)
		check(not game.hud.modal_open and not game.profile.data.run.counters.has("pending-room-choice:" + game._room_key), "Finishing sacrifice clears its persisted pending page")
	await _fixture("Battle", "LevelMap_1010102", true)
	var selector := _item(DungeonWorldInteractions.PARTNER_SELECTOR)
	check(not selector.is_empty(), "Combat room contains source partner skill selector")
	if not selector.is_empty():
		game.world.interactions.interact(str(selector.id))
		var key: String = "partner-skill:" + game._room_key + ":" + str(selector.id)
		var state: Dictionary = game._room_choices().open_partner(key)
		check(game.hud.modal_open and selector.state.used and state.options.size() == 4, "Selector offers two unlocked skills and two ordinary rewards")
		check(game.hud.page._rows.any(func(row): return str(row.get("icon", "")).begins_with("res://assets/ui/partner_skills/") and ResourceLoader.exists(str(row.icon))), "Partner selector resolves recovered source skill icons")
		await _capture("partner")
		game.hud.close_page()
		game._interact()
		check(game.hud.modal_open and game._room_choices().open_partner(key).options == state.options, "Partner choices reopen without rerolling")
		var selected := -1
		for index in state.options.size():
			if str(state.options[index].mode) == "new":
				selected = index
				break
		if selected >= 0:
			combat = game.world.player.combat
			combat.health = combat.max_health * 0.6
			before = combat.health
			game._action("choose_partner_skill", selected, {"key": key, "slot": 0})
			check(game._room_choices().partner_slots().size() == 1 and not game.hud.modal_open, "Partner choice equips a live run skill and closes the selector")
			check(is_equal_approx(combat.health, before), "Choosing a partner does not restore stale saved HP")
			check(not game._room_choices().extra_buff_ids().is_empty(), "Equipped partner contributes its source passive buffs")
			check(game.campaign.state.phase == "room", "Partner selection preserves ongoing battle phase")
			game.world.advance_partner_skills(3.0)
			game.profile.data.run.counters["MonsterPartnerSp"] = 75.0
			var skill_state: Dictionary = game.world.partner_skill_state()
			check(skill_state.slots.size() == 1 and skill_state.slots[0].ready, "Selected partner exposes a charged active skill")
			game._skill(5, true)
			check(combat.current_action == str(skill_state.slots[0].action), "Partner combat input starts the original source action")
			check(is_equal_approx(float(game.profile.data.run.counters.MonsterPartnerSp), 75.0 - float(skill_state.slots[0].cost)), "Partner action spends the shared source energy cost")
			check(not game.world.use_skill(5).success, "Partner cooldown rejects an immediate repeated cast")
			game.hud.update_partner_skills(game.world.partner_skill_state())
			check(game.hud.partner_skill_bar.visible and game.hud.partner_skill_bar.buttons[0].art != null, "Equipped skill has an actual source icon in the combat HUD")
			await _capture("partner-combat")
			combat.drain_events()
			game.profile.data.run.counters["MonsterPartnerSp"] = 0.0
			check(combat.add_buff("95300122"), "Dragon source charge buff applies to live player combat")
			for combat_event in combat.drain_events(): game.world._consume(game.world.player, combat_event)
			check(is_equal_approx(float(game.world.partner_skill_state().sp), 25.0), "Source partner charge event reaches shared energy in the live world")
	await _fixture("Entrance", "LevelMap_1010001")
	var meal_shop := _item(DungeonWorldInteractions.MEAL_SHOP)
	check(not meal_shop.is_empty(), "Entrance contains the packaged reusable meal shop")
	if not meal_shop.is_empty():
		game.profile.data.buildings["7"] = 3
		var meal: Dictionary = game.catalog.rows("CatMealData")[0]
		var meal_id := DungeonCatalog.row_id(meal)
		game.profile.data.recipes[str(meal_id)] = 1
		var price: Dictionary = game.systems._meal_price(meal, 1)
		for resource in price: game.profile.data.materials[str(resource)] = 10000
		var gold: int = game.systems.material(101)
		game.world.interactions.interact(str(meal_shop.id))
		check(game.hud.modal_open and not meal_shop.state.used, "In-run source meal shop opens without consuming its marker")
		game._action("room_meal_select", meal_id, {"marker_id": str(meal_shop.id), "level": 1})
		check(game.systems.rank(game.profile.data.meal_selection, meal_id) == 1, "Meal page can select an unlocked researched dish")
		await _capture("meals")
		game._action("room_meal_buy", 0, {"marker_id": str(meal_shop.id)})
		check(game.systems.material(101) == gold - int(price.get("101", 0)), "Meal page charges actual permanent gold during adventure")
		check(game.systems.rank(game.systems.purchased_meals(), meal_id) == 1, "In-run meal purchase activates its existing gameplay effect")
		check(not meal_shop.state.used and game.campaign.state.phase == "room", "Meal shop stays reusable and leaves the room phase unchanged")
	_finish()

func combat_position() -> Vector3:
	return game.world.player.position

func _finish() -> void:
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "captures": captures, "scope": "Godot reconstruction integration; APK not executed"}
	FileAccess.open("res://reports/room-activity-flow-20261026.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("ROOM_ACTIVITY_FLOW ", JSON.stringify(report))
	if is_instance_valid(game): game.queue_free()
	canvas.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
