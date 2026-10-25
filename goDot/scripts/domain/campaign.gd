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
var _enemy_rows: Dictionary = {}
var _spawn_settings: Dictionary = {}
var world_map_data: Dictionary = {}
var _areas: Dictionary = {}
var _world_modules: Array = []

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
	_areas.clear()
	for area in database.get("Areas", database.get("Regions", [])):
		_areas[int(area.Id)] = area
	world_map_data = {}
	_world_modules = []
	if FileAccess.file_exists("res://assets/data/RegionMapData.json"):
		var maps = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/RegionMapData.json"))
		if maps is Array:
			for map in maps:
				if map.get("IsActive", false):
					world_map_data = map
					_world_modules = map.get("ModuleList", [])
					break
	_enemy_rows.clear()
	if FileAccess.file_exists("res://assets/data/EnemyData.json"):
		for row in JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/EnemyData.json")):
			_enemy_rows[int(row.id)] = row
	if FileAccess.file_exists("res://assets/data/RogueConfigData.json"):
		_spawn_settings = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/RogueConfigData.json"))
	return not _nodes.is_empty()

func generate(seed_value: int, difficulty: int) -> Dictionary:
	if _nodes.is_empty() and not configure():
		return _result(false, "Missing campaign database")
	if difficulty < 0 or difficulty > 10:
		return _result(false, "Difficulty must be 0 through 10")
	_random_state = seed_value & 0xffffffff
	var layers: Array = []
	var defaults: Array = database.get("Regions", [])
	if defaults.size() != _world_modules.size() or defaults.is_empty():
		return _result(false, "Missing active world map modules")
	for module_index in defaults.size():
		var generated = _generate_region_layers(defaults[module_index], module_index, difficulty)
		if generated.is_empty(): return _result(false, "Empty route region %s" % defaults[module_index].Id)
		layers.append_array(generated)
	state = {"version": 1, "seed": seed_value, "difficulty": difficulty, "layer_index": 0, "module_index": 0, "selected_slot": 0, "world_slots": _empty_world_slots(), "current_node_id": 0, "phase": "route", "region_selection": true, "waves_cleared": 0, "wave_count": 0, "last_rank": 0, "spawn_group": 0, "action_resolved": false, "is_practice": false, "layers": layers, "visited": []}
	_build_connections()
	events.clear()
	return _result(true, "Campaign generated")

func _generate_region_layers(region: Dictionary, module_index: int, difficulty: int) -> Array:
	var layers: Array = []
	var appearances: Dictionary = {}
	var last = int(region.MiddleColumns) + 2
	for depth in range(1, last + 1):
		var candidates: Array = []
		for node in database.Nodes:
			if int(node.Region) != int(region.Id) or not _eligible(node, difficulty): continue
			var suitable: bool
			if depth == 1:
				suitable = node.Flow == "Entrance"
			elif depth == last:
				suitable = node.Flow == "Boss"
			else:
				suitable = node.Flow != "Entrance" and node.Flow != "Boss" and depth >= int(node.MinDepth) and depth <= int(node.MaxDepth)
			if suitable and (int(node.MaxAppearTime) <= 0 or int(appearances.get(int(node.Id), 0)) < int(node.MaxAppearTime)):
				candidates.append(node)
		if candidates.is_empty(): return []
		var width = 1 if depth == 1 or depth == last else mini(int(region.MaxRows), candidates.size())
		var selected: Array = []
		for row in range(width):
			var node = _weighted(candidates)
			selected.append(int(node.Id))
			candidates.erase(node)
			appearances[int(node.Id)] = int(appearances.get(int(node.Id), 0)) + 1
		layers.append({"region": int(region.Id), "module_index": module_index, "depth": depth, "node_ids": selected, "selected_id": 0, "complete": false})
	return layers

func region_choices() -> Array:
	if state.is_empty() or state.phase != "route" or not state.get("region_selection", false): return []
	var module_index = _pending_module(state)
	if module_index < 0: return []
	var result: Array = []
	for slot in _world_modules[module_index].get("SlotList", []):
		if _slot_unlocked(slot, int(state.difficulty)) and not _replacement_layers(int(slot.NodeLevel), module_index).is_empty():
			result.append(_world_slot_alias(slot, module_index))
	return result

