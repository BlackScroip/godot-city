extends SceneTree

var game: Node
var canvas: SubViewport
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("CAMP TOKEN: " + message)

func settle() -> void:
	for frame in 12: await process_frame

func _run() -> void:
	DungeonLocale.set_locale("zh_CN", false)
	canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	game = load("res://scripts/main.gd").new()
	game.save_store = DungeonSaveStore.new("/private/tmp/camp-token-reference-%d.json" % Time.get_ticks_usec())
	canvas.add_child(game)
	game.set_process(false)
	game.world.set_process(false)
	game.world.set_physics_process(false)
	game.audio.stop()
	game.profile.data.buildings["2"] = 1
	game.profile.data.character_levels["1"] = 4
	game.systems.refresh_tokens()
	game.systems.grant_material(101, 10000)
	game.systems.grant_material(108, 10000)
	game.systems.set_record("token:slots", 3)
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390), Vector2i(2460, 1080)]:
		canvas.size = dimensions
		game.menus.open("tokens", 50011)
		await settle()
		var view = game.hud.page.camp_service_view
		check(view.choice_buttons.size() == game.systems.relationship_tokens.ids().size(), "every source token has a tile")
		check(view.equipped_buttons.size() == game.systems.token_slots(), "equipped strip uses actual capacity")
		check(int(view.rows[view.selected].token_id) == 50011, "requested token is selected")
		check(view.collection_scroll.size.y >= 140, "compact collection remains usable " + str(dimensions))
		for button in view.choice_buttons:
			check(button.icon != null, "token tile has artwork " + str(button.get_meta("row_id")))
			var source: Dictionary = view.rows[int(button.get_meta("row_index"))]
			if bool(source.get("locked", false)): check(button.get_theme_color("icon_normal_color") == Color.BLACK, "locked token uses source silhouette")
		for button in view.action_buttons:
			view.detail_scroll.ensure_control_visible(button)
			await settle()
			check(view.detail_scroll.get_global_rect().intersects(button.get_global_rect()), "token action scrolls into view")
		view.detail_scroll.scroll_vertical = 0
		await settle()
		if "--render-check" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			var frame = canvas.get_texture().get_image()
			frame.save_png("res://reports/camp-token-reference-%dx%d.png" % [dimensions.x, dimensions.y])
	game._action("op:equip_token", 50011, 0)
	await settle()
	check(game.systems.relationship_tokens.equipped().has(50011), "equip action updates character loadout")
	var view = game.hud.page.camp_service_view
	check(int(view.equipped_buttons[0].get_meta("token_id")) == 50011, "equipped strip refreshes after action")
	check(view.equipped_buttons[0].icon == DungeonStyle.texture(game.systems.token_status(50011).icon), "equipped strip uses actual token artwork")
	game.menus.open("characters", 1)
	game._action("page:awakening", 1, 0)
	await settle()
	check(is_instance_valid(game.hud.page.awakening_view) and game.hud.page.special == null, "awakening entry opens independent implemented page")
	game.hud.page.awakening_view.back_requested.emit()
	check(game.menus.current_page == "characters" and game.hud.modal_open, "awakening returns to source character")
	game._save(true)
	var saved = game.save_store.load_profile()
	check(saved.get("char_equipped_tokens", {}).get("1", []).has(50011), "token UI loadout persists")
	game.queue_free()
	await settle()
	var report = {"suite": "camp_token_reference", "checks": checks, "failures": failures, "rendered": "--render-check" in OS.get_cmdline_user_args()}
	var output = FileAccess.open("res://reports/camp-token-reference-test.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t"))
	print(JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
