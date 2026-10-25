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
	check(game.profile.data.dialogue_state.stage == "choices", "Completion opens source choices")
	game._action("talk_skip", 0, 0)
	game._action("talk_next", 0, 0)
	check(game.systems.stat("npc:executions:220201") == before + 1, "Extra taps cannot re-execute finished function")
	var persisted = game.save_store.load_profile()
	check(persisted.get("dialogue_state", {}).get("stage", "") == "choices", "Choice stage persists")
	check(not game.systems.npc_function_status(220201).success, "One-time story becomes unavailable")
	var has_build := false
	var has_first := false
	for choice in game.hud.page.page_context.choices:
		if choice.action == "page:buildings": has_build = true
		if int(choice.id) == 220201: has_first = true
	check(has_build and not has_first, "Architect exposes construction and removes finished option")
	game._action("page:buildings", 0, 0)
	check(game.hud.page._layout == "buildings" and game.profile.data.dialogue_state.is_empty(), "Service choice navigates and clears completed conversation")
	game._start_dialogue(220000)
	var greeting_before = game.systems.stat("npc:executions:220000")
	game._close_page()
	check(game.profile.data.dialogue_state.is_empty() and not game.world.paused, "Cancel releases world and discards unfinished story")
	check(game.systems.stat("npc:executions:220000") == greeting_before, "Cancelled story has no completion reward")
	game.profile.data.buildings["2"] = 1
	game._start_dialogue(100000)
	game._skip_dialogue()
	var has_guild := false
	for choice in game.hud.page.page_context.choices:
		if choice.action == "page:talents": has_guild = true
	check(has_guild, "Luna links to guild support")
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
		check(not game.hud.page.dialogue_view.skip_button.visible, "Choice stage hides story skip")
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
