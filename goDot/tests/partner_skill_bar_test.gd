extends SceneTree

var checks := 0
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var bar := preload("res://scripts/presentation/partner_skill_bar.gd").new()
	root.add_child(bar)
	await process_frame
	check(not bar.visible and bar.buttons.size() == 2, "Unequipped bar stays hidden with two stable touch controls")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/partner_skills.json"))
	for skill in data.skills:
		var slot: Dictionary = skill.duplicate(true)
		slot.merge({"remaining": 0.0, "ready": true}, true)
		bar.update_state({"sp": 75, "max_sp": 75, "slots": [slot]})
		check(bar.buttons[0].art != null and bar.buttons[0].art.resource_path.ends_with(str(skill.icon) + ".png"), "APK skill icon loads: " + str(skill.id))
	var first: Dictionary = data.skills[0].duplicate(true)
	first.merge({"remaining": 0.0, "ready": true}, true)
	var second: Dictionary = data.skills[1].duplicate(true)
	second.merge({"remaining": 1.5, "ready": false}, true)
	bar.update_state({"sp": 40, "max_sp": 75, "slots": [first, second]})
	check(bar.visible and bar.size == Vector2(154, 118), "Bar dimensions remain fixed")
	check(bar.buttons[0].position == Vector2(0, 28) and bar.buttons[1].position == Vector2(78, 28) and bar.buttons[0].size == Vector2(68, 68), "Touch targets use the specified geometry")
	check(not bar.buttons[0].disabled and bar.buttons[1].disabled and bar.buttons[1].cooldown == 1.5, "Ready and cooling skills have independent availability")
	check(is_equal_approx(bar.buttons[0].resource_fraction, 40.0 / 75) and bar.buttons[0].resource_fraction == bar.buttons[1].resource_fraction, "Both skills show their shared energy")
	check(bar.energy_label.text == "SP 40 / 75", "Energy label includes current value and capacity")
	check(bar.buttons[0].tooltip_text.contains(str(first.name)) and bar.buttons[0].tooltip_text.contains("SP 25") and not bar.buttons[0].tooltip_text.contains("<#"), "Tooltip shows skill identity, cost and readable source description")
	var pressed: Array[int] = []
	bar.skill_pressed.connect(func(index: int): pressed.append(index))
	var touch := InputEventScreenTouch.new()
	touch.index = 31
	touch.position = bar.buttons[0].get_global_rect().get_center()
	touch.pressed = true
	bar.buttons[0]._input(touch)
	touch.pressed = false
	bar.buttons[0]._input(touch)
	check(pressed == [0], "Touch release emits the correct skill index once")
	touch.pressed = true
	bar.buttons[0]._input(touch)
	bar.update_state({"sp": 40, "max_sp": 75, "slots": [first, second]}, true, true)
	check(bar.buttons[0].disabled and bar.buttons[0].finger == -1 and bar.buttons[0].readiness_suspended and bar.buttons[0].low_effects, "Suspension releases held input and applies reduced effects")
	bar.update_state({"sp": 40, "max_sp": 75, "slots": [first]})
	check(not bar.buttons[1].visible and bar.buttons[1].disabled, "Removing a slot clears its touch control")
	bar.update_state({"sp": 0, "max_sp": 0, "slots": []})
	check(not bar.visible and bar.buttons[0].finger == -1, "Removing all skills hides and releases the bar")
	bar.queue_free()
	await process_frame
	print("PARTNER_SKILL_BAR_TEST ", JSON.stringify({"checks": checks, "passed": failures.is_empty(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)
