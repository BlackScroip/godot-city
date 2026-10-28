extends SceneTree

var game: Node
var failures: Array[String] = []
var checks := 0
var stages: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr(message)

func _wait_loading() -> void:
	game.world.set_physics_process(false)
	game.world.set_process(true)
	var deadline := Time.get_ticks_msec() + 60000
	while game._transitioning and Time.get_ticks_msec() < deadline: await process_frame
	_check(not game._transitioning, "Room loading completes")
	game.set_process(false)
	game.world.set_process(false)
	game.world.set_physics_process(false)
	game.world.auto_attack_enabled = false
	game.world.presentation.audio_enabled = false
	game.world.player.invulnerability = 10000

func _items(type: String) -> Array:
	return game.world.interactions._items.values().filter(func(item): return str(item.marker.Type) == type)

func _point(item: Dictionary) -> Vector3:
	var collider: Dictionary = item.colliders[0]
	var local: Vector3 = game.world.interactions._matrix(collider.world_matrix) * game.world.interactions._vector(collider.properties.get("m_Center", {}))
	return game.world.interactions._world_position(local) - Vector3.UP * 0.8

func _gates(sealed: bool, exit_open: bool, chests_open: bool) -> void:
	for item in _items("EEUT_CloseArea"):
		if int(item.data.get("TriggerId", -1)) not in [1, 2]: continue
		_check(item.state.enabled == sealed, "%s boundary enabled=%s" % [game.world.room_stage, sealed])
		for body in item.bodies:
			_check((body.node.collision_layer != 0) == sealed, "Boundary collision follows room stage")
	for item in _items("EEUT_StageChangeDoor"):
		_check(item.state.enabled == exit_open, "%s exit enabled=%s" % [game.world.room_stage, exit_open])
		_check(is_instance_valid(item.visual) and item.visual.visible, "Doorway root remains visible while locked")
	for item in _items("EEUT_AbilityItemTreasureBox"):
		if int(item.data.get("TreasureId", 0)) == 1:
			_check(item.state.enabled == chests_open, "Completion chest follows reward stage")

func _restore_stage(expected: String) -> void:
	game._build_save_snapshot()
	var before: Dictionary = game.profile.data.run.battle.transients.room_flow.duplicate(true)
	var queued: Array = game.profile.data.run.battle.transients.wave_spawns.duplicate(true)
	game._load_room(true)
	await _wait_loading()
	_check(game.world.room_stage == expected, "Checkpoint restores " + expected)
	_check(is_equal_approx(game.world._room_stage_wait, float(before.remaining)), "Checkpoint preserves remaining stage delay")
	_check(game.world.wave_spawn_queue == queued, "Checkpoint preserves pending enemy order")
	stages.append(expected)

func _tick(delta: float) -> void:
	game.world._physics_process(delta)

func _defeat_wave() -> void:
	var cleared: int = game.campaign.state.waves_cleared
	while not game.world.wave_spawn_queue.is_empty(): _tick(0.2)
	for actor in game.world.actors.duplicate():
		if not actor.is_player and not actor.dead:
			actor.combat.health = 0
			game.world._die(actor)
	while game.world._wave_gate_remaining > 0 and int(game.campaign.state.waves_cleared) == cleared:
		_tick(minf(0.25, game.world._wave_gate_remaining))
	if int(game.campaign.state.waves_cleared) == cleared and game.world._wave_clear_remaining < 0: _tick(0.001)

