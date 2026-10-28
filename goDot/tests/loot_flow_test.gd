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

func wait_transition(game: Node) -> void:
	var started := Time.get_ticks_msec()
	while game._transitioning and Time.get_ticks_msec() - started < 20000:
		await process_frame
	check(not game._transitioning, "Portal animation and loading finish")

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
	check(game.campaign.state.region_selection and game.hud.page.route_view.context.map_scope == "world", "New adventure opens world selection before entering a room")
	var id := int(game.campaign.state.layers[0].node_ids[0])
	var regions: Array = game.campaign.region_choices()
	check(not regions.is_empty(), "World map exposes a reachable source slot")
	if not regions.is_empty(): game._action("select_region", int(regions[0].node_id), 0)
	check(game._transitioning and game.world.player_transfer.active, "Selecting a level plays departure and guards transitions")
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
	game.world.ground_loot.spawn_altar(game.world.player.position + Vector3(16, 0, 0), "altar:leave-prompt-test")
	var pending_altar_key: String = "altar:" + game._room_key + ":pending-test"
	game.systems.create_loot_reward(30301, pending_altar_key, 3)
	game.profile.data.run.counters["SelectLootRemainCount_Sprites"] = 1
	game._environment_action("transition", {})
	check(game.campaign.state.phase == "reward" and game.hud.page.title_label.text == "确认离开", "Unclaimed room items require leave confirmation")
	check(game.hud.page._layout == "unclaimed" and game.hud.page.unclaimed_view != null, "Unclaimed room rewards use the dedicated prompt")
	var pending_rows: Array = game.hud.page._rows
	check(pending_rows.any(func(row): return row.title == "精灵祭坛" and int(row.count) == 2), "Generated and pending altars are listed separately from loot")
	check(pending_rows.any(func(row): return row.title == "未拾取的物品" and int(row.count) == 1), "Altar does not inflate the ground item count")
	check(int(game.systems.material(101)) == gold, "Coins are not settled before leave confirmation")
	game.hud.page.unclaimed_view.return_button.pressed.emit()
	check(game.campaign.state.phase == "reward" and not game.hud.modal_open, "Cancelling leave keeps player in completed room")
	check(game.world.ground_loot.entries.size() == 4, "Returning preserves every ground reward")
	var source_altar = {"source_item": {"state": {"enabled": true, "used": false, "broken": false}}}
	game.world.ground_loot.source_altars.append(source_altar)
	game._environment_action("transition", {})
	check(game.hud.page._rows.any(func(row): return row.title == "精灵祭坛" and int(row.count) == 3), "Available source altar is included once")
	source_altar.source_item.state.used = true
	game._environment_action("transition", {})
	check(game.hud.page._rows.any(func(row): return row.title == "精灵祭坛" and int(row.count) == 2), "Claimed source altar is excluded")
	source_altar.source_item.state.used = false
	source_altar.source_item.state.enabled = false
	game._environment_action("transition", {})
	check(game.hud.page._rows.any(func(row): return row.title == "精灵祭坛" and int(row.count) == 2), "Inactive source altar is excluded")
	game.world.ground_loot.source_altars.erase(source_altar)
	game._environment_action("transition", {})
	if DisplayServer.get_name() != "headless":
		for frame in 8: await process_frame
		await RenderingServer.frame_post_draw
		canvas.get_texture().get_image().save_png("/private/tmp/unclaimed-in-game.png")
	game.hud.page.unclaimed_view.continue_button.pressed.emit()
	await wait_transition(game)
	check(game.campaign.state.phase == "route" and game.hud.modal_open, "Confirmed room portal opens route directly")
	check(not game.profile.data.run.rewards.any(func(reward): return str(reward.key) == pending_altar_key) and int(game.profile.data.run.counters.get("SelectLootRemainCount_Sprites", -1)) == 0, "Confirmed exit discards pending altar choice and counter")
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
	regions = game.campaign.region_choices()
	check(not regions.is_empty() and game.campaign.select_region(int(regions[0].node_id)).success, "Chapter exit fixture begins in a confirmed region")
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
			check(game._transitioning and game.world.player_transfer.active, "Chapter portal plays departure before world selection")
			started = Time.get_ticks_msec()
			while game._transitioning and Time.get_ticks_msec() - started < 20000:
				await process_frame
			check(game.campaign.state.phase == "route" and game.campaign.state.region_selection and int(game.campaign.state.current_node_id) == 0, "Chapter portal waits for world confirmation before entering the next entrance")
			check(game.hud.modal_open and game.hud.page.route_view.context.map_scope == "world", "Chapter portal displays the world map")
			regions = game.campaign.region_choices()
			for region in regions:
				if int(region.region) == int(next_layer.region):
					game._action("select_region", int(region.node_id), 0)
					break
			await wait_transition(game)
			check(game.campaign.state.phase == "room" and int(game.campaign.state.current_node_id) == entrance_id, "World confirmation enters the selected next chapter entrance")
			break
	var combat_id := 0
	for node in game.campaign.database.Nodes:
		if str(node.Flow) == "Boss":
			combat_id = int(node.Id)
			break
	game.campaign.start_practice(combat_id, 9127)
	game._load_room()
	await wait_transition(game)
	game.world.set_physics_process(false)
	for item in game.world.interactions._items.values():
		if str(item.marker.get("Type", "")) in ["EEUT_StageChangeDoor", "EEUT_Protal"]:
			check(not item.state.enabled, "Combat portal interaction stays disabled")
	game._environment_action("transition", {})
	check(game.campaign.state.phase == "room", "Combat blocks portal transition")
	game.campaign.state.waves_cleared = game.campaign.state.wave_count
	game.world.begin_room_clear()
	game.world._tick_room_sequence(1.0)
	game.world._tick_room_sequence(1.0)
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
	await wait_transition(game)
	check(game.campaign.state.phase == "won" and not game.profile.data.run.active and game.profile.data.run.outcome.stage == "share", "Final portal completes run and opens victory presentation")
	check(int(game.systems.material(101)) == gold + 9, "Confirmed final exit settles remaining coins once")
	game._action("result_next", 0, 0)
	game._action("result_next", 0, 0)
	game._action("result_camp", 0, 0)
	await wait_transition(game)
	check(not game._flow_locked() and not game.hud.modal_open, "Victory settlement returns to camp before a new adventure")
	game.systems.begin_run(9128, game.selected_character, 100, 0)
	check(game.profile.data.run.talents.is_empty(), "Temporary talent upgrades do not survive a new run")
	game.queue_free()
	await process_frame
	print("LOOT_FLOW_TEST ", JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
