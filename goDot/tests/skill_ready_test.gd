extends SceneTree

const Combat = preload("res://scripts/domain/combat.gd")
var assertions := 0
var failures: Array[String] = []
var hud: DungeonHud

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition: failures.append(message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	root.size = Vector2i(1280, 720)
	hud = DungeonHud.new()
	root.add_child(hud)
	await process_frame
	for character in range(1, 8):
		var combat = Combat.new()
		combat.configure(null, null, character)
		for slot in range(5): combat.energy[slot] = float(combat.fighter.skills[slot].maxSp)
		hud.update_combat(combat, false)
		for slot in range(5):
			var key: DungeonTouchButton = hud.skill_buttons[slot]
			var definition: Dictionary = combat.fighter.skills[slot]
			var expected = slot == 3 and float(definition.maxSp) > 0 and float(definition.maxSp) >= float(definition.sp)
			check(key.ready_full == expected and key.ready_orbit.active == expected, "Character %d slot %d full stock readiness" % [character, slot])
			var dimensions = key.size
			var inside = key._contains(key.global_position + key.size * 0.5)
			var outside = key._contains(key.global_position + Vector2(key.size.x * 1.05, key.size.y * 0.5))
			check(inside and not outside and key.size == dimensions, "Orbit retains original circular touch bounds")
			if slot != 3 or float(definition.maxSp) <= 0: continue
			combat.energy[slot] = maxf(0.0, float(definition.maxSp) - 0.1)
			hud.update_combat(combat, false)
			check(not key.ready_orbit.active, "Less than full stock extinguishes immediately")
			if float(definition.sp) < float(definition.maxSp):
				combat.energy[slot] = float(definition.sp)
				hud.update_combat(combat, false)
				check(not key.ready_full, "One available charge is not full multi-charge stock")
			combat.energy[slot] = float(definition.maxSp)
			hud.update_combat(combat, false)
			check(key.ready_orbit.active and is_zero_approx(key.ready_orbit.burst_age), "Entering full stock starts one burst")
			key.ready_orbit.advance(0.2)
			hud.update_combat(combat, false)
			check(key.ready_orbit.burst_age >= 0.2, "Repeated full HUD updates do not restart burst")
			combat.cooldowns[slot] = 0.2
			hud.update_combat(combat, false)
			check(not key.ready_orbit.active, "Cooldown extinguishes full stock orbit")
			combat.cooldowns[slot] = 0
			hud.update_combat(combat, false)
			key.disabled = true
			key._process(0)
			check(not key.ready_orbit.active, "Disabled button has no ready particles")
			key.disabled = false
			key._process(0)
			combat.energy[slot] = 0
			hud.update_combat(combat, false)
			check(not key.ready_orbit.active, "Spent resource removes orbit immediately")
			combat.energy[slot] = float(definition.maxSp)
			hud.update_combat(combat, false)
		combat.health = 0
		hud.update_combat(combat, false)
		for key in hud.skill_buttons: check(not key.ready_orbit.active, "Dead player has no readiness orbit")
	var combat = Combat.new()
	combat.configure()
	for slot in range(5): combat.energy[slot] = float(combat.fighter.skills[slot].maxSp)
	hud.update_combat(combat, false)
	var button: DungeonTouchButton = hud.skill_buttons[3]
	hud.readiness_suspended = true
	hud.update_combat(combat, false)
	check(not button.ready_orbit.active, "Pause suppresses ready particles")
	hud.readiness_suspended = false
	hud.update_combat(combat, false)
	button._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not button.ready_orbit.active, "Background focus loss clears ready particles")
	button._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	check(button.ready_orbit.active, "Focus restores eligible ready indication")
	hud.skill_cluster.hide()
	check(not button.ready_orbit.active, "Hidden controls leave no residual orbit")
	hud.skill_cluster.show()
	check(button.ready_orbit.active, "Visible controls restore full ready indication")
	hud.low_effects = true
	hud.update_combat(combat, false)
	check(button.ready_orbit.low_effects, "Reduced effects preference reaches orbit")
	var touch = InputEventScreenTouch.new()
	touch.index = 4
	touch.position = button.global_position + button.size * 0.5
	touch.pressed = true
	button._input(touch)
	check(button.finger == 4 and button.button_pressed, "Ready effect preserves touch capture")
	touch.pressed = false
	touch.position = Vector2.ZERO
	button._input(touch)
	check(button.finger == -1 and not button.button_pressed, "Ready effect preserves outside release")
	if "--render-check" in OS.get_cmdline_user_args():
		await screenshots(combat)
	var report = {"assertions": assertions, "failures": failures, "characters": 7, "render_check": "--render-check" in OS.get_cmdline_user_args()}
	FileAccess.open("res://reports/skill-ready-tests.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("SKILL_READY ", JSON.stringify(report))
	hud.free()
	quit(0 if failures.is_empty() else 1)

func screenshots(combat: RefCounted) -> void:
	root.grab_focus()
	hud.navigation.hide()
	hud.counters.hide()
	hud.vitals.hide()
	hud.title_label.hide()
	hud.joystick.hide()
	var background = ColorRect.new()
	background.color = Color("28433c")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.root.add_child(background)
	hud.root.move_child(background, 0)
	for dimensions in [Vector2i(1280, 720), Vector2i(960, 540)]:
		root.size = dimensions
		await process_frame
		hud._layout()
		for state in ["full", "partial", "spent", "reduced"]:
			hud.low_effects = state == "reduced"
			for slot in range(5):
				var capacity = float(combat.fighter.skills[slot].maxSp)
				combat.energy[slot] = capacity if state in ["full", "reduced"] else capacity * 0.5 if state == "partial" else 0.0
			hud.update_combat(combat, false)
			for key in hud.skill_buttons:
				key._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
				key.ready_orbit.set_process(false)
				key.ready_orbit.advance(0.8)
			await process_frame
			await RenderingServer.frame_post_draw
			var image = root.get_texture().get_image()
			var pixel_scale = Vector2(image.get_size()) / hud.root.size
			var region = Rect2i(Vector2i((hud.skill_cluster.position - Vector2(8, 8)) * pixel_scale), Vector2i(Vector2(436, 346) * pixel_scale))
			var crop = image.get_region(region)
			crop.save_png("res://reports/skill-ready-%s-%dx%d.png" % [state, dimensions.x, dimensions.y])
			var warm_pixels := 0
			for y in crop.get_height():
				for x in crop.get_width():
					var pixel = crop.get_pixel(x, y)
					if pixel.r > 0.3 and pixel.g < pixel.r * 0.75 and pixel.b < pixel.r * 0.4: warm_pixels += 1
			check(warm_pixels > 0 if state in ["full", "reduced"] else warm_pixels == 0, "%s screenshot has warm particles only at full ultimate stock (%d pixels)" % [state, warm_pixels])
