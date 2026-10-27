extends SceneTree

var checks := 0
var failures: Array[String] = []
var canvas: SubViewport
var page: DungeonMenuPage
var commands: Array = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("CAMP SERVICES UI: " + message)

func settle() -> void:
	for frame in 8: await process_frame

func _run() -> void:
	canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	page = DungeonMenuPage.new()
	canvas.add_child(page)
	page.command.connect(func(kind, id, extra): commands.append([kind, id, extra]))
	var rows: Array = []
	for index in 36:
		rows.append({"title": "保温便当 %d" % index, "description": "攻击力提高 10%\n需要完成营地建设。\n升级材料：金币 ×500\n".repeat(3), "icon": "sprite_tokenicon_50011", "token_id": 50001 + index, "buttons": [{"text": "强化", "action": "op:upgrade_token", "id": 50001 + index, "extra": 0, "disabled": false}], "slot_rows": [{"title": "攻击增幅", "icon": "Sprite_Gem_RedLevel4", "buttons": [{"text": "选择", "action": "token_socket_select", "id": 50001, "extra": 0}]}, {"title": "未解锁", "icon": "锁", "buttons": [{"text": "解锁", "action": "op:unlock_amplifier_slot", "id": 50001, "extra": 1}]}, {"title": "未解锁", "icon": "锁", "buttons": []}]})
	var token_state = {"character_id": 1, "character_name": "骑士", "slots": 3, "equipped": [50001], "selected_token_id": 50001, "presets": [{"name": "预设1", "buttons": [{"text": "保存1", "action": "op:save_token_preset", "id": 0}]}], "summary": "攻击力 +10%\n生命值 +100"}
	token_state.presets.clear()
	for index in 15:
		token_state.presets.append({"name": "预设%d" % (index + 1), "index": index, "buttons": [{"text": "保存", "action": "op:save_token_preset", "id": index}, {"text": "应用", "action": "op:load_token_preset", "id": index}, {"text": "删除", "action": "op:delete_token_preset", "id": index}]})
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390), Vector2i(2460, 1080)]:
		canvas.size = dimensions
		page.size = dimensions
		for page_id in ["tokens", "work", "meals", "partners", "decorations", "npcs", "archive", "history", "extra_challenges"]:
			page.display("据点", rows, "tokens" if page_id == "tokens" else "camp_service", {"page": page_id, "camp": true, "token_state": token_state, "resources": [["material:101", "100000"]]})
			await settle()
			var view = page.camp_service_view
			check(is_instance_valid(view), page_id + " specialized view")
			check(view.choice_buttons.size() == rows.size(), page_id + " all records reachable")
			check(view.body.get_global_rect().end.x <= dimensions.x + 1, page_id + " body fits horizontal viewport")
			check(view.body.get_global_rect().end.y <= dimensions.y + 1, page_id + " body fits vertical viewport %s actual %s" % [dimensions, view.body.get_global_rect()])
			check(view.detail_scroll.size.x > 150, page_id + " usable details width")
			if page_id == "tokens": check(view.preset_buttons.size() == 3, "fifteen presets show only selected preset operations")
			view.choice_buttons[5].pressed.emit()
			await settle()
			check(view.selected == 5, page_id + " collection selects requested item")
			view.action_buttons[0].pressed.emit()
			check(commands.back()[1] == 50006, page_id + " command retains selected item identity")
			view.collection_scroll.ensure_control_visible(view.choice_buttons.back())
			await settle()
			check(view.collection_scroll.scroll_vertical > 0 or dimensions.y == 1080, page_id + " collection scrolls to final entry")
			if page_id != "tokens":
				view.search.text = "not present"
				view.search.text_changed.emit(view.search.text)
				check(view.choice_buttons.is_empty(), page_id + " search empty state")
				view.search.text = ""
				view.search.text_changed.emit("")
			await settle()
			if "--render-check" in OS.get_cmdline_user_args():
				await RenderingServer.frame_post_draw
				var image = canvas.get_texture().get_image()
				var colors: Dictionary = {}
				for y in range(0, dimensions.y, 15):
					for x in range(0, dimensions.x, 15): colors[image.get_pixel(x, y).to_rgba32()] = true
				check(colors.size() > 20, page_id + " nonblank source imagery")
				image.save_png("res://reports/camp-services-%s-%dx%d.png" % [page_id, dimensions.x, dimensions.y])
	page.queue_free()
	await settle()
	print(JSON.stringify({"suite": "camp_services_presentation", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
