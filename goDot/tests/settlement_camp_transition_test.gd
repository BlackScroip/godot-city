extends SceneTree

var failures: Array[String] = []
var checks := 0
var game: Node
var canvas: SubViewport
var save_path := ""
var pending_path := ""
var source_path := ""
var source_digest := ""
var message_peak := 0.0
var completed := false

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("SETTLEMENT_CAMP_FAILURE: " + message)

func _sample_queue() -> void:
	message_peak = maxf(message_peak, Performance.get_monitor(Performance.MEMORY_MESSAGE_BUFFER_MAX))

func _is_clean_saved_run(run: Dictionary) -> bool:
	if bool(run.get("active", true)) or not run.get("outcome", {}).is_empty(): return false
	for key in ["inventory", "talents", "battle", "route", "counters", "materials"]:
		if not run.get(key) is Dictionary or not run[key].is_empty(): return false
	for key in ["events", "rewards", "shops", "node_entry_buffs", "completed_nodes", "completed_occurrences"]:
		if not run.get(key) is Array or not run[key].is_empty(): return false
	return true

func _wait_transition() -> bool:
	var deadline := Time.get_ticks_msec() + 90000
	while game._transitioning and Time.get_ticks_msec() < deadline:
		_sample_queue()
		await process_frame
	_sample_queue()
	check(not game._transitioning, "Transition finishes within 90 seconds")
	if game._transitioning: return false
	await process_frame
	_sample_queue()
	return true

func _open_game(path: String) -> void:
	game = load("res://scripts/main.gd").new()
	game.save_store = DungeonSaveStore.new(path)
	canvas.add_child(game)
	game.set_process(false)
	game.world.set_physics_process(false)
	game.audio.stop()
	await process_frame
	_sample_queue()

func _close_game() -> void:
	if not is_instance_valid(game): return
	game.save_store.flush()
	game.queue_free()
	await process_frame
	game = null

func _advance_to_rewards() -> bool:
	for _step in 3:
		var outcome: Dictionary = game.profile.data.run.get("outcome", {})
		if outcome.is_empty():
			check(false, "Settlement outcome exists")
			return false
		if outcome.get("stage", "summary") == "rewards": return true
		var view = game.hud.page.outcome_view
		if not is_instance_valid(view) or not is_instance_valid(view.confirm):
			check(false, "Settlement has a real confirmation button")
			return false
		var button = view.confirm
		var was_summary: bool = outcome.get("stage", "summary") == "summary"
		var unclaimed: bool = not outcome.get("experience_claimed", false)
		var vouchers_before: int = game.systems.material(501)
		var vouchers: int = int(outcome.get("vouchers", 0)) if unclaimed else 0
		button.pressed.emit()
		if was_summary:
			button.pressed.emit()
			check(game.systems.material(501) == vouchers_before + vouchers, "Repeated summary confirmation grants vouchers only once")
		await process_frame
		_sample_queue()
	check(false, "Settlement reaches rewards")
	return false

