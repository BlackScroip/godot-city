extends SceneTree

const Palette = preload("res://scripts/presentation/choice_palette.gd")
var failures: Array[String] = []
var checks := 0

class PageRecorder extends DungeonHud:
	var captured_rows: Array = []
	func show_page(_title: String, rows: Array, _layout := "list", _context: Dictionary = {}) -> void:
		captured_rows = rows

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _run() -> void:
	check(Palette.data().apk_sha256 == "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505", "Palette is recovered from the supplied APK")
	for value in [[0, 1], [1, 3], [2, 4], [3, 5], [8, 5]]:
		check(Palette.rarity(value[0]) == value[1], "Native talent level-to-star mapping %s" % [value])
	check(Palette.color("title").is_equal_approx(Color(1, 0.7488158345222473, 0.20283019542694092, 1)), "Title retains the prefab float RGBA")
	check(Palette.color("effect").is_equal_approx(Color(1, 0.9613932967185974, 0.9198113083839417, 1)), "Description retains the prefab float RGBA")
	check(Palette.color("choose").is_equal_approx(Color(1, 0.5888394117355347, 0, 1)), "Choice retains the prefab orange RGBA")
	check(int(Palette.data().button_transition) == 0, "Native choice button does not recolor on hover or press")
	for rare in range(1, 6):
		for kind in ["rarebg_vertical", "rarebg_vertical_line", "slotfg_rare_square"]:
			check(Palette.texture(Palette.sprite_key(kind, rare)) != null, "Recovered rarity %d %s exists" % [rare, kind])
	for kind in ["rarebg_vertical", "rarebg_vertical_line", "slotfg_rare_square"]:
		check(Palette.sprite_key(kind, 5, "旧日遗物") == kind + "_curse_v2", "Old-day items share the native curse sprite")
		check(Palette.texture(Palette.sprite_key(kind, 5, "诅咒遗物")) != null, "Recovered curse sprite exists")
	var canvas = SubViewport.new()
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var page = DungeonMenuPage.new()
	page.theme = DungeonStyle.theme()
	canvas.add_child(page)
	var rows: Array = []
	for level in range(1, 4):
		rows.append({"title": ["焰之伤", "炎灵灼杀", "炎爆瞬刃"][level - 1], "icon": "sprite_charatalent_10%d" % level,
			"target_level": level, "rarity": 2, "level_text": "Lv.%d" % level,
			"effect_description": "命中敌人后附加灼烧效果。", "level_description": "战技伤害提高%d%%。" % (level * 20),
			"buttons": [{"action": "choose_talent", "id": 100 + level}]})
	page.display("选择本局天赋", rows, "talent")
	var selection = page.special.get_child(0)
	for index in 3:
		check(selection.parts[index].panel.background_key == "rarebg_vertical_%d_v2" % (index + 3), "Talent card derives its sprite from candidate level")
		check(selection.parts[index].tag.get_theme_color("font_color").is_equal_approx(Palette.color("level")), "Talent level uses native brown")
		check(selection.parts[index].level_description.get_theme_color("font_color").is_equal_approx(Palette.color("level_description")), "Talent upgrade description keeps its distinct native color")
	await _capture(canvas, page, "talent")
	var catalog = DungeonCatalog.new()
	check(catalog.load_all(), "Load actual loot metadata")
	rows.clear()
	for id in [16101, 11101, 11005]:
		var ability = catalog.find("AbilityItems", id)
		rows.append({"title": ability.Name, "description": DungeonCatalog.clean(ability.Description), "icon": "loot:" + str(id),
			"rarity": int(ability.Rare), "loot_type": catalog.find("LootData", id).get("loot_type", ""), "buttons": [{"action": "choose_loot", "id": id}]})
	page.display("选择冒险道具", rows, "support")
	selection = page.special.get_child(0)
	for index in 3:
		check(selection.parts[index].panel.background_key == "rarebg_vertical_%d_v2" % (index + 1), "Item rarity retains exact source sprite")
		var frame = selection.parts[index].icon_frame.get_theme_stylebox("panel") as StyleBoxTexture
		check(frame.texture == Palette.texture(Palette.sprite_key("slotfg_rare_square", index + 1)), "Item icon frame matches the same rarity")
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
			check(selection.parts[index].choose.get_theme_color(state).is_equal_approx(Palette.color("choose")), "Choice does not introduce an unsupported text tint")
	await _capture(canvas, page, "items")
	rows.clear()
	for id in [22011, 20403, 13103]:
		var ability = catalog.find("AbilityItems", id)
		rows.append({"title": ability.Name, "description": DungeonCatalog.clean(ability.Description), "icon": "loot:" + str(id),
			"rarity": int(ability.Rare), "loot_type": catalog.find("LootData", id).get("loot_type", ""), "buttons": [{"action": "choose_loot", "id": id}]})
	page.display("选择冒险道具", rows, "support")
	selection = page.special.get_child(0)
	for index in 2:
		check(selection.parts[index].panel.background_key == "rarebg_vertical_curse_v2", "Curse and old-day cards use the native curse background")
		check(selection.parts[index].title.get_theme_color("font_color").is_equal_approx(Palette.color("curse_title_color")), "Curse title keeps its native muted gold")
		check(selection.parts[index].description.get_theme_color("font_color").is_equal_approx(Palette.color("curse_desc_color")), "Curse description keeps its native yellow")
	selection._select(1)
	check(selection.parts[1].panel.background_color().is_equal_approx(Palette.color("background_tint") * Color(245 / 255.0, 245 / 255.0, 245 / 255.0, 1)), "Selection tints only the background with native ColorBlock")
	await _capture(canvas, page, "special-items")
	_verify_entry_points(catalog)
	print("APK_CHOICE_COLOR_TEST ", JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)

