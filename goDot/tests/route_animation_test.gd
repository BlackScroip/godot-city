extends SceneTree

var failures: Array[String] = []
var checks := 0
var canvas: SubViewport
var background: TextureRect
var rows: Array = []
var captures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _page(dimensions: Vector2i) -> DungeonRoutePage:
	canvas.size = dimensions
	background.size = Vector2(dimensions)
	var page = DungeonRoutePage.new()
	page.theme = DungeonStyle.theme()
	canvas.add_child(page)
	page.size = Vector2(dimensions)
	page.configure(rows, {"current_layer": 1, "portrait": "sprite_cardicon_square_jiannan", "search": 2})
	return page

func _run() -> void:
	Engine.max_fps = 60
	create_timer(30).timeout.connect(func(): quit(2))
	canvas = SubViewport.new()
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var display = TextureRect.new()
	display.texture = canvas.get_texture()
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(display)
	background = TextureRect.new()
	background.texture = DungeonStyle.texture("res://assets/ui/route/world_background_1.png")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	canvas.add_child(background)
	var campaign = DungeonCampaign.new()
	check(campaign.configure() and campaign.generate(12345, 0).success, "Actual campaign generates")
	check(campaign.select_region(2).success, "Select the forest region")
	check(campaign.enter(int(campaign.choices()[0].node_id)).success, "Enter the entrance")
	campaign.resolve_action()
	check(campaign.complete_room().success and campaign.advance().success, "Open the three-way branch")
	rows = campaign.route_map()
	var catalog = DungeonCatalog.new()
	check(catalog.load_all(), "Actual reward catalog loads")
	var systems = DungeonSystems.new(catalog, DungeonProfile.new())
	check(systems.begin_run(12345, 1, 100, 0).success, "Actual reward fixture starts a run")
	systems.ensure_map_node_increments(campaign)
	for row in rows:
		row["config_id"] = int(row.layer_index) * 100000000 + int(row.node_id)
		row["NodeIncrementData"] = systems.room_node_increments("12345:%d:%d" % [int(row.layer_index), int(row.node_id)], row)
	check(rows.any(func(row): return not row.NodeIncrementData.is_empty()), "Preview includes actual rolled node rewards")
	for name in ["frame", "gold", "magic", "mineral", "partner", "spirit"]:
		var texture = DungeonStyle.texture("res://assets/ui/route/badges/%s.png" % name)
		check(texture != null and texture.get_width() > 0 and texture.get_height() > 0, "Recovered badge artwork loads: " + name)
	await process_frame
	await process_frame
	for dimensions in [Vector2i(1600, 900), Vector2i(2460, 1080), Vector2i(844, 390)]:
		var page = _page(dimensions)
		check(page.nodes.all(func(node): return is_zero_approx(node.modulate.a)), "Opening begins before the first visible frame")
		while not page._opening_started: await process_frame
		await create_timer(0.12).timeout
		check(page.nodes.front().modulate.a > page.nodes.back().modulate.a, "Opening reveals earlier columns first at %s (first %.3f, last %.3f)" % [dimensions, page.nodes.front().modulate.a, page.nodes.back().modulate.a])
		await create_timer(0.70).timeout
		check(page.nodes.all(func(node): return is_equal_approx(node.modulate.a, 1.0)), "Opening reveals all nodes within one second")
		check(is_equal_approx(page._opening_alpha, 1.0), "Connections finish their opening fade")
		var choices = page.nodes.filter(func(node): return node.available)
		check(choices.size() == 3, "Animation keeps all three reachable choices")
		choices[0].pressed.emit()
		var selected: DungeonRouteNode = choices[0]
		var layout = selected.get_rect()
		var narrowest := INF
		var widest := 0.0
		for sample in 32:
			await create_timer(0.05).timeout
			var frame = selected._selected_frame_rect()
			narrowest = minf(narrowest, frame.size.x)
			widest = maxf(widest, frame.size.x)
			check(frame.encloses(Rect2(Vector2.ZERO, selected.size)), "Selection always surrounds the inner card")
			check(frame.get_center().is_equal_approx(selected.size * 0.5), "Scaling remains centered")
			check(selected.get_rect() == layout and selected.scale == Vector2.ONE, "Animation preserves layout and input geometry")
		check(widest - narrowest > 0.5, "Selected frame visibly breathes over time")
		for node in page.nodes:
			var inner: Rect2 = node._room_rect()
			check(inner.size.x < node.size.x and inner.size.y < node.size.y, "Inner card leaves additional space around its artwork")
			var badges: Array[Rect2] = node._badge_rects()
			for index in badges.size():
				check(node._selected_frame_rect().encloses(badges[index]), "Reward badge stays inside the reserved outer frame")
				for other in range(index + 1, badges.size()):
					check(not badges[index].intersects(badges[other]), "Reward badges remain individually readable")
			var peak_size = node.size * DungeonRouteNode.SELECTED_FRAME_SIZE * DungeonRouteNode.SELECTION_PEAK_SCALE
			var peak = Rect2(node.position + (node.size - peak_size) * 0.5, peak_size)
			check(Rect2(Vector2(-0.1, -0.1), page.graph.size + Vector2(0.2, 0.2)).encloses(peak), "Even the peak frame fits inside scroll content")
		await _capture("res://reports/route-animation-%dx%d.png" % [dimensions.x, dimensions.y])
		page._select(int(choices[1].room.node_id))
		await create_timer(0.03).timeout
		page._select(int(choices[2].room.node_id))
		await create_timer(0.03).timeout
		page._select(int(choices[0].room.node_id))
		await create_timer(0.40).timeout
		check(choices.filter(func(node): return node.chosen).size() == 1, "Rapid switching leaves exactly one selected node")
		check(is_equal_approx(choices[1]._selection_scale, 1.0) and is_equal_approx(choices[2]._selection_scale, 1.0), "Deselected nodes stop scaling")
		page.size.x -= 10
		await process_frame
		await process_frame
		check(page.nodes.all(func(node): return is_equal_approx(node.modulate.a, 1.0) and is_equal_approx(node._reveal_scale, 1.0)), "Resizing never replays the opening")
		var emitted: Array = []
		page.command.connect(func(kind, id, extra): emitted.append([kind, id, extra]))
		page.confirm.pressed.emit()
		check(emitted.size() == 1 and emitted[0][0] == "enter_node" and emitted[0][1] == page.selected_id, "Confirmation works while the selection is animated")
		page.queue_free()
		await process_frame
	if "--capture-motion" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await _capture_motion()
	canvas.queue_free()
	display.queue_free()
	await process_frame
	var report = {"checks": checks, "passed": failures.is_empty(), "failures": failures, "captures": captures}
	FileAccess.open("res://reports/route-animation-test.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("ROUTE_ANIMATION ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func _capture(path: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	canvas.get_texture().get_image().save_png(path)
	captures.append(path)

func _capture_motion() -> void:
	DirAccess.make_dir_recursive_absolute("res://reports/route-animation-frames")
	var page = _page(Vector2i(1600, 900))
	var choices = page.nodes.filter(func(node): return node.available)
	choices[0].pressed.emit()
	for frame in 180:
		if frame == 70: page._select(int(choices[1].room.node_id))
		if frame == 110: page._select(int(choices[2].room.node_id))
		await process_frame
		if frame % 2 == 0:
			await RenderingServer.frame_post_draw
			canvas.get_texture().get_image().save_png("res://reports/route-animation-frames/%03d.png" % (frame / 2))
	page.queue_free()
	await process_frame
