extends SceneTree

const CloseUp = preload("res://scripts/presentation/camera_closeup.gd")
var checks := 0
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	var helper = CloseUp.new()
	helper.enter(1, "playerchara/axe_liedichongjibo_derivative")
	check(helper.target_offset == -1.0, "first original axe window starts at zero")
	check(is_equal_approx(helper.step(1.0 / 60.0), -0.1), "source per-frame zoom smoothing")
	helper.update_action(1, 667.0)
	check(helper.target_offset == 0.0, "window exit restores target")
	helper.update_action(1, 717.0)
	check(helper.target_offset == -3.0, "second axe window starts at 717ms")
	helper.update_action(2, 1217.0)
	check(helper.target_offset == -3.0, "foreign owner cannot advance action")
	helper.pause(true)
	var previous: float = helper.distance_offset
	helper.update_action(1, 1217.0)
	check(helper.step(1.0) == previous and helper.target_offset == -3.0, "pause freezes time and smoothing")
	helper.pause(false)
	helper.update_action(1, 1217.0)
	check(helper.target_offset == 0.0, "second window ends exactly")
	helper.enter(1, "orb_satk_start")
	check(helper.target_offset == 0.0, "conditioned event requires condition evidence")
	helper.enter(1, "orb_satk_start", func(_event): return true)
	check(helper.target_offset == -2.0, "approved buff condition enables source window")
	helper.enter(1, "skill_lance_weapon1")
	helper.update_action(1, 100.0)
	check(helper.target_offset == 0.0, "disabled source event stays disabled")
	helper.enter(1, "boss/born")
	check(helper.target_offset == 0.0, "no invented boss close-up")
	helper.enter(1, "ActGroup_playerchara/sys_dead")
	check(helper.target_offset == -4.0, "source death zoom")
	helper.exit(2)
	check(helper.target_offset == -4.0, "foreign owner cannot exit")
	helper.exit(1)
	check(helper.target_offset == 0.0, "exit resets target")
	helper.restore()
	check(helper.distance_offset == 0.0 and not helper.paused, "restore immediately clears state")
	print("camera_closeup_test checks=", checks, " failures=", failures)
	quit(0 if failures.is_empty() else 1)