func _verify_entry_points(catalog: DungeonCatalog) -> void:
	var game = load("res://scripts/main.gd").new()
	game.catalog = catalog
	game.profile = DungeonProfile.new()
	game.systems = DungeonSystems.new(catalog, game.profile)
	game.hud = PageRecorder.new()
	game.menus = DungeonMenus.new(game)
	check(game.systems.begin_run(817024, 1, 100).success, "Entry point audit starts a real run")
	game.profile.data.run.talent_rewards = []
	for quality in ["Low", "Normal", "High"]:
		game.profile.data.run.talent_rewards.clear()
		game.systems.set_record("talent:choices", 0)
		game.systems.queue_character_talent_reward(quality)
		var reward = game.systems.pending_character_talent_reward()
		for level in range(1, 4):
			for id in reward.choices: reward.levels[str(id)] = level
			game._talent_rewards()
			for row in game.hud.captured_rows:
				if row.get("presentation_role", "") == "refresh": continue
				check(row.rarity == level + 2 and row.target_level == level, "Real talent entry point uses level rather than %s quality" % quality)
	game.profile.data.run.talent_rewards.clear()
	game.systems.set_record("talent:choices", 0)
	game.profile.data.run.rewards = [{"key": "audit-colors", "choices": [22011, 20403, 13103]}]
	game._rewards("audit-colors")
	check(game.hud.captured_rows.slice(0, 3).map(func(row): return row.loot_type) == ["诅咒遗物", "旧日遗物", "天赋卷轴"], "Real reward entry point preserves loot types")
	game.hud.free()
	game.ads.free()
	game.resource_audio.free()
	game.free()

func _capture(canvas: SubViewport, page: DungeonMenuPage, label: String) -> void:
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390)]:
		canvas.size = dimensions
		page.size = Vector2(dimensions)
		for frame in 10: await process_frame
		if page._open_tween and page._open_tween.is_valid() and page._open_tween.is_running(): await page._open_tween.finished
		var selection = page.special.get_child(0)
		for part in selection.parts:
			check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(part.panel.get_global_rect()), "Native artwork remains in the viewport")
			check(part.scroll.size.y > 20, "Descriptions remain scrollable at both viewport sizes")
		if DisplayServer.get_name() == "headless": continue
		await RenderingServer.frame_post_draw
		var rendered = canvas.get_texture().get_image()
		var path = "res://reports/apk-choice-%s-%dx%d.png" % [label, dimensions.x, dimensions.y]
		rendered.save_png(path)
		for part in selection.parts:
			var sample_uv = Vector2(0.07, 0.5)
			var position = part.panel.get_global_transform() * (part.panel.size * sample_uv)
			var actual = rendered.get_pixelv(Vector2i(position))
			var source = part.panel.background.get_image()
			var expected = source.get_pixelv(Vector2i(Vector2(source.get_size()) * sample_uv)) * part.panel.background_color()
			var matches: bool = absf(actual.r - expected.r) < 0.04 and absf(actual.g - expected.g) < 0.04 and absf(actual.b - expected.b) < 0.04
			if not matches: print("CHOICE_COLOR_PIXEL ", JSON.stringify({"page": label, "size": str(dimensions), "background": part.panel.background_key, "point": str(position), "actual": str(actual), "expected": str(expected)}))
			check(matches, "Rendered card color matches the recovered APK pixel")
