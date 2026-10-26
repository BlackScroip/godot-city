extends SceneTree

var failures: Array[String] = []
var checks := 0
var commands: Array = []

class PageRecorder extends DungeonHud:
	var captured_rows: Array = []
	var captured_layout := ""
	func show_page(_title: String, rows: Array, layout := "list", _context: Dictionary = {}) -> void:
		captured_rows = rows
		captured_layout = layout

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
		rows.append({"title": ["烈阳之锋", "破空剑心", "焰之伤"][index], "icon": "sprite_charatalent_10%d" % (index + 1), "rarity": 5, "grade": "传奇", "level_text": "Lv.0 → Lv.1", "description": "解锁战技派生技能，命中敌人会获得剑心。\n\n等级1：战技伤害+20%，命中敌人后获得1层剑心。\n\n".repeat(4), "buttons": [{"text": "选择", "action": "choose_talent", "id": index + 101, "extra": "reward:test"}]})
	rows.append({"presentation_role": "refresh", "buttons": [{"text": "刷新", "action": "refresh_talent", "id": "reward:test", "extra": 0, "disabled": true}]})
	page.display("选择角色天赋", rows, "talent")
	var selection = page.special.get_child(0)
	await _verify_layout(canvas, page, selection, "talent")
	check(selection.parts.size() == 3, "Three candidates")
	check(selection.refresh_button.disabled, "Unavailable refresh remains disabled")
	selection._select(2)
	check(selection.parts[2].panel.selected and not selection.parts[0].panel.selected, "Selection highlight follows preview")
	selection.parts[2].choose.pressed.emit()
	check(commands == [["choose_talent", 103, "reward:test"]], "Choice keeps exact candidate and reward identity")
	commands.clear()
	var support: Array = []
	var catalog = DungeonCatalog.new()
	check(catalog.load_all(), "Support uses real item data")
	for id in [11005, 11101, 16101]:
		var ability = catalog.find("AbilityItems", id)
		support.append({"title": ability.Name, "description": DungeonCatalog.clean(ability.Description), "icon": "loot:" + str(id), "rarity": int(ability.Rare), "buttons": [{"text": "选择", "action": "choose_loot", "id": id, "extra": "support:test"}]})
	support.append({"presentation_role": "refresh", "buttons": [{"text": "刷新", "action": "refresh_loot", "id": "support:test", "extra": 0}]})
	page.display("选择冒险家支援道具", support, "support")
	selection = page.special.get_child(0)
	await _verify_layout(canvas, page, selection, "support")
	check(selection.parts[0].panel.fill_top != selection.parts[1].panel.fill_top and selection.parts[1].panel.fill_top != selection.parts[2].panel.fill_top, "Support rarities have distinct blue, green and gray cards")
	check(not selection.parts[0].tag.visible, "Items do not show an empty talent level")
	selection.parts[0].choose.pressed.emit()
	selection.refresh_button.pressed.emit()
	selection.character_button.pressed.emit()
	check(commands == [["choose_loot", 11005, "support:test"], ["refresh_loot", "support:test", 0], ["page:inventory", 0, 0]], "Support choice, refresh and character retain their commands")
	page.display("普通菜单", [], "list")
	check(page.stack.get_child(0).visible and page.stack.get_child(1).visible, "Leaving selection restores the normal heading")
	_verify_entry_points(catalog)
	print("TALENT_SELECTION_LAYOUT_TEST ", JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)

func _verify_entry_points(catalog: DungeonCatalog) -> void:
	var game = load("res://scripts/main.gd").new()
	game.catalog = catalog
	game.profile = DungeonProfile.new()
	game.systems = DungeonSystems.new(catalog, game.profile)
	game.hud = PageRecorder.new()
	game.menus = DungeonMenus.new(game)
	game.systems.begin_run(817024, 1, 100)
	check(game.systems.prepare_npc_support(101001).success, "Real NPC support prepares")
	game._show_npc_support(101001)
	check(game.hud.captured_layout == "support" and game.hud.captured_rows.size() == 3, "NPC support enters the card layout")
	for row in game.hud.captured_rows:
		check(not row.description.is_empty() and int(row.rarity) > 0, "NPC cards include the real effect and rarity")
		check(row.buttons[0].action == "op:claim_npc_support" and row.buttons[0].id == 101001, "NPC cards retain their function identity")
	game.profile.data.run.rewards.append({"key": "support:test", "choices": [11005, 11101, 16101]})
	game._rewards("support:test")
	check(game.hud.captured_layout == "support", "Run rewards enter the card layout")
	check(game.hud.captured_rows.slice(0, 3).map(func(row): return int(row.rarity)) == [3, 2, 1], "Run reward rarities come from item data")
	game.systems.queue_character_talent_reward("High")
	game._talent_rewards()
	check(game.hud.captured_layout == "talent" and game.hud.captured_rows[0].rarity == 5, "Legendary talents enter the gold card layout")
	game.hud.free()
	game.ads.free()
	game.resource_audio.free()
	game.free()

func _verify_layout(canvas: SubViewport, page: DungeonMenuPage, selection: Control, mode: String) -> void:
	for dimensions in [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(2460, 1080), Vector2i(844, 390)]:
		canvas.size = dimensions
		page.size = Vector2(dimensions)
		for frame in 10: await process_frame
		var viewport = Rect2(Vector2.ZERO, Vector2(dimensions))
		check(page.size.y <= dimensions.y + 1, "Page stays within viewport %s %s" % [mode, dimensions])
		check(viewport.encloses(selection.toolbar.get_global_rect()), "Toolbar stays inside viewport %s %s" % [mode, dimensions])
		check(not selection.heading.get_global_rect().intersects(selection.toolbar.get_global_rect()), "Heading does not overlap toolbar %s %s" % [mode, dimensions])
		for part in selection.parts:
			check(viewport.encloses(part.panel.get_global_rect()), "Card stays inside viewport %s %s" % [mode, dimensions])
			check(part.scroll.size.y > 24, "Description remains scrollable %s %s" % [mode, dimensions])
			check(viewport.encloses(part.choose.get_global_rect()), "Choice remains reachable %s %s" % [mode, dimensions])
			check(part.title.get_global_rect().end.y <= part.scroll.get_global_rect().position.y, "Title and description do not overlap %s %s" % [mode, dimensions])
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			canvas.get_texture().get_image().save_png("/private/tmp/%s-selection-%dx%d.png" % [mode, dimensions.x, dimensions.y])
