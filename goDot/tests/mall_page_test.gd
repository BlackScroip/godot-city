extends SceneTree

const MallPage = preload("res://scripts/presentation/mall_page.gd")
var failures: Array[String] = []
var checks := 0
var commands: Array = []
var catalog = DungeonCatalog.new()
var systems

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _rows() -> Array:
	var result: Array = []
	for source in catalog.rows("MallTradeData"):
		if not source.get("Enable", false): continue
		var id = DungeonCatalog.row_id(source)
		var quote = systems.offer_quote(id)
		var ad = str(source.GoodsPayType) == "Ad"
		result.append({"title": DungeonCatalog.row_name(source), "config_id": id, "payment_type": source.GoodsPayType, "offer_quote": quote,
			"buttons": [{"text": "免广告领取" if ad else "购买" if source.GoodsPayType in ["Money", "Other"] else "兑换", "action": "ad_skip:mall" if ad else "op:buy_mall", "id": id, "extra": 0, "disabled": false if ad else not quote.can_buy}]})
	return result

func _run() -> void:
	check(catalog.load_all(), "packaged catalog loads")
	systems = DungeonSystems.new(catalog, DungeonProfile.new())
	systems.grant_material(90002, 2000)
	var viewport = SubViewport.new()
	viewport.size = Vector2i(1920, 900)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var page = MallPage.new()
	page.theme = DungeonStyle.theme()
	viewport.add_child(page)
	page.size = viewport.size
	var context = {"systems": systems, "catalog": catalog}
	page.configure(null, _rows(), context)
	page.command.connect(func(kind, id, extra): commands.append([kind, id, extra]))
	for dimensions in [Vector2i(1920, 900), Vector2i(844, 390), Vector2i(2460, 1080)]:
		viewport.size = dimensions
		page.size = dimensions
		page.select_category("vip")
		for frame in 8: await process_frame
		check(page.category_buttons.size() == 5, "five original mall tabs remain reachable %s" % dimensions)
		check(page.portrait.texture != null and page._texture("特权") != null and page._texture("免广告") != null, "original portrait, key and ad-free sprite load %s" % dimensions)
		check(page.primary_button.text == "￥18" and page.primary_button.disabled, "original cash price remains visible without a payment bridge %s" % dimensions)
		check(page.daily_reward.text == "200", "VIP daily amount uses RogueConfigData %s" % dimensions)
		check(page.get_global_rect().encloses(page.primary_button.get_global_rect()), "VIP purchase remains inside viewport %s" % dimensions)
		for tab in page.category_buttons.values(): check(page.get_global_rect().encloses(tab.get_global_rect()), "tab fits viewport %s" % dimensions)
		await _capture(viewport, "vip", dimensions)
		page.select_category("rainbow")
		for frame in 8: await process_frame
		check(page.visible_offer_ids.size() == 17, "rainbow shows four ads, nine resource trades and four crystal packs %s" % dimensions)
		check(page.offer_buttons.has(20001), "real FreeCion offer remains accessible %s" % dimensions)
		await _capture(viewport, "rainbow", dimensions)
		page.select_category("treasure")
		for frame in 8: await process_frame
		check(page.primary_button.disabled, "fresh profile respects real treasure NPC prerequisite %s" % dimensions)
		check(not page.status_label.text.is_empty(), "treasure lock has a reason %s" % dimensions)
		await _capture(viewport, "treasure", dimensions)
		for category in ["blessing", "bundles"]:
			page.select_category(category)
			for frame in 8: await process_frame
			check(not page.purchase_buttons.is_empty() and page.purchase_buttons[0].disabled, "cash variants retain payment verification gate %s %s" % [category, dimensions])
			await _capture(viewport, category, dimensions)
	var ids: Dictionary = {}
	for category in ["vip", "blessing", "rainbow", "bundles"]:
		page.select_category(category)
		for id in page.visible_offer_ids:
			check(not ids.has(id), "offer appears once across categories " + str(id))
			ids[id] = true
	check(ids.size() == 28, "all enabled original offers appear across mall categories")
	page.select_category("rainbow")
	page.select_offer(20001)
	check(not page.purchase_buttons[0].disabled, "funded original FreeCion offer enables its command")
	page.purchase_buttons[0].pressed.emit()
	check(commands.back() == ["op:buy_mall", 20001, 0], "offer command preserves selected original identity")
	var before = systems.material(90002)
	check(systems.buy_mall(20001).success and systems.material(90002) == before - 120, "real routed resource purchase uses exact original price")
	page.select_offer(1002)
	page.purchase_buttons[0].pressed.emit()
	check(commands.back() == ["ad_skip:mall", 1002, 0], "ad offer retains reward callback route")
	page.select_category("blessing")
	check(page.visible_offer_ids == [30002, 30003, 30004], "all three configured blessing variants remain visible")
	for id in [30002, 30003, 30004]:
		page.select_offer(id)
		check(page.purchase_buttons[0].disabled, "unverified blessing entitlement cannot be purchased " + str(id))
	page.select_category("bundles")
	check(not page._offer_title(2015, page._row(2015)).contains("PopShopTradeData"), "unresolved localization key falls back to real reward material name")
	page.select_offer(2019)
	check(context.mall_category == "bundles" and context.selected_offer == 2019, "category and offer selection persist for menu refresh")
	page._emit_entry({"action": "op:buy_mall", "id": 30001, "disabled": true})
	check(commands.back() == ["ad_skip:mall", 1002, 0], "disabled payment entry cannot emit a purchase")
	viewport.queue_free()
	await process_frame
	systems.effects = null
	systems.decorations = null
	var result = {"passed": failures.is_empty(), "checks": checks, "failures": failures, "renderer": DisplayServer.get_name(), "viewports": [[1920, 900], [844, 390], [2460, 1080]], "categories": ["vip", "rainbow", "treasure", "blessing", "bundles"]}
	var file = FileAccess.open("res://reports/mall-page-tests.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(result, "\t") + "\n")
		file.close()
	print("MALL_PAGE_TEST ", JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)

func _capture(viewport: SubViewport, name: String, dimensions: Vector2i) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var picture = viewport.get_texture().get_image()
	check(not picture.is_empty(), "rendered mall screenshot is nonempty")
	picture.save_png("/private/tmp/mall-%s-%dx%d.png" % [name, dimensions.x, dimensions.y])
