extends SceneTree

var assertions := 0
var failures: Array[String] = []
var hud: DungeonHud
var events: Array = []
var layouts: Array = []

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition: failures.append(message)

func touch(index: int, point: Vector2, pressed: bool, canceled := false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = point
	event.pressed = pressed
	event.canceled = canceled
	root.push_input(event, true)

func center(key: DungeonTouchButton) -> Vector2:
	return key.get_global_transform_with_canvas() * (key.size * 0.5)

func radius(key: DungeonTouchButton) -> float:
	return (key.size.x * 0.5 + key.hit_padding) * key.get_global_transform_with_canvas().get_scale().x

func run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	hud = DungeonHud.new()
	root.add_child(hud)
	hud.skill.connect(func(slot, pressed): events.append([slot, pressed]))
	hud.action.connect(func(kind, mode, _extra):
		if kind == "auto_attack_mode": hud.set_attack_mode(mode))
	var keys: Array = hud.skill_by_slot.values() + [hud.attack_mode_button]
	for dimensions in [Vector2i(640, 360), Vector2i(844, 390), Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(2460, 1080), Vector2i(1200, 900)]:
		root.size = dimensions
		await process_frame
		await process_frame
		hud._layout()
		var bounds = Rect2(Vector2.ZERO, hud.root.size)
		var controls: Array = []
		for index in keys.size():
			var key: DungeonTouchButton = keys[index]
			var point = center(key)
			var target_radius = radius(key)
			check(bounds.encloses(Rect2(point - Vector2.ONE * target_radius, Vector2.ONE * target_radius * 2)), "Entire touch target fits " + str(dimensions))
			check(target_radius * 2 >= 47.99, "Touch target is at least 48 pixels " + str(dimensions))
			for other in keys.slice(index + 1):
				check(point.distance_to(center(other)) > target_radius + radius(other) + 2, "Touch circles have a gap " + str(dimensions))
			controls.append({"center": [point.x, point.y], "touch_diameter": target_radius * 2})
			var rect = key.get_global_rect()
			var original_art = key._art_rect()
			# A touch near the rim must remain valid after the artwork shrinks.
			var rim = point + Vector2.RIGHT * (target_radius - 1)
			touch(index + 10, rim, true)
			check(key.finger == index + 10 and key.button_pressed, "Rim press captures " + str(index))
			check(key.visual_scale < 1, "Fast press has immediate feedback")
			key._advance_feedback(0.1)
			check(is_equal_approx(key.visual_scale, key.PRESSED_SCALE) and key._contains(rim) and key.get_global_rect() == rect, "Held scale keeps stable touch bounds")
			check(key._art_rect().get_center().is_equal_approx(original_art.get_center()) and key._art_rect().size.is_equal_approx(original_art.size * key.PRESSED_SCALE), "Only the centered artwork contracts")
			touch(99, Vector2.ZERO, false)
			check(key.button_pressed, "Other finger cannot release a held skill")
			touch(index + 10, Vector2.ZERO, false)
			key._advance_feedback(0.12)
			check(key.finger == -1 and not key.button_pressed and key.visual_scale > 1.0, "Outside release produces rebound")
			key._advance_feedback(0.1)
			check(is_equal_approx(key.visual_scale, 1.0) and key.get_global_rect() == rect, "Rebound settles without layout movement")
		layouts.append({"size": [dimensions.x, dimensions.y], "controls": controls})
		var attack: DungeonTouchButton = keys[0]
		var dodge: DungeonTouchButton = keys[1]
		events.clear()
		touch(1, center(attack), true)
		touch(2, center(dodge), true)
		check(attack.finger == 1 and dodge.finger == 2, "Two skills capture independent pointers")
		touch(1, Vector2.ZERO, false, true)
		check(attack.finger == -1 and attack.visual_scale == 1.0 and dodge.finger == 2, "Cancel resets one button immediately")
		touch(2, Vector2.ZERO, false)
		check(events == [[0, true], [1, true], [0, false], [1, false]], "Scaling adds no duplicate gameplay events")
		for cycle in 8:
			touch(3, center(attack), true)
			touch(3, center(attack), false)
		attack._advance_feedback(1)
		check(attack.visual_scale == 1.0 and events.size() == 20, "Rapid taps settle with one event pair per tap")
		touch(4, center(attack), true)
		hud.show_page("Menu", [])
		check(attack.finger == -1 and attack.visual_scale == 1.0, "Menu cancels held feedback")
		hud.close_page()
		touch(4, center(attack), true)
		attack._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		check(attack.finger == -1 and attack.visual_scale == 1.0, "Backgrounding clears held feedback")
		attack._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
		touch(4, center(attack), true)
		attack.disabled = true
		attack._process(0)
		check(attack.finger == -1 and attack.visual_scale == 1.0, "Disabled state releases the held action")
		attack.disabled = false
		touch(4, center(attack), true)
		hud._layout()
		for frame in 4: hud.set_adventure_mode(hud.adventure_mode)
		check(attack.finger == 4 and attack.visual_scale < 1.0, "Unchanged layout and mode refresh preserve held input")
		root.size = dimensions + Vector2i(20, 0)
		await process_frame
		hud._layout()
		check(attack.finger == -1 and attack.visual_scale == 1.0, "Changed geometry cancels stale pointer coordinates")
		touch(4, center(attack), true)
		touch(4, center(attack), false)
		attack._advance_feedback(0.04)
		check(attack.finger == -1 and attack.visual_scale < 0.92, "Same-frame tap still completes visible icon compression")
		attack._advance_feedback(0.3)
		check(is_equal_approx(attack.visual_scale, 1.0), "Quick tap settles fully")
	var burst: DungeonTouchButton = keys[3]
	burst.ready_full = true
	touch(5, center(burst), true)
	burst._advance_feedback(0.1)
	check(burst.ready_orbit.scale == Vector2.ONE, "Ready orbit keeps its full frame size during icon feedback")
	check((burst.ready_orbit.position + burst.ready_orbit.scale * burst.size * 0.5).is_equal_approx(burst.size * 0.5), "Ready orbit stays centered")
	touch(5, center(burst), false)
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.position = center(keys[0])
	mouse.pressed = true
	mouse.device = -1
	root.push_input(mouse, true)
	check(keys[0].finger == -1, "Emulated mouse does not duplicate touch")
	mouse.device = 0
	root.push_input(mouse, true)
	check(keys[0].finger == -2, "Desktop mouse captures skill")
	keys[0]._mouse_exited()
	check(keys[0].finger == -1 and keys[0].visual_scale == 1.0, "Leaving the window clears mouse feedback")
	check(DungeonHud.skill_safe_insets(Vector2(844, 390), Vector2(2532, 1170), Rect2(132, 0, 2268, 1107)).is_equal_approx(Vector2(44, 21)), "Mobile safe area converts native pixels to viewport coordinates")
	check(DungeonHud.skill_safe_insets(Vector2(844, 390), Vector2.ZERO, Rect2()).is_zero_approx(), "Missing safe area leaves layout unchanged")
	var report = {"assertions": assertions, "failures": failures, "layouts": layouts}
	FileAccess.open("res://reports/skill-controls-tests.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("SKILL_CONTROLS ", JSON.stringify({"assertions": assertions, "failures": failures, "viewports": layouts.size()}))
	hud.free()
	quit(0 if failures.is_empty() else 1)
