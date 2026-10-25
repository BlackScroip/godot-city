extends SceneTree

var assertions := 0
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message)

func _initialize() -> void:
	var campaign = DungeonCampaign.new()
	campaign.configure()
	for difficulty in range(11):
		for seed_value in [1, 17, 12345]:
			campaign.generate(seed_value, difficulty)
			for index in campaign.state.layers.size() - 1:
				var layer: Dictionary = campaign.state.layers[index]
				var next: Array = campaign.state.layers[index + 1].node_ids
				var incoming: Array = []
				for id in layer.node_ids:
					var targets: Array = layer.connections[str(int(id))]
					check(not targets.is_empty(), "Every source has an outgoing route")
					for target in targets:
						check(next.has(int(target)), "Arrows only connect to the next column")
						incoming.append(int(target))
				for id in next: check(incoming.has(int(id)), "Every room has an incoming route")
				for pair in layer.vertical_links:
					check(layer.node_ids.has(int(pair[0])) and layer.node_ids.has(int(pair[1])), "Vertical arrows stay within the column")
	campaign.generate(12345, 0)
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
	check(clone.vertical_choices().size() == 1 and int(clone.vertical_choices()[0].node_id) == target, "Vertical destination survives restore")
	for layer in snapshot.layers:
		layer.erase("connections")
		layer.erase("vertical_links")
		layer.erase("completed_ids")
	check(clone.restore(snapshot), "Older saves receive designed route connections")
	check(campaign.enter(target, true).success and int(campaign.state.layer_index) == 1, "Vertical movement enters same-depth room")
	_complete(campaign)
	check(int(campaign.state.layer_index) == 2, "Vertical room rejoins next-column progression")
	check(campaign.state.layers[1].completed_ids.size() == 2, "Both completed rooms remain recorded")
	check(campaign.vertical_choices().is_empty(), "Completed vertical room cannot be farmed again")
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

func _complete(campaign: DungeonCampaign) -> void:
	if campaign.current_room().combat:
		while not campaign.room_ready(): campaign.clear_wave()
	else: campaign.resolve_action()
	campaign.complete_room()
	campaign.advance()
