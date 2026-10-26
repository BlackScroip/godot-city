extends SceneTree

var failures: Array[String] = []
var checks := 0
var captures: Array[String] = []
var canvas: SubViewport

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	canvas = SubViewport.new()
	canvas.size = Vector2i(2460, 1080)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var background = TextureRect.new()
	background.texture = DungeonStyle.texture("res://assets/ui/route/world_background_1.png")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.size = Vector2(canvas.size)
	canvas.add_child(background)
	var campaign = DungeonCampaign.new()
	check(campaign.configure() and campaign.generate(12345, 10).success, "APK campaign fixtures generate")
	var world = _page(campaign.region_map(), true)
	for dimensions in [Vector2i(2460, 1080), Vector2i(1600, 900), Vector2i(844, 390)]:
		await _resize(world, dimensions, background)
		check(world.edges.size() == 16, "World has exactly the adjacent-module connections")
		for kind in ["dotted", "cross", "solid"]:
			var expected = {"dotted": 4, "cross": 6, "solid": 6}[kind]
			check(world.edges.filter(func(edge): return edge.kind == kind).size() == expected, "World uses the APK " + kind + " connection family")
		_validate_paths(world)
		await _capture("world", dimensions)
	world.queue_free()
	await process_frame
	check(campaign.select_region(2).success, "Forest is selected")
	var entrance = int(campaign.choices()[0].node_id)
	check(campaign.enter(entrance).success, "Enter the actual entrance node")
	campaign.resolve_action()
	check(campaign.complete_room().success and campaign.advance().success, "Entrance opens the first three-way branch")
	var rows = campaign.route_map()
	for row in rows: row["config_id"] = int(row.layer_index) * 100000000 + int(row.node_id)
	var rooms = _page(rows, false)
	check(not rooms.origin.visible, "Small map uses its real entrance without an extra origin")
	for dimensions in [Vector2i(2460, 1080), Vector2i(1600, 900), Vector2i(844, 390)]:
		await _resize(rooms, dimensions, background)
		check(rooms.edges.all(func(edge): return edge.kind in ["solid", "vertical"]), "Every room diagonal is a continuous arrow")
		check(rooms.edges.filter(func(edge): return not edge.vertical and rooms._path_state(edge) == "available").size() == 3, "Only the current entrance's three reachable branches glow")
		_validate_paths(rooms)
		await _capture("rooms", dimensions)
	var option = rooms.nodes.filter(func(node): return node.available)[0]
	option.pressed.emit()
	var chosen = rooms.selected_id
	rooms._confirm()
	check(chosen > 0, "Corrected path presentation keeps room selection functional")
	rooms.queue_free()
	await process_frame
	# Visited alternatives must not create a false highlighted forward path.
	var source = DungeonRouteNode.new()
	var target = DungeonRouteNode.new()
	source.room = {"config_id": 101, "is_anchor": false}
	target.room = {"passed_parents": [102]}
	source.visited = true
	target.visited = true
	var sample = DungeonRoutePage.new()
	check(sample._path_state({"from": source, "to": target}) == "unavailable", "Two visited nodes alone do not imply a passed edge")
	target.room.passed_parents = [101]
	check(sample._path_state({"from": source, "to": target}) == "passed", "Only actual consecutive history marks a passed edge")
	source.free()
	target.free()
	sample.free()
	canvas.queue_free()
	await process_frame
	var report = {"checks": checks, "passed": failures.is_empty(), "failures": failures, "captures": captures}
	FileAccess.open("res://reports/route-connections-test.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("ROUTE_CONNECTIONS ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func _page(rows: Array, world: bool) -> DungeonRoutePage:
	var page = DungeonRoutePage.new()
	page.theme = DungeonStyle.theme()
	canvas.add_child(page)
	page.size = Vector2(canvas.size)
	page.configure(rows, {"map_scope": "world" if world else "rooms", "first_layer": 1 if world else 0,
		"current_layer": 1, "portrait": "sprite_cardicon_square_jiannan", "character": "迷宫入口", "search": 2})
	return page

func _resize(page: DungeonRoutePage, dimensions: Vector2i, background: TextureRect) -> void:
	canvas.size = dimensions
	background.size = Vector2(dimensions)
	page.size = Vector2(dimensions)
	for frame in 8: await process_frame
	check(page.scroll.get_rect().end.y <= page.footer.position.y, "Map connections stay above the footer")
	check(page.get_rect().encloses(page.header.get_rect()) and page.get_rect().encloses(page.footer.get_rect()), "Controls fit the viewport")

func _validate_paths(page: DungeonRoutePage) -> void:
	for edge in page.edges:
		if edge.vertical:
			var areas = page._vertical_path_rects(edge)
			check(areas.size() == 2, "Vertical links retain both directions on every viewport")
			for area in areas:
				check(area.size.y >= 8, "Vertical arrows remain visible on narrow viewports")
				check(not area.intersects(edge.from.get_rect()) and not area.intersects(edge.to.get_rect()), "Vertical arrows stay between room cards")
			continue
		var path = page._path_geometry(edge)
		check(path.area.size.x > 0 and path.area.size.y > 0, "Every path has a drawable area")
		check(path.end.x > path.start.x, "Forward paths always point toward the next column")
		check(DungeonStyle.texture(page.PATH_ART + str(path.sprite) + ".png") != null, "Every path state uses a recovered APK texture")
		if edge.kind in ["dotted", "cross"]:
			check(is_equal_approx(path.draw_scale.x, path.draw_scale.y), "Dotted and curved paths preserve circular dots and dash thickness")
		else:
			check(path.draw_size.y >= 13, "Solid arrowheads retain their height at shallow angles")
		if not page.is_world_map():
			check(not edge.from.get_rect().has_point(path.start) and not edge.to.get_rect().has_point(path.end), "Paths stop outside the room cards")
		if page.is_world_map() and edge.kind == "cross":
			check(signf(path.end.y - path.start.y) == signf(edge.to.position.y - edge.from.position.y), "Cross paths keep their direction on narrow viewports")

func _capture(scope: String, dimensions: Vector2i) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var path = "res://reports/route-connections-%s-%dx%d.png" % [scope, dimensions.x, dimensions.y]
	canvas.get_texture().get_image().save_png(path)
	captures.append(path)
