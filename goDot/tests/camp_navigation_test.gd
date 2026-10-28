extends SceneTree

const NAVIGATION = preload("res://scripts/presentation/role_navigation.gd")
const PAGES := ["camp", "buildings", "characters", "weapons", "storage", "inventory", "resources", "resource", "training", "talents", "partners", "work", "dispatch", "meals", "npcs", "decorations", "archive", "history", "extra_challenges", "tasks", "achievements", "tokens", "amplifiers", "awakening", "difficulty", "mall", "settings"]
const CAPTURES := ["camp", "buildings", "tasks", "talents", "resources", "tokens", "awakening", "difficulty", "mall", "settings"]
var checks := 0
var failures: Array[String] = []
var game: Node
var canvas: SubViewport

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("CAMP NAVIGATION: " + message)

func settle() -> void:
	for frame in 8: await process_frame

func visible_back_buttons(node: Node, found: Array[Button]) -> void:
	if node is Button and node.get_meta("camp_back_navigation", false) and node.is_visible_in_tree(): found.append(node)
	for child in node.get_children(): visible_back_buttons(child, found)

func rect(control: Control) -> Rect2:
	var transform := control.get_global_transform()
	return Rect2(transform.origin, transform.get_scale().abs() * control.size)

func click(control: Control) -> void:
	var position := rect(control).get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = position
	canvas.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		canvas.push_input(event, true)
		await process_frame

func page_title() -> Control:
	var page: DungeonMenuPage = game.hud.page
	match page._layout:
		"camp_service", "tokens": return page.camp_service_view.heading.get_child(1)
		"awakening": return null
		"buildings": return page.building_view.title
		"character": return page.character_view._title_art
		"weapon": return null
		"inventory": return page.inventory_view._title_art
		"prepare": return page.prepare_view.header.get_child(1)
		"shop": return page.shop_view._title_art
		"settings": return page.special.settings_view.title
	return page.title_label

func _run() -> void:
	create_timer(90).timeout.connect(func(): quit(2))
	DungeonLocale.set_locale("zh_CN", false)
	canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	game = load("res://scenes/main.tscn").instantiate()
	game.save_store = DungeonSaveStore.new("/private/tmp/camp-navigation-%d.json" % Time.get_ticks_usec())
	canvas.add_child(game)
	while not game.initialized: await process_frame
	game.set_process(false)
	game.world.set_process(false)
	game.world.set_physics_process(false)
	game.world.player.set_physics_process(false)
	game.world._background = false
	game.audio.stop()
	for building in game.catalog.rows("Buildings"):
		game.profile.data.buildings[str(building.id)] = int(building.max_level)
	game.world.refresh_camp_progression()
	for viewport_size in [Vector2i(1600, 900), Vector2i(844, 390)]:
		canvas.size = viewport_size
		game.hud._layout()
		await settle()
		for destination in PAGES:
			game._close_page()
			var id := 101 if destination == "resource" else int(game.catalog.rows("MonsterWorkData")[0].id) if destination == "dispatch" else 0
			game.menus.open(destination, id)
			await settle()
			if destination == "buildings":
				game.hud.page.building_view._opening = false
				game.hud.page.building_view._apply_open(1.0)
			var found: Array[Button] = []
			visible_back_buttons(game.hud.page, found)
			var label: String = destination + " " + str(viewport_size)
			check(found.size() == 1, label + " exposes exactly one primary left back arrow")
			if found.size() != 1: continue
			var button := found[0]
			var bounds := rect(button)
			check(bounds.size.x >= 43.9 and bounds.size.y >= 43.9, label + " preserves a 44px touch target after scaling: " + str(bounds.size))
			check(button.get_node("Arrow").texture == NAVIGATION.BACK_TEXTURE, label + " uses the original shared arrow")
			check(button.get_theme_stylebox("normal") is StyleBoxEmpty and button.get_theme_stylebox("hover") is StyleBoxEmpty and button.get_theme_stylebox("pressed") is StyleBoxEmpty, label + " has no unrelated button backing")
			check(button.focus_mode == Control.FOCUS_ALL and not button.tooltip_text.is_empty(), label + " remains keyboard accessible and named")
			var expected := NAVIGATION.header_margin(Vector2(viewport_size))
			check(bounds.position.distance_to(expected) <= 3.0, label + " aligns its back arrow with shared safe margins: " + str(bounds.position))
			check(Rect2(Vector2.ZERO, Vector2(viewport_size)).encloses(bounds), label + " keeps its touch target fully on screen")
			var title := page_title()
			if is_instance_valid(title):
				check(absf(rect(title).get_center().y - bounds.get_center().y) <= 8, label + " vertically aligns its title with the back arrow")
			if destination == "difficulty":
				var prepare = game.hud.page.prepare_view
				var bounty: Button = prepare.left.get_child(0).get_child(-1)
				check(rect(prepare.left).encloses(rect(bounty)) and rect(bounty).size.y >= 44, label + " keeps the bounty entry fully visible and reachable")
			if OS.get_cmdline_user_args().has("--render-check") and destination in CAPTURES:
				await RenderingServer.frame_post_draw
				var screenshot = canvas.get_texture().get_image()
				check(not screenshot.is_empty(), label + " renders a nonempty page")
				screenshot.save_png("res://reports/camp-navigation-%s-%dx%d.png" % [destination, viewport_size.x, viewport_size.y])
			if destination == "difficulty":
				await click(game.hud.page.prepare_view.left.get_child(0).get_child(-1))
				check(game.menus.current_page == "extra_challenges", label + " opens the bounty page through an actual pointer click")
				game.menus.open("difficulty")
				await settle()
				button = game.hud.page.prepare_view.header.get_child(0)
			button.pressed.emit()
			if destination == "buildings": await create_timer(0.6).timeout
			check(game.menus.current_page == "work" if destination == "dispatch" else not game.hud.modal_open, label + " invokes the actual parent or close action")
		game.menus.open("characters")
		await settle()
		var character = game.hud.page.character_view
		character.attributes_button.pressed.emit()
		await settle()
		var attributes = character._attribute_overlay
		var attribute_back: Button = attributes.get_node("CloseAttributes")
		check(attribute_back.get_node("Arrow").texture == NAVIGATION.BACK_TEXTURE, "Attribute details uses the shared back arrow " + str(viewport_size))
		check(rect(attribute_back).size.y >= 43.9 and rect(attribute_back).position.distance_to(NAVIGATION.header_margin(Vector2(viewport_size))) <= 3, "Attribute details keeps the same safe position and touch target " + str(viewport_size))
		if OS.get_cmdline_user_args().has("--render-check"):
			await RenderingServer.frame_post_draw
			canvas.get_texture().get_image().save_png("res://reports/camp-navigation-attributes-%dx%d.png" % [viewport_size.x, viewport_size.y])
		await click(attribute_back)
		check(not attributes.visible and game.hud.modal_open and game.menus.current_page == "characters", "Attribute arrow returns to character details through a pointer click " + str(viewport_size))
	for alias in ["treasure", "chests"]:
		game.menus.open(alias)
		await settle()
		check(game.menus.current_page == "mall" and is_instance_valid(game.hud.page.shop_view), alias + " resolves to the implemented mall page")
		check(game.hud.page.shop_view.selected_category == "treasure", alias + " selects the real guild treasure tab")
		game.menus.open("mall")
		check(game.hud.page.shop_view.selected_category == "treasure", alias + " retains the treasure tab after a refresh")
	print("CAMP_NAVIGATION ", JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	game.free()
	canvas.free()
	quit(0 if failures.is_empty() else 1)
