extends SceneTree

var game: Node
var failures: Array[String] = []
var checks := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.save_store = DungeonSaveStore.new("/private/tmp/merchant-shortcuts-%d.json" % Time.get_ticks_usec())
	root.add_child(game)
	game.set_process(false)
	game.world.set_process(false)
	game.world.set_physics_process(false)
	game.audio.stop()
	game.systems.begin_run(20261028, 1, 100, 0)
	game.systems.grant_material(102, 10000)
	game.campaign.start_practice(1019101, 20261028)
	game._room_key = "merchant-shortcuts"
	var environment := Node3D.new()
	game.world.add_child(environment)
	var markers: Array = []
	for entry in [["trader", "EEUT_Special_Trader", 0], ["slime", "EEUT_Special_GemShopMan", 10]]:
		markers.append({"SceneName": "Shortcuts", "SourceGameObjectId": entry[0], "Type": entry[1], "DataJson": "{}", "world_position": [entry[2], 0, 0]})
	game.world.interactions.setup(environment, markers, {"catalog": game.catalog})
	game.world.player.position = Vector3.ZERO
	game.world.paused = false
	game.hud.close_page()
	var trader: Dictionary = game.world.interactions._items.trader
	var prompts: Array = game._interaction_prompts([trader])
	check(prompts.size() == 2 and prompts[0].text == "特拉德" and prompts[1].text == "查看商品", "Merchant exposes separate talk and goods prompts")
	game._action("world_npc_talk", "trader", 0)
	check(game.hud.page._layout == "dialogue" and int(game.profile.data.dialogue_state.function_id) == 200000, "Talk preserves merchant dialogue")
	game._close_page()
	game._action("world_npc_trade", "trader", 0)
	check(game.hud.page._layout == "dialogue" and int(game.profile.data.dialogue_state.function_id) == 200201, "First shop shortcut preserves initial dialogue requirement")
	game._action("talk_skip", 0, 0)
	game._close_page()
	game._action("world_npc_trade", "trader", 0)
	check(game.hud.page._layout == "room_shop" and game.hud.modal_open, "Unlocked shortcut opens Boss shop directly")
	var shop: Dictionary = game.systems.get_room_shop(game._room_key)
	var offer: Dictionary = shop.offers[3]
	game._action("buy_room", int(offer.loot_id), 0)
	var paid: int = game.systems.material(102)
	game._action("buy_room", int(offer.loot_id), 0)
	check(offer.sold and game.systems.material(102) == paid, "Shortcut merchant stock cannot charge twice")
	game._close_page()
	game.world.player.position = Vector3(50, 0, 0)
	game._action("world_npc_trade", "trader", 0)
	check(not game.hud.modal_open, "Stale merchant shortcut rejects distant player")
	game.world.player.position = Vector3.ZERO
	trader.state.enabled = false
	game._action("world_npc_trade", "trader", 0)
	check(not game.hud.modal_open, "Disabled merchant rejects shortcut")
	trader.state.enabled = true
	game.world.player.position = Vector3(10, 0, 0)
	var slime: Dictionary = game.world.interactions._items.slime
	prompts = game._interaction_prompts([slime])
	check(prompts.size() == 2 and prompts[0].text == "修格斯" and prompts[1].text == "供奉", "Slime King exposes separate talk and offering prompts")
	game._action("world_npc_talk", "slime", 0)
	check(game.hud.page._layout == "dialogue" and int(game.profile.data.dialogue_state.function_id) == 210000, "Slime talk opens source NPC dialogue")
	game._close_page()
	game._action("world_npc_trade", "slime", 0)
	check(game.hud.page._layout == "adventure_event" and game.hud.page.page_context.gem_offering, "Slime shortcut opens existing offering flow")
	var status: Dictionary = game.systems.gem_offering_status(game._room_key + ":slime")
	game._action("gem_offering_buy", str(status.key), {"marker_id": "slime"})
	paid = game.systems.material(102)
	game._action("gem_offering_buy", str(status.key), {"marker_id": "slime"})
	check(game.systems.gem_offering_status(game._room_key + ":slime").used and game.systems.material(102) == paid, "Offering remains single purchase through shortcut")
	game._close_page()
	game.world.player.position = Vector3.ZERO
	game._action("world_npc_trade", "slime", 0)
	check(not game.hud.modal_open, "Slime shortcut also checks proximity")
	game.queue_free()
	await process_frame
	print("MERCHANT_SHORTCUTS ", JSON.stringify({"checks": checks, "passed": failures.is_empty(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)
