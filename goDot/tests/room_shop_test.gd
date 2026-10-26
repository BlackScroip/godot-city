extends SceneTree

var checks := 0
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var catalog = DungeonCatalog.new()
	check(catalog.load_all(), "Catalog loads")
	var profile = DungeonProfile.new()
	var systems = DungeonSystems.new(catalog, profile)
	check(systems.begin_run(20261026, 1, 100).success, "Run starts")
	systems.grant_material(102, 10000)
	systems.set_record("shop:invested", 100)
	systems.set_record("shop:level", 2)
	var shop = systems.get_room_shop("room-shop", 1)
	check(shop.offers.size() == 7, "Level two shop has three supplies and four relics")
	for index in 3:
		check(int(shop.offers[index].price) == [80, 120, 150][index] and shop.offers[index].supply, "Authored fixed supply price at " + str(index))
	var status = systems.room_shop_status("room-shop")
	check(status.level == 2 and status.next_needed == 400 and status.deposit == 50 and status.remaining == 5, "Reference level two deposit status")
	var resources = systems.material(102)
	check(not systems.invest_shop(51).success and systems.material(102) == resources, "Stale or arbitrary deposit is rejected without charge")
	for index in 5: check(systems.invest_shop(50).success, "Fixed deposit " + str(index))
	check(systems.room_shop_status("room-shop").remaining == 0 and systems.stat("shop:invested") == 350, "Five deposits share one run limit")
	check(not systems.invest_shop(50).success and systems.material(102) == resources - 250, "Sixth deposit cannot charge resources")
	var fresh_shop = systems.get_room_shop("second-room-shop", 1)
	check(not fresh_shop.is_empty() and systems.room_shop_status("second-room-shop").remaining == 0, "New merchant does not reset run deposit limit")
	check(not systems.refresh_room_shop("room-shop").success, "Level two cannot refresh")
	systems.set_record("shop:level", 4)
	check(systems.refresh_room_shop("room-shop").success and not systems.refresh_room_shop("room-shop").success, "Earned refresh is single use")
	var offer = shop.offers[3]
	profile.data.materials["102"] = 0
	check(not systems.buy_room_offer("room-shop", int(offer.loot_id)).success and not offer.sold, "Insufficient purchase leaves stock intact")
	systems.grant_material(102, 10000)
	check(systems.buy_room_offer("room-shop", int(offer.loot_id)).success and offer.sold, "Purchase consumes exact merchant slot")
	check(not systems.buy_room_offer("room-shop", int(offer.loot_id)).success, "Sold slot cannot charge twice")
	var loot_id = int(offer.loot_id)
	var quote = systems.shop_seal_quote(loot_id)
	check(not quote.is_empty(), "Owned normal relic is sealable")
	var ability_id = int(catalog.find("LootData", loot_id).ability_item_id)
	check(systems.ability_sources().has(str(ability_id)), "Purchased relic ability is active")
	resources = systems.material(102)
	check(systems.seal_room_loot("room-shop", loot_id).success, "Merchant seals relic")
	check(systems.material(102) == resources + int(quote.magic), "Seal pays authored regional resale quote")
	check(systems.rank(profile.data.run.inventory, loot_id) > 0 and not systems.ability_sources().has(str(ability_id)), "Sealed ownership is retained and ability is removed")
	check(not systems.can_add_loot(loot_id), "Sealed relic cannot be reacquired")
	check(not systems.seal_room_loot("room-shop", loot_id).success and systems.material(102) == resources + int(quote.magic), "Repeated seal cannot pay twice")
	var restored_profile = DungeonProfile.new()
	check(restored_profile.restore(JSON.parse_string(JSON.stringify(profile.data))), "Shop state validates through JSON save restore")
	var restored = DungeonSystems.new(catalog, restored_profile)
	check(restored.is_shop_sealed(loot_id) and not restored.ability_sources().has(str(ability_id)), "Sealed ability remains disabled after reload")
	check(restored.room_shop_status("room-shop").remaining == 0 and restored.get_room_shop("room-shop").offers[3].sold, "Deposit count and sold stock survive reload")
	await _layout_checks(catalog, systems, shop)
	for instance in [systems, restored]: instance.decorations = null
	print("ROOM_SHOP_TEST ", JSON.stringify({"checks": checks, "passed": failures.is_empty(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func _layout_checks(catalog, systems, shop: Dictionary) -> void:
	var canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var page = preload("res://scripts/presentation/room_shop.gd").new()
	page.theme = DungeonStyle.theme()
	canvas.add_child(page)
	var data: Array = []
	for offer in shop.offers:
		var loot_id = int(offer.loot_id)
		var ability = catalog.find("AbilityItems", int(catalog.find("LootData", loot_id).ability_item_id))
		data.append({"title": DungeonCatalog.clean(systems.loot_name(loot_id)), "description": DungeonCatalog.clean(systems.loot_description(loot_id)), "loot_id": loot_id, "icon": "loot:" + str(loot_id), "price": int(offer.price), "rarity": int(ability.Rare), "sold": offer.sold, "status": "已售罄" if offer.sold else ""})
	page.configure(data, {"shop": systems.room_shop_status("room-shop"), "magic": systems.material(102), "free": 0, "seal_rows": data.slice(3)})
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390)]:
		canvas.size = dimensions
		page.size = Vector2(dimensions)
		for frame in 8: await process_frame
		for control in [page.header, page.investment, page.tabs, page.scroll, page.refresh, page.footer]:
			check(page.get_global_rect().encloses(control.get_global_rect()), "Shop control fits %s: %s %s" % [dimensions, control.get_class(), control.get_global_rect()])
		check(page.cards.size() == 7 and page.grid.columns == 4, "Seven reference cards retain four columns " + str(dimensions))
		check(page.cards[0].size.x >= 100 and page.cards[0].size.y >= 120, "Readable shop cards " + str(dimensions))
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			canvas.get_texture().get_image().save_png("/private/tmp/room-shop-%dx%d.png" % [dimensions.x, dimensions.y])
		page._show_item(data[0])
		for frame in 5: await process_frame
		check(page.get_global_rect().encloses(page.modal.get_node("Panel").get_global_rect()), "Purchase detail fits " + str(dimensions) + " " + str(page.modal.get_node("Panel").get_global_rect()))
		page._close_modal()
		page._show_levels()
		for frame in 5: await process_frame
		check(page.get_global_rect().encloses(page.modal.get_node("Panel").get_global_rect()), "Level detail fits " + str(dimensions))
		page._close_modal()
		page._select_mode("seal", false)
		for frame in 5: await process_frame
		check(page.cards.size() == 4 and not page.refresh.visible, "Seal tab displays owned relics " + str(dimensions))
		page._select_mode("buy", false)
	canvas.queue_free()
	await process_frame
