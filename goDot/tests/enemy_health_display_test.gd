extends SceneTree

const HealthBar = preload("res://scripts/presentation/enemy_health_bar.gd")
const HealthStateBar = preload("res://scripts/presentation/health_state_bar.gd")

var failures: Array[String] = []
var checks := 0
var images: Array[String] = []

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
	var normal: DungeonActor = world.actors[3]
	hud.battle_readout.update_enemies(world.actors, world.camera, 0)
	var elite_bar = overlay.bars[elite.get_instance_id()]
	check(not elite_bar.value_label.visible, "Unenhanced elite has no numeric HP caption")
	check(elite.combat.apply_enemy_enhancements([{"id": 110100020, "buff_id": "110100020", "name": "伏击"}]), "Real elite enhancement applies")
	var damage: float = elite.combat.max_health * 0.37
	elite.combat.invincible = 0
	elite.combat.defense = 0
	elite.combat.armor = 0
	elite.combat.shield = 0
	elite.combat.receive({"damage": damage, "attack_collision": false, "definition": {}})
	world._tick_damage_numbers(1.0)
	elite.combat.armor = elite.combat.max_health * 0.25
	elite.combat.shield = elite.combat.max_health * 0.7
	for dimensions in [Vector2i(1600, 900), Vector2i(2460, 1080), Vector2i(844, 390)]:
		root.size = dimensions
		await process_frame
		await process_frame
		hud.battle_readout.update_enemies(world.actors, world.camera, 0.016)
		check(overlay.bars.size() == 3, "All living normal and elite units have distinct health bars")
		var bar = overlay.bars[elite.get_instance_id()]
		check(bar.elite and bar.icon.texture != null and bar.value_label.visible, "Enhanced elite has recovered insignia and caption")
		check(not overlay.bars[normal.get_instance_id()].elite, "Normal enemy keeps compact bar")
		check(is_equal_approx(bar.fraction, elite.combat.health / elite.combat.max_health), "Fill follows settled combat damage")
		check(is_equal_approx(bar.hp_bar.value, elite.combat.health) and is_equal_approx(bar.hp_bar.max_value, elite.combat.max_health), "HP range preserves real combat values")
		check(is_equal_approx(overlay.bars[other.get_instance_id()].fraction, 1), "Same enemy ID does not share health state")
		var caption := DungeonCatalog.clean("伏击") + " " + DungeonCatalog.clean(str(elite.combat.enemy.name))
		check(bar.value_label.text == caption, "Enhanced caption joins localized enhancement and enemy names")
		check(not overlay.bars[other.get_instance_id()].value_label.visible, "Unenhanced elite does not expose numeric HP")
		check(is_equal_approx(bar.shield_fraction, 0.25) and is_equal_approx(bar.armor_bar.value, elite.combat.armor), "Floating outer bar reads armor rather than the separate shield")
		check(bar.value_label.get_theme_font("font").get_string_size(bar.value_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, bar.value_label.get_theme_font_size("font_size")).x <= bar.value_label.size.x, "Localized caption fits its fixed width at %s" % dimensions)
		for value in overlay.bars.values():
			check(value.visible and Rect2(Vector2.ZERO, Vector2(root.get_visible_rect().size)).encloses(value.get_global_rect()), "Projected bar fits viewport %s" % dimensions)
		if graphical:
			await process_frame
			await RenderingServer.frame_post_draw
			var path := "res://reports/enemy-health-%dx%d.png" % [dimensions.x, dimensions.y]
			root.get_texture().get_image().save_png(path)
			images.append(path)
	_check_frame_follow()
	_check_source_art()
	var bar = overlay.bars[elite.get_instance_id()]
	bar.update_health(0.2, 100, 20, 0)
	check(is_equal_approx(bar.fraction, 0.002) and is_equal_approx(bar.shield_fraction, 0.2), "Living fractional HP and armor remain independent")
	check(not bar.value_label.text.contains("/"), "Floating elite caption never turns into numeric HP")
	elite.combat.max_health = 1000000000000.0
	elite.combat.health = 999999999999.2
	bar.update_actor(elite.combat, 0)
	check(is_equal_approx(bar.hp_bar.value, elite.combat.health) and not bar.value_label.text.contains("999999"), "Large HP stays in the range without leaking into the caption")
	var full_caption: String = bar.value_label.text
	elite.combat.custom_properties["_enemy_enhancements"][0]["name"] = "伏击伏击伏击伏击伏击伏击伏击伏击伏击伏击"
	bar.update_actor(elite.combat, 0)
	check(bar.value_label.text.length() > full_caption.length(), "Long enhancement caption fixture reaches the display")
	check(bar.value_label.get_theme_font("font").get_string_size(bar.value_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, bar.value_label.get_theme_font_size("font_size")).x <= bar.value_label.size.x, "Long enhancement names fit the caption width")
	elite.combat.health = 0
	hud.battle_readout.update_enemies(world.actors, world.camera, 1.0 / 60)
	check(overlay.bars.has(elite.get_instance_id()) and is_equal_approx(bar.modulate.a, 0.8), "Existing zero-HP bar fades twenty percent on the first rendered death frame")
	var death_alpha: float = bar.modulate.a
	hud.battle_readout.update_enemies(world.actors, world.camera, 0)
	check(is_equal_approx(bar.modulate.a, death_alpha), "Paused death presentation preserves the current alpha")
	for frame in 5: hud.battle_readout.update_enemies(world.actors, world.camera, 1.0 / 60)
	check(is_equal_approx(bar.modulate.a, pow(0.8, 6)), "Death alpha follows the native multiplicative per-frame fade")
	death_alpha = bar.modulate.a
	check(elite.combat.revive(elite.combat.max_health * 0.5, 0), "Real combat revival restores living HP")
	hud.battle_readout.update_enemies(world.actors, world.camera, 1.0 / 60)
	check(is_equal_approx(bar.modulate.a, death_alpha + (1.0 - death_alpha) * 0.2), "Revival fades the same tracked bar back toward full alpha")
	world.actors.erase(elite)
	hud.battle_readout.update_enemies(world.actors, world.camera, 0)
	check(not overlay.bars.has(elite.get_instance_id()), "Removing the actor recycles its fading health bar")
	other.hide()
	hud.battle_readout.update_enemies(world.actors, world.camera, 0.016)
	check(not overlay.bars.has(other.get_instance_id()), "Hidden unit has no floating health bar")
	other.show()
	other.visual.hide()
	hud.battle_readout.update_enemies(world.actors, world.camera, 0)
	check(not overlay.bars.has(other.get_instance_id()), "Hidden visual removes its floating health bar")
	other.visual.show()
	other.dead = true
	hud.battle_readout.update_enemies(world.actors, world.camera, 0)
	check(not overlay.bars.has(other.get_instance_id()), "Already-dead actor does not create a new bar even with positive HP")
	other.dead = false
	hud.battle_readout.update_enemies(world.actors, world.camera, 0)
	check(overlay.bars.has(other.get_instance_id()), "Restored living actor receives a fresh bar")
	overlay.update_actors([], world.camera, 0)
	check(overlay.bars.is_empty(), "Room cleanup removes every tracked bar")
	hud.queue_free()
	world.queue_free()
	await process_frame
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "rendered": graphical, "images": images,
		"scope": "Godot combat HP, armor and real enhancement state; source per-frame trail, death alpha interpolation, pause and revival, actor cleanup and recovered sprites at three viewports. Not original APK runtime observation."}
	FileAccess.open("res://reports/enemy-health-display-test.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("ENEMY_HEALTH_DISPLAY ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func _check_frame_follow() -> void:
	var observed: Dictionary = {}
	for hz in [60, 120]:
		var bar = HealthBar.new()
		root.add_child(bar)
		bar.update_health(100, 100, 0, 0)
		bar.update_health(50, 100, 0, 0)
		check(is_equal_approx(bar.follow_fraction, 1), "Paused damage updates fill without advancing trail at %dHz" % hz)
		for frame in hz: bar.update_health(50, 100, 0, 1.0 / hz)
		var expected := 0.5 + 0.5 * pow(0.9, hz)
		check(absf(bar.follow_fraction - expected) < 0.000001, "Damage trail follows native ten-percent per-frame formula at %dHz" % hz)
		observed[hz] = bar.follow_fraction
		var before: float = bar.follow_fraction
		bar.update_health(100, 100, 0, 0)
		check(is_equal_approx(bar.follow_fraction, before), "Paused healing preserves the trail at %dHz" % hz)
		bar.update_health(100, 100, 0, 1.0 / hz)
		check(absf(bar.follow_fraction - (before + (1.0 - before) * 0.1)) < 0.000001, "Healing also follows ten-percent per-frame rather than snapping at %dHz" % hz)
		bar.queue_free()
	check(float(observed[120]) < float(observed[60]), "One second at 120 rendered frames advances further than 60 source frames")

func _check_source_art() -> void:
	for kind in ["normal", "elite"]:
		var source: Dictionary = HealthStateBar.source(kind)
		check(not source.get("images", {}).is_empty(), "%s source sprite metadata loads" % kind)
		for path in source.get("images", {}):
			var resource := str(source.images[path].resource)
			check(DungeonStyle.texture(resource) != null, "%s source sprite resolves: %s" % [kind, path])
