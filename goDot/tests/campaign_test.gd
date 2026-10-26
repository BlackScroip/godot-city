extends SceneTree

const Campaign = preload("res://scripts/domain/campaign.gd")
var assertions: int = 0
var failures: Array = []

func _initialize() -> void:
	var campaign = Campaign.new()
	_check(campaign.configure(), "Campaign data loads")
	_check(campaign.database.Nodes.size() >= 356, "Recovered campaign includes the original nodes and newer map branches")
	_check(campaign.database.Regions.size() == 5, "5 regions")
	var route_count = 0
	var room_count = 0
	var spawn_count = 0
	for difficulty in range(11):
		for seed_value in [1, 17, 389]:
			_check(campaign.generate(seed_value, difficulty).success, "Route generates difficulty %s seed %s" % [difficulty, seed_value])
			_check(campaign.state.layers.size() == 35, "35 room route")
			var original = campaign.snapshot()
			var check_copy = Campaign.new()
			check_copy.configure(campaign.database)
			check_copy.generate(seed_value, difficulty)
			_check(JSON.stringify(original) == JSON.stringify(check_copy.snapshot()), "Seeded route deterministic")
			while campaign.state.phase != "won":
				_check(campaign.state.phase == "route", "Route reachable after reward")
				if campaign.state.get("region_selection", false):
					var regions = campaign.region_choices()
					_check(not regions.is_empty(), "Next region is selected on the world map")
					if regions.is_empty(): break
					var normal_slots = [2, 4, 6, 8, 9]
					_check(campaign.select_region(normal_slots[campaign.current_module_index()]).success, "Select reachable ordinary region")
				var choices = campaign.choices()
				_check(not choices.is_empty(), "Each layer has choices")
				if choices.is_empty():
					break
				_check(campaign.enter(int(choices[0].node_id)).success, "Enter reachable node")
				var room = campaign.current_room()
				_check(room.node_id > 0 and room.stage_id > 0, "Room aliases have IDs")
				_check(not campaign.advance().success, "Cannot skip objective and reward")
				if room.combat:
					for wave in range(1, int(campaign.state.wave_count) + 1):
						var spawns = campaign.wave_spawns(wave)
						spawn_count += spawns.size()
						_check(not spawns.is_empty(), "Combat wave has enemies node %s wave %s" % [room.node_id, wave])
						for spawn in spawns:
							_check(int(spawn.enemy_id) > 0 and spawn.position is Dictionary, "Spawn IDs and positions valid")
						_check(campaign.clear_wave().success, "Wave clears once")
					_check(not campaign.clear_wave().success, "Extra wave clear rejected")
				else:
					_check(campaign.resolve_action().success, "Room action resolves")
					_check(not campaign.resolve_action().success, "Room action resolves once")
				_check(campaign.room_ready(), "Objective opens exit")
				_check(campaign.complete_room(25.0, 0, 100.0).success, "Room settlement")
				var saved = JSON.parse_string(JSON.stringify(campaign.snapshot()))
				_check(check_copy.restore(saved), "Complete objective snapshot restores")
				_check(campaign.advance().success, "Reward claims")
				_check(not campaign.advance().success, "Reward cannot duplicate")
				room_count += 1
			_check(campaign.state.visited.size() == 35, "All route rooms visited")
			route_count += 1
	for room in campaign.database.Nodes + campaign.database.SpecialStages:
		_check(campaign.start_practice(int(room.Id), 17).success, "Practice can load node %s" % room.Id)
		_check(campaign.current_room().node_id == int(room.Id), "Practice retains original ID")
	var timed = {"FightType": "TimeLimit", "Flow": "Battle", "FightData": {"RewardTimeLimit_Lv3": 30, "RewardTimeLimit_Lv2": 60, "RewardTimeLimit_Lv1": 90}}
	_check(campaign.rank(timed, 30, 0, 100) == 3, "Timed rank top boundary")
	_check(campaign.rank(timed, 90.1, 0, 100) == 0, "Timed rank timeout")
	var protect = {"FightType": "ProtectTarget", "Flow": "Battle", "FightData": {"RemainTargetHp_Lv3": 80, "RemainTargetHp_Lv2": 50}}
	_check(campaign.rank(protect, 0, 0, 80) == 3, "Protect rank top boundary")
	_check(campaign.rank(protect, 0, 0, 0) == 0, "Protect target failure rank")
	var dodge = {"FightType": "DodgeBattle", "Flow": "Battle", "FightData": {"BeHitCount_Lv3": 0, "BeHitCount_Lv2": 3, "BeHitCount_Lv1": 5}}
	_check(campaign.rank(dodge, 0, 0, 100) == 3 and campaign.rank(dodge, 0, 6, 100) == 0, "Dodge rank boundaries")
	campaign.generate(1, 0)
	var malformed = campaign.snapshot()
	malformed.layers[0].node_ids = [99999999]
	_check(not campaign.restore(malformed), "Unknown saved route rejected")
	_check(not campaign.generate(1, 11).success, "Invalid difficulty rejected")
	var report = {"schema": 1, "assertions": assertions, "failures": failures, "routes": route_count, "rooms": room_count, "spawns": spawn_count, "parity": "Recovered eligibility, route dimensions, forced spawns and rank thresholds; deterministic route sampling and random enemy counts reconstructed."}
	var file = FileAccess.open("res://reports/campaign_test.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report, "\t"))
	print("CAMPAIGN TEST: %s assertions, %s failures, %s routes, %s room settlements" % [assertions, failures.size(), route_count, room_count])
	for failure in failures:
		printerr(failure)
	quit(0 if failures.is_empty() else 1)

func _check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)
