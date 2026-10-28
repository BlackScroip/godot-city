extends SceneTree

var checks := 0
var failures: Array[String] = []
var coverage := {"characters": 0, "character_upgrades": 0, "weapons": 0, "weapon_upgrades": 0, "fashions": 0, "public_awakenings": 0, "admin_awakenings": 0}

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("CHARACTER_PROGRESSION: " + message)

func _run() -> void:
	var catalog := DungeonCatalog.new()
	check(catalog.load_all(), "Exact source catalog loads")
	var profile := DungeonProfile.new()
	var systems := DungeonSystems.new(catalog, profile)
	for id in range(1, 8): profile.data.buildings[str(id)] = 3
	for id in [101, 103, 501, 502, 503]: systems.grant_material(id, 100000000)
	for character in catalog.rows("CharData"):
		if str(character.get("available_state", "")) != "Normal": continue
		var id := int(character.id)
		if id != 1:
			var quote := systems.character_recruit_status(id)
			var before: Dictionary = profile.data.materials.duplicate(true)
			check(quote.can_recruit and systems.unlock_character(id).success, "Source character can be recruited: %d" % id)
			_verify_spending(systems, before, quote.price, "recruit %d" % id)
			check(systems.rank(profile.data.character_levels, id) == 1 and systems.stat("weapon:%d" % int(character.default_weapon)) == 1, "Recruit grants level one and its exact source default weapon: %d" % id)
			var duplicate: Dictionary = profile.data.duplicate(true)
			check(not systems.unlock_character(id).success and profile.data == duplicate, "Duplicate recruitment cannot charge again: %d" % id)
		check(systems.select_character(id).success and int(profile.data.selected_character) == id, "Every recruited character can enter the active slot: %d" % id)
		coverage.characters += 1
		for level in range(1, 15):
			var quote := systems.character_upgrade_status(id)
			var before: Dictionary = profile.data.materials.duplicate(true)
			check(quote.level == level and quote.can_upgrade and systems.upgrade_character(id).success, "Character %d level %d upgrades" % [id, level])
			_verify_spending(systems, before, quote.price, "character %d level %d" % [id, level])
			check(systems.rank(profile.data.character_levels, id) == level + 1, "Character grows exactly one level")
			coverage.character_upgrades += 1
		var maximum: Dictionary = profile.data.duplicate(true)
		check(not systems.character_upgrade_status(id).can_upgrade and not systems.upgrade_character(id).success and profile.data == maximum, "Source maximum blocks an extra upgrade: %d" % id)
		systems.set_record("character-region:%d" % id, 5)
		systems.set_record("chaos:claimed:%d" % id, systems.chaos_max_level())
	for weapon in catalog.rows("WeaponData"):
		var id := int(weapon.id)
		var character_id := id / 100
		var source_costs := DungeonCatalog.ids(weapon.unlock_mineral_mat_count)
		for level in range(systems.stat("weapon:%d" % id), source_costs.size()):
			var quote := systems.weapon_upgrade_status(id)
			var before := systems.material(103)
			check(quote.can_upgrade and systems.upgrade_weapon(id).success, "Weapon %d rank %d can craft or upgrade" % [id, level])
			check(systems.material(103) == before - source_costs[level] and systems.stat("weapon:%d" % id) == level + 1, "Weapon rank consumes its exact authored cost once")
			coverage.weapon_upgrades += 1
		var active := int(profile.data.selected_character)
		check(systems.equip_weapon(id, character_id).success and systems.equipped_weapon(character_id) == id, "All source weapons can equip on their owner: %d" % id)
		check(int(profile.data.selected_character) == active, "Equipment browsing cannot change the active character")
		var wrong := 1 if character_id != 1 else 2
		var before: Dictionary = profile.data.duplicate(true)
		check(not systems.equip_weapon(id, wrong).success and profile.data == before, "Cross-character weapon equipment is rejected: %d" % id)
		check(not systems.upgrade_weapon(id).success and profile.data == before, "Maximum weapon rank cannot spend again: %d" % id)
		coverage.weapons += 1
	var fashion_rows: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/role_character/CharaFashionConfigData.json"))
	for fashion in fashion_rows:
		var id := int(fashion.id)
		var character_id := int(fashion.chara_id)
		var quote := systems.character_fashion_status(id, character_id)
		if not quote.owned:
			var before: Dictionary = profile.data.duplicate(true)
			if not bool(fashion.get("is_cash_only_unlock", false)) and not quote.price.is_empty():
				check(quote.can_unlock and systems.unlock_character_fashion(id, character_id).success, "Every material-priced fashion can unlock: %d" % id)
				_verify_spending(systems, before.materials, quote.price, "fashion %d" % id)
			else:
				check(not quote.can_unlock and not systems.unlock_character_fashion(id, character_id).success and profile.data == before, "Platform fashion and attached variants cannot be fabricated: %d" % id)
		if systems.character_fashion_status(id, character_id).owned:
			check(systems.equip_character_fashion(id, character_id).success and int(systems.character_fashion_equipped()[str(character_id)]) == id, "Owned fashion equips on its source character: %d" % id)
			var wrong := 1 if character_id != 1 else 2
			var before: Dictionary = profile.data.duplicate(true)
			check(not systems.equip_character_fashion(id, wrong).success and profile.data == before, "Wrong-character fashion equipment is rejected")
		coverage.fashions += 1
	for node in catalog.rows("CharaTalentAwakeTreeData"):
		var id := int(node.id)
		var quote := systems.awakening_status(id)
		if bool(node.get("is_admin_mode", false)) or not bool(node.get("is_enabled", true)):
			var before: Dictionary = profile.data.duplicate(true)
			check(not quote.can_unlock and not systems.unlock_awakening(id).success and profile.data == before, "Administrative awakening stays unavailable: %d" % id)
			coverage.admin_awakenings += 1
			continue
		var before: Dictionary = profile.data.materials.duplicate(true)
		check(quote.can_unlock and systems.unlock_awakening(id).success, "Every public awakening unlocks after source progress: %d" % id)
		_verify_spending(systems, before, quote.price, "awakening %d" % id)
		check(systems.toggle_awakening(id).success and id in profile.data.active_awakenings, "Public awakening activates: %d" % id)
		check(int(node.ability_item_id) in systems.persistent_ability_ids(int(node.chara_id)), "Source awakening ability reaches the character binding: %d" % id)
		check(systems.toggle_awakening(id).success and id not in profile.data.active_awakenings and systems.stat("awake:unlocked:%d" % id) == 1, "Deactivation keeps ownership and releases points: %d" % id)
		coverage.public_awakenings += 1
	for character in catalog.rows("CharData"):
		var id := int(character.id)
		check(systems.select_character(id).success and int(profile.data.selected_weapon) == id * 100 + 5, "Switching all characters restores their individual final weapon: %d" % id)
	var store := DungeonSaveStore.new("/private/tmp/character-full-progression-%d.json" % Time.get_ticks_usec())
	check(store.save(profile.data), "All character progression writes to an isolated real save")
	var restored := DungeonProfile.new()
	check(restored.restore(store.load_profile()), "Full roster progression restores from disk")
	var restored_systems := DungeonSystems.new(catalog, restored)
	for character in catalog.rows("CharData"):
		var id := int(character.id)
		check(restored_systems.rank(restored.data.character_levels, id) == 15 and restored_systems.equipped_weapon(id) == id * 100 + 5, "Saved character levels and individual equipment restore: %d" % id)
	for weapon in catalog.rows("WeaponData"):
		check(restored_systems.stat("weapon:%d" % int(weapon.id)) == 5, "Every source weapon keeps its crafted rank after restore")
	for node in catalog.rows("CharaTalentAwakeTreeData"):
		check(restored_systems.stat("awake:unlocked:%d" % int(node.id)) == systems.stat("awake:unlocked:%d" % int(node.id)), "Every source awakening keeps its unlock record after restore")
	check(restored_systems.character_fashion_owned() == systems.character_fashion_owned() and restored_systems.character_fashion_equipped() == systems.character_fashion_equipped(), "All fashion ownership and character equipment restore")
	check(int(restored.data.selected_character) == 8 and int(restored.data.selected_weapon) == 805 and restored.data.active_awakenings.is_empty(), "Active character, weapon and deactivated awakening state restore")
	profile.data.run.active = true
	var immutable: Dictionary = profile.data.duplicate(true)
	check(not systems.select_character(1).success and not systems.equip_weapon(101, 1).success and not systems.equip_character_fashion(1001, 1).success and not systems.toggle_awakening(101).success and profile.data == immutable, "Adventure context rejects all permanent character equipment mutations")
	check(coverage.characters == 8 and coverage.character_upgrades == 112 and coverage.weapons == 40 and coverage.fashions == 45 and coverage.public_awakenings == 110 and coverage.admin_awakenings == 10, "Complete source roster and progression tables were exercised")
	await _real_recruit_flow()
	var report := {"checks": checks, "failures": failures, "coverage": coverage, "passed": failures.is_empty(), "source": "1061664.apk retained static tables; transactions and UI run in Godot with isolated saves. Chaos progress is a fixture; original APK and platform purchases are not executed."}
	var file := FileAccess.open("res://reports/character-complete-progression.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("CHARACTER_COMPLETE_PROGRESSION ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func _verify_spending(systems: DungeonSystems, before: Dictionary, price: Dictionary, label: String) -> void:
	for key in price: check(systems.material(int(key)) == int(before.get(key, 0)) - int(price[key]), "Exact material %s spending for %s" % [key, label])

func _real_recruit_flow() -> void:
	var canvas := SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var game = load("res://scenes/main.tscn").instantiate()
	game.save_store = DungeonSaveStore.new("/private/tmp/character-recruit-ui-%d.json" % Time.get_ticks_usec())
	canvas.add_child(game)
	var deadline := Time.get_ticks_msec() + 60000
	while not game.initialized and Time.get_ticks_msec() < deadline: await process_frame
	check(game.initialized, "Real game initializes for the recruitment flow")
	if not game.initialized:
		canvas.queue_free()
		await process_frame
		return
	game.set_process(false)
	game.world.set_physics_process(false)
	game.audio.stop()
	game.menus.open("characters", 8)
	game.hud.page.character_view.action_bar.get_child(0).pressed.emit()
	var dialog = game.hud.page.character_view._recruit_overlay
	check(is_instance_valid(dialog) and dialog.confirm_button.disabled and not dialog.reason_label.text.is_empty(), "Unavailable recruitment opens readable source costs and its facility reason")
	check(dialog.panel.get_node("Quote/RecruitPortrait").texture != null, "Eighth character recruitment uses its recovered source portrait")
	check(dialog.panel.get_node("Quote/RecruitDescription").text == "生命值 100\n攻击力 120\n防御力 70", "Unresolved source biography shows real character attributes")
	check(not game.hud.page.character_view.biography.visible, "Unresolved character biography does not leak a source localization key")
	var before: Dictionary = game.profile.data.duplicate(true)
	dialog.confirm_button.pressed.emit()
	check(game.profile.data == before, "A disabled recruitment confirmation cannot spend or unlock")
	game.profile.data.buildings["1"] = 1
	game.profile.data.materials["502"] = 30
	dialog.refresh()
	check(not dialog.confirm_button.disabled and dialog.material_labels[0].text == "30/30", "Recruitment quotes the eighth character's real source cost")
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390)]:
		canvas.size = dimensions
		game.hud._layout()
		for frame in 5: await process_frame
		check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(dialog.panel.get_global_rect()), "Recruit confirmation fits desktop and mobile")
		if "--render-check" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			canvas.get_texture().get_image().save_png("res://reports/character-complete-recruit-%dx%d.png" % [dimensions.x, dimensions.y])
	game.profile.data.materials["502"] = 29
	dialog.confirm_button.pressed.emit()
	check(dialog.confirm_button.disabled and game.systems.rank(game.profile.data.character_levels, 8) == 0, "Confirmation revalidates resources changed after the quote")
	game.profile.data.materials["502"] = 30
	dialog.refresh()
	dialog.confirm_button.pressed.emit()
	dialog._confirm()
	check(game.systems.rank(game.profile.data.character_levels, 8) == 1 and game.systems.material(502) == 0 and game.systems.stat("weapon:801") == 1, "Actual confirmation recruits once and grants the default weapon")
	var saved: Dictionary = game.save_store.load_profile()
	check(int(saved.character_levels.get("8", 0)) == 1 and int(saved.materials.get("502", -1)) == 0, "Real recruitment is saved immediately")
	check(game.hud.page.character_view._character_id() == 8, "Recruitment refresh retains the browsed character")
	game.hud.page.character_view.picker_button.pressed.emit()
	game.hud.page.character_view.selections[7].pressed.emit()
	check(game.selected_character == 8 and game.selected_weapon == 801, "The newly recruited character can actually enter camp with its weapon")
	game.hud.page.character_view.back_requested.emit()
	check(not game.hud.modal_open and game.world._camp_camera, "Recruitment returns to the actual camp")
	canvas.queue_free()
	await process_frame
