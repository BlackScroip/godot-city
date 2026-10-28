extends SceneTree

var checks := 0
var failures: Array[String] = []
var catalog := DungeonCatalog.new()
var terms: Dictionary = {}
var semantic := RegEx.create_from_string("<#specinfo=[\"']?([^>\"']+)[\"']?>")
var sprite := RegEx.create_from_string("<sprite\\s+name=[\"']([^\"']+)[\"'][^>]*>")
var images := RegEx.create_from_string("\\[img=\\d+x\\d+\\](.*?)\\[/img\\]")
var canvas: SubViewport
var source_fields := 0
var source_icons := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr(message)

func _expected_icons(source: String) -> Array:
	var expanded = source
	for depth in 8:
		var matches = semantic.search_all(expanded)
		if matches.is_empty(): break
		for token in matches:
			expanded = expanded.replace(token.get_string(), str(terms.get("<#specinfo=" + token.get_string(1) + ">", {}).get("text_cn", "")))
	var result: Array = []
	for token in sprite.search_all(expanded):
		result.append(SourceRichText.sprite_path(token.get_string(1)))
	return result

func _verify(label: SourceRichText, source: String, context: String) -> void:
	var expected = _expected_icons(source)
	var actual: Array = []
	for token in images.search_all(label.text): actual.append(token.get_string(1))
	check(label.source_text == source, context + " keeps source tags before rendering")
	check(actual == expected and not expected.has(""), context + " keeps every APK icon in order")
	check(not label.get_parsed_text().contains("【图标：") and not label.text.contains("<#"), context + " has no missing icon or leaked source tag")
	source_fields += 1
	source_icons += expected.size()

func _settle() -> void:
	for frame in 6: await process_frame

func _capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var image = canvas.get_texture().get_image()
	check(not image.is_empty() and image.get_used_rect().has_area(), name + " renders visible pixels")
	image.save_png("res://reports/description-icons-%s-%dx%d.png" % [name, canvas.size.x, canvas.size.y])

func _verify_flow(stack: Control, context: String) -> void:
	var previous_end := 0.0
	for child in stack.get_children():
		if not child is Control or not child.visible: continue
		check(child.position.y >= previous_end - 1, context + " description rows do not overlap")
		previous_end = child.get_rect().end.y
		if child is SourceRichText:
			check(child.size.y >= child.get_content_height() - 1, context + " rich text fits its content height")
			check(child.size.x <= stack.size.x + 1, context + " rich text fits the column width")

