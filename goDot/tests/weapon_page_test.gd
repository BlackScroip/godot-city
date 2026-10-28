extends SceneTree

const WeaponPage = preload("res://scripts/presentation/weapon_page.gd")
var failures: Array[String] = []
var checks := 0
var commands: Array = []
var catalog = DungeonCatalog.new()
var systems

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _rows(character_id := 1, in_run := false) -> Array:
	var result: Array = []
	var source_character = catalog.find("CharData", character_id)
	var allowed = DungeonCatalog.ids(source_character.get("can_equip_weapon_id_list", ""))
	for source in catalog.rows("WeaponData"):
		var id = int(source.id)
		if id not in allowed: continue
		var rank = systems.stat("weapon:" + str(id))
		var quote = systems.weapon_upgrade_status(id)
		var buttons: Array = []
		if not in_run:
			buttons = [{"text": "打造" if rank == 0 else "升级", "action": "op:upgrade_weapon", "id": id, "extra": 0, "disabled": not quote.can_upgrade}, {"text": "已装备" if id == 101 else "装备", "action": "equip_weapon", "id": id, "extra": 0, "disabled": rank == 0 or id == 101}]
		result.append({"config_id": id, "weapon_id": id, "title": source.name, "rank": rank, "icon": source.square_icon_name, "model": "res://assets/weapons/weapon_%d.glb" % id, "source_description": DungeonCatalog.clean(source.description), "effect_description": source.effect_description, "description": DungeonCatalog.clean(source.description) + "\n" + str(quote.reason), "buttons": buttons, "in_run": in_run})
	return result

