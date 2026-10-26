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
	var context = {"catalog": catalog, "systems": systems, "selected_character": 1, "resources": [["material:101", "1378"], ["material:102", "132"], ["loot:12101", "0/3"], ["material:10501", "0"]]}
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
	check(view.action_bar.get_child(0).disabled, "Already selected character command is disabled")
	view.action_bar.get_child(1).pressed.emit()
	check(_events.back() == ["op:upgrade_character", 1, 0], "Upgrade forwards the existing operation contract")
	view.talent_button.pressed.emit()
	check(_events.back() == ["page:character_talents", 1, 0], "Talent opens selected character talents")
	view.awakening_button.pressed.emit()
	check(_events.back() == ["page:awakening", 1, 0], "Awakening forwards the browsed character")
	view.selections[1].pressed.emit()
	check(view.selected == 1 and view.name_label.text == "妮洛", "Roster switches illustration and identity")
	check(host.page_context.selected_character == 2, "Browsing survives an operation refresh")
	check(view.action_bar.get_child(0).disabled, "Locked characters cannot be selected")
	view.action_bar.get_child(1).pressed.emit()
	check(_events.back() == ["op:unlock_character", 2, 0], "Recruit forwards the existing unlock contract")
	view.navigation[1].pressed.emit()
	check(_events.back() == ["page:weapons", 2, 0], "Weapon navigation follows browsed character")
	view.navigation[2].pressed.emit()
	check(_events.back() == ["page:inventory", 0, 0], "Bag opens the real inventory")
	view.navigation[3].pressed.emit()
	check(_events.back() == ["page:storage", 0, 0], "Storage opens owned materials")
	view.style_button.pressed.emit()
	check(view.active_tab == "style" and host.page_context.character_mode == "style", "Battle style tab persists")
	check(view.detail.get_children().any(func(child): return child is Label and "暗夜镰术" in child.text), "Battle style reads the selected character's real skill names")
	view.details_button.pressed.emit()
	check(view.active_tab == "details", "Details tab returns to stats")
	check(view.detail.find_children("*", "Label", true, false).any(func(child): return child.text == "(+4)"), "Equipment and progression bonuses are shown")
	for dimensions in [Vector2i(1600, 900), Vector2i(2460, 1080), Vector2i(844, 390)]:
		canvas.size = dimensions
		for step in 10: await process_frame
		check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(view.get_rect()), "Full character page fits " + str(dimensions))
		check(view.showcase.size.x > 100, "Character retains visible artwork width " + str(dimensions))
		check(view.showcase.get_global_rect().end.x <= view.right_column.get_global_rect().position.x, "Artwork and attributes stay separate " + str(dimensions))
		check(view.resource_bar.get_global_rect().end.x <= view.get_global_rect().end.x, "Resources fit " + str(dimensions))
		check(view.action_bar.get_global_rect().end.y <= view.get_global_rect().end.y, "Progression commands remain visible " + str(dimensions))
		check(view.navigation[3].get_global_rect().end.y <= view.get_global_rect().end.y, "All left navigation remains visible " + str(dimensions))
		for child in view.detail.get_children():
			if child is VBoxContainer:
				for line in child.get_children():
					check(line.size.y <= 45, "Stat rows stay on one line " + str(dimensions))
					check(line.get_global_rect().end.x <= view.detail_scroll.get_global_rect().end.x, "Stat rows fit the detail width " + str(dimensions))
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			canvas.get_texture().get_image().save_png("res://reports/character-page-%dx%d.png" % [dimensions.x, dimensions.y])
	view.model_button.pressed.emit()
	for step in 8: await process_frame
	check(view.showcase.get_child(0) is DungeonModelPreview, "3D toggle loads the real character model")
	check(host.page_context.use_model, "3D mode survives operation refresh")
	view.model_button.pressed.emit()
	view.attributes_button.pressed.emit()
	for step in 4: await process_frame
	check(is_instance_valid(view._attribute_overlay), "Attribute details opens a dismissible overlay")
	view._attribute_overlay.queue_free()
	canvas.queue_free()
	display.queue_free()
	await process_frame
	print("CHARACTER_PAGE ", JSON.stringify({"passed": failures.is_empty(), "assertions": assertions, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