func select_region(slot_id: int) -> Dictionary:
	var choices = region_choices().filter(func(slot): return int(slot.node_id) == slot_id)
	if choices.is_empty(): return _result(false, "World slot is not reachable", slot_id)
	var selected: Dictionary = choices[0]
	var module_index = current_module_index()
	if int(state.layers[int(state.layer_index)].region) != int(selected.region):
		var replacement = _replacement_layers(int(selected.region), module_index)
		if replacement.size() != _module_size(module_index): return _result(false, "Region has no complete route", slot_id)
		for index in replacement.size(): state.layers[_module_start(module_index) + index] = replacement[index]
		_build_connections()
	state.region_selection = false
	state.module_index = module_index
	state.selected_slot = slot_id
	state.world_slots[module_index] = slot_id
	events.append({"type": "region_select", "id": slot_id, "region": int(selected.region), "module_index": module_index, "occurrence": int(state.layer_index)})
	return _result(true, "Region selected", slot_id)

func region_map() -> Array:
	var result: Array = []
	if state.is_empty() or state.get("is_practice", false) or state.phase not in ["route", "room", "reward"]: return result
	var current = current_module_index()
	var pending = bool(state.get("region_selection", false))
	var chosen: Array = state.get("world_slots", _empty_world_slots())
	var anchor_slot = int(chosen[current - 1]) if pending and current > 0 else 0 if pending else int(chosen[current])
	var available = region_choices().map(func(region): return int(region.node_id))
	for module_index in _world_modules.size():
		var slots: Array = _world_modules[module_index].get("SlotList", [])
		for lane in slots.size():
			var slot: Dictionary = slots[lane]
			var row = _world_slot_alias(slot, module_index)
			var id = int(slot.Id)
			row.merge({"config_id": (module_index + 1) * 100000000 + id, "lane": lane, "lane_count": slots.size(), "parents": [], "vertical_neighbors": [], "visited": int(chosen[module_index]) == id and bool(state.layers[_module_start(module_index) + _module_size(module_index) - 1].complete), "current": not pending and module_index == current and int(chosen[module_index]) == id, "is_anchor": id == anchor_slot, "available": available.has(id), "unknown": not slot.get("IsOpen", false) and int(slot.NodeLevel) == 0, "locked": slot.get("IsOpen", false) and not _slot_unlocked(slot, int(state.difficulty))})
			if module_index > 0:
				for previous in _world_modules[module_index - 1].get("SlotList", []): row.parents.append(module_index * 100000000 + int(previous.Id))
			result.append(row)
	return result

func _world_slot_alias(slot: Dictionary, module_index: int) -> Dictionary:
	var row = slot.duplicate(true)
	row.merge({"node_id": int(slot.Id), "slot_id": int(slot.Id), "region": int(slot.NodeLevel), "module_index": module_index, "progress_region": module_index + 1, "layer_index": module_index + 1, "name": str(slot.Name), "description": str(slot.get("Desc", "")), "map_mode": "world", "map_scope": "world", "world_icon": str(slot.get("IconName", "")), "high_risk": bool(slot.get("IsHighRisk", false)), "is_high_risk": bool(slot.get("IsHighRisk", false)), "clear_boss_ids": slot.get("ClearBossEnemyIdList", []).duplicate(), "extra_rewards": slot.get("ExtraRewardList", []).duplicate(true), "lock_reason": str(slot.get("UnlockDesc", "")) if slot.get("IsOpen", false) else str(slot.get("UnopenDesc", ""))})
	return row

func _slot_unlocked(slot: Dictionary, difficulty: int) -> bool:
	if not slot.get("IsOpen", false) or slot.get("IsAdminOnly", false): return false
	match int(slot.get("UnlockConditionType", 0)):
		0: return true
		1053: return difficulty >= int(slot.get("UnlockParam1", 0))
	return false

