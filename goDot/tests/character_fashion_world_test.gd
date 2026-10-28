extends "res://tests/room_activity_flow_test.gd"

const Models = preload("res://scripts/presentation/character_fashion_models.gd")
var equipped_count := 0
var room_count := 0

func _run() -> void:
	create_timer(180).timeout.connect(func(): quit(2))
	canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	game = load("res://scenes/main.tscn").instantiate()
	game.save_store = DungeonSaveStore.new("/private/tmp/character-fashion-world-%d.json" % Time.get_ticks_usec())
	canvas.add_child(game)
	game.set_process(false)
	game.world.set_physics_process(false)
	game.world.presentation.audio_enabled = false
	game.audio.stop()
	var source: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/role_character/CharaFashionConfigData.json"))
	# Ownership here is a rendering fixture; payment and unlock gates have separate tests.
	game.profile.data["fashion_owned"] = source.map(func(row): return int(row.id))
	for character_id in range(1, 9):
		game.profile.data.character_levels[str(character_id)] = 1
		game.systems.set_record("weapon:%d" % (character_id * 100 + 1), 1)
	for character_id in range(1, 9):
		game._action("select_character", character_id, 0)
		check(game.world.player.actor_id == character_id, "Actual camp switches to character %d" % character_id)
		var rows: Array = source.filter(func(row): return int(row.chara_id) == character_id)
		for row in rows:
			var id := int(row.id)
			var actor: DungeonActor = game.world.player
			var combat_id := actor.combat.get_instance_id()
			var position := actor.position
			actor.facing = Vector3.LEFT
			game._action("op:equip_character_fashion", id, character_id)
			await process_frame
			_check_actor(id, "camp")
			check(actor == game.world.player and actor.combat.get_instance_id() == combat_id and actor.position.is_equal_approx(position), "Equipping fashion %d preserves the live actor and combat state" % id)
			if id != character_id * 1000 + 1:
				check(is_equal_approx(actor.visual.rotation.y, atan2(actor.facing.x, actor.facing.z)), "Fashion replacement preserves facing %d" % id)
			var saved: Dictionary = game.save_store.load_profile()
			check(int(saved.get("fashion_equipped", {}).get(str(character_id), character_id * 1000 + 1)) == id, "Equipped fashion %d is saved immediately" % id)
			var visual_id := actor.visual.get_instance_id()
			game._action("op:equip_character_fashion", id, character_id)
			check(actor.visual.get_instance_id() == visual_id, "Repeated equip does not rebuild the current fashion %d" % id)
			equipped_count += 1
		var active_visual: int = game.world.player.visual.get_instance_id()
		var other := 2 if character_id == 1 else 1
		game._action("op:equip_character_fashion", other * 1000 + 2, other)
		check(game.world.player.actor_id == character_id and game.world.player.visual.get_instance_id() == active_visual, "Equipping a browsed character leaves the active model intact")
		game._close_page()
		if character_id in [1, 8]: await _capture("fashion-camp-%d" % character_id)
		game.profile.data = game.save_store.load_profile()
		game._restore_flow()
		await _wait()
		var equipped := int(game.systems.character_fashion_equipped()[str(character_id)])
		_check_actor(equipped, "camp reload")
		game.systems.begin_run(20261028, character_id, 100, 0)
		var rooms: Array = game.campaign.database.Nodes.filter(func(node): return str(node.Flow) == "Rest")
		check(not rooms.is_empty() and game.campaign.start_practice(int(rooms[0].Id), 20261028).success, "A source room starts for character %d" % character_id)
		game._load_room()
		await _wait()
		_check_actor(equipped, "adventure")
		game._save(true)
		game.profile.data = game.save_store.load_profile()
		game._restore_flow()
		await _wait()
		_check_actor(equipped, "adventure reload")
		room_count += 1
		var run_visual: int = game.world.player.visual.get_instance_id()
		game._action("op:equip_character_fashion", character_id * 1000 + 1, character_id)
		check(game.world.player.visual.get_instance_id() == run_visual and int(game.systems.character_fashion_equipped()[str(character_id)]) == equipped, "Adventure cannot mutate permanent equipment")
		if character_id == 8:
			game._close_page()
			await _capture("fashion-adventure-8")
		game.profile.data.run = DungeonProfile.new_run()
		game._camp()
		await process_frame
	check(equipped_count == 45 and room_count == 8, "All 45 fashions equip in camp and all eight characters retain them in rooms")
	game.queue_free()
	await process_frame
	var report := {"checks": checks, "failures": failures, "passed": failures.is_empty(), "equipped_fashions": equipped_count, "adventure_characters": room_count, "captures": captures, "scope": "Actual Godot UI commands, camp and room actors, source weapon sockets, animation bindings and disk-save restoration. Ownership is a test fixture, including paid appearances; no payment entitlement is granted by production code."}
	var file := FileAccess.open("res://reports/character-fashion-world-20261028.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("CHARACTER_FASHION_WORLD ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func _check_actor(fashion_id: int, location: String) -> void:
	var actor: DungeonActor = game.world.player
	var context := "%s/%d" % [location, fashion_id]
	check(actor.visual_loaded and actor.visual.scene_file_path == Models.path_for(fashion_id), "The actual player uses its equipped source scene: " + context)
	check(is_instance_valid(actor.weapon) and actor.visual.is_ancestor_of(actor.weapon), "Weapon attaches to the replacement model skeleton: " + context)
	if is_instance_valid(actor.weapon):
		check(actor.weapon.scene_file_path == game.world.asset_path("weapons", game.selected_weapon), "The selected weapon remains unchanged: " + context)
	check(actor.animation != null and not actor.animations.is_empty(), "Equipped model keeps source animations: " + context)
	if actor.animation:
		actor.play_animation("idle", true)
		check(not actor.animation.current_animation.is_empty(), "Equipped model can play idle: " + context)
		actor.play_animation("attack", true)
		check("attack" in str(actor.animation.current_animation).to_lower() or "atk" in str(actor.animation.current_animation).to_lower(), "Equipped model can play a source attack: " + context)
		actor.play_animation("idle", true)

func _wait() -> void:
	var focus_guard := func():
		if is_instance_valid(game) and is_instance_valid(game.world): game.world._background = false
	process_frame.connect(focus_guard)
	await super._wait()
	process_frame.disconnect(focus_guard)
