extends SceneTree

var checks := 0
var failures: Array[String] = []
var images: Array[String] = []
var canvas: SubViewport
var game: Node

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func render_frame() -> void:
	for frame in 3: await process_frame
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw

func _run() -> void:
	create_timer(120).timeout.connect(func(): quit(2))
	canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	game = load("res://scenes/main.tscn").instantiate()
	game.save_store = DungeonSaveStore.new("/private/tmp/battle-hud-visual-%d.json" % Time.get_ticks_usec())
	canvas.add_child(game)
	game.set_process(false)
	game.world.set_physics_process(false)
	game.world.presentation.audio_enabled = false
	game.world.auto_attack_enabled = false
	game.audio.stop()
	check(game.systems.begin_run(20261026, 1, 100, 0).success, "Visual adventure starts")
	for node in game.campaign.database.Nodes:
		if str(node.get("Flow", "")) == "Shop":
			game.campaign.start_practice(int(node.Id), 20261026)
			break
	game._load_room()
	var deadline := Time.get_ticks_msec() + 60000
	while game._transitioning and Time.get_ticks_msec() < deadline: await process_frame
	check(not game._transitioning, "Original room finishes preparing")
	game.world.set_process(false)
	game.world.paused = false
	game.hud.close_page()
	game.world.snap_camera()
	game.world.player.combat.add_buff("100300", 4 - game.world.player.combat.special_resource())
	game.world.player.combat.energy[3] = 37
	game.world.player.combat.cooldowns[3] = 0
	game.world.player.combat.health = 96
	game.profile.data.run.health = 96
	game._process(0)
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390), Vector2i(2460, 1080)]:
		canvas.size = dimensions
		await render_frame()
		game.hud._layout()
		game.hud.update_combat(game.world.player.combat, false)
		game.hud.objective_guide.update_target(game.world, false)
		game.hud.objective_guide._process(0.3)
		await render_frame()
		check(is_equal_approx(game.hud.reference_vitals.charge_fraction, 0.8), "Four sword-intent segments at %s" % dimensions)
		var key: DungeonTouchButton = game.hud.skill_by_slot[3]
		check(is_equal_approx(key.resource_fraction, 0.37) and not key.ready_full, "Ultimate shows independent 37 percent progress")
		check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(key.get_global_rect()), "Ultimate fits viewport at %s" % dimensions)
		if DisplayServer.get_name() != "headless":
			var picture := canvas.get_texture().get_image()
			var path := "res://reports/battle-hud-%dx%d.png" % [dimensions.x, dimensions.y]
			picture.save_png(path)
			images.append(path)
			var colors := {}
			for y in range(0, dimensions.y, 17):
				for x in range(0, dimensions.x, 17): colors[picture.get_pixel(x, y).to_rgba32()] = true
			check(colors.size() > 100, "Actual 3D room and HUD render a nonblank image")
		game.hud.show_page("暂停", [])
		game._process(0)
		check(not game.hud.objective_guide.visible, "Main pause hides guide")
		game.hud.close_page()
		game._process(0)
	await _check_vertical_fill()
	game.queue_free()
	await process_frame
	canvas.free()
	var report := {"checks": checks, "passed": failures.is_empty(), "failures": failures, "images": images,
		"scope": "Original main scene in a source shop room. Staged 4/5 JP and 37/100 SP. Desktop Godot rendering; not original Android runtime parity."}
	FileAccess.open("res://reports/battle-hud-visual-test.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("BATTLE_HUD_VISUAL_TEST ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func _check_vertical_fill() -> void:
	if DisplayServer.get_name() == "headless": return
	var probe := SubViewport.new()
	probe.size = Vector2i(128, 128)
	probe.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(probe)
	var key := DungeonTouchButton.new()
	key.position = Vector2(8, 8)
	key.size = Vector2(112, 112)
	key.art = game.hud.skill_by_slot[3].art
	key.ring = game.hud.skill_by_slot[3].ring
	key.unavailable = true
	key.resource_fraction = 0
	probe.add_child(key)
	await render_frame()
	var empty := probe.get_texture().get_image()
	key.resource_fraction = 0.37
	key.queue_redraw()
	await render_frame()
	var partial := probe.get_texture().get_image()
	var changed := 0
	var first_row := 128
	for y in range(128):
		for x in range(128):
			var a := empty.get_pixel(x, y)
			var b := partial.get_pixel(x, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.02:
				changed += 1
				first_row = mini(first_row, y)
	check(changed > 100, "Partial SP visibly changes rendered button pixels")
	check(first_row >= int(8 + 112 * (0.08 + 0.84 * 0.63)) - 1, "SP fill grows vertically from the bottom")
	partial.save_png("res://reports/burst-fill-37.png")
	key.resource_fraction = 1
	key.unavailable = false
	key.ready_full = true
	key.queue_redraw()
	await render_frame()
	check(key.ready_orbit.active, "Full ultimate starts its ready orbit")
	probe.free()
