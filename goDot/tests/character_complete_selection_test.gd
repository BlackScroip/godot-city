extends SceneTree

var checks := 0
var failures: Array[String] = []
var commands: Array = []
var rendered := false

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("CHARACTER_SELECTION: " + message)

func settle() -> void:
	for frame in 5: await process_frame
	await create_timer(0.22).timeout

func _run() -> void:
	rendered = "--render-check" in OS.get_cmdline_user_args()
	var canvas := SubViewport.new()
	canvas.size = Vector2i(2460, 1080)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var page := DungeonMenuPage.new()
	page.theme = DungeonStyle.theme()
	canvas.add_child(page)
	page.command.connect(func(kind, id, extra): commands.append([kind, id, extra]))
	var catalog := DungeonCatalog.new()
	check(catalog.load_all(), "Source catalog loads")
	var rows: Array = []
	for id in [106, 112, 113]:
		var source := catalog.find("CharTalentData", id)
		var levels := DungeonCatalog.ids(source.get("level_data_id_list", ""))
		var level := catalog.find("CharTalentLevelData", levels[0]) if not levels.is_empty() else {}
		rows.append({"config_id": id, "title": source.get("name", ""), "icon": source.get("icon_name", ""), "target_level": 1, "description": DungeonCatalog.clean(source.get("description", "")), "level_description": DungeonCatalog.clean(level.get("effect_description", "")), "buttons": [{"action": "choose_talent", "id": id, "extra": "selection-proof"}]})
	rows[0]["marked"] = true
	page.display("选择角色天赋", rows, "talent")
	var view = page.special.get_child(0)
	await settle()
	check(view.selected == -1 and not view.selection_effect.visible, "An unopened choice has no selected card or selection effect")
	check(view.parts.all(func(part): return not part.choose.visible), "Confirmation is hidden until a card is selected")
	view.parts[0].choose.pressed.emit()
	check(commands.is_empty(), "A hidden unselected confirmation cannot grant a reward")
	for dimensions in [Vector2i(2460, 1080), Vector2i(1600, 900), Vector2i(844, 390)]:
		canvas.size = dimensions
		page.size = Vector2(dimensions)
		await settle()
		for index in range(3):
			var before: Array = view.parts.map(func(part): return part.slot.get_global_rect())
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = true
			view.parts[index].panel.gui_input.emit(click)
			await settle()
			check(commands.is_empty(), "Preview never submits a reward %s/%d" % [dimensions, index])
			check(view.parts[index].panel.scale.is_equal_approx(Vector2.ONE * 1.08), "Selected card reaches the reference enlargement %s/%d" % [dimensions, index])
			check(view.parts[index].choose.visible and view.selection_effect.visible, "Selected card exposes confirmation and light %s/%d" % [dimensions, index])
			for other in range(3):
				check(view.parts[other].slot.get_global_rect().is_equal_approx(before[other]), "Selecting never moves its stable card slot")
				if other != index:
					check(not view.parts[other].choose.visible and view.parts[other].panel.scale.is_equal_approx(Vector2.ONE), "Previous card returns to its original scale and hides confirmation")
			var bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
			var selected_rect: Rect2 = view.parts[index].panel.get_global_rect()
			check(bounds.encloses(selected_rect), "Enlarged card stays within the viewport %s/%d" % [dimensions, index])
			check(bounds.encloses(view.parts[index].choose.get_global_rect()), "Confirmation stays visible %s/%d" % [dimensions, index])
			check(view.parts[index].scroll.size.y > 24, "Description remains scrollable %s/%d" % [dimensions, index])
			for other in range(3):
				if other != index: check(not selected_rect.intersects(view.parts[other].panel.get_global_rect()), "Enlarged card never overlaps another card")
		check(view.parts[0].icon.get_node("TalentMark").visible, "Saved talent marker survives changing the preview")
		if rendered:
			await RenderingServer.frame_post_draw
			var lit := canvas.get_texture().get_image()
			lit.save_png("res://reports/character-complete-selected-%dx%d.png" % [dimensions.x, dimensions.y])
			view.selection_effect.hide()
			await RenderingServer.frame_post_draw
			var unlit := canvas.get_texture().get_image()
			var selection_rect: Rect2 = view.parts[2].panel.get_global_rect()
			var pixel_count := 0
			for y in range(maxi(0, int(selection_rect.position.y) - 60), mini(dimensions.y, int(selection_rect.end.y) + 50), 3):
				for x in range(maxi(0, int(selection_rect.position.x) - 50), mini(dimensions.x, int(selection_rect.end.x) + 50), 3):
					if selection_rect.has_point(Vector2(x, y)): continue
					var on := lit.get_pixel(x, y)
					var off := unlit.get_pixel(x, y)
					if on.b > off.b + 0.035 and on.b > on.r: pixel_count += 1
			check(pixel_count > 35, "Rendered blue-white light is visibly present outside the card %s (%d pixels)" % [dimensions, pixel_count])
			view.selection_effect.show()
			await create_timer(0.2).timeout
			await RenderingServer.frame_post_draw
			var animated := canvas.get_texture().get_image()
			check(lit.get_data() != animated.get_data(), "Selection light and source stars animate %s" % dimensions)
	view.parts[2].choose.pressed.emit()
	view.parts[2].choose.pressed.emit()
	check(commands == [["choose_talent", 113, "selection-proof"]], "Repeated confirmation emits the exact selected reward only once")
	view._select(0)
	check(view.selected == 2, "A submitted choice cannot change while completion is pending")
	page.queue_free()
	canvas.queue_free()
	await process_frame
	var report := {"checks": checks, "failures": failures, "rendered": rendered, "passed": failures.is_empty()}
	var file := FileAccess.open("res://reports/character-complete-selection.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("CHARACTER_COMPLETE_SELECTION ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
