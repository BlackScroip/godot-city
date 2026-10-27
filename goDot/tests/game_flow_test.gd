extends SceneTree

var failures: Array[String] = []
var checks := 0
var game: Node
var canvas: SubViewport
var save_path := ""
var render_check := false

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FLOW FAILURE: " + message)

func _wait_transition() -> void:
	var deadline = Time.get_ticks_msec() + 60000
	while game._transitioning and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not game._transitioning, "Transition finishes within 60 seconds")
	await process_frame
	game.set_process(false)
	game.world.set_physics_process(false)

func _start() -> void:
	game._primary()
	var regions: Array = game.campaign.region_choices()
	check(not regions.is_empty() and game.campaign.state.region_selection, "New adventure waits for world region confirmation")
	if not regions.is_empty(): game._select_region(int(regions[0].node_id))
	await _wait_transition()
	if game.world.room_stage == "opening": game.world._physics_process(game.world._room_stage_wait)
	check(game.profile.data.run.active and game.campaign.state.get("phase") == "room", "World confirmation enters first room")
	check(game.campaign.current_room().get("flow") == "Entrance", "First room is chapter entrance")
	check(not game.hud.modal_open, "First room does not require route selection")
	check(game.hud.skill_cluster.visible and not game.hud.skill_by_slot[0].disabled, "Entering an adventure restores combat controls")
	check(not game.hud.navigation_buttons.menu_adventure.visible and game.hud.navigation_buttons.menu_difficulty.visible, "Adventure navigation replaces start adventure with difficulty")

func _combat_room() -> void:
	for node in game.campaign.database.Nodes:
		if node.Flow == "Battle" and int(node.MinDifficulty) == 0:
			game.campaign.start_practice(int(node.Id), 12345)
			game._load_room()
			await _wait_transition()
			for item in game.world.interactions._items.values():
				if item.marker.Type == "EEUT_PlayerTrigger" and int(item.data.get("TriggerId", -1)) == 1:
					var collider: Dictionary = item.colliders[0]
					var point: Vector3 = game.world.interactions._matrix(collider.world_matrix) * game.world.interactions._vector(collider.properties.get("m_Center", {}))
					game.world.player.position = game.world.interactions._world_position(point) - Vector3.UP * 0.8
					game.world.interactions.tick(0.02, game.world.player.position)
					break
			game._save(true)
			check(game.world._enemy_count() > 0, "Combat fixture has live enemies")
			return
	check(false, "Combat fixture exists")

func _die() -> void:
	game.world.player.combat.health = 0
	game.profile.data.run.health = 0
	game.world._die(game.world.player)
	check(game._death_pending and game._flow_locked(), "Death locks flow immediately")

func _seed_run_items() -> void:
	game.profile.data.run.inventory["11001"] = 1
	game.profile.data.run.talents["101"] = 1
	game.profile.data.run["region_rewards"] = [{"AttributeType": "AtkAddFixed", "Value": 10}]
	game.systems.grant_material(102, 27)
	game.systems.grant_material(103, 3)
	game.systems.grant_material(801, 1)

func _return_to_camp() -> void:
	var outcome: Dictionary = game.profile.data.run.outcome.duplicate(true)
	var player_id: int = game.world.player.get_instance_id()
	if render_check:
		canvas.size = Vector2i(1600, 900) if outcome.victory else Vector2i(844, 390)
		game.hud._layout()
	game._action("result_camp", 0, 0)
	check(game._transitioning and game.room_loading.visible and game.world.paused, "Return to camp immediately shows loading and pauses gameplay")
	check(game.room_loading.destination == "营地" and game.room_loading.progress_bar.value == 0, "Camp loading starts with fresh destination and progress")
	check(game.world.player.get_instance_id() == player_id and game.profile.data.run.outcome == outcome, "Loading appears before camp replaces the result and player")
	game._action("result_camp", 0, 0)
	game._action("close_page", 0, 0)
	check(game._transitioning and game.room_loading.visible and game.profile.data.run.outcome == outcome, "Repeated return and close actions cannot interrupt camp loading")
	if render_check and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		check(game.room_loading.visible, "Loading stays visible for its first rendered frame")
		var frame: Image = canvas.get_texture().get_image()
		check(not frame.is_empty(), "Camp loading renders pixels")
		frame.save_png("/private/tmp/settlement-camp-loading-%s-%dx%d.png" % ["victory" if outcome.victory else "death", canvas.size.x, canvas.size.y])
	await _wait_transition()
	check(not game.room_loading.visible and game.room_loading.progress_bar.value == 100, "Camp hides loading only after reaching completion")
	check(game.world._camp_camera and is_instance_valid(game.world.player) and not game.world.paused, "Loading finishes in a playable camp")
	check(game.hud.skill_cluster.visible and not game.hud.skill_by_slot[0].disabled, "Returning to camp retains usable combat controls")
	check(game.hud.navigation_buttons.menu_adventure.visible and not game.hud.navigation_buttons.menu_difficulty.visible, "Returning to camp restores start adventure")
	check(not game.world.presentation.has_pending_preparation(), "Camp player resources are ready before loading closes")

