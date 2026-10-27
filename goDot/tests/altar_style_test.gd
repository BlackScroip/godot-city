extends SceneTree

const Palette = preload("res://scripts/presentation/choice_palette.gd")
const RichSource = preload("res://scripts/presentation/source_rich_text.gd")
var checks := 0
var failures: Array[String] = []
var captures: Array[String] = []
var commands: Array = []
var catalog: DungeonCatalog

class PageRecorder extends DungeonHud:
	var captured_rows: Array = []
	var captured_layout := ""
	var captured_context: Dictionary = {}
	func show_page(_title: String, rows: Array, layout := "list", context: Dictionary = {}) -> void:
		captured_rows = rows
		captured_layout = layout
		captured_context = context

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _row(id: int, sacrifice := false) -> Dictionary:
	var loot := catalog.find("LootData", id)
	var ability := catalog.find("AbilityItems", int(loot.get("ability_item_id", id)))
	var row := {"title": ability.Name, "description": DungeonCatalog.clean(ability.Description), "source_description": ability.Description,
		"loot_id": id, "icon": "loot:" + str(id), "rarity": int(ability.Rare), "loot_type": loot.loot_type,
		"effect_tags": loot.get("effect_tag_list", []), "show_collection_badge": id == 20230,
		"buttons": [{"text": "献祭" if sacrifice else "选择", "action": "choose_sacrifice" if sacrifice else "choose_loot", "id": id, "extra": "altar:style"}]}
	if sacrifice:
		row.merge({"hp_cost": 30 + id % 20, "locked": id == 20260, "lock_command": {"action": "lock_sacrifice", "id": id, "extra": "altar:style"}})
	return row