func _replacement_layers(area_id: int, module_index: int) -> Array:
	if not _areas.has(area_id): return []
	var previous_random_state = _random_state
	_random_state = (int(state.seed) ^ area_id * 65537 ^ module_index * 397) & 0xffffffff
	var layers = _generate_region_layers(_areas[area_id], module_index, int(state.difficulty))
	_random_state = previous_random_state
	return layers if layers.size() == _module_size(module_index) else []

func current_module_index() -> int:
	return _module_for_layer(int(state.get("layer_index", 0))) if not state.is_empty() and not state.get("is_practice", false) else 0

func _module_for_layer(layer_index: int) -> int:
	for module_index in database.get("Regions", []).size():
		if layer_index >= _module_start(module_index) and layer_index < _module_start(module_index) + _module_size(module_index): return module_index
	return -1

func _module_start(module_index: int) -> int:
	var start = 0
	for index in module_index: start += _module_size(index)
	return start

func _module_size(module_index: int) -> int:
	return int(database.get("Regions", [])[module_index].MiddleColumns) + 2

func _empty_world_slots() -> Array:
	var slots: Array = []
	slots.resize(_world_modules.size())
	slots.fill(0)
	return slots

func _pending_module(candidate: Dictionary) -> int:
	if candidate.get("is_practice", false): return -1
	var index = int(candidate.get("layer_index", -1))
	var layers: Array = candidate.get("layers", [])
	var module_index = _module_for_layer(index)
	if module_index < 0 or index != _module_start(module_index) or index >= layers.size(): return -1
	if int(candidate.get("current_node_id", 0)) != 0 or layers[index].get("complete", false) or int(layers[index].get("selected_id", 0)) != 0: return -1
	for id in layers[index].get("node_ids", []):
		if not _nodes.has(int(id)) or _nodes[int(id)].Flow != "Entrance": return -1
	if module_index == 0: return module_index
	var previous: Dictionary = layers[index - 1]
	if not previous.get("complete", false): return -1
	var previous_id = int(previous.get("selected_id", 0))
	if not _nodes.has(previous_id) or _nodes[previous_id].Flow != "Boss": return -1
	return module_index

func _restore_world_state(saved: Dictionary) -> bool:
	if saved.has("region_selection") and not saved.region_selection is bool: return false
	var index = int(saved.layer_index)
	if not saved.has("region_selection"):
		saved["region_selection"] = saved.phase == "route" and int(saved.layers[index].get("depth", 0)) == 1 and not saved.get("is_practice", false)
	if bool(saved.region_selection) and saved.phase != "route": return false
	if saved.get("is_practice", false):
		if saved.region_selection: return false
		saved["module_index"] = 0
		saved["selected_slot"] = 0
		saved["world_slots"] = _empty_world_slots()
		return true
	var module_index = _module_for_layer(index)
	if module_index < 0 or _world_modules.size() != database.get("Regions", []).size(): return false
	var total = _module_start(_world_modules.size())
	if saved.layers.size() != total: return false
	var areas: Array = []
	for module in _world_modules.size():
		var start = _module_start(module)
		var area_id = int(saved.layers[start].region)
		areas.append(area_id)
		for depth in _module_size(module):
			var layer: Dictionary = saved.layers[start + depth]
			if int(layer.region) != area_id or int(layer.get("depth", 0)) != depth + 1: return false
			if layer.has("module_index") and (not _whole_number(layer.module_index) or int(layer.module_index) != module): return false
			layer["module_index"] = module
	var chosen: Array = []
	if saved.has("world_slots"):
		if not saved.world_slots is Array or saved.world_slots.size() != _world_modules.size(): return false
		for id in saved.world_slots:
			if not _whole_number(id) or int(id) < 0: return false
			chosen.append(int(id))
	else:
		chosen = _empty_world_slots()
		for module in module_index + 1:
			if module == module_index and saved.region_selection: continue
			if module == module_index and saved.phase == "failed" and int(saved.current_node_id) == 0 and int(saved.layers[index].depth) == 1: continue
			for slot in _world_modules[module].get("SlotList", []):
				if int(slot.NodeLevel) == int(areas[module]): chosen[module] = int(slot.Id)
	var active_selected = not saved.region_selection and not (saved.phase == "failed" and int(saved.current_node_id) == 0 and int(saved.layers[index].depth) == 1 and int(chosen[module_index]) == 0)
	for module in _world_modules.size():
		var should_be_selected = module < module_index or (module == module_index and active_selected)
		if should_be_selected:
			if int(chosen[module]) == 0: return false
			var matches: Array = _world_modules[module].get("SlotList", []).filter(func(slot): return int(slot.Id) == int(chosen[module]) and int(slot.NodeLevel) == int(areas[module]))
			if matches.is_empty() or not _slot_unlocked(matches[0], int(saved.difficulty)): return false
			if module < module_index:
				var last: Dictionary = saved.layers[_module_start(module) + _module_size(module) - 1]
				var boss = int(last.get("selected_id", 0))
				if not last.get("complete", false) or not _nodes.has(boss) or _nodes[boss].Flow != "Boss": return false
		elif int(chosen[module]) != 0 or int(areas[module]) != int(database.Regions[module].Id):
			return false
	var selected_slot = int(chosen[module_index])
	if saved.has("selected_slot") and (not _whole_number(saved.selected_slot) or int(saved.selected_slot) != selected_slot): return false
	if saved.has("module_index") and (not _whole_number(saved.module_index) or int(saved.module_index) != module_index): return false
	if saved.region_selection and _pending_module(saved) != module_index: return false
	if saved.phase == "route" and int(saved.layers[index].depth) == 1 and _pending_module(saved) != module_index: return false
	saved["world_slots"] = chosen
	saved["selected_slot"] = selected_slot
	saved["module_index"] = module_index
	return true