func _check_camp_cleanup(vouchers: int, minerals: int) -> void:
	check(game.profile.data.run == DungeonProfile.new_run(), "Return to camp clears temporary items, talents, counters, route and battle")
	check(game.systems.material(102) == 0, "Return to camp clears remaining magic")
	check(game.systems.material(501) == vouchers and game.systems.material(103) == minerals, "Return to camp preserves vouchers and collected minerals")
	game.menus.open("inventory")
	check(game.hud.page._rows.all(func(row): return int(row.get("loot_id", 0)) == 0), "Camp inventory has no previous adventure relics")
	game.menus.open("storage")
	check(game.hud.page._rows.any(func(row): return int(row.get("material_id", 0)) == 801), "Camp inventory retains permanent material boxes")
	game._close_page()
	var saved: Dictionary = game.save_store.load_profile()
	check(not saved.is_empty() and saved.run.inventory.is_empty() and saved.run.talents.is_empty() and saved.run.battle.is_empty() and int(saved.materials.get("102", 0)) == 0, "Camp cleanup is persisted to disk")
	game.profile.data = saved
	game._restore_flow()
	check(game.profile.data.run == DungeonProfile.new_run() and not game.hud.modal_open, "Camp reload keeps temporary inventory empty")

func _verify_blocked_close(message: String) -> void:
	game._action("close_page", 0, 0)
	check(game.hud.modal_open, message + " ignores close action")
	var event = InputEventKey.new()
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	game._unhandled_input(event)
	check(game.hud.modal_open, message + " ignores Escape")

func _render_outcome() -> void:
	if not render_check: return
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390)]:
		canvas.size = dimensions
		game.hud._layout()
		await process_frame
		await process_frame
		var outcome = game.hud.page.outcome_view
		check(is_instance_valid(outcome), "Outcome view exists at %s" % dimensions)
		if not is_instance_valid(outcome): continue
		check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(outcome.stage.get_global_rect()), "Outcome content fits %s" % dimensions)
		check(outcome.confirm.get_global_rect().end.y <= dimensions.y, "Outcome confirmation fits %s" % dimensions)
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var frame: Image = canvas.get_texture().get_image()
			check(not frame.is_empty(), "Outcome produces rendered pixels")
			frame.save_png("/private/tmp/game-flow-%dx%d.png" % [dimensions.x, dimensions.y])

