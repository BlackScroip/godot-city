extends SceneTree

var checks := 0
var failures: Array[String] = []
var game: Node
var canvas: SubViewport

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("REGION NOTICE FAILURE: ", message)

func wait_loading() -> void:
	game.world.set_physics_process(false)
	game.world.set_process(true)
	var deadline := Time.get_ticks_msec() + 60000
	while game._transitioning and Time.get_ticks_msec() < deadline:
		game.world._background = false
		await process_frame
	check(not game._transitioning, "Room loading and transfer complete")
	game.set_process(false)
	game.world.set_process(false)
	game.world.set_physics_process(false)
	game.hud.region_notice.set_process(false)

func capture(dimensions: Vector2i, phase: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var image := canvas.get_texture().get_image()
	check(not image.is_empty(), "Rendered image has pixels: " + phase)
	image.save_png("res://reports/region-notice-%dx%d-%s.png" % [dimensions.x, dimensions.y, phase])
	if phase == "title":
		var gold_pixels := 0
		for y in range(roundi(dimensions.y * 0.06), roundi(dimensions.y * 0.30), 2):
			for x in range(roundi(dimensions.x * 0.3), roundi(dimensions.x * 0.7), 2):
				var color := image.get_pixel(x, y)
				if color.r > 0.7 and color.g > 0.5 and color.b < 0.7: gold_pixels += 1
		check(gold_pixels > 100, "Recovered gold banner renders at " + str(dimensions))

func _run() -> void:
	create_timer(120).timeout.connect(func(): quit(2))
	canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var display := TextureRect.new()
	display.texture = canvas.get_texture()
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(display)
	game = load("res://scripts/main.gd").new()
	game.save_store = DungeonSaveStore.new("/private/tmp/city-region-notice-%d.json" % Time.get_ticks_usec())
	canvas.add_child(game)
	game.audio.stop()
	game.world.presentation.audio_enabled = false
	game.set_process(false)
	game.world.set_physics_process(false)
	await process_frame
	var notice: Control = game.hud.region_notice
	check(not notice.visible and notice.entry_key.is_empty(), "Camp has no entry banner")
	game._primary()
	check(not notice.visible, "World selection does not play an entry banner")
	game._select_region(2)
	await wait_loading()
	check(not game.room_loading.visible and not game.hud.modal_open, "Entry banner starts after loading closes")
	check(notice.visible and notice.entry_key == game._room_key, "Real room entry presents its banner once")
	check(notice.title_label.text == "魔法森林", "Entry uses the actual region name")
	check(notice.elapsed < 0.2, "Transfer does not consume the banner lifetime")
	check(notice.mouse_filter == Control.MOUSE_FILTER_IGNORE and notice.title_label.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Entry banner leaves gameplay input available")
	notice.set_process(false)
	notice.advance(1.0)
	check(notice.banner.visible and notice.title_label.visible and notice.title_label.modulate.a > 0.99, "Recovered animation reveals the title")
	game.hud.toast("普通提示")
	check(notice.title_label.text == "魔法森林" and is_equal_approx(notice.elapsed, 1.0), "Ordinary toast does not replace or restart the region title")
	game._show_region_notice()
	check(is_equal_approx(notice.elapsed, 1.0), "Repeated flow refresh does not replay the banner")
	notice.advance(1.0)
	check(notice.visible and notice.banner.modulate.a < 1.0 and notice.banner.modulate.a > 0.0, "Recovered banner fade runs before completion")
	notice.advance(0.7)
	check(not notice.visible and not notice.is_processing(), "Entry banner disappears and stops processing after 2.67 seconds")
	game.hud.show_page("设置", [])
	check(not notice.visible and notice.entry_key.is_empty(), "Opening a page clears the transient banner")
	game.hud.close_page()
	check(not notice.visible, "Closing a page does not replay the entry")
	game._build_save_snapshot()
	game._load_room(true)
	await wait_loading()
	check(not notice.visible and game._pending_region_notice.is_empty(), "Resuming a saved room does not replay an entry")
	check(game.campaign.resolve_action().success, "Entrance action resolves")
	check(game.campaign.complete_room().success and game.campaign.advance().success, "Advance to a different room")
	game._select_node(int(game.campaign.choices()[0].node_id))
	await wait_loading()
	check(notice.visible and notice.entry_key == game._room_key and notice.title_label.text == "魔法森林", "A new room in the region gets a fresh entry animation")
	game.difficulty = 10
	check(game.campaign.generate(24680, 10).success, "Generate a route with alternate regions")
	game._select_region(1, true)
	await wait_loading()
	check(notice.visible and notice.title_label.text == "翠灵岛", "Alternate region uses its own actual name")
	game._process(0.0)
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390), Vector2i(2460, 1080)]:
		canvas.size = dimensions
		for frame in 3: await process_frame
		notice.clear()
		notice.present("visual:" + str(dimensions), "翠灵岛")
		notice.set_process(false)
		notice.advance(0.35)
		await capture(dimensions, "flash")
		notice.advance(0.65)
		var bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
		check(bounds.encloses(notice.banner.get_global_rect()), "Banner fits " + str(dimensions))
		check(bounds.encloses(notice.title_label.get_global_rect()), "Title fits " + str(dimensions))
		check(notice.banner.get_global_rect().end.y < dimensions.y * 0.4, "Banner stays near the top at " + str(dimensions))
		check(game.hud.message_label.get_global_rect().position.y >= notice.banner.get_global_rect().end.y, "Ordinary toast sits below the banner at " + str(dimensions))
		await capture(dimensions, "title")
		notice.advance(1.7)
		check(is_equal_approx(game.hud.message_label.position.y, 140.0 * game.hud.message_label.scale.y), "Toast returns to its normal position after the banner")
		await capture(dimensions, "hidden")
	game._camp()
	check(not notice.visible and notice.entry_key.is_empty() and game._pending_region_notice.is_empty(), "Return to camp cancels entry presentation")
	game.systems.decorations = null
	game.queue_free()
	await process_frame
	canvas.queue_free()
	await process_frame
	for child in root.get_children(): child.queue_free()
	await process_frame
	var report := {"checks": checks, "passed": failures.is_empty(), "failures": failures}
	FileAccess.open("res://reports/region-notice-test.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("REGION_NOTICE ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
