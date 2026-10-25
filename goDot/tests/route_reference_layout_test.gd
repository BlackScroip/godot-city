extends SceneTree

var failures: Array[String] = []
var assertions := 0

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var display = TextureRect.new()
	display.texture = canvas.get_texture()
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(display)
	var campaign = DungeonCampaign.new()
	campaign.configure()
	campaign.generate(12345, 0)
	check(campaign.select_region(2).success, "World map confirms the region before displaying its room layout")
	var rooms = campaign.route_map()
	for row in rooms:
		row["config_id"] = int(row.layer_index) * 100000000 + int(row.node_id)
	var page = DungeonRoutePage.new()
	canvas.add_child(page)
	page.configure(rooms, {"portrait": "sprite_cardicon_square_jiannan", "character": "迷宫入口", "magic": 397, "search": 2, "search_max": 4})
	var emitted: Array = []
	page.command.connect(func(kind, id, extra): emitted.append([kind, id, extra]))
	for dimensions in [Vector2i(1600, 900), Vector2i(2460, 1080), Vector2i(844, 390)]:
		canvas.size = dimensions
		page.size = Vector2(dimensions)
		for step in 8: await process_frame
		check(Rect2(Vector2.ZERO, page.size).encloses(page.header.get_rect()), "Header fits " + str(dimensions))
		check(Rect2(Vector2.ZERO, page.size).encloses(page.footer.get_rect()), "Footer fits " + str(dimensions))
		check(page.scroll.get_rect().end.y <= page.footer.position.y, "Graph stays above controls " + str(dimensions))
		for node in page.nodes:
			check(Rect2(Vector2.ZERO, page.graph.size).encloses(node.get_rect()), "Diamond and label fit graph")
			check(node.disabled != node.available, "Only reachable rooms can be selected")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			canvas.get_texture().get_image().save_png("res://reports/route-reference-%dx%d.png" % [dimensions.x, dimensions.y])
	var selected = page.selected_id
	for row in rooms:
		if not row.available:
			page._select(int(row.node_id), int(row.layer_index))
			check(page.selected_id == selected, "Locked destination cannot replace selection")
			break
	page._confirm()
	check(emitted.size() == 1 and emitted[0][0] == "enter_node" and emitted[0][1] == selected, "Confirm dispatches the actual selected node")
	canvas.queue_free()
	display.queue_free()
	await process_frame
	print("ROUTE_REFERENCE_LAYOUT ", JSON.stringify({"passed": failures.is_empty(), "assertions": assertions, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
