extends SceneTree

class FixtureWorld extends RefCounted:
	var player := DungeonActor.new()
	func asset_path(kind: String, id: int) -> String:
		return "res://assets/characters/character_%d.glb" % id if kind == "characters" else ""

class FixtureGame extends Node:
	var catalog := DungeonCatalog.new()
	var profile := DungeonProfile.new()
	var systems: DungeonSystems
	var hud: DungeonHud
	var world := FixtureWorld.new()
	var selected_character := 1
	var resource_audio = null

var failures: Array[String] = []
var checks := 0
var canvas: SubViewport
var game: FixtureGame
var captures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func _settle() -> void:
	for frame in 8: await process_frame

func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	var image := canvas.get_texture().get_image()
	var colors: Dictionary = {}
	for y in range(0, image.get_height(), 8):
		for x in range(0, image.get_width(), 8): colors[image.get_pixel(x, y).to_html()] = true
	check(colors.size() > 50, "Rendered page has visible content: " + label)
	var path := "res://reports/spirit-attachment-%s-%dx%d.png" % [label, canvas.size.x, canvas.size.y]
	check(image.save_png(path) == OK, "Screenshot writes: " + label)
	captures.append(path)

func _run() -> void:
	create_timer(90).timeout.connect(func(): quit(2))
	canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	game = FixtureGame.new()
	canvas.add_child(game)
	check(game.catalog.load_all(), "Actual APK catalog loads")
	game.systems = DungeonSystems.new(game.catalog, game.profile)
	game.hud = DungeonHud.new()
	canvas.add_child(game.hud)
	game.world.player.combat = DungeonCombat.new()
	game.world.player.combat.configure()
	var menus := DungeonMenus.new(game)
	game.hud.action.connect(func(kind, id, _extra):
		if kind.begins_with("page:"): menus.open(kind.trim_prefix("page:"), int(id)))
	var skills: RefCounted = menus.spirit_skills
	check(skills.owned().is_empty(), "Camp has no adventure spirit attachments")
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(skills.SOURCE))
	check(source.icons.size() == 33, "Current APK covers eight three-tier families and nine fusions")
	for id in source.icons:
		var entry: Dictionary = skills.definition(int(id))
		check(not entry.is_empty() and entry.ability_id == int(id), "Spirit resolves through real LootData: " + id)
		check(entry.description == DungeonCatalog.clean(source.icons[id].description), "Description retains current APK behavior: " + id)
		check(DungeonStyle.texture(entry.icon) != null, "Current APK sprite loads: " + id)
	check(skills.definition(11005).is_empty(), "Ordinary relics do not become spirits")
	check(game.systems.begin_run(20261027, 1, 100, 0).success, "Adventure starts")
	game.profile.data.stats["max-region"] = 4
	for id in [20211, 20231]: game.profile.data.stats["loot-region:" + str(id)] = 2
	for id in [10000, 20210, 20220, 20230]: check(game.systems.add_loot(id).success, "Grant real loot: %d" % id)
	check(skills.owned().map(func(row): return int(row.id)) == [20210, 20220, 20230], "Acquired spirits attach without ordinary relics")
	var upgrade: Dictionary = skills.preview(20211)
	check(upgrade.mode == "升级" and upgrade.replacements.size() == 1 and upgrade.transition.contains("火精灵"), "Upgrade preview identifies the replaced attachment")
	for id in [20211, 20212, 20231, 20232]: check(game.systems.add_loot(id).success, "Upgrade through real source rules: %d" % id)
	var fusion: Dictionary = skills.preview(20270)
	check(fusion.mode == "融合" and fusion.available and fusion.replacements.size() == 2, "Fusion preview uses real eligibility and both components")
	check(skills.upgrade_options(20212).any(func(row): return int(row.id) == 20270), "Spirit detail can discover source fusion possibilities")
	check(game.systems.add_loot(20270).success, "Actual fusion succeeds")
	check(skills.owned().map(func(row): return int(row.id)) == [20220, 20270], "Fusion removes both component skill icons")
	for id in [20255, 20265]: check(game.systems.add_loot(id).success, "New APK spirit attaches: %d" % id)
	var owned_before: Dictionary = game.profile.data.run.inventory.duplicate(true)
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390)]:
		canvas.size = dimensions
		menus.open("characters")
		await _settle()
		var character: DungeonCharacterPage = game.hud.page.character_view
		var icons := character.detail.get_node_or_null("AttachedSpiritSkills")
		check(icons != null and icons.get_child_count() == 4, "Character displays only current attachments: " + str(dimensions))
		character.detail_scroll.scroll_vertical = 10000
		await _settle()
		if icons != null:
			var first: Button = icons.get_child(0)
			check(first.icon != null and first.tooltip_text.contains("水精灵"), "Character attachment has its actual icon and skill description")
			check(character.detail_scroll.get_global_rect().grow(0.5).encloses(first.get_global_rect()), "Character attachment can be scrolled into view: %s %s in %s" % [dimensions, first.get_global_rect(), character.detail_scroll.get_global_rect()])
		await _capture("character")
		if icons != null: icons.get_child(0).pressed.emit()
		await _settle()
		var inventory: DungeonInventoryPage = game.hud.page.inventory_view
		check(inventory != null and inventory.inventory_filter == "spirits" and inventory.selected_inventory_key == "loot:20220", "Character icon opens the correct spirit detail")
		check(inventory.selections.filter(func(button): return button.visible).size() == 4, "Spirit filter excludes ordinary relics")
		check(inventory.description_label.text.contains("已附加") and inventory.description_label.text.contains("进阶与融合"), "Detail shows attachment and real upgrade paths")
		check(inventory.filter_bar.get_global_rect().end.y <= inventory.item_scroll.get_global_rect().position.y, "Filters and item grid do not overlap: " + str(dimensions))
		check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(inventory.filter_bar.get_global_rect()), "Filter fits viewport: " + str(dimensions))
		await _capture("inventory")
		inventory.set_filter("all")
		check(inventory.selections.filter(func(button): return button.visible).size() == 5, "All filter restores ordinary loot")
		inventory.set_filter("spirits")
		inventory.select_item("loot:20270")
		menus.open("inventory")
		await _settle()
		inventory = game.hud.page.inventory_view
		check(inventory.inventory_filter == "spirits" and inventory.selected_inventory_key == "loot:20270", "Refresh preserves spirit filter and selected fusion")
		var row := {"title": fusion.name, "description": fusion.description, "icon": "loot:20270", "grade": fusion.grade, "spirit_skill": fusion,
			"level_text": fusion.transition, "buttons": [{"text": fusion.mode, "action": "choose_loot", "id": 20270, "extra": "altar:test"}]}
		game.hud.show_page("请选择一个精灵", [row, row.duplicate(true), row.duplicate(true)], "altar")
		await _settle()
		var altar: DungeonReferencePages = game.hud.page.special
		check(altar.altar_parts.size() == 3, "Altar presents three source candidates")
		for part in altar.altar_parts:
			check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(part.panel.get_global_rect()), "Fusion candidate fits viewport: " + str(dimensions))
			check(part.icon.texture != null and part.scroll.size.y > 20, "Fusion candidate preserves icon and scrollable skill text")
		await _capture("fusion")
	check(game.profile.data.run.inventory == owned_before, "Viewing attachments and previews never mutates inventory")
	game.profile.data.run.inventory = {"11005": 1}
	menus.open("inventory")
	await _settle()
	game.hud.page.inventory_view.set_filter("spirits")
	check(game.hud.page.inventory_view.selected == -1 and game.hud.page.inventory_view.empty_label.visible, "Empty spirit filter clears old detail and shows an empty state")
	game.profile.data.run.active = false
	check(skills.owned().is_empty(), "Ending adventure clears character attachments")
	menus.open("storage")
	await _settle()
	check(not game.hud.page.inventory_view.filter_bar.visible, "Persistent storage has no adventure filter")
	var report := {"checks": checks, "passed": failures.is_empty(), "failures": failures, "captures": captures,
		"scope": "Current APK data and icons, actual acquisition and fusion, character-to-bag navigation, filtering, previews and desktop/mobile Godot rendering"}
	FileAccess.open("res://reports/spirit-attachment-ui-test.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("SPIRIT_ATTACHMENT_UI ", JSON.stringify(report))
	game.world.player.free()
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
