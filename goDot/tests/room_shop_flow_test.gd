extends SceneTree

var game: Node
var checks := 0
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(90).timeout.connect(func(): quit(2))
	game = load("res://scenes/main.tscn").instantiate()
	game.save_store = DungeonSaveStore.new("/private/tmp/room-shop-flow-%d.json" % Time.get_ticks_usec())
	root.add_child(game)
	game.set_process(false)
	game.world.set_process(false)
	game.world.set_physics_process(false)
	game.world.presentation.audio_enabled = false
	game.world.auto_attack_enabled = false
	game.audio.stop()
	check(game.systems.begin_run(20261026, 1, 100, 0).success, "Game run starts")
	game.systems.grant_material(102, 10000)
	game.systems.set_record("shop:invested", 100)
	game.systems.set_record("shop:level", 2)
	var node_id := 0
	for node in game.campaign.database.Nodes:
		if str(node.get("Flow", "")) == "Shop":
			node_id = int(node.Id)
			break
	check(node_id > 0, "Original shop room fixture exists")
	game.campaign.start_practice(node_id, 20261026)
	game._load_room()
	game.world.set_process(true)
	var deadline = Time.get_ticks_msec() + 60000
	while game._transitioning and Time.get_ticks_msec() < deadline: await process_frame
	check(not game._transitioning, "Original shop room loads")
	game.world.set_process(false)
	game.world.paused = false
	game.hud.close_page()
	game._room_action()
	await process_frame
	check(game.hud.modal_open and game.hud.page._layout == "room_shop", "Actual room action opens the dedicated shop page")
	var key = str(game._room_key)
	var shop: Dictionary = game.systems.get_room_shop(key)
	var loot_id = int(shop.offers[3].loot_id)
	var magic = game.systems.material(102)
	game._action("buy_room", loot_id, 0)
	check(shop.offers[3].sold and game.systems.material(102) == magic - int(shop.offers[3].price), "Actual purchase command pays stock price")
	check(game.hud.page.page_context.shop.level == 2 and game.hud.page._rows[3].sold, "Purchase redraws merchant state")
	game._action("invest_room_shop", 50, 0)
	check(game.hud.page.page_context.shop.remaining == 4 and game.hud.page.page_context.shop.next_needed == 350, "Actual deposit command redraws level progress and run count")
	game._action("room_shop_mode", "seal", 0)
	game._action("seal_room_loot", loot_id, 0)
	check(game.systems.is_shop_sealed(loot_id) and game.hud.page.page_context.mode == "seal", "Seal command keeps the selected shop tab")
	check(game.hud.page.page_context.seal_rows.is_empty(), "Sealed item leaves the owned seal candidate list")
	check(game._save(true), "Actual game persists shop state")
	game.hud.close_page()
	game._room_action()
	check(game.systems.get_room_shop(key).offers[3].sold and game.hud.page.page_context.shop.remaining == 4, "Closing and reopening does not regenerate merchant state")
	game.queue_free()
	await process_frame
	print("ROOM_SHOP_FLOW_TEST ", JSON.stringify({"checks": checks, "passed": failures.is_empty(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)
