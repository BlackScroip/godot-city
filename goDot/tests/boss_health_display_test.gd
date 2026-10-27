extends SceneTree

const BossHealthBar = preload("res://scripts/presentation/boss_health_bar.gd")
const HealthStateBar = preload("res://scripts/presentation/health_state_bar.gd")
const Tally = preload("res://scripts/domain/battle_tally.gd")

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
	world.spawn_wave([{"enemy_id": 13001, "position": origin + Vector3(-2, 0, 3)}, {"enemy_id": 23001, "position": origin + Vector3(2, 0, 3)}, {"enemy_id": 11001, "position": origin + Vector3(0, 0, 4)}], 0, 20261027)
	for actor in world.actors: actor.suspended = true
	world.camera.position = origin + Vector3(0, 14, -12)
	world.camera.look_at(origin + Vector3(0, 0, 2))
	world.camera.size = 12
	var first: DungeonActor = world.actors[1]
	var second: DungeonActor = world.actors[2]
	var normal: DungeonActor = world.actors[3]
	var hud := DungeonHud.new()
	root.add_child(hud)
	hud.set_adventure_mode(true)
	var readout = hud.battle_readout
	readout.show()
	var boss = readout.boss
	var tally = Tally.new()
	var title := DungeonCatalog.clean(str(first.combat.enemy.name))
	readout.update_values(tally, first, title, 0)
	check(readout.bar == boss.bar and readout.boss_name == boss.name_label and readout.boss_health == boss.health_label, "Readout preserves public boss range and label aliases")
	check(boss.visible and boss.name_label.text == title, "Living boss displays its actual source name")
	check(is_equal_approx(readout.bar.value, first.combat.health) and is_equal_approx(readout.bar.max_value, first.combat.max_health), "Boss range reads actual combat HP")
	first.combat.invincible = 0
	first.combat.defense = 0
	first.combat.armor = 0
	first.combat.shield = 0
	var previous: float = first.combat.health
	first.combat.receive({"damage": first.combat.max_health * 0.39, "attack_collision": false, "definition": {}})
	readout.update_values(tally, first, title, 1.0 / 60)
	check(first.combat.health < previous and is_equal_approx(boss.bar.value, first.combat.health), "Settled combat damage reaches boss range")
	check(boss.bar.follow_fraction > boss.bar.fraction, "Boss damage leaves a source follow trail")
	check(boss.health_label.text == "%.0f/%.0f" % [first.combat.health, first.combat.max_health], "Boss numbers use source rounded format without spaces")
	_check_frame_follow()
	_check_finite_lock()
	_check_source_art()
	_check_selection(world, first, second, normal, boss, title)
	first.combat.health = first.combat.max_health * 0.61
	first.combat.shield = 0
	first.combat.add_buff("42300203")
	first.combat.add_buff("42300203")
	readout.update_values(tally, first, title, 0)
	check(is_equal_approx(first.combat.shield, first.combat.max_health * 2), "Real repeatable dragon shield buff grants two maximum-HP shields")
	check(is_equal_approx(boss.shield_fraction, 1) and is_equal_approx(boss.shield_overcap, 1), "Two maximum-HP shields fill both source shield layers")
	check(boss.shield_text.visible and boss.shield_text.text.contains("%.0f" % first.combat.shield), "Boss shield text reflects actual shield state")
	for ratio in [0.005, 0.01, 0.03, 0.05, 0.051]:
		first.combat.shield = first.combat.max_health * ratio
		readout.update_values(tally, first, title, 0)
		var expected: float = 0.05 if ratio >= 0.01 and ratio <= 0.05 else ratio
		check(is_equal_approx(boss.shield_fraction, expected), "Boss low-shield visibility floor follows source interval at ratio %.3f" % ratio)
	first.combat.shield = first.combat.max_health * 1.5
	readout.update_values(tally, first, title, 0)
	check(is_equal_approx(boss.shield_fraction, 1) and is_equal_approx(boss.shield_overcap, 0.5), "One-and-a-half shields divide between base and overcap layers")
	_install_lock(first.combat)
	readout.update_values(tally, first, title, 0)
	check(not boss.lock_active and not boss.lock_overlay.visible, "Installed but untriggered HP lock has no locked overlay")
	var saved_shield: float = first.combat.shield
	first.combat.shield = 0
	first.combat.receive({"damage": first.combat.max_health * 1000, "attack_collision": false, "definition": {}})
	first.combat.shield = saved_shield
	readout.update_values(tally, first, title, 0)
	check(is_equal_approx(first.combat.health / first.combat.max_health, 0.5) and int(first.combat.statuses["display_lock"].lock_count) > 0, "Real lethal damage activates the fixture lock before the UI reads it")
	check(boss.lock_active and boss.lock_overlay.visible, "Triggered active HP lock displays the recovered locked overlay")
	readout.update_values(tally, first, title, 0.3)
	check(boss._lock_image is NinePatchRect and boss._lock_image.patch_margin_left == 31 and boss._lock_image.patch_margin_right == 27, "Lock plate preserves the source sliced end caps")
	check(boss.bar.get_global_rect().encloses(boss.lock_overlay.get_global_rect()), "Animated lock plate stays inset within the HP frame")
	check(boss.health_label.z_index > boss.lock_overlay.z_index, "Health numbers remain above the animated lock plate")
	for elapsed in [0.0, 0.05, 0.133333, 0.2, 0.3, 0.5]:
		boss._lock_time = 0
		boss._update_lock(true, elapsed)
		var icon_rect: Rect2 = boss._lock_icon.get_global_rect()
		check(not icon_rect.intersects(boss.health_label.get_global_rect()), "Lock icon stays outside the numeric text area at %.3fs" % elapsed)
	boss._lock_time = 0
	boss._update_lock(true, 0.3)
	world._tick_damage_numbers(1.0)
	for dimensions in [Vector2i(1600, 900), Vector2i(2460, 1080), Vector2i(844, 390)]:
		root.size = dimensions
		await process_frame
		await process_frame
		readout._layout()
		readout.update_values(tally, first, title, 0)
		readout.update_enemies(world.actors, world.camera, 0)
		var visible_rect := Rect2(Vector2.ZERO, Vector2(root.get_visible_rect().size))
		check(boss.visible and visible_rect.encloses(boss.get_global_rect()), "Boss health group fits viewport %s" % dimensions)
		check(Rect2(Vector2.ZERO, boss.size).encloses(boss.name_label.get_rect()) and Rect2(Vector2.ZERO, boss.size).encloses(boss.health_label.get_rect()), "Boss labels fit their group at %s" % dimensions)
		_check_label_fit(boss.name_label, "Boss source name fits at %s" % dimensions)
		_check_label_fit(boss.health_label, "Boss numeric HP fits at %s" % dimensions)
		if graphical:
			await process_frame
			await RenderingServer.frame_post_draw
			var picture := root.get_texture().get_image()
			var path := "res://reports/boss-health-display-%dx%d.png" % [dimensions.x, dimensions.y]
			picture.save_png(path)
			images.append(path)
			var colors := {}
			for y in range(0, dimensions.y, 23):
				for x in range(0, dimensions.x, 23): colors[picture.get_pixel(x, y).to_rgba32()] = true
			check(colors.size() > 100, "Actual room and source boss artwork render a nonblank image at %s" % dimensions)
	first.combat.remove_buff("display_lock")
	readout.update_values(tally, first, title, 0)
	check(not boss.lock_active, "Removing the lock immediately clears its active display state")
	readout.update_values(tally, first, title, 0.2)
	check(not boss.lock_overlay.visible, "Removed lock overlay disappears after its source close animation")
	first.combat.shield = 0
	readout.update_values(tally, first, title, 0)
	check(is_zero_approx(boss.shield_fraction) and is_zero_approx(boss.shield_overcap) and not boss.shield_text.visible, "Depleted shield clears both layers and its number")
	if graphical:
		for dimensions in [Vector2i(1600, 900), Vector2i(2460, 1080), Vector2i(844, 390)]:
			root.size = dimensions
			await process_frame
			await process_frame
			readout._layout()
			readout.update_values(tally, first, title, 0)
			await process_frame
			await RenderingServer.frame_post_draw
			var path := "res://reports/boss-health-display-unlocked-%dx%d.png" % [dimensions.x, dimensions.y]
			root.get_texture().get_image().save_png(path)
			images.append(path)
	first.combat.health = 0.6
	readout.update_values(tally, first, title, 0)
	check(boss.health_label.text == "1/%.0f" % first.combat.max_health and boss.bar.value == 0.6, "Fractional living HP preserves real range value and native rounded number")
	first.combat.max_health = 1000000000000.0
	first.combat.health = 999999999999.2
	first.combat.shield = 1999999999999.4
	readout.update_values(tally, first, title + title + title + title, 0)
	check(boss.health_label.text == "%.0f/%.0f" % [first.combat.health, first.combat.max_health], "Large boss HP keeps native numeric formatting")
	_check_label_fit(boss.name_label, "Long boss names fit the recovered name area")
	_check_label_fit(boss.health_label, "Large boss HP fits its numeric area")
	_check_label_fit(boss.shield_text, "Large boss shield fits its numeric area")
	readout.hide()
	check(not boss.is_visible_in_tree(), "Modal parent suppression hides the complete boss group")
	readout.show()
	readout.update_values(tally, null, "", 0)
	check(not boss.visible, "Room cleanup with no target hides the boss readout")
	hud.queue_free()
	world.queue_free()
	await process_frame
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "rendered": graphical, "images": images,
		"scope": "Godot real combat damage and shield buffs, source per-frame follow, lock display state, target lifecycle and recovered sprites at three viewports. Not original APK runtime observation."}
	FileAccess.open("res://reports/boss-health-display-test.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("BOSS_HEALTH_DISPLAY ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func _check_selection(world: DungeonWorld, first: DungeonActor, second: DungeonActor, normal: DungeonActor, boss: Control, title: String) -> void:
	check(BossHealthBar.is_displayable(first) and not BossHealthBar.is_displayable(normal), "Target filter accepts living Boss rank only")
	check(BossHealthBar.select_target(world.actors) == first, "Two-boss selection starts from the first displayable target")
	for state in ["hidden", "dead", "zero", "visual"]:
		var saved_health: float = first.combat.health
		match state:
			"hidden": first.hide()
			"dead": first.dead = true
			"zero": first.combat.health = 0
			"visual": first.visual.hide()
		check(not BossHealthBar.is_displayable(first) and BossHealthBar.select_target(world.actors) == second, "Target selection skips %s first Boss" % state)
		boss.update_actor(first, title, 0)
		check(not boss.visible, "Direct update hides %s Boss" % state)
		first.show()
		first.dead = false
		first.combat.health = saved_health
		first.visual.show()
	boss.update_actor(first, title, 0)
	first.combat.health *= 0.1
	boss.update_actor(first, title, 1.0 / 60)
	second.combat.health *= 0.37
	boss.update_actor(second, DungeonCatalog.clean(str(second.combat.enemy.name)), 0)
	check(is_equal_approx(boss.bar.fraction, 0.37) and is_equal_approx(boss.bar.follow_fraction, 0.37), "Switching Boss snaps both fill and trail to the new target")
	check(boss.name_label.text == DungeonCatalog.clean(str(second.combat.enemy.name)), "Switching Boss updates the actual target name")
	check(BossHealthBar.select_target([]) == null and not BossHealthBar.is_displayable(null), "Empty and null targets cannot display Boss health")
	first.combat.health = first.combat.max_health
	second.combat.health = second.combat.max_health

func _check_frame_follow() -> void:
	var observed: Dictionary = {}
	for hz in [60, 120]:
		var bar = HealthStateBar.new()
		root.add_child(bar)
		bar.update_health(100, 100, 0)
		bar.update_health(50, 100, 0)
		check(is_equal_approx(bar.follow_fraction, 1), "Paused Boss damage does not advance its trail at %dHz" % hz)
		for frame in hz: bar.update_health(50, 100, 1.0 / hz)
		check(absf(bar.follow_fraction - (0.5 + 0.5 * pow(0.9, hz))) < 0.000001, "Boss trail uses ten-percent interpolation per rendered frame at %dHz" % hz)
		observed[hz] = bar.follow_fraction
		var before: float = bar.follow_fraction
		bar.update_health(100, 100, 0)
		check(is_equal_approx(bar.follow_fraction, before), "Paused Boss healing preserves its previous follow value at %dHz" % hz)
		bar.update_health(100, 100, 1.0 / hz)
		check(absf(bar.follow_fraction - (before + (1.0 - before) * 0.1)) < 0.000001, "Boss healing uses the same source interpolation at %dHz" % hz)
		bar.reset()
		bar.update_health(13, 100, 0)
		check(is_equal_approx(bar.fraction, 0.13) and is_equal_approx(bar.follow_fraction, 0.13), "Reset starts a new target without a stale trail at %dHz" % hz)
		bar.queue_free()
	check(float(observed[120]) < float(observed[60]), "Boss source trail retains per-frame behavior at different render rates")

func _check_finite_lock() -> void:
	var unit := DungeonCombat.new()
	check(unit.configure_enemy(11001, 61).success, "Independent finite-lock combat fixture loads")
	unit.max_health = 1000
	unit.health = 1000
	unit.defense = 0
	_install_lock(unit, 1)
	var entry: Dictionary = unit.statuses["display_lock"]
	check(int(entry.lock_count) == 0 and int(entry.lock_remaining) == 1 and not unit.enemy_health_locked(), "Untriggered finite lock has a remaining use without lighting its indicator")
	unit.receive({"damage": 10000, "attack_collision": false, "definition": {}})
	check(unit.health == 500 and int(entry.lock_remaining) == 0 and int(entry.lock_count) == 1, "Real lethal hit consumes the finite lock and records one cumulative activation")
	check(unit.enemy_health_locked(), "Exhausted finite lock remains indicated while its activated status awaits deferred removal")
	unit.tick(0)
	check(unit.enemy_health_locked(), "Zero elapsed time cannot dispose the pending activated lock")
	unit.tick(1.0 / 60)
	check(not unit.statuses.has("display_lock") and not unit.enemy_health_locked(), "Deferred next-frame removal clears the exhausted lock indicator")

func _install_lock(unit: DungeonCombat, maximum_count: int = -1) -> void:
	unit._buff_index = unit._buff_index.duplicate(true)
	unit._buff_index["display_lock"] = {"id": "display_lock", "type": "EBT_SpecialBuffLockHp", "duration": -1, "maxLayers": 1, "triggers": [], "raw_data": {"LevelSourceType": "Single", "BuffSettingDataList": [{"MinPrecent": 500, "MaxPrecent": 1000, "MaxLockCount": maximum_count}]}}
	check(unit.add_buff("display_lock"), "HP lock fixture enters the real status collection")
	unit.statuses["display_lock"]["lock_count"] = 0

func _check_label_fit(label: Label, message: String) -> void:
	var measured := label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size"))
	check(measured.x <= label.size.x, message)

func _check_source_art() -> void:
	var source: Dictionary = HealthStateBar.source("boss")
	check(not source.get("images", {}).is_empty(), "Recovered Boss sprite metadata loads")
	for path in source.get("images", {}):
		check(DungeonStyle.texture(str(source.images[path].resource)) != null, "Boss source sprite resolves: %s" % path)
