extends CanvasLayer

signal finished
signal skip_changed(enabled: bool)

var active := false
var elapsed := 0.0
var duration := 4.0
var world: DungeonWorld
var actor: DungeonActor
var blocker := Control.new()
var bands = preload("res://scripts/presentation/boss_intro_banner.gd").new()
var skip := Button.new()
var _skip_check := TextureRect.new()
var _skip_label := Label.new()
var _camera_transform := Transform3D.IDENTITY
var _camera_fov := 60.0
var _behavior: Dictionary = {}
var _presentation_controls: Dictionary = {}
var _sounds: Array = []
var _voices: Array[AudioStreamPlayer] = []
var _banner_start := 0.0
var _camera_returned := false
var _speed := 1.0
var _banner_elapsed := -1.0
var _audio_cursor := 0

func _ready() -> void:
	layer = 80
	blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	blocker.theme = DungeonStyle.theme()
	blocker.clip_contents = true
	add_child(blocker)
	blocker.add_child(bands)
	skip.toggle_mode = true
	skip.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]: skip.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	var background := TextureRect.new()
	for entry in [["Background", background], ["Background/Checkmark", _skip_check], ["Text_Skip", _skip_label]]:
		var record: Dictionary = bands.catalog.skip.nodes[entry[0]]
		var control: Control = entry[1]
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var parent: Control = background if entry[0] == "Background/Checkmark" else skip
		parent.add_child(control)
		var rect: Dictionary = record.rect
		control.anchor_left = float(rect.anchor_min[0])
		control.anchor_right = float(rect.anchor_max[0])
		control.anchor_top = 1.0 - float(rect.anchor_max[1])
		control.anchor_bottom = 1.0 - float(rect.anchor_min[1])
		var extent := Vector2(float(rect.size_delta[0]), float(rect.size_delta[1]))
		var offset := Vector2(float(rect.anchored_position[0]), -float(rect.anchored_position[1])) - extent * 0.5
		control.offset_left = offset.x
		control.offset_top = offset.y
		control.offset_right = offset.x + extent.x
		control.offset_bottom = offset.y + extent.y
		if control is TextureRect:
			control.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			control.texture = load(str(record.image.texture))
	var text: Dictionary = bands.catalog.skip.nodes.Text_Skip.text
	_skip_label.add_theme_font_override("font", load(str(text.font.resource)))
	_skip_label.add_theme_font_size_override("font_size", int(text.font_size))
	_skip_label.add_theme_constant_override("outline_size", 0)
	_skip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_skip_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	skip.toggled.connect(_toggle_skip)
	blocker.add_child(skip)
	blocker.resized.connect(_layout)
	hide()

func set_skip_preference(enabled: bool) -> void:
	skip.set_pressed_no_signal(enabled)
	_skip_check.visible = enabled
	_speed = 3.0 if enabled else 1.0

func _toggle_skip(enabled: bool) -> void:
	_speed = 3.0 if enabled else 1.0
	_skip_check.visible = enabled
	if active and is_instance_valid(world): world.set_boss_show(true, _speed)
	skip_changed.emit(enabled)

func begin(target_world: DungeonWorld, target: DungeonActor, name_text: String) -> void:
	finish()
	if not is_instance_valid(target_world) or not is_instance_valid(target_world.camera) or not is_instance_valid(target) or target.dead: return
	world = target_world
	actor = target
	if _behavior.is_empty(): _behavior = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/monster_behavior.json"))
	var config: Dictionary = _behavior.get("enemies", {}).get(str(actor.actor_id), {})
	duration = float(config.get("boss_action_time", 4.0))
	_banner_start = maxf(0.0, duration - 4.0)
	_camera_transform = world.camera.transform
	_camera_fov = world.camera.fov
	_camera_returned = false
	active = true
	elapsed = 0.0
	_banner_elapsed = 0.0 if _banner_start == 0.0 else -1.0
	_audio_cursor = 0
	_speed = 3.0 if skip.button_pressed else 1.0
	world.set_boss_show(true, _speed)
	_presentation_controls.clear()
	if world.hud:
		_presentation_controls[world.hud.root] = world.hud.root.visible
		world.hud.root.hide()
	_skip_label.text = DungeonLocale.text("跳过")
	bands.set_boss_name(name_text)
	for sound in bands.catalog.audio: _sounds.append(sound)
	show()
	skip.show()
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	_layout()
	_update_camera()
	_update_banner()