func _run() -> void:
	check(catalog.load_all(), "original weapon and character catalog loads")
	systems = DungeonSystems.new(catalog, DungeonProfile.new())
	var viewport = SubViewport.new()
	viewport.size = Vector2i(2048, 900)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var page = WeaponPage.new()
	viewport.add_child(page)
	page.size = viewport.size
	var context = {"catalog": catalog, "systems": systems, "character_id": 1, "selected_weapon": 101, "equipped_weapon": 101, "resources": [["material:101", "1378"]]}
	page.configure(null, _rows(), context)
	page.command.connect(func(kind, id, extra): commands.append([kind, id, extra]))
	for key in page._selector_map: check(page._texture(key, true) != null, "recovered original selector texture loads " + str(key))
	check(page.weapon_buttons.size() == 5, "selector shows five configured records without inventing the absent sixth slot")
	check(page.navigation.size() == 3, "camp uses original character weapon storage navigation")
	check(page.selected_weapon == 101 and page.name_label.text == "暗月刀", "initial real weapon identity matches source screenshot")
	check(page.effect_label.text == "攻击力+5%。", "main detail shows current rank effect without all five rank descriptions")
	check(page.preview.has_model, "real converted GLB is loaded")
	check(not page.selector_open and not page.selector.visible, "weapon main screen starts with unframed preview")
	var original_equipped = int(context.equipped_weapon)
	page.select_weapon(102)
	check(page.selected_weapon == 102 and context.selected_weapon == 102, "browsed weapon persists")
	check(commands.is_empty() and int(context.equipped_weapon) == original_equipped, "browsing never emits an equip operation")
	page.select_weapon(999999)
	check(page.selected_weapon == 102, "unknown source id cannot replace selection")
	page.selector_entry.pressed.emit()
	check(page.selector_open and context.weapon_selector_open, "original weapon switch opens persistent selector")
	page.weapon_buttons[101].pressed.emit()
	check(page.selected_weapon == 101 and page.selector_open, "selector weapon browsing preserves the active overlay")
	page._emit_entry({"action": "equip_weapon", "id": 102, "disabled": true})
	check(commands.is_empty(), "locked disabled operation cannot emit")
	page._emit_entry({"action": "op:upgrade_weapon", "id": 101, "extra": 0})
	check(commands.back() == ["op:upgrade_weapon", 101, 0], "real operation contract and selected id remain intact")
	for dimensions in [Vector2i(2048, 900), Vector2i(1600, 900), Vector2i(844, 390), Vector2i(2460, 1080)]:
		viewport.size = dimensions
		page.size = dimensions
		page.select_weapon(101)
		page.set_selector_open(false)
		for frame in 12: await process_frame
		var bounds = Rect2(Vector2.ZERO, Vector2(dimensions))
		var factor = minf(dimensions.x / 2048.0, dimensions.y / 900.0)
		var expected_back = Rect2((Vector2(20, 14) * factor).max(Vector2(12, 8)), (Vector2(120, 100) * factor).max(Vector2(44, 44)))
		for header in [page.canvas, page.selector]:
			var back = header.get_node("RoleBackButton")
			check(back.get_global_rect().is_equal_approx(expected_back), "main and selector use the shared role back bounds %s" % dimensions)
			check(back.get_node("Arrow").texture == WeaponPage.ROLE_NAVIGATION.BACK_TEXTURE, "main and selector use the same uncapped source arrow")
		check(page.canvas.get_global_rect().position == Vector2.ZERO, "shared source shell stays anchored to top left %s" % dimensions)
		check(bounds.encloses(page.selector_entry.get_global_rect()), "weapon switch fits viewport %s" % dimensions)
		check(bounds.encloses(page.detail_scroll.get_global_rect()), "original right detail fits viewport %s" % dimensions)
		check(page.preview.get_global_rect().end.x < page.detail_scroll.get_global_rect().position.x, "model and right detail remain separate %s" % dimensions)
		check(page.biography.get_global_rect().size.x <= page.detail_scroll.get_global_rect().size.x + 1, "source description wraps within detail %s" % dimensions)
		await _capture(viewport, page, "main", dimensions)
		page.set_selector_open(true)
		for frame in 12: await process_frame
		for button in page.action_buttons: check(bounds.encloses(button.get_global_rect()), "selector command remains inside viewport %s" % dimensions)
		await _capture(viewport, page, "selector", dimensions)
	for character_id in range(1, 8):
		for row in _rows(character_id):
			page.preview.show_model(str(row.model))
			check(page.preview.has_model and page.preview.bounds.size.length() > 0.01, "original converted weapon model has visible bounds " + str(row.weapon_id))
	viewport.remove_child(page)
	page.preview._fit()
	check(not page.preview.is_inside_tree(), "deferred preview resize safely returns after menu removal")
	page.queue_free()
	await process_frame
	viewport.size = Vector2i(1600, 900)
	var sickle_page = WeaponPage.new()
	viewport.add_child(sickle_page)
	sickle_page.size = viewport.size
	sickle_page.configure(null, _rows(2), {"catalog": catalog, "systems": systems, "character_id": 2, "selected_weapon": 202, "equipped_weapon": 201, "resources": [["material:101", "1378"]]})
	check(sickle_page.preview._effects.size() == 1 and sickle_page.selector_preview._effects.size() == 1, "Sickle main and selector replace the recovered FX surface with its original shader parameters")
	if not sickle_page.preview._effects.is_empty():
		var effect: ShaderMaterial = sickle_page.preview._effects[0]
		check(effect.get_shader_parameter("use_source_mask") and effect.get_shader_parameter("use_source_fade"), "Sickle effect retains the APK mask and fade instead of an opaque noise rectangle")
		check(effect.get_shader_parameter("source_fade_vertex_alpha"), "Sickle fade uses vertex alpha from its verified APK shader variant")
		check(effect.get_shader_parameter("source_mask") is Texture2D and effect.get_shader_parameter("source_distort") is Texture2D, "Sickle source mask and distortion textures are loaded")
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390)]:
		viewport.size = dimensions
		sickle_page.size = dimensions
		sickle_page.set_selector_open(false)
		for frame in 12: await process_frame
		await _capture(viewport, sickle_page, "sickle-main", dimensions)
		sickle_page.set_selector_open(true)
		for frame in 12: await process_frame
		await _capture(viewport, sickle_page, "sickle-selector", dimensions)
	if DisplayServer.get_name() != "headless" and not sickle_page.selector_preview._effects.is_empty():
		var effect: ShaderMaterial = sickle_page.selector_preview._effects[0]
		sickle_page.selector_preview.set_process(false)
		effect.set_shader_parameter("clock", 0.0)
		for frame in 4: await process_frame
		await RenderingServer.frame_post_draw
		var before: Image = sickle_page.selector_preview.viewport.get_texture().get_image()
		effect.set_shader_parameter("clock", 0.3)
		for frame in 4: await process_frame
		await RenderingServer.frame_post_draw
		var after: Image = sickle_page.selector_preview.viewport.get_texture().get_image()
		var animated_pixels := 0
		for y in range(0, before.get_height(), 2):
			for x in range(0, before.get_width(), 2):
				if before.get_pixel(x, y) != after.get_pixel(x, y): animated_pixels += 1
		check(animated_pixels > 10, "Recovered sickle distortion and fade visibly animate without changing the model framing")
	sickle_page.queue_free()
	await process_frame
	viewport.size = Vector2i(2048, 900)
	var eighth_page = WeaponPage.new()
	viewport.add_child(eighth_page)
	eighth_page.size = viewport.size
	eighth_page.configure(null, _rows(8), {"catalog": catalog, "systems": systems, "character_id": 8, "selected_weapon": 801, "equipped_weapon": 801, "resources": [["material:101", "1378"]]})
	check(eighth_page.weapon_buttons.size() == 5, "normal eighth character exposes all five real source weapons")
	for row in _rows(8):
		var id = int(row.weapon_id)
		eighth_page.select_weapon(id)
		for frame in 8: await process_frame
		check(eighth_page.preview.has_model, "direct APK eighth-role weapon GLB renders " + str(id))
		check(eighth_page._texture(str(row.icon), true) != null, "exact eighth-role weapon square icon loads " + str(id))
		await _capture(viewport, eighth_page, str(id), viewport.size)
	eighth_page.open_selector()
	for frame in 8: await process_frame
	await _capture(viewport, eighth_page, "eighth-selector", viewport.size)
	eighth_page.queue_free()
	await process_frame
	viewport.size = Vector2i(2460, 1080)
	var run_page = WeaponPage.new()
	viewport.add_child(run_page)
	run_page.size = viewport.size
	var run_context = {"catalog": catalog, "systems": systems, "character_id": 1, "selected_weapon": 101, "equipped_weapon": 101, "in_run": true, "partner_navigation": true, "resources": [["material:101", "1378"], ["material:102", "132"], ["loot:12101", "0/3"], ["material:108", "0"]]}
	run_page.configure(null, _rows(1, true), run_context)
	check(run_page.navigation.size() == 5 and run_page._resources.get_child_count() == 4, "run includes bag partner and all four proven resource counters")
	run_page.open_selector()
	check(run_page.action_buttons.is_empty(), "run weapon selector does not expose camp upgrade or equip commands")
	for frame in 12: await process_frame
	await _capture(viewport, run_page, "run-selector", viewport.size)
	viewport.queue_free()
	await process_frame
	systems.effects = null
	systems.decorations = null
	var result = {"passed": failures.is_empty(), "checks": checks, "failures": failures, "renderer": DisplayServer.get_name(), "viewports": [[2048, 900], [1600, 900], [844, 390], [2460, 1080]]}
	var output = FileAccess.open("res://reports/weapon-page-tests.json", FileAccess.WRITE)
	if output:
		output.store_string(JSON.stringify(result, "\t") + "\n")
		output.close()
	print("WEAPON_PAGE_TEST ", JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)

