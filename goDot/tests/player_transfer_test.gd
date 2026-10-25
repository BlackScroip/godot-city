extends SceneTree

var checks := 0
var failures: Array[String] = []
var canvas: SubViewport
var game: Node
var completed := 0
var sounds: Array[String] = []
var captured_level := false

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("TRANSFER FAILURE: ", message)

func _wait_transition() -> void:
	var deadline := Time.get_ticks_msec() + 60000
	while game._transitioning and Time.get_ticks_msec() < deadline:
		# Automated visual checks must advance even when the editor owns desktop focus.
		game.world._background = false
		if not captured_level and game.world.player_transfer.active and game.world.player_transfer.arriving:
			captured_level = true
			game.world.set_process(false)
			game.world.player_transfer.advance(maxf(0.0, 0.35 - game.world.player_transfer.elapsed))
			game.world.player_transfer.advance(0.0, true)
			await _capture("level-arrival")
			game.world.player_transfer.advance(0.0)
			game.world.set_process(true)
		await process_frame
	check(not game._transitioning, "Transition finishes without leaving input locked")

func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	for frame in 6: await process_frame
	await RenderingServer.frame_post_draw
	var picture := canvas.get_texture().get_image()
	check(not picture.is_empty(), "Transfer renders pixels: " + label)
	var sample := picture.duplicate()
	sample.resize(64, 36)
	var colors: Dictionary = {}
	for y in sample.get_height():
		for x in sample.get_width(): colors[sample.get_pixel(x, y).to_rgba32()] = true
	check(colors.size() > 100, "Rendered scene has nonblank pixels: " + label)
	picture.save_png("/private/tmp/player-transfer-%s-%dx%d.png" % [label, canvas.size.x, canvas.size.y])

