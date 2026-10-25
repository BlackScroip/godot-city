extends Node3D

signal finished
signal sound_requested(name: String)

const AUTHORED = preload("res://scripts/presentation/authored_effect.gd")
const SOURCE_PATH := "res://assets/data/player_lifecycle.json"
static var _source: Dictionary = {}
var active := false
var elapsed := 0.0
var duration := 0.0
var action := ""
var effect: Node3D
var _actor: DungeonActor
var _visual_transform := Transform3D.IDENTITY
var _visual_visible := true
var _source_visible := true
var _indicator_visible := true
var _was_suspended := false
var _events: Array = []
var _next_event := 0
var _effects: Dictionary = {}
var _playing: Array[Dictionary] = []
var _media: Dictionary
var _textures: Dictionary
var _low_quality := false

static func definition(key: String) -> Dictionary:
	if _source.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_PATH))
		if parsed is Dictionary: _source = parsed
	return _source.get("actions", {}).get(key, {})

func begin_action(actor: DungeonActor, key: String, media: Dictionary, textures: Dictionary, low_quality := false) -> bool:
	if active or not is_instance_valid(actor) or not is_instance_valid(actor.visual): return false
	var source := definition(key)
	if source.is_empty(): return false
	_stop_effects()
	_actor = actor
	action = key
	elapsed = 0.0
	duration = float(source.duration)
	_visual_transform = actor.visual.transform
	_visual_visible = actor.visual.visible
	_source_visible = true
	_indicator_visible = actor.direction_indicator.visible if actor.direction_indicator else false
	_was_suspended = actor.suspended
	_media = media
	_textures = textures
	_low_quality = low_quality
	actor.suspended = true
	actor.desired_velocity = Vector3.ZERO
	actor.locomotion = Vector3.ZERO
	actor.velocity = Vector3.ZERO
	actor.clear_impact_state()
	actor.end_action_motion()
	if actor.direction_indicator: actor.direction_indicator.hide()
	_events = source.get("events", []).filter(func(event): return bool(event.get("enabled", true)) and actor.combat._conditions(event.get("conditions", []), bool(event.get("all", true))))
	_events.sort_custom(func(a, b): return float(a.time) < float(b.time) if not is_equal_approx(float(a.time), float(b.time)) else int(a.index) < int(b.index))
	_next_event = 0
	# Missing weapon-specific clips use a local transfer pose; source events stay intact.
	actor.play_animation("reborn" if key == "revival" else "transfer", true)
	active = true
	_dispatch_due()
	_apply_motion()
	return true

func advance(delta: float, stopped := false) -> void:
	if stopped:
		_advance_effects(0.0, true)
		return
	if active and (not is_instance_valid(_actor) or not is_instance_valid(_actor.visual)):
		cancel()
		return
	if not active:
		_advance_effects(delta)
		return
	var end := minf(elapsed + maxf(0.0, delta), duration)
	while _next_event < _events.size() and float(_events[_next_event].time) <= end:
		_advance_segment(maxf(0.0, float(_events[_next_event].time) - elapsed))
		_dispatch_due()
	_advance_segment(maxf(0.0, end - elapsed))
	_apply_motion()
	if elapsed >= duration:
		_restore_actor()
		active = false
		finished.emit()

func _advance_segment(delta: float) -> void:
	_advance_effects(delta)
	if _actor.animation: _actor.animation.advance(delta)
	elapsed += delta

func _advance_effects(delta: float, stopped := false) -> void:
	for entry in _playing.duplicate():
		entry.node.advance(delta * float(entry.speed), stopped, float(entry.speed))
		if entry.node.age >= entry.node.lifetime:
			entry.node.stop()
			_playing.erase(entry)

func _dispatch_due() -> void:
	while _next_event < _events.size() and float(_events[_next_event].time) <= elapsed + 0.00001:
		var event: Dictionary = _events[_next_event]
		_next_event += 1
		if event.has("anim"):
			var name := str(event.anim).replace("@", "_")
			if _actor.animation and _actor.animation.has_animation(name):
				_actor.play_animation(name, true)
				_actor.animation.advance(0.0)
		elif event.has("effect"):
			_start_effect(event)
		elif event.has("sound"):
			sound_requested.emit(str(event.sound))
		elif event.has("visible"):
			_source_visible = bool(event.visible)

func _start_effect(event: Dictionary) -> void:
	var address := str(event.effect)
	var key := address + (":low" if _low_quality else ":full")
	if not _effects.has(key):
		var instance = AUTHORED.new()
		var source: Dictionary = _media.get("effects", {}).get(address, {})
		for path in source.get("textures", []):
			if not _textures.has(path) and ResourceLoader.exists(str(path)): _textures[path] = load(str(path))
		instance.configure(source, _low_quality, _textures)
		add_child(instance)
		_effects[key] = instance
	effect = _effects[key]
	effect.global_position = _actor.global_position
	if event.get("anchor", "") == "Unit_Center": effect.global_position.y += 0.85
	effect.restart()
	_playing.append({"node": effect, "speed": float(event.get("speed", 1.0))})

func _apply_motion() -> void:
	_actor.visual.visible = _visual_visible and _source_visible

func _restore_actor() -> void:
	if not is_instance_valid(_actor): return
	if is_instance_valid(_actor.visual):
		_actor.visual.transform = _visual_transform
		_actor.visual.visible = _visual_visible
	if _actor.direction_indicator: _actor.direction_indicator.visible = _indicator_visible
	_actor.suspended = _was_suspended
	_actor.play_animation("idle", true)
	if _actor.animation: _actor.animation.advance(0.0)
	_actor = null

func _stop_effects() -> void:
	for entry in _playing: entry.node.stop()
	_playing.clear()
	effect = null

func cancel() -> void:
	var was_active := active
	_restore_actor()
	active = false
	_stop_effects()
	_events.clear()
	if was_active: finished.emit()
