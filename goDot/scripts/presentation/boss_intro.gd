extends CanvasLayer

signal finished
var active := false
var elapsed := 0.0
var duration := 3.0
var world: DungeonWorld
var actor: DungeonActor
var blocker := Control.new()
var bands: Control
var title := DungeonStyle.label("", 58)
var skip := Button.new()
var _camera_transform := Transform3D.IDENTITY
var _camera_fov := 60.0
var _animation := ""
var _animation_position := 0.0
var _animation_speed := 1.0
var _visual_transform := Transform3D.IDENTITY
var _behavior: Dictionary = {}
var _commands: Array = []
var _command_cursor := 0
var _presentation_controls: Dictionary = {}
var _sounds: Array = []
var _voices: Array[AudioStreamPlayer3D] = []

class Bands extends Control:
	var reveal := 0.0
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var slide := (1.0 - reveal) * h * 0.3
		draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h * 0.08 - slide), Vector2(0, h * 0.25 - slide)]), Color.BLACK)
		draw_colored_polygon(PackedVector2Array([Vector2(0, h * 0.1 - slide), Vector2(w, -slide), Vector2(w, 10 - slide), Vector2(0, h * 0.1 + 10 - slide)]), Color("b90f18"))
		draw_colored_polygon(PackedVector2Array([Vector2(0, h * 0.90 + slide), Vector2(w, h * 0.74 + slide), Vector2(w, h), Vector2(0, h)]), Color.BLACK)
		draw_colored_polygon(PackedVector2Array([Vector2(0, h * 0.95 + slide), Vector2(w, h * 0.80 + slide), Vector2(w, h * 0.84 + slide), Vector2(0, h * 0.99 + slide)]), Color("b90f18"))

func _ready() -> void:
	layer = 80
	blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.theme = DungeonStyle.theme()
	add_child(blocker)
	bands = Bands.new()
	bands.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bands.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blocker.add_child(bands)
	title.add_theme_color_override("font_color", Color("fa2a22"))
	title.add_theme_color_override("font_outline_color", Color("fff0e6"))
	title.add_theme_constant_override("outline_size", 5)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	blocker.add_child(title)
	skip.text = "跳过"
	skip.add_theme_font_size_override("font_size", 30)
	for state in ["normal", "hover", "pressed"]: skip.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	skip.pressed.connect(finish)
	blocker.add_child(skip)
	blocker.resized.connect(_layout)
	hide()

func begin(target_world: DungeonWorld, target: DungeonActor, name_text: String) -> void:
	if active: finish()
	world = target_world
	actor = target
	if not is_instance_valid(actor) or actor.dead: return
	if _behavior.is_empty(): _behavior = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/monster_behavior.json"))
	var config: Dictionary = _behavior.get("enemies", {}).get(str(actor.actor_id), {})
	duration = clampf(float(config.get("boss_action_time", 3.0)), 2.0, 8.0)
	var pose := str(config.get("boss_action", ""))
	if pose.is_empty(): pose = str(config.get("first_action", "born"))
	_commands = actor.combat._action(str(actor.combat.enemy.group), pose).get("events", []).filter(func(event): return bool(event.get("enabled", true)) and event.get("type", "") in ["EET_PlayAnim", "EET_PlayEffect", "EET_PlaySound", "EET_PlayVoice"])
	_commands.sort_custom(func(a, b): return float(a.time) < float(b.time))
	_command_cursor = 0
	_camera_transform = world.camera.transform
	_camera_fov = world.camera.fov
	if actor.animation:
		_animation = actor.animation.current_animation
		_animation_position = actor.animation.current_animation_position
		_animation_speed = actor.animation_state_speed
	if actor.visual: _visual_transform = actor.visual.transform
	actor.play_animation(pose, true)
	active = true
	elapsed = 0.0
	title.text = name_text
	world.paused = true
	world.intent.clear()
	if world.hud:
		world.hud.joystick._reset()
		for key in world.hud.skill_buttons: key.release()
		world.hud.attack_mode_button.release()
		_presentation_controls.clear()
		for control in [world.hud.joystick, world.hud.skill_cluster, world.hud.vitals, world.hud.primary, world.hud.navigation]:
			_presentation_controls[control] = control.visible
			control.hide()
	show()
	_layout()

func _layout() -> void:
	var s := blocker.size
	var factor := minf(1.0, minf(s.x / 1280.0, s.y / 720.0))
	title.add_theme_font_size_override("font_size", 48)
	title.scale = Vector2.ONE * factor
	title.position = Vector2(s.x * 0.12, s.y * 0.67)
	title.size = Vector2(s.x * 0.76 / maxf(factor, 0.1), 86)
	skip.scale = Vector2.ONE * factor
	skip.position = Vector2(34, 70) * factor
	skip.size = Vector2(120, 52)

