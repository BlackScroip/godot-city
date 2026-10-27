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
	var resource_audio = null

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
	game.world.player.combat.configure()
	var menus = DungeonMenus.new(game)
	var available := 0
	var inspected := 0
	var inline_map = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/talent_view/inline_map.json"))
	for path in inline_map.values():
		check(ResourceLoader.exists(str(path)) and load(str(path)) is Texture2D, "Inline icon texture exists: " + str(path))
	for character in game.catalog.rows("CharData"):
		if character.get("available_state", "") != "Normal": continue
		available += 1
		var id = int(character.id)
		menus.open("character_talents", id)
		var inspector = game.hud.page.character_view.talent_view
		var source_rows = game.catalog.rows("CharTalentData").filter(func(row): return int(row.chara_id) == id)
		check(inspector.character_id == id, "Inspector follows browsed character %d" % id)
		check(inspector.groups.size() == (0 if source_rows.is_empty() else 3), "Character %d matches available source talent groups" % id)
		check(inspector.buttons.size() == source_rows.size() and (id == 8 or source_rows.size() == 21), "Character %d matches available source nodes" % id)
		for group in inspector.groups.values():
			check(group.size() == 7 and group.filter(func(row): return bool(row.get("is_core_talent", false))).size() == 1, "Each source group has one core and six enhancements")
		for talent_id in inspector.buttons:
			var icons = inspector.buttons[talent_id].get_children().filter(func(child): return child is TextureRect)
			check(not icons.is_empty() and icons[0].texture != null, "Talent %d has its recovered icon" % int(talent_id))
			inspector.show_detail(int(talent_id))
			var description: String = inspector.detail_text.get_parsed_text()
			for level in [1, 2, 3]:
				check(("等级%d：" % level) in description, "Talent %d includes level %d" % [int(talent_id), level])
			check(not "<#specinfo" in inspector.detail_text.text, "Talent %d resolves every rich-text term" % int(talent_id))
			inspector.close_detail()
			inspected += 1
		inspector.queue_free()
		await process_frame
	check(available == 8, "All eight available characters are covered")
	check(inspected == 168, "All 168 available talents and their three levels are inspected")
	menus.open("characters", 1)
	var character_view = game.hud.page.character_view
	menus.open("character_talents", 1)
	var view = character_view.talent_view
	check(game.hud.page.character_view == character_view and menus.current_page == "characters", "Talent route preserves character page background")
	var rows = game.catalog.rows("CharTalentData").filter(func(row): return int(row.chara_id) == 1)
	var first_id = int(rows[0].id)
	var locked_count := 0
	for row in rows:
		var locked = int(row.unlock_chara_level) > 1
		var badge = view.buttons[int(row.id)].get_node_or_null("UnlockLevel")
		check(is_instance_valid(badge) == locked, "Unlock badge follows character level for %d" % int(row.id))
		if locked:
			locked_count += 1
			check(badge.text == str(int(row.unlock_chara_level)), "Badge displays exact required level")
	check(locked_count > 0, "Locked talent badges are exercised")
	var button: Button = view.buttons[first_id]
	for step in 4: await process_frame
	_click(canvas, button.get_global_rect().get_center())
	await process_frame
	check(is_instance_valid(view.detail_overlay), "Viewport pointer click on a talent opens its detail")
	_click(canvas, view.detail_panel.get_global_rect().position + Vector2(12, 12))
	await process_frame
	check(is_instance_valid(view.detail_overlay), "Click inside the detail paper does not pass through to dismiss")
	_click(canvas, Vector2(10, 10))
	await process_frame
	check(not is_instance_valid(view.detail_overlay) and not view.is_queued_for_deletion(), "Real background click dismisses only the detail layer")
	for expected_mark in [true, false]:
		_pointer(canvas, button.get_global_rect().get_center(), true)
		await create_timer(view.HOLD_SECONDS + 0.1).timeout
		_pointer(canvas, button.get_global_rect().get_center(), false)
		await process_frame
		check(game.systems.is_character_talent_marked(first_id) == expected_mark, "Real pointer hold toggles mark to " + str(expected_mark))
		check(not is_instance_valid(view.detail_overlay), "Real pointer long-press release never opens detail")
	button.button_down.emit()
	view._process(view.HOLD_SECONDS - 0.01)
	check(not game.systems.is_character_talent_marked(first_id), "Hold shorter than the source threshold does not mark")
	view._process(0.011)
	button.button_up.emit()
	button.pressed.emit()
	check(game.systems.is_character_talent_marked(first_id), "Holding to the source threshold marks talent")
	check(not is_instance_valid(view.detail_overlay), "Long press release does not open detail")
	button.button_down.emit()
	view._process(0.1)
	button.button_up.emit()
	button.pressed.emit()
	check(is_instance_valid(view.detail_overlay), "Short press opens detail")
	for level in [1, 2, 3]:
		check(("等级%d：" % level) in view.detail_text.get_parsed_text(), "Detail shows level %d" % level)
	var click = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	view.detail_overlay.gui_input.emit(click)
	check(not is_instance_valid(view.detail_overlay) and not view.is_queued_for_deletion(), "Detail background dismisses only top layer")
	var other: Dictionary = game.catalog.rows("CharTalentData").filter(func(row): return int(row.chara_id) == 2)[0]
	game.systems.toggle_character_talent_mark(int(other.id), 2)
	view.clear_button.pressed.emit()
	check(not game.systems.is_character_talent_marked(first_id) and game.systems.is_character_talent_marked(int(other.id)), "Clear button only clears browsed character")
	for dimensions in [Vector2i(844, 390), Vector2i(1600, 900), Vector2i(2048, 900)]:
		canvas.size = dimensions
		for step in 8: await process_frame
		var viewport_rect = Rect2(Vector2.ZERO, Vector2(dimensions))
		check(viewport_rect.encloses(view.panel.get_global_rect()), "Talent panel fits " + str(dimensions))
		check(viewport_rect.encloses(view.clear_button.get_global_rect()), "Clear command fits " + str(dimensions))
		var rectangles: Array[Rect2] = []
		for talent_button in view.buttons.values():
			var area = talent_button.get_global_rect()
			check(view.panel.get_global_rect().encloses(area), "Talent node remains inside panel " + str(dimensions))
			for previous in rectangles: check(not area.intersects(previous), "Talent nodes do not overlap " + str(dimensions))
			rectangles.append(area)
		await _screenshot(canvas, "character-talents-%dx%d.png" % [dimensions.x, dimensions.y])
		view.show_detail(192)
		for step in 4: await process_frame
		check(viewport_rect.encloses(view.detail_panel.get_global_rect()), "Talent detail fits " + str(dimensions))
		check(view.detail_panel.get_global_rect().encloses(view.detail_text.get_global_rect()), "Detail description fits paper " + str(dimensions))
		await _screenshot(canvas, "character-talents-detail-%dx%d.png" % [dimensions.x, dimensions.y])
		view.close_detail()
	_click(canvas, Vector2(10, 10))
	await process_frame
	check(not is_instance_valid(view) and is_instance_valid(game.hud.page.character_view), "Outer background closes inspector and preserves character")
	game.profile.data.run.active = true
	game.systems.queue_character_talent_reward("Low", 1)
	var pending = game.profile.data.run.talent_rewards.duplicate(true)
	var choices = game.systems.stat("talent:choices")
	menus.open("character_talents", 1)
	game.hud.page.character_view.talent_view.show_detail(first_id)
	check(game.profile.data.run.talent_rewards == pending and game.systems.stat("talent:choices") == choices and game.profile.data.run.talents.is_empty(), "Inspecting talents never consumes pending choice or learns a talent")
	game.hud.page.character_view.talent_view.queue_free()
	await process_frame
	game.profile.data.character_levels["1"] = 8
	game.profile.data.run.talents = {"101": 1, "102": 2, "103": 3}
	game.systems.toggle_character_talent_mark(101, 1)
	menus.open("character_talents", 1)
	var run_view = game.hud.page.character_view.talent_view
	for id in [101, 102, 103]:
		var rank = id - 100
		var node: Button = run_view.buttons[id]
		check(node.get_meta("rarity") == rank + 2, "Run talent rank %d uses source rarity %d" % [rank, rank + 2])
		var stars = node.get_node_or_null("TalentLevelStars")
		check(is_instance_valid(stars) and stars.get_child_count() == rank, "Run talent rank %d displays matching star count" % rank)
		if is_instance_valid(stars):
			check(stars.get_children().all(func(child): return child is TextureRect and child.texture != null), "Run talent stars use recovered textures")
	check(run_view.buttons[101].get_node("MarkFrame").visible, "Owned talent independently retains its marker")
	for step in 6: await process_frame
	await _screenshot(canvas, "character-talents-run-marked-2048x900.png")
	game.world.player.free()
	canvas.queue_free()
	display.queue_free()
	await process_frame
	print("CHARACTER TALENT INSPECTOR: ", JSON.stringify({"assertions": assertions, "failures": failures, "passed": failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)

func _screenshot(canvas: SubViewport, file: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	check(canvas.get_texture().get_image().save_png("res://reports/" + file) == OK, "Screenshot saved: " + file)

func _click(canvas: SubViewport, position: Vector2) -> void:
	var motion = InputEventMouseMotion.new()
	motion.position = position
	canvas.push_input(motion, true)
	for pressed in [true, false]:
		_pointer(canvas, position, pressed)

func _pointer(canvas: SubViewport, position: Vector2, pressed: bool) -> void:
	var event = InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	canvas.push_input(event, true)
