extends SceneTree

var failures: Array[String] = []
var checks = 0
var commands: Array = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _run() -> void:
	var catalog = DungeonCatalog.new()
	check(catalog.load_all(), "source catalogs load")
	var profile = DungeonProfile.new()
	var systems = DungeonSystems.new(catalog, profile)
	systems.grant_material(101, 10000)
	systems.grant_material(10101, 20)
	systems.grant_material(10102, 20)
	systems.begin_run(100, 1, 100)
	systems.end_run(false)
	check(systems.upgrade_building(2).success, "guild fixture unlocked through real construction")
	var viewport = SubViewport.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.size = Vector2i(1600, 900)
	root.add_child(viewport)
	var background = ColorRect.new()
	background.color = Color("ece8db")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(background)
	var heading = DungeonStyle.label("委托栏", 30)
	heading.theme = DungeonStyle.theme()
	heading.add_theme_color_override("font_color", Color("485e6e"))
	heading.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	heading.position = Vector2(24, 14)
	viewport.add_child(heading)
	var board = DungeonCommissionBoard.new()
	board.theme = DungeonStyle.theme()
	viewport.add_child(board)
	board.command.connect(func(kind, id, extra): commands.append([kind, id, extra]))
	board.configure(null, [], {"systems": systems, "catalog": catalog, "group_id": 100})
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390), Vector2i(2460, 1080)]:
		viewport.size = dimensions
		board.position = Vector2(20, 62)
		board.size = Vector2(dimensions) - Vector2(40, 82)
		for frame in 8: await process_frame
		check(board.group_buttons.size() == 62, "commission sidebar contains all original groups %s" % dimensions)
		check(board.task_scroll.size.x > 300 and board.task_scroll.size.y > 150, "task list remains usable %s" % dimensions)
		check(board.get_global_rect().encloses(board.footer.get_global_rect()), "commission footer stays in view %s" % dimensions)
		check(board.get_global_rect().encloses(board.footer_button.get_global_rect()), "group claim remains reachable %s" % dimensions)
		check(board.sidebar.size.y <= board.size.y + 1, "group rail scrolls within view %s" % dimensions)
		await _capture(viewport, "commission", dimensions)
	check(board.task_buttons.has(10001) and not board.task_buttons[10001].disabled, "completed real resource task enables claim")
	board.task_buttons[10001].pressed.emit()
	check(commands.back() == ["op:claim_task", 10001, 0], "task claim emits exact source identity")
	check(systems.claim_task(10001).success, "claim command reaches real domain reward")
	board.refresh()
	await process_frame
	check(board.task_buttons[10001].disabled and board.task_buttons[10001].text == "已领取", "claimed task is disabled after refresh")
	board.select_group(200)
	check(board.selected_group == 200 and not board.task_buttons.is_empty(), "group selection loads corresponding tasks")
	board.queue_free()
	await process_frame
	heading.text = "公会支援表"
	var guild = DungeonGuildPage.new()
	guild.theme = DungeonStyle.theme()
	viewport.add_child(guild)
	guild.command.connect(func(kind, id, extra): commands.append([kind, id, extra]))
	guild.configure(null, [], {"systems": systems, "catalog": catalog})
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390), Vector2i(2460, 1080)]:
		viewport.size = dimensions
		guild.position = Vector2(20, 62)
		guild.size = Vector2(dimensions) - Vector2(40, 82)
		for frame in 8: await process_frame
		check(guild.category_buttons.size() == 3 and guild.node_buttons.size() == 21, "guild source categories and first branch nodes %s" % dimensions)
		check(guild.graph_scroll.size.x > 250 and guild.detail_scroll.size.x > 150, "guild graph and detail keep usable widths %s" % dimensions)
		check(guild.get_global_rect().encloses(guild.detail_scroll.get_global_rect()), "guild detail viewport remains within page %s" % dimensions)
		check(guild.graph.custom_minimum_size.x >= 1200 and (dimensions.x > 2000 or guild.graph.custom_minimum_size.x > guild.graph_scroll.size.x), "source eleven-column tree keeps fixed tracks and scrolls when needed %s" % dimensions)
		check(not guild.graph.branches.is_empty(), "prerequisite connectors generated %s" % dimensions)
		await _capture(viewport, "guild", dimensions)
	check(guild.selected_talent == 101 and not guild.upgrade_button.disabled, "first talent is fundable using real source materials")
	guild.select_talent(102)
	check(guild.upgrade_button.disabled, "child talent remains blocked until its parent is learned")
	guild.select_talent(101)
	guild.upgrade_button.pressed.emit()
	check(commands.back() == ["op:upgrade_global_talent", 101, 0], "guild action emits selected talent identity")
	check(systems.upgrade_global_talent(101).success, "real guild transaction learns parent talent")
	guild.refresh()
	guild.select_talent(102)
	check(not guild.upgrade_button.disabled, "parent unlock enables actual child upgrade")
	guild.select_category(3)
	check(guild.node_buttons.size() == 19 and guild.selected_talent == 301, "third source category has its original nineteen nodes")
	viewport.queue_free()
	await process_frame
	var result = {"checks": checks, "failures": failures, "passed": failures.is_empty()}
	print("CAMP_REFERENCE_PAGES_TEST ", JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)

func _capture(viewport: SubViewport, name: String, dimensions: Vector2i) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var picture = viewport.get_texture().get_image()
	check(not picture.is_empty(), "rendered %s screenshot is nonempty" % name)
	picture.save_png("/private/tmp/camp-%s-%dx%d.png" % [name, dimensions.x, dimensions.y])