func _run() -> void:
	canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	game = load("res://scenes/main.tscn").instantiate()
	game.save_store = DungeonSaveStore.new("/private/tmp/transfer-test-%d.json" % Time.get_ticks_usec())
	canvas.add_child(game)
	game.set_process(false)
	game.world.set_process(false)
	game.world.set_physics_process(false)
	game.audio.stop()
	game.hud.close_page()
	var player: DungeonActor = game.world.player
	var transfer = game.world.player_transfer
	transfer.finished.connect(func(): completed += 1)
	transfer.sound_requested.connect(func(name): sounds.append(name))
	var body_position := player.position
	var original := player.visual.transform
	for size in [Vector2i(1600, 900), Vector2i(844, 390)]:
		canvas.size = size
		game.world.paused = true
		check(transfer.begin(player, false, game.world.presentation.media, game.world.presentation.texture_cache), "Departure starts")
		check(not transfer.begin(player, true, game.world.presentation.media, game.world.presentation.texture_cache), "Repeated activation cannot replace running transfer")
		check(is_equal_approx(transfer.duration, 2.5), "Departure retains source action duration")
		transfer.advance(0.2)
		check(sounds.slice(-2) == ["audio_fx_event_exit_room", "audio_fx_event_exit_room_2"], "Both source departure layers fire at the authored event")
		check(player.visual.position.y > original.origin.y + 0.5, "Departure lifts the player model")
		check(player.position.is_equal_approx(body_position), "Visual ascent does not change physical or saved spawn position")
		check(not player.direction_indicator.visible and player.suspended, "Transfer hides ground indicator and suspends actor")
		var age: float = transfer.elapsed
		transfer.advance(1.0, true)
		check(is_equal_approx(transfer.elapsed, age), "Background suspension freezes transfer")
		check(transfer.effect.emitters.all(func(entry): return is_zero_approx(entry.node.speed_scale)), "Background suspension freezes particle simulation")
		check(transfer.effect.emitters.size() > 0, "Recovered ascent particle layers are instantiated")
		check(transfer._media.effects["23121801_fx_other_transferrise"].textures.all(func(path): return transfer._textures.get(path) is Texture2D), "Transfer loads original material textures before rendering")
		transfer.advance(0.0)
		await _capture("rise")
		transfer.advance(0.14)
		check(not player.visual.visible, "Departure hides model at source .33 second event")
		transfer.advance(transfer.duration)
		check(not transfer.active and player.visual.transform.is_equal_approx(original) and player.visual.visible, "Departure restores model before route or loading handoff")
		check(transfer.begin(player, true, game.world.presentation.media, game.world.presentation.texture_cache, true), "Arrival starts in reduced effects mode")
		check(is_equal_approx(transfer.duration, 1.0) and not player.visual.visible, "Arrival starts hidden with source one second duration")
		check(player.visual.position.y > original.origin.y + 3.0, "Arrival begins above the spawn point")
		transfer.advance(transfer.duration * 0.35)
		check(player.visual.visible, "Arrival reveals model after the source .167 second event")
		check(is_equal_approx(transfer.effect.age, 0.525), "Arrival particles retain source 1.5 playback speed")
		check(player.visual.position.y < original.origin.y + transfer.HEIGHT, "Arrival lowers player towards the floor")
		check(transfer.effect.particle_count <= 160, "Reduced transfer obeys particle budget")
		await _capture("drop")
		transfer.advance(transfer.duration)
		check(not transfer.active and player.visual.transform.is_equal_approx(original), "Landing restores exact model transform")
		check(player.direction_indicator.visible, "Landing restores ground indicator")
	check(completed == 4, "Every completed motion emits one completion")
	var revival = game.world.player_revival
	revival.sound_requested.connect(func(name): sounds.append(name))
	check(revival.begin_action(player, "revival", game.world.presentation.media, game.world.presentation.texture_cache), "Rebirth presentation starts while gameplay is suspended")
	check(player.animation.current_animation == "common_reborn", "Rebirth uses recovered common reborn clip")
	check(revival._playing.size() == 1 and sounds.back() == "audio_fx_event_revive_1", "Rebirth starts only the symbol and first sound")
	check(revival.effect.emitters.size() > 0, "Recovered rebirth symbol has particle layers")
	revival.advance(1.19)
	check(revival._playing.size() == 1, "Rebirth explosion cannot fire before 1.2 seconds")
	revival.advance(0.02)
	check(revival._playing.size() == 2 and sounds.back() == "audio_fx_event_revive_2", "Rebirth explosion and second sound fire at 1.2 seconds")
	check(is_equal_approx(revival.effect.age, 0.01), "A long frame does not age a new explosion from action start")
	await _capture("rebirth")
	revival.advance(2.0)
	check(not revival.active and player.visual.transform.is_equal_approx(original), "Rebirth restores model and ends after original duration")
	transfer.begin(player, false, game.world.presentation.media, game.world.presentation.texture_cache)
	transfer.advance(0.5)
	transfer.cancel()
	check(not transfer.active and transfer.effect == null and player.visual.transform.is_equal_approx(original), "Environment release cancels transfer and restores model")
	game.world.set_process(true)
	game.set_process(true)
	game._primary()
	check(game.campaign.state.region_selection and game.hud.page.route_view.context.map_scope == "world" and not game._transitioning, "Camp waits on world confirmation before beginning transfer")
	var regions: Array = game.campaign.region_choices()
	check(not regions.is_empty(), "World map exposes a reachable source slot")
	if not regions.is_empty(): game._action("select_region", int(regions[0].node_id), 0)
	check(game._transitioning and transfer.active and not game.room_loading.visible, "Camp portal plays departure before showing loading")
	var seed: int = game.profile.data.run.seed
	game._action("primary", 0, 0)
	game._environment_action("transition", {})
	check(game.profile.data.run.seed == seed and game.campaign.state.phase == "route", "Input during departure cannot advance twice")
	await _wait_transition()
	check(not game.room_loading.visible and not transfer.active and game.campaign.state.phase == "room", "Loading and arrival complete before gameplay resumes")
	check(game.world.player.visual.visible, "New room player is visible after landing")
	game.world.player_transfer.begin(game.world.player, false, game.world.presentation.media, game.world.presentation.texture_cache)
	game.world.release_environment()
	check(not transfer.active and game.world.player == null, "Releasing a room clears an active transfer")
	game.queue_free()
	await process_frame
	canvas.queue_free()
	await process_frame
	print("PLAYER_TRANSFER_TEST ", JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
