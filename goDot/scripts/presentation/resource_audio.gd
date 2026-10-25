extends Node

const BINDINGS_PATH := "res://assets/data/resource_bindings.json"
const VOICE_BUDGET := 8
const AMBIENT_BUDGET := 4
const QUEUE_BUDGET := 24
const CACHE_BUDGET := 32
const STEP_DISTANCE := 1.35
const CAMP_MUSIC := ["audio_music_maincity_1", "audio_music_maincity_2", "audio_music_maincity_3"]
const REGION_MUSIC := ["audio_music_area_1", "audio_music_area_2", "audio_music_area_3", "audio_music_area_4", "audio_music_area_5"]

var enabled := true:
	set(value):
		enabled = value
		if not value: _stop_all()
var media: Dictionary = {}
var bindings: Dictionary = {}
var voices: Array[AudioStreamPlayer] = []
var ambience: Array[AudioStreamPlayer] = []
var music: AudioStreamPlayer
var music_starts := 0
var pending: Array[Dictionary] = []
var sound_cache: Dictionary = {}
var missing: Dictionary = {}
var played := 0
var footsteps := 0
var _world: DungeonWorld
var _cache_order: Array[String] = []
var _ambient_layers: Array[Dictionary] = []
var _background := false
var _serial := 0
var _region := 0
var _camp := false
var _step_distance := 0.0
var _last_position := Vector3.ZERO
var _tracked_player := 0
var _step_index := 0
var _music_context := ""
var _music_playlist: Array[String] = []
var _music_track := 0
var _music_layer: Dictionary = {}
var _music_wait := 0.0
var _music_started := false

func configure(value: Dictionary, world: DungeonWorld) -> void:
	_stop_all()
	media = value
	_world = world
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BINDINGS_PATH)) if FileAccess.file_exists(BINDINGS_PATH) else {}
	bindings = parsed if parsed is Dictionary else {}
	process_mode = Node.PROCESS_MODE_ALWAYS
	if voices.is_empty():
		for index in VOICE_BUDGET:
			var voice = AudioStreamPlayer.new()
			add_child(voice)
			voices.append(voice)
		for index in AMBIENT_BUDGET:
			var voice = AudioStreamPlayer.new()
			add_child(voice)
			ambience.append(voice)
	if music == null:
		music = AudioStreamPlayer.new()
		music.name = "Music"
		add_child(music)
		music.finished.connect(_music_finished)
	music.stop()
	music.stream = null
	_music_context = ""
	_music_playlist.clear()
	_music_layer.clear()
	_music_started = false
	_ambient_layers.clear()
	_tracked_player = 0
	_step_distance = 0.0

func play_event(event: String) -> void:
	if _blocked(): return
	var events: Dictionary = bindings.get("events", {})
	var entry: Dictionary = events.get(event, events.get("page_open", {}) if event.begins_with("page:") else {})
	if entry.is_empty(): return
	_queue_named(str(entry.get("sound", "")), bool(entry.get("pause_with_world", false)))

func play_named(name: String, pause_with_world := true) -> void:
	if not _blocked(): _queue_named(name, pause_with_world)

func play_music(region: int, camp: bool) -> void:
	var context := "camp" if camp else str(clampi(region, 1, 5))
	if context == _music_context:
		_sync_music(0.0)
		return
	_music_context = context
	_music_playlist.clear()
	if camp:
		for key in CAMP_MUSIC:
			if not _layers(key).is_empty(): _music_playlist.append(key)
	else:
		var key: String = REGION_MUSIC[int(context) - 1]
		if not _layers(key).is_empty(): _music_playlist.append(key)
	if music:
		music.stop()
		music.stream = null
	_music_track = 0
	_prepare_music_track()
	_sync_music(0.0)

func _prepare_music_track() -> void:
	_music_started = false
	_music_layer = {}
	_music_wait = 0.0
	if _music_playlist.is_empty(): return
	var layers := _layers(_music_playlist[_music_track])
	if layers.is_empty(): return
	_music_layer = layers[0]
	_music_wait = maxf(0.0, float(_music_layer.get("delay", 0)))

func _music_finished() -> void:
	if _music_playlist.is_empty(): return
	_music_track = (_music_track + 1) % _music_playlist.size()
	_prepare_music_track()
	_sync_music(0.0)

func _sync_music(delta: float) -> void:
	if music == null: return
	var paused := _blocked() or _paused()
	music.stream_paused = paused
	if paused or _music_started or _music_layer.is_empty(): return
	_music_wait -= delta
	if _music_wait > 0.0: return
	_start_voice(music, _music_layer, 0, true)
	_music_started = music.playing
	if _music_started: music_starts += 1

func enter_environment(region: int, camp: bool) -> void:
	_region = region
	_camp = camp
	_step_distance = 0.0
	_tracked_player = 0
	_step_index = 0
	# World layers cannot leak across rooms; menu and transition feedback can finish.
	for index in range(pending.size() - 1, -1, -1):
		if pending[index].world: pending.remove_at(index)
	for voice in voices:
		if voice.get_meta("world", false): voice.stop()
	for voice in ambience: voice.stop()
	_ambient_layers.clear()
	var environments: Dictionary = bindings.get("environments", {})
	var names: Array = environments.get("camp" if camp else str(region), [])
	for name in names:
		for layer in _layers(str(name)):
			if _ambient_layers.size() >= AMBIENT_BUDGET: break
			_ambient_layers.append({"layer": layer, "wait": maxf(0.0, float(layer.get("delay", 0)))})

