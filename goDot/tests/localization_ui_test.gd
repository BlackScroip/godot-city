extends SceneTree

var failures: Array[String] = []
var checks := 0
var canvas: SubViewport
var output := "/private/tmp/localization-ui"
var languages: Array[Dictionary]
var render_check := false
var captures := 0
var strict_catalogs := false

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("LOCALIZATION UI FAILURE: " + message)

func _settle() -> void:
	for frame in 5: await process_frame

func _capture(name: String) -> void:
	if not render_check: return
	await RenderingServer.frame_post_draw
	var picture := canvas.get_texture().get_image()
	check(not picture.is_empty(), name + " renders")
	check(picture.get_pixel(picture.get_width() / 2, picture.get_height() / 2).a > 0.9, name + " is opaque")
	picture.save_png(output.path_join(name + ".png"))
	captures += 1

func _find_selector(node: Node) -> OptionButton:
	if node is OptionButton: return node
	for child in node.get_children():
		var selector := _find_selector(child)
		if selector: return selector
	return null

func _button_text_fits(home: CanvasLayer, suffix: String) -> void:
	var button: Button = home.start_button
	var font: Font = button.get_theme_font("font")
	var text_size := font.get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, button.get_theme_font_size("font_size"))
	var text_rect := Rect2(button.get_global_rect().get_center() - text_size * 0.5, text_size)
	check(not text_rect.intersects(button.get_node("LeftArrow").get_global_rect()), "Start text clears left arrow " + suffix)
	check(not text_rect.intersects(button.get_node("RightArrow").get_global_rect()), "Start text clears right arrow " + suffix)

func _file_digest(path: String) -> String:
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""

func _artwork_titles(view: Control, expected: int, suffix: String) -> void:
	var titles := view.find_children("LocalizedArtworkText", "Label", true, false)
	check(titles.size() == expected, "Artwork titles have localized captions " + suffix)
	for caption: Label in titles:
		var artwork := caption.get_parent() as TextureRect
		var use_caption := DungeonLocale.current_locale() != "zh_CN"
		check(caption.visible == use_caption, "Artwork title follows locale " + suffix)
		if not use_caption: continue
		check(artwork.texture == null, "Translated title clears baked text " + suffix)
		var translated := DungeonLocale.text(caption.text)
		var width := caption.get_theme_font("font").get_string_size(translated, HORIZONTAL_ALIGNMENT_LEFT, -1, caption.get_theme_font_size("font_size")).x
		check(width <= caption.size.x + 1, "Artwork caption fits " + suffix + " " + translated)
		check(caption.get_line_count() == 1, "Artwork caption remains on one line " + suffix)

func _visible_copy(node: Node, suffix: String) -> void:
	if not strict_catalogs or DungeonLocale.current_locale() in ["zh_CN", "zh_TW", "ja"]: return
	if node is Control and not node.is_visible_in_tree(): return
	if (node is Label or node is Button or node is RichTextLabel) and not node is OptionButton:
		var enabled := true
		var ancestor := node
		while ancestor:
			if ancestor.auto_translate_mode != Node.AUTO_TRANSLATE_MODE_INHERIT:
				enabled = ancestor.auto_translate_mode != Node.AUTO_TRANSLATE_MODE_DISABLED
				break
			ancestor = ancestor.get_parent()
		var displayed := node.tr(str(node.text)) if enabled else str(node.text)
		var han := RegEx.create_from_string("[\\x{3400}-\\x{9fff}]")
		check(han.search(displayed) == null, "Visible copy is translated " + suffix + " " + displayed.left(140))
	for child in node.get_children(): _visible_copy(child, suffix)

