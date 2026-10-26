extends SceneTree

var game: Node
var canvas: SubViewport
var checks := 0
var failures: Array[String] = []
var captures: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _run() -> void:
	create_timer(100).timeout.connect(func(): quit(2))
	canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	game = load("res://scenes/main.tscn").instantiate()
	game.save_store = DungeonSaveStore.new("/private/tmp/pickup-world-visual-%d.json" % Time.get_ticks_usec())
	canvas.add_child(game)
	game.set_process(false)
	game.world.set_process(false)
	game.world.set_physics_process(false)
	game.world.presentation.audio_enabled = false
	game.world.auto_attack_enabled = false
	game.audio.stop()
	check(game.systems.begin_run(20261026, 1, 100, 0).success, "Actual game starts a run")
	var node_id := 0
	for node in game.campaign.database.Nodes:
		if str(node.get("Flow", "")) == "Shop":
			node_id = int(node.Id)
			break
	check(node_id > 0, "Original noncombat room fixture exists")
	game.campaign.start_practice(node_id, 20261026)
	game._load_room()
	game.world.set_process(true)
	var deadline := Time.get_ticks_msec() + 60000
	while game._transitioning and Time.get_ticks_msec() < deadline: await process_frame
	check(not game._transitioning and is_instance_valid(game.world.environment_root), "Original room finishes loading")
	game.world.set_process(false)
	game.world.set_physics_process(false)
	game.world.fighting = false
	game.world.paused = false
	game.hud.close_page()
	game.world.snap_camera()
	game.world.player.set_physics_process(false)
	game.world.player.set_process(false)
	var drops = game.world.ground_loot
	var point: Vector3 = game.world.player.position
	var side: Vector3 = game.world.camera.global_basis.x
	side.y = 0
	side = side.normalized()
	var forward := side.cross(Vector3.UP).normalized()
	# The source entrance is between two raised walls; use its adjacent open floor.
	var open_point := point - side * 2.0 - forward * 3.0
	var map: RID = game.world.get_world_3d().navigation_map
	if map.is_valid(): open_point = NavigationServer3D.map_get_closest_point(map, open_point)
	game.world.player.position = open_point
	game.world.player.previous_position = open_point
	game.world.player.reset_physics_interpolation()
	point = open_point
	game.world.snap_camera()
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390), Vector2i(2460, 1080)]:
		canvas.size = dimensions
		drops.clear()
		game._process(0)
		game.hud._layout()
		for frame in 5: await process_frame
		var baseline: Image
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			baseline = canvas.get_texture().get_image()
		drops.spawn(20105, point + side * 1.05)
		drops.spawn(10100, point + side * 2.3 - forward * 2.5)
		drops.spawn(15101, point - side * 2.3 - forward * 2.5)
		drops.spawn(101, point - side * 1.2 - forward * 3.3, 12, true)
		drops.spawn(102, point - forward * 3.3, 9, true)
		drops.spawn(103, point + side * 1.2 - forward * 3.3, 2, true)
		game._process(0)
		for frame in 5: await process_frame
		var card = game.hud.pickup_panel
		var suffix := "%dx%d" % [dimensions.x, dimensions.y]
		check(card.visible and game.hud.pickup_name.text == "迅捷之靴", "Actual HUD shows nearby boots description: " + suffix)
		check(game.hud.primary.visible and game.hud.primary.text == "拾取", "Actual HUD exposes manual pickup command: " + suffix)
		check(not game.hud.modal_open and not game.world.fighting, "Pickup remains a nonmodal room interaction: " + suffix)
		check(drops.entries.size() == 6, "Visual fixture retains all six ground drops: " + suffix)
		var bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
		check(bounds.encloses(card.get_global_rect()), "Pickup description fits actual viewport: " + suffix)
		check(bounds.encloses(game.hud.primary.get_global_rect()), "Pickup command fits actual viewport: " + suffix)
		check(bounds.encloses(card.close_button.get_global_rect()), "Close command fits actual viewport: " + suffix)
		check(not card.get_global_rect().intersects(game.hud.primary.get_global_rect()), "Pickup description and command do not overlap: " + suffix)
		for button in game.hud.skill_buttons:
			if not button.is_visible_in_tree(): continue
			check(not card.get_global_rect().intersects(button.get_global_rect()), "Pickup description avoids skill control %s: %s" % [button.name, suffix])
			check(not game.hud.primary.get_global_rect().intersects(button.get_global_rect()), "Pickup command avoids skill control %s: %s" % [button.name, suffix])
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var screenshot := canvas.get_texture().get_image()
			check(not screenshot.is_empty() and screenshot.get_size() == dimensions, "Actual room capture has viewport pixels: " + suffix)
			var colors := _scene_colors(screenshot)
			check(colors > 80, "Unframed 3D room has nonblank varied central pixels: " + suffix)
			var differences: Array = []
			for entry in drops.entries:
				var projected: Vector2 = game.world.camera.unproject_position(entry.visual.global_position)
				check(bounds.has_point(projected), "Ground sprite projects inside actual camera: %s:%s" % [entry.id, suffix])
				var changed := _changed_pixels(baseline, screenshot, projected)
				differences.append({"id": entry.id, "material": entry.material, "changed_pixels": changed})
				check(changed > 8, "Ground sprite changes rendered source-region pixels: %s:%s" % [entry.id, suffix])
			var path := "res://reports/pickup-world-%s.png" % suffix
			screenshot.save_png(path)
			captures.append({"viewport": [dimensions.x, dimensions.y], "path": path, "central_color_count": colors, "drops": differences})
		var before: int = int(game.profile.data.run.inventory.get("20105", 0))
		await _click(card.close_button.get_global_rect().get_center())
		game._process(0)
		await process_frame
		check(not card.visible, "Physical close stays dismissed through main update: " + suffix)
		check(game.hud.primary.visible and game.hud.primary.text == "拾取", "Closing description keeps actual pickup command: " + suffix)
		check(drops.entries.size() == 6 and int(game.profile.data.run.inventory.get("20105", 0)) == before, "Closing description grants no item and deletes no drop: " + suffix)
		check(game.hud.joystick.finger == -1 and game.hud.joystick.value == Vector2.ZERO, "Closing description leaves movement untouched: " + suffix)
		await _click(game.hud.primary.get_global_rect().get_center())
		check(drops.entries.size() == 5 and int(game.profile.data.run.inventory.get("20105", 0)) == before + 1, "Actual pickup button still grants boots exactly once after dismiss: " + suffix)
	var report := {"checks": checks, "passed": failures.is_empty(), "failures": failures,
		"room_node": node_id, "captures": captures, "renderer": DisplayServer.get_name()}
	var output := FileAccess.open("res://reports/pickup-world-visual-tests.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t") + "\n")
	output.close()
	print("PICKUP_WORLD_VISUAL_TEST ", JSON.stringify(report))
	game.queue_free()
	canvas.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _click(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	canvas.push_input(motion, true)
	await process_frame
	var press := InputEventMouseButton.new()
	press.position = point
	press.global_position = point
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	canvas.push_input(press, true)
	for frame in 2:
		game._process(0)
		await process_frame
	var release := InputEventMouseButton.new()
	release.position = point
	release.global_position = point
	release.button_index = MOUSE_BUTTON_LEFT
	canvas.push_input(release, true)
	await process_frame

func _scene_colors(image: Image) -> int:
	var colors: Dictionary = {}
	for y in range(int(image.get_height() * 0.22), int(image.get_height() * 0.7), 9):
		for x in range(int(image.get_width() * 0.2), int(image.get_width() * 0.63), 9):
			var color := image.get_pixel(x, y)
			if maxf(color.r, maxf(color.g, color.b)) < 0.03: continue
			colors[color.to_rgba32()] = true
	return colors.size()

func _changed_pixels(before: Image, after: Image, center: Vector2) -> int:
	var changed := 0
	for y in range(maxi(0, int(center.y) - 18), mini(after.get_height(), int(center.y) + 18)):
		for x in range(maxi(0, int(center.x) - 18), mini(after.get_width(), int(center.x) + 18)):
			var first := before.get_pixel(x, y)
			var second := after.get_pixel(x, y)
			if absf(first.r - second.r) + absf(first.g - second.g) + absf(first.b - second.b) > 0.08: changed += 1
	return changed
