extends SceneTree

var checks := 0
var failures: Array[String] = []
var game: Node
var canvas: SubViewport

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _wait_loading() -> void:
	game.world.set_physics_process(false)
	game.world.set_process(true)
	var deadline := Time.get_ticks_msec() + 60000
	while game._transitioning and Time.get_ticks_msec() < deadline: await process_frame
	check(not game._transitioning, "Room finishes its loading and transfer sequence")
	game.set_process(false)
	game.world.set_process(false)
	game.world.set_physics_process(false)
	game.world.presentation.audio_enabled = false

func _run() -> void:
	create_timer(90).timeout.connect(func(): quit(2))
	canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	game = load("res://scenes/main.tscn").instantiate()
	game.save_store = DungeonSaveStore.new("/private/tmp/city-route-visibility-%d.json" % Time.get_ticks_usec())
	canvas.add_child(game)
	await _wait_loading()
	check(game.systems.begin_run(12345, 1, 100, 0).success, "Visibility fixture starts a real run")
	game.profile.data.run.inventory["22131"] = 1
	check(game.systems.attributes().get("RandomHideRogueRoadMapNodeChance", 0) == 1000, "Source strange mushroom hides unvisited nodes")
	game.campaign.generate(12345, 0)
	check(game.campaign.select_region(2).success, "Visibility fixture selects the reachable forest region")
	check(game.campaign.enter(int(game.campaign.choices()[0].node_id)).success, "Enter the unhidden first room")
	game.campaign.resolve_action()
	check(game.campaign.complete_room().success and game.campaign.advance().success, "Complete entrance before selecting a hidden branch")
	game._route()
	for frame in 6: await process_frame
	var route: DungeonRoutePage = game.hud.page.route_view
	var selected := 0
	for node in route.nodes:
		var row: Dictionary = node.room
		var key := "%d:%d:%d" % [12345, int(row.layer_index), int(row.node_id)]
		check(row.get("NodeIncrementData", {}) == game.systems.room_node_increments(key, row), "Map row displays the saved actual node increments")
		if row.get("is_hidden", false):
			check(node.tooltip_text.begins_with("未知节点") and not node.tooltip_text.contains(str(row.get("Flow", ""))), "Hidden tooltip preserves the source unknown name")
			check(node._badge_types().is_empty(), "Hidden node conceals its actual increment badges")
			var artwork: Texture2D = node._artwork()
			check(artwork != null and artwork.resource_path == "res://assets/ui/route/room_unknown.png", "Hidden node uses recovered source unknown artwork")
			if node.available and selected == 0: selected = int(row.node_id)
	check(selected > 0, "A hidden reachable branch remains selectable")
	if selected > 0:
		route._select(selected)
		check(not route.confirm.disabled and route.selected_id == selected, "Selecting an unknown branch enables confirmation")
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390)]:
		canvas.size = dimensions
		for frame in 8: await process_frame
		check(route.scroll.get_rect().end.y <= route.footer.position.y, "Hidden map graph and controls do not overlap")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			canvas.get_texture().get_image().save_png("res://reports/route-hidden-%dx%d.png" % [dimensions.x, dimensions.y])
	var sample := DungeonRouteNode.new()
	sample.room = {"NodeIncrementData": {"70001": 0, "70002": 0, "10000": 0, "13006": 0}}
	check(sample._badge_types().size() == 4, "All four selected increments receive badges")
	sample.room.NodeIncrementData["13008"] = 0
	check(sample._badge_types() == ["gold", "magic", "mineral", "partner", "spirit"], "All five source reward icons have a stable display order")
	sample.room = {"NodeIncrementData": {70001: 0, 13008: 0}}
	check(sample._badge_types() == ["gold", "spirit"], "Unsaved integer reward keys receive the same badges")
	sample.room = {"IncrementOptions": "GoldLode,MagicpointLode,CollectingMaterials,SpritesAltar"}
	check(sample._badge_types().is_empty(), "Candidate increment flags are never presented as selected rewards")
	sample.free()
	if selected > 0:
		game._enter_node(selected)
		await _wait_loading()
		check(game.campaign.state.phase == "room" and int(game.campaign.state.current_node_id) == selected, "Actual entry accepts the hidden reachable node")
		check(not game.campaign.is_node_hidden(int(game.campaign.state.layer_index), selected), "Entering reveals the chosen node immediately")
		var room: Dictionary = game.campaign.current_room()
		var appearance: Dictionary = game.systems.room_environment_appearance(game._room_key, room, game.world.interactions._items.values())
		for id in appearance:
			if not appearance[id]: check(not game.world.interactions._items[id].state.enabled, "Actual room applies the saved failed appearance result")
		var increments: Dictionary = game.systems.room_node_increments(game._room_key, room)
		game._build_save_snapshot()
		game._load_room(true)
		await _wait_loading()
		check(game.systems.room_environment_appearance(game._room_key, room, game.world.interactions._items.values()) == appearance, "Room reload retains per-object appearance")
		check(game.systems.room_node_increments(game._room_key, room) == increments, "Room reload retains the map reward increments")
	game.systems.decorations = null
	game.queue_free()
	await process_frame
	canvas.queue_free()
	await process_frame
	var report := {"checks": checks, "passed": failures.is_empty(), "failures": failures}
	FileAccess.open("res://reports/route-visibility-flow.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("ROUTE_VISIBILITY_FLOW ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
