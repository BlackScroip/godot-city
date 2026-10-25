extends SceneTree

var failures: Array[String] = []
var checks := 0
var save_path := "/private/tmp/loot-flow-%d.json" % Time.get_ticks_usec()
var canvas: SubViewport

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func make_game() -> Node:
	var game = load("res://scenes/main.tscn").instantiate()
	game.save_store = DungeonSaveStore.new(save_path)
	canvas.add_child(game)
	game.world.set_physics_process(false)
	game.world.presentation.audio_enabled = false
	game.audio.stop()
	game.set_process(false)
	return game

func _run() -> void:
	canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var game = make_game()
	game.hud.close_page()
	game._primary()
	var id := int(game.campaign.choices()[0].node_id)
	game._select_node(id)
	check(game._transitioning and game.room_loading.visible, "Selecting a level immediately shows loading and guards transitions")
	game._select_node(id)
	check(game.campaign.state.phase == "route", "Duplicate selection cannot enter before async preload")
	var started := Time.get_ticks_msec()
	while game._transitioning and Time.get_ticks_msec() - started < 20000:
		await process_frame
	check(not game._transitioning and not game.room_loading.visible, "Async transition finishes and hides loading")
	check(game.campaign.state.phase == "room" and int(game.campaign.state.current_node_id) == id, "Async transition enters selected room exactly once")
	game.hud.close_page()
	game.world.ground_loot.spawn(13103, game.world.player.position)
	game._interact()
	var reward: Dictionary = game.systems.pending_character_talent_reward()
	check(game.world.ground_loot.entries.is_empty(), "Picking scroll consumes ground object")
	check(game.hud.modal_open and reward.get("choices", []).size() == 3, "Scroll opens persisted three-choice talent modal")
	check(str(reward.get("quality", "")) == "High", "Legendary scroll preserves quality")
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390)]:
		canvas.size = dimensions
		await process_frame
		await process_frame
		await process_frame
		for part in game.hud.page.special.altar_parts:
			check(part.scroll.size.y >= 55.0, "Talent description remains readable at %s" % dimensions)
			check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(part.panel.get_global_rect()), "Talent card fits viewport at %s" % dimensions)
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			canvas.get_texture().get_image().save_png("res://reports/talent-choice-%dx%d.png" % [dimensions.x, dimensions.y])
	if not reward.is_empty():
		var talent_id := int(reward.choices[0])
		var level := int(reward.levels[str(talent_id)])
		game._action("choose_talent", talent_id, str(reward.key))
		check(int(game.profile.data.run.talents.get(str(talent_id), 0)) == level, "Choice applies advertised talent level to this run")
		check(game.systems.pending_character_talent_reward().is_empty() and not game.hud.modal_open, "Choice is consumed once and closes modal")
		game._action("choose_talent", talent_id, str(reward.key))
		check(int(game.profile.data.run.talents.get(str(talent_id), 0)) == level, "Repeated choice cannot grant extra levels")
	game._finish_noncombat()
	var gold := int(game.systems.material(101))
	var magic := int(game.systems.material(102))
	game.world.ground_loot.spawn(101, game.world.player.position + Vector3(20, 0, 0), 17, true)
	game.world.ground_loot.spawn(102, game.world.player.position + Vector3(18, 0, 0), 5, true)
	game.world.ground_loot.spawn(20103, game.world.player.position + Vector3(15, 0, 0))
	game._environment_action("transition", {})
	check(game.campaign.state.phase == "reward" and game.hud.page.title_label.text == "确认离开", "Unclaimed room items require leave confirmation")
	check(int(game.systems.material(101)) == gold, "Coins are not settled before leave confirmation")
	game._action("close_page", 0, 0)
	check(game.campaign.state.phase == "reward" and not game.hud.modal_open, "Cancelling leave keeps player in completed room")
	game._environment_action("transition", {})
	game._action("leave_unclaimed", 0, 0)
	check(game.campaign.state.phase == "route" and game.hud.modal_open, "Confirmed room portal opens route directly")
	check(int(game.systems.material(101)) == gold + 17, "Portal settles attracted coins before leaving")
	check(int(game.systems.material(102)) == magic + 5, "Portal settles remaining magic material")
	game._action("close_page", 0, 0)
	game._environment_action("transition", {})
	check(game.campaign.state.phase == "route" and game.hud.modal_open and game.hud.page._layout == "route", "Portal reopens route after route page is closed")
	check(int(game.systems.material(101)) == gold + 17, "Reopening route does not grant settled coins again")
	game.world.ground_loot.clear()
	for item in game.world.interactions._items.values():
		if str(item.marker.get("Type", "")) == "EEUT_AbilityItemTreasureBox": item.state.opened = true
	game.campaign.generate(9127, 0)
	for layer_index in game.campaign.state.layers.size() - 1:
		var layer: Dictionary = game.campaign.state.layers[layer_index]
		var next_layer: Dictionary = game.campaign.state.layers[layer_index + 1]
		if int(next_layer.region) > int(layer.region):
			game.campaign.state.layer_index = layer_index
			game.campaign.state.current_node_id = int(layer.node_ids[0])
			layer.selected_id = int(layer.node_ids[0])
			game.campaign.state.phase = "reward"
			var entrance_id := int(next_layer.node_ids[0])
			game._environment_action("transition", {})
			check(game._transitioning and game.room_loading.visible, "Chapter portal starts loading next chapter entrance")
			started = Time.get_ticks_msec()
			while game._transitioning and Time.get_ticks_msec() - started < 20000:
				await process_frame
			check(game.campaign.state.phase == "room" and int(game.campaign.state.current_node_id) == entrance_id, "Chapter portal enters next chapter entrance without route detour")
			break
	var combat_id := 0
	for node in game.campaign.database.Nodes:
		if str(node.Flow) == "Boss":
			combat_id = int(node.Id)
			break
	game.campaign.start_practice(combat_id, 9127)
	game._load_room()
	game.world.set_physics_process(false)
	for item in game.world.interactions._items.values():
		if str(item.marker.get("Type", "")) in ["EEUT_StageChangeDoor", "EEUT_Protal"]:
			check(not item.state.enabled, "Combat portal interaction stays disabled")
	game._environment_action("transition", {})
	check(game.campaign.state.phase == "room", "Combat blocks portal transition")
	game.campaign.state.waves_cleared = game.campaign.state.wave_count
	game._finish_room()
	check(game.campaign.state.phase == "reward", "Cleared boss waits in reward room")
	for item in game.world.interactions._items.values():
		if str(item.marker.get("Type", "")) in ["EEUT_StageChangeDoor", "EEUT_Protal"]:
			check(item.state.enabled, "Clearing the room enables portal interaction")
	game.world.ground_loot.clear()
	game.world.ground_loot.spawn(20103, game.world.player.position + Vector3(1, 0, 0))
	game._save(true)
	game.queue_free()
	await process_frame
	game = make_game()
	check(game.campaign.state.phase == "reward", "Save reload restores completed-room phase")
	check(game.world.ground_loot.entries.size() == 1, "Completed-room reload retains ground loot")
	var enemies := 0
	for actor in game.world.actors:
		if not actor.is_player: enemies += 1
	check(enemies == 0 and not game.world.fighting, "Completed-room reload does not respawn enemies")
	gold = int(game.systems.material(101))
	game.world.ground_loot.spawn(101, game.world.player.position + Vector3(20, 0, 0), 9, true)
	game._environment_action("transition", {})
	check(game.campaign.state.phase == "reward" and game.hud.page.title_label.text == "确认离开", "Final portal warns about restored unclaimed relic")
	game._action("close_page", 0, 0)
	check(game.campaign.state.phase == "reward" and int(game.systems.material(101)) == gold, "Cancelling final exit keeps room and pending coins")
	game._environment_action("transition", {})
	game._action("leave_unclaimed", 0, 0)
	check(game.campaign.state.phase == "won" and not game.profile.data.run.active and game.profile.data.run.outcome.stage == "share", "Final portal completes run and opens victory presentation")
	check(int(game.systems.material(101)) == gold + 9, "Confirmed final exit settles remaining coins once")
	game._action("result_next", 0, 0)
	game._action("result_next", 0, 0)
	game._action("result_camp", 0, 0)
	check(not game._flow_locked() and not game.hud.modal_open, "Victory settlement returns to camp before a new adventure")
	game.systems.begin_run(9128, game.selected_character, 100, 0)
	check(game.profile.data.run.talents.is_empty(), "Temporary talent upgrades do not survive a new run")
	game.queue_free()
	await process_frame
	print("LOOT_FLOW_TEST ", JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
