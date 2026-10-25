extends SceneTree

const Campaign = preload("res://scripts/domain/campaign.gd")
const NORMAL_SLOTS = [2, 4, 6, 8, 9]
var assertions := 0
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message)

func _initialize() -> void:
	var campaign = _clone()
	check(campaign.region_choices().is_empty() and campaign.region_map().is_empty(), "No world map before a run")
	check(campaign.generate(12345, 0).success, "Campaign generates")
	check(campaign.state.layers.size() == 35, "Five world modules preserve 35 room layers")
	var initial = campaign.snapshot()
	var map = campaign.region_map()
	check(map.size() == 9, "Active RegionMapData contains nine actual world slots")
	var areas = [6, 1, 7, 2, 0, 3, 0, 4, 5]
	for index in map.size():
		var row: Dictionary = map[index]
		check(int(row.node_id) == index + 1 and int(row.region) == int(areas[index]), "World slot IDs stay distinct from area IDs")
		check(row.map_mode == "world" and not str(row.world_icon).is_empty(), "World map preserves the authored icon")
		check(int(row.config_id) == int(row.layer_index) * 100000000 + int(row.node_id), "World paths use the shared config identity")
		check(row.parents.size() == (0 if int(row.module_index) == 0 else 2), "Every adjacent module exposes both incoming branches")
		if int(row.node_id) in [5, 7]: check(row.unknown and not row.available and not row.IsOpen, "Authored unknown slots remain closed")
		if int(row.node_id) in [1, 3]:
			check(row.locked and not row.available, "High-risk branches retain their difficulty lock")
			check(row.high_risk and row.clear_boss_ids.size() == 1 and row.extra_rewards.size() == 1 and not str(row.description).is_empty(), "High-risk rows retain warning, boss-history and bonus metadata")
	check(_ids(campaign) == [2], "Ordinary opening offers forest slot two")
	check(campaign.choices().is_empty() and campaign.vertical_choices().is_empty(), "World confirmation gates all room choices")
	check(campaign.route_map().all(func(row): return not row.available and not row.vertical), "Unconfirmed small-map preview is read only")
	var entrance = int(campaign.state.layers[0].node_ids[0])
	check(not campaign.enter(entrance).success and not campaign.enter(entrance, true).success, "Room entry cannot bypass world confirmation")
	for id in [0, 1, 3, 4, 5, 7, 9, 10]: check(not campaign.select_region(id).success, "Locked, closed, future and unknown slots are rejected")
	check(campaign.snapshot() == initial, "Rejected selections never mutate progress")
	_restore(initial, true, "New pending snapshot")
	_restore(_legacy(initial), true, "Old initial route")
	var failed = _clone()
	failed.restore(initial)
	failed.fail()
	_restore(failed.snapshot(), false, "Failure before world confirmation")
	for flag in ["true", 1]:
		var bad = initial.duplicate(true)
		bad.region_selection = flag
		check(not _clone().restore(bad), "Selection field requires a boolean")
	var malformed = initial.duplicate(true)
	malformed.world_slots[1] = 4
	check(not _clone().restore(malformed), "Future modules cannot be preselected")
	malformed = initial.duplicate(true)
	malformed.module_index = 1
	check(not _clone().restore(malformed), "Saved module must match current room depth")
	check(campaign.select_region(2).success, "Confirm forest slot")
	check(campaign.state.world_slots == [2, 0, 0, 0, 0] and int(campaign.state.selected_slot) == 2, "Slot history records map identity separately from area")
	check(campaign.state.phase == "route" and int(campaign.state.current_node_id) == 0, "Region selection leaves room entry to the application")
	check(campaign.state.layers == initial.layers, "Normal slot selection preserves its generated rooms")
	check(not campaign.select_region(2).success and not campaign.select_region(1).success, "Confirmed module cannot be redirected")
	_restore(campaign.snapshot(), false, "Confirmed world slot")
	failed.restore(campaign.snapshot())
	failed.fail()
	_restore(failed.snapshot(), false, "Failure after world confirmation but before room entry")
	check(campaign.enter(entrance).success, "Enter confirmed forest entrance")
	_restore(_legacy(campaign.snapshot()), false, "Old active entrance")
	malformed = campaign.snapshot()
	malformed.selected_slot = 1
	check(not _clone().restore(malformed), "Selected slot must match slot history")
	malformed.world_slots[0] = 1
	check(not _clone().restore(malformed), "Selected slot must match the actual room area")
	var completed := 0
	while campaign.state.phase != "won" and completed < 40:
		if campaign.state.region_selection:
			var module = campaign.current_module_index()
			var before = campaign.snapshot()
			check(_ids(campaign) == [NORMAL_SLOTS[module]], "Boundary offers the next module's ordinary slot")
			check(int(campaign.state.selected_slot) == 0 and campaign.choices().is_empty() and campaign.vertical_choices().is_empty(), "Boundary blocks forward entry and backward lane changes")
			check(not campaign.enter(int(campaign.state.layers[int(campaign.state.layer_index)].node_ids[0])).success, "Next entrance requires world confirmation")
			check(not campaign.select_region(NORMAL_SLOTS[module - 1]).success and not campaign.select_region(9 if module < 4 else 2).success, "Completed and future modules cannot be selected")
			check(campaign.snapshot() == before, "Rejected boundary actions preserve state")
			var previous = campaign.region_map().filter(func(row): return int(row.node_id) == NORMAL_SLOTS[module - 1])
			check(previous[0].visited and previous[0].is_anchor, "Completed slot anchors the pending world map")
			_restore(before, true, "Pending module")
			_restore(_legacy(before), true, "Old module boundary")
			malformed = before.duplicate(true)
			malformed.layers[int(malformed.layer_index) - 1].complete = false
			check(not _clone().restore(malformed), "Next module requires the previous boss to be completed")
			check(campaign.select_region(NORMAL_SLOTS[module]).success, "Confirm next ordinary slot")
			check(campaign.vertical_choices().is_empty(), "Next module cannot move back into the previous module")
		if campaign.state.phase == "route" and not _enter(campaign): break
		_complete(campaign)
		completed += 1
		if completed == 1:
			_restore(_legacy(campaign.snapshot()), false, "Old middle-column route")
			malformed = campaign.snapshot()
			malformed.region_selection = true
			check(not _clone().restore(malformed), "Middle column cannot impersonate a world boundary")
	check(campaign.state.phase == "won" and completed == 35 and campaign.state.visited.size() == 35, "Ordinary route wins after exactly 35 rooms")
	check(campaign.state.world_slots == NORMAL_SLOTS and campaign.region_choices().is_empty(), "Victory preserves all confirmed ordinary slots")
	_restore(campaign.snapshot(), false, "Victory")
	check(not campaign.select_region(2).success and not campaign.enter(entrance, true).success, "Victory cannot replay prior modules")
	_high_risk()
	check(campaign.start_practice(entrance, 17).success and not campaign.state.region_selection, "Practice bypasses world selection")
	_restore(_legacy(campaign.snapshot()), false, "Old practice room")
	print("WORLD_MAP_RULES ", JSON.stringify({"passed": failures.is_empty(), "assertions": assertions, "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func _high_risk() -> void:
	var missing = _clone()
	missing.generate(87511, 0)
	missing.world_map_data.ModuleList[0].SlotList[0].UnlockConditionType = 0
	check(not missing.select_region(1).success and _ids(missing) == [2], "Missing eligible rooms block high-risk selection even if a lock is bypassed")
	var campaign = _clone()
	campaign.generate(87511, 9)
	check(_ids(campaign) == [2], "Difficulty nine cannot select the island")
	campaign.generate(87511, 10)
	check(_ids(campaign) == [1, 2], "Chaos difficulty exposes island and forest")
	if _ids(campaign) != [1, 2]: return
	var defaults: Array = campaign.snapshot().layers
	check(campaign.select_region(1).success, "Confirm island slot one")
	check(campaign.state.layers.size() == 35 and campaign.state.layers.slice(0, 7).all(func(layer): return int(layer.region) == 6), "Island replaces the first seven layers with area six")
	check(campaign.state.layers.slice(7) == defaults.slice(7), "Island selection preserves later module generation")
	var same = _clone()
	same.generate(87511, 10)
	same.select_region(1)
	check(same.state.layers == campaign.state.layers, "Seed and slot reproduce identical island rooms")
	for room in 7:
		if not _enter(campaign): return
		check(int(campaign.current_room().region) == 6 and int(campaign.current_room().progress_region) == 1, "Island room identity is separate from first-module economic progression")
		_complete(campaign)
	check(campaign.state.region_selection and campaign.current_module_index() == 1 and _ids(campaign) == [3, 4], "Island completion returns to module two")
	check(campaign.select_region(3).success, "Confirm lava slot three")
	check(campaign.state.layers.size() == 35 and campaign.state.layers.slice(7, 14).all(func(layer): return int(layer.region) == 7), "Lava replaces module two with area seven")
	if not _enter(campaign): return
	check(int(campaign.current_room().region) == 7 and int(campaign.current_room().progress_region) == 2, "Lava room identity is separate from second-module economic progression")
	_restore(campaign.snapshot(), false, "Active lava room")
	_restore(_legacy(campaign.snapshot()), false, "Legacy high-risk room")
	_complete(campaign)
	for room in 6:
		if not _enter(campaign): return
		_complete(campaign)
	check(campaign.state.region_selection and campaign.current_module_index() == 2 and _ids(campaign) == [6], "Lava returns to module three instead of following numeric area order")
	check(campaign.state.world_slots == [1, 3, 0, 0, 0] and int(campaign.state.layers[int(campaign.state.layer_index)].region) == 3, "Branch history is independent of descending area IDs")
	_restore(campaign.snapshot(), true, "High-risk module boundary")
	while campaign.state.phase != "won" and campaign.state.visited.size() < 40:
		if campaign.state.region_selection:
			var choices = campaign.region_choices()
			if choices.is_empty():
				check(false, "Remaining route has a reachable module")
				return
			campaign.select_region(int(choices[0].node_id))
		if not _enter(campaign): return
		_complete(campaign)
	check(campaign.state.phase == "won" and campaign.state.visited.size() == 35 and campaign.state.world_slots == [1, 3, 6, 8, 9], "High-risk route still wins after five modules and 35 rooms")
	_restore(campaign.snapshot(), false, "High-risk victory")

func _enter(campaign: RefCounted) -> bool:
	var rooms = campaign.choices()
	check(not rooms.is_empty(), "Selected module offers a room")
	if rooms.is_empty(): return false
	var success: bool = campaign.enter(int(rooms[0].node_id)).success
	check(success, "Enter selected-module room")
	return success

func _complete(campaign: RefCounted) -> void:
	if campaign.current_room().combat:
		while not campaign.room_ready(): campaign.clear_wave()
	else: campaign.resolve_action()
	check(campaign.complete_room().success, "Room objective completes")
	check(campaign.advance().success, "Room completion advances once")

func _ids(campaign: RefCounted) -> Array:
	return campaign.region_choices().map(func(slot): return int(slot.node_id))

func _clone() -> RefCounted:
	var campaign = Campaign.new()
	check(campaign.configure(), "Campaign configures")
	return campaign

func _legacy(snapshot: Dictionary) -> Dictionary:
	var saved = snapshot.duplicate(true)
	for key in ["region_selection", "module_index", "selected_slot", "world_slots"]: saved.erase(key)
	for layer in saved.layers: layer.erase("module_index")
	return saved

func _restore(snapshot: Dictionary, pending: bool, message: String) -> void:
	var campaign = _clone()
	var saved = JSON.parse_string(JSON.stringify(snapshot))
	var success: bool = campaign.restore(saved)
	check(success, message + " restores")
	if not success: return
	check(campaign.state.region_selection == pending and int(campaign.state.layer_index) == int(snapshot.layer_index) and int(campaign.state.current_node_id) == int(snapshot.current_node_id), message + " preserves selection and room")
	check(campaign.state.layers.map(func(layer): return layer.node_ids) == snapshot.layers.map(func(layer): return layer.node_ids), message + " preserves generated rooms")
	check(campaign.state.phase == snapshot.phase and int(campaign.state.waves_cleared) == int(snapshot.waves_cleared) and int(campaign.state.wave_count) == int(snapshot.wave_count), message + " preserves objective progress")
	check(campaign.state.get("spawn_plan", {}) == saved.get("spawn_plan", {}) and campaign.state.visited.map(func(id): return int(id)) == snapshot.visited.map(func(id): return int(id)), message + " preserves spawns and room history")
