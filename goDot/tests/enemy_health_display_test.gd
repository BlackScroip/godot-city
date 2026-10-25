extends SceneTree

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _run() -> void:
	var graphical := DisplayServer.get_name() != "headless"
	var world := DungeonWorld.new()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.presentation.set_process(false)
	world.presentation.audio_enabled = false
	if graphical: world.load_environment(1010101)
	var origin := world.vector(world.environment_entry.get("player_start", {})) if graphical else Vector3.ZERO
	var player_combat := DungeonCombat.new()
	player_combat.configure()
	world.create_player(player_combat, 1, origin)
	world.spawn_wave([{"enemy_id": 12001, "position": origin + Vector3(-2, 0, 2)}, {"enemy_id": 12001, "position": origin + Vector3(2, 0, 2)}, {"enemy_id": 11001, "position": origin + Vector3(0, 0, 4)}], 0, 481)
	for actor in world.actors: actor.suspended = true
	world.camera.position = origin + Vector3(0, 14, -12)
	world.camera.look_at(origin + Vector3(0, 0, 2))
	world.camera.size = 12
	var hud := DungeonHud.new()
	root.add_child(hud)
	hud.set_adventure_mode(true)
	hud.battle_readout.show()
	var overlay = hud.battle_readout.enemy_health
	var elite: DungeonActor = world.actors[1]
	var other: DungeonActor = world.actors[2]
	for dimensions in [Vector2i(1600, 900), Vector2i(2460, 1080), Vector2i(844, 390)]:
		root.size = dimensions
		await process_frame
		await process_frame
		hud.battle_readout.update_enemies(world.actors, world.camera, 0.016)
		check(overlay.bars.size() == 3, "All living normal and elite units have distinct health bars")
		var bar = overlay.bars[elite.get_instance_id()]
		check(bar.elite and bar.icon.texture != null and bar.value_label.visible, "Elite has recovered insignia and numeric HP")
		check(not overlay.bars[world.actors[3].get_instance_id()].elite, "Normal enemy keeps compact bar")
		elite.combat.health = elite.combat.max_health * 0.63
		hud.battle_readout.update_enemies(world.actors, world.camera, 0.016)
		check(is_equal_approx(bar.fraction, 0.63), "Fill follows actual current/max HP")
		check(is_equal_approx(overlay.bars[other.get_instance_id()].fraction, 1), "Same enemy ID does not share health state")
		check(bar.value_label.text == "%d / %d" % [ceili(elite.combat.health), ceili(elite.combat.max_health)], "Displayed HP matches combat state")
		for value in overlay.bars.values():
			check(value.visible and Rect2(Vector2.ZERO, Vector2(root.get_visible_rect().size)).encloses(value.get_global_rect()), "Projected bar fits viewport %s" % dimensions)
		if graphical:
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://reports/enemy-health-%dx%d.png" % [dimensions.x, dimensions.y])
	var bar = overlay.bars[elite.get_instance_id()]
	bar.update_health(50, 100, 20, 0.01)
	check(bar.follow_fraction > bar.fraction and is_equal_approx(bar.shield_fraction, 0.2), "Damage trail and shield use separate fractions")
	bar.update_health(50, 100, 0, 1)
	check(is_equal_approx(bar.follow_fraction, 0.5), "Damage trail settles to current HP")
	bar.update_health(0.2, 100, 0, 0)
	check(bar.value_label.text == "1 / 100", "Living fractional HP never displays zero")
	elite.combat.health = 0
	hud.battle_readout.update_enemies(world.actors, world.camera, 0.016)
	check(not overlay.bars.has(elite.get_instance_id()), "Zero HP removes bar immediately before death animation")
	other.hide()
	hud.battle_readout.update_enemies(world.actors, world.camera, 0.016)
	check(not overlay.bars.has(other.get_instance_id()), "Hidden unit has no floating health bar")
	overlay.update_actors([], world.camera, 0)
	check(overlay.bars.is_empty(), "Room cleanup removes every tracked bar")
	hud.queue_free()
	world.queue_free()
	await process_frame
	print("ENEMY_HEALTH_DISPLAY ", JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures, "rendered": graphical}))
	quit(0 if failures.is_empty() else 1)
