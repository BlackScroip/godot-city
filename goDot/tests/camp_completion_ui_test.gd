extends SceneTree

var game: Node
var canvas: SubViewport
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("CAMP COMPLETION UI: " + message)

func settle() -> void:
	for frame in 20: await process_frame

func click_command(action: String) -> Dictionary:
	var view = game.hud.page.camp_service_view
	for index in view.rows.size():
		for entry in view.rows[index].get("buttons", []):
			if str(entry.get("action", "")) != action or bool(entry.get("disabled", false)): continue
			view.select_row(index)
			for button in view.action_buttons:
				var data: Dictionary = button.get_meta("command", {})
				if str(data.get("action", "")) == action:
					var result = data.duplicate(true)
					button.pressed.emit()
					return result
	return {}

func _run() -> void:
	canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	game = load("res://scripts/main.gd").new()
	game.save_store = DungeonSaveStore.new("/private/tmp/camp-completion-ui-%d.json" % Time.get_ticks_usec())
	canvas.add_child(game)
	game.set_process(false)
	game.world.set_process(false)
	game.world.set_physics_process(false)
	game.audio.stop()
	await settle()
	for building in game.catalog.rows("Buildings"): game.profile.data.buildings[str(building.id)] = int(building.max_level)
	for material in game.catalog.rows("MaterialData"): game.systems.grant_material(int(material.id), 10000)
	for amplifier in game.catalog.rows("RelationshipAmplifyData"): game.systems.grant_material(int(amplifier.id), 10)
	for token_id in game.systems.relationship_tokens.ids(): game.profile.data.stats["token:" + str(token_id)] = 3
	var token_id = int(game.systems.relationship_tokens.ids()[0])
	game.systems.equip_token(token_id)
	game.systems.unlock_amplifier_slot(token_id, 0)
	game.systems.receive_extra_challenges()
	game.systems.begin_run(817, game.selected_character, 100)
	game.profile.data.run.counters["run:elapsed"] = 145
	game.profile.data.run.counters["run:kills"] = 12
	game.profile.data.run.region = 2
	game.profile.data.run.completed_occurrences = ["fixture:1", "fixture:2"]
	game.profile.data.run.route = {"layers": [{"region": 1, "module_index": 0, "selected_id": 1, "complete": true}, {"region": 1, "module_index": 0, "selected_id": 2, "complete": true}, {"region": 2, "module_index": 1, "selected_id": 3, "complete": false}]}
	game.systems.history.capture(false, "retreat")
	game.systems.end_run(false)
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390), Vector2i(2460, 1080)]:
		canvas.size = dimensions
		await settle()
		for page_id in ["tokens", "amplifiers", "work", "meals", "partners", "decorations", "npcs", "archive", "history", "extra_challenges", "token_compose_preview"]:
			game.menus.open(page_id)
			await settle()
			var view = game.hud.page.camp_service_view
			check(is_instance_valid(view), page_id + " real menu specialized")
			if not is_instance_valid(view): continue
			check(view.rows.size() > 0, page_id + " model rows")
			check(view.body.get_global_rect().end.x <= dimensions.x + 1, page_id + " horizontal viewport " + str(dimensions))
			check(view.body.get_global_rect().end.y <= dimensions.y + 1, page_id + " vertical viewport " + str(dimensions))
			if page_id in ["tokens", "amplifiers"]:
				check(view.preset_buttons.size() == 3, page_id + " preset operation controls")
				check(view.token_state.sockets.size() == 3, page_id + " original three sockets per token")
			if page_id == "history":
				check(view.rows.size() > 1 and str(view.rows[1].description).contains("区域1：完成2个房间"), "history renders actual captured region completion")
				view.select_row(1)
				await settle()
			if not view.action_buttons.is_empty():
				var last: Button = view.action_buttons.back()
				view.detail_scroll.ensure_control_visible(last)
				await settle()
				check(view.detail_scroll.get_global_rect().intersects(last.get_global_rect()), page_id + " final detail action reachable " + str(dimensions))
				view.detail_scroll.scroll_vertical = 0
				await settle()
			if "--render-check" in OS.get_cmdline_user_args():
				await RenderingServer.frame_post_draw
				var image = canvas.get_texture().get_image()
				var colors: Dictionary = {}
				for y in range(0, dimensions.y, 20):
					for x in range(0, dimensions.x, 20): colors[image.get_pixel(x, y).to_rgba32()] = true
				check(colors.size() > 20, page_id + " nonblank real game pixels")
				image.save_png("res://reports/camp-completion-%s-%dx%d.png" % [page_id, dimensions.x, dimensions.y])
	game.menus.open("tokens", token_id)
	await settle()
	var essence_before: int = game.systems.material(108)
	var upgrade = click_command("op:upgrade_token")
	await settle()
	check(not upgrade.is_empty() and game.systems.stat("token:" + str(upgrade.get("id", 0))) == 4, "token upgrade UI changes actual level")
	check(game.systems.material(108) < essence_before, "token upgrade UI consumes quoted essence")
	game.menus.open("amplifiers", token_id)
	await settle()
	var equip = click_command("op:equip_amplifier")
	await settle()
	check(not equip.is_empty() and int(game.systems.relationship_tokens.slots(token_id)[0]) == int(equip.get("id", 0)), "amplifier UI equips selected token socket")
	game.menus.open("token_compose_preview", 60001)
	await settle()
	var owned_before: int = game.systems.material(60001)
	var gold_before: int = game.systems.material(101)
	var compose = click_command("op:compose_amplifier_batch")
	await settle()
	check(not compose.is_empty() and game.systems.material(60001) == owned_before - 5, "confirmed compose UI consumes five source amplifiers")
	check(game.systems.material(101) == gold_before - 500, "confirmed compose UI consumes source tier gold")
	if not compose.is_empty():
		game._action(str(compose.action), compose.id, compose.get("extra", 0))
		await settle()
		check(game.systems.material(60001) == owned_before - 5, "stale composition UI cannot spend twice")
	var entries: Array = game.systems.extra_challenges.entries()
	if not entries.is_empty():
		var quest: Dictionary = entries[0]
		game.profile.data.extra_challenges.active[str(int(quest.id))] = int(quest.required)
		game.menus.open("extra_challenges")
		await settle()
		var claim = click_command("op:claim_extra_challenge")
		await settle()
		check(not claim.is_empty() and not game.systems.extra_challenges.entry(int(claim.get("id", 0))).active, "bounty UI claims and removes completed entry")
	game._save(true)
	var saved: Dictionary = game.save_store.load_profile()
	if saved.is_empty():
		var raw = JSON.parse_string(FileAccess.get_file_as_string(game.save_store.path + ".tmp"))
		print("CAMP SAVE DIAGNOSTIC ", game.save_store.warning, " ", game.save_store.path, " tokens=", preload("res://scripts/domain/relationship_tokens.gd").validate_state(raw), " bounty=", preload("res://scripts/domain/extra_challenges.gd").validate_state(raw.extra_challenges), " history=", preload("res://scripts/domain/camp_history.gd").validate(raw))
	check(not saved.is_empty() and saved.get("camp_schema_version", 0) >= 2, "camp UI transactions persist valid migrated save")
	game.menus.open("history")
	await settle()
	var history_action = click_command("history_detail")
	await settle()
	check(not history_action.is_empty() and game.hud.page._layout == "outcome", "history detail opens existing settlement presentation")
	check(game.profile.data.run_history.size() == 1, "history inspection does not append or award another record")
	if "--render-check" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		canvas.get_texture().get_image().save_png("res://reports/camp-completion-history-detail-2460x1080.png")
	game.queue_free()
	await settle()
	var report = {"suite": "camp_completion_ui", "checks": checks, "failures": failures, "apk_runtime_comparison": "not executed", "rendered": "--render-check" in OS.get_cmdline_user_args()}
	var output = FileAccess.open("res://reports/camp-completion-ui-test.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t") + "\n")
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
