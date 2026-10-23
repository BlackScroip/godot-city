extends SceneTree

var failures: Array[String] = []
var checks := 0
var game: Node
var canvas: SubViewport

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _run() -> void:
	create_timer(55).timeout.connect(func(): quit(2))
	canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	game = load("res://scenes/main.tscn").instantiate()
	game.save_store = DungeonSaveStore.new("res://reports/loot-test-profile-%d.json" % Time.get_ticks_usec())
	canvas.add_child(game)
	await process_frame
	game.set_process(false)
	game.world.set_physics_process(false)
	game.hud.close_page()
	game.systems.begin_run(51943, game.selected_character, 100, 0)
	var drops = game.world.ground_loot
	var point = game.world.player.position
	var old_gold = game.systems.material(101)
	drops.spawn(101, point + Vector3(8, 0, 0), 12, true)
	check(not drops.pickup(point, game.systems).success, "Distant loot cannot be collected")
	check(game.systems.material(101) == old_gold, "Spawning does not grant money")
	var saved = JSON.parse_string(JSON.stringify(drops.snapshot()))
	drops.restore(saved)
	check(drops.entries.size() == 1, "JSON round trip restores ground loot")
	for frame in 120: drops.advance_collection(1.0 / 60.0, point, game.systems)
	check(drops.entries.is_empty(), "Money is automatically attracted and collected")
	check(game.systems.material(101) == old_gold + 12, "Collect grants exact amount")
	check(not drops.pickup(point + Vector3(8, 0, 0), game.systems).success, "Cannot collect twice")
	drops.spawn(20103, point)
	check(drops.pickup(point, game.systems).success, "Nearby relic enters inventory")
	check(int(game.profile.data.run.inventory.get("20103", 0)) == 1, "Relic counted once")
	game.profile.data.run.inventory["20103"] = 20
	drops.spawn(20103, point)
	check(not drops.pickup(point, game.systems).success and drops.entries.size() == 1, "At stack cap item remains on ground")
	game.profile.data.run.inventory["20103"] = 1
	drops.clear()
	var outcomes: Dictionary = {}
	for index in 12:
		game._drop_treasure(point)
		for entry in drops.entries:
			check(entry.visual.texture != null, "Every drop has an image")
			if entry.material: outcomes["%d:%d" % [entry.id, entry.amount]] = true
			else: check(int(entry.id) == 13102, "Normal chest drops the APK configured refined talent scroll")
		drops.clear()
	check(outcomes.size() > 2, "Seeded treasure resource quantities vary")
	game._drop_treasure(point, "Luxury")
	check(drops.entries.any(func(entry): return int(entry.id) == 13102 and not entry.material), "Luxury chest guarantees the configured refined talent scroll")
	drops.clear()
	game._drop_treasure(point, "Curse")
	check(drops.entries.any(func(entry): return int(entry.id) == 13103 and not entry.material), "Curse chest guarantees a legendary talent scroll")
	drops.clear()
	game._drop_treasure(point, "Curse_Final")
	check(not drops.entries.any(func(entry): return not entry.material), "Final curse chest does not enter the normal talent scroll branch")
	drops.clear()
	game._environment_action("reward", {"type": "EEUT_AbilityItemTreasureBox", "marker_id": "test-chest", "position": point})
	var chest_count = drops.entries.size()
	game._environment_action("reward", {"type": "EEUT_AbilityItemTreasureBox", "marker_id": "test-chest", "position": point})
	check(drops.entries.size() == chest_count, "Same chest cannot produce loot twice")
	drops.clear()
	game.world.spawn_wave([{"enemy_id": 13001, "position": [point.x + 4, point.y, point.z]}], 0, 901)
	var enemy = game.world.actors.back()
	var gold_before_kill = game.systems.material(101)
	game.world._die(enemy)
	check(game.systems.material(101) == gold_before_kill, "Kill leaves money on ground instead of direct grant")
	var death_drops = drops.entries.size()
	check(death_drops > 0, "Boss death produces loot at death position")
	game.world._die(enemy)
	check(drops.entries.size() == death_drops, "Repeated death cannot duplicate loot")
	drops.clear()
	for row in game.catalog.rows("LootData"):
		check(DungeonStyle.texture("loot:" + str(int(row.id))) != null, "Every catalog relic resolves image")
	var choices = game.systems.create_loot_reward(30301, "altar:test", 3)
	check(choices.size() == 3, "Altar offers three distinct eligible spirits")
	drops.spawn_altar(point + Vector3(1, 0, 0), "altar:test")
	var altar_anchor: Node3D = drops.entries[0].effect_anchor
	check(drops.entries[0].has("effect_binding"), "Spirit altar binds original APK particle prefab")
	drops.restore(JSON.parse_string(JSON.stringify(drops.snapshot())))
	check(drops.entries[0].get("altar", "") == "altar:test", "Altar persists")
	check(altar_anchor.is_queued_for_deletion(), "Restoring altar releases old particle anchor")
	game._rewards()
	check(game.hud.page._layout == "altar", "Altar opens specialized layout")
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390)]:
		canvas.size = dimensions
		await capture("altar-%dx%d" % [dimensions.x, dimensions.y])
	game._action("choose_loot", choices[0], "altar:test")
	check(game.profile.data.run.rewards.is_empty(), "Choice consumes altar reward")
	check(drops.entries.is_empty(), "Choice removes altar marker")
	var environment_effects = game.world.environment_root.get_node_or_null("EnvironmentEffects")
	if environment_effects:
		check(environment_effects.bindings.filter(func(entry): return entry.address == "25040703_fx_other_spritesaltar").is_empty(), "Choice releases altar particle binding immediately")
	canvas.size = Vector2i(1600, 900)
	game.menus.open("inventory")
	await capture("inventory")
	game.hud.close_page()
	drops.spawn(20103, point + Vector3(1, 0, 0))
	drops.spawn(20260, point + Vector3(-1, 0, 0))
	game.world.camera.position = point + game.world._camera_offset
	game.world.camera.look_at(point)
	game.hud.update_state("", 64, 100, "", "", "")
	game.hud.update_counters(game.systems, 0)
	game.hud.update_combat(game.world.player.combat, false)
	game.hud.show_pickup(drops.nearest(point), game.systems, false)
	await capture("pickup")
	canvas.size = Vector2i(844, 390)
	await capture("pickup-mobile")
	print("LOOT_TEST ", JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func capture(label: String) -> void:
	for frame in 8: await process_frame
	var bounds = Rect2(Vector2.ZERO, Vector2(canvas.size))
	if game.hud.page.visible and game.hud.page._layout == "altar":
		for button in game.hud.page.find_children("*", "Button", true, false):
			if button.is_visible_in_tree(): check(bounds.encloses(button.get_global_rect()), "Altar command fits viewport: " + label)
	elif not game.hud.modal_open:
		check(bounds.encloses(game.hud.primary.get_global_rect()), "Pickup command fits viewport: " + label)
		check(bounds.encloses(game.hud.pickup_panel.get_global_rect()), "Pickup detail fits viewport: " + label)
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	canvas.get_texture().get_image().save_png("res://reports/loot-" + label + ".png")
