extends SceneTree

var failures: Array[String] = []
var measurements: Array = []
var game: Node
var canvas: SubViewport

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _run() -> void:
	canvas = SubViewport.new()
	canvas.size = Vector2i(1280, 720)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var display = TextureRect.new()
	display.texture = canvas.get_texture()
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(display)
	game = load("res://scenes/main.tscn").instantiate()
	game.save_store = DungeonSaveStore.new("res://reports/presentation-test-%d.json" % Time.get_ticks_usec())
	canvas.add_child(game)
	await process_frame
	game.world.player.position = Vector3(28.8, 0.1, 66.2)
	for i in 50: await process_frame
	for dimensions in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2460, 1080), Vector2i(1200, 900)]:
		canvas.size = dimensions
		game.hud.close_page()
		for i in 8: await process_frame
		var controls = game.hud.skill_buttons
		check(controls[0].size.x > controls[1].size.x, "Attack larger than dodge")
		check(controls[2].position.y < controls[0].position.y and controls[3].position.y < controls[0].position.y, "Skills above attack")
		for key in controls:
			check(Rect2(Vector2.ZERO, game.hud.root.size).encloses(key.get_global_rect()), "Skill inside viewport " + str(dimensions))
		await _capture("camp-%dx%d" % [dimensions.x, dimensions.y])
		game.menus.open("characters")
		for i in 8: await process_frame
		await _capture("characters-%dx%d" % [dimensions.x, dimensions.y])
	game.hud.close_page()
	for name in ["camp", "weapons", "partners", "talents", "inventory", "archive", "mall", "settings", "awakening", "tasks", "tokens", "amplifiers", "work", "dispatch", "meals", "buildings", "npcs", "npc", "achievements", "difficulty", "character_talents"]:
		game.menus.open(name, 1 if name in ["weapons", "npc"] else 100 if name == "tasks" else 0)
		await process_frame
		check(game.hud.modal_open and game.hud.page.displayed_row_count() > 0, "Page populated " + name)
		if name in ["camp", "archive", "settings", "weapons", "talents", "buildings", "awakening", "difficulty", "mall"]: await _capture(name)
	game.hud.close_page()
	game.world.player.combat.health = 0
	await process_frame
	check(game.hud.health.value == 0, "Zero HP shows empty bar")
	game.world.player.combat.health = game.world.player.combat.max_health
	game._smoke_begin()
	for i in 100: await process_frame
	await _capture("battle")
	var frames: Array = []
	var previous_frame = Time.get_ticks_usec()
	for i in 120:
		await process_frame
		var now = Time.get_ticks_usec()
		frames.append((now - previous_frame) / 1000.0)
		previous_frame = now
	frames.sort()
	var report = {"passed": failures.is_empty(), "failures": failures, "screenshots": measurements, "wall_frame_median_ms": frames[60], "wall_frame_p95_ms": frames[114], "performance_scope": "Wall time between frames, includes frame cap and vsync; no matching pre-change baseline, not a 10-percent performance acceptance result.", "static_memory": Performance.get_monitor(Performance.MEMORY_STATIC), "missing_icons": DungeonStyle.missing.keys(), "renderer": RenderingServer.get_video_adapter_name()}
	var file = FileAccess.open("res://reports/presentation-tests.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("PRESENTATION ", JSON.stringify(report))
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var image = canvas.get_texture().get_image()
	var path = "res://reports/style-" + name + ".png"
	image.save_png(path)
	measurements.append({"name": name, "width": image.get_width(), "height": image.get_height(), "path": path})
