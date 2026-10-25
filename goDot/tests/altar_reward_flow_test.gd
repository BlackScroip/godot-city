extends SceneTree

var failures: Array[String] = []
var checks := 0
var canvas: SubViewport
var game: Node
var save_path := ""
var captures := "--capture" in OS.get_cmdline_user_args()
var capture_paths: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _new_game() -> Node:
	var instance = load("res://scenes/main.tscn").instantiate()
	instance.save_store = DungeonSaveStore.new(save_path)
	canvas.add_child(instance)
	instance.set_process(false)
	instance.world.set_process(false)
	instance.world.set_physics_process(false)
	instance.world.presentation.audio_enabled = false
	instance.audio.stop()
	return instance

func _reward(key: String) -> Dictionary:
	for reward in game.profile.data.run.rewards:
		if str(reward.key) == key: return reward
	return {}

func _source_altar(marker: String = "") -> Dictionary:
	for entry in game.world.ground_loot.source_altars:
		if marker.is_empty() or str(entry.marker_id) == marker: return entry
	return {}

func _click(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	canvas.push_input(motion, true)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = point
	press.pressed = true
	canvas.push_input(press, true)
	await process_frame
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = point
	canvas.push_input(release, true)
	await process_frame

func _resume() -> void:
	game.queue_free()
	await process_frame
	game = _new_game()
	await process_frame
	game.set_process(false)
	game.world.set_physics_process(false)
	game.hud.close_page()

func _run() -> void:
	create_timer(70).timeout.connect(func(): quit(2))
	canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	save_path = "/private/tmp/altar-reward-flow-%d.json" % Time.get_ticks_usec()
	game = _new_game()
	await process_frame
	game.hud.close_page()
	check(game.systems.begin_run(817024, game.selected_character, 100, 0).success, "Run begins for altar integration test")
	check(game.campaign.generate(817024, 0).success, "A real campaign route is generated")
	check(game.campaign.select_region(2).success, "The world map confirms the authored altar region")
	# Enter an authored battle room with a real altar in a completed room state.
	var entrance: Dictionary = game.campaign.choices()[0]
	check(game.campaign.enter(int(entrance.node_id)).success, "Authored entrance can be entered")
	game.campaign.resolve_action()
	game.campaign.complete_room()
	game.campaign.advance()
	game.campaign.state.layers[1].node_ids = [1010104]
	game.campaign._build_connections()
	check(game.campaign.enter(1010104).success, "The source LevelMap_1010104 room can be entered")
	game.campaign.state.waves_cleared = int(game.campaign.state.wave_count)
	game.campaign.complete_room()
	game._load_room()
	game.world.set_physics_process(false)
	game.world.paused = false
	game.world.fighting = false
	game.hud.close_page()
	await process_frame
	var entry := _source_altar()
	check(not entry.is_empty(), "Main flow registers an altar from the actual imported stage")
	if entry.is_empty():
		_finish()
		return
	var marker := str(entry.marker_id)
	var key := str(entry.altar)
	var altar: Node3D = entry.source_item.visual
	var egg: Node3D = entry.visual
	check(str(egg.name).begins_with("sprite_abilityitemicon_14104__u"), "Imported source egg with the real double underscore suffix is selected")
	check(entry.source_item.altar_eggs.size() > 0, "Interaction adapter recognizes the source egg for consumption")
	var source_sprite := egg.get_node_or_null("SourceAltarPickup") as Sprite3D
	check(source_sprite != null and source_sprite.texture == DungeonStyle.texture(game.world.ground_loot.ALTAR_EGG_TEXTURE), "Real source altar renders the exact APK pickup image")
	if source_sprite:
		check(source_sprite.is_visible_in_tree() and not is_zero_approx(source_sprite.global_basis.determinant()), "Source pickup renderer is visible with a nonsingular world transform")
		check(is_equal_approx(source_sprite.pixel_size, 0.01), "Source pickup retains the APK's 100 pixels per unit")
	game.world.ground_loot.sync_source_altars(game.world.interactions, game._room_key)
	entry = _source_altar(marker)
	check(egg.find_children("SourceAltarPickup", "Sprite3D", true, false).size() == 1, "Repeated source synchronization cannot duplicate the pickup image")
	game.world.player.global_position = altar.global_position + Vector3(-1.1, 0.05, 0.8)
	game.world.camera.global_position = altar.global_position + Vector3(0, 10, 7)
	game.world.camera.look_at(egg.global_position)
	game.world.ground_loot.update_altar_pointer(game.world.camera, game.world.player.global_position, true)
	await process_frame
	var target: Button = entry.pointer
	check(target.is_visible_in_tree(), "The real altar egg has a clickable target")
	await _capture("source-altar-egg")
	var inventory_before: Dictionary = game.profile.data.run.inventory.duplicate(true)
	var platform_visible := altar.visible
	await _click(target.get_global_rect().get_center())
	check(game.hud.modal_open and game.hud.page._layout == "altar", "Clicking the source egg enters the main spirit choice flow")
	await _capture("source-altar-choice")
	var reward := _reward(key)
	check(not reward.is_empty(), "Activation creates a persistent altar choice record")
	if reward.is_empty():
		_finish()
		return
	var choices: Array = reward.choices.duplicate()
	var expected_count := 3 + int(game.systems.attributes().get("BlessingPlusSelectExtraCount", 0))
	check(choices.size() == expected_count, "Spirit selection uses the APK candidate count")
	check(int(reward.pool_id) == int(game.catalog.config.AbilityItemLootPoolId_Sprites), "Fresh spirit candidates come from the source sprites pool")
	check(choices.all(func(id): return game.catalog.find("LootData", id).get("loot_type", "") in ["随从", "高级随从"]), "Every available choice is a source spirit")
	check(game.profile.data.run.inventory == inventory_before, "Activation queues a choice without silently granting an arbitrary spirit")
	check(int(game.profile.data.run.counters.get("SelectLootRemainCount_Sprites", 0)) == 1, "Activation records exactly one pending source spirit selection")
	check(entry.source_item.state.used and not egg.visible, "Source egg is consumed once when the opportunity is queued")
	check(source_sprite != null and not source_sprite.is_visible_in_tree(), "Consuming the source egg hides its recovered renderer")
	check(altar.visible == platform_visible and altar.is_visible_in_tree(), "Consuming the egg retains the source altar platform")
	var pending_count: int = game.profile.data.run.rewards.size()
	var random_step := int(game.profile.data.run.random_step)
	game.hud.close_page()
	game.world.paused = false
	check(not game.world.interactions.interact(marker).success, "The same source altar rejects a second activation")
	check(game.profile.data.run.rewards.size() == pending_count and int(game.profile.data.run.random_step) == random_step, "Rejected activation cannot duplicate or reroll the pending reward")
	check(game._save(true), "Pending selection and consumed source marker save successfully")
	await _resume()
	entry = _source_altar(marker)
	check(game.profile.data.run.active and not entry.is_empty(), "Save restore returns to the same authored altar room")
	check(_reward(key).get("choices", []) == choices, "Save restore preserves exact pending spirit choices")
	check(not entry.is_empty() and entry.source_item.state.used and not entry.visual.visible, "Save restore keeps only the source egg consumed")
	check(not entry.is_empty() and not entry.visual.get_node("SourceAltarPickup").is_visible_in_tree(), "Restored pending altar cannot show its recovered pickup renderer")
	check(not game.world.interactions.interact(marker).success and game.profile.data.run.rewards.size() == pending_count, "Restored altar cannot create an additional opportunity")
	game._rewards(key)
	check(game.hud.modal_open and game.hud.page._layout == "altar", "Saved opportunity reopens its original spirit selection")
	var spirit := int(choices[0])
	var row: Dictionary = game.catalog.find("LootData", spirit)
	var ability: Dictionary = game.catalog.find("AbilityItems", int(row.ability_item_id))
	var cap := maxi(1, int(ability.get("MaxHaveCount", 1)))
	game.profile.data.run.inventory[str(spirit)] = cap
	game._action("choose_loot", spirit, key)
	check(not _reward(key).is_empty() and int(game.profile.data.run.inventory[str(spirit)]) == cap, "A spirit at its item cap retains the pending choice and cannot overgrant")
	check(int(game.profile.data.run.counters.get("SelectLootRemainCount_Sprites", 0)) == 1, "A failed capped grant retains its pending source selection count")
	game.profile.data.run.inventory.erase(str(spirit))
	game._apply_growth()
	game._action("choose_loot", spirit, key)
	check(_reward(key).is_empty(), "Choosing one spirit consumes the pending opportunity")
	check(int(game.profile.data.run.inventory.get(str(spirit), 0)) == 1, "The chosen spirit enters the current run exactly once")
	check(int(game.profile.data.run.counters.get("SelectLootRemainCount_Sprites", 0)) == 0, "A successful spirit choice consumes one pending source selection count")
	game.world.paused = false
	game.world._physics_process(1.0 / 60.0)
	check(game.world.spirit_followers.entries.has(spirit), "The acquired spirit is installed in the active follower controller")
	if game.world.spirit_followers.entries.has(spirit):
		var follower: Dictionary = game.world.spirit_followers.entries[spirit]
		check(follower.visual.texture == DungeonStyle.texture("loot:" + str(spirit)), "The acquired follower displays its actual item image")
		var before: Vector3 = follower.position
		game.world.player.position += Vector3(3, 0, 0)
		game.world.spirit_followers.advance(0.1, game.world.player)
		check((follower.position as Vector3).distance_to(before) > 0.01, "The acquired spirit starts following the moving player")
	game.world.camera.global_position = game.world.player.global_position + Vector3(0, 10, 8)
	game.world.camera.look_at(game.world.player.global_position + Vector3(0, 0.8, 0))
	await _capture("source-altar-follower")
	game._action("choose_loot", spirit, key)
	check(int(game.profile.data.run.inventory.get(str(spirit), 0)) == 1 and _reward(key).is_empty(), "A repeated selection command cannot grant a second spirit")
	check(game._save(true), "Claimed spirit and used altar save successfully")
	await _resume()
	entry = _source_altar(marker)
	check(int(game.profile.data.run.inventory.get(str(spirit), 0)) == 1 and _reward(key).is_empty(), "Claimed spirit survives restore without recreating its reward")
	check(int(game.profile.data.run.counters.get("SelectLootRemainCount_Sprites", 0)) == 0, "Restoring a claimed altar keeps its pending selection count at zero")
	check(not entry.is_empty() and entry.source_item.state.used and not entry.visual.visible, "Claimed altar remains consumed after a second restore")
	game.world.paused = false
	game.world._physics_process(1.0 / 60.0)
	check(game.world.spirit_followers.entries.has(spirit), "Restoring the run reinstalls the acquired spirit follower")
	check(not game.world.interactions.interact(marker).success and _reward(key).is_empty(), "Restored consumed altar cannot replenish a claimed selection")
	_finish()

func _capture(label: String) -> void:
	if not captures or DisplayServer.get_name() == "headless": return
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390)]:
		canvas.size = dimensions
		await process_frame
		await process_frame
		game.world.ground_loot.update_altar_pointer(game.world.camera, game.world.player.global_position, not game.hud.modal_open)
		await RenderingServer.frame_post_draw
		var image := canvas.get_texture().get_image()
		check(not image.is_empty() and image.get_size() == dimensions, "Rendered %s has the expected %s image size" % [label, dimensions])
		if image.is_empty(): continue
		var colors: Dictionary = {}
		for x in range(0, image.get_width(), 20):
			for y in range(0, image.get_height(), 20): colors[image.get_pixel(x, y).to_html()] = true
		check(colors.size() > 20, "Rendered %s at %s has nonblank game pixels" % [label, dimensions])
		if label == "source-altar-egg": await _check_pickup_pixels(image, dimensions)
		var path := "res://reports/%s-%dx%d.png" % [label, dimensions.x, dimensions.y]
		check(image.save_png(path) == OK, "Rendered %s at %s saves successfully" % [label, dimensions])
		capture_paths.append(ProjectSettings.globalize_path(path))
	canvas.size = Vector2i(1600, 900)
	await process_frame
	await process_frame
	game.world.ground_loot.update_altar_pointer(game.world.camera, game.world.player.global_position, not game.hud.modal_open)

func _check_pickup_pixels(shown: Image, dimensions: Vector2i) -> void:
	var entry := _source_altar()
	var sprite := entry.visual.get_node("SourceAltarPickup") as Sprite3D
	var center: Vector2 = game.world.camera.unproject_position(sprite.global_position)
	var region := Rect2i(Vector2i(center) - Vector2i(60, 60), Vector2i(120, 120)).intersection(Rect2i(Vector2i.ZERO, dimensions))
	sprite.hide()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var hidden := canvas.get_texture().get_image()
	var changed := 0
	for x in range(region.position.x, region.end.x):
		for y in range(region.position.y, region.end.y):
			var before := shown.get_pixel(x, y)
			var after := hidden.get_pixel(x, y)
			if absf(before.r - after.r) + absf(before.g - after.g) + absf(before.b - after.b) > 0.08: changed += 1
	check(changed > 40, "The source pickup itself changes visible pixels at %s (%d pixels)" % [dimensions, changed])
	sprite.show()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw

func _finish() -> void:
	print("ALTAR_REWARD_FLOW_TEST ", JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty(), "display": DisplayServer.get_name(), "captures": capture_paths}))
	if is_instance_valid(canvas): canvas.queue_free()
	quit(0 if failures.is_empty() else 1)