func _run() -> void:
	render_check = "--render-check" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless"
	strict_catalogs = "--strict-catalogs" in OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(output)
	languages = DungeonLocale.language_options()
	var test_languages := languages
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--test-locales="):
			var codes := argument.trim_prefix("--test-locales=").split(",")
			test_languages = languages.filter(func(entry): return entry.code in codes)
	check(not test_languages.is_empty(), "At least one requested locale is available")
	var original_locale := DungeonLocale.current_locale()
	var original_locale_path := DungeonLocale.settings_path
	var original_profile_digest := _file_digest(DungeonSaveStore.SAVE_PATH)
	var original_locale_digest := _file_digest(original_locale_path)
	var fixture_path := output.path_join("fixture-%d.json" % Time.get_ticks_usec())
	DungeonLocale.settings_path = fixture_path + ".language.cfg"
	canvas = SubViewport.new()
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	canvas.gui_embed_subwindows = true
	canvas.size = Vector2i(1600, 900)
	root.add_child(canvas)
	var home = load("res://scripts/presentation/start_screen.gd").new()
	canvas.add_child(home)
	for language in test_languages:
		DungeonLocale.set_locale(language.code, false)
		check(DungeonLocale.text("0") == "0", "Zero stays numeric " + str(language.code))
		check(DungeonLocale.text("42 / 100") == "42 / 100", "Counters stay numeric " + str(language.code))
		for dimensions in [Vector2i(1600, 900), Vector2i(844, 390)]:
			canvas.size = dimensions
			await _settle()
			var suffix := "%s-%dx%d" % [language.code, dimensions.x, dimensions.y]
			var bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
			check(bounds.encloses(home.start_button.get_global_rect()), "Start fits " + suffix)
			check(bounds.encloses(home.language_select.get_global_rect()), "Language selector fits " + suffix)
			check(home.language_select.item_count == 13, "All startup languages " + suffix)
			check(home.language_select.get_item_metadata(home.language_select.selected) == language.code, "Startup selection " + suffix)
			check(home.logo.visible == str(language.code).begins_with("zh"), "Localized brand mode " + suffix)
			_button_text_fits(home, suffix)
			if home.brand_label.visible:
				check(bounds.encloses(home.brand_label.get_global_rect()), "Brand fits " + suffix)
				check(home.brand_label.size.is_equal_approx(home.logo.size), "Brand uses logo frame " + suffix)
				var font: Font = home.brand_label.get_theme_font("font")
				var font_size: int = home.brand_label.get_theme_font_size("font_size")
				check(font.get_string_size(home.brand_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= home.brand_label.size.x, "Brand text fits " + suffix)
			for index in languages.size():
				check(home.language_select.get_item_text(index) == languages[index].name, "Native name " + suffix + str(index))
			await _capture("home-" + suffix)
			_visible_copy(home, "home " + suffix)
			if language.code == "en" and dimensions.x == 844 and render_check:
				home.language_select.show_popup()
				await _settle()
				await _capture("home-language-popup-" + suffix)
				home.language_select.get_popup().hide()
	home.language_select.item_selected.emit(2)
	check(DungeonLocale.current_locale() == "en", "Startup selection changes current language")
	check(home.language_select.get_item_metadata(home.language_select.selected) == "en", "Startup selection refreshes immediately")
	home.show_error("游戏资源加载失败，请重试")
	DungeonLocale.set_locale("de", false)
	await _settle()
	check(home.start_button.text == DungeonLocale.text("重新加载"), "Retry label follows changed language")
	_button_text_fits(home, "German retry")
	home.queue_free()
	await process_frame
	var game = load("res://scenes/main.tscn").instantiate()
	game.save_store = DungeonSaveStore.new(fixture_path)
	canvas.add_child(game)
	var deadline := Time.get_ticks_msec() + 20000
	while not game.initialized and Time.get_ticks_msec() < deadline: await process_frame
	check(game.initialized, "Game initializes for localization interface checks")
	if not game.initialized:
		canvas.queue_free()
		await process_frame
		DungeonLocale.settings_path = original_locale_path
		DungeonLocale.set_locale(original_locale, false)
		quit(1)
		return
	game.set_process(false)
	game.world.set_physics_process(false)
	game.world.paused = true
	for language in test_languages:
		DungeonLocale.set_locale(language.code, false)
		for dimensions in [Vector2i(1600, 900), Vector2i(844, 390)]:
			canvas.size = dimensions
			game.hud.close_page()
			await _settle()
			var suffix := "%s-%dx%d" % [language.code, dimensions.x, dimensions.y]
			for key in game.hud.navigation.get_children():
				var caption: Label = key.get_child(1)
				check(caption.size.x <= 114 and caption.get_line_count() <= 2, "HUD navigation caption fits " + suffix + " " + caption.text)
				var font: Font = caption.get_theme_font("font")
				var font_size: int = caption.get_theme_font_size("font_size")
				var measured := font.get_multiline_string_size(DungeonLocale.text(caption.text), HORIZONTAL_ALIGNMENT_CENTER, 110, font_size, -1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE)
				check(measured.y <= caption.size.y + 1, "HUD navigation caption height fits " + suffix + " " + caption.text)
			await _capture("camp-" + suffix)
			_visible_copy(game.hud, "HUD " + suffix)
			game.menus.open("settings")
			game.hud.page.special._settings_section("账户")
			await _settle()
			var page: DungeonMenuPage = game.hud.page
			var bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
			var selector := _find_selector(page.special)
			check(selector != null, "Settings selector exists " + suffix)
			check(bounds.encloses(page.get_global_rect()), "Settings page fits " + suffix)
			check(bounds.encloses(selector.get_global_rect()), "Settings selector fits " + suffix)
			check(page.get_global_rect().encloses(page.special.rail.get_parent().get_global_rect()), "Settings rail fits " + suffix)
			check(selector.item_count == 13, "All settings languages " + suffix)
			check(selector.get_item_metadata(selector.selected) == language.code, "Settings selection " + suffix)
			check(selector.size.x > 180, "Settings language usable width " + suffix)
			var title: Label = page.special.settings_view.title
			var title_width := title.get_theme_font("font").get_string_size(DungeonLocale.text(title.text), HORIZONTAL_ALIGNMENT_LEFT, -1, title.get_theme_font_size("font_size")).x
			check(title_width <= title.size.x and title.get_line_count() == 1, "Settings title fits on one line " + suffix)
			await _capture("settings-language-" + suffix)
			_visible_copy(page, "settings account " + suffix)
			for section in ["游戏性", "画面", "声音", "账户", "指南", "操作配置"]:
				page.special._settings_section(section)
				await _settle()
				var scroll: ScrollContainer = page.special.detail.get_parent()
				check(bounds.encloses(scroll.get_global_rect()), "Settings viewport fits " + section + " " + suffix)
				for row in page.special.detail.get_children():
					check(row.size.x <= scroll.size.x + 1, "Settings row fits horizontally " + section + " " + suffix)
				if section in ["画面", "游戏性"]:
					await _capture("settings-" + ("visual-" if section == "画面" else "gameplay-") + suffix)
				_visible_copy(page, "settings " + section + " " + suffix)
			var views := {"characters": "character_view", "weapons": "weapon_view", "storage": "inventory_view", "mall": "shop_view", "difficulty": "prepare_view"}
			for destination in views:
				game.menus.open(destination)
				await _settle()
				var current_page: DungeonMenuPage = game.hud.page
				var current_view: Control = current_page.get(views[destination])
				check(is_instance_valid(current_view), "Localized page opens " + destination + " " + suffix)
				check(bounds.encloses(current_page.get_global_rect()), "Localized page fits viewport " + destination + " " + suffix)
				if is_instance_valid(current_view):
					check(current_page.get_global_rect().encloses(current_view.get_global_rect()), "Localized view fits page " + destination + " " + suffix)
					_artwork_titles(current_view, 2 if destination in ["mall", "weapons"] else 1, destination + " " + suffix)
					if destination == "difficulty":
						check(not current_view.left.get_global_rect().intersects(current_view.right.get_global_rect()), "Preparation columns do not overlap " + suffix)
						check(bounds.encloses(current_view.start.get_global_rect()), "Preparation start button fits " + suffix)
						var token_heading: Label = current_view.token_title
						var heading_width := token_heading.get_theme_font("font").get_string_size(DungeonLocale.text(token_heading.text), HORIZONTAL_ALIGNMENT_LEFT, -1, token_heading.get_theme_font_size("font_size")).x
						check(heading_width <= token_heading.size.x + 1 or token_heading.get_line_count() > 1, "Preparation token heading wraps long translations " + suffix)
						check(token_heading.get_visible_line_count() > 0 and token_heading.get_visible_line_count() == token_heading.get_line_count(), "Preparation token heading remains fully visible " + suffix)
						for card in current_view.equipment.get_children():
							var content: VBoxContainer = card.get_child(0)
							for item in content.get_children():
								if item is Control and item.visible:
									check(card.get_global_rect().grow(1).encloses(item.get_global_rect()), "Preparation equipment content stays inside its card " + suffix)
							var caption: Label = content.get_child(0)
							check(caption.get_line_count() <= 2 and caption.get_visible_line_count() == caption.get_line_count(), "Preparation equipment name remains fully visible " + suffix)
				await _capture("page-" + destination + "-" + suffix)
				_visible_copy(current_page, destination + " " + suffix)
			if strict_catalogs:
				for destination in ["camp", "training", "resources", "talents", "character_talents", "partners", "work", "decorations", "meals", "meal_buffs", "buildings", "npcs", "awakening", "tokens", "amplifiers", "achievements", "tasks", "archive"]:
					game.menus.open(destination)
					await _settle()
					var current_page: DungeonMenuPage = game.hud.page
					var fits := bounds.encloses(current_page.get_global_rect())
					check(fits, "Additional menu fits viewport " + destination + " " + suffix)
					if not fits:
						print("LOCALIZATION_UI_OVERFLOW ", destination, " ", suffix, " page=", current_page.get_global_rect(), " minimum=", current_page.get_combined_minimum_size())
						for child in current_page.stack.get_children():
							if child is Control and child.visible:
								print("LOCALIZATION_UI_OVERFLOW_CHILD ", child.get_class(), " size=", child.size, " minimum=", child.get_combined_minimum_size())
						await _capture("overflow-" + destination + "-" + suffix)
					if destination == "awakening":
						var summary := current_page.special.find_child("AwakeningSummary", true, false)
						check(summary != null, "Awakening summary exists " + suffix)
						if summary:
							var summary_text: Label = summary.get_child(0)
							var text_width := summary_text.get_theme_font("font").get_string_size(DungeonLocale.text(summary_text.text), HORIZONTAL_ALIGNMENT_LEFT, -1, summary_text.get_theme_font_size("font_size")).x
							check(text_width <= summary_text.size.x + 1 or summary_text.get_line_count() > 1, "Awakening summary wraps long translations " + suffix)
							check(summary_text.get_visible_line_count() > 0 and summary_text.get_visible_line_count() == summary_text.get_line_count(), "Awakening summary remains fully visible " + suffix)
						await _capture("page-awakening-" + suffix)
					_visible_copy(current_page, destination + " " + suffix)
		print("LOCALIZATION_UI_LOCALE ", language.code)
	game.menus.open("settings")
	game.hud.page.special._settings_section("账户")
	var selector := _find_selector(game.hud.page.special)
	var wallet: Dictionary = game.profile.data.materials.duplicate(true)
	selector.item_selected.emit(4)
	check(DungeonLocale.current_locale() == "ko", "Settings selection reaches main command")
	check(game.hud.page.page_context.get("settings_section") == "账户", "Settings refresh preserves account section")
	check(game.profile.data.materials == wallet and not game.profile.data.run.active, "Changing language preserves progress")
	canvas.queue_free()
	await process_frame
	await process_frame
	DungeonLocale.settings_path = original_locale_path
	DungeonLocale.set_locale(original_locale, false)
	for suffix in ["", ".bak", ".tmp", ".language.cfg"]:
		if FileAccess.file_exists(fixture_path + suffix): DirAccess.remove_absolute(fixture_path + suffix)
	check(_file_digest(DungeonSaveStore.SAVE_PATH) == original_profile_digest, "User profile remains unchanged")
	check(_file_digest(original_locale_path) == original_locale_digest, "User language preference remains unchanged")
	var result := {"checks": checks, "failures": failures, "passed": failures.is_empty(), "rendered": render_check, "copy_checked": strict_catalogs, "captures": captures, "locales": test_languages.map(func(entry): return entry.code), "viewports": [[1600, 900], [844, 390]], "screenshot_directory": output}
	var report := "res://reports/localization-ui.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(report.get_base_dir()))
	var file := FileAccess.open(report, FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t") + "\n")
	print("LOCALIZATION_UI_TEST ", JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
