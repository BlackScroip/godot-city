extends SceneTree

var game: Node
var canvas: SubViewport
var failures: Array[String] = []
var checks := 0
var rendered := false

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("CAMP DIALOGUE FAILURE: " + message)

func settle() -> void:
	for i in 5: await process_frame

func capture(label: String, dimensions: Vector2i) -> void:
	await settle()
	var view = game.hud.page.dialogue_view
	check(is_instance_valid(view), "Dialogue has dedicated view: " + label)
	check(not game.hud.shade.visible and not game.hud.navigation.visible, "Dialogue keeps scene visible and hides navigation")
	check(view.portrait.texture != null, "Original NPC portrait resolves")
	check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(view.text_scroll.get_global_rect()), "Dialogue text fits " + str(dimensions))
	if rendered:
		await RenderingServer.frame_post_draw
		canvas.get_texture().get_image().save_png("res://reports/camp-dialogue-%s-%dx%d.png" % [label, dimensions.x, dimensions.y])

func _run() -> void:
	create_timer(90).timeout.connect(func(): quit(2))
	rendered = "--render-check" in OS.get_cmdline_user_args()
	canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	game = load("res://scripts/main.gd").new()
	game.save_store = DungeonSaveStore.new("/private/tmp/camp-dialogue-flow-%d.json" % Time.get_ticks_usec())
	canvas.add_child(game)
	game.set_process(false)
	game.world.set_physics_process(false)
	game.audio.stop()
	game.systems.grant_material(106, 2)
	await settle()
	for npc in game.catalog.rows("NPCData"):
		var entry = game.catalog.find("NPCFunctionData", game._npc_entry(int(npc.id)))
		check(not entry.is_empty() and int(entry.npc_index) == int(npc.id), "Every resident resolves its original entry: " + str(npc.id))
	game.menus.open("npc", 2200)
	check(game.hud.page._layout == "dialogue", "Resident entry opens story presentation")
	check(int(game.profile.data.dialogue_state.function_id) == 220201, "Source entry priority selects first meeting")
	check(game.world.paused, "Dialogue pauses world input")
	var before = game.systems.stat("npc:executions:220201")
	game._action("talk_skip", 0, 0)
	check(game.systems.stat("npc:executions:220201") == before + 1, "Skip completes source function once")
	check(game.profile.data.dialogue_state.is_empty() and not game.world.paused, "One-time story without next functions exits")
	game._action("talk_next", 0, 0)
	check(game.systems.stat("npc:executions:220201") == before + 1, "Extra taps cannot re-execute finished function")
	game._start_dialogue(220000)
	game._skip_dialogue()
	var persisted = game.save_store.load_profile()
	check(persisted.get("dialogue_state", {}).get("stage", "") == "choices", "Choice stage persists")
	check(not game.systems.npc_function_status(220201).success, "One-time story becomes unavailable")
	var has_build := false
	var has_first := false
	for choice in game.hud.page.page_context.choices:
		if choice.action == "page:buildings": has_build = true
		if int(choice.id) == 220201: has_first = true
	check(not has_build and not has_first, "Source choices omit synthetic services and finished story")
	check(game.hud.page.page_context.text == "嘿！你来了。", "Normal options preserve original greeting")
	game._action("talk_skip", 0, 0)
	check(game.profile.data.dialogue_state.stage == "choices" and game.world.paused, "Skip cannot bypass explicit options")
	check(not game.hud.page.dialogue_view._input_locked, "Skip at options keeps buttons responsive")
	game._close_page()
	game._action("page:buildings", 0, 0)
	check(game.hud.page._layout == "buildings" and game.profile.data.dialogue_state.is_empty(), "Service choice navigates and clears completed conversation")
	game._start_dialogue(220000)
	var greeting_before = game.systems.stat("npc:executions:220000")
	game._close_page()
	check(game.profile.data.dialogue_state.is_empty() and not game.world.paused, "Cancel releases world and discards unfinished story")
	check(game.systems.stat("npc:executions:220000") == greeting_before, "Cancelled story has no completion reward")
	game.profile.data.buildings["2"] = 1
	var reward_npc: Dictionary
	for item in game.world.interactions._items.values():
		if int(item.data.get("NpcId", 0)) == 1000:
			reward_npc = item
			item.state.enabled = true
			game.world.player.position = item.position + Vector3(0, 0, 1.3)
			break
	game.world._event_refresh_at = 0
	game._process(0.0)
	check(game._npc_enter_function(1000) == 100201, "World prompt and opening choose the same authored reward entry")
	check(game.hud.primary.icon == DungeonStyle.texture("sprite_conversation_gift") and game.hud.primary.get_node("Notification").visible, "Pending reward entry has gift icon and attention dot")
	check(game.world._event_markers.has(str(reward_npc.id)) and game.world._event_markers[str(reward_npc.id)].visible, "Pending one-time chat has a world exclamation")
	game._start_dialogue(100000)
	game._skip_dialogue()
	var has_first_gift := false
	for choice in game.hud.page.page_context.choices:
		if int(choice.id) == 100201 and choice.icon == "sprite_conversation_gift": has_first_gift = true
	check(has_first_gift, "Available reward dialogue retains original gift icon")
	game._start_dialogue(100201)
	while not game.profile.data.dialogue_state.is_empty() and game.profile.data.dialogue_state.stage == "story": game._next_dialogue()
	check(game.hud.page.dialogue_view.reward_popup != null, "Normal line-by-line reward completion opens the same receipt")
	game._close_page()
	game.world._event_refresh_at = 0
	game._process(0.0)
	var reward_badge = game.world._event_markers.get(str(reward_npc.get("id", "")))
	check(is_instance_valid(reward_badge) and not reward_badge.visible, "Completed reward entry clears its world exclamation")
	reward_npc.state.enabled = false
	game._action("page:talents", 0, 0)
	check(game.hud.page._layout == "guild", "Guild choice opens actual support tree")
	for item in game.world.interactions._items.values():
		if item.marker.get("Type", "") == "EEUT_NPC" and int(item.data.get("NpcId", 0)) == 2200:
			game.world.player.position = item.position + Vector3(0, 0, 1.3)
			break
	game.world.camp_camera.reset()
	game.world.snap_camera()
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390), Vector2i(2460, 1080)]:
		canvas.size = dimensions
		game.hud._layout()
		game._close_page()
		game._process(0.0)
		await settle()
		check(game.hud.primary.visible and not game.hud.primary.text.is_empty(), "Nearby facility exposes original interaction prompt")
		check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(game.hud.primary.get_global_rect()), "Interaction prompt stays within screen")
		if rendered:
			await RenderingServer.frame_post_draw
			canvas.get_texture().get_image().save_png("res://reports/camp-dialogue-proximity-%dx%d.png" % [dimensions.x, dimensions.y])
		game._start_dialogue(220000)
		await capture("story", dimensions)
		game._skip_dialogue()
		await capture("choices", dimensions)
		check(game.hud.page.dialogue_view.skip_button.visible, "Choice stage retains original top-left skip")
	await _gift_flow()
	game._close_page()
	check(not game.hud.modal_open and not game.world.paused, "Conversation exits cleanly")
	print("Camp dialogue flow checks: %d; failures: %d" % [checks, failures.size()])
	var file = FileAccess.open("res://reports/camp-dialogue-flow-tests.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "rendered": rendered}, "\t"))
	game.queue_free()
	await process_frame
	canvas.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _gift_flow() -> void:
	game._close_page()
	for item in game.world.interactions._items.values():
		if int(item.data.get("NpcId", 0)) == 1300:
			game.world.player.position = item.position + Vector3(0, 0, 1.3)
			break
	game.world.camp_camera.reset()
	game.world.snap_camera()
	var gold = game.systems.material(101)
	game._start_dialogue(130201)
	check(not game.hud.page.dialogue_view.choice_scroll.visible, "One-time reward chat uses story view")
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390), Vector2i(2460, 1080)]:
		canvas.size = dimensions
		game.hud._layout()
		await capture("lottie-reward-story", dimensions)
	game._skip_dialogue()
	check(game.systems.material(101) == gold + 100, "Lottie's first meeting grants exact source reward")
	check(game.profile.data.dialogue_state.is_empty(), "Reward story exits instead of substituting idle greeting")
	check(game.world.paused and game.hud.page.dialogue_view.reward_popup != null, "Reward opens obtained-items popup before resuming camp")
	var popup = game.hud.page.dialogue_view.reward_popup
	check(popup.heading.text == "获得物品" and popup.counts[0].text == "100" and popup.icons[0].texture == DungeonStyle.texture("material:101"), "Popup shows the actual granted material and amount")
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390), Vector2i(2460, 1080)]:
		canvas.size = dimensions
		game.hud._layout()
		await settle()
		check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(popup.heading.get_global_rect()) and Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(popup.slots[0].get_global_rect()), "Reward content fits " + str(dimensions))
		if rendered:
			await RenderingServer.frame_post_draw
			canvas.get_texture().get_image().save_png("res://reports/camp-dialogue-reward-%dx%d.png" % [dimensions.x, dimensions.y])
	game._next_dialogue()
	check(game.systems.material(101) == gold + 100, "Reward cannot be duplicated by stale continuation")
	await create_timer(0.31).timeout
	popup._handle_pointer(Vector2(10, 10), true)
	popup._handle_pointer(Vector2(10, 10), false)
	check(not game.hud.modal_open and not game.world.paused, "Blank-area dismissal resumes camp")
	game._start_dialogue(130000)
	game._skip_dialogue()
	var choices: Array = game.hud.page.page_context.choices
	check(choices.map(func(choice): return int(choice.id)) == [139301, 139101, 139900], "Lottie offers exact APK option order")
	check(choices[0].text == "送礼(金苹果:2)" and choices[0].icon == "sprite_conversation_apple", "Apple option displays owned count and original icon")
	check(game.hud.page.page_context.text == "欢迎来到冒险家公会，想要登记委托？还是想领取奖励？", "Lottie greeting matches supplied reference")
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390), Vector2i(2460, 1080)]:
		canvas.size = dimensions
		game.hud._layout()
		await capture("lottie-choices", dimensions)
	game._action("op:execute_npc_function", 139301, 0)
	check(game.profile.data.dialogue_state.lines.size() == 4, "First gift selects original relationship story")
	check(game.hud.page.page_context.text == "金苹果？谢谢您冒险家大人。", "First gift plays its own authored dialogue")
	check(game.systems.material(106) == 2 and game.systems.stat("relationship:1300") == 0, "Starting gift dialogue does not settle early")
	await capture("lottie-apple-story", canvas.size)
	game._skip_dialogue()
	check(game.systems.material(106) == 1 and game.systems.stat("relationship:1300") == 1, "Gift completion consumes one apple and raises this NPC relationship")
	check(game.systems.stat("talk:139800") == 1 and game.systems.stat("token:50301") == 1, "Source gift talk and relationship token unlock persist")
	check(game.profile.data.dialogue_state.is_empty(), "Gift completion follows original exit path")
	check(game.hud.page.dialogue_view.reward_popup.icons[0].texture == DungeonStyle.texture("material:50301"), "New relationship token receives obtained-items presentation")
	game._close_page()
	game._next_dialogue()
	check(game.systems.material(106) == 1, "Stale gift completion does not spend twice")
	game._start_dialogue(139301)
	check(game.profile.data.dialogue_state.lines == game.dialogue.read_story("talkcfg_npc_139801", 139301 + 1), "Second gift selects next relationship story")
	game._close_page()
	check(game.systems.material(106) == 1 and game.systems.stat("relationship:1300") == 1, "Cancelling gift story spends nothing")
	game.systems.spend({"106": 1})
	game._start_dialogue(130000)
	game._skip_dialogue()
	check(game.hud.page.page_context.choices.map(func(choice): return int(choice.id)) == [139101, 139900], "Empty apple option is hidden before guild level two")
	game._close_page()
	game.profile.data.buildings["2"] = 2
	game._start_dialogue(130000)
	game._skip_dialogue()
	check(game.hud.page.page_context.choices[0].disabled and game.hud.page.page_context.choices[0].text == "送礼(金苹果:0)", "Unlocked empty apple option remains visible and disabled")
	game._start_dialogue(139301)
	check(game.profile.data.dialogue_state.stage == "choices" and not game.hud.page.dialogue_view._input_locked, "Insufficient gifts keep options responsive")
	game._close_page()
	game.systems.grant_material(106, 1)
	game.systems.set_record("relationship:1300", 10)
	game._start_dialogue(130000)
	game._skip_dialogue()
	check(not game.hud.page.dialogue_view.choice_buttons[0].disabled, "Maximum relationship keeps the owned-apple option available")
	game.hud.page.dialogue_view.choice_buttons[0].pressed.emit()
	check(game.profile.data.dialogue_state.stage == "choices" and not game.hud.page.dialogue_view._input_locked and game.systems.material(106) == 1, "Maximum relationship refuses a gift without spending or locking options")
	game._close_page()
	game.systems.set_record("relationship:1300", 1)
	game._start_dialogue(130000)
	game._skip_dialogue()
	game._action("op:execute_npc_function", 139900, 0)
	check(game.hud.page.page_context.text == "感谢您的帮助冒险家大人，祝您此行顺利。", "Goodbye plays original NPC farewell")
	game._skip_dialogue()
	check(game.profile.data.dialogue_state.is_empty() and not game.world.paused, "Farewell exits and releases input")
