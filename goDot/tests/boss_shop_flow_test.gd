extends SceneTree

var checks := 0
var failures: Array[String] = []
var game: Node

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("BOSS SHOP: " + message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(90).timeout.connect(func(): quit(2))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_store = DungeonSaveStore.new("/private/tmp/boss-shop-%d.json" % Time.get_ticks_usec())
	root.add_child(game)
	game.set_process(false)
	game.audio.stop()
	game.systems.begin_run(20261028, 1, 100, 0)
	game.systems.grant_material(102, 10000)
	game.systems.set_record("shop:level", 6)
	game.campaign.start_practice(1019101, 20261028)
	game._load_room()
	var deadline := Time.get_ticks_msec() + 60000
	while game._transitioning and Time.get_ticks_msec() < deadline:
		game.world.player_transfer.advance(0.1, false)
		await process_frame
	check(not game._transitioning, "Real Boss map loads")
	if game._transitioning: quit(1); return
	game.world.set_process(false)
	game.world.set_physics_process(false)
	game.world.presentation.audio_enabled = false
	game.world.auto_attack_enabled = false
	game.hud.close_page()
	game.world.paused = false
	var merchant: Dictionary = {}
	for item in game.world.interactions._items.values():
		if item.marker.Type == "EEUT_Special_Trader": merchant = item
	check(not merchant.is_empty(), "Boss map contains its source merchant")
	if merchant.is_empty(): quit(1); return
	check(str(merchant.marker.DataJson) == "{}" and str(merchant.data.NpcId) == "2000", "Empty source merchant data binds the APK component identity")
	var source_identities: Array = []
	for item in game.world.interactions._items.values():
		source_identities.append([str(item.id), str(item.marker.Type), JSON.parse_string(str(item.marker.DataJson)), str(item.binding.get("ConfigId", ""))])
	check(game.world.interactions._fingerprint == JSON.stringify([game.world.interactions.scene, source_identities]).sha256_text(), "NPC defaults preserve original environment checkpoint fingerprint")
	check(game.world.interactions.is_interaction_available(merchant), "Boss merchant exposes a real interaction")
	check(game.world.interactions.interact(str(merchant.id)).success and game.hud.page._layout == "dialogue", "World merchant interaction opens its source dialogue")
	game._action("talk_skip", 0, 0)
	check(not game.systems.npc_function_status(200101).success, "Source initial conversation still gates merchant stock")
	check(game.hud.page.page_context.choices.any(func(choice): return int(choice.id) == 200201), "Fresh player can reach initial conversation through actual merchant choices")
	game._action("op:execute_npc_function", 200201, 0)
	game._action("talk_skip", 0, 0)
	game._open_npc(2000)
	game._action("talk_skip", 0, 0)
	check(game.hud.page.page_context.choices.any(func(choice): return int(choice.id) == 200101), "Merchant dialogue offers source View Goods choice")
	game._action("op:execute_npc_function", 200101, 0)
	check(game.hud.page._layout == "room_shop" and game.hud.modal_open, "Source shop command opens merchant inside Boss room")
	check(game.profile.data.dialogue_state.is_empty(), "Shop replaces persisted dialogue")
	var phase: String = game.campaign.state.phase
	var stage: String = game.world.room_stage
	var key: String = game._room_key
	var shop: Dictionary = game.systems.get_room_shop(key)
	check(shop.offers.size() >= 6 and shop.supplies, "Boss merchant uses existing supplies and relic stock")
	var offer: Dictionary = shop.offers[3]
	var magic: int = game.systems.material(102)
	game._action("buy_room", int(offer.loot_id), 0)
	check(offer.sold and game.systems.material(102) == magic - int(offer.price), "Boss purchase pays and grants real stock")
	check(game.hud.page._layout == "room_shop" and game.hud.page._rows[3].sold, "Purchase redraw stays in Boss merchant")
	game._action("buy_room", int(offer.loot_id), 0)
	check(game.systems.material(102) == magic - int(offer.price), "Sold Boss stock cannot charge twice")
	game._action("invest_room_shop", int(game.systems.room_shop_status(key).deposit), 0)
	check(game.hud.page._layout == "room_shop" and game.hud.page.page_context.shop.remaining == 4, "Boss deposit redraws current progress")
	game._action("refresh_room_shop", 0, 0)
	check(game.hud.page._layout == "room_shop" and int(shop.refreshes) == 1, "Boss refresh redraws real stock")
	game._action("room_shop_mode", "seal", 0)
	game._action("seal_room_loot", int(offer.loot_id), 0)
	check(game.systems.is_shop_sealed(int(offer.loot_id)) and game.hud.page._layout == "room_shop" and game.hud.page.page_context.mode == "seal", "Boss seal applies effect and retains selected tab")
	game._room_shop_mode = "buy"
	game._show_room_shop(game.campaign.current_room())
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390)]:
		root.size = dimensions
		for frame in 5: await process_frame
		var view: Control = game.hud.page.room_shop_view
		check(view.context.return_to_room and not view.footer.visible and view.header.get_node("Back").has_meta("camp_back_navigation"), "Boss uses shared back navigation: " + str(dimensions))
		check(view.get_global_rect().encloses(view.footer.get_global_rect()), "Boss footer fits viewport: " + str(dimensions))
		for button in [view.deposit, view.deposit.get_parent().get_child(0)]:
			for state in ["normal", "hover", "pressed", "disabled"]:
				var style: StyleBoxTexture = button.get_theme_stylebox(state)
				check(style.texture_margin_top == 0 and style.texture_margin_bottom == 0 and style.texture_margin_left == 45 and style.texture_margin_right == 45, "Shop button preserves white pill background: " + state + " " + str(dimensions))
		for card in view.cards:
			check(not card.get_node("Title").get_global_rect().intersects(card.get_node("Frame").get_global_rect()), "Goods title does not overlap icon: " + str(dimensions) + " " + str([card.get_node("Title").get_rect(), card.get_node("Frame").get_rect()]))
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://reports/boss-shop-%dx%d.png" % [dimensions.x, dimensions.y])
	game.hud.page.room_shop_view.header.get_node("Back").pressed.emit()
	check(not game.hud.modal_open and not game.world.paused, "Boss footer closes shop and resumes room")
	check(game.campaign.state.phase == phase and game.world.room_stage == stage, "Shop operations never complete or skip the Boss encounter")
	game._start_dialogue(200101)
	check(game.hud.page._layout == "room_shop" and shop.offers[3].sold, "Reopening Boss merchant retains sold stock")
	check(game._save(true), "Boss merchant writes a real checkpoint")
	var restored_profile = DungeonProfile.new()
	check(restored_profile.restore(game.save_store.load_profile()), "Boss merchant checkpoint validates")
	var restored = DungeonSystems.new(game.catalog, restored_profile)
	var restored_shop: Dictionary = restored.get_room_shop(key)
	check(JSON.parse_string(JSON.stringify(restored_shop.offers)) == JSON.parse_string(JSON.stringify(shop.offers)), "Restored Boss stock matches across JSON numeric types")
	check(int(restored_shop.refreshes) == 1 and restored.is_shop_sealed(int(offer.loot_id)), "Restored Boss refresh and seals match")
	game.queue_free()
	await process_frame
	print("BOSS_SHOP_FLOW ", JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