func _process(delta: float) -> void:
	if not active: return
	if not is_instance_valid(actor) or actor.dead or not is_instance_valid(world):
		finish()
		return
	for voice in _voices: voice.stream_paused = world._background
	if world._background: return
	elapsed += delta
	bands.reveal = clampf(elapsed / 0.25, 0.0, 1.0) * clampf((duration - elapsed) / 0.25, 0.0, 1.0)
	bands.queue_redraw()
	title.modulate.a = bands.reveal
	if actor.animation: actor.animation.advance(delta * actor.animation_state_speed)
	while _command_cursor < _commands.size() and float(_commands[_command_cursor].time) <= elapsed:
		var command: Dictionary = _commands[_command_cursor]
		_command_cursor += 1
		if not actor.combat._conditions(command.get("conditions", []), bool(command.get("all", true))): continue
		if command.type == "EET_PlayAnim": actor.play_animation(str(command.anim), true)
		else:
			var before: int = world.presentation.spawned
			var sounds_before: int = world.presentation.sound_queue.size()
			world.presentation.command(actor, {"command": command, "sequence": -1})
			while world.presentation.sound_queue.size() > sounds_before:
				_sounds.append(world.presentation.sound_queue.pop_at(sounds_before))
			if world.presentation.spawned > before:
				world.presentation.active.back()["boss_intro_owner"] = get_instance_id()
				world.presentation.active.back().clock_sequence = -1
	# Only cosmetic events from the recovered pose advance while battle clocks stop.
	for effect in world.presentation.active:
		if effect.get("boss_intro_owner", 0) != get_instance_id(): continue
		effect.age += delta
		if effect.follow:
			var anchor = effect.follow.get_ref()
			if anchor:
				effect.root.global_position = anchor.global_position + effect.world_offset if effect.get("position_without_rotate", false) else anchor.to_global(effect.offset)
				if effect.follow_rotation: effect.root.global_basis = anchor.global_basis * effect.rotation_offset
				if float(effect.get("detach_after", 0)) > 0 and effect.age >= float(effect.detach_after):
					effect.follow = null
					effect.follow_rotation = false
		if effect.authored: effect.authored.advance(delta * float(effect.playback_speed), false, float(effect.playback_speed))
	for i in range(world.presentation.active.size() - 1, -1, -1):
		var effect = world.presentation.active[i]
		if effect.get("boss_intro_owner", 0) == get_instance_id() and effect.age >= effect.duration:
			effect.erase("boss_intro_owner")
			world.presentation._recycle(i)
	_tick_sounds(delta)
	var focus := actor.global_position + Vector3.UP * maxf(0.8, actor.impact_bounds.size.y * 0.45)
	var distance := maxf(12.0, actor.impact_bounds.size.length() * 2.8)
	var facing := actor.facing.normalized()
	var offset := (facing + Vector3.UP * 0.8 + Vector3.UP.cross(facing) * 0.25).normalized() * distance
	world.camera.global_position = focus + offset * lerpf(1.15, 1.0, clampf(elapsed / duration, 0.0, 1.0))
	world.camera.look_at(focus)
	world.camera.fov = 48
	if elapsed >= duration: finish()

func finish() -> void:
	if not active: return
	active = false
	hide()
	_sounds.clear()
	for voice in _voices:
		voice.stop()
		voice.queue_free()
	_voices.clear()
	if is_instance_valid(world) and is_instance_valid(world.camera):
		world.camera.transform = _camera_transform
		world.camera.fov = _camera_fov
		for i in range(world.presentation.active.size() - 1, -1, -1):
			var effect = world.presentation.active[i]
			if effect.get("boss_intro_owner", 0) == get_instance_id():
				effect.erase("boss_intro_owner")
				world.presentation._recycle(i)
	for control in _presentation_controls:
		if is_instance_valid(control): control.visible = _presentation_controls[control]
	_presentation_controls.clear()
	if is_instance_valid(actor):
		if actor.animation and not _animation.is_empty():
			actor.animation.play(_animation)
			actor.animation.seek(_animation_position, true)
			actor.animation_state_speed = _animation_speed
		if actor.visual: actor.visual.transform = _visual_transform
	finished.emit()

func _tick_sounds(delta: float) -> void:
	for i in range(_sounds.size() - 1, -1, -1):
		var sound: Dictionary = _sounds[i]
		sound.delay -= delta
		if sound.delay > 0: continue
		_sounds.remove_at(i)
		if not world.presentation.audio_enabled or sound.layer.get("clips", []).is_empty(): continue
		var voice: AudioStreamPlayer3D
		for candidate in _voices:
			if not candidate.playing:
				voice = candidate
				break
		if not voice and _voices.size() < 4:
			voice = AudioStreamPlayer3D.new()
			world.add_child(voice)
			_voices.append(voice)
		if not voice: continue
		var path := str(sound.layer.clips[int(sound.get("clip", 0))])
		if not ResourceLoader.exists(path): continue
		voice.stream = load(path)
		voice.position = actor.position
		voice.pitch_scale = clampf(float(sound.layer.get("pitch", 1)) * float(sound.get("pitch", 1)), 0.2, 3.0)
		voice.volume_db = linear_to_db(maxf(0.001, float(sound.layer.get("volume", 1)) * 0.65 * float(sound.get("gain", 1))))
		voice.play()

func _input(event: InputEvent) -> void:
	if not active: return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ESCAPE, KEY_SPACE, KEY_ENTER]: finish()
	if not event is InputEventMouse and not event is InputEventScreenTouch and not event is InputEventScreenDrag:
		get_viewport().set_input_as_handled()
