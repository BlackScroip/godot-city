extends "res://tests/room_gate_flow_test.gd"

func _load_kind(value: String, field := "Flow") -> void:
	if is_instance_valid(game):
		game.queue_free()
		await process_frame
	game = load("res://scenes/main.tscn").instantiate()
	game.save_store = DungeonSaveStore.new("/private/tmp/city-special-gates-%d.json" % Time.get_ticks_usec())
	root.add_child(game)
	game.set_process(false)
	game.world.set_physics_process(false)
	_check(game.systems.begin_run(42, 1, 100, 0).success, "Independent run starts for " + value)
	var id := 0
	for node in game.campaign.database.Nodes:
		if str(node.get(field, "")) == value:
			id = int(node.Id)
			break
	_check(id > 0, "Source fixture exists: " + value)
	game.campaign.start_practice(id, 42)
	game._load_room()
	await _wait_loading()

func _enter() -> void:
	for item in _items("EEUT_PlayerTrigger"):
		if int(item.data.get("TriggerId", -1)) == 1:
			game.world.player.position = _point(item)
			game.world.interactions.tick(0.02, game.world.player.position)
			return
	_check(false, "Source entry trigger exists")

func _exit() -> void:
	var doors := _items("EEUT_StageChangeDoor") + _items("EEUT_Protal")
	_check(not doors.is_empty(), "Room has a source exit")
	if not doors.is_empty():
		_check(game.world.interactions.interact(str(doors[0].id)).success, "Explicit open exit interaction succeeds")

func _run() -> void:
	await _load_kind("ProtectTarget", "FightType")
	_check(game.world.room_stage == "entry", "Protect room initially awaits entrance")
	_enter()
	_check(game.world.room_stage == "protection" and game.world._enemy_count() == 0, "Entering protection room seals it without auto spawning")
	_gates(true, false, false)
	await _restore_stage("protection")
	var targets := _items("EEUT_ProtectTarget")
	_check(not targets.is_empty(), "Protection fixture includes actual target")
	if targets.is_empty():
		_finish()
		return
	var target: Dictionary = targets[0]
	var volume: Dictionary = game.world.interactions._volumes(target, "Box_InteractArea")[0]
	var matrix: Transform3D = game.world.interactions._matrix(volume.world_matrix)
	var center: Vector3 = game.world.interactions._vector(volume.properties.get("m_Center", {}))
	var point: Vector3 = game.world.interactions._world_position(matrix * center) - Vector3.UP * 0.8
	var outside: Vector3 = game.world.interactions._world_position(matrix * (center + Vector3(100, 0, 0))) - Vector3.UP * 0.8
	_check(game.world.interactions.nearest_interaction(outside, 1000).get("id", "") != target.id, "Protection prompt respects authored bounds even with large search radius")
	game.world.player.position = point
	game.world.interactions.tick(0.1, point)
	_check(game.world.room_stage == "protection" and game.world._enemy_count() == 0, "Standing in protection interaction bounds never starts battle automatically")
	_check(game.world.interactions.nearest_interaction(point).get("id", "") == target.id, "Protection target is actionable inside actual interaction volume")
	_check(game.world.interactions.interact_nearest(point).success, "Explicit target action starts protection")
	_check(game.world.room_stage == "fighting" and game.world.actors.size() == 2, "Protection action creates first enemy immediately")
	_check(not game.world.interactions.interact(str(target.id)).success, "Protection target rejects repeated start")
	await _check_completion("ProtectTarget", 0.0)
	for kind in ["DodgeBattle", "TimeLimit"]:
		await _load_kind(kind, "FightType")
		_enter()
		_check(game.world.room_stage == "fighting", kind + " begins at authored entry")
		await _check_completion(kind, 0.0 if kind == "DodgeBattle" else 1.0)
	for pair in [["Entrance", 0.1], ["Treasure", 1.0]]:
		await _load_kind(pair[0])
		_check(game.world.room_stage == "opening", str(pair[0]) + " delays exit enablement")
		_gates(false, false, true)
		game.world.paused = true
		_tick(10)
		_check(is_equal_approx(game.world._room_stage_wait, pair[1]), "Pause freezes " + str(pair[0]) + " opening delay")
		game.world.paused = false
		_tick(pair[1] - 0.001)
		_check(game.world.room_stage == "opening", "Opening cannot finish early")
		_tick(0.001)
		_check(game.world.room_stage == "open", "Opening finishes at source delay")
	for flow in ["Shop", "Rest", "Event"]:
		await _load_kind(flow)
		_check(game.world.room_stage == "open" and game.campaign.state.phase == "room", flow + " permits exit before resolving optional activity")
		var magic: int = game.systems.material(102)
		_exit()
		await _wait_loading()
		_check(game.campaign.state.phase != "room", flow + " exits without consuming its activity")
		_check(game.systems.material(102) >= magic, flow + " exit does not spend currency")
	await _load_kind("Curse")
	_check(game.world.room_stage == "event_locked", "Curse exit starts locked")
	game._finish_noncombat()
	_check(game.world.room_stage == "event_locked" and game.campaign.state.phase == "room", "Direct noncombat completion cannot bypass required curse choice")
	game._room_action()
	_check(game.hud.modal_open, "Curse interaction shows choice menu")
	game._action("close_page", 0, 0)
	_check(game.world.room_stage == "event_locked", "Closing curse choice menu does not unlock exit")
	game._environment_action("transition", {})
	_check(game.campaign.state.phase == "room", "Locked curse rejects transition")
	var key: String = "old_day:" + game._room_key
	game._action("choose_loot", -1, key)
	_check(game.world.room_stage == "event_locked", "Invalid curse choice cannot unlock exit")
	var choices: Array = []
	for reward in game.profile.data.run.rewards:
		if str(reward.key) == key: choices = reward.choices
	_check(not choices.is_empty(), "Curse creates source loot choices")
	if not choices.is_empty():
		game._action("choose_loot", int(choices[0]), key)
		_check(game.world.room_stage == "open" and game.campaign.state.phase == "reward", "Successful curse choice completes event and opens exit")
	_finish()

func _check_completion(kind: String, prewait: float) -> void:
	while int(game.campaign.state.waves_cleared) < int(game.campaign.state.wave_count) - 1:
		_defeat_wave()
	_defeat_wave()
	_tick(0.051)
	_check(game.world.room_stage == "clearing" and is_equal_approx(game.world._room_stage_wait, prewait), kind + " applies source completion prewait")
	game.world.paused = true
	_tick(4)
	_check(game.world.room_stage == "clearing", kind + " clear pauses")
	game.world.paused = false
	_tick(prewait)
	_check(game.world.room_stage == "rewards", kind + " releases boundary after correct prewait")
	_gates(false, false, true)
	_tick(0.999)
	_check(game.world.room_stage == "rewards", kind + " exit waits full final second")
	_tick(0.001)
	_check(game.world.room_stage == "open", kind + " exit opens after final second")

func _finish() -> void:
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures}
	FileAccess.open("res://reports/special-room-gate-flow.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("SPECIAL_ROOM_GATE_FLOW ", JSON.stringify(report))
	game.queue_free()
	quit(0 if failures.is_empty() else 1)
