extends SceneTree

const Dialogue = preload("res://scripts/presentation/dialogue_page.gd")

var checks = 0
var failures: Array[String] = []
var commands: Array = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _run() -> void:
	var viewport = SubViewport.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.size = Vector2i(1600, 900)
	root.add_child(viewport)
	var background = DungeonStyle.picture("res://reports/camp-restored-1600x900.png", Vector2.ZERO)
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(background)
	var page = _page(viewport, {"speaker": "阿尔托", "text": "欢迎回来，冒险家！\n公会的新设施已经准备好了。收集材料、修复营地，大家就能一起踏上新的旅程。", "portrait": "characterillustration_jianzhu_normal"})
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390), Vector2i(2460, 1080)]:
		viewport.size = dimensions
		page.size = Vector2(dimensions)
		for frame in 6: await process_frame
		check(page.portrait.texture != null, "original NPC portrait loads %s" % dimensions)
		check(page.portrait.position.y < 0 and page.portrait.get_rect().end.y > page.size.y, "source portrait fills left side with lower body cropped %s" % dimensions)
		check(page.get_rect().encloses(page.text_scroll.get_rect()), "dialogue text stays within viewport %s" % dimensions)
		check(page.text_scroll.size.y >= 55, "dialogue remains readable in short landscape %s" % dimensions)
		check(page.dialogue_band.position.y >= page.size.y * 0.5, "scene remains unobscured above lower dialogue strip %s" % dimensions)
		check(page.get_rect().encloses(page.skip_button.get_rect()) and page.get_rect().encloses(page.next_button.get_rect()), "skip and next remain reachable %s" % dimensions)
		await _capture(viewport, "line", dimensions)
	_mouse(page, Vector2(900, 400), true)
	_mouse(page, Vector2(1000, 400), false)
	check(commands.is_empty(), "dragging does not advance dialogue")
	_mouse(page, Vector2(900, 400), true)
	_mouse(page, Vector2(900, 400), false)
	check(commands == [["talk_next", 0, 0]], "body release advances once")
	page.next_button.pressed.emit()
	check(commands.size() == 1, "duplicate click cannot skip a second line")
	page.queue_free()
	await process_frame
	page = _page(viewport, {"speaker": "洛蒂", "text": "欢迎来到冒险家公会，想要登记委托？还是想领取奖励？", "portrait": "characterillustration_renwu_normal", "show_relationship": true, "relationship": 3, "choices": [{"text": "送礼(金苹果:1)", "icon": "sprite_conversation_apple", "action": "op:execute_npc_function", "id": 139301}, {"text": "闲聊。", "icon": "sprite_conversation_talk", "action": "op:execute_npc_function", "id": 139101}, {"text": "再见。", "icon": "sprite_conversation_talk", "action": "op:execute_npc_function", "id": 139900}]})
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390), Vector2i(2460, 1080)]:
		viewport.size = dimensions
		page.size = Vector2(dimensions)
		for frame in 6: await process_frame
		check(not page.next_button.visible and page.choice_scroll.visible, "choices replace continue arrow %s" % dimensions)
		check(page.get_rect().encloses(page.choice_scroll.get_rect()), "choices stay inside scene %s" % dimensions)
		check(page.choice_scroll.get_rect().end.y <= page.dialogue_band.position.y, "choices do not cover current dialogue %s" % dimensions)
		check(page.choice_scroll.size.y >= 100, "choices remain reachable at compact height %s" % dimensions)
		check(page.relationship_label.visible and page.relationship_label.text == "3", "current NPC relationship displays %s" % dimensions)
		check(page.get_rect().encloses(page.relationship_icon.get_rect()), "relationship heart stays within screen %s" % dimensions)
		for button in page.choice_buttons:
			check(button.icon != null, "source choice icon resolves %s" % dimensions)
		await _capture(viewport, "choices", dimensions)
	_mouse(page, Vector2(900, 400), true)
	_mouse(page, Vector2(900, 400), false)
	check(commands.size() == 1, "background taps cannot bypass explicit choices")
	page.skip_button.pressed.emit()
	check(commands.back() == ["talk_skip", 0, 0] and not page._input_locked and not page.choice_buttons[1].disabled, "skip at choices preserves responsive options")
	page.choice_buttons[1].pressed.emit()
	check(commands.back() == ["op:execute_npc_function", 139101, 0], "NPC option preserves exact source function")
	page.queue_free()
	await process_frame
	page = _page(viewport, {"speaker": "阿尔托", "text": "继续冒险吧。", "portrait": "characterillustration_jianzhu_normal"})
	page.skip_button.pressed.emit()
	check(commands.back() == ["talk_skip", 0, 0], "skip emits dialogue skip")
	page.queue_free()
	await process_frame
	page = _page(viewport, {"rewards": [{"name": "金币", "icon": "material:101", "count": 100}]})
	var popup = page.reward_popup
	popup._handle_pointer(Vector2(10, 10), true)
	popup._handle_pointer(Vector2(10, 10), false)
	check(not popup._closed, "reward popup ignores the opening tap")
	await create_timer(0.31).timeout
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390), Vector2i(2460, 1080)]:
		viewport.size = dimensions
		page.size = Vector2(dimensions)
		for frame in 6: await process_frame
		check(popup.icons[0].texture != null and popup.counts[0].text == "100", "reward icon and count resolve %s" % dimensions)
		check(page.get_rect().encloses(popup.close_hint.get_rect()), "reward close hint fits %s" % dimensions)
		var item_center: Vector2 = popup.slots[0].get_rect().get_center()
		popup._handle_pointer(item_center, true)
		popup._handle_pointer(item_center, false)
		check(not popup._closed, "item tap does not dismiss reward %s" % dimensions)
		await _capture(viewport, "reward", dimensions)
	popup._handle_pointer(Vector2(10, 10), true)
	popup._handle_pointer(Vector2(10, 10), false)
	check(commands.back() == ["talk_reward_close", 0, 0], "blank tap dismisses reward popup")
	var count_before := commands.size()
	popup._handle_pointer(Vector2(10, 10), true)
	popup._handle_pointer(Vector2(10, 10), false)
	check(commands.size() == count_before, "reward dismissal emits once")
	viewport.queue_free()
	await process_frame
	var result = {"checks": checks, "failures": failures, "passed": failures.is_empty()}
	print("DIALOGUE_PAGE_TEST ", JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)

func _page(viewport: SubViewport, context: Dictionary):
	var page = Dialogue.new()
	page.theme = DungeonStyle.theme()
	page.size = Vector2(viewport.size)
	viewport.add_child(page)
	page.command.connect(func(kind, id, extra): commands.append([kind, id, extra]))
	page.configure(null, [], context)
	return page

func _mouse(page, point: Vector2, down: bool) -> void:
	var event = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.pressed = down
	page._gui_input(event)

func _capture(viewport: SubViewport, mode: String, dimensions: Vector2i) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var picture = viewport.get_texture().get_image()
	check(not picture.is_empty(), "dialogue screenshot renders")
	picture.save_png("/private/tmp/camp-dialogue-%s-%dx%d.png" % [mode, dimensions.x, dimensions.y])
