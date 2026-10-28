extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr(message)

func _run() -> void:
	var canvas := SubViewport.new()
	canvas.size = Vector2i(2460, 1080)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var page := DungeonMenuPage.new()
	page.theme = DungeonStyle.theme()
	canvas.add_child(page)
	var catalog := DungeonCatalog.new()
	check(catalog.load_all(), "Catalog loads")
	var event: Dictionary = catalog.find("AdvantureEventData", 105)
	var choice: Dictionary = event.TypeData.GambleOptionList[0]
	var commands: Array = []
	page.command.connect(func(kind, id, extra): commands.append([kind, id, extra]))
	var context := {"room_activity": true, "name": event.Name, "story": event.TypeData.Gamble_StoryText, "icon": event.Icon, "event_type": event.EventType, "magic": 160, "search": 0, "search_max": 3, "choices": [{"text": choice.StartGambleText, "action": "event_choice", "id": 1051, "extra": {"key": "event:fixture"}}, {"text": choice.EndGambleText, "action": "event_choice", "id": -1, "extra": {"key": "event:fixture"}}]}
	var rendered := DisplayServer.get_name() != "headless" and "--capture" in OS.get_cmdline_user_args()
	var captured: Array = []
	for dimensions in [Vector2i(2460, 1080), Vector2i(1600, 900), Vector2i(844, 390), Vector2i(390, 844)]:
		canvas.size = dimensions
		page.size = Vector2(dimensions)
		page.display(event.Name, [], "adventure_event", context)
		for frame in 6: await process_frame
		await create_timer(0.35).timeout
		var view = page.adventure_event_view
		check(is_instance_valid(view) and view.is_visible_in_tree(), "Actual event page is displayed " + str(dimensions))
		check(view.illustration.texture != null and view.background.texture != null, "APK artwork is bound " + str(dimensions))
		check(view.story.text.contains("[color=#fdb933]魔镜[/color]") and view.story.text.contains("[color=#fdb933]魔镜魔镜[/color]"), "Story retains the APK mirror keywords and their original color")
		var rich: RichTextLabel = view.choice_buttons[0].get_node("ChoiceText")
		check(rich.text.contains("[img=") and rich.text.contains("[color="), "Choice retains inline currency art and colors")
		var bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
		for control in [view.title_label, view.story_scroll, view.choice_scroll, view.resource_bar]:
			check(bounds.grow(1).encloses(control.get_global_rect()), "Event region stays inside viewport " + str(dimensions))
		check(not view.story_scroll.get_global_rect().intersects(view.choice_scroll.get_global_rect()), "Story and choices do not overlap")
		check(not view.title_label.get_global_rect().intersects(view.resource_bar.get_global_rect()), "Event title clears the currency counters")
		check(not view.back_button.get_global_rect().intersects(view.resource_bar.get_global_rect()), "Back control clears the currency counters")
		for button in view.choice_buttons:
			var text: RichTextLabel = button.get_node("ChoiceText")
			check(text.get_content_height() <= button.size.y - text.position.y + 1, "Choice text fits its clickable surface")
			var paper: NinePatchRect = button.get_node("ChoicePaper")
			check(paper.patch_margin_left == 38 and paper.patch_margin_top == 38 and paper.patch_margin_bottom == 40 and is_equal_approx(paper.scale.x, paper.scale.y), "Choice preserves APK slice borders with uniform corner scale")
		if rendered:
			await RenderingServer.frame_post_draw
			var image := canvas.get_texture().get_image()
			var colors := {}
			for y in range(0, image.get_height(), 20):
				for x in range(0, image.get_width(), 20): colors[image.get_pixel(x, y).to_rgba32()] = true
			check(colors.size() > 100, "Rendered event has nonblank source artwork")
			var paper: NinePatchRect = view.choice_buttons[0].get_node("ChoicePaper")
			var paper_bounds := paper.get_global_rect()
			var edge_y := int(paper_bounds.position.y + 5)
			var center_pixel := image.get_pixel(int(paper_bounds.get_center().x), edge_y)
			for fraction in [0.2, 0.8]:
				var edge_pixel := image.get_pixel(int(paper_bounds.position.x + paper_bounds.size.x * fraction), edge_y)
				check(absf(edge_pixel.r - center_pixel.r) + absf(edge_pixel.g - center_pixel.g) + absf(edge_pixel.b - center_pixel.b) < 0.06, "Option top edge remains straight without stretched oval distortion")
			var path := "res://reports/adventure-event-complete-%dx%d.png" % [dimensions.x, dimensions.y]
			image.save_png(path)
			captured.append(path)
	var view = page.adventure_event_view
	view.choice_buttons[0].pressed.emit()
	view.choice_buttons[0].pressed.emit()
	check(commands.size() == 1 and int(commands[0][1]) == 1051, "Repeated input submits the event choice once")
	var result := {"checks": checks, "failures": failures, "passed": failures.is_empty(), "captures": captured}
	var output := FileAccess.open("res://reports/adventure-event-ui-20261028.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(result, "\t") + "\n")
	print("ADVENTURE_EVENT_UI ", JSON.stringify(result))
	canvas.free()
	quit(0 if failures.is_empty() else 1)
