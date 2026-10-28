extends SceneTree

class GameProbe extends "res://scripts/main.gd":
	var entered_regions: Array[int] = []
	var loaded_layers: Array[int] = []
	func _ready() -> void:
		set_process(false)
	func _load_room(_resume := false) -> void:
		loaded_layers.append(int(campaign.state.layer_index))
	func _save(_immediate := false) -> bool:
		return true
	func _select_region(id: int, _confirmed := false) -> void:
		entered_regions.append(id)

var checks := 0
var failures: Array[String] = []
var captures: Array[String] = []
var canvas: SubViewport

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _page(rows: Array, details: Dictionary) -> DungeonRoutePage:
	var page = DungeonRoutePage.new()
	page.theme = DungeonStyle.theme()
	canvas.add_child(page)
	page.size = Vector2(canvas.size)
	page.configure(rows, details)
	return page

func _settle() -> void:
	for frame in 8: await process_frame

func _run() -> void:
	create_timer(60).timeout.connect(func(): quit(2))
	canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var display = TextureRect.new()
	display.texture = canvas.get_texture()
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(display)
	var background = TextureRect.new()
	background.texture = DungeonStyle.texture("res://assets/ui/route/world_background_1.png")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	canvas.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var campaign = DungeonCampaign.new()
	check(campaign.configure() and campaign.generate(12345, 0).success, "Current APK campaign loads")
	var world = _page(campaign.region_map(), {"map_scope": "world", "first_layer": 1, "current_layer": 1})
	check(world.selected_id == 0 and not world.confirm.visible, "World map opens unselected")
	world._select(2, 1)
	check(world.selected_id == 2 and not world.confirm.disabled, "Open current region can be confirmed")
	world._select(1, 1)
	check(world.selected_id == 1 and world.confirm.disabled and world.nodes.filter(func(node): return node.chosen).size() == 1, "Locked region replaces previous selection and disables entry")
	check(not world.selection_detail.text.is_empty(), "Locked selection displays its detail on the map")
	var emitted: Array = []
	world.command.connect(func(kind, id, extra): emitted.append([kind, id, extra]))
	world._confirm()
	check(emitted.is_empty(), "Locked region cannot dispatch entry")
	world._select(5, 3)
	check(world.selected_id == 1, "Future region cannot replace selection")
	world._select(2, 1)
	world._confirm()
	world._confirm()
	check(emitted.size() == 1 and emitted[0][0] == "select_region" and emitted[0][1] == 2, "Confirmation dispatches once")
	world.queue_free()
	await process_frame
	check(campaign.select_region(2).success, "Select actual forest region")
	var duplicate := 1010801
	var anchor := 1010101
	var previous: Dictionary = campaign.state.layers[2]
	previous.node_ids = [anchor, duplicate]
	previous.selected_id = anchor
	previous.complete = true
	previous.completed_ids = [anchor]
	previous.connections = {str(anchor): [duplicate], str(duplicate): [duplicate]}
	previous.vertical_links = [[anchor, duplicate]]
	campaign.state.layers[3].node_ids = [duplicate]
	campaign.state.layer_index = 3
	var fixture: Dictionary = campaign.snapshot().duplicate(true)
	check(campaign.route_choice(duplicate).layer_index == 3, "Unqualified entry prefers forward occurrence")
	check(campaign.route_choice(duplicate, 2).vertical, "Explicit previous column resolves the vertical occurrence")
	check(not campaign.enter(duplicate, false, 2).success, "Vertical occurrence requires vertical authorization")
	check(campaign.enter(duplicate, true, 2).success and campaign.state.layer_index == 2, "Vertical entry cannot enter the forward duplicate")
	campaign.state = fixture.duplicate(true)
	check(campaign.enter(duplicate, true, 3).success and campaign.state.layer_index == 3, "Forward entry cannot enter the vertical duplicate")
	campaign.state = fixture.duplicate(true)
	var rows = campaign.route_map()
	for row in rows:
		row["config_id"] = int(row.layer_index) * 100000000 + int(row.node_id)
		row["available"] = row.available or row.vertical
	var rooms = _page(rows, {"first_layer": 0, "current_layer": 3})
	check(rooms.selected_id == 0 and not rooms.confirm.visible, "Room map opens unselected")
	emitted.clear()
	rooms.command.connect(func(kind, id, extra): emitted.append([kind, id, extra]))
	rooms._confirm()
	check(emitted.is_empty(), "Unselected room confirmation is ignored")
	rooms._select(duplicate, 2)
	rooms._select(duplicate, 3)
	check(rooms.nodes.filter(func(node): return node.chosen).size() == 1 and rooms.rows[rooms.selected_index].layer_index == 3, "Duplicate room selections highlight one occurrence")
	rooms._confirm()
	rooms._confirm()
	check(emitted.size() == 1 and emitted[0][2] == {"layer_index": 3}, "Room confirmation preserves column identity exactly once")
	rooms.queue_free()
	await process_frame
	for dimensions in [Vector2i(1600, 900), Vector2i(2460, 1080), Vector2i(844, 390)]:
		canvas.size = dimensions
		background.size = Vector2(dimensions)
		for scope in ["world", "rooms"]:
			var layout_rows: Array = []
			for column in 9:
				layout_rows.append({"node_id": column + 1, "config_id": column + 1, "layer_index": column,
					"lane": 0, "lane_count": 1, "available": column == 5, "is_anchor": column == 4,
					"map_mode": scope, "name": "Forest", "world_icon": "森林图标", "IconName": "icon_stagerewardtypeicon_Normal"})
			var page = _page(layout_rows, {"map_scope": scope, "first_layer": 0, "current_layer": 5})
			await _settle()
			for index in [4, 5]:
				var bounds: Rect2 = page.nodes[index].get_rect()
				var glow: float = page._graph_margin if scope == "rooms" and index == 5 else 0.0
				check(bounds.position.x - glow >= page.scroll.scroll_horizontal - 1 and bounds.end.x + glow <= page.scroll.scroll_horizontal + page.scroll.size.x + 1, "%s shows current and next nodes at %s" % [scope, dimensions])
			check(page.get_rect().encloses(page.header.get_rect()) and page.get_rect().encloses(page.footer.get_rect()), "Controls stay inside %s" % dimensions)
			check(page.scroll.get_rect().end.y <= page.footer.position.y, "Graph stays above controls at %s" % dimensions)
			page.scroll.scroll_horizontal += 110
			var old_column: float = (page.scroll.scroll_horizontal + page.scroll.size.x * 0.5 - page._graph_margin - page.node_size.x * 0.5) / page.column_width
			page.size.x -= 40
			await _settle()
			var new_column: float = (page.scroll.scroll_horizontal + page.scroll.size.x * 0.5 - page._graph_margin - page.node_size.x * 0.5) / page.column_width
			check(absf(old_column - new_column) < 0.01, "Resize preserves manually browsed column")
			page.size = Vector2(dimensions)
			await _settle()
			page._scroll_to_current()
			await _capture(page, scope, dimensions)
			page.context.current_layer = 8
			for row in page.rows: row.is_anchor = false
			page._scroll_to_current()
			var last: Rect2 = page.nodes.back().get_rect()
			check(last.end.x - page.scroll.scroll_horizontal <= page.scroll.size.x + 1, "Last column remains visible after clamping")
			page.queue_free()
			await process_frame
	await _check_completed_room_positions()
	await _check_menu_room_position()
	await _check_world_positions()
	await _check_game(campaign, fixture, duplicate)
	canvas.queue_free()
	display.queue_free()
	await process_frame
	var report = {"checks": checks, "passed": failures.is_empty(), "failures": failures, "captures": captures}
	FileAccess.open("res://reports/map-selection-position-test.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("MAP_SELECTION_POSITION ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func _check_completed_room_positions() -> void:
	var campaign = DungeonCampaign.new()
	check(campaign.configure() and campaign.generate(12345, 0).success and campaign.select_region(2).success, "Progression fixture opens actual APK forest route")
	for cleared in 6:
		var choices = campaign.choices()
		check(not choices.is_empty(), "Progression has a forward destination after %d rooms" % cleared)
		if choices.is_empty(): return
		check(campaign.enter(int(choices[0].node_id)).success, "Progression enters room %d" % cleared)
		if campaign.current_room().combat:
			while not campaign.room_ready(): campaign.clear_wave()
		elif not campaign.trial_status().is_empty(): campaign.decline_trial()
		else: campaign.resolve_action()
		check(campaign.complete_room().success and campaign.advance().success, "Completed room %d returns to route selection" % cleared)
		var snapshot = campaign.snapshot().duplicate(true)
		for dimensions in [Vector2i(1600, 900), Vector2i(1280, 720), Vector2i(2460, 1080), Vector2i(844, 390), Vector2i(1000, 900), Vector2i(640, 900)]:
			canvas.size = dimensions
			var rows = campaign.route_map()
			for row in rows: row["config_id"] = int(row.layer_index) * 100000000 + int(row.node_id)
			var page = _page(rows, {"map_scope": "rooms", "first_layer": 0, "current_layer": int(campaign.state.layer_index), "portrait": "sprite_cardicon_square_jiannan"})
			await _settle()
			var reachable := 0
			var anchors := 0
			for index in page.nodes.size():
				if page.rows[index].is_anchor:
					anchors += 1
					var anchor_bounds = page.nodes[index].get_rect()
					check(anchor_bounds.position.x >= page.scroll.scroll_horizontal - 1 and anchor_bounds.end.x <= page.scroll.scroll_horizontal + page.scroll.size.x + 1, "Current room remains visible after room %d at %s" % [cleared, dimensions])
				if not page.rows[index].available: continue
				reachable += 1
				var bounds = page.nodes[index].get_rect()
				var glow = bounds.size.x * (DungeonRouteNode.SELECTED_FRAME_SIZE.x * DungeonRouteNode.SELECTION_PEAK_SCALE - 1.0) * 0.5
				check(bounds.position.x - glow >= page.scroll.scroll_horizontal - 1 and bounds.end.x + glow <= page.scroll.scroll_horizontal + page.scroll.size.x + 1, "Next selectable room fits with its highlight after room %d at %s" % [cleared, dimensions])
			check(anchors == 1 and reachable > 0 and page.selected_id == 0 and not page.confirm.visible, "Current and next columns are visible without preselecting a room")
			check(campaign.snapshot() == snapshot, "Opening completed-room selection preserves progress")
			if cleared == 3 and dimensions in [Vector2i(1600, 900), Vector2i(844, 390), Vector2i(1000, 900), Vector2i(640, 900)] and DisplayServer.get_name() != "headless":
				await create_timer(0.8).timeout
				await RenderingServer.frame_post_draw
				var path = "res://reports/map-next-room-%dx%d.png" % [dimensions.x, dimensions.y]
				canvas.get_texture().get_image().save_png(path)
				captures.append(path)
			page.queue_free()
			await process_frame

func _check_menu_room_position() -> void:
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390)]:
		canvas.size = dimensions
		var rows: Array = []
		for column in 12:
			rows.append({"node_id": column + 1, "config_id": column + 1, "layer_index": column,
				"lane": 0, "lane_count": 1, "available": column == 7, "is_anchor": column == 6,
				"name": "Room", "IconName": "icon_stagerewardtypeicon_Normal"})
		var menu = DungeonMenuPage.new()
		menu.theme = DungeonStyle.theme()
		canvas.add_child(menu)
		menu.size = Vector2(dimensions)
		menu.display("选择路线", rows, "route", {"map_scope": "rooms", "first_layer": 0, "current_layer": 7})
		await _settle()
		var page = menu.route_view
		var bounds = page.nodes[6].selection_bounds()
		bounds.position += page.nodes[6].position
		var next = page.nodes[7].selection_bounds()
		next.position += page.nodes[7].position
		next = next.grow_individual(page._graph_margin, 0, page._graph_margin, 0)
		bounds = bounds.merge(next)
		check(bounds.position.x >= page.scroll.scroll_horizontal - 1 and bounds.end.x <= page.scroll.scroll_horizontal + page.scroll.size.x + 1, "Menu shows current and next rooms at %s" % dimensions)
		check(absf(bounds.get_center().x - (page.scroll.scroll_horizontal + page.scroll.size.x * 0.5)) <= 1, "Menu centers current and next rooms at %s" % dimensions)
		menu.queue_free()
		await process_frame