func _whole_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))

func choices() -> Array:
	var result: Array = []
	if state.is_empty() or state.phase != "route" or state.get("region_selection", false):
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
	if state.is_empty() or state.phase != "route" or state.get("region_selection", false): return result
	var anchor = route_anchor()
	if anchor.is_empty(): return result
	var layer: Dictionary = state.layers[int(anchor.layer_index)]
	if int(layer.get("module_index", 0)) != current_module_index(): return result
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
		var module_index = int(layer.get("module_index", 0))
		var default_area = int(database.Regions[module_index].Id) if module_index < database.get("Regions", []).size() else int(layer.region)
		var rule: Dictionary = route_rules.get("regions", {}).get(str(int(layer.region)), route_rules.get("regions", {}).get(str(default_area), {}))
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
	if state.is_empty() or state.phase not in ["route", "room", "reward"]: return result
	var current = int(state.layer_index)
	if current < 0 or current >= state.layers.size(): return result
	var region = int(state.layers[current].region)
	var reachable = choices().map(func(room): return int(room.node_id))
	var vertical = vertical_choices().map(func(room): return int(room.node_id))
	var anchor = route_anchor()
	if state.phase != "route":
		anchor = {"layer_index": current, "node_id": int(state.current_node_id)}
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
			room["current"] = state.phase != "route" and bool(room.is_anchor)
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
	if state.is_empty() or state.phase != "route" or state.get("region_selection", false):
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
	state.wave_count = _next_int(int(room.WaveMin), int(room.WaveMax) + 1) if _is_combat(room) and bool(room.RandomEnemies) else 0
	var groups: Array = []
	for spawn in room.ForcedSpawns:
		if int(spawn.Group) > 0 and not groups.has(int(spawn.Group)):
			groups.append(int(spawn.Group))
	_random_state = (int(state.seed) ^ node_id) & 0xffffffff
	state.spawn_group = groups[_next_int(0, groups.size())] if not groups.is_empty() else 0
	for spawn in room.ForcedSpawns:
		if bool(room.ManualEnemies) and int(spawn.EnemyId) > 0 and (int(spawn.Group) == 0 or int(spawn.Group) == int(state.spawn_group)):
			state.wave_count = maxi(int(state.wave_count), int(spawn.Wave))
	state["spawn_plan"] = _build_spawn_plan(room)
	state["spawn_plan_version"] = 2
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
	state = {"version": 1, "seed": seed_value, "difficulty": int(node.MinDifficulty), "layer_index": 0, "module_index": 0, "selected_slot": 0, "world_slots": _empty_world_slots(), "current_node_id": 0, "phase": "route", "region_selection": false, "waves_cleared": 0, "wave_count": 0, "last_rank": 0, "spawn_group": 0, "action_resolved": false, "is_practice": true, "layers": [{"region": int(node.Region), "module_index": 0, "depth": maxi(1, int(node.MinDepth)), "node_ids": [node_id], "selected_id": 0, "complete": false}], "visited": []}
	return enter(node_id)

