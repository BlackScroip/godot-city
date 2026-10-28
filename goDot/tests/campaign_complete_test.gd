extends SceneTree

const Campaign = preload("res://scripts/domain/campaign.gd")
var checks := 0
var failures: Array[String] = []
var rooms: Array = []
var combat_data: Dictionary
var restored = Campaign.new()

func _initialize() -> void:
	var campaign = Campaign.new()
	_check(campaign.configure(), "Campaign data loads")
	_check(restored.configure(campaign.database), "Independent restore instance loads")
	combat_data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/combat.json"))
	var enemy_ids: Dictionary = {}
	for enemy in combat_data.enemies: enemy_ids[int(enemy.id)] = true
	var nodes: Array = campaign.database.Nodes + campaign.database.SpecialStages
	var waves := 0
	var spawns := 0
	var trials := 0
	var flow_counts: Dictionary = {}
	for node in nodes:
		var id := int(node.Id)
		_check(campaign.start_practice(id, 371).success, "%d starts its own real stage" % id)
		var room: Dictionary = campaign.current_room()
		flow_counts[room.flow] = int(flow_counts.get(room.flow, 0)) + 1
		_check(room.node_id == id and int(room.stage_id) > 0 and not str(room.SceneName).is_empty(), "%d retains stage and scene identity" % id)
		_check(not campaign.advance().success, "%d cannot advance before objective settlement" % id)
		_restore(campaign, "%d initial room" % id)
		var room_spawns := 0
		if room.combat:
			_check(int(campaign.state.wave_count) > 0, "%d combat objective has at least one wave" % id)
			for wave in range(1, int(campaign.state.wave_count) + 1):
				var entries: Array = campaign.wave_spawns(wave)
				_check(not entries.is_empty(), "%d wave %d contains enemies" % [id, wave])
				for entry in entries:
					_check(enemy_ids.has(int(entry.enemy_id)), "%d spawn %s resolves a combat enemy" % [id, entry.enemy_id])
					var position: Dictionary = entry.position
					_check([position.get("X", 0), position.get("Y", 0), position.get("Z", 0)].all(func(value): return is_finite(float(value))), "%d spawn position is finite" % id)
				room_spawns += entries.size()
				_check(campaign.clear_wave().success, "%d wave %d clears" % [id, wave])
				_restore(campaign, "%d wave %d" % [id, wave])
				waves += 1
			_check(not campaign.clear_wave().success, "%d rejects duplicate final wave clear" % id)
		elif room.flow == "TreasureTrial":
			_check(not campaign.resolve_action().success, "%d trial cannot use ordinary room shortcut" % id)
			_check(campaign.start_trial(2, {}).success, "%d starts recovered luxury trial pipeline" % id)
			for step in 20:
				if campaign.trial_status().phase == "complete": break
				_check(campaign.tick_trial(100, false).success, "%d advances trial phase" % id)
				_restore(campaign, "%d trial cursor" % id)
			_check(campaign.claim_trial_reward().success and not campaign.claim_trial_reward().success, "%d claims trial reward once" % id)
			trials += 1
		else:
			_check(campaign.resolve_action().success and not campaign.resolve_action().success, "%d resolves ordinary objective once" % id)
		_check(campaign.room_ready(), "%d objective opens exit" % id)
		_check(campaign.complete_room(25.0, 0, 100).success, "%d settles objective" % id)
		_check(not campaign.complete_room(25.0, 0, 100).success, "%d rejects duplicate settlement" % id)
		_restore(campaign, "%d reward cursor" % id)
		_check(campaign.advance().success and campaign.state.phase == "won", "%d reward advances completed practice" % id)
		_check(not campaign.advance().success and campaign.state.visited == [id], "%d completion is recorded exactly once" % id)
		_restore(campaign, "%d completed room" % id)
		spawns += room_spawns
		rooms.append({"id": id, "stage": room.stage_id, "flow": room.flow, "scene": room.SceneName, "waves": room.wave_count, "spawns": room_spawns})
	_check(campaign.database.Nodes.size() == 514 and campaign.database.SpecialStages.size() == 19, "All 514 active campaign nodes and 19 special stages are included")
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "nodes": campaign.database.Nodes.size(), "special_stages": campaign.database.SpecialStages.size(), "settled_rooms": rooms.size(), "waves": waves, "spawns": spawns, "trials": trials, "flows": flow_counts, "rooms": rooms, "scope": "Exhaustive domain-level objective, reward, advance and JSON recovery for all recovered nodes and special stages with real spawn definitions and luxury trial timers. Does not claim visual scene traversal or original APK runtime execution."}
	FileAccess.open("res://reports/campaign-complete-test.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("CAMPAIGN_COMPLETE ", JSON.stringify({"passed": report.passed, "checks": checks, "failure_count": failures.size(), "first_failures": failures.slice(0, 10), "rooms": rooms.size(), "waves": waves, "spawns": spawns, "trials": trials}))
	quit(0 if failures.is_empty() else 1)

func _restore(campaign: RefCounted, label: String) -> void:
	var saved: Dictionary = JSON.parse_string(JSON.stringify(campaign.snapshot()))
	_check(restored.restore(saved), label + " survives JSON recovery")
	_check(_preserves(saved, JSON.parse_string(JSON.stringify(restored.snapshot()))), label + " preserves progress and spawn plan")

func _preserves(expected: Variant, actual: Variant) -> bool:
	if expected is Dictionary:
		if not actual is Dictionary: return false
		# Practice saves may acquire default route-link fields; all recorded values must remain.
		for key in expected:
			if not actual.has(key) or not _preserves(expected[key], actual[key]): return false
		return true
	if expected is Array:
		if not actual is Array or expected.size() != actual.size(): return false
		for index in expected.size():
			if not _preserves(expected[index], actual[index]): return false
		return true
	return expected == actual

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)
