extends SceneTree

var failures: Array[String] = []
var checks := 0
var canvas: SubViewport
var host: DungeonMenuPage
var catalog: DungeonCatalog
var systems: DungeonSystems
var profile: DungeonProfile
var rendered := false

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures.append(text)
		push_error(text)

func _navigation(in_run: bool) -> Array:
	var rows := [{"label": "角色", "page": "characters"}, {"label": "武器", "page": "weapons"}]
	if in_run: rows.append({"label": "背包", "page": "inventory"})
	rows.append({"label": "仓库", "page": "storage"})
	if in_run: rows.append({"label": "怪物伙伴", "page": "partners"})
	return rows

func _context(page: String, in_run := false) -> Dictionary:
	return {"page": page, "catalog": catalog, "systems": systems, "camp": not in_run, "in_run": in_run,
		"character_id": 1, "role_navigation": _navigation(in_run),
		"resources": [["material:101", "1378"], ["material:102", "123"], ["loot:12101", "15/20"], ["material:108", "1"]] if in_run else [["material:101", "1378"]]}

func _materials() -> Array:
	var rows: Array = []
	for id in [101, 103, 108, 502, 601, 602, 90002, 801]:
		var source := catalog.find("MaterialData", id)
		if source.is_empty(): continue
		var row := {"material_id": id, "title": DungeonCatalog.clean(DungeonCatalog.row_name(source)),
			"description": DungeonCatalog.clean(DungeonCatalog.description(source)), "count": systems.material(id), "star_num": source.star_num}
		if id == 801: row["buttons"] = [{"text": "开启", "action": "op:open_material_box", "id": id, "extra": 0, "disabled": false}]
		rows.append(row)
	return rows

func _loot() -> Array:
	var rows: Array = []
	for source in catalog.rows("LootData"):
		if rows.size() >= 30: break
		var id := int(source.id)
		var ability := catalog.find("AbilityItems", int(source.get("ability_item_id", id)))
		if not ability.get("DisplayInBag", true): continue
		profile.data.run.inventory[str(id)] = 1 + rows.size() % 4
		rows.append({"loot_id": id, "title": DungeonCatalog.clean(DungeonCatalog.row_name(ability)), "count": profile.data.run.inventory[str(id)],
			"description": DungeonCatalog.clean(DungeonCatalog.description(ability)), "star_num": int(ability.get("Rare", 1))})
	return rows

func _page(rows: Array, context: Dictionary) -> DungeonInventoryPage:
	var view := DungeonInventoryPage.new()
	canvas.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.page_context = context
	view.configure(host, rows, context)
	return view