func _capture(viewport: SubViewport, page, mode: String, dimensions: Vector2i) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var picture = viewport.get_texture().get_image()
	check(not picture.is_empty(), "rendered screenshot is nonempty " + mode)
	picture.save_png("/private/tmp/weapon-%s-%dx%d.png" % [mode, dimensions.x, dimensions.y])
	var model_picture: Image = (page.selector_preview if page.selector_open else page.preview).viewport.get_texture().get_image()
	var pixels := 0
	for y in range(0, model_picture.get_height(), 4):
		for x in range(0, model_picture.get_width(), 4):
			if model_picture.get_pixel(x, y).a > 0.1: pixels += 1
	check(pixels > 50, "original real weapon renders nontransparent model pixels " + mode + str(dimensions))
	if mode.begins_with("sickle"):
		var border_pixels := 0
		for x in model_picture.get_width():
			if model_picture.get_pixel(x, 0).a > 0.1 or model_picture.get_pixel(x, model_picture.get_height() - 1).a > 0.1: border_pixels += 1
		for y in model_picture.get_height():
			if model_picture.get_pixel(0, y).a > 0.1 or model_picture.get_pixel(model_picture.get_width() - 1, y).a > 0.1: border_pixels += 1
		check(border_pixels == 0, "Sickle model and source effect stay fully inside the viewport " + mode + str(dimensions))
