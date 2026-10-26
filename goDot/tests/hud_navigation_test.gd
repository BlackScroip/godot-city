extends SceneTree

var checks := 0
var failures: Array[String] = []
var hud: DungeonHud
var systems: DungeonSystems
var profile: DungeonProfile
var commands: Array = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func visible_navigation() -> Array:
	return hud.navigation.get_children().filter(func(key): return key.visible).map(func(key): return str(key.name))

func tick_resources(delta: float) -> void:
	for counter in hud.counter_buttons: counter.advance(delta)

func _run() -> void:
	create_timer(30).timeout.connect(func(): quit(2))
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	var catalog := DungeonCatalog.new()
	check(catalog.load_all(), "Packaged catalog loads")
	profile = DungeonProfile.new()
	systems = DungeonSystems.new(catalog, profile)
	hud = DungeonHud.new()
	root.add_child(hud)
	hud.action.connect(func(kind, id, extra): commands.append([kind, id, extra]))
	for counter in hud.counter_buttons: counter.set_process(false)
	hud.update_counters(systems, 0)
	systems.gameplay_event.connect(func(event: Dictionary):
		if event.get("type", "") in ["resource_gained", "resource_spent"]: hud.update_counters(systems, 0))
	hud.update_navigation(systems)
	check(hud.counter_buttons.all(func(key): return not key.visible), "Initial balances do not reveal resource rows")
	check(visible_navigation() == ["menu_store", "menu_character", "menu_settings"], "Camp before the first victory has the three native entries")
	var gold = hud.counter_buttons[0]
	var magic = hud.counter_buttons[1]
	systems.grant_material(101, 25)
	hud.update_counters(systems, 0)
	check(gold.visible and not magic.visible and hud.counter_values[0].text == "125", "Gold gain reveals only its own accurate balance")
	check(is_equal_approx(gold.value_label.scale.x, 1.8) and gold.value_label.modulate == Color(1.0, 0.9, 0.12), "Changed resource total starts with the native scale and highlight")
	tick_resources(0.25)
	check(is_equal_approx(gold.modulate.a, 0.5), "Resource row fades in over half a second")
	tick_resources(0.25)
	check(is_equal_approx(gold.modulate.a, 1.0), "Resource fade reaches full alpha")
	systems.grant_material(101, 10)
	hud.update_counters(systems, 0)
	check(gold.change_label.text == "+35", "Consecutive gains aggregate their displayed delta")
	tick_resources(2.5)
	check(is_equal_approx(gold.change_label.modulate.a, 0.75), "Delta holds for two seconds then fades for two seconds")
	check(gold.value_label.scale == Vector2.ONE and gold.value_label.modulate == Color.WHITE, "Resource total settles to its normal size and color")
	check(systems.spend({"101": 5}), "Gold spending succeeds")
	hud.update_counters(systems, 0)
	check(gold.visible and gold.change_label.text == "-5" and hud.counter_values[0].text == "130", "Spending also reveals the row and resets the sign of its delta")
	tick_resources(4.99)
	hud.update_counters(systems, 0)
	check(gold.visible, "Unchanged refreshes do not hide a pending row early")
	tick_resources(0.02)
	check(not gold.visible, "Resource row deactivates after five seconds without extending on polling")
	hud.show_page("Settings", [])
	hud.close_page()
	check(not gold.visible, "Closing a modal cannot resurrect an expired resource row")
	check(systems.spend({"101": 5}), "Same-frame resource expense succeeds")
	systems.grant_material(101, 5)
	check(gold.visible and hud.counter_values[0].text == "130", "An expense and refund within one frame still reveal resource feedback")
	tick_resources(6)
	systems.grant_material(101, 1)
	check(gold.visible and gold.change_label.text == "+1", "A frame longer than the hide timer clears the previous delta before the next gain")
	systems.add_search_points(1)
	hud.update_counters(systems, 0)
	check(hud.counter_values[3].text == "1/3" and not hud.counter_buttons[3].visible, "Search updates its string without inventing a numeric auto-reveal absent from the retained source path")
	profile.data.stats["difficulty:win:0"] = 1
	hud.update_navigation(systems)
	check(hud.navigation_buttons.menu_adventure.visible, "A legacy per-difficulty victory also enables native completed-run entries")
	profile.data.stats.wins = 1
	hud.update_navigation(systems)
	check(visible_navigation() == ["menu_adventure", "menu_comment", "menu_cloud", "menu_store", "menu_character", "menu_settings"], "First victory unlocks ordered quick-start, review and cloud prompts")
	profile.data.stats["ui:read:Btn_QuickStart"] = 0
	profile.data.stats["ui:read:Btn_GoComment"] = 0
	profile.data.stats["ui:read:Btn_CloudSave"] = 0
	hud.update_navigation(systems)
	check(visible_navigation() == ["menu_adventure", "menu_store", "menu_character", "menu_settings"], "Existing native read keys hide review/cloud even when their stored value is zero")
	check(not hud._navigation_badges.menu_adventure.visible, "Acknowledged quick start retains the entry without a red dot")
	profile.data.guide_index = 9
	hud.update_navigation(systems)
	check(visible_navigation() == ["menu_character", "menu_settings"], "Guide progress gates optional menu entries")
	profile.data.dialogue_state = {"npc_id": 1}
	hud.update_navigation(systems)
	check(visible_navigation().is_empty(), "Dialogue suppresses the remaining player and option entries")
	profile.data.guide_index = 10
	hud.update_navigation(systems)
	check(visible_navigation().is_empty(), "Dialogue also suppresses unlocked quick start, review, cloud and store entries")
	profile.data.dialogue_state = {}
	profile.data.guide_index = 10
	profile.data.run.active = true
	hud.set_adventure_mode(true)
	hud.update_navigation(systems)
	check(visible_navigation() == ["menu_difficulty", "menu_character", "menu_settings"], "Adventure replaces camp-only entries with difficulty")
	profile.data.purchased_meals = {str(catalog.rows("CatMealData")[0].Id): 1}
	hud.update_navigation(systems)
	check(visible_navigation() == ["menu_meal_buffs", "menu_difficulty", "menu_character", "menu_settings"], "Only a purchased meal exposes the active meal-buff entry")
	hud.navigation_buttons.menu_difficulty.pressed.emit()
	hud.navigation_buttons.menu_meal_buffs.pressed.emit()
	check(commands.slice(-2) == [["page:difficulty", 0, 0], ["page:meal_buffs", 0, 0]], "Native menu entries dispatch separate working page commands")
	for dimensions in [Vector2i(640, 360), Vector2i(844, 390), Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(2460, 1080), Vector2i(1200, 900)]:
		profile.data.run.active = true
		hud.set_adventure_mode(true)
		hud.update_navigation(systems)
		root.size = dimensions
		await process_frame
		await process_frame
		hud._layout()
		hud.primary.text = "精灵祭坛"
		hud.primary.show()
		var scale_factor := minf(1.0, minf(dimensions.x / 1280.0, dimensions.y / 720.0))
		var anchor := hud.skill_cluster.position
		for insets in [Vector2.ZERO, Vector2(44, 21), Vector2(88, 42)]:
			hud.skill_cluster.position = anchor - insets
			hud._layout_interaction(scale_factor)
			var command_bounds := hud.primary.get_global_rect()
			check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(command_bounds), "Interaction stays within viewport %s %s" % [dimensions, insets])
			for key in hud.skill_buttons + [hud.attack_mode_button]:
				var padding: float = key.hit_padding * key.get_global_transform_with_canvas().get_scale().x
				check(not command_bounds.intersects(key.get_global_rect().grow(padding)), "Interaction avoids every skill and auto-switch hit target %s %s" % [dimensions, insets])
			check(command_bounds.end.y < hud.attack_mode_button.get_global_rect().position.y and command_bounds.get_center().x < hud.attack_mode_button.get_global_rect().get_center().x, "Interaction sits above and left of attack switch %s %s" % [dimensions, insets])
		for key in hud.navigation.get_children():
			if key.visible: check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(key.get_global_rect()), "Visible navigation fits %s %s" % [dimensions, key.name])
		profile.data.run.active = false
		profile.data.stats.erase("ui:read:Btn_GoComment")
		profile.data.stats.erase("ui:read:Btn_CloudSave")
		hud.set_adventure_mode(false)
		hud.update_navigation(systems)
		hud._layout()
		await process_frame
		for key in hud.navigation.get_children():
			if key.visible: check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(key.get_global_rect()), "Camp navigation fits %s %s" % [dimensions, key.name])
	var report := {"checks": checks, "passed": failures.is_empty(), "failures": failures}
	FileAccess.open("res://reports/hud-navigation-tests.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("HUD_NAVIGATION ", JSON.stringify(report))
	hud.free()
	quit(0 if failures.is_empty() else 1)