func _run() -> void:
	render_check = "--render-check" in OS.get_cmdline_user_args()
	save_path = "/private/tmp/game-flow-%d.json" % Time.get_ticks_usec()
	canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	game = load("res://scripts/main.gd").new()
	game.save_store = load("res://scripts/save_store.gd").new(save_path)
	canvas.add_child(game)
	game.set_process(false)
	game.world.set_physics_process(false)
	game.audio.stop()
	await process_frame
	check(not game.profile.data.run.active, "Fresh private save starts in camp")
	await _start()
	var entrance_id = game.campaign.state.current_node_id
	game._action("map", 0, 0)
	check(game.hud.modal_open and game.hud.page._layout == "route", "Map opens room preview")
	check(game.hud.page._rows.all(func(row): return not bool(row.get("available", false))), "Preview has no selectable routes")
	var another_id = game.campaign.state.layers[1].node_ids[0]
	game._action("enter_node", another_id, 0)
	check(game.campaign.state.current_node_id == entrance_id and not game._transitioning, "Map preview cannot skip room")
	game._action("map", 0, 0)
	check(not game.hud.modal_open and not game.world.paused, "Map toggle closes preview and restores room")
	game.world.player.combat.health = 37
	game.world.player.combat.armor = 9
	game.profile.data.run.health = 37
	game.profile.data.run.armor = 9
	game._environment_action("transition", {})
	if game.campaign.state.phase == "reward" and game.hud.modal_open:
		game._action("leave_unclaimed", 0, 0)
	await _wait_transition()
	check(game.campaign.state.phase == "route", "Exit gate advances completed entrance to route")
	check(game.hud.modal_open and game.hud.page._layout == "route", "Exit gate opens route selection")
	game._save(true)
	var saved = game.save_store.load_profile()
	check(not saved.is_empty(), "Route save validates")
	if saved.is_empty():
		_finish()
		return
	game.profile.data = saved
	game._restore_flow()
	await _wait_transition()
	check(is_equal_approx(game.world.player.combat.health, 37) and is_equal_approx(game.world.player.combat.armor, 9), "Route reload preserves life and armor")
	check(game.campaign.state.phase == "route" and game.hud.modal_open, "Route reload restores selection")
	await _combat_room()
	game.profile.data.run.counters["RevivalRemainCount"] = 1
	var enemies = game.world._enemy_count()
	var enemy_ids: Array = game.world.actors.filter(func(actor): return not actor.is_player).map(func(actor): return actor.get_instance_id())
	var maximum: float = game.world.player.combat.max_health
	game.world.player.combat.busy = 3.0
	game.world.player.combat.current_action = "old_attack"
	_die()
	_verify_blocked_close("Revival")
	game._tick_death(1.5)
	check(game._revival_stage == 1 and game.world.player.dead, "Revival first delay keeps actor down")
	game._tick_death(1.01)
	check(not game.world.player.dead and game._revival_stage == 2, "Revival restores actor after second delay")
	check(is_equal_approx(game.world.player.combat.health, maximum * 0.3), "Revival restores 30 percent life")
	check(game.world.player.combat.busy == 0 and game.world.player.combat.current_action.is_empty(), "Revival clears the interrupted attack")
	check(is_equal_approx(game.world.player.invulnerability, 1.0), "Revival grants one second protection")
	check(game.systems.revival_count() == 0 and int(game.profile.data.run.counters.get("revivals:used", 0)) == 1, "Revival consumes exactly one count")
	check(game.world._enemy_count() == enemies and enemy_ids == game.world.actors.filter(func(actor): return not actor.is_player).map(func(actor): return actor.get_instance_id()), "Revival preserves existing enemy actors")
	game._tick_death(1.5)
	check(game.world.player_revival.active and game._flow_locked(), "Revival presentation holds input for its authored duration")
	game.world.player_revival.advance(game.world.player_revival.duration)
	game._tick_death(10)
	check(not game._flow_locked() and not game.hud.modal_open and not game.world.paused, "Revival final delay resumes room")
	check(int(game.profile.data.run.counters.get("revivals:used", 0)) == 1, "Repeated timer tick cannot consume extra revival")
	game.profile.data.run.counters["run:total_depth"] = 4
	_seed_run_items()
	var player_key = str(game.world.player.combat.actor_key)
	game._record_run_impact({"source_key": player_key, "receiver_key": "enemy:settlement", "resolved_accepted": true, "resolved_damage": 1200})
	game.battle_tally.reset()
	game._record_run_impact({"source_key": player_key, "receiver_key": "enemy:settlement", "resolved_accepted": true, "resolved_damage": 800})
	game._record_run_impact({"source_key": "enemy:other", "receiver_key": "enemy:settlement", "resolved_accepted": true, "resolved_damage": 9999})
	game._record_run_impact({"source_key": player_key, "receiver_key": "enemy:settlement", "resolved_accepted": false, "resolved_damage": 9999})
	check(game.profile.data.run.counters["run:damage"] == 2000 and game.profile.data.run.counters["run:max_damage"] == 1200, "Run damage survives room tally reset and excludes rejected or foreign impacts")
	_die()
	game._save(true)
	saved = game.save_store.load_profile()
	check(not saved.is_empty() and saved.run.health == 0, "Death saves zero health")
	game._death_pending = false
	game.profile.data = saved
	game._restore_flow()
	await _wait_transition()
	check(game.world.player.dead and game._death_pending and game.hud.modal_open, "Death save restores mandatory death flow")
	_verify_blocked_close("Death")
	game._tick_death(2.0)
	check(not game.profile.data.run.active and game.profile.data.run.get("outcome", {}).get("stage") == "summary", "No revivals enters summary after two seconds")
	check(game.profile.data.run.outcome.damage == 2000 and game.profile.data.run.outcome.max_damage == 1200, "Settlement retains damage after save and restore")
	_verify_blocked_close("Result summary")
	await _render_outcome()
	game._action("result_camp", 0, 0)
	check(game._flow_locked(), "Cannot bypass summary straight to camp")
	var vouchers_before: int = game.systems.material(501)
	var vouchers: int = int(game.profile.data.run.outcome.vouchers)
	check(vouchers > 0, "Settlement fixture earns vouchers")
	game._action("result_next", 0, 0)
	check(game.profile.data.run.outcome.stage == "rewards", "Summary continues to rewards")
	check(not game.profile.data.run.inventory.is_empty() and game.systems.material(102) == 27, "Temporary items remain available during reward conversion")
	check(game.systems.material(501) == vouchers_before + vouchers, "Summary grants expected vouchers")
	game._action("result_next", 0, 0)
	check(game.systems.material(501) == vouchers_before + vouchers, "Repeated next cannot duplicate vouchers")
	game.profile.data = game.save_store.load_profile()
	game._restore_flow()
	check(game.profile.data.run.outcome.stage == "rewards" and game.hud.modal_open, "Settlement reload retains rewards stage")
	game._action("result_next", 0, 0)
	check(game.systems.material(501) == vouchers_before + vouchers and game.profile.data.run.outcome.experience_claimed, "Settlement reload cannot regrant vouchers")
	var minerals_before: int = game.systems.material(103)
	await _return_to_camp()
	check(not game.profile.data.run.active and not game._flow_locked() and not game.hud.modal_open, "Rewards return to playable camp")
	_check_camp_cleanup(vouchers_before + vouchers, minerals_before)
	await _start()
	game.profile.data.run.route = {"version": 1, "phase": "room", "layers": []}
	game._restore_flow()
	check(not game.profile.data.run.active and not game.hud.modal_open, "Invalid route returns to camp")
	await _start()
	game.profile.data.run.counters["run:total_depth"] = 35
	_seed_run_items()
	game._finish_run(true)
	check(game.profile.data.run.outcome.stage == "share", "Victory first shows share stage")
	_verify_blocked_close("Victory share")
	vouchers_before = game.systems.material(501)
	vouchers = int(game.profile.data.run.outcome.vouchers)
	game._action("result_next", 0, 0)
	check(game.profile.data.run.outcome.stage == "summary", "Victory share continues to summary")
	check(game.systems.material(501) == vouchers_before, "Victory share does not grant vouchers early")
	game._action("result_next", 0, 0)
	check(game.profile.data.run.outcome.stage == "rewards" and game.systems.material(501) == vouchers_before + vouchers, "Victory summary grants vouchers once")
	minerals_before = game.systems.material(103)
	await _return_to_camp()
	check(not game._flow_locked() and not game.profile.data.run.active, "Victory rewards return to camp")
	_check_camp_cleanup(vouchers_before + vouchers, minerals_before)
	_seed_run_items()
	game._restore_flow()
	check(game.profile.data.run == DungeonProfile.new_run() and game.systems.material(102) == 0, "Loading an old camp save clears leftover temporary items")
	_finish()

func _finish() -> void:
	game.set_process(false)
	game.queue_free()
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(save_path + suffix): DirAccess.remove_absolute(save_path + suffix)
	print("GAME_FLOW_TEST ", JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
