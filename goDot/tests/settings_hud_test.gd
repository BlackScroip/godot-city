extends SceneTree

const EDITOR = preload("res://scripts/presentation/touch_layout_editor.gd")
var failures: Array[String] = []
var checks := 0
var hud: DungeonHud
var skill_events: Array = []
var test_path := "/private/tmp/city-touch-settings-%d.cfg" % Time.get_ticks_usec()

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _touch(editor: Control, index: int, point: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = point
	event.pressed = pressed
	editor._input(event)

func _drag(editor: Control, index: int, point: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = point
	editor._input(event)

func _center(key: Control) -> Vector2:
	return key.get_global_transform_with_canvas() * (key.size * 0.5)

func _run() -> void:
	create_timer(30).timeout.connect(func(): quit(2))
	EDITOR.settings_path = test_path
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1600, 900)
	hud = DungeonHud.new()
	root.add_child(hud)
	hud.skill.connect(func(slot, pressed): skill_events.append([slot, pressed]))
	await process_frame
	await process_frame
	hud._layout()
	var stock_attack := _center(hud.skill_buttons[0])
	var stock_size := hud.skill_buttons[0].size
	var partner_geometry: Array = hud.partner_skill_bar.buttons.map(func(key): return [key.position, key.size])
	check(hud._touch_layout.is_empty(), "A new install keeps the unmodified skill layout")
	for index in hud.TOUCH_CONTROL_IDS.size():
		var key: Control = hud.skill_buttons[index] if index < 4 else hud.attack_mode_button
		check(key.position == hud.SKILL_POSITIONS[index] and key.size.x == hud.SKILL_SIZES[index], "Default source geometry is unchanged for slot %d" % index)
	check(hud.joystick.home.is_equal_approx(Vector2(128, 382)), "Default joystick retains its original local home")
	hud.update_room_timer(72.9, true)
	check(not hud.room_timer.visible, "Room timer is hidden by default")
	hud.apply_settings({"show_timer": true, "joystick_fixed": true})
	check(hud.room_timer.visible and hud.room_timer.text == "01:12", "Timer reflects real elapsed room time")
	check(hud.joystick.fixed_mode, "HUD applies fixed joystick setting")
	hud.update_room_timer(72.9, false)
	check(not hud.room_timer.visible, "Timer does not appear outside an active run")
	hud.update_room_timer(72.9, true)
	var stock_navigation := hud.navigation.position
	var stock_counters := hud.counters.position
	hud.apply_settings({"show_timer": true, "ui_width": 100, "ui_height": 50})
	check(hud.counters.position.is_equal_approx(stock_counters + Vector2(78.125, 50)), "Canonical safe padding moves left and top HUD inwards")
	check(hud.navigation.position.is_equal_approx(stock_navigation + Vector2(-78.125, 50)), "Canonical safe padding moves right HUD inwards")
	check(_center(hud.skill_buttons[0]).is_equal_approx(stock_attack - Vector2(78.125, 0)), "Width setting also adjusts combat controls")
	hud.apply_settings({"show_timer": true})
	hud.show_page("Settings", [])
	check(not hud.room_timer.visible, "Modal pages conceal the timer")
	hud.begin_touch_customization()
	await process_frame
	var editor: Control = hud.touch_editor
	check(is_instance_valid(editor) and hud.modal_open and not hud.page.visible, "Touch editor temporarily replaces settings while gameplay remains blocked")
	check(not hud.skill_cluster.visible and not hud.joystick.visible, "Live gameplay touch controls are suspended during editing")
	var original: Dictionary = editor.draft.duplicate(true)
	var from: Vector2 = editor._center("attack")
	_touch(editor, 1, from, true)
	_drag(editor, 2, Vector2(600, 500))
	check(editor.draft.attack == original.attack, "A second finger cannot move a captured control")
	_drag(editor, 1, Vector2(840, 530))
	_touch(editor, 1, Vector2(840, 530), false)
	check(editor.draft.attack.center.is_equal_approx(Vector2(840, 530) / Vector2(1600, 900)), "Dragging stores independent normalized coordinates")
	check(editor.draft.dodge == original.dodge and editor.draft.joystick == original.joystick, "Dragging one control preserves other controls")
	editor.size_slider.value = 125
	check(is_equal_approx(editor.draft.attack.scale, 1.25), "Size slider changes only the selected control")
	editor.cancel_button.pressed.emit()
	check(not is_instance_valid(hud.touch_editor) and hud.page.visible and hud.modal_open, "Cancel restores the settings modal")
	check(_center(hud.skill_buttons[0]).is_equal_approx(stock_attack) and not FileAccess.file_exists(test_path), "Cancel leaves active layout and disk unchanged")
	hud.begin_touch_customization()
	await process_frame
	editor = hud.touch_editor
	from = editor._center("attack")
	_touch(editor, 3, from, true)
	_drag(editor, 3, Vector2(840, 530))
	_touch(editor, 3, Vector2(840, 530), false)
	editor.size_slider.value = 125
	editor._select("auto")
	_touch(editor, 4, editor._center("auto"), true)
	_drag(editor, 4, Vector2(450, 510))
	_touch(editor, 4, Vector2(450, 510), false)
	var saved_draft: Dictionary = editor.draft.duplicate(true)
	editor.save_button.pressed.emit()
	check(not is_instance_valid(hud.touch_editor) and hud.page.visible and hud.modal_open, "Successful save returns to settings")
	check(EDITOR.read_layout() == saved_draft and FileAccess.file_exists(test_path), "Saved layout survives ConfigFile round trip")
	hud.close_page()
	check(_center(hud.skill_buttons[0]).is_equal_approx(Vector2(840, 530)) and hud.skill_buttons[0].size == stock_size * 1.25, "Saved geometry is applied to real combat buttons")
	check(_center(hud.attack_mode_button).is_equal_approx(Vector2(450, 510)), "Custom auto-attack layout targets the automation switch")
	check(hud.partner_skill_bar.buttons.map(func(key): return [key.position, key.size]) == partner_geometry, "Custom auto-attack layout leaves partner skill geometry untouched")
	var event := InputEventScreenTouch.new()
	event.index = 7
	event.pressed = true
	event.position = _center(hud.skill_buttons[0])
	hud.skill_buttons[0]._input(event)
	hud._layout()
	check(hud.skill_buttons[0].finger == 7, "Unchanged custom layout preserves a held gameplay button")
	hud.skill_buttons[0].release(true)
	var reloaded := DungeonHud.new()
	root.add_child(reloaded)
	await process_frame
	reloaded._layout()
	check(reloaded._touch_layout == saved_draft and _center(reloaded.skill_buttons[0]).is_equal_approx(Vector2(840, 530)), "A fresh HUD reloads the persisted touch arrangement")
	reloaded.free()
	root.size = Vector2i(844, 390)
	await process_frame
	await process_frame
	hud._layout()
	check((_center(hud.skill_buttons[0]) / Vector2(844, 390)).is_equal_approx(saved_draft.attack.center), "Custom normalized centers survive viewport changes")
	for key in hud.skill_buttons + [hud.attack_mode_button]:
		check(Rect2(Vector2.ZERO, hud.root.size).encloses(key.get_global_rect()), "Customized control remains within mobile viewport")
	hud.joystick._begin_pointer(20, hud.joystick.home + Vector2(20, 0))
	hud._layout()
	check(hud.joystick.finger == 20, "An unchanged mobile layout preserves a held custom joystick")
	hud.joystick._reset()
	hud.show_page("Settings", [])
	hud.begin_touch_customization()
	await process_frame
	editor = hud.touch_editor
	var before_failure := hud._touch_layout.duplicate(true)
	EDITOR.settings_path = test_path + "/missing/controls.cfg"
	editor.save_button.pressed.emit()
	check(is_instance_valid(hud.touch_editor) and editor.status.text == "保存失败，请重试", "Persistence errors leave the editor open with accurate feedback")
	check(hud._touch_layout == before_failure, "Failed save cannot mutate active controls")
	check(not hud.reset_touch_customization() and hud._touch_layout == before_failure, "Failed reset cannot erase active layout")
	EDITOR.settings_path = test_path
	editor.reset_button.pressed.emit()
	check(editor.draft != saved_draft and hud._touch_layout == before_failure, "Preview reset remains uncommitted until save")
	hud.cancel_touch_customization()
	check(hud.reset_touch_customization() and EDITOR.read_layout().is_empty(), "Reset atomically replaces persisted custom controls with stock defaults")
	for index in 4:
		check(hud.skill_buttons[index].position == hud.SKILL_POSITIONS[index] and hud.skill_buttons[index].size.x == hud.SKILL_SIZES[index], "Reset restores stock source geometry")
	check(EDITOR.normalize({"attack": {"center": Vector2(NAN, 0.5)}, "dodge": {"center": Vector2(0.5, 0.5), "scale": INF}}).is_empty(), "Corrupt stored values cannot inject invalid geometry")
	hud.begin_touch_customization()
	hud.close_page()
	check(not is_instance_valid(hud.touch_editor) and not hud.modal_open, "Closing the host page cancels the editor completely")
	hud.free()
	DirAccess.remove_absolute(test_path)
	DirAccess.remove_absolute(test_path + ".tmp")
	EDITOR.settings_path = "user://touch_controls.cfg"
	print("SETTINGS_HUD ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
