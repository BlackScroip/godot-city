class_name DungeonCampaign
extends RefCounted

const DATA_PATH = "res://assets/data/campaign.json"
const PHASES = ["route", "room", "reward", "won", "failed"]
var database: Dictionary = {}
var state: Dictionary = {}
var diagnostics: Array = []
var events: Array = []
var _nodes: Dictionary = {}
var _random_state: int = 1
var route_rules: Dictionary = {}

func configure(data: Dictionary = {}) -> bool:
	if FileAccess.file_exists("res://assets/data/route_rules.json"):
		route_rules = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/route_rules.json"))
	database = data
	if database.is_empty() and FileAccess.file_exists(DATA_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if parsed is Dictionary:
			database = parsed
	_nodes.clear()
	for node in database.get("Nodes", []) + database.get("SpecialStages", []):
		_nodes[int(node.Id)] = node
	return not _nodes.is_empty()

func generate(seed_value: int, difficulty: int) -> Dictionary:
	if _nodes.is_empty() and not configure():
		return _result(false, "Missing campaign database")
	if difficulty < 0 or difficulty > 10:
		return _result(false, "Difficulty must be 0 through 10")
	_random_state = seed_value & 0xffffffff
	var layers: Array = []
	var appearances: Dictionary = {}
	for region in database.get("Regions", []):
		var last = int(region.MiddleColumns) + 2
		for depth in range(1, last + 1):
			var candidates: Array = []
			for node in database.Nodes:
				if int(node.Region) != int(region.Id) or not _eligible(node, difficulty):
					continue
				var suitable: bool
				if depth == 1:
					suitable = node.Flow == "Entrance"
				elif depth == last:
					suitable = node.Flow == "Boss"
				else:
					suitable = node.Flow != "Entrance" and node.Flow != "Boss" and depth >= int(node.MinDepth) and depth <= int(node.MaxDepth)
				if suitable and (int(node.MaxAppearTime) <= 0 or int(appearances.get(int(node.Id), 0)) < int(node.MaxAppearTime)):
					candidates.append(node)
			if candidates.is_empty():
				return _result(false, "Empty route region %s depth %s" % [region.Id, depth])
			var width = 1 if depth == 1 or depth == last else mini(int(region.MaxRows), candidates.size())
			var selected: Array = []
			for row in range(width):
				var node = _weighted(candidates)
				selected.append(int(node.Id))
				candidates.erase(node)
				appearances[int(node.Id)] = int(appearances.get(int(node.Id), 0)) + 1
			layers.append({"region": int(region.Id), "depth": depth, "node_ids": selected, "selected_id": 0, "complete": false})
	state = {"version": 1, "seed": seed_value, "difficulty": difficulty, "layer_index": 0, "current_node_id": 0, "phase": "route", "waves_cleared": 0, "wave_count": 0, "last_rank": 0, "spawn_group": 0, "action_resolved": false, "is_practice": false, "layers": layers, "visited": []}
	_build_connections()
	events.clear()
	return _result(true, "Campaign generated")

func choices() -> Array:
	var result: Array = []
	if state.is_empty() or state.phase != "route":
		return result
	var ids: Array = state.layers[int(state.layer_index)].node_ids
	var anchor = route_anchor()
	if not anchor.is_empty():
		ids = state.layers[int(anchor.layer_index)].get("connections", {}).get(str(int(anchor.node_id)), [])
	for id in ids:
		result.append(_room_alias(_nodes[int(id)]))
	return result

func route_anchor() -> Dictionary:
	if state.is_empty() or int(state.layer_index) <= 0: return {}
	var index = int(state.layer_index) - 1
	var id = int(state.layers[index].selected_id)
	return {"layer_index": index, "node_id": id} if id > 0 else {}

func vertical_choices() -> Array:
	var result: Array = []
	if state.is_empty() or state.phase != "route": return result
	var anchor = route_anchor()
	if anchor.is_empty(): return result
	var layer: Dictionary = state.layers[int(anchor.layer_index)]
	for pair in layer.get("vertical_links", []):
		var id = int(pair[1]) if int(pair[0]) == int(anchor.node_id) else int(pair[0]) if int(pair[1]) == int(anchor.node_id) else 0
		if id == 0 or layer.get("completed_ids", []).has(id): continue
		var room = _room_alias(_nodes[id])
		room["layer_index"] = int(anchor.layer_index)
		room["vertical"] = true
		result.append(room)
	return result

func _build_connections() -> void:
	for index in state.layers.size():
		var layer: Dictionary = state.layers[index]
		var rule: Dictionary = route_rules.get("regions", {}).get(str(int(layer.region)), {})
		var ids: Array = layer.node_ids
		layer["connections"] = {}
		layer["vertical_links"] = []
		if not layer.has("completed_ids"):
			layer["completed_ids"] = [int(layer.selected_id)] if bool(layer.complete) and int(layer.selected_id) > 0 else []
		for pair in rule.get("vertical", {}).get(str(int(layer.depth)), []):
			if int(pair[0]) < ids.size() and int(pair[1]) < ids.size(): layer.vertical_links.append([int(ids[int(pair[0])]), int(ids[int(pair[1])])])
		if index + 1 >= state.layers.size(): continue
		var next: Array = state.layers[index + 1].node_ids
		for id in ids: layer.connections[str(int(id))] = []
		if ids.size() == 1 or next.size() == 1:
			for id in ids: layer.connections[str(int(id))] = next.duplicate()
		else:
			var forward: Array = rule.get("forward", [])
			var pairs: Array = forward[int(layer.depth) - 1] if int(layer.depth) <= forward.size() else []
			for pair in pairs:
				if int(pair[0]) < ids.size() and int(pair[1]) < next.size(): layer.connections[str(int(ids[int(pair[0])]))].append(int(next[int(pair[1])]))
			# Keep every lane playable if a region uses fewer rows than its authored pattern.
			for lane in ids.size():
				if layer.connections[str(int(ids[lane]))].is_empty(): layer.connections[str(int(ids[lane]))].append(int(next[mini(lane, next.size() - 1)]))
			for lane in next.size():
				var reachable = false
				for targets in layer.connections.values():
					if targets.has(int(next[lane])): reachable = true
				if not reachable: layer.connections[str(int(ids[mini(lane, ids.size() - 1)]))].append(int(next[lane]))

func route_map(all_regions := false) -> Array:
	var result: Array = []
	if state.is_empty() or state.phase != "route": return result
	var current = int(state.layer_index)
	var region = int(state.layers[current].region)
	var reachable = choices().map(func(room): return int(room.node_id))
	var vertical = vertical_choices().map(func(room): return int(room.node_id))
	var anchor = route_anchor()
	for index in state.layers.size():
		var layer: Dictionary = state.layers[index]
		if not all_regions and int(layer.region) != region: continue
		for lane in layer.node_ids.size():
			var room = _room_alias(_nodes[int(layer.node_ids[lane])])
			room["layer_index"] = index
			room["lane"] = lane
			room["lane_count"] = layer.node_ids.size()
			room["available"] = index == current and reachable.has(int(room.node_id))
			room["vertical"] = index == current - 1 and vertical.has(int(room.node_id))
			room["visited"] = layer.get("completed_ids", []).has(int(room.node_id))
			room["is_anchor"] = not anchor.is_empty() and index == int(anchor.layer_index) and int(room.node_id) == int(anchor.node_id)
			room["parents"] = []
			if index > 0:
				for source in state.layers[index - 1].get("connections", {}):
					if state.layers[index - 1].connections[source].has(int(room.node_id)): room.parents.append((index - 1) * 100000000 + int(source))
			room["vertical_neighbors"] = []
			for pair in layer.get("vertical_links", []):
				if pair.has(int(room.node_id)): room.vertical_neighbors.append(int(pair[1]) if int(pair[0]) == int(room.node_id) else int(pair[0]))
			result.append(room)
	return result

func enter(node_id: int, allow_vertical := false) -> Dictionary:
	if state.is_empty() or state.phase != "route":
		return _result(false, "Route selection is not active", node_id)
	var reachable = choices().any(func(room): return int(room.node_id) == node_id)
	var vertical = vertical_choices().filter(func(room): return int(room.node_id) == node_id)
	if not reachable and not (allow_vertical and not vertical.is_empty()):
		return _result(false, "Node is not reachable", node_id)
	if not reachable: state.layer_index = int(vertical[0].layer_index)
	var room: Dictionary = _nodes[node_id]
	state.current_node_id = node_id
	state.layers[int(state.layer_index)].selected_id = node_id
	state.waves_cleared = 0
	state.action_resolved = false
	_random_state = (int(state.seed) ^ node_id ^ int(state.layer_index) * 397) & 0xffffffff
	state.wave_count = _next_int(int(room.WaveMin), int(room.WaveMax) + 1) if _is_combat(room) else 0
	var groups: Array = []
	for spawn in room.ForcedSpawns:
		if int(spawn.Group) > 0 and not groups.has(int(spawn.Group)):
			groups.append(int(spawn.Group))
	_random_state = (int(state.seed) ^ node_id) & 0xffffffff
	state.spawn_group = groups[_next_int(0, groups.size())] if not groups.is_empty() else 0
	for spawn in room.ForcedSpawns:
		if bool(room.ManualEnemies) and (int(spawn.Group) == 0 or int(spawn.Group) == int(state.spawn_group)):
			state.wave_count = maxi(int(state.wave_count), int(spawn.Wave))
	state.phase = "room"
	events.append({"type": "room_enter", "id": node_id, "region": int(room.Region), "node_type": int(room.Type), "occurrence": state.layer_index})
	return _result(true, "Room entered", node_id)

func current_room() -> Dictionary:
	if state.is_empty() or int(state.get("current_node_id", 0)) == 0:
		return {}
	var result = _room_alias(_nodes[int(state.current_node_id)])
	result.wave_count = state.wave_count
	result.waves_cleared = state.waves_cleared
	result.phase = state.phase
	result.enemies = wave_spawns(int(state.waves_cleared) + 1) if state.phase == "room" and _is_combat(result) and int(state.waves_cleared) < int(state.wave_count) else []
	return result

func start_practice(node_id: int, seed_value: int = 1) -> Dictionary:
	if _nodes.is_empty():
		configure()
	if not _nodes.has(node_id):
		return _result(false, "Unknown node", node_id)
	var node: Dictionary = _nodes[node_id]
	state = {"version": 1, "seed": seed_value, "difficulty": int(node.MinDifficulty), "layer_index": 0, "current_node_id": 0, "phase": "route", "waves_cleared": 0, "wave_count": 0, "last_rank": 0, "spawn_group": 0, "action_resolved": false, "is_practice": true, "layers": [{"region": int(node.Region), "depth": maxi(1, int(node.MinDepth)), "node_ids": [node_id], "selected_id": 0, "complete": false}], "visited": []}
	return enter(node_id)

func wave_spawns(wave: int) -> Array:
	var result: Array = []
	if state.is_empty() or state.phase != "room" or wave < 1 or wave > int(state.wave_count):
		return result
	var room: Dictionary = _nodes[int(state.current_node_id)]
	if not _is_combat(room):
		return result
	_random_state = (int(state.seed) ^ int(room.Id) ^ wave * 7919) & 0xffffffff
	for spawn in room.ForcedSpawns:
		if int(spawn.Wave) == wave and bool(room.ManualEnemies) and (int(spawn.Group) == 0 or int(spawn.Group) == int(state.spawn_group)):
			result.append(_forced_spawn(room, spawn))
	if bool(room.RandomEnemies) and not room.EnemyIds.is_empty():
		var lower = maxi(1, int(room.EliteTypeMin) if room.EnemyClass == "Elite" else int(room.EnemyTypeMin))
		var upper = maxi(lower, int(room.EliteTypeMax) if room.EnemyClass == "Elite" else int(room.EnemyTypeMax))
		for index in range(_next_int(lower, upper + 1)):
			result.append(_spawn(room, int(room.EnemyIds[_next_int(0, room.EnemyIds.size())]), int(room.SpawnPoints[index % room.SpawnPoints.size()].Id) if not room.SpawnPoints.is_empty() else 0, false))
	# Some packaged elite rooms request 2-3 waves but only describe wave 1.
	# Repeating their last scripted composition keeps the published wave count playable.
	if result.is_empty() and bool(room.ManualEnemies):
		var previous_wave = 0
		for spawn in room.ForcedSpawns:
			if int(spawn.Wave) < wave and (int(spawn.Group) == 0 or int(spawn.Group) == int(state.spawn_group)):
				previous_wave = maxi(previous_wave, int(spawn.Wave))
		if previous_wave > 0:
			for spawn in room.ForcedSpawns:
				if int(spawn.Wave) == previous_wave and (int(spawn.Group) == 0 or int(spawn.Group) == int(state.spawn_group)):
					var enemy = _forced_spawn(room, spawn)
					enemy.reconstructed = true
					result.append(enemy)
			_report("Manual wave composition repeated: node %s wave %s from wave %s" % [room.Id, wave, previous_wave])
	return result

func clear_wave() -> Dictionary:
	if state.is_empty() or state.phase != "room" or not _is_combat(_nodes[int(state.current_node_id)]) or int(state.waves_cleared) >= int(state.wave_count):
		return _result(false, "No uncleared wave")
	state.waves_cleared = int(state.waves_cleared) + 1
	events.append({"type": "wave_clear", "id": state.current_node_id, "wave": state.waves_cleared})
	return _result(true, "Wave cleared", int(state.current_node_id))

func resolve_action() -> Dictionary:
	if state.is_empty() or state.phase != "room" or _is_combat(_nodes[int(state.current_node_id)]) or bool(state.action_resolved):
		return _result(false, "Room action unavailable")
	state.action_resolved = true
	return _result(true, "Room action resolved", int(state.current_node_id))

func room_ready() -> bool:
	if state.is_empty() or state.phase != "room":
		return false
	return int(state.waves_cleared) >= int(state.wave_count) if _is_combat(_nodes[int(state.current_node_id)]) else bool(state.action_resolved)

func complete_room(elapsed_seconds: float = 0.0, hit_count: int = 0, target_health_percent: float = 100.0) -> Dictionary:
	if not room_ready() or not is_finite(elapsed_seconds) or elapsed_seconds < 0 or hit_count < 0 or not is_finite(target_health_percent):
		return _result(false, "Room objective is incomplete or result invalid")
	var node: Dictionary = _nodes[int(state.current_node_id)]
	if node.FightType == "ProtectTarget" and target_health_percent <= 0:
		fail()
		return _result(false, "Protected target defeated", int(node.Id))
	state.last_rank = rank(node, elapsed_seconds, hit_count, target_health_percent)
	state.phase = "reward"
	events.append({"type": "room_complete", "id": int(node.Id), "region": int(node.Region), "rank": state.last_rank, "fight_type": node.FightType, "elapsed": elapsed_seconds, "hit_count": hit_count, "boss": node.Flow == "Boss", "occurrence": state.layer_index})
	var result = _result(true, "Room completed", int(node.Id))
	result.rank = state.last_rank
	return result

func advance() -> Dictionary:
	if state.is_empty() or state.phase != "reward":
		return _result(false, "Reward is not available")
	state.layers[int(state.layer_index)].complete = true
	if not state.layers[int(state.layer_index)].has("completed_ids"): state.layers[int(state.layer_index)]["completed_ids"] = []
	state.layers[int(state.layer_index)].completed_ids.append(int(state.current_node_id))
	state.visited.append(int(state.current_node_id))
	if int(state.layer_index) + 1 >= state.layers.size():
		state.phase = "won"
		events.append({"type": "campaign_won", "difficulty": state.difficulty, "seed": state.seed})
	else:
		state.layer_index = int(state.layer_index) + 1
		state.current_node_id = 0
		state.phase = "route"
	return _result(true, "Reward claimed")

func fail() -> Dictionary:
	if state.is_empty() or state.phase == "won" or state.phase == "failed":
		return _result(false, "No active campaign")
	state.phase = "failed"
	events.append({"type": "campaign_failed", "id": state.current_node_id, "difficulty": state.difficulty})
	return _result(true, "Campaign failed")

func snapshot() -> Dictionary:
	return state.duplicate(true)

func restore(saved: Dictionary) -> bool:
	if _nodes.is_empty() and not configure():
		return false
	saved = saved.duplicate(true)
	# JSON uses floating point numbers; membership checks must use normalized IDs.
	if saved.get("layers") is Array:
		for layer in saved.layers:
			if layer is Dictionary and layer.get("node_ids") is Array:
				for index in range(layer.node_ids.size()):
					layer.node_ids[index] = int(layer.node_ids[index])
				layer.selected_id = int(layer.get("selected_id", 0))
				if layer.get("completed_ids") is Array: layer.completed_ids = layer.completed_ids.map(func(id): return int(id))
	if int(saved.get("version", 0)) != 1 or not PHASES.has(saved.get("phase")):
		return false
	var layers = saved.get("layers", [])
	var difficulty = int(saved.get("difficulty", -1))
	var index = int(saved.get("layer_index", -1))
	if not layers is Array or layers.is_empty() or index < 0 or index >= layers.size() or difficulty < 0 or difficulty > 10:
		return false
	for layer in layers:
		if not layer is Dictionary or not layer.get("node_ids", []) is Array or layer.get("node_ids", []).is_empty():
			return false
		for id in layer.node_ids:
			if not _nodes.has(int(id)) or int(_nodes[int(id)].Region) != int(layer.get("region", 0)) or not _eligible(_nodes[int(id)], difficulty):
				return false
		if int(layer.get("selected_id", 0)) != 0 and not layer.node_ids.has(layer.selected_id):
			return false
		for id in layer.get("completed_ids", []):
			if not layer.node_ids.has(int(id)): return false
	var current = int(saved.get("current_node_id", 0))
	if current != 0:
		if not layers[index].node_ids.has(current):
			return false
		var node: Dictionary = _nodes[current]
		var wave_count = int(saved.get("wave_count", 0))
		var cleared = int(saved.get("waves_cleared", -1))
		var max_wave = int(node.WaveMax)
		for spawn in node.ForcedSpawns:
			max_wave = maxi(max_wave, int(spawn.Wave))
		if cleared < 0 or cleared > wave_count or (_is_combat(node) and (wave_count < int(node.WaveMin) or wave_count > max_wave)):
			return false
		if saved.phase == "reward" and ((_is_combat(node) and cleared != wave_count) or (not _is_combat(node) and not bool(saved.get("action_resolved", false)))):
			return false
	elif saved.phase in ["room", "reward", "won"]:
		return false
	state = saved.duplicate(true)
	_build_connections()
	state["visited"] = state.get("visited", [])
	events.clear()
	return true

func drain_events() -> Array:
	var result = events
	events = []
	return result

func rank(node: Dictionary, elapsed: float, hits: int, target_hp: float) -> int:
	var data: Dictionary = node.get("FightData", {})
	match str(node.get("FightType", "")):
		"TimeLimit":
			return 3 if elapsed <= float(data.get("RewardTimeLimit_Lv3", 0)) else 2 if elapsed <= float(data.get("RewardTimeLimit_Lv2", 0)) else 1 if elapsed <= float(data.get("RewardTimeLimit_Lv1", 0)) else 0
		"ProtectTarget":
			return 3 if target_hp >= float(data.get("RemainTargetHp_Lv3", 100)) else 2 if target_hp >= float(data.get("RemainTargetHp_Lv2", 50)) else 1 if target_hp > 0 else 0
		"DodgeBattle":
			return 3 if hits <= int(data.get("BeHitCount_Lv3", 0)) else 2 if hits <= int(data.get("BeHitCount_Lv2", 1)) else 1 if hits <= int(data.get("BeHitCount_Lv1", 2)) else 0
	if node.Flow == "Boss":
		var times: Array = data.get("BossBattleRankTime", [])
		for index in range(times.size()):
			if elapsed <= float(times[index]):
				return times.size() - index
		return 0 if not times.is_empty() else 1
	return 1

func _eligible(node: Dictionary, difficulty: int) -> bool:
	return difficulty >= int(node.MinDifficulty) and difficulty <= int(node.MaxDifficulty)

func _is_combat(node: Dictionary) -> bool:
	return node.Flow == "Battle" or node.Flow == "Boss"

func _room_alias(node: Dictionary) -> Dictionary:
	var result = node.duplicate(true)
	result.node_id = int(node.Id)
	result.stage_id = int(node.StageId)
	result.environment_id = int(node.EnvironmentId)
	result.region = int(node.Region)
	result.node_type = int(node.Type)
	result.flow = str(node.Flow)
	result.name = str(node.Name)
	result.fight_type = str(node.FightType)
	result.player_start = node.PlayerStart
	result.combat = _is_combat(node)
	result.enemies = []
	result.rewards = []
	return result

func _spawn(node: Dictionary, id: int, index: int, forced: bool) -> Dictionary:
	var position: Dictionary = node.PlayerStart.duplicate()
	var found = false
	for point in node.SpawnPoints:
		if int(point.Id) == index:
			position = point.Position.duplicate()
			found = true
			break
	if not found:
		position.X = float(position.X) + 4.0
		position.Z = float(position.Z) + 4.0
	return {"EnemyId": id, "SpawnIndex": index, "Forced": forced, "Position": position, "enemy_id": id, "spawn_index": index, "forced": forced, "position": position, "health_override": 0.0, "attack_override": 0.0, "passive_buff_ids": []}

func _forced_spawn(node: Dictionary, spawn: Dictionary) -> Dictionary:
	var enemy = _spawn(node, int(spawn.EnemyId), int(spawn.SpawnIndex), true)
	for key in ["HealthOverride", "AttackOverride", "LevelOverride", "QuestEnemyId", "PassiveBuffIds", "CreateEnvironmentUnitIds"]:
		enemy[key] = spawn.get(key, [] if key.ends_with("Ids") else 0)
	enemy.health_override = enemy.HealthOverride
	enemy.attack_override = enemy.AttackOverride
	enemy.passive_buff_ids = enemy.PassiveBuffIds
	return enemy

func _report(message: String) -> void:
	if not diagnostics.has(message):
		diagnostics.append(message)
		events.append({"type": "diagnostic", "message": message})

func _weighted(nodes: Array) -> Dictionary:
	var total = 0
	for node in nodes:
		total += maxi(1, int(node.AppearChance))
	var value = _next_int(0, total)
	for node in nodes:
		value -= maxi(1, int(node.AppearChance))
		if value < 0:
			return node
	return nodes.back()

func _next_int(lower: int, upper: int) -> int:
	_random_state = (_random_state * 1664525 + 1013904223) & 0xffffffff
	return lower + (_random_state % maxi(1, upper - lower))

func _result(success: bool, message: String, id: int = 0) -> Dictionary:
	return {"success": success, "message": message, "id": id}