func _return_to_camp(expect_existing_camp: bool) -> bool:
	if not await _advance_to_rewards(): return false
	var view = game.hud.page.outcome_view
	if not is_instance_valid(view) or not is_instance_valid(view.confirm):
		check(false, "Rewards page has a real return button")
		return false
	var button = view.confirm
	var old_view: WeakRef = weakref(view)
	var old_root_id: int = game.world.environment_root.get_instance_id()
	var old_player_id: int = game.world.player.get_instance_id()
	var before: Dictionary = game.profile.data.run.outcome.duplicate(true)
	var wallet: Dictionary = game.profile.data.materials.duplicate(true)
	var retained_hud_texture: Texture2D = game.hud.page.backdrop.texture
	var texture_key := "res://assets/art_generated/showcase-v1.png"
	var item_key := "%s:%d" % [false, 11005]
	check(is_instance_valid(DungeonStyle.texture(texture_key)) and is_instance_valid(DungeonItemArt.texture(11005)), "UI and item textures load before return")
	check(DungeonStyle._textures.has(texture_key) and DungeonItemArt.cache.has(item_key), "Loaded textures populate the UI and item caches")
	button.pressed.emit()
	check(game._transitioning and game.room_loading.visible and game.world.paused, "Return immediately shows loading and pauses the world")
	check(game.profile.data.run.get("outcome", {}) == before, "Return keeps outcome until transition starts")
	button.pressed.emit()
	game._action("close_page", 0, 0)
	check(game._transitioning and game.profile.data.run.get("outcome", {}) == before, "Repeated button and close actions cannot interrupt return")
	if not await _wait_transition(): return false
	check(not game.room_loading.visible and not game.hud.modal_open, "Loading and settlement close after return")
	check(not is_instance_valid(old_view.get_ref()) and not is_instance_valid(game.hud.page.outcome_view), "Settlement view is released after return")
	check(game.world._camp_camera and is_instance_valid(game.world.player) and not game.world.paused, "Return ends in a playable camp")
	check(is_instance_valid(retained_hud_texture) and game.hud.page.backdrop.texture == retained_hud_texture, "HUD-owned texture remains valid after cache release")
	check(not DungeonStyle._textures.has(texture_key) and not DungeonItemArt.cache.has(item_key), "Unused UI and item cache entries are released on return")
	check(is_instance_valid(DungeonStyle.texture(texture_key)) and is_instance_valid(DungeonItemArt.texture(11005)), "UI and item textures reload after cache release")
	if expect_existing_camp:
		check(game.world.environment_root.get_instance_id() == old_root_id, "Restored settlement reuses the existing camp environment")
		check(game.world.player.get_instance_id() == old_player_id, "Restored settlement reuses the existing camp player")
	else:
		check(game.world.environment_root.get_instance_id() != old_root_id, "Battle environment is replaced by the camp")
		check(game.world.player.get_instance_id() != old_player_id, "Battle player is replaced by the camp player")
	check(_is_clean_saved_run(game.profile.data.run), "Return clears all temporary run data")
	check(game.systems.material(102) == 0, "Return clears temporary magic")
	for key in ["101", "103", "501"]:
		check(int(game.profile.data.materials.get(key, 0)) == int(wallet.get(key, 0)), "Return preserves permanent material " + key)
	check(game.save_store.flush(), "Camp save completes")
	var persisted: Dictionary = game.save_store.load_profile()
	check(not persisted.is_empty() and _is_clean_saved_run(persisted.run) and int(persisted.materials.get("102", 0)) == 0, "Clean camp state is persisted")
	return true

func _start_combat_fixture() -> bool:
	var result: Dictionary = game.systems.begin_run(123456, game.selected_character, game.world.player.combat.max_health, 0)
	check(bool(result.get("success", false)), "Synthetic adventure starts")
	if not result.get("success", false): return false
	var node_id := _battle_node_id()
	check(node_id > 0, "A real battle room is available")
	if node_id == 0: return false
	game.campaign.start_practice(node_id, 123456)
	game._load_room()
	if not await _wait_transition(): return false
	check(not game.world._camp_camera and is_instance_valid(game.world.environment_root), "Fixture loads a battle environment")
	var run: Dictionary = game.profile.data.run
	run.counters["run:total_depth"] = 27
	run.counters["run:kills"] = 100
	run.region = 4
	for row in game.catalog.rows("AbilityItems").slice(0, 25): run.inventory[str(int(row.get("ID", row.get("id", 0))))] = 1
	for row in game.catalog.rows("CharTalentData").slice(0, 8): run.talents[str(int(row.id))] = 1
	for row in game.catalog.rows("MaterialData").slice(0, 8): run.materials[str(int(row.id))] = 1
	game.profile.data.materials["102"] = 27
	game._finish_run(false)
	check(not game.profile.data.run.active and not game.profile.data.run.get("outcome", {}).is_empty(), "Battle produces a real settlement")
	return not game.profile.data.run.get("outcome", {}).is_empty()

func _battle_node_id() -> int:
	for node in game.campaign.database.Nodes:
		if node.Flow == "Battle" and int(node.MinDifficulty) == 0: return int(node.Id)
	return 0