func _queue_named(name: String, pause_with_world: bool) -> void:
	var key := name.get_file().trim_suffix(".prefab").to_lower()
	var layers := _layers(key)
	if layers.is_empty():
		if not key.is_empty(): missing[key] = true
		return
	_serial += 1
	for layer in layers.slice(0, VOICE_BUDGET):
		var clips: Array = layer.get("clips", [])
		if clips.is_empty(): continue
		if pending.size() >= QUEUE_BUDGET:
			var victim := 0
			for index in pending.size():
				if pending[index].world:
					victim = index
					break
			pending.remove_at(victim)
		pending.append({"layer": layer, "clip": (_serial - 1) % clips.size(), "delay": maxf(0.0, float(layer.get("delay", 0))), "world": pause_with_world})

func _layers(name: String) -> Array:
	var key := name.get_file().trim_suffix(".prefab").to_lower()
	return media.get("audio", {}).get(key, [])

func _blocked() -> bool:
	return not enabled or _background or (is_instance_valid(_world) and _world._background)

func _paused() -> bool:
	return (is_inside_tree() and get_tree().paused) or (is_instance_valid(_world) and _world.paused)

func _process(delta: float) -> void:
	_sync_music(delta)
	if _blocked():
		_stop_all()
		return
	var paused := _paused()
	for voice in voices: voice.stream_paused = paused and bool(voice.get_meta("world", false))
	for voice in ambience: voice.stream_paused = paused
	for index in _ambient_layers.size():
		if paused: break
		var entry := _ambient_layers[index]
		entry.wait -= delta
		if entry.wait > 0 or ambience[index].playing: continue
		_start_voice(ambience[index], entry.layer, 0, true)
	# Forward traversal preserves the order of layers sharing an authored timestamp.
	var index := 0
	while index < pending.size():
		var entry := pending[index]
		if paused and entry.world:
			index += 1
			continue
		entry.delay -= delta
		if entry.delay > 0:
			index += 1
			continue
		var voice := _event_voice(bool(entry.world))
		if voice: _start_voice(voice, entry.layer, int(entry.clip), bool(entry.world))
		pending.remove_at(index)

func _event_voice(world_sound: bool) -> AudioStreamPlayer:
	for voice in voices:
		if not voice.playing: return voice
	var oldest: AudioStreamPlayer
	for voice in voices:
		if world_sound and not voice.get_meta("world", false): continue
		if oldest == null or int(voice.get_meta("serial", 0)) < int(oldest.get_meta("serial", 0)): oldest = voice
	if oldest: oldest.stop()
	return oldest

func _start_voice(voice: AudioStreamPlayer, layer: Dictionary, clip: int, world_sound: bool) -> void:
	var clips: Array = layer.get("clips", [])
	if clips.is_empty(): return
	var path := str(clips[clip % clips.size()])
	var stream := _stream(path)
	if stream == null: return
	voice.stream = stream
	voice.pitch_scale = maxf(0.01, float(layer.get("pitch", 1)))
	voice.volume_db = linear_to_db(maxf(0.0001, float(layer.get("volume", 1))))
	voice.stream_paused = false
	voice.set_meta("world", world_sound)
	voice.set_meta("serial", played)
	voice.play()
	played += 1

func _stream(path: String) -> AudioStream:
	if sound_cache.has(path):
		_cache_order.erase(path)
		_cache_order.append(path)
		return sound_cache[path]
	if not ResourceLoader.exists(path):
		missing[path] = true
		return null
	var resource = load(path)
	if not resource is AudioStream:
		missing[path] = true
		return null
	while _cache_order.size() >= CACHE_BUDGET:
		sound_cache.erase(_cache_order.pop_front())
	sound_cache[path] = resource
	_cache_order.append(path)
	return resource

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_world) or not is_instance_valid(_world.player):
		_tracked_player = 0
		return
	var player := _world.player
	var point := player.global_position
	var identity := player.get_instance_id()
	if identity != _tracked_player:
		_tracked_player = identity
		_last_position = point
		_step_distance = 0.0
		return
	var travelled := Vector2(point.x - _last_position.x, point.z - _last_position.z).length()
	_last_position = point
	if _blocked() or _paused() or player.dead or player.suspended or player.dodge_elapsed >= 0 or player.knockback_elapsed >= 0 or player.locomotion.length_squared() < 0.1 or travelled > STEP_DISTANCE * 2.0:
		_step_distance = 0.0
		return
	_step_distance += travelled
	if _step_distance < STEP_DISTANCE: return
	_step_distance = fmod(_step_distance, STEP_DISTANCE)
	var names: Array = bindings.get("footsteps", {}).get("camp" if _camp else str(_region), [])
	if names.is_empty(): return
	_queue_named(str(names[_step_index % names.size()]), true)
	_step_index += 1
	footsteps += 1

func _stop_all() -> void:
	pending.clear()
	for voice in voices: voice.stop()
	for voice in ambience: voice.stop()
	# Music keeps its playback cursor through mute and application suspension.
	if music: music.stream_paused = true
	_step_distance = 0.0

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		_background = true
		_stop_all()
	elif what in [NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED]:
		_background = false