func _run() -> void:
	DungeonLocale.set_locale("zh_CN", false)
	check(catalog.load_all(), "APK catalog loads")
	for row in JSON.parse_string(FileAccess.get_file_as_string(SourceRichText.TERMS_PATH)):
		terms[str(row.key)] = row
	var probe = SourceRichText.new()
	root.add_child(probe)
	# Real corpus checks derive the expected icon sequence from the APK keyword table.
	for table in ["WeaponData", "CharaTalentAwakeTreeData", "RelationshipAmplifyData"]:
		for row in catalog.rows(table):
			for field in ["description", "effect_description"]:
				var raw = SourceRichText.source_field(table, DungeonCatalog.row_id(row), field, str(row.get(field, "")))
				if raw.is_empty(): continue
				probe.set_source(raw)
				_verify(probe, raw, "%s:%d:%s" % [table, DungeonCatalog.row_id(row), field])
	var combat: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/combat.json"))
	for fighter in combat.characters:
		for skill in fighter.skills:
			var id = int(skill.id) if int(skill.id) > 0 else int(fighter.skills[0].id)
			var raw = SourceRichText.source_field("AttackData", id, "description", str(skill.description))
			probe.set_source(raw)
			_verify(probe, raw, "Character %d skill %d" % [int(fighter.id), int(skill.id)])
	var dialogue: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/dialogue.json"))
	var color_line: Dictionary = {}
	for story in dialogue.Stories:
		for line in story.Lines:
			if str(line.Text).contains("<color="):
				probe.set_source(str(line.Text))
				check(probe.text.contains("[color=") and not probe.text.contains("<color"), "Original dialogue colors remain formatted")
				if color_line.is_empty(): color_line = line
	probe.queue_free()
	canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var display = TextureRect.new()
	display.texture = canvas.get_texture()
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(display)
	var profile = DungeonProfile.new()
	var systems = DungeonSystems.new(catalog, profile)
	var page = preload("res://scripts/presentation/weapon_page.gd").new()
	page.theme = DungeonStyle.theme()
	canvas.add_child(page)
	var rows: Array = []
	for source in catalog.rows("WeaponData"):
		if int(source.id) not in [101, 102, 103, 104, 105]: continue
		rows.append({"weapon_id": int(source.id), "title": source.name, "rank": 1, "source_description": source.description, "effect_description": source.effect_description, "description": DungeonCatalog.clean(source.description), "buttons": []})
	page.configure(null, rows, {"catalog": catalog, "systems": systems, "character_id": 1, "selected_weapon": 101, "equipped_weapon": 101})
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390)]:
		canvas.size = dimensions
		page.size = Vector2(dimensions)
		for row in rows:
			for rank in 5:
				row.rank = rank + 1
				page.select_weapon(int(row.weapon_id))
				var expected = SourceRichText.source_field("WeaponData", int(row.weapon_id), "effect_description", str(row.effect_description)).split("|")[rank].strip_edges()
				_verify(page.effect_label, expected, "Actual weapon %d rank %d at %s" % [row.weapon_id, rank + 1, dimensions])
		page.select_weapon(101)
		await _settle()
		_verify_flow(page.biography.get_parent(), "Weapon detail " + str(dimensions))
		await _capture("weapon")
		page.open_selector()
		await _settle()
		_verify(page.selector_effect, "等级5：\n" + str(rows[0].effect_description).split("|")[4].strip_edges(), "Weapon selector " + str(dimensions))
		_verify_flow(page.selector_effect.get_parent(), "Weapon selector " + str(dimensions))
		await _capture("weapon-selector")
		page.set_selector_open(false)
	var blade = catalog.find("WeaponData", 801)
	page.rows.append({"weapon_id": 801, "title": blade.name, "rank": 1, "source_description": blade.description, "effect_description": blade.effect_description, "description": blade.description + "\n需要武器矿石", "buttons": []})
	page.select_weapon(801)
	check(page.name_label.text == SourceRichText.source_field("WeaponData", 801, "name"), "Character eight weapon uses its recovered APK name")
	check(not page.effect_label.source_text.contains("LV1") and page.effect_label.text.contains("[img="), "Character eight placeholder effects are replaced by the APK icon descriptions")
	check(page.selector_status.text == "需要武器矿石", "Catalog placeholder biography does not leak into the recovered selector status")
	await _settle()
	await _capture("blade-weapon")
	page.queue_free()
	await process_frame
	var character = preload("res://scripts/presentation/character_page.gd").new()
	canvas.add_child(character)
	var character_rows: Array = []
	for fighter in combat.characters:
		var source = catalog.find("CharData", int(fighter.id))
		character_rows.append({"config_id": int(fighter.id), "title": source.name, "description": source.description, "stats": [], "buttons": []})
	character.configure(null, character_rows, {"catalog": catalog, "systems": systems, "selected_character": 1})
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390)]:
		canvas.size = dimensions
		character.size = Vector2(dimensions)
		for index in combat.characters.size():
			character.selected = index
			character.set_detail_tab("style")
			await _settle()
			var labels = character.detail.get_children().filter(func(child): return child is SourceRichText)
			check(labels.size() == 4, "All four visible character skill descriptions use source rich text")
			for skill_index in labels.size():
				var skill: Dictionary = combat.characters[index].skills[skill_index]
				var expected = SourceRichText.source_field("AttackData", int(skill.id), "description", str(skill.description))
				_verify(labels[skill_index], expected, "Actual character %d skill %d at %s" % [index + 1, skill_index, dimensions])
			_verify_flow(character.detail, "Character skills " + str(dimensions))
			if index == 0: await _capture("skills")
	character.queue_free()
	await process_frame
	var talk = preload("res://scripts/presentation/dialogue_page.gd").new()
	talk.theme = DungeonStyle.theme()
	canvas.add_child(talk)
	talk.configure(null, [], {"speaker": color_line.get("Speaker", ""), "text": color_line.get("Text", ""), "portrait": "characterillustration_jianzhu_normal"})
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390)]:
		canvas.size = dimensions
		talk.size = Vector2(dimensions)
		await _settle()
		_verify(talk.text_label, str(color_line.get("Text", "")), "Actual source dialogue " + str(dimensions))
		check(talk.text_label.text.contains("[color="), "Actual dialogue view keeps source color")
		check(talk.text_label.size.y >= talk.text_label.get_content_height() - 1, "Dialogue grows inside the scroll area")
		await _capture("dialogue")
		var tagged = str(combat.characters[0].skills[1].description)
		talk.text_label.set_source(tagged)
		talk._layout()
		await _settle()
		_verify(talk.text_label, tagged, "Controlled tagged dialogue input " + str(dimensions))
		check(talk.text_label.text.contains("[img=%dx%d]" % [talk.text_label.get_theme_font_size("normal_font_size"), talk.text_label.get_theme_font_size("normal_font_size")]), "Dialogue inline icons follow its responsive font")
		talk.text_label.set_source(str(color_line.get("Text", "")))
	talk.queue_free()
	await process_frame
	var awakening = preload("res://scripts/presentation/awakening_page.gd").new()
	canvas.add_child(awakening)
	awakening.configure(null, [], {"catalog": catalog, "systems": systems, "character_id": 1})
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390)]:
		canvas.size = dimensions
		awakening.size = Vector2(dimensions)
		await _settle()
		var labels = awakening.details.get_children().filter(func(child): return child is SourceRichText)
		check(labels.size() == 1, "Actual awakening effect uses source rich text")
		if not labels.is_empty():
			_verify(labels[0], DungeonCatalog.description(catalog.find("CharaTalentAwakeTreeData", awakening.selected_awakening)), "Actual awakening " + str(dimensions))
		_verify_flow(awakening.details, "Awakening " + str(dimensions))
		await _capture("awakening")
	canvas.queue_free()
	display.queue_free()
	await process_frame
	var result = {"passed": failures.is_empty(), "checks": checks, "failures": failures, "source_fields": source_fields, "source_icon_occurrences": source_icons, "evidence_type": "Godot reconstruction runtime; APK tags and PNG provenance checked separately", "viewports": ["1600x900", "844x390"]}
	FileAccess.open("res://reports/description-inline-icons-test-20261028.json", FileAccess.WRITE).store_string(JSON.stringify(result, "\t"))
	print("DESCRIPTION_INLINE_ICONS_TEST ", JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