func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.save_store = DungeonSaveStore.new("/private/tmp/city-room-gates-%d.json" % Time.get_ticks_usec())
	root.add_child(game)
	game.set_process(false)
	game.systems.begin_run(42, 1, 100, 0)
	var selected := false
	for node in game.campaign.database.Nodes:
		if node.Flow != "Battle" or int(node.MinDifficulty) != 0: continue
		game.campaign.start_practice(int(node.Id), 42)
		if int(game.campaign.state.wave_count) > 1:
			selected = true
			break
	_check(selected, "Ordinary multiwave fixture exists")
	game._load_room()
	await _wait_loading()
	_check(game.world.room_stage == "entry" and game.world._enemy_count() == 0, "Room waits for authored entry trigger before creating enemies")
	_gates(false, false, false)
	await _restore_stage("entry")
	var entry: Dictionary = {}
	for item in _items("EEUT_PlayerTrigger"):
		if int(item.data.get("TriggerId", -1)) == 1: entry = item
	_check(not entry.is_empty(), "Room contains authored player trigger 1")
	if entry.is_empty():
		_finish()
		return
	game._finish_room()
	game._leave_room(true)
	_check(game.campaign.state.phase == "room", "Entry cannot be completed or exited by commands")
	game.world.player.position = _point(entry)
	game.world.interactions.tick(0.02, game.world.player.position)
	_check(game.world.room_stage == "fighting" and game.world.actors.size() == 2, "Trigger creates first enemy immediately")
	_gates(true, false, false)
	for item in _items("EEUT_CloseArea"):
		if not item.colliders.is_empty(): game.world.interactions.tick(0.02, _point(item))
	_gates(true, false, false)
	_check(not game.world.wave_spawn_queue.is_empty(), "Fixture has staggered enemy spawns")
	_tick(0.199)
	_check(game.world.actors.size() == 2, "Second enemy waits until 0.2 seconds")
	_tick(0.001)
	_check(game.world.actors.size() == 3, "Second enemy appears at 0.2 seconds")
	await _restore_stage("fighting")
	var wait_before: float = game.world._wave_spawn_wait
	game.world.paused = true
	_tick(5)
	_check(is_equal_approx(game.world._wave_spawn_wait, wait_before), "Pause freezes queued enemy timer")
	game.world.paused = false
	_defeat_wave()
	_check(int(game.campaign.state.waves_cleared) == 1, "Ordinary wave completion reaches campaign")
	_check(not game.world.wave_spawn_queue.is_empty() and is_equal_approx(game.world._wave_spawn_wait, 1.0), "Next wave receives source one second delay")
	var queued: int = game.world.wave_spawn_queue.size()
	_tick(0.999)
	_check(game.world.wave_spawn_queue.size() == queued, "Next wave cannot spawn before one second")
	_tick(0.001)
	_check(game.world.wave_spawn_queue.size() == queued - 1, "Next wave begins at one second")
	while int(game.campaign.state.waves_cleared) < int(game.campaign.state.wave_count) - 1:
		_defeat_wave()
	_defeat_wave()
	_check(game.world.room_stage == "fighting", "Final defeated wave retains its 0.05 second wait")
	_tick(0.049)
	_check(game.world.room_stage == "fighting", "Final wait cannot complete before 0.05 seconds")
	_tick(0.0011)
	_check(game.world.room_stage == "clearing", "Final wait enters clear sequence")
	_gates(true, false, false)
	_tick(0.25)
	await _restore_stage("clearing")
	var clear_wait: float = game.world._room_stage_wait
	game.world.paused = true
	_tick(5)
	_check(is_equal_approx(game.world._room_stage_wait, clear_wait), "Pause freezes completion delay")
	game.world.paused = false
	_tick(clear_wait - 0.001)
	_check(game.world.room_stage == "clearing", "Barrier stays closed until one second after clear")
	_tick(0.001)
	_check(game.world.room_stage == "rewards" and game.campaign.state.phase == "reward", "One second releases barriers and enables completion rewards")
	_check(game.hud.battle_complete.visible and is_equal_approx(game.hud.battle_complete.battle_seconds, game.world.elapsed), "Completion publishes the frozen room combat time")
	_gates(false, false, true)
	await _restore_stage("rewards")
	_check(not game.hud.battle_complete.visible, "Restoring a completed room does not replay its completion banner")
	game._leave_room(true)
	_check(game.campaign.state.phase == "reward", "Reward stage blocks early exit")
	_tick(0.999)
	_check(game.world.room_stage == "rewards", "Exit remains locked for the second full delay")
	_tick(0.001)
	_check(game.world.room_stage == "open", "Exit unlocks after the second one second delay")
	_gates(false, true, true)
	await _restore_stage("open")
	for item in _items("EEUT_StageChangeDoor"):
		game.world.interactions.tick(0.02, game.world.interactions._world_position(item.position))
	_check(game.campaign.state.phase == "reward" and not game.hud.modal_open, "Proximity to unlocked exit never transitions automatically")
	var transitions := {"count": 0}
	game.world.interactions.transition_requested.connect(func(_context): transitions.count += 1)
	var exits := _items("EEUT_StageChangeDoor")
	_check(not exits.is_empty(), "Fixture has an explicit exit interaction")
	if not exits.is_empty():
		game.world.interactions.interact(str(exits[0].id))
		_check(transitions.count == 1, "Explicit exit interaction dispatches one transition")
	_finish()

func _finish() -> void:
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "restored_stages": stages}
	FileAccess.open("res://reports/room-gate-flow.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("ROOM_GATE_FLOW ", JSON.stringify(report))
	game.queue_free()
	quit(0 if failures.is_empty() else 1)
