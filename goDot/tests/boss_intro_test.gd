extends SceneTree

const IDS := [13001, 13002, 23001, 23002, 33001, 33002, 43001, 52001, 52003, 53001]
const TIMES := [4.0, 4.0, 7.0, 4.0, 4.0, 4.0, 4.0, 4.0, 4.0, 5.0]
const HP := "Box_EnemyBossHpState_OnlyPlayAnim"
var checks := 0
var failures: Array[String] = []
var world: DungeonWorld
var intro: CanvasLayer
var graphical := false
var captures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _advance(seconds: float) -> void:
	var count := ceili(seconds * 60.0)
	for frame in count:
		var delta := minf(1.0 / 60.0, seconds - float(frame) / 60.0)
		world._physics_process(delta)
		for actor in world.actors:
			if is_instance_valid(actor): actor._process(delta)
		world.presentation._process(delta)
		intro._process(delta)

func _capture(name_text: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := "res://reports/boss-intro-%s.png" % name_text
	image.save_png(path)
	captures.append(path)
	var colors: Dictionary = {}
	for y in range(0, image.get_height(), 25):
		for x in range(0, image.get_width(), 25): colors[image.get_pixel(x, y).to_html()] = true
	check(colors.size() > 40, "%s renders the recovered scene and UI" % name_text)

func _run() -> void:
	graphical = DisplayServer.get_name() != "headless"
	root.size = Vector2i(1600, 900)
	world = DungeonWorld.new()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.presentation.set_process(false)
	world.presentation.audio_enabled = false
	var campaign := DungeonCampaign.new()
	campaign.configure()
	campaign.start_practice(1019101, 42)
	var room := campaign.current_room()
	var source_spawn: Dictionary = campaign.wave_spawns(1)[0]
	if graphical: world.load_environment(int(room.environment_id))
	else:
		var ground := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(1000, 1, 1000)
		collision.shape = shape
		ground.position.y = -0.5
		ground.add_child(collision)
		world.add_child(ground)
	var combat := DungeonCombat.new()
	combat.configure()
	combat.max_health = 1000000
	combat.health = combat.max_health
	world.create_player(combat, 1, room.get("player_start", {}))
	world.player.set_process(false)
	var hud := DungeonHud.new()
	root.add_child(hud)
	world.hud = hud
	hud.set_adventure_mode(true)
	intro = preload("res://scripts/presentation/boss_intro.gd").new()
	root.add_child(intro)
	intro.set_process(false)
	await process_frame
	var camera_before := world.camera.transform
	var fov_before := world.camera.fov
	var catalog: Dictionary = intro.bands.catalog
	check(catalog.apk_sha256 == "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505", "Banner is bound to the requested APK")
	check(catalog.nodes.size() == 26 and catalog.tracks.size() == 23, "Current embedded Show banner retains its complete node and animation inventory")
	for index in IDS.size():
		var id: int = IDS[index]
		var spawn := source_spawn.duplicate(true)
		spawn.enemy_id = id
		world.spawn_wave([spawn], 0, 42)
		var boss: DungeonActor = world.actors.back()
		boss.set_process(false)
		var sequence: int = boss.combat._cast_sequence
		var current: String = boss.combat.current_action
		if id == 13001:
			combat._start(combat._action("ActGroup_playerchara", str(combat.fighter.combo[0])), 0)
			for event in combat.drain_events(): world._consume(world.player, event)
			check(combat._pending.any(func(event): return event.has("hit")), "Fixture begins with a real pending player attack")
			world.intent.request(combat, 0, true)
		intro.set_skip_preference(false)
		intro.begin(world, boss, str(boss.combat.enemy.name))
		check(intro.duration == TIMES[index], "%d uses exact BossActTime" % id)
		check(not world.paused and world.boss_show_active and world.simulation_scale == 1.0, "%d locks controls without pausing battle" % id)
		check(world.camera.fov == fov_before, "%d retains the level camera projection" % id)
		check(not world.use_skill(0).success, "%d rejects player attacks during entrance" % id)
		check(combat.current_action == "sys_idle" and not combat._pending.any(func(event): return event.has("hit") and event.get("action_timeline", true)), "%d requests source player idle and cancels pending attack hits" % id)
		check(not hud.root.visible, "%d hides the complete normal HUD" % id)
		check(world.intent.pending.is_empty(), "%d clears queued player input" % id)
		check(boss.combat._cast_sequence == sequence and boss.combat.current_action == current, "%d never restarts the authored gameplay action" % id)
		var animation_before := boss.animation.current_animation_position if boss.animation else -1.0
		_advance(0.3)
		if id != 33002:
			check(boss.animation != null and boss.animation.current_animation_position != animation_before, "%d model animation advances with the actual gameplay action" % id)
		else:
			check(world.asset_path("enemies", id).is_empty(), "Unpackaged tiger model remains an explicit source gap")
		check(boss.combat.action_elapsed > 0.0, "%d real gameplay timeline advances during entrance" % id)
		check(world.player.desired_velocity == Vector3.ZERO and not world.intent.manual_attack_active(), "%d suppresses movement and automatic attacks" % id)
		if id == 13001:
			check(boss.combat.buff_layers("41300103") == 1, "BossAct initializes the phase HP lock exactly once")
			_advance(1.7)
			var title: Label = intro.bands._drawables["Box_Name/Image_Title"]
			check(title.text == str(boss.combat.enemy.name), "Recovered title receives the localized boss name")
			check(title.get_theme_color("font_shadow_color").a == 0.0 and title.get_theme_constant("outline_size") == 0, "Source title has neither inherited theme shadow nor outline")
			check(intro.bands.nodes["Box_Name/Image_Black"].is_visible_in_tree(), "Source black bands enter before the title")
			for viewport in [Vector2i(1600, 900), Vector2i(844, 390)]:
				root.size = viewport
				await process_frame
				intro._layout()
				check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(intro.skip.get_global_rect()), "Skip stays within %s" % viewport)
				if graphical: await _capture("%d-%dx%d-title" % [id, viewport.x, viewport.y])
			root.size = Vector2i(1600, 900)
			await process_frame
			intro._process(1.8)
			check(intro.bands.nodes[HP].modulate.a > 0.9, "Source HP display fades in after the name")
			check(intro.bands.nodes[HP + "/HpStateBar"].size.x > 200, "Recovered vertical layout expands the animated HP bar")
			intro._process(0.7)
			var bar: TextureProgressBar = intro.bands._drawables[HP + "/HpStateBar/Bar/BarTop_Cur"]
			check(bar.value > 0.0 and bar.value < 1.0, "Recovered HP fill animates rather than appearing full")
			if graphical: await _capture("%d-hp" % id)
			intro._process(0.55)
			check(not intro.active and intro.visible and not world.boss_show_active, "Controls resume before the independent final banner fade")
			check(hud.root.visible, "Complete normal HUD returns when controls resume")
			check(world.camera.transform.is_equal_approx(camera_before), "Normal completion restores the player camera")
			intro._process(0.6)
			check(not intro.visible, "Banner completes its full 5.6 second source curve")
		else:
			check(intro.bands.visible == (id not in [23001, 53001]), "%d observes its configured delayed banner start" % id)
			intro.skip.button_pressed = true
			check(intro.active and world.simulation_scale == 3.0, "%d source skip toggle selects 3x" % id)
			var before: float = intro.elapsed
			var idle_sequence: int = combat._cast_sequence
			intro._process(0.1)
			check(is_equal_approx(intro.elapsed - before, 0.3), "%d entrance timer uses the same accelerated battle clock" % id)
			check(combat._cast_sequence == idle_sequence, "%d toggling speed does not interrupt player idle again" % id)
			if id in [23001, 53001]:
				intro.skip.button_pressed = false
				intro._process(intro._banner_start - intro.elapsed - 0.01)
				check(not intro.bands.visible, "%d waits until the exact T-4 banner boundary" % id)
				intro._process(0.02)
				check(intro.bands.visible and is_equal_approx(intro._banner_elapsed, 0.01), "%d starts its banner at T-4" % id)
				intro._process(intro.duration - intro.elapsed + 0.001)
				check(intro.active and world.camera.transform.is_equal_approx(camera_before), "%d returns the camera at T while controls remain locked" % id)
				intro._process(0.998)
				check(intro.active, "%d retains the full final battle second" % id)
				intro._process(0.002)
				check(not intro.active and intro.visible and hud.root.visible, "%d restores controls at T+1 with the independent banner tail" % id)
			intro.finish()
		check(world.simulation_scale == 1.0 and not world.boss_show_active, "%d cleans up speed and control lock" % id)
		check(boss.combat._cast_sequence >= sequence, "%d retains gameplay state at completion" % id)
		if graphical and id in [23001, 33001, 43001, 53001]:
			intro.set_skip_preference(false)
			intro.begin(world, boss, str(boss.combat.enemy.name))
			_advance(maxf(0, intro.duration - 4.0) + 2.0)
			await _capture("%d-title" % id)
			intro.finish()
		world.clear_training_effects()
		world.presentation.clear()
		for actor in world.actors.duplicate():
			if actor.is_player: continue
			world.actors.erase(actor)
			actor.queue_free()
		await process_frame
	world.spawn_wave([source_spawn], 0, 42)
	var accelerated: DungeonActor = world.actors.back()
	accelerated.set_process(false)
	intro.set_skip_preference(true)
	world.presentation.audio_enabled = true
	intro.begin(world, accelerated, str(accelerated.combat.enemy.name))
	intro._process(0.1)
	check(intro._voices.size() == 2 and intro._voices.all(func(voice): return voice.bus == &"Effects" and voice.pitch_scale >= pow(2.0, -0.25 / 12.0) and voice.pitch_scale <= pow(2.0, 0.25 / 12.0) and voice.stream != null), "Recovered Sonity sounds use the effects bus and source quarter-semitone random pitch, independently of banner speed")
	var pitches: Array = intro._voices.map(func(voice): return voice.pitch_scale)
	world._background = true
	intro._process(1.0)
	check(is_equal_approx(intro.elapsed, 0.3) and intro._voices.all(func(voice): return voice.stream_paused), "Backgrounding suspends both accelerated entry and UI sound playback")
	world._background = false
	intro._process(0.0)
	intro.skip.button_pressed = false
	var toggle_before: float = intro.elapsed
	intro._process(0.1)
	check(world.simulation_scale == 1.0 and is_equal_approx(intro.elapsed - toggle_before, 0.1), "Untoggling skip restores normal speed during the entrance")
	intro.skip.button_pressed = true
	var live_before: float = intro.elapsed
	_advance(0.3)
	check(is_equal_approx(intro.elapsed - live_before, 0.9) and accelerated.combat.action_elapsed > 0.8, "Accelerated entrance advances the real Boss action and timer together")
	if graphical:
		_advance(0.5)
		await _capture("skip-3x")
	intro._process((intro.duration + 1.0 - intro.elapsed) / 3.0 + 0.001)
	check(not intro.active and intro.visible and world.simulation_scale == 1.0 and hud.root.visible, "Full 3x lifecycle restores controls before the banner tail")
	check(intro._voices.map(func(voice): return voice.pitch_scale) == pitches, "Control restoration preserves each sound's original pitch")
	var tail_before: float = intro._banner_elapsed
	intro._process(0.1)
	check(is_equal_approx(intro._banner_elapsed - tail_before, 0.1), "The remaining banner tail plays at normal speed")
	intro._process(0.6)
	check(not intro.visible and not intro._voices.is_empty(), "Natural accelerated banner completion lets pending source sounds finish")
	intro.finish()
	check(intro._voices.is_empty(), "Explicit cancellation releases pending UI sounds")
	hud.root.hide()
	intro.begin(world, accelerated, str(accelerated.combat.enemy.name))
	intro.finish()
	check(not hud.root.visible, "Cancellation preserves an already hidden HUD")
	hud.root.show()
	world.presentation.audio_enabled = false
	intro.set_skip_preference(false)
	world.spawn_wave([{"enemy_id": 13001}], 0, 42)
	var target: DungeonActor = world.actors.back()
	intro.begin(world, target, "狼王")
	world._background = true
	intro._process(1.0)
	check(intro.elapsed == 0.0, "Backgrounding pauses the source timer")
	world._background = false
	target.dead = true
	intro._process(0.01)
	check(not intro.active and not intro.visible and world.simulation_scale == 1 and not world.boss_show_active, "Invalid or dead targets release all presentation state")
	world.queue_free()
	hud.queue_free()
	intro.queue_free()
	await process_frame
	var report := {"checks": checks, "failures": failures, "passed": failures.is_empty(), "rendered": graphical, "bosses": IDS, "captures": captures, "source_gaps": [{"enemy_id": 33002, "asset": "myenemy_jianchihu.prefab", "reason": "Model absent from supplied APK manifest; configuration and timeline are tested."}]}
	FileAccess.open("res://reports/boss-intro-%s.json" % ("render" if graphical else "runtime"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("BOSS_INTRO ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
