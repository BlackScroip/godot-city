extends SceneTree

var game: Node
var canvas: SubViewport
var failures: Array[String] = []
var captures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(55).timeout.connect(func(): quit(2))
	canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var display = TextureRect.new()
	display.texture = canvas.get_texture()
	display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(display)
	game = load("res://scenes/main.tscn").instantiate()
	game.save_store = DungeonSaveStore.new("res://reports/relic-art-visual-profile.json")
	canvas.add_child(game)
	await process_frame
	game.set_process(false)
	game.world.set_physics_process(false)
	game.hud.close_page()
	game.systems.begin_run(6243, game.selected_character, 100, 0)
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/art_generated/relics/manifest.json"))
	var samples: Array = []
	var rarities: Dictionary = {}
	for item in manifest.items:
		game.profile.data.run.inventory[str(int(item.id))] = 1
		if not rarities.has(int(item.rarity)):
			rarities[int(item.rarity)] = true
			samples.append(int(item.id))
	for dimensions in [Vector2i(1600,900), Vector2i(844,390)]:
		canvas.size = dimensions
		game.menus.open("inventory")
		for row in game.hud.page._rows:
			if not row.has("loot_id"): continue
			var expected = "res://assets/art_generated/relics/relic_%d.png" % int(row.loot_id)
			if DungeonStyle.texture(str(row.icon)).resource_path != expected:
				failures.append("Inventory image mismatch: " + str(row.loot_id))
		await capture("inventory-%dx%d" % [dimensions.x, dimensions.y])
		game.profile.data.run.rewards = [{"key":"relic-art-preview", "choices": samples.slice(0,3), "pool_id":20002}]
		game._rewards()
		await capture("rewards-%dx%d" % [dimensions.x, dimensions.y])
	canvas.size = Vector2i(1600,900)
	game.hud.close_page()
	var point = game.world.player.position
	game.world.ground_loot.clear()
	for index in samples.size():
		game.world.ground_loot.spawn(samples[index], point + Vector3((index-2)*1.2,0,1.5))
	for entry in game.world.ground_loot.entries:
		if entry.visual.texture != DungeonItemArt.ground_texture(int(entry.id)):
			failures.append("Ground image mismatch: " + str(entry.id))
	game.world.camera.position = point + game.world._camera_offset
	game.world.camera.look_at(point)
	game.hud.show_pickup(game.world.ground_loot.nearest(point), game.systems, false)
	await capture("ground")
	var report = {"passed":failures.is_empty(), "failures":failures, "captures":captures}
	var file = FileAccess.open("res://reports/relic-art-visual-tests.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	print("RELIC_ART_VISUAL ", JSON.stringify(report))
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func capture(label: String) -> void:
	for frame in 10: await process_frame
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var path = "res://reports/relic-art-" + label + ".png"
	canvas.get_texture().get_image().save_png(path)
	captures.append(path)
