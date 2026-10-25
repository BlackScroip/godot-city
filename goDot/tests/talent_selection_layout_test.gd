extends SceneTree

var failures: Array[String] = []
var checks := 0
var commands: Array = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _run() -> void:
	var canvas = SubViewport.new()
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	canvas.size = Vector2i(1280, 720)
	root.add_child(canvas)
	var page = DungeonMenuPage.new()
	page.theme = DungeonStyle.theme()
	canvas.add_child(page)
	page.command.connect(func(kind, id, extra): commands.append([kind, id, extra]))
	var rows: Array = []
	for index in 3:
		rows.append({"title": ["烈阳之锋", "破空剑心", "焰之伤"][index], "icon": "sprite_charatalent_10%d" % (index + 1), "grade": "传奇", "level_text": "Lv.0 → Lv.1", "description": "解锁战技派生技能，命中敌人会获得剑心。\n\n等级1：战技伤害+20%，命中敌人后获得1层剑心。\n\n".repeat(4), "buttons": [{"text": "选择", "action": "choose_talent", "id": index + 101, "extra": "reward:test"}]})
	rows.append({"presentation_role": "refresh", "buttons": [{"text": "刷新", "action": "refresh_talent", "id": "reward:test", "extra": 0, "disabled": true}]})
	page.display("选择角色天赋", rows, "talent")
	var selection = page.special.get_child(0)
	for dimensions in [Vector2i(1280, 720), Vector2i(2460, 1080), Vector2i(844, 390)]:
		canvas.size = dimensions
		page.size = Vector2(dimensions)
		for frame in 8: await process_frame
		check(page.size.y <= dimensions.y + 1, "Page stays within viewport %s" % dimensions)
		for part in selection.parts:
			check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(part.panel.get_global_rect()), "Card stays inside viewport %s" % dimensions)
			check(part.scroll.size.y > 24, "Description remains scrollable %s" % dimensions)
			check(part.choose.get_global_rect().end.y <= dimensions.y, "Choice remains reachable %s" % dimensions)
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			canvas.get_texture().get_image().save_png("/private/tmp/talent-selection-%dx%d.png" % [dimensions.x, dimensions.y])
	check(selection.parts.size() == 3, "Three candidates")
	check(selection.refresh_button.disabled, "Unavailable refresh remains disabled")
	selection._select(2)
	check(selection.parts[2].panel.selected and not selection.parts[0].panel.selected, "Selection highlight follows preview")
	selection.parts[2].choose.pressed.emit()
	check(commands == [["choose_talent", 103, "reward:test"]], "Choice keeps exact candidate and reward identity")
	print("TALENT_SELECTION_LAYOUT_TEST ", JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