func _run() -> void:
	catalog = DungeonCatalog.new()
	check(catalog.load_all(), "Real APK catalog loads")
	var canvas := SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var page := DungeonMenuPage.new()
	page.theme = DungeonStyle.theme()
	canvas.add_child(page)
	page.command.connect(func(kind, id, extra): commands.append([kind, id, extra]))
	var scenarios := {"sprites": [20230, 20265, 20260], "curse": [22011, 22021, 22031], "old_day": [20403, 20408, 20409], "sacrificial": [20230, 20260, 11005]}
	for kind in scenarios:
		var rows: Array = []
		for id in scenarios[kind]: rows.append(_row(id, kind == "sacrificial"))
		var actions: Array = [{"text": "刷新", "action": "refresh_sacrifice" if kind == "sacrificial" else "refresh_loot", "id": "altar:style", "disabled": true}]
		if kind == "sacrificial": actions.append({"text": "结束献祭", "action": "finish_sacrifice", "id": "altar:style"})
		rows.append({"presentation_role": "refresh", "buttons": actions})
		page.display("请选择一个精灵" if kind == "sprites" else "选择遗物", rows, "altar", {"altar_kind": kind})
		var view = page.special.get_child(0)
		check(page.special.altar_parts == view.parts and view.parts.size() == 3, "All altars use shared source cards: " + kind)
		check(not page.stack.get_child(0).visible, "Source selection owns its full-screen heading: " + kind)
		check(view.refresh_button.disabled, "Refresh unavailable state survives: " + kind)
		check(view.parts.all(func(part): return not part.choose.visible), "Source confirm starts hidden: " + kind)
		for part in view.parts:
			check(part.description is RichTextLabel and part.description.source_text == rows[view.parts.find(part)].source_description, "Raw source description reaches rich renderer: " + kind)
			check(not part.description.get_parsed_text().contains("<#specinfo="), "Semantic tags do not leak: " + kind)
			check(part.panel.background_key == ("rarebg_vertical_curse_v2" if kind in ["curse", "old_day"] else Palette.sprite_key("rarebg_vertical", int(rows[view.parts.find(part)].rarity))), "Correct source rarity or curse card: " + kind)
		if kind == "sprites":
			check(view.parts[0].has("book") and not view.parts[1].has("book"), "Only undiscovered item has source collection badge")
			check(view.parts[1].tags.get_child_count() == 1 and view.parts[2].tags.get_child_count() == 2, "Source ice and dark damage tags render below their names")
		if kind == "sacrificial":
			check(view.parts.all(func(part): return part.has("lock") and part.has("health")), "Sacrifice exposes locking and original HP price")
			check(view.parts[1].lock.button_pressed, "Saved locked choice remains locked")
			view.parts[1].lock.pressed.emit()
			check(commands.pop_back() == ["lock_sacrifice", 20260, "altar:style"], "Lock retains exact altar and candidate identity")
			view.finish_button.pressed.emit()
			check(commands.pop_back() == ["finish_sacrifice", "altar:style", ""], "Finish has a separate command from refresh")
		for dimensions in [Vector2i(1600, 900), Vector2i(844, 390)]:
			canvas.size = dimensions
			page.size = Vector2(dimensions)
			for frame in 12: await process_frame
			await create_timer(0.35).timeout
			var viewport := Rect2(Vector2.ZERO, Vector2(dimensions))
			check(viewport.encloses(view.toolbar.get_global_rect()), "Toolbar fits " + kind + str(dimensions))
			check(not view.heading.get_global_rect().intersects(view.toolbar.get_global_rect()), "Heading clears toolbar " + kind + str(dimensions))
			for part in view.parts:
				check(viewport.grow(0.5).encloses(part.panel.get_global_rect()), "Card fits " + kind + str(dimensions))
				check(part.scroll.size.y >= 40, "Source text stays scrollable " + kind + str(dimensions))
				check(part.title.get_global_rect().end.y <= part.scroll.get_global_rect().position.y, "Name does not overlap effect " + kind + str(dimensions))
				check(part.panel.get_global_rect().grow(0.5).encloses(part.footer.get_global_rect()), "Confirm area stays within source card " + kind + str(dimensions))
				for accessory in ["book", "lock", "health"]:
					if not part.has(accessory): continue
					check(part.panel.get_global_rect().grow(0.5).encloses(part[accessory].get_global_rect()), "Card accessory fits " + accessory + kind + str(dimensions))
					check(part[accessory].size.x < part.panel.size.x * 0.5 and part[accessory].size.y < part.panel.size.y * 0.2, "Card accessory keeps its source scale " + accessory + kind + str(dimensions))
			await _capture(canvas, kind, dimensions)
		view._select(1)
		check(commands.is_empty() and view.parts[1].choose.visible and not view.parts[0].choose.visible, "Preview does not grant an item: " + kind)
		view.parts[1].choose.pressed.emit()
		check(commands.pop_back() == ["choose_sacrifice" if kind == "sacrificial" else "choose_loot", scenarios[kind][1], "altar:style"], "Explicit confirm grants exact displayed candidate: " + kind)
		if kind == "sprites":
			view._show_help()
			check(view.help_dialog.title == "收集遗物吧！" and view.help_dialog.visible, "Source Guide3 opens from the question mark")
			view.help_dialog.hide()
	await _verify_extra_choices(canvas, page)
	_verify_entry_points()
	var report := {"checks": checks, "passed": failures.is_empty(), "failures": failures, "captures": captures,
		"source": "1061664.apk static prefabs, native selection handlers, GuideData and LootData; rendered execution is Godot"}
	var file := FileAccess.open("res://reports/altar-style-test.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	print("ALTAR_STYLE_TEST ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func _verify_extra_choices(canvas: SubViewport, page: DungeonMenuPage) -> void:
	var rows: Array = []
	for id in [20210, 20220, 20230, 20240, 20250]: rows.append(_row(id))
	canvas.size = Vector2i(844, 390)
	page.size = Vector2(844, 390)
	page.display("请选择一个精灵", rows, "altar")
	for frame in 12: await process_frame
	for part in page.special.altar_parts:
		check(Rect2(0, 0, 844.5, 390.5).encloses(part.panel.get_global_rect()), "Blessing extra candidates still fit the mobile viewport")

func _verify_entry_points() -> void:
	var game = load("res://scripts/main.gd").new()
	game.catalog = catalog
	game.profile = DungeonProfile.new()
	game.systems = DungeonSystems.new(catalog, game.profile)
	game.hud = PageRecorder.new()
	game.menus = DungeonMenus.new(game)
	game.systems.begin_run(73281, 1, 500)
	for key in ["altar:style", "curse_altar:style", "old_day:style"]:
		game.profile.data.run.rewards = [{"key": key, "choices": [20230, 20260, 20250]}]
		game._rewards(key)
		check(game.hud.captured_layout == "altar", "Actual altar entry selects source presentation: " + key)
		for row in game.hud.captured_rows.slice(0, 3):
			check(row.has("source_description") and row.has("effect_tags") and row.show_collection_badge, "Entry supplies raw source, tags and new-item badge")
	game.profile.data.discovered_loot.append(20230)
	game._rewards("old_day:style")
	check(not game.hud.captured_rows[0].show_collection_badge, "Previously obtained item suppresses original new badge")
	check(not game.hud.captured_rows[0].lock_visible, "Source lock buttons stay hidden until permanent talent 221 exists")
	game.profile.data.talents["221"] = 1
	game._rewards("old_day:style")
	check(game.hud.captured_rows[0].lock_visible, "Permanent talent 221 enables source altar lock buttons")
	_verify_reward_lock(game)
	game._show_sacrifice("sacrifice:style")
	check(game.hud.captured_layout == "altar" and game.hud.captured_context.altar_kind == "sacrificial", "Actual sacrifice enters shared source panel")
	for row in game.hud.captured_rows.slice(0, 3):
		check(row.has("source_description") and row.has("hp_cost") and row.has("rarity") and row.has("loot_type"), "Actual sacrifice forwards price, rarity and curse style")
	game.hud.free()
	game.ads.free()
	game.resource_audio.free()
	game.free()

func _verify_reward_lock(game: Node) -> void:
	var key := "altar:locked"
	var ids: Array = game.systems.create_loot_reward(30301, key, 3)
	check(ids.size() == 3, "Real spirit pool supplies lock fixture")
	if ids.size() != 3: return
	var id := int(ids[1])
	game.profile.data.talents.erase("221")
	check(not game.systems.toggle_loot_reward_lock(key, id).success, "Reward lock enforces source talent gate")
	game.profile.data.talents["221"] = 1
	check(game.systems.toggle_loot_reward_lock(key, id).success, "Source reward candidate can be locked")
	check(not game.systems.toggle_loot_reward_lock(key, 9999999).success, "Non-candidate cannot become locked")
	game.profile.data.run.counters.SelectRefreshTime = 2
	check(game.systems.refresh_loot_reward(key).success, "Unlocked choices refresh beside a held candidate")
	var reward: Dictionary = game.profile.data.run.rewards.filter(func(item): return item.key == key)[0]
	check(reward.choices[1] == id and reward.choices.count(id) == 1 and reward.locked_ids == [id], "Refresh preserves exact held candidate and slot without duplicates")
	check(game.profile.data.run.counters.SelectRefreshTime == 1, "Refresh spends one token")
	check(game.profile.restore(JSON.parse_string(JSON.stringify(game.profile.data))), "Locked reward passes real save validation and ID normalization")
	game._rewards(key)
	check(game.hud.captured_rows[1].locked, "JSON restoration forwards held candidate state")
	check(game.systems.toggle_loot_reward_lock(key, id).success, "Reward candidate unlocks again")

func _capture(canvas: SubViewport, kind: String, dimensions: Vector2i) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var picture := canvas.get_texture().get_image()
	var distinct := 0
	var first := picture.get_pixel(0, 0)
	for y in range(0, picture.get_height(), 20):
		for x in range(0, picture.get_width(), 20):
			var sample := picture.get_pixel(x, y)
			if Vector3(sample.r - first.r, sample.g - first.g, sample.b - first.b).length() > 0.15: distinct += 1
	check(distinct > 100, "Rendered altar card pixels are nonblank " + kind + str(dimensions))
	var path := "res://reports/altar-%s-%dx%d.png" % [kind, dimensions.x, dimensions.y]
	picture.save_png(path)
	captures.append(path)