func _start_active_camp_fixture() -> bool:
	check(game.world._camp_camera, "Active adventure fixture starts with a camp backdrop")
	var result: Dictionary = game.systems.begin_run(654321, game.selected_character, game.world.player.combat.max_health, 0)
	check(bool(result.get("success", false)), "Active adventure with camp backdrop starts")
	if not result.get("success", false): return false
	var node_id := _battle_node_id()
	if node_id == 0:
		check(false, "A battle node is available for active camp fixture")
		return false
	game.campaign.start_practice(node_id, 654321)
	game.campaign.state.phase = "route"
	game.world.player.combat.health = 1.0
	game.world.player.combat.armor = 17.0
	game.profile.data.run.health = 1.0
	game.profile.data.run.armor = 17.0
	game._finish_run(false)
	check(not game.profile.data.run.get("outcome", {}).is_empty(), "Active adventure over camp produces a settlement")
	return not game.profile.data.run.get("outcome", {}).is_empty()

func _run() -> void:
	var arguments := OS.get_cmdline_user_args()
	var input_index := arguments.find("--profile")
	if input_index >= 0:
		if input_index + 1 >= arguments.size():
			check(false, "--profile requires a JSON file path")
			_finish()
			return
		source_path = ProjectSettings.globalize_path(arguments[input_index + 1])
		if not FileAccess.file_exists(source_path) or DungeonSaveStore.new(source_path)._read(source_path).is_empty():
			check(false, "Input profile is missing or invalid")
			_finish()
			return
		source_digest = FileAccess.get_sha256(source_path)
	var stem := "/private/tmp/settlement-camp-transition-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	save_path = stem + ".json"
	pending_path = stem + "-pending.json"
	if not source_path.is_empty():
		check(DirAccess.copy_absolute(source_path, save_path) == OK, "Read-only profile is copied to an isolated test path")
		if not failures.is_empty():
			_finish()
			return
	canvas = SubViewport.new()
	canvas.size = Vector2i(844, 390)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	await _open_game(save_path)
	if not await _wait_transition():
		_finish()
		return
	if not game.profile.data.run.get("outcome", {}).is_empty():
		check(game.world._camp_camera, "Pending profile restores with a camp backdrop")
		if not await _return_to_camp(true):
			_finish()
			return
	elif game.profile.data.run.active:
		game._finish_run(false)
		if not await _return_to_camp(false):
			_finish()
			return
	if not await _start_combat_fixture() or not await _advance_to_rewards():
		_finish()
		return
	check(game._save(true), "Pending rewards save completes")
	check(DirAccess.copy_absolute(save_path, pending_path) == OK, "Pending rewards are copied for restart")
	if not await _return_to_camp(false):
		_finish()
		return
	await _close_game()
	await _open_game(pending_path)
	check(game.profile.data.run.get("outcome", {}).get("stage", "") == "rewards", "Restart restores the pending rewards stage")
	check(game.world._camp_camera and game.hud.modal_open, "Restart displays rewards over camp")
	if not await _return_to_camp(true) or not _start_active_camp_fixture():
		_finish()
		return
	completed = await _return_to_camp(false)
	if completed:
		check(game.world.player.combat.health > 1.0 and game.world.player.combat.armor != 17.0, "Rebuilt camp player does not retain active adventure health or armor")
	_finish()

func _finish() -> void:
	if is_instance_valid(game):
		game.save_store.flush()
		game.queue_free()
	if not source_path.is_empty() and not source_digest.is_empty():
		check(FileAccess.get_sha256(source_path) == source_digest, "Input profile remains unchanged")
	check(completed, "Both battle return and restored settlement return complete")
	_sample_queue()
	var queue_limit := float(ProjectSettings.get_setting("memory/limits/message_queue/max_size_mb", 32)) * 1024.0 * 1024.0
	var queue_budget := queue_limit * 0.75
	check(message_peak < queue_budget, "Message queue peak stays below 75 percent of configured capacity")
	print("SETTLEMENT_CAMP_TRANSITION_TEST ", JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty(), "message_queue_peak_bytes": int(message_peak), "message_queue_budget_bytes": int(queue_budget), "message_queue_capacity_bytes": int(queue_limit), "input_profile": not source_path.is_empty()}))
	for path in [save_path, pending_path]:
		if path.is_empty(): continue
		for suffix in ["", ".bak", ".tmp"]:
			if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	quit(0 if failures.is_empty() else 1)
