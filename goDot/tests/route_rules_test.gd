extends SceneTree

var assertions := 0
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message)

func _initialize() -> void:
	var campaign = DungeonCampaign.new()
	campaign.configure()
	var signatures: Array = []
	for difficulty in range(11):
		for seed_value in [1, 17, 12345]:
			campaign.generate(seed_value, difficulty)
			if difficulty == 0: signatures.append(_topology(campaign.state.layers.slice(0, 7)))
			for index in campaign.state.layers.size() - 1:
				var layer: Dictionary = campaign.state.layers[index]
				var next: Array = campaign.state.layers[index + 1].node_ids
				var incoming: Array = []
				for id in layer.node_ids:
					var targets: Array = layer.connections[str(int(id))]
					check(not targets.is_empty(), "Every source has an outgoing route")
					for target in targets:
						check(next.has(int(target)), "Arrows only connect to the next column")
						if layer.node_ids.size() > 1 and next.size() > 1:
							check(absi(layer.node_ids.find(id) - next.find(int(target))) <= 1, "Forward diagonals only reach an adjacent lane")
						incoming.append(int(target))
					if layer.node_ids.size() == next.size(): check(targets.has(int(next[layer.node_ids.find(id)])), "Every room retains the APK's straight forward route")
				for id in next: check(incoming.has(int(id)), "Every room has an incoming route")
				check(layer.vertical_links.size() <= 1, "A generated column has at most one vertical link")
				for pair in layer.vertical_links:
					check(layer.node_ids.has(int(pair[0])) and layer.node_ids.has(int(pair[1])), "Vertical arrows stay within the column")
					check(absi(layer.node_ids.find(int(pair[0])) - layer.node_ids.find(int(pair[1]))) == 1, "Vertical arrows only connect adjacent lanes")
					check(pair.has(int(layer.node_ids[1])) and not campaign._nodes[int(layer.node_ids[1])].CanConnect, "Vertical arrows originate from an eligible center room")
	check(signatures[0] != signatures[1] and signatures[1] != signatures[2], "Different seeds produce different route connections")
	_generation_probability(campaign)
	_vertical_attribute_rules()
	campaign.generate(12345, 0)
	var same = DungeonCampaign.new()
	same.configure()
	same.generate(12345, 0)
	check(same.snapshot() == campaign.snapshot(), "The same seed reproduces rooms and connections")
	var random_state = campaign._random_state
	var topology = _topology(campaign.state.layers)
	for layer in campaign.state.layers:
		layer.erase("connections")
		layer.erase("vertical_links")
	campaign._build_connections()
	check(campaign._random_state == random_state and _topology(campaign.state.layers) == topology, "Topology migration preserves the gameplay RNG and the seed's routes")
	_fixture_connections(campaign)
	check(campaign.select_region(2).success, "World map confirms the first region before room selection")
	check(campaign.enter(int(campaign.choices()[0].node_id)).success, "Enter entrance")
	_complete(campaign)
	var middle = int(campaign.state.layers[1].node_ids[1])
	check(campaign.enter(middle).success, "Entrance branches to middle lane")
	_complete(campaign)
	var blocked = int(campaign.state.layers[2].node_ids[0])
	check(not campaign.enter(blocked).success, "Missing arrow blocks a next-column room")
	var vertical: Array = campaign.vertical_choices()
	check(vertical.size() == 1, "Authored vertical arrow exposes one adjacent room")
	var target = int(vertical[0].node_id)
	check(not campaign.enter(target).success, "Vertical movement requires explicit resource authorization")
	var snapshot = JSON.parse_string(JSON.stringify(campaign.snapshot()))
	var clone = DungeonCampaign.new()
	clone.configure()
	check(clone.restore(snapshot), "Route and arrows survive JSON restore")
	check(clone.state.layers[1].connections == campaign.state.layers[1].connections and clone.state.layers[1].vertical_links == campaign.state.layers[1].vertical_links, "Restore preserves the actual saved topology")
	check(clone.vertical_choices().size() == 1 and int(clone.vertical_choices()[0].node_id) == target, "Vertical destination survives restore")
	var legacy = snapshot.duplicate(true)
	for layer in legacy.layers: layer.erase("connection_version")
	check(clone.restore(legacy) and clone.state.layers[1].connections == campaign.state.layers[1].connections, "Unversioned saved routes keep their existing connections")
	_invalid_topology(snapshot)
	for layer in snapshot.layers:
		layer.erase("connections")
		layer.erase("vertical_links")
		layer.erase("completed_ids")
	check(clone.restore(snapshot), "Older saves without topology receive seeded APK connections")
	var middle_row = campaign.route_map().filter(func(row): return int(row.layer_index) == 1 and int(row.node_id) == middle)[0]
	var entrance = int(campaign.state.layers[0].selected_id)
	check(middle_row.passed_parents == [entrance], "Passed route records the entrance-to-middle traversal")
	check(campaign.enter(target, true).success and int(campaign.state.layer_index) == 1, "Vertical movement enters same-depth room")
	var lateral_row = campaign.route_map().filter(func(row): return int(row.layer_index) == 1 and int(row.node_id) == target)[0]
	check(lateral_row.passed_parents == [100000000 + middle], "Passed route records the actual direction of a lateral traversal")
	_complete(campaign)
	check(int(campaign.state.layer_index) == 2, "Vertical room rejoins next-column progression")
	check(campaign.state.layers[1].completed_ids.size() == 2, "Both completed rooms remain recorded")
	check(campaign.vertical_choices().is_empty(), "Completed vertical room cannot be farmed again")
	var forward = int(campaign.choices()[0].node_id)
	check(campaign.enter(forward).success, "Continue forward from the completed lateral room")
	var forward_row = campaign.route_map().filter(func(row): return int(row.layer_index) == 2 and int(row.node_id) == forward)[0]
	check(forward_row.passed_parents == [100000000 + target], "Passed forward path starts at the last lateral room, without highlighting alternate parents")
	_high_risk_preserves_topology()
	var catalog = DungeonCatalog.new()
	catalog.load_all()
	var profile = DungeonProfile.new()
	var systems = DungeonSystems.new(catalog, profile)
	systems.begin_run(12345, 1, 100)
	check(systems.search_point_count() == 0 and systems.search_point_max() == 3, "Search resource starts at 0/3")
	check(not systems.consume_route_shift().success, "No resource means no paid lane change")
	systems.effects.acquire(15102)
	check(systems.search_point_count() == 2, "Existing spirit-bottle item grants two points")
	check(systems.consume_route_shift().success and systems.search_point_count() == 1, "Lane change spends one point")
	systems.effects.acquire(15102)
	systems.effects.acquire(15101)
	check(systems.search_point_count() == 3, "Resource grant respects capacity")
	systems.effects.acquire(15103)
	check(systems.search_point_max() == 4 and systems.search_point_count() == 4, "Existing badge expands capacity before granting points")
	profile.data.run.inventory["22132"] = 1
	check(int(systems.route_shift_quote().cost) == 0, "Purified mushroom exempts route cost")
	systems.consume_route_shift()
	check(systems.search_point_count() == 4, "Exempt lane change keeps points")
	var report = {"assertions": assertions, "failures": failures, "passed": failures.is_empty()}
	FileAccess.open("res://reports/route-rules.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("ROUTE_RULES ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func _topology(layers: Array) -> Array:
	var result: Array = []
	for index in layers.size():
		var layer: Dictionary = layers[index]
		var next: Array = layers[index + 1].node_ids if index + 1 < layers.size() else []
		var forward: Array = []
		var vertical: Array = []
		for id in layer.node_ids:
			forward.append(layer.connections.get(str(int(id)), []).map(func(target): return next.find(int(target))))
		for pair in layer.vertical_links: vertical.append([layer.node_ids.find(int(pair[0])), layer.node_ids.find(int(pair[1]))])
		result.append({"connections": forward, "vertical_links": vertical})
	return result

func _fixture_connections(campaign: DungeonCampaign) -> void:
	var layer: Dictionary = campaign.state.layers[1]
	var next: Array = campaign.state.layers[2].node_ids
	for lane in layer.node_ids.size(): layer.connections[str(int(layer.node_ids[lane]))] = [int(next[lane])]
	layer.vertical_links = [[int(layer.node_ids[1]), int(layer.node_ids[2])]]

func _generation_probability(campaign: DungeonCampaign) -> void:
	var diagonal_count := 0
	var diagonal_trials := 0
	var vertical_count := 0
	var vertical_trials := 0
	for seed_value in range(1, 101):
		campaign.generate(seed_value, 0)
		for index in campaign.state.layers.size() - 1:
			var layer: Dictionary = campaign.state.layers[index]
			var next: Array = campaign.state.layers[index + 1].node_ids
			if layer.node_ids.size() == 3:
				if not campaign._nodes[int(layer.node_ids[1])].CanConnect:
					vertical_trials += 1
					vertical_count += layer.vertical_links.size()
				else: check(layer.vertical_links.is_empty(), "The packaged connectivity flag excludes vertical generation")
				if next.size() == 3:
					diagonal_trials += 4
					for targets in layer.connections.values(): diagonal_count += targets.size() - 1
	check(diagonal_count > diagonal_trials * 0.4 and diagonal_count < diagonal_trials * 0.6, "Seed sample follows independent 50-percent diagonal rolls")
	check(vertical_count > vertical_trials * 0.2 and vertical_count < vertical_trials * 0.4, "Seed sample follows the APK's base 30-percent vertical chance")

func _invalid_topology(snapshot: Dictionary) -> void:
	var clone = DungeonCampaign.new()
	clone.configure()
	var first = str(int(snapshot.layers[1].node_ids[0]))
	for invalid in [[], null, {"999999999": []}]:
		var damaged = snapshot.duplicate(true)
		damaged.layers[1].connections = invalid
		check(not clone.restore(damaged), "Malformed saved connections are rejected")
	for targets in [[], [999999999], [snapshot.layers[2].node_ids[0], snapshot.layers[2].node_ids[0]]]:
		var damaged = snapshot.duplicate(true)
		damaged.layers[1].connections[first] = targets
		check(not clone.restore(damaged), "Saved routes reject missing, unknown and duplicate destinations")
	var damaged = snapshot.duplicate(true)
	damaged.layers[1].vertical_links = [[damaged.layers[1].node_ids[0], damaged.layers[1].node_ids[2]]]
	check(not clone.restore(damaged), "Saved vertical links cannot skip the middle lane")
	for field in ["vertical_initial_roll", "vertical_initial_lane"]:
		damaged = snapshot.duplicate(true)
		damaged.layers[1][field] = 100
		check(not clone.restore(damaged), "Saved initial vertical rolls and directions are validated")
	damaged = snapshot.duplicate(true)
	damaged.layers[0]["vertical_attribute"] = 100
	damaged.layers[0]["vertical_refresh_count"] = -1
	check(not clone.restore(damaged), "Saved vertical refresh counters cannot be negative")

func _vertical_attribute_rules() -> void:
	var campaign = _vertical_fixture()
	var later: Array = campaign.snapshot().layers.slice(7)
	var random_state = campaign._random_state
	campaign.set_road_map_attributes({"RoadMapVerticalMoveChanceIncrease": 100.99})
	for layer in campaign.state.layers.slice(0, 7):
		if not campaign._can_generate_vertical(layer): continue
		check(not layer.vertical_links.is_empty() == (int(layer.vertical_initial_roll) < 40), "Initial attribute truncates before division and reuses the original strict chance roll")
		if not layer.vertical_links.is_empty(): check(layer.vertical_links[0] == [int(layer.node_ids[1]), int(layer.node_ids[int(layer.vertical_initial_lane)])], "Initial binding keeps the saved vertical direction")
	check(campaign.state.layers.slice(7) == later and campaign._random_state == random_state, "Initial attribute binding affects only the active module and preserves gameplay RNG")
	var bound = campaign.snapshot()
	campaign.set_road_map_attributes({"RoadMapVerticalMoveChanceIncrease": 100.1})
	check(campaign.snapshot() == bound, "An unchanged truncated attribute never rerolls when reopening a map")
	var clone = DungeonCampaign.new()
	clone.configure()
	check(clone.restore(JSON.parse_string(JSON.stringify(bound))), "Bound initial vertical rolls restore through JSON")
	check(_topology(clone.state.layers) == _topology(bound.layers) and int(clone.state.layers[0].vertical_attribute) == 100 and int(clone.state.layers[0].vertical_refresh_count) == 0, "Initial topology and bound attribute survive JSON restore")
	var restored = clone.snapshot()
	clone.set_road_map_attributes({"RoadMapVerticalMoveChanceIncrease": 100})
	check(clone.snapshot() == restored, "Rebinding the same attribute after reload never rerolls")
	var existing: Array = []
	for layer in campaign.state.layers.slice(0, 7): existing.append(layer.vertical_links.duplicate(true))
	campaign.set_road_map_attributes({"RoadMapVerticalMoveChanceIncrease": 700.99})
	for index in 7:
		var layer: Dictionary = campaign.state.layers[index]
		if campaign._can_generate_vertical(layer): check(layer.vertical_links.size() == 1, "A 100-percent refresh connects every missing eligible center")
		if not existing[index].is_empty(): check(layer.vertical_links == existing[index], "Attribute refresh preserves every existing vertical link")
	check(int(campaign.state.layers[0].vertical_refresh_count) == 1 and campaign._random_state == random_state, "One attribute change records one isolated refresh event")
	var refreshed = campaign.snapshot()
	check(clone.restore(JSON.parse_string(JSON.stringify(refreshed))), "A refreshed topology and counter restore through JSON")
	check(_topology(clone.state.layers) == _topology(refreshed.layers) and int(clone.state.layers[0].vertical_attribute) == 700 and int(clone.state.layers[0].vertical_refresh_count) == 1, "Refreshed topology and event counter survive JSON restore")
	restored = clone.snapshot()
	clone.set_road_map_attributes({"RoadMapVerticalMoveChanceIncrease": 700})
	check(clone.snapshot() == restored, "An unchanged attribute cannot refresh again after reload")
	clone.set_road_map_attributes({"RoadMapVerticalMoveChanceIncrease": -300})
	check(_topology(clone.state.layers) == _topology(refreshed.layers) and int(clone.state.layers[0].vertical_refresh_count) == 2, "Later negative attribute changes never remove existing links")
	var negative = _vertical_fixture()
	negative.set_road_map_attributes({"RoadMapVerticalMoveChanceIncrease": -300.99})
	check(negative.state.layers.slice(0, 7).all(func(layer): return layer.vertical_links.is_empty()), "An unstarted module applies a zero-percent initial threshold without premature base links")
	negative.set_road_map_attributes({"RoadMapVerticalMoveChanceIncrease": 1000})
	check(negative.state.layers.slice(0, 7).all(func(layer): return not negative._can_generate_vertical(layer) or layer.vertical_links.size() == 1), "Vertical refresh chance is capped at 100 percent")
	var started = _vertical_fixture()
	started.select_region(2)
	started.enter(int(started.choices()[0].node_id))
	var before = _topology(started.state.layers)
	started.set_road_map_attributes({"RoadMapVerticalMoveChanceIncrease": -300})
	check(_topology(started.state.layers) == before, "First attribute binding cannot remove links once the module has started")
	var legacy = _vertical_fixture().snapshot()
	for layer in legacy.layers:
		for field in ["vertical_initial_roll", "vertical_initial_lane", "vertical_attribute", "vertical_refresh_count"]: layer.erase(field)
	check(clone.restore(JSON.parse_string(JSON.stringify(legacy))), "Legacy topology without initial roll metadata still restores")
	clone.set_road_map_attributes({"RoadMapVerticalMoveChanceIncrease": 700})
	check(_topology(clone.state.layers) == _topology(legacy.layers), "The first attribute binding preserves legacy saved topology without refreshing")
	campaign.select_region(2)
	for room in 7:
		campaign.enter(int(campaign.choices()[0].node_id))
		_complete(campaign)
	var completed = campaign.snapshot().layers.slice(0, 7)
	campaign.set_road_map_attributes({"RoadMapVerticalMoveChanceIncrease": 100})
	for layer in campaign.state.layers.slice(7, 14):
		if campaign._can_generate_vertical(layer): check(not layer.vertical_links.is_empty() == (int(layer.vertical_initial_roll) < 40), "A future module initializes from the current attribute and its own original roll")
	check(campaign.state.layers.slice(0, 7) == completed, "Binding the next module never refreshes completed modules")
	later = campaign.snapshot().layers.slice(14)
	random_state = campaign._random_state
	check(campaign.select_region(3).success, "Lava replacement remains available in the attribute fixture")
	for layer in campaign.state.layers.slice(7, 14):
		if campaign._can_generate_vertical(layer): check(not layer.vertical_links.is_empty() == (int(layer.vertical_initial_roll) < 40), "A replacement module initializes from the inherited attribute before entry")
	check(int(campaign.state.layers[7].vertical_attribute) == 100 and int(campaign.state.layers[7].vertical_refresh_count) == 0, "Replacing a module binds its initial attribute without an extra refresh")
	check(campaign.state.layers.slice(0, 6) == completed.slice(0, 6) and campaign.state.layers.slice(14) == later and campaign._random_state == random_state, "Replacement attribute binding preserves unrelated routes and gameplay RNG")

func _vertical_fixture() -> DungeonCampaign:
	var campaign = DungeonCampaign.new()
	campaign.configure()
	var eligible: Array = []
	for seed_value in range(1, 101):
		campaign.generate(seed_value, 10)
		eligible.clear()
		for index in range(1, 6):
			if campaign._can_generate_vertical(campaign.state.layers[index]): eligible.append(index)
		if eligible.size() >= 4: break
	check(eligible.size() >= 4, "Vertical attribute fixture has four source-eligible centers")
	for index in eligible:
		var layer: Dictionary = campaign.state.layers[index]
		layer.vertical_initial_roll = 95
		layer.vertical_initial_lane = 2
		layer.vertical_links = []
	for position in 4:
		var layer: Dictionary = campaign.state.layers[int(eligible[position])]
		layer.vertical_initial_roll = [35, 15, 40, 39][position]
		layer.vertical_initial_lane = 0 if position % 2 == 0 else 2
		if int(layer.vertical_initial_roll) < 30: layer.vertical_links = [[int(layer.node_ids[1]), int(layer.node_ids[int(layer.vertical_initial_lane)])]]
	return campaign

func _high_risk_preserves_topology() -> void:
	var campaign = DungeonCampaign.new()
	campaign.configure()
	campaign.generate(87511, 10)
	var later = campaign.snapshot().layers.slice(7)
	var random_state = campaign._random_state
	check(campaign.select_region(1).success, "High-risk island can replace the first module")
	check(campaign.state.layers.slice(7) == later and campaign._random_state == random_state, "Replacing a region preserves every later room, route and gameplay RNG")
	check(campaign.state.layers[6].connections.values()[0] == campaign.state.layers[7].node_ids, "Replacement boss connects to the next module's entrance")
	for room in 7:
		check(campaign.enter(int(campaign.choices()[0].node_id)).success, "Complete the selected island route")
		_complete(campaign)
	var first = campaign.snapshot().layers.slice(0, 6)
	later = campaign.snapshot().layers.slice(14)
	check(campaign.select_region(3).success, "High-risk lava can replace the second module")
	check(campaign.state.layers.slice(0, 6) == first and campaign.state.layers.slice(14) == later, "Second-module replacement preserves unrelated module topology")
	check(campaign.state.layers[6].connections.values()[0] == campaign.state.layers[7].node_ids, "Previous boss now targets the replacement area's entrance")

func _complete(campaign: DungeonCampaign) -> void:
	if campaign.current_room().combat:
		while not campaign.room_ready(): campaign.clear_wave()
	elif campaign.current_room().flow == "TreasureTrial": campaign.decline_trial()
	else: campaign.resolve_action()
	campaign.complete_room()
	campaign.advance()
