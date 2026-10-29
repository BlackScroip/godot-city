extends SceneTree

const ResourceAudio = preload("res://scripts/presentation/resource_audio.gd")
var assertions := 0
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition: failures.append(message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var recovered: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/combat_presentation/catalog.json"))
	var media: Dictionary = {"audio": recovered.audio.duplicate(true)}
	var clip := str(media.audio.audio_fx_btn_click_level1[0].clips[0])
	media.audio["test_layered"] = [
		{"clips": [clip], "volume": 0.25, "pitch": 0.5, "delay": 0.1},
		{"clips": [clip], "volume": 0.5, "pitch": 1.5, "delay": 0.25}
	]
	media.audio["audio_fx_trap_ice_land_mine_trigger_delay"] = [{"clips": [clip], "volume": 0.8}]
	var source = DungeonWorld.new()
	var audio = ResourceAudio.new()
	root.add_child(audio)
	audio.configure(media, source)
	audio.set_process(false)
	audio.set_physics_process(false)
	check(audio.sound_cache.is_empty(), "Configuration does not decode the audio catalog")
	check(audio.voices.size() == 8 and audio.ambience.size() == 4 and audio.music != null, "Audio players have fixed event and ambience pools plus an independent music voice")
	for event in audio.bindings.events:
		check(media.audio.has(audio.bindings.events[event].sound), "Event %s resolves a recovered audio layer" % event)
	for section in ["environments", "footsteps"]:
		for region in audio.bindings[section]:
			for name in audio.bindings[section][region]: check(media.audio.has(name), "%s %s resolves %s" % [section, region, name])
	audio.play_named("test_layered.prefab")
	check(audio.pending.size() == 2 and audio.sound_cache.is_empty(), "Authored layers queue without eager decoding")
	audio._process(0.09)
	check(audio.played == 0 and audio.pending.size() == 2, "Authored delay prevents early playback")
	audio._process(0.02)
	check(audio.played == 1 and audio.pending.size() == 1, "First layer starts at its own timestamp")
	check(is_equal_approx(audio.voices[0].pitch_scale, 0.5) and is_equal_approx(audio.voices[0].volume_db, linear_to_db(0.25)), "Source pitch and linear volume are preserved")
	audio._process(0.15)
	check(audio.played == 2 and audio.pending.is_empty(), "Second layer keeps its independent delay")
	check(is_equal_approx(audio.voices[1].pitch_scale, 1.5), "Second layer retains its own pitch")
	check(audio.sound_cache.size() == 1, "Layers sharing a clip decode it only once")
	audio.play_named(audio.ICE_FLOOR_SOUND)
	audio.play_named(audio.ICE_FLOOR_SOUND)
	check(audio.pending.size() == 1 and is_equal_approx(audio.pending[0].layer.volume, 0.2), "Ice floor traps attenuate and coalesce simultaneous sounds")
	audio._process(audio.ICE_FLOOR_INTERVAL)
	audio.play_named(audio.ICE_FLOOR_SOUND)
	check(audio.pending.size() == 1, "Ice floor sound can play again after the interval")
	audio.enabled = false
	check(audio.pending.is_empty() and not audio.voices.any(func(voice): return voice.playing), "Muting immediately stops event voices")
	audio.play_event("ui_confirm")
	check(audio.pending.is_empty(), "Muted UI events do not accumulate")
	audio.enabled = true
	source.paused = true
	audio.play_named("test_layered")
	audio._process(1.0)
	check(audio.pending.size() == 2 and is_equal_approx(audio.pending[0].delay, 0.1), "World pause freezes delayed world audio")
	audio.play_event("ui_confirm")
	var before: int = audio.played
	audio._process(0)
	check(audio.played == before + 1 and audio.pending.size() == 2, "Menu confirmation remains audible during a modal pause")
	audio.enter_environment(3, false)
	check(audio.pending.is_empty() and audio._ambient_layers.size() == 3, "Environment change clears old world events and preserves all wind layers")
	audio._process(0.1)
	check(not audio.ambience.any(func(voice): return voice.playing), "Ambience cannot start while the world is paused")
	source.paused = false
	audio._process(0.1)
	check(audio.ambience.all(func(voice): return voice.playing) == false and audio.ambience.slice(0, 3).all(func(voice): return voice.playing), "Only the three authored wind layers occupy ambient voices")
	source.paused = true
	audio._process(0.1)
	check(audio.ambience.slice(0, 3).all(func(voice): return voice.stream_paused), "World pause pauses environment playback")
	source.paused = false
	audio._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not audio.ambience.any(func(voice): return voice.playing), "Backgrounding stops ambient audio immediately")
	audio.play_event("ui_confirm")
	check(audio.pending.is_empty(), "Background UI events are discarded")
	audio._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	audio._process(0)
	check(audio.ambience.slice(0, 3).all(func(voice): return voice.playing), "Returning to the foreground restarts only the current environment")
	source._background = true
	audio._process(0)
	check(not audio.ambience.any(func(voice): return voice.playing), "The world's background state also blocks playback")
	source._background = false
	audio.enabled = false
	audio.enter_environment(1, false)
	check(audio._ambient_layers.size() == 1, "Changing rooms while muted updates the selected environment")
	audio.enabled = true
	for index in 100: audio.play_named("test_layered")
	check(audio.pending.size() == audio.QUEUE_BUDGET, "Event bursts keep the queue bounded")
	check(audio.get_child_count() == 13, "Event bursts never allocate extra audio players")
	audio.play_event("ui_confirm")
	check(not audio.pending.back().world, "UI feedback remains admitted after a full world event queue")
	audio.enabled = false
	audio.enabled = true
	audio.play_event("page:unlisted")
	check(audio.pending.size() == media.audio.audio_ui_turnpage.size(), "An unlisted page uses the recovered page-turn sound")
	audio.enabled = false
	audio.enabled = true
	var actor = DungeonActor.new()
	root.add_child(actor)
	actor.set_physics_process(false)
	actor.is_player = true
	actor.combat = DungeonCombat.new()
	var presentation = preload("res://scripts/presentation/combat_presentation.gd").new()
	root.add_child(presentation)
	presentation.configure({})
	presentation.set_process(false)
	source.presentation = presentation
	source.player = actor
	actor.locomotion = Vector3.RIGHT
	audio._physics_process(0)
	actor.position.x += 1.4
	audio._physics_process(0.2)
	check(audio.footsteps == 0, "Small travel accumulates without an early footstep")
	actor.position.x += 1.4
	audio._physics_process(0.2)
	check(audio.footsteps == 1 and audio.pending.size() == 1, "A walking stride triggers its regional ground sound")
	check(presentation.active.size() == 1 and presentation.active[0].key == audio.STEP_EFFECT and presentation.active[0].authored != null and presentation.active[0].authored.particle_count > 0, "A walking stride emits the recovered foot-level smoke")
	check(not audio.bindings.footsteps["1"].has("audio_fx_movestep_glassdirt_02"), "Grass footsteps exclude the clip shared with bee movement")
	actor.position.x += 2.8
	audio._physics_process(0.1)
	check(audio.footsteps == 1, "High movement speed cannot exceed the minimum step interval")
	audio._physics_process(0.23)
	check(audio.footsteps == 1, "A blocked player cannot trigger a pending step without displacement")
	actor.position.x += 0.1
	audio._physics_process(0.01)
	check(audio.footsteps == 2 and presentation.active.size() == 2, "A deferred stride triggers once its minimum interval has elapsed")
	source.paused = true
	actor.position.x += 2
	audio._physics_process(0)
	check(audio.footsteps == 2, "Paused motion does not create steps")
	source.paused = false
	actor.dodge_elapsed = 0.1
	actor.position.x += 1.5
	audio._physics_process(0)
	check(audio.footsteps == 2, "A dodge does not produce walking steps")
	actor.dodge_elapsed = -1
	actor.position.x += 30
	audio._physics_process(0)
	check(audio.footsteps == 2, "A teleport displacement does not create walking steps")
	actor.suspended = true
	actor.position.x += 1.5
	audio._physics_process(0)
	check(audio.footsteps == 2, "Suspended portal motion does not create steps")
	audio.enabled = false
	actor.suspended = false
	actor.position.x += 2.8
	audio._physics_process(0.4)
	check(audio.footsteps == 3 and presentation.active.size() == 3 and audio.pending.is_empty(), "Muted audio still produces walking smoke without queueing sound")
	check(presentation.active.all(func(entry): return entry.authored.emitters.all(func(emitter): return emitter.node.material_override != null)), "Walking smoke has recovered particle materials")
	presentation.suspended = true
	presentation._process(2.0)
	check(presentation.active.size() == 3, "Pause preserves active walking smoke")
	presentation.suspended = false
	presentation._process(2.0)
	check(presentation.active.is_empty() and presentation._active_particles == 0 and presentation._active_emitters == 0, "Walking smoke expires and releases its particle budget")
	var cached: int = audio.sound_cache.size()
	audio.play_music(1, true)
	check(audio._music_playlist.size() == 3 and audio.sound_cache.size() == cached and audio.music_starts == 0, "Selecting camp music while muted records its three tracks without decoding")
	audio.enabled = true
	audio._process(0)
	check(audio.music.playing and audio.music_starts == 1, "Enabling audio starts the selected camp music")
	check(audio.music.stream == audio.sound_cache[media.audio.audio_music_maincity_1[0].clips[0]], "Camp music uses the recovered maincity track")
	check(is_equal_approx(audio.music.volume_db, linear_to_db(0.35)) and is_equal_approx(audio.music.pitch_scale, 1.0), "Music keeps its recovered volume and pitch")
	audio.music.seek(2.5)
	var cursor: float = audio.music.get_playback_position()
	audio.play_music(1, true)
	check(audio.music_starts == 1 and absf(audio.music.get_playback_position() - cursor) < 0.05, "Repeated music selection does not restart the same environment")
	source.paused = true
	audio._process(1.0)
	check(audio.music.stream_paused and absf(audio.music.get_playback_position() - cursor) < 0.05, "World pause preserves the music cursor")
	source.paused = false
	audio._process(0)
	check(not audio.music.stream_paused and audio.music_starts == 1, "Music resumes after world pause without restarting")
	audio.enabled = false
	check(audio.music.stream_paused, "Mute pauses music immediately")
	audio.enabled = true
	audio._process(0)
	check(not audio.music.stream_paused and audio.music_starts == 1, "Unmuting resumes the same music playback")
	audio._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(audio.music.stream_paused, "Application backgrounding pauses music immediately")
	audio._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	audio._process(0)
	check(not audio.music.stream_paused and audio.music_starts == 1, "Foregrounding resumes existing music playback")
	for track in [2, 3, 1]:
		audio.music.stop()
		audio.music.finished.emit()
		check(audio.music.stream == audio.sound_cache[media.audio["audio_music_maincity_%d" % track][0].clips[0]], "Camp playlist advances to recovered track %d and wraps" % track)
	for region in range(1, 6):
		audio.play_music(region, false)
		check(audio.music.stream == audio.sound_cache[media.audio["audio_music_area_%d" % region][0].clips[0]], "Region %d selects its recovered area music" % region)
		var starts: int = audio.music_starts
		audio.play_music(region, false)
		check(audio.music_starts == starts, "Repeated region %d selection keeps music playing" % region)
	audio.music.stop()
	var repeated_stream: AudioStream = audio.music.stream
	audio.music.finished.emit()
	check(audio.music.playing and audio.music.stream == repeated_stream, "Area music loops on completion")
	repeated_stream = null
	audio.enabled = false
	cached = audio.sound_cache.size()
	audio.play_music(4, false)
	check(audio.music.stream == null and audio.sound_cache.size() == cached, "Changing music while muted discards the old track without loading the next")
	audio.enabled = true
	audio._process(0)
	check(audio.music.playing and audio.music.stream == audio.sound_cache[media.audio.audio_music_area_4[0].clips[0]], "Unmuting starts the newly selected region rather than the previous song")
	var paths: Dictionary = {}
	for layers in media.audio.values():
		for layer in layers:
			for path in layer.clips: paths[path] = true
		if paths.size() > audio.CACHE_BUDGET: break
	for path in paths.keys().slice(0, audio.CACHE_BUDGET + 1): audio._stream(str(path))
	check(audio.sound_cache.size() <= audio.CACHE_BUDGET and audio._cache_order.size() <= audio.CACHE_BUDGET, "Lazy decoded stream cache evicts old entries at its fixed budget")
	check(audio.missing.is_empty(), "All exercised recovered sounds have importable streams")
	var report = {"assertions": assertions, "failures": failures, "players": audio.get_child_count(), "cache_entries": audio.sound_cache.size(), "footsteps": audio.footsteps, "events": audio.bindings.events.size()}
	FileAccess.open("res://reports/resource-audio-tests.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("RESOURCE_AUDIO ", JSON.stringify(report))
	actor.free()
	presentation.free()
	source.ground_loot.free()
	source.spirit_followers.free()
	source.player_transfer.free()
	source.player_revival.free()
	source.free()
	audio.free()
	quit(0 if failures.is_empty() else 1)
