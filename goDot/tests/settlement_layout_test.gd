extends SceneTree

var checks := 0
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var context = {
		"title": "战斗失败", "stage": "summary", "victory": false, "elapsed": 237,
		"portrait": "sprite_artwork_square_jiannan", "button": "下一步", "action": "result_next",
		"effective_experience": 200, "vouchers": 2, "conversion_capacity": 200,
		"talents": [{"icon": "sprite_charatalent_101", "grade": 3, "talent": true, "count_text": "★★", "name": "焰之伤"}],
		"relics": [], "rewards": [],
		"statistics": [["击败数量", "57"], ["总伤害", "4.8万"], ["最大伤害", "1200"], ["获得魔力精华", "791"], ["获得矿石素材", "0"], ["获得金币", "238"]]}
	for id in [20102, 20103, 20104, 20105, 20106, 20107, 20138, 20401]:
		var info = DungeonItemArt.relic_info(id)
		context.relics.append({"icon": "loot:" + str(id), "grade": info.rarity, "count": 1, "name": info.name})
	for entry in [[101, 238], [501, 2], [40001, 1], [90001, 2]]:
		context.rewards.append({"icon": "sprite_materialicon_" + str(entry[0]), "count": entry[1]})
	for view in ["summary", "rewards", "empty", "overflow"]:
		var data = context.duplicate(true)
		data.stage = "rewards" if view == "rewards" else "summary"
		if view == "rewards": data.button = "返回营地"; data.action = "result_camp"
		if view == "empty": data.talents = []; data.relics = []
		if view == "overflow":
			for i in 60:
				data.talents.append(context.talents[0])
				data.relics.append(context.relics[0])
		var page = preload("res://scripts/presentation/run_outcome.gd").new()
		page.theme = DungeonStyle.theme()
		canvas.add_child(page)
		page.configure(data)
		for dimensions in [Vector2i(2460, 1080), Vector2i(1600, 900), Vector2i(844, 390)]:
			canvas.size = dimensions
			page.size = Vector2(dimensions)
			for frame in 8: await process_frame
			var bounds = Rect2(Vector2.ZERO, Vector2(dimensions))
			for control in [page.header, page.confirm, page.rewards] if view == "rewards" else [page.header, page.talents, page.relics, page.statistics, page.confirm]:
				check(bounds.encloses(control.get_global_rect()), "%s %s fits %s" % [view, control.get_class(), dimensions])
			if view != "rewards":
				check(not page.relics.get_global_rect().intersects(page.confirm.get_global_rect()), "Relics and confirmation remain separate")
				check(page.statistics.get_global_rect().end.y <= page.confirm.get_global_rect().position.y, "Statistics end above confirmation")
			if view == "overflow":
				check(page.relics.get_child(1).get_v_scroll_bar().max_value > page.relics.get_child(1).size.y, "Long collections can scroll")
			if DisplayServer.get_name() != "headless" and view in ["summary", "rewards"]:
				await RenderingServer.frame_post_draw
				var picture = canvas.get_texture().get_image()
				var content_pixels := 0
				for y in range(0, dimensions.y, 20):
					for x in range(0, dimensions.x, 20):
						if picture.get_pixel(x, y) != picture.get_pixel(0, 0): content_pixels += 1
				check(not picture.is_empty() and content_pixels > 25, "Settlement has rendered content")
				picture.save_png("/private/tmp/settlement-%s-%dx%d.png" % [view, dimensions.x, dimensions.y])
		var commands: Array = []
		page.command.connect(func(kind, _id, _extra): commands.append(kind))
		page.confirm.pressed.emit()
		check(page.confirm.disabled and commands == [data.action], "Confirmation locks and emits its stage action")
		page.queue_free()
		await process_frame
	check(DungeonStyle.texture("sprite_artwork_square_shuangdao") != null, "Character portrait exists")
	print("SETTLEMENT_LAYOUT ", JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
