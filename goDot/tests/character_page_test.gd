extends SceneTree

var failures: Array[String] = []
var assertions := 0
var _events: Array = []

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var catalog = DungeonCatalog.new()
	check(catalog.load_all(), "Recovered character catalog loads")
	var profile = DungeonProfile.new()
	var systems = DungeonSystems.new(catalog, profile)
	var canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var display = TextureRect.new()
	display.texture = canvas.get_texture()
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(display)
	var host = DungeonMenuPage.new()
	canvas.add_child(host)
	host.hide()
	var rows: Array = []
	for source in catalog.rows("CharData"):
		var id = int(source.id)
		rows.append({"config_id": id, "title": str(source.name) + "  Lv.%d" % (1 if id == 1 else 0), "description": DungeonCatalog.clean(source.description) + "\n金币 ×200", "icon": source.square_icon_name, "artwork": source.full_icon_name, "model": "res://assets/characters/character_%d.glb" % id, "active_character": id == 1, "in_run": false, "stats": [["生命", "100"], ["攻击", "89"], ["防御", "84"], ["暴击率", "5%"], ["暴击伤害", "150%"]], "stats_bonus": ["", "+4", "+14", "", ""], "buttons": [{"text": "已选择" if id == 1 else "选择", "action": "select_character", "id": id, "disabled": id != 1}, {"text": "升级" if id == 1 else "招募", "action": "op:upgrade_character" if id == 1 else "op:unlock_character", "id": id}, {"text": "查看天赋", "action": "page:character_talents", "id": id}]})
	var context = {"catalog": catalog, "systems": systems, "selected_character": 1, "camp": true, "in_run": false, "fashion_equipped": {"1": 1001}, "fashion_owned": [], "resources": [["material:101", "1378"]]}
	host.page_context = context
	var view = preload("res://scripts/presentation/character_page.gd").new()
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(view)
	view.configure(host, rows, context)
	view.command.connect(func(kind, id, extra): _events.append([kind, id, extra]))
	for step in 8: await process_frame
	check(view.name_label.text == "凯", "Selected identity uses real recovered name")
	check(view.showcase.get_child(0) is TextureRect, "Initial showcase uses full recovered artwork")
	check(view.selections.size() == 8, "All available characters can be browsed")
	check(view.resource_bar.get_child_count() == 1, "Camp source header shows gold only")
	check(view.navigation.map(func(button): return button.text) == ["角色", "武器", "仓库"], "Camp source navigation excludes the run bag")
	check(not view._roster_overlay.visible, "Roster stays in its separate selection overlay")
	check(view.showcase.get_child(0).texture.resource_path.ends_with("sprite_illustration_jiannan.png"), "Kai uses exact source flame illustration")
	check(view.action_bar.get_child_count() == 1, "Main source view exposes the progression action")
	systems.grant_material(501, 20)
	view.action_bar.get_child(0).pressed.emit()
	check(is_instance_valid(view._upgrade_overlay) and _events.is_empty(), "Upgrade opens a quote without spending or dispatching")
	for dimensions in [Vector2i(2048, 900), Vector2i(844, 390)]:
		canvas.size = dimensions
		for step in 8: await process_frame
		check(view.get_global_rect().encloses(view._upgrade_overlay.panel.get_global_rect()), "Integrated upgrade panel fits " + str(dimensions))
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			canvas.get_texture().get_image().save_png("res://reports/character-upgrade-page-%dx%d.png" % [dimensions.x, dimensions.y])
	view._upgrade_overlay.confirm_button.pressed.emit()
	check(_events.back() == ["op:upgrade_character", 1, 0], "Upgrade confirmation forwards the existing operation contract")
	view.talent_button.pressed.emit()
	check(is_instance_valid(view.talent_view), "Talent opens selected character talents")
	view.talent_view.queue_free()
	await process_frame
	view.awakening_button.pressed.emit()
	check(_events.back() == ["page:awakening", 1, 0], "Awakening forwards the browsed character")
	view.picker_button.pressed.emit()
	check(view._roster_overlay.visible, "Portrait opens independent character selection")
	view.selections[1].pressed.emit()
	check(view.selected == 1 and view.name_label.text == "妮洛", "Roster switches illustration and identity")
	check(host.page_context.selected_character == 2, "Browsing survives an operation refresh")
	check(not view._roster_overlay.visible, "Selection returns to the source details page")
	check(_events.back() == ["page:awakening", 1, 0], "Browsing a locked character never equips it")
	view.action_bar.get_child(0).pressed.emit()
	check(_events.back() == ["op:unlock_character", 2, 0], "Recruit forwards the existing unlock contract")
	view.navigation[1].pressed.emit()
	check(_events.back() == ["page:weapons", 2, 0], "Weapon navigation follows browsed character")
	view.navigation[2].pressed.emit()
	check(_events.back() == ["page:storage", 0, 0], "Storage opens owned materials")
	view.style_button.pressed.emit()
	check(view.active_tab == "style" and host.page_context.character_mode == "style", "Battle style tab persists")
	check(view.detail.get_children().any(func(child): return child is Label and "暗夜镰术" in child.text), "Battle style reads the selected character's real skill names")
	view.details_button.pressed.emit()
	check(view.active_tab == "details", "Details tab returns to stats")
	check(view.detail.find_children("*", "Label", true, false).any(func(child): return child.text == "(+4)"), "Equipment and progression bonuses are shown")
	view._select_showcase(0)
	for dimensions in [Vector2i(1600, 900), Vector2i(2460, 1080), Vector2i(844, 390)]:
		canvas.size = dimensions
		for step in 10: await process_frame
		check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(view.get_rect()), "Full character page fits " + str(dimensions))
		check(view.showcase.size.x > 100, "Character retains visible artwork width " + str(dimensions))
		check(view.showcase.get_global_rect().end.x <= view.right_column.get_global_rect().position.x, "Artwork and attributes stay separate " + str(dimensions))
		check(view.resource_bar.get_global_rect().end.x <= view.get_global_rect().end.x, "Resources fit " + str(dimensions))
		check(view.action_bar.get_global_rect().end.y <= view.get_global_rect().end.y, "Progression commands remain visible " + str(dimensions))
		var back_rect = view._back_button.get_global_rect()
		var factor = minf(dimensions.x / 2048.0, dimensions.y / 900.0)
		check(back_rect.position.is_equal_approx(Vector2(20, 14) * factor) and back_rect.size.is_equal_approx(Vector2(120, 100) * factor), "Shared back button fits source geometry " + str(dimensions))
		check(view.navigation.back().get_global_rect().end.y <= view.get_global_rect().end.y, "All left navigation remains visible " + str(dimensions))
		var stats = view.detail.get_node("SourceAttributes")
		check(stats.get_child_count() == 5, "Five original attribute icons and values exist " + str(dimensions))
		check(stats.get_global_rect().end.x <= view.detail_scroll.get_global_rect().end.x + 1, "Stat rows fit the detail width " + str(dimensions))
		check(stats.get_global_rect().end.y <= view.detail_scroll.get_global_rect().end.y + 1, "All five stats are visible above progression " + str(dimensions))
		if stats.get_global_rect().end.y > view.detail_scroll.get_global_rect().end.y + 1: print("CHARACTER_GEOMETRY ", {"stats": stats.get_rect(), "scroll": view.detail_scroll.get_rect(), "bio": view.biography.get_rect(), "caption": view.detail.get_child(0).get_rect()})
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			canvas.get_texture().get_image().save_png("res://reports/character-page-%dx%d.png" % [dimensions.x, dimensions.y])
	view.model_button.pressed.emit()
	for step in 8: await process_frame
	check(view.showcase.get_child(0) is DungeonModelPreview, "3D toggle loads the real character model")
	check(host.page_context.use_model, "3D mode survives operation refresh")
	view.model_button.pressed.emit()
	for dimensions in [Vector2i(2048, 900), Vector2i(1600, 900), Vector2i(844, 390)]:
		canvas.size = dimensions
		view.attributes_button.pressed.emit()
		for step in 8: await process_frame
		check(is_instance_valid(view._attribute_overlay), "Attribute details opens a full-screen table")
		check(view._attribute_overlay._table.get_child_count() == 61, "Attributes include all 52 source properties and nine group separators")
		check(view._attribute_overlay.get_global_rect().size.is_equal_approx(Vector2(dimensions)), "Attribute shade covers viewport")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			canvas.get_texture().get_image().save_png("res://reports/character-attributes-%dx%d.png" % [dimensions.x, dimensions.y])
		var table = view._attribute_overlay._table
		var help = table.get_child(6).find_children("*", "Button", true, false)[0]
		help.pressed.emit()
		check(view._attribute_overlay._help.visible, "Attribute question mark opens the source explanation")
		check(view._attribute_overlay.dismiss_help() and view._attribute_overlay.visible, "Dismissing help retains the attribute page")
		view._attribute_overlay._scroll.scroll_vertical = 10000
		for step in 4: await process_frame
		check(table.get_child(-1).get_global_rect().end.y <= view._attribute_overlay._scroll.get_global_rect().end.y + 1, "Last source attribute is reachable by scrolling")
		view._dismiss_overlay(view._attribute_overlay)
		view.fashion_button.pressed.emit()
		for step in 8: await process_frame
		check(view._fashion_overlay.visible and host.page_context.fashion_open, "Fashion opens its dedicated page")
		check(view._fashion_overlay.swatches.size() == 5, "Kai exposes all five source color swatches")
		check(view._fashion_overlay.swatches[0].find_children("*", "Label", true, false).any(func(label): return label.text == "穿戴中"), "Equipped fashion is marked on the swatch")
		check(view._fashion_overlay._art.get_global_rect().end.x <= view._fashion_overlay._details.get_global_rect().position.x, "Fashion art and details do not overlap")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			canvas.get_texture().get_image().save_png("res://reports/character-fashion-%dx%d.png" % [dimensions.x, dimensions.y])
		view._fashion_overlay.close()
	view._show_fashions()
	for step in 4: await process_frame
	view._fashion_overlay.swatches[1].pressed.emit()
	check(view._selected_fashion().id == 1002 and view._fashion_overlay.visible, "Selecting a swatch previews it inside the fashion page")
	check(view._fashion_overlay._model_button.disabled, "Unrecovered alternate 3D is disabled")
	check(host.page_context.fashion_open and host.page_context.selected_fashion == 1002, "Fashion selection survives a command refresh")
	var action = view._fashion_overlay.find_child("FashionAction", true, false)
	check(action.disabled, "Insufficient material disables fashion purchase")
	profile.data.materials["502"] = 30
	view._show_fashions()
	for step in 4: await process_frame
	action = view._fashion_overlay.find_child("FashionAction", true, false)
	check(action.text == "解锁" and not action.disabled, "Affordable selected fashion can unlock")
	action.pressed.emit()
	check(_events.back() == ["op:unlock_character_fashion", 1002, 1], "Fashion purchase forwards exact identifiers")
	check(systems.unlock_character_fashion(1002, 1).success, "Source fashion purchase succeeds")
	view.context["fashion_owned"] = systems.character_fashion_owned()
	view._show_fashions()
	for step in 4: await process_frame
	action = view._fashion_overlay.find_child("FashionAction", true, false)
	check(action.text == "装备" and not action.disabled, "Purchased selected fashion exposes equip")
	action.pressed.emit()
	check(_events.back() == ["op:equip_character_fashion", 1002, 1], "Fashion equipment forwards exact transaction")
	view._fashion_overlay.close()
	check(view._preview_fashion == 0 and not host.page_context.fashion_open, "Back restores equipped appearance and closes fashion context")
	view.hide()
	var run_row: Dictionary = rows[0].duplicate(true)
	run_row["in_run"] = true
	run_row["buttons"] = [{"text": "查看天赋", "action": "page:character_talents", "id": 1}]
	var run_context = {"catalog": catalog, "systems": systems, "camp": false, "in_run": true, "partner_navigation": true, "resources": [["material:101", "1378"], ["material:102", "132"], ["loot:12101", "0/3"], ["material:108", "0"]]}
	var run_view = preload("res://scripts/presentation/character_page.gd").new()
	run_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(run_view)
	run_view.configure(host, [run_row], run_context)
	for step in 8: await process_frame
	check(run_view.navigation.map(func(button): return button.text) == ["角色", "武器", "背包", "仓库", "怪物伙伴"], "Run source navigation includes bag and unlocked partner")
	check(run_view.resource_bar.get_child_count() == 4, "Run source header exposes exactly its four source resources")
	check(not run_view.action_bar.visible and not run_view.picker_button.visible, "Run details cannot switch or upgrade the camp roster")
	check(run_view.navigation.back().get_global_rect().end.y <= canvas.size.y, "All five run entries fit the phone landscape")
	check(run_view.resource_bar.get_global_rect().end.x <= canvas.size.x, "All four run resource pills fit the phone landscape")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		canvas.get_texture().get_image().save_png("res://reports/character-page-run-844x390.png")
	canvas.queue_free()
	display.queue_free()
	await process_frame
	print("CHARACTER_PAGE ", JSON.stringify({"passed": failures.is_empty(), "assertions": assertions, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
