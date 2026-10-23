extends SceneTree

var failures: Array[String] = []
var checks := 0
var hud: DungeonHud
var stick: DungeonJoystick
var captures := "--capture" in OS.get_cmdline_user_args()

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func touch(index: int, point: Vector2, pressed: bool, canceled := false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = point
	event.pressed = pressed
	event.canceled = canceled
	root.push_input(event, true)

func drag(index: int, point: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = point
	root.push_input(event, true)

func location(point: Vector2) -> Vector2:
	return stick.get_global_transform_with_canvas() * point

func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	hud = DungeonHud.new()
	root.add_child(hud)
	stick = hud.joystick
	for dimensions in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2460, 1080), Vector2i(1200, 900)]:
		root.size = dimensions
		await process_frame
		await process_frame
		var start := location(stick.size * Vector2(0.75, 0.4))
		check(start.x > 218, "Expanded area reaches beyond old joystick at " + str(dimensions))
		check(Rect2(Vector2.ZERO, stick.size).encloses(Rect2(stick.home - Vector2.ONE * stick.radius, Vector2.ONE * stick.radius * 2)), "Idle hint fits safe area")
		touch(2, start, true)
		check(stick.finger == 2 and stick.value == Vector2.ZERO, "Any point in left movement area starts neutral")
		drag(2, start + Vector2(40, 0))
		check(stick.value.x > 0.5, "Floating joystick follows drag")
		var skill := hud.skill_buttons[0]
		var skill_point := skill.get_global_rect().get_center()
		touch(7, skill_point, true)
		check(stick.finger == 2 and skill.finger == 7 and skill.button_pressed, "Second finger uses skill while moving")
		touch(9, start, false)
		check(stick.finger == 2, "Foreign release cannot stop movement")
		drag(2, Vector2(dimensions.x + 100, -100))
		check(stick.finger == 2 and is_equal_approx(stick.value.length(), 1), "Dragging beyond capture area keeps control with bounded speed")
		touch(2, Vector2(-100, -100), false)
		check(stick.finger == -1 and stick.value == Vector2.ZERO and skill.button_pressed, "Outside release stops movement without releasing skill")
		touch(7, skill_point, false, true)
		check(skill.finger == -1 and not skill.button_pressed, "Skill cancellation releases its pointer")
		touch(2, start, true)
		drag(2, start + Vector2(0, -60))
		touch(2, start, false, true)
		check(stick.finger == -1 and stick.value == Vector2.ZERO, "Touch cancellation clears movement")
		touch(4, start, true)
		check(stick.finger == 4, "Immediate new touch works after cancellation")
		drag(4, start + Vector2(60, 0))
		touch(4, start, true)
		check(stick.finger == 4 and stick.value == Vector2.ZERO, "Reused touch ID recovers a missed release")
		stick.hide()
		check(stick.finger == -1 and stick.value == Vector2.ZERO, "Hiding synchronously resets capture")
		stick.show()
		for cycle in 3:
			touch(4, start, true)
			drag(4, start + Vector2(60, 0))
			hud.show_page("Menu", [])
			check(stick.finger == -1 and not stick.visible, "Opening menu cancels movement")
			touch(4, start, false)
			hud.close_page()
			touch(5, start, true)
			check(stick.finger == 5, "Closing menu restores touch area immediately")
			touch(5, start, false)
		var blocker := Button.new()
		blocker.position = start - Vector2(30, 30)
		blocker.size = Vector2(60, 60)
		hud.root.add_child(blocker)
		stick.excluded_controls.append(blocker)
		touch(5, start, true)
		check(stick.finger == -1, "Visible controls inside movement area retain priority")
		touch(5, start, false)
		stick.excluded_controls.erase(blocker)
		blocker.free()
		touch(5, start, true)
		stick._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		check(stick.finger == -1 and stick.value == Vector2.ZERO, "Focus loss clears touch capture")
		touch(6, start, true)
		check(stick.finger == 6, "Touch works after returning to app")
		touch(6, start, false)
		var mouse := InputEventMouseButton.new()
		mouse.button_index = MOUSE_BUTTON_LEFT
		mouse.position = start
		mouse.pressed = true
		mouse.device = -1
		root.push_input(mouse, true)
		check(stick.finger == -1, "Emulated mouse cannot duplicate touch")
		mouse.device = 0
		root.push_input(mouse, true)
		check(stick.finger == -2 and stick.value == Vector2.ZERO, "Desktop mouse starts floating joystick")
		stick._process(0)
		check(stick.finger == -1, "Missing mouse-up is recovered from physical button state")
		root.push_input(mouse, true)
		stick._mouse_exited()
		check(stick.finger == -1, "Mouse leaving window cannot leave a stuck joystick")
		touch(6, start, true)
		stick.size += Vector2(1, 1)
		check(stick.finger == -1, "Resize resets capture before changing coordinates")
		hud._layout()
		if captures:
			await capture("idle-%dx%d" % [dimensions.x, dimensions.y])
			touch(2, start, true)
			drag(2, start + Vector2(40, -20))
			await capture("active-%dx%d" % [dimensions.x, dimensions.y])
			touch(2, start, false)
	await check_gameplay()
	var report := {"passed": failures.is_empty(), "assertions": checks, "failures": failures, "display": DisplayServer.get_name()}
	FileAccess.open("res://reports/joystick-test.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("JOYSTICK_TEST ", JSON.stringify(report))
	hud.free()
	quit(0 if failures.is_empty() else 1)

func capture(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	check(not image.is_empty(), "Rendered joystick viewport is nonblank")
	image.save_png("res://reports/joystick-" + label + ".png")
	var point := stick._home() if stick.finger == -1 else stick.center
	var sample := location(point + Vector2.UP * stick.radius)
	var background := image.get_pixel(int(sample.x), int(sample.y - 8))
	var changed := 0
	for x in range(int(sample.x) - 4, int(sample.x) + 5):
		for y in range(int(sample.y) - 2, int(sample.y) + 3):
			var pixel := image.get_pixel(x, y)
			if Vector3(pixel.r - background.r, pixel.g - background.g, pixel.b - background.b).length() > 0.05: changed += 1
	check(changed > 5, "Joystick ring remains visible on dark backgrounds")

func check_gameplay() -> void:
	for name in ["move_left", "move_right", "move_up", "move_down"]:
		if not InputMap.has_action(name): InputMap.add_action(name)
	var world := DungeonWorld.new()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.hud = hud
	var combat := preload("res://scripts/domain/combat.gd").new()
	combat.configure()
	var player := world.create_player(combat, 1, Vector3.ZERO)
	var start := location(stick.size * Vector2(0.7, 0.45))
	touch(3, start, true)
	drag(3, start + Vector2(64, 0))
	var initial := player.position
	for i in 20:
		await physics_frame
		world._background = false
		world._physics_process(1.0 / 60)
	check(Vector2(player.position.x - initial.x, player.position.z - initial.z).length() > 0.5, "Touch drag moves physical player")
	touch(3, Vector2(-100, -100), false)
	for i in 20:
		await physics_frame
		world._physics_process(1.0 / 60)
	check(player.desired_velocity == Vector3.ZERO and player.locomotion == Vector3.ZERO, "Lifting finger stops player without stuck movement")
	world.free()