func wave_spawns(wave: int) -> Array:
	if state.is_empty() or state.phase != "room" or wave < 1 or wave > int(state.wave_count):
		return []
	var room: Dictionary = _nodes[int(state.current_node_id)]
	if not _is_combat(room):
		return []
	if not state.has("spawn_plan"):
		state["spawn_plan"] = _build_spawn_plan(room)
	return state.spawn_plan.get(str(wave), []).duplicate(true)

func _build_spawn_plan(room: Dictionary) -> Dictionary:
	var plan: Dictionary = {}
	if not _is_combat(room): return plan
	_random_state = (int(state.seed) ^ int(room.Id) ^ 0x53504157) & 0xffffffff
	var species: Array = []
	if bool(room.RandomEnemies):
		for rate in ["Elite", "Normal"]:
			var candidates: Array = []
			for id in room.EnemyIds:
				var row: Dictionary = _enemy_rows.get(int(id), {})
				if row.get("enemy_rate", "") == rate and float(row.get("difficulty", 0)) > 0:
					candidates.append(row)
			var lower = int(room.get("EliteTypeMin", 0) if rate == "Elite" else room.get("EnemyTypeMin", 0))
			var upper = int(room.get("EliteTypeMax", lower) if rate == "Elite" else room.get("EnemyTypeMax", lower))
			for index in mini(candidates.size(), _next_int(lower, maxi(lower, upper) + 1)):
				species.append(candidates.pop_at(_next_int(0, candidates.size())))
	var percentages: Array = []
	var patterns: Array = database.get("WavePatterns", []).filter(func(pattern): return int(pattern.TotWaveCount) == int(state.wave_count))
	if not patterns.is_empty():
		var total_weight = 0
		for pattern in patterns: total_weight += maxi(1, int(pattern.SelectWeight))
		var pick = _next_int(0, total_weight)
		for pattern in patterns:
			pick -= maxi(1, int(pattern.SelectWeight))
			if pick < 0:
				percentages = pattern.DifficultyPercent
				break
	for wave in range(1, int(state.wave_count) + 1):
		var enemies: Array = []
		var points: Array = room.SpawnPoints.duplicate(true)
		var forced: Array = room.ForcedSpawns.filter(func(spawn): return bool(room.ManualEnemies) and int(spawn.EnemyId) > 0 and (int(spawn.Group) == 0 or int(spawn.Group) == int(state.spawn_group)) and _matches_wave(int(spawn.Wave), wave, int(state.wave_count)))
		for spawn in forced:
			var found = points.filter(func(point): return int(point.Id) == int(spawn.SpawnIndex))
			if found.is_empty():
				_report("Invalid forced spawn point: node %s wave %s point %s" % [room.Id, wave, spawn.SpawnIndex])
				continue
			enemies.append(_forced_spawn(room, spawn))
			points.erase(found[0])
		var random_ids: Array = []
		var percent = float(percentages[wave - 1]) if wave <= percentages.size() else 1.0 / maxi(1, int(state.wave_count))
		var remaining_budget = float(room.get("MaxEnemyDifficulty", 0)) * percent
		var average = remaining_budget / maxi(1, species.size())
		for index in species.size():
			var allocation = average + average / 3.0 * (_next_unit() * 2.0 - 1.0)
			if index == species.size() - 1 or allocation > remaining_budget: allocation = remaining_budget
			var cost = float(species[index].difficulty)
			var count = int(allocation / cost)
			for amount in maxi(1, count): random_ids.append(int(species[index].id))
			remaining_budget -= cost * count
		var nearby: Array = points.filter(func(point):
			var distance = _point_distance(point.Position, room.PlayerStart)
			return distance > float(_spawn_settings.get("EnemyRandomCreateDistanceToPlayerMin", 10)) and distance < float(_spawn_settings.get("EnemyRandomCreateDistanceToPlayerMax", 25)))
		for id in random_ids:
			if points.is_empty(): break
			var pool: Array = nearby if not nearby.is_empty() else points
			var point: Dictionary = pool[_next_int(0, pool.size())]
			enemies.append(_spawn(room, id, int(point.Id), false))
			points.erase(point)
			nearby.erase(point)
		plan[str(wave)] = enemies
	return plan

