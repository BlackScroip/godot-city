extends SceneTree

var failures: Array[String] = []
var assertions := 0

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message)

func _initialize() -> void:
	var campaign = DungeonCampaign.new()
	check(campaign.configure(), "Campaign source data loads")
	check(campaign.generate(12345, 0).success, "Campaign generates hidden rolls")
	for layer in campaign.state.layers:
		check(layer.hide_rolls.size() == layer.node_ids.size(), "Every node occurrence receives one saved roll")
		for roll in layer.hide_rolls.values(): check(roll >= 0 and roll < 1000, "Roll is an integer in [0, 1000)")
	var original = campaign.snapshot()
	var node_id = int(campaign.state.layers[1].node_ids[0])
	for threshold in [-1, 0, 1, 500, 999, 1000, 1001]:
		campaign.set_road_map_attributes({"RandomHideRogueRoadMapNodeChance": threshold})
		for roll in range(1000):
			campaign.state.layers[1].hide_rolls[str(node_id)] = roll
			check(campaign.is_node_hidden(1, node_id) == (roll < threshold), "Native strict comparison threshold=%d roll=%d" % [threshold, roll])
	var type_attributes = {
		1: "HideRogueRoadMapNodeChance_Shop", 2: "HideRogueRoadMapNodeChance_Fight",
		3: "HideRogueRoadMapNodeChance_Rest", 5: "HideRogueRoadMapNodeChance_OnlyReward",
		11: "HideRogueRoadMapNodeChance_Event", 13: "HideRogueRoadMapNodeChance_OldDayRoom",
		14: "HideRogueRoadMapNodeChance_ChestTrialRoom",
	}
	for node_type in type_attributes:
		var attribute: String = type_attributes[node_type]
		campaign.set_road_map_attributes({"RandomHideRogueRoadMapNodeChance": 100.9, attribute: 200.9})
		check(campaign.node_hide_chance(node_type) == 300, "Global and type attributes truncate separately before adding")
		for other_type in type_attributes:
			if other_type != node_type: check(campaign.node_hide_chance(other_type) == 100, "Type hiding does not affect another room type")
	for node_type in [-1, 0, 4, 6, 7, 8, 9, 10, 12, 15, 100]:
		campaign.set_road_map_attributes({"RandomHideRogueRoadMapNodeChance": -1.9, "HideRogueRoadMapNodeChance_Fight": 1000})
		check(campaign.node_hide_chance(node_type) == -1, "Unmapped node type has only the global chance")
	campaign.restore(original)
	campaign.set_road_map_attributes({"RandomHideRogueRoadMapNodeChance": 1000})
	for index in campaign.state.layers.size():
		for id in campaign.state.layers[index].node_ids:
			var source: Dictionary = campaign._nodes[int(id)]
			check(campaign.is_node_hidden(index, int(id)) == (int(source.FirstOrFinal) not in [1, 2]), "Source special first/final nodes never hide")
	check(campaign.select_region(2).success, "World region selection remains valid")
	check(campaign.enter(int(campaign.choices()[0].node_id)).success, "Enter source entrance")
	_complete(campaign)
	var choices = campaign.choices().map(func(room): return int(room.node_id))
	var before_preview = campaign.snapshot()
	for row in campaign.route_map():
		if int(row.layer_index) == 1:
			check(row.is_hidden and row.display_name == "未知节点", "Hidden nodes display the source unknown localization")
			check(row.display_icon == "icon_stagerewardtypeicon_Unknown", "Hidden nodes use the exact source icon name")
			check(row.available == choices.has(int(row.node_id)), "Hidden state preserves reachable choices")
	check(campaign.snapshot() == before_preview, "Repeated previews never reroll or mutate route progress")
	var chosen = int(choices[0])
	check(campaign.enter(chosen).success, "A hidden reachable room can be entered")
	check(not campaign.is_node_hidden(1, chosen), "Entering reveals the node before completing it")
	check(not bool(campaign.state.layers[1].complete), "Reveal is independent of completion")
	for id in campaign.state.layers[1].node_ids:
		if int(id) != chosen: check(campaign.is_node_hidden(1, int(id)), "Unvisited alternatives remain hidden")
	var saved = JSON.parse_string(JSON.stringify(campaign.snapshot()))
	var clone = DungeonCampaign.new()
	clone.configure()
	clone.set_road_map_attributes({"RandomHideRogueRoadMapNodeChance": 1000})
	check(clone.restore(saved), "Hidden rolls restore through JSON")
	check(clone.route_map() == campaign.route_map(), "Restored map preserves hidden and revealed occurrences")
	var unchanged_rolls = clone.snapshot().layers[1].hide_rolls.duplicate()
	clone.set_road_map_attributes({"RandomHideRogueRoadMapNodeChance": 0})
	check(clone.route_map().all(func(room): return not room.is_hidden), "Removing the hiding attribute reveals unvisited rooms")
	clone.set_road_map_attributes({"RandomHideRogueRoadMapNodeChance": 1000})
	check(clone.snapshot().layers[1].hide_rolls == unchanged_rolls, "Attribute changes reuse the original roll")
	check(not clone.is_node_hidden(1, chosen), "Entered node stays revealed when the hiding attribute returns")
	var legacy = original.duplicate(true)
	for layer in legacy.layers: layer.erase("hide_rolls")
	check(clone.restore(legacy), "Legacy save receives missing rolls")
	check(clone.snapshot().layers == original.layers, "Legacy migration is deterministic and preserves the generated route")
	for invalid in [-1, 1000, 0.5, "0", true, null]:
		var damaged = original.duplicate(true)
		damaged.layers[1].hide_rolls[str(node_id)] = invalid
		check(not clone.restore(damaged), "Invalid saved roll is rejected: " + str(invalid))
	var damaged = original.duplicate(true)
	damaged.layers[1].hide_rolls["999999999"] = 1
	check(not clone.restore(damaged), "Saved rolls cannot introduce an unknown node")
	damaged = original.duplicate(true)
	damaged.layers[1].hide_rolls = []
	check(not clone.restore(damaged), "Saved rolls require a dictionary")
	var catalog = DungeonCatalog.new()
	catalog.load_all()
	var profile = DungeonProfile.new()
	var systems = DungeonSystems.new(catalog, profile)
	systems.begin_run(12345, 1, 100)
	profile.data.run.inventory["20411"] = 1
	clone.set_road_map_attributes(systems.attributes(1))
	check(clone.node_hide_chance(2) == 250, "Packaged map-scroll ability feeds its 250 global chance")
	profile.data.run.inventory["22131"] = 1
	clone.set_road_map_attributes(systems.attributes(1))
	check(clone.node_hide_chance(2) == 1250, "Packaged mushroom adds 1000 without clamping the sum")
	var report = {"passed": failures.is_empty(), "assertions": assertions, "failures": failures,
		"source_methods": {"roll_file": "0x2d85378", "refresh_file": "0x2e83440", "type_map_file": "0x12f1e08"}}
	FileAccess.open("res://reports/road-map-hidden-nodes-test.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("ROAD_MAP_HIDDEN_NODES ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func _complete(campaign: DungeonCampaign) -> void:
	if campaign.current_room().combat:
		while not campaign.room_ready(): campaign.clear_wave()
	else: campaign.resolve_action()
	campaign.complete_room()
	campaign.advance()
