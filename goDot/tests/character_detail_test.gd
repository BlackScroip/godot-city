extends SceneTree

class FixtureWorld extends RefCounted:
	var player = DungeonActor.new()
	func asset_path(kind: String, id: int) -> String:
		return "res://assets/characters/character_%d.glb" % id if kind == "characters" else ""

class FixtureGame extends Node:
	var catalog = DungeonCatalog.new()
	var profile = DungeonProfile.new()
	var systems: DungeonSystems
	var hud: DungeonHud
	var world = FixtureWorld.new()
	var selected_character = 1

var failures: Array[String] = []
var assertions := 0

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var display = TextureRect.new()
	display.texture = canvas.get_texture()
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(display)
	var game = FixtureGame.new()
	canvas.add_child(game)
	check(game.catalog.load_all(), "Recovered catalog loads")
	game.systems = DungeonSystems.new(game.catalog, game.profile)
	game.hud = DungeonHud.new()
	canvas.add_child(game.hud)
	game.world.player.combat = DungeonCombat.new()
	var combat: DungeonCombat = game.world.player.combat
	combat.configure()
	combat.health = 61
	combat.set_external_attributes({"AtkAddFixed": 20, "DefAddFixed": 10, "CriticalRate": 150, "CriticalMulti": 250})
	game.profile.data.run.active = true
	var menus = DungeonMenus.new(game)
	var navigation_actions: Array = []
	game.hud.action.connect(func(kind, id, _extra):
		navigation_actions.append(kind)
		if kind.begins_with("page:"): menus.open(kind.trim_prefix("page:"), int(id)))
	game.hud.set_adventure_mode(true)
	game.hud.navigation.get_child(3).pressed.emit()
	check(navigation_actions == ["page:characters"] and menus.current_page == "characters", "Maze HUD character button opens character detail")
	check(game.hud.page._rows.size() == 1, "Maze detail only shows the active character")
	var row: Dictionary = game.hud.page._rows[0]
	check(row.stats[0][1] == "61 / %d" % ceili(combat.max_health), "Detail uses current health")
	check(row.stats[1][1] == str(roundi(combat.effective_attack_power())), "Detail includes attack modifiers")
	check(row.stats[2][1] == str(roundi(combat.defense + 10)), "Detail includes defense modifiers")
	check(row.stats[3][1] == "20.0%", "Detail includes critical chance modifiers")
	check(row.stats[4][1] == "175%", "Detail includes critical damage modifiers")
	check(DungeonStyle.texture(row.artwork) != null, "Character uses recovered full artwork")
	check(row.buttons.any(func(entry): return entry.action == "page:character_talents"), "Detail links character talents")
	check(not row.buttons.any(func(entry): return str(entry.action).begins_with("op:")), "Maze detail does not offer camp recruitment or upgrades")
	for dimensions in [Vector2i(1600, 900), Vector2i(2460, 1080), Vector2i(844, 390)]:
		canvas.size = dimensions
		for step in 8: await process_frame
		var page = game.hud.page
		var view = page.special
		check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(page.get_rect()), "Character page fits " + str(dimensions))
		check(view.showcase.size.x > 100, "Hero art retains width " + str(dimensions))
		check(view.showcase.get_rect().end.x <= view.detail.get_parent().position.x, "Hero and attributes do not overlap " + str(dimensions))
		check(page.resource_bar.get_global_rect().end.x <= page.get_global_rect().end.x, "Resources fit " + str(dimensions))
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			canvas.get_texture().get_image().save_png("res://reports/character-detail-%dx%d.png" % [dimensions.x, dimensions.y])
	game.hud.page.special.use_model = true
	game.hud.page.special._select_showcase(0)
	for step in 8: await process_frame
	check(game.hud.page.special.showcase.get_child(0) is DungeonModelPreview, "3D toggle shows the real character model")
	check(Rect2(Vector2.ZERO, Vector2(canvas.size)).encloses(game.hud.page.get_rect()), "3D detail fits phone landscape")
	menus.open("storage")
	check(game.hud.page.title_label.text == "仓库", "Storage tab opens actual persistent materials")
	check(game.hud.page._rows.any(func(entry): return entry.get("material_id", 0) == 101), "Storage contains owned gold")
	menus.open("inventory")
	check(game.hud.page.page_context.page == "inventory", "Bag tab keeps run inventory")
	game.profile.data.run.active = false
	menus.open("characters")
	check(game.hud.page._rows.size() > 1, "Camp keeps character roster")
	game.world.player.free()
	canvas.queue_free()
	display.queue_free()
	await process_frame
	print("CHARACTER_DETAIL ", JSON.stringify({"passed": failures.is_empty(), "assertions": assertions, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
