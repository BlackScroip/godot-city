extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _run() -> void:
	var canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	root.add_child(canvas)
	var hud = DungeonHud.new()
	canvas.add_child(hud)
	await process_frame
	var commands: Array[String] = []
	hud.action.connect(func(kind, _id, _extra): commands.append(kind))
	var profile = DungeonProfile.new()
	var systems = DungeonSystems.new(DungeonCatalog.new(), profile)
	hud.update_navigation(systems)
	check(hud.navigation.get_children().filter(func(key): return key.visible).size() == 3, "Camp initially exposes store, character and settings")
	hud.set_adventure_mode(true)
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390)]:
		canvas.size = dimensions
		await process_frame
		hud._layout()
		await process_frame
		var visible = hud.navigation.get_children().filter(func(key): return key.visible)
		check(visible.size() == 3, "Level has exactly three navigation commands")
		check(visible.map(func(key): return key.tooltip_text) == ["难度", "角色", "设置"], "Level navigation order matches difficulty, character, settings")
		check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(hud.navigation.get_global_rect()), "Level navigation fits viewport " + str(dimensions))
		for key in visible:
			check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(key.get_global_rect()), "Navigation button fits viewport")
			key.pressed.emit()
		check(commands.slice(-3) == ["page:difficulty", "page:characters", "settings"], "Each level button dispatches its existing page")
	hud.show_page("设置", [])
	check(not hud.navigation.visible, "Open page hides navigation")
	hud.close_page()
	check(hud.navigation.get_children().filter(func(key): return key.visible).size() == 3, "Closing page preserves level navigation")
	hud.set_adventure_mode(false)
	await process_frame
	check(hud.navigation.get_children().filter(func(key): return key.visible).size() == 3, "Returning without a victory preserves the initial camp commands")
	profile.data.stats["wins"] = 1
	hud.update_navigation(systems)
	await process_frame
	check(hud.navigation.get_children().filter(func(key): return key.visible).size() == 6, "First victory unlocks quick start, comment and cloud entries")
	hud.adventure_button.pressed.emit()
	check(commands.back() == "quick_start" and hud.adventure_caption.text == "开始冒险", "Unlocked camp entry dispatches quick start with its source caption")
	systems.decorations = null
	canvas.queue_free()
	await process_frame
	print("LEVEL NAVIGATION ", "PASS" if failures.is_empty() else "FAIL ", failures)
	quit(0 if failures.is_empty() else 1)