func _run() -> void:
	rendered = "--render-check" in OS.get_cmdline_user_args()
	catalog = DungeonCatalog.new()
	check(catalog.load_all(), "Actual extracted configuration loads")
	profile = DungeonProfile.new()
	for id in [101, 103, 108, 502, 601, 602, 90002, 801]: profile.data.materials[str(id)] = 2 if id == 801 else 1378 if id == 101 else 13
	systems = DungeonSystems.new(catalog, profile)
	host = DungeonMenuPage.new()
	canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var rows := _materials()
	var view := _page(rows, _context("storage"))
	await process_frame
	view._adapt()
	for dimensions in [Vector2i(2048, 900), Vector2i(1600, 900), Vector2i(844, 390), Vector2i(2460, 1080)]:
		canvas.size = dimensions
		await process_frame
		view._adapt()
		var factor = minf(dimensions.x / 2048.0, dimensions.y / 900.0)
		var expected_back = Rect2(Vector2(20, 14) * factor, Vector2(120, 100) * factor)
		check(view._back.get_global_rect().is_equal_approx(expected_back), "warehouse uses the shared role back bounds %s" % dimensions)
		check(view._back.get_node("Arrow").texture == DungeonInventoryPage.ROLE_NAVIGATION.BACK_TEXTURE, "warehouse uses the original role arrow")
	canvas.size = Vector2i(1600, 900)
	await process_frame
	view._adapt()
	check(view.rows.size() == rows.size() and view.grid.columns == 6, "Warehouse displays real items in six source-style columns")
	check(view.navigation.map(func(button): return button.text) == ["角色", "武器", "仓库"], "Camp uses only the actual three navigation categories")
	check(view.resource_bar.get_child_count() == 1, "Camp header shows its single gold counter")
	check(view.selected_inventory_key == "material:101" and view.detail_icon.texture != null, "First material selects its original icon and detail")
	check(view.description_label.text.contains("获取途径"), "Material detail retains real acquisition information")
	var commands: Array = []
	view.command.connect(func(kind, id, extra):
		commands.append([kind, id, extra])
		if kind == "op:open_material_box": systems.open_material_box(int(id)))
	view.navigation[1].pressed.emit()
	check(commands.back() == ["page:weapons", 1, 0], "Navigation emits the actual character weapon command")
	view.select_item("material:801")
	check(view.selected_inventory_key == "material:801" and host.page_context.selected_inventory_key == "material:801", "Stable selection persists in host context")
	var before := systems.material(801)
	check(view.action_bar.get_child_count() == 1, "Actual material-box row creates its action")
	view.action_bar.get_child(0).pressed.emit()
	check(commands.back() == ["op:open_material_box", 801, 0] and systems.material(801) == before - 1, "The visible action button dispatches the real open command and consumes one real box")
	view.selections[0].pressed.emit()
	check(view.selected_inventory_key == "material:101", "A real tile click replaces selected detail")
	view.select_item(2)
	check(view.selected == 2, "Public integer selection addresses the same grid")
	for tier in range(1, 6): check(view._texture("slotfg_rare_square_%d_v2" % tier) != null, "Original rarity frame exists for tier " + str(tier))
	var loot := _loot()
	if rendered:
		for page in ["storage", "inventory"]:
			view.queue_free()
			await process_frame
			view = _page(rows if page == "storage" else loot, _context(page, page == "inventory"))
			for dimensions in [Vector2i(1600, 900), Vector2i(844, 390), Vector2i(2460, 1080)]:
				canvas.size = dimensions
				for frame in 4: await process_frame
				view._adapt()
				await process_frame
				await RenderingServer.frame_post_draw
				var picture := canvas.get_texture().get_image()
				check(not picture.is_empty() and picture.save_png("res://reports/role-%s-%dx%d.png" % [page, dimensions.x, dimensions.y]) == OK, "Source-style page renders at " + page + str(dimensions))
				var frame := view.selections[0].get_global_rect()
				var amount := view._count_labels[0].get_global_rect()
				check(frame.encloses(amount), "Count remains within its tile at " + page + str(dimensions))
				check(view._paper is NinePatchRect and view._paper.scale.x < 0.6, "Detail preserves sliced source corners at " + str(dimensions))
	view.queue_free()
	await process_frame
	var state := _context("inventory", true)
	state["selected_inventory_key"] = "loot:" + str(int(loot[3].loot_id))
	view = _page(loot, state)
	await process_frame
	check(view.navigation.map(func(button): return button.text) == ["角色", "武器", "背包", "仓库", "怪物伙伴"], "Run context preserves all authorized source navigation categories")
	check(view.resource_bar.get_child_count() == 4, "Run header accepts all four recovered resource counters")
	check(view.selected == 3 and view.selected_inventory_key == state.selected_inventory_key, "Refresh restores the selected stable item key")
	var snapshots := profile.data.duplicate(true)
	view.select_item(5)
	check(profile.data == snapshots and view.action_bar.get_child_count() == 0, "Relic browsing and detail selection never invent item-use or storage transactions")
	view.queue_free()
	await process_frame
	view = _page([{"title": "暂无可显示内容", "description": "", "buttons": []}], _context("inventory", true))
	await process_frame
	check(view.rows.is_empty() and view.selections.is_empty() and view.empty_label.visible and view.selected_inventory_key.is_empty(), "Generic empty-row placeholders do not become fake loot-zero tiles")
	var closed_events: Array = []
	view.back_requested.connect(func(): closed_events.append(true))
	view._back.pressed.emit()
	check(closed_events.size() == 1, "Visible back arrow dispatches the host return signal")
	view.queue_free()
	await process_frame
	canvas.queue_free()
	host.free()
	await process_frame
	var report := FileAccess.open("res://reports/role-inventory-tests.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks": checks, "failures": failures, "rendered": rendered}, "\t"))
	print("Role inventory: %d checks; failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)
