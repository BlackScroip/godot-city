extends SceneTree

var game: Node
var canvas: SubViewport
var failures: Array[String] = []
var checks := 0
var clock := 2000000000
var render_check := false

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("CAMP FLOW FAILURE: " + message)

func settle_layout() -> void:
	for i in 4: await process_frame

func snapshot(page: String, dimensions: Vector2i) -> void:
	canvas.size = dimensions
	game.hud._layout()
	if page == "world":
		game._close_page()
		game.hud.update_combat(game.world.player.combat, true)
	else:
		game.menus.open(page, 3 if page == "buildings" else 0)
	await settle_layout()
	check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(game.hud.page.get_global_rect()), "Page bounds fit %s at %s" % [page, dimensions])
	if page == "buildings":
		check(game.hud.page.building_view.nodes.size() == 21, "Seven facilities expose three construction stages each")
		check(game.hud.page.page_context.selected_id == 3, "Requested facility remains selected")
	if page == "world":
		check(game.hud.camp_button.visible, "Camp overview remains reachable")
		check(game.hud.counter_buttons[1].get_meta("resource_id") == 501, "Camp HUD shows adventure vouchers")
	if render_check:
		await RenderingServer.frame_post_draw
		var frame = canvas.get_texture().get_image()
		check(not frame.is_empty(), "Rendered pixels exist for " + page)
		frame.save_png("res://reports/camp-flow-%s-%dx%d.png" % [page, dimensions.x, dimensions.y])

func _run() -> void:
	render_check = "--render-check" in OS.get_cmdline_user_args()
	canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	game = load("res://scripts/main.gd").new()
	game.save_store = DungeonSaveStore.new("/private/tmp/camp-flow-%d.json" % Time.get_ticks_usec())
	canvas.add_child(game)
	game.set_process(false)
	game.world.set_physics_process(false)
	game.audio.stop()
	game.systems.utc_now = func(): return clock
	await settle_layout()
	game.hud.update_counters(game.systems, 0)
	game.menus.open("buildings", 3)
	check(game.hud.page._rows.size() == 7, "Architect placeholder is not a purchasable building")
	game._action("op:upgrade_building", 3, 0)
	check(game.systems.material(101) == 100 and game.systems.rank(game.profile.data.buildings, 3) == 0, "Insufficient building funds never mutate wallet")
	game.systems.grant_material(101, 200)
	game._action("op:upgrade_building", 3, 0)
	check(game.systems.material(101) == 0 and game.systems.rank(game.profile.data.buildings, 3) == 1, "Construction deducts exactly the quoted gold")
	check(not game.hud.modal_open and game.world.camp_camera.focus_remaining > 0, "Construction reveals and focuses the actual scene facility")
	var persisted = game.save_store.load_profile()
	check(int(persisted.get("buildings", {}).get("3", 0)) == 1, "Construction persists before returning to camp")
	game._action("op:upgrade_building", 3, 0)
	check(game.systems.rank(game.profile.data.buildings, 3) == 1, "Repeated unaffordable construction cannot upgrade")
	for page in ["camp", "resources", "buildings", "characters", "weapons", "talents", "partners", "work", "meals", "npcs", "awakening", "tokens", "amplifiers", "tasks", "achievements", "archive", "mall", "difficulty"]:
		game.menus.open(page)
		check(game.hud.modal_open and game.hud.page.displayed_row_count() > 0, "Camp system has an inspectable page: " + page)
	game.profile.data.buildings["6"] = 3
	game.profile.data.buildings["4"] = 3
	var partner = int(game.catalog.rows("MonsterPartnerData")[0].id)
	game.profile.data.partners[str(partner)] = 1
	var job := 0
	for row in game.catalog.rows("MonsterWorkData"):
		if row.type == "Normal" and game.systems.is_unlocked(int(row.unlock_data_id)):
			job = int(row.id)
			break
	check(job > 0, "A naturally unlocked normal dispatch exists")
	var state = game.systems.work_status(job)
	for key in state.price: game.systems.grant_material(int(key), int(state.price[key]))
	game.menus.open("dispatch", job)
	game._action("op:start_work", job, partner)
	check(game.menus.current_page == "work" and game.profile.data.work.size() == 1, "UI dispatch returns to running orders")
	clock += int(state.duration_seconds)
	game.menus.tick(1.1)
	check(game.systems.work_status(job).ready, "Persisted UTC dispatch completes without an open world")
	var enabled_claim := false
	for row in game.hud.page._rows:
		for button in row.buttons:
			if button.action == "op:collect_work" and int(button.id) == job: enabled_claim = not button.disabled
	check(enabled_claim, "Open dispatch page updates its claim button automatically")
	var before = game.systems.material(int(state.reward.id))
	game._action("op:collect_work", job, 0)
	game._action("op:collect_work", job, 0)
	check(game.systems.material(int(state.reward.id)) == before + int(state.reward.amount), "Repeated UI reward claim grants exactly once")
	game.profile.data.materials["501"] = 0
	game.systems.begin_run(7654321, 1, 100)
	game.profile.data.run.counters["run:total_depth"] = 5
	game.profile.data.run.counters["run:kills"] = 7
	game._finish_run(false, "test")
	var vouchers = int(game.profile.data.run.outcome.vouchers)
	game._action("result_next", 0, 0)
	game._action("result_next", 0, 0)
	check(game.systems.material(501) == vouchers, "Settlement claims adventure vouchers exactly once through UI")
	game._action("result_camp", 0, 0)
	game.world.set_physics_process(false)
	check(not game.profile.data.run.active and game.profile.data.run.get("outcome", {}).is_empty(), "Settlement returns to camp and releases progression")
	var upgrade = game.systems.character_upgrade_status(1)
	for key in upgrade.price: game.systems.grant_material(int(key), maxi(0, int(upgrade.price[key]) - game.systems.material(int(key))))
	var old_vouchers = game.systems.material(501)
	game._action("op:upgrade_character", 1, 0)
	check(game.systems.rank(game.profile.data.character_levels, 1) == 2 and game.systems.material(501) == old_vouchers - int(upgrade.price.get("501", 0)), "Adventure vouchers fund permanent character growth")
	game.hud.set_adventure_mode(false)
	game.hud.update_counters(game.systems, 0)
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390), Vector2i(2460, 1080)]:
		for page in ["world", "camp", "buildings", "resources", "work", "characters", "tasks", "talents"]:
			await snapshot(page, dimensions)
	var report = {"checks": checks, "failures": failures, "rendered": render_check}
	var file = FileAccess.open("res://reports/camp-flow-tests.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("Camp flow checks: %d; failures: %d" % [checks, failures.size()])
	game.queue_free()
	await process_frame
	canvas.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
