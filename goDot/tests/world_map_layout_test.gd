extends SceneTree

var failures: Array[String] = []
var checks := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var campaign = DungeonCampaign.new()
	check(campaign.configure(), "New world table loads")
	for difficulty in [0, 10]:
		campaign.generate(1206, difficulty)
		var page = DungeonRoutePage.new()
		page.theme = DungeonStyle.theme()
		canvas.add_child(page)
		page.configure(campaign.region_map(), {"map_scope": "world", "first_layer": 1, "current_layer": 1, "portrait": "sprite_cardicon_square_jiannan", "character": "迷宫入口"})
		check(page.selected_id == 0 and not page.confirm.visible, "World initially waits for deliberate region selection")
		page._select(5)
		check(page.selected_id == 0, "Closed unknown slot cannot be selected")
		page._select(1)
		check(page.selected_id == (1 if difficulty == 10 else 0), "High risk requires current difficulty10")
		for dimensions in [Vector2i(1600, 900), Vector2i(2460, 1080), Vector2i(844, 390)]:
			canvas.size = dimensions
			page.size = Vector2(dimensions)
			for frame in 10: await process_frame
			for control in [page.header, page.footer, page.scroll]: check(page.get_global_rect().encloses(control.get_global_rect()), "World controls fit %s" % dimensions)
			check(page.nodes.size() == 9 and page.edges.size() > 9, "Actual nine world slots and connecting paths")
			for node in page.nodes:
				check(node.size.y >= 80, "World icon remains readable %s" % dimensions)
				check(Rect2(Vector2.ZERO, page.graph.size).encloses(node.get_rect()), "World node stays inside scroll content %s" % dimensions)
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				canvas.get_texture().get_image().save_png("/private/tmp/world-map-d%d-%dx%d.png" % [difficulty, dimensions.x, dimensions.y])
		page._select(2)
		check(page.selected_id == 2 and page.confirm.visible and not page.confirm.disabled, "Normal reachable region enables confirmation")
		page.queue_free()
		await process_frame
	canvas.queue_free()
	await process_frame
	print("WORLD_MAP_LAYOUT ", JSON.stringify({"checks": checks, "passed": failures.is_empty(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)