func _layout() -> void:
	if bands.catalog.is_empty(): return
	var reference: Array = bands.catalog.reference_size
	var factor := minf(blocker.size.x / float(reference[0]), blocker.size.y / float(reference[1]))
	if factor <= 0.0: return
	bands.size = blocker.size / factor
	bands.scale = Vector2.ONE * factor
	var rect: Dictionary = bands.catalog.skip.nodes[""].rect
	var extent: Array = rect.size_delta
	var position_value: Array = rect.anchored_position
	skip.scale = Vector2.ONE * factor
	skip.size = Vector2(float(extent[0]), float(extent[1]))
	skip.position = (Vector2(float(position_value[0]), -float(position_value[1])) - skip.size * 0.5) * factor

func _process(delta: float) -> void:
	if not visible and _voices.is_empty(): return
	if not is_instance_valid(world):
		finish()
		return
	for voice in _voices:
		voice.stream_paused = world._background or world.paused or not world.presentation.audio_enabled
	if not visible: return
	if not is_instance_valid(actor) or actor.dead or (is_instance_valid(world.player) and world.player.dead):
		finish()
		return
	if world._background or world.paused: return
	delta = maxf(0.0, delta)
	var previous := elapsed
	if active: elapsed += delta * world.simulation_scale
	if _banner_elapsed < 0.0 and elapsed >= _banner_start:
		_banner_elapsed = maxf(0.0, elapsed - _banner_start) / maxf(0.001, world.simulation_scale) * _speed
	elif _banner_elapsed >= 0.0:
		_banner_elapsed += delta * _speed
	if active:
		_update_camera()
		if elapsed >= duration + 1.0:
			var excess := maxf(0.0, elapsed - maxf(previous, duration + 1.0)) / maxf(0.001, world.simulation_scale)
			_banner_elapsed -= excess * (_speed - 1.0)
			_resume_battle()
	_update_banner()
	_tick_sounds()
	if _banner_elapsed >= float(bands.catalog.duration) and not active:
		hide()
		_sounds.clear()

func _update_banner() -> void:
	bands.visible = _banner_elapsed >= 0.0 and _banner_elapsed < float(bands.catalog.duration)
	if bands.visible: bands.sample(_banner_elapsed)

func _update_camera() -> void:
	if elapsed >= duration:
		_restore_camera()
		return
	# ChangeFollowTarget(boss, true) keeps the level camera's existing projection.
	world.camera.position = actor.position + world._camera_offset
	world.camera.look_at(actor.global_position)
	world.camera.reset_physics_interpolation()

func _restore_camera() -> void:
	if _camera_returned: return
	_camera_returned = true
	if is_instance_valid(world) and is_instance_valid(world.camera):
		world.camera.transform = _camera_transform
		world.camera.fov = _camera_fov
		world.camera.reset_physics_interpolation()

func _resume_battle() -> void:
	if not active: return
	active = false
	_restore_camera()
	if is_instance_valid(world): world.set_boss_show(false)
	_speed = 1.0
	for control in _presentation_controls:
		if is_instance_valid(control): control.visible = _presentation_controls[control]
	_presentation_controls.clear()
	skip.hide()
	blocker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	finished.emit()

func finish() -> void:
	_resume_battle()
	hide()
	_sounds.clear()
	for voice in _voices:
		if is_instance_valid(voice):
			voice.stop()
			voice.queue_free()
	_voices.clear()

func _tick_sounds() -> void:
	while _audio_cursor < _sounds.size() and float(_sounds[_audio_cursor].start) <= _banner_elapsed:
		var source: Dictionary = _sounds[_audio_cursor]
		_audio_cursor += 1
		if not world.presentation.audio_enabled: continue
		var voice := AudioStreamPlayer.new()
		voice.bus = &"Effects"
		add_child(voice)
		voice.stream = load(str(source.resource))
		voice.volume_db = float(source.event_volume_db) + float(source.container_volume_db)
		var variation := float(source.get("pitch_random_range_semitones", 0.0)) if source.get("pitch_random_enabled", false) else 0.0
		voice.pitch_scale = pow(2.0, randf_range(-variation, variation) / 12.0)
		voice.finished.connect(func():
			_voices.erase(voice)
			voice.queue_free())
		voice.play()
		_voices.append(voice)

func _input(event: InputEvent) -> void:
	if not active: return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ESCAPE, KEY_SPACE, KEY_ENTER]:
		skip.button_pressed = not skip.button_pressed
	if not event is InputEventMouse and not event is InputEventScreenTouch and not event is InputEventScreenDrag:
		get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	_resume_battle()