func _matches_wave(authored: int, wave: int, total: int) -> bool:
	return authored == wave if authored > 0 else authored == wave - total - 1

func _point_distance(a: Dictionary, b: Dictionary) -> float:
	return Vector3(float(a.get("X", 0)) - float(b.get("X", 0)), float(a.get("Y", 0)) - float(b.get("Y", 0)), float(a.get("Z", 0)) - float(b.get("Z", 0))).length()

func _next_unit() -> float:
	return float(_next_int(0, 16777216)) / 16777216.0

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
		state.region_selection = false
		events.append({"type": "campaign_won", "difficulty": state.difficulty, "seed": state.seed})
	else:
		var previous_module = current_module_index()
		state.layer_index = int(state.layer_index) + 1
		state.current_node_id = 0
		state.phase = "route"
		state.module_index = current_module_index()
		state.region_selection = int(state.module_index) != previous_module
		if state.region_selection: state.selected_slot = 0
	return _result(true, "Reward claimed")

func fail() -> Dictionary:
	if state.is_empty() or state.phase == "won" or state.phase == "failed":
		return _result(false, "No active campaign")
	state.phase = "failed"
	state.region_selection = false
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
		if not saved.has("spawn_plan") and bool(node.ManualEnemies) and not bool(node.RandomEnemies):
			var authored_count = 0
			for spawn in node.ForcedSpawns:
				if int(spawn.EnemyId) > 0 and (int(spawn.Group) == 0 or int(spawn.Group) == int(saved.get("spawn_group", 0))):
					authored_count = maxi(authored_count, int(spawn.Wave))
			if authored_count > 0:
				wave_count = authored_count
				cleared = mini(cleared, authored_count)
				saved.wave_count = wave_count
				saved.waves_cleared = cleared
		var min_wave = int(node.WaveMin) if bool(node.RandomEnemies) else 1
		if cleared < 0 or cleared > wave_count or (_is_combat(node) and (wave_count < min_wave or wave_count > max_wave)):
			return false
		if saved.phase == "reward" and ((_is_combat(node) and cleared != wave_count) or (not _is_combat(node) and not bool(saved.get("action_resolved", false)))):
			return false
	elif saved.phase in ["room", "reward", "won"]:
		return false
	if not _restore_world_state(saved): return false
	state = saved.duplicate(true)
	if current != 0 and not state.has("spawn_plan"):
		state["spawn_plan"] = _build_spawn_plan(_nodes[current])
		state["spawn_plan_version"] = 2
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
	result.module_index = 0
	for index in _world_modules.size():
		if _world_modules[index].get("SlotList", []).any(func(slot): return int(slot.NodeLevel) == int(node.Region)):
			result.module_index = index
			break
	result.progress_region = int(result.module_index) + 1
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
	var rotation: Dictionary = {}
	var found = false
	for point in node.SpawnPoints:
		if int(point.Id) == index:
			position = point.Position.duplicate()
			rotation = point.get("Rotation", {}).duplicate()
			found = true
			break
	if not found:
		position.X = float(position.X) + 4.0
		position.Z = float(position.Z) + 4.0
	return {"EnemyId": id, "SpawnIndex": index, "Forced": forced, "Position": position, "Rotation": rotation, "enemy_id": id, "spawn_index": index, "forced": forced, "position": position, "rotation": rotation, "born_position": position.duplicate(), "health_override": 0.0, "attack_override": 0.0, "passive_buff_ids": []}

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