func _check_world_positions() -> void:
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390), Vector2i(640, 900)]:
		canvas.size = dimensions
		for pending in [false, true]:
			var rows: Array = []
			for column in 8:
				rows.append({"node_id": column + 1, "config_id": column + 1, "layer_index": column + 1,
					"lane": 0, "lane_count": 1, "available": pending and column == 4,
					"selectable": pending and column == 4, "is_anchor": column == 3,
					"current": not pending and column == 3, "map_mode": "world", "name": "Forest", "world_icon": "森林图标"})
			var page = _page(rows, {"map_scope": "world", "first_layer": 1, "current_layer": 5 if pending else 4, "preview": not pending})
			await _settle()
			for index in [3, 4]:
				var bounds: Rect2 = page.nodes[index].get_rect()
				check(bounds.position.x >= page.scroll.scroll_horizontal - 1 and bounds.end.x <= page.scroll.scroll_horizontal + page.scroll.size.x + 1, "World current and next regions visible at %s pending=%s" % [dimensions, pending])
			page.queue_free()
			await process_frame

func _check_game(campaign: DungeonCampaign, fixture: Dictionary, duplicate: int) -> void:
	var game = GameProbe.new()
	root.add_child(game)
	game.catalog = DungeonCatalog.new()
	check(game.catalog.load_all(), "Game entry catalog loads")
	game.profile = DungeonProfile.new()
	game.systems = DungeonSystems.new(game.catalog, game.profile)
	game.systems.begin_run(12345, 1, 100, 0)
	game.campaign = campaign
	game.hud = DungeonHud.new()
	canvas.add_child(game.hud)
	game.world = DungeonWorld.new()
	game.menus = DungeonMenus.new(game)
	game.systems.effects.acquire(15102)
	check(game.systems.search_point_count() == 2, "Entry fixture has two shift charges")
	campaign.state = fixture.duplicate(true)
	game._enter_node(duplicate, 3)
	check(campaign.state.layer_index == 3 and game.systems.search_point_count() == 2, "Forward duplicate costs no shift charge")
	campaign.state = fixture.duplicate(true)
	game._enter_node(duplicate, 2)
	check(campaign.state.layer_index == 2 and game.systems.search_point_count() == 1, "Vertical duplicate enters previous column and costs one charge")
	game._enter_node(duplicate, 2)
	check(game.systems.search_point_count() == 1 and game.loaded_layers == [3, 2], "Repeated entry cannot load or charge twice")
	campaign.generate(12345, 0)
	game.profile.data.auto_route = true
	game._world_route(false)
	check(game.entered_regions.is_empty() and game.hud.page.route_view.is_world_map(), "Automatic option keeps initial world selection")
	check(campaign.state.region_selection, "Opening initial world map does not mutate the route")
	campaign.state.layer_index = 7
	campaign.state.module_index = 1
	campaign.state.layers[6].complete = true
	campaign.state.layers[6].selected_id = int(campaign.state.layers[6].node_ids[0])
	game._world_route(false)
	check(game.entered_regions.size() == 1, "Later single-choice module still enters automatically")
	game.systems.decorations = null
	for node in [game.resource_audio, game.ads, game.world.ground_loot, game.world.spirit_followers, game.world.player_transfer, game.world.player_revival]: node.free()
	game.world.free()
	game.hud.queue_free()
	game.queue_free()
	await process_frame

func _capture(page: DungeonRoutePage, scope: String, dimensions: Vector2i) -> void:
	if DisplayServer.get_name() == "headless": return
	page._select(6, 5)
	await create_timer(0.9).timeout
	await RenderingServer.frame_post_draw
	var path = "res://reports/map-position-%s-%dx%d.png" % [scope, dimensions.x, dimensions.y]
	canvas.get_texture().get_image().save_png(path)
	captures.append(path)
