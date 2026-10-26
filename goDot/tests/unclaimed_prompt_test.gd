extends SceneTree

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr(message)

func _run() -> void:
	var canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var hud = DungeonHud.new()
	canvas.add_child(hud)
	var rows = [
		{"title": "未开启的宝箱", "count": 2, "icon": "sprite_conversation_gift"},
		{"title": "精灵祭坛", "count": 1, "icon": "res://assets/environment_effects/spirit_altar_egg.png"},
		{"title": "未拾取的物品", "count": 12, "icon": "sprite_conversation_get"}]
	var commands: Array[String] = []
	hud.action.connect(func(kind, _id, _extra): commands.append(kind))
	for count in [1, 2, 3, 12]:
		var data = rows.slice(0, mini(count, 3))
		if count == 12:
			data = []
			for index in 12:
				data.append({"title": "未领取的奖励物品名称较长时应当自动换行", "count": 12345, "icon": "sprite_conversation_gift"})
		hud.show_page("确认离开", data, "unclaimed")
		var view = hud.page.unclaimed_view
		for dimensions in [Vector2i(2460, 1080), Vector2i(1600, 900), Vector2i(844, 390), Vector2i(640, 360), Vector2i(390, 844)]:
			canvas.size = dimensions
			for frame in 8: await process_frame
			var bounds = Rect2(Vector2.ZERO, Vector2(dimensions))
			check(bounds.encloses(view.dialog.get_global_rect()), "Dialog with %d rows fits %s" % [count, dimensions])
			check(view.dialog.get_global_rect().get_center().distance_to(bounds.get_center()) <= 1.5, "Dialog stays centered at %s" % dimensions)
			for control in [view.heading, view.introduction, view.reward_scroll, view.warning, view.return_button, view.continue_button]:
				check(view.dialog.get_global_rect().encloses(control.get_global_rect()), "Content stays inside dialog at %s" % dimensions)
			check(view.reward_scroll.get_global_rect().end.y <= view.warning.get_global_rect().position.y, "Reward list stays above warning")
			check(view.warning.get_global_rect().end.y <= view.return_button.get_global_rect().position.y, "Warning stays above actions")
			check(not view.return_button.get_global_rect().intersects(view.continue_button.get_global_rect()), "Actions do not overlap")
			check(view.return_button.size.y >= 44 and view.continue_button.size.y >= 44, "Actions retain touch target height")
			for line in view._reward_rows:
				check(line.get_child(0).texture != null, "Reward icon exists")
				check(line.get_child(1).get_global_rect().end.x <= line.get_child(2).get_global_rect().position.x, "Reward title and count stay separate")
			if count == 12: check(view.reward_list.size.y > view.reward_scroll.size.y, "Overflow rewards remain scrollable")
			if DisplayServer.get_name() != "headless" and count == 3:
				await RenderingServer.frame_post_draw
				canvas.get_texture().get_image().save_png("/private/tmp/unclaimed-prompt-%dx%d.png" % [dimensions.x, dimensions.y])
		check(hud.shade.visible and not hud.message_label.visible and not hud.page.backdrop.visible, "Prompt has shade without menu artwork or toast")
		view.return_button.pressed.emit()
		view.continue_button.pressed.emit()
		check(commands.back() == "close_page" and commands.size() == (1 if count == 1 else 2 if count == 2 else 3 if count == 3 else 4), "Return action emits once despite repeated input")
	hud.show_page("确认离开", rows, "unclaimed")
	var view = hud.page.unclaimed_view
	var previous = commands.size()
	view.continue_button.pressed.emit()
	view.continue_button.pressed.emit()
	check(commands.size() == previous + 1 and commands.back() == "leave_unclaimed", "Continue action emits exactly once")
	hud.show_page("普通菜单", [])
	await process_frame
	check(hud.page.unclaimed_view == null and hud.page.stack.get_child(0).visible, "Normal menu restores its heading and releases prompt")
	hud.close_page()
	check(not hud.modal_open and not hud.shade.visible and hud.message_label.visible, "Closing restores the HUD")
	print("UNCLAIMED_PROMPT_TEST ", JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
