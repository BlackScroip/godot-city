extends SceneTree

var checks := 0
var failures: Array[String] = []
var render_rows: Array = []
var world: DungeonWorld
var probe: FrameProbe

class FrameProbe extends Node:
	signal stepped
	var world: DungeonWorld
	var capture := false
	var full_world := false
	var samples: Array = []
	var ticks := 0
	func _physics_process(delta: float) -> void:
		if full_world: world._physics_process(delta)
		else: world.player._physics_process(delta)
		ticks += 1
		stepped.emit()
	func _process(delta: float) -> void:
		world._background = false
		var before := world._camera_focus
		world._process(delta)
		if not capture: return
		var target := world._camera_target(true)
		var raw := world._camera_target(false)
		var lookahead := world.player.locomotion.limit_length(1.0) * world.FEEL.camera_lookahead
		var expected := before.lerp(target + lookahead, 1.0 - exp(-world.FEEL.camera_response * delta))
		samples.append({"delta": delta, "fraction": Engine.get_physics_interpolation_fraction(),
			"body": world.player.position.x, "rendered": world.player.get_global_transform_interpolated().origin.x,
			"target_error": absf((target.x - raw.x) - (world.player.get_global_transform_interpolated().origin.x - world.player.global_position.x)),
			"camera_error": world._camera_focus.distance_to(expected)})

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	create_timer(45.0).timeout.connect(func(): quit(2))
	var old_cap := Engine.max_fps
	var old_physics := Engine.physics_ticks_per_second
	var old_vsync := DisplayServer.window_get_vsync_mode()
	if DisplayServer.get_name() != "headless": DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	check(bool(ProjectSettings.get_setting("physics/common/physics_interpolation", false)), "Project enables Godot physics interpolation")
	check(int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 0)) == 60, "Gameplay keeps a fixed 60 Hz physics clock")
	Engine.physics_ticks_per_second = 60
	for action in ["move_left", "move_right", "move_up", "move_down"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	world = DungeonWorld.new()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.catalog = {}
	world.auto_attack_enabled = false
	world.presentation.audio_enabled = false
	world.presentation.set_process(false)
	var combat := DungeonCombat.new()
	combat.configure(null, null, 1, 0, 541)
	world.create_player(combat, 1, Vector3(40, 0, 20))
	world.player.set_process(false)
	check(world.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF, "Render camera is independent of physics interpolation")
	check(world.player.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_ON, "The moving physics body supplies interpolated transforms")
	check(world.player.visual.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF, "Animated model keeps render-frequency facing beneath the interpolated body")
	check(world.player.get_global_transform_interpolated().origin.distance_to(world.player.global_position) < 0.001, "A distant player spawn has no interpolation streak from the origin")
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	floor_body.position.y = -0.5
	world.add_child(floor_body)
	probe = FrameProbe.new()
	probe.world = world
	root.add_child(probe)
	for cap in [30, 60, 90, 120]: await _render_rate(cap)
	probe.set_process(false)
	probe.set_physics_process(false)
	_flash_transitions()
	_render_scales()
	await _battle_scale()
	await process_frame
	probe.free()
	world.free()
	Engine.max_fps = old_cap
	Engine.physics_ticks_per_second = old_physics
	if DisplayServer.get_name() != "headless": DisplayServer.window_set_vsync_mode(old_vsync)
	var report := {"checks": checks, "failures": failures, "render_rates": render_rows,
		"display": DisplayServer.get_name(), "physics_hz": 60}
	FileAccess.open("/private/tmp/city-mobile-smoothness.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("MOBILE_SMOOTHNESS " + JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func _render_rate(cap: int) -> void:
	Engine.max_fps = cap
	probe.capture = false
	world.player.position = Vector3(40, 0.05, 20)
	world.player.get_global_transform_interpolated()
	world.player.reset_physics_interpolation()
	world.player.desired_velocity = Vector3.RIGHT * 4.0
	world.player.locomotion = world.player.desired_velocity
	world.snap_camera()
	for tick in 12: await probe.stepped
	probe.samples.clear()
	probe.capture = true
	var first_tick := probe.ticks
	var started := Time.get_ticks_usec()
	while Time.get_ticks_usec() - started < 450000: await process_frame
	probe.capture = false
	var elapsed := float(Time.get_ticks_usec() - started) / 1000000.0
	var max_camera_error := 0.0
	var max_target_error := 0.0
	var fractional_frames := 0
	var between_tick_frames := 0
	var previous: Dictionary = {}
	for sample: Dictionary in probe.samples:
		max_camera_error = maxf(max_camera_error, sample.camera_error)
		max_target_error = maxf(max_target_error, sample.target_error)
		if absf(sample.rendered - sample.body) > 0.0001: fractional_frames += 1
		if not previous.is_empty() and is_equal_approx(sample.body, previous.body) and absf(sample.rendered - previous.rendered) > 0.0001:
			between_tick_frames += 1
		previous = sample
	check(probe.samples.size() >= 8, "The real engine supplies render samples at the %d FPS cap" % cap)
	check(probe.ticks - first_tick >= 20, "Physics continues at 60 Hz with the %d FPS render cap" % cap)
	check(max_target_error < 0.0001, "Camera target uses the actual interpolated body at %d FPS" % cap)
	check(max_camera_error < 0.0001, "Camera follows the rendered pose rather than a physics-tick pose at %d FPS" % cap)
	check(fractional_frames > 0, "Godot produces interpolated positions at %d FPS" % cap)
	if cap > 60: check(between_tick_frames > 0, "The rendered target advances between physics ticks at %d FPS" % cap)
	var sample_count := probe.samples.size()
	probe.samples.clear()
	probe.set_physics_process(false)
	var destination := Vector3(120, 0.05, -60)
	world.player.desired_velocity = Vector3.ZERO
	world.player.locomotion = Vector3.ZERO
	world.player.position = destination
	world.player.reset_physics_interpolation()
	world.snap_camera()
	check(world._camera_focus.distance_to(world._camera_target()) < 0.001, "Camera snap immediately agrees with the teleported pose at %d FPS" % cap)
	# Interpolated transforms are cached once per rendered frame.
	await process_frame
	await process_frame
	check(world.player.get_global_transform_interpolated().origin.distance_to(destination) < 0.001, "Teleport resets the interpolation history at %d FPS" % cap)
	probe.set_physics_process(true)
	render_rows.append({"requested_fps": cap, "observed_fps": float(sample_count) / elapsed,
		"physics_ticks": probe.ticks - first_tick, "fractional_frames": fractional_frames,
		"between_tick_frames": between_tick_frames, "camera_error": max_camera_error, "target_error": max_target_error})

func _flash_transitions() -> void:
	var actor := world.player
	var mesh: MeshInstance3D = actor.flash_meshes[0]
	var external := StandardMaterial3D.new()
	mesh.material_overlay = external
	for frame in 20: actor._process(1.0 / 120.0)
	check(mesh.material_overlay == external, "Idle frames preserve an overlay owned by another presentation effect")
	actor.hit_flash(0.2)
	actor._process(0.01)
	check(mesh.material_overlay == actor.flash_material, "Entering hit flash assigns the flash material")
	mesh.material_overlay = external
	for frame in 5: actor._process(0.01)
	check(mesh.material_overlay == external, "A sustained flash does not repeatedly overwrite the mesh overlay")
	actor._process(0.2)
	check(mesh.material_overlay == null, "Leaving hit flash clears its overlay")
	mesh.material_overlay = external
	actor._process(0.01)
	check(mesh.material_overlay == external, "Subsequent idle frames do not keep clearing materials")
	actor.hit_flash(0.2)
	actor.suspended = true
	actor._process(1.0)
	check(mesh.material_overlay == external and is_equal_approx(actor.hurt_timer, 0.2), "Suspension preserves flash time and overlay")
	actor.suspended = false
	actor.clear_impact_state()

func _render_scales() -> void:
	check(is_equal_approx(DungeonStyle.render_scale(Vector2i(2560, 1440), 1, true), 0.625), "Default phone quality renders a 1600-pixel long 3D edge")
	check(is_equal_approx(DungeonStyle.render_scale(Vector2i(2560, 1440), 0, true), 0.5), "Reduced phone quality lowers 3D fill cost further")
	check(is_equal_approx(DungeonStyle.render_scale(Vector2i(1440, 2560), 1, true), 0.625), "Phone orientation keeps the same pixel budget")
	check(DungeonStyle.render_scale(Vector2i(2560, 1440), 2, true) == 1.0, "High phone quality keeps native 3D resolution")
	check(DungeonStyle.render_scale(Vector2i(3840, 2160), 0, false) == 1.0, "Desktop rendering keeps native resolution")
	check(DungeonStyle.render_scale(Vector2i(960, 540), 0, true) == 1.0, "Small displays are not upscaled or needlessly reduced")
	check(DungeonStyle.render_scale(Vector2i(8000, 6000), 0, true) == 0.5, "Extreme resolutions retain the minimum quality bound")

func _ticks(count: int) -> void:
	for tick in count: await probe.stepped

func _battle_scale() -> void:
	Engine.max_fps = 120
	var other := DungeonActor.new()
	other.combat = DungeonCombat.new()
	other.combat.configure_enemy(11001)
	other.combat.actor_key = "smoothness_enemy"
	world.add_child(other)
	other.position = Vector3(100, 0, 100)
	other.set_process(false)
	world.actors.append(other)
	world._actor_index[other.combat.actor_key] = other
	var shot := DungeonProjectile.new()
	shot.configure({"definition": {"raw": JSON.stringify({"EntityProperty": {"IsCheckEnvCollider": false, "IsCheckEnvUnitCollider": false},
		"MotionAnimatorType": "EMAT_Line", "MotionAnimatorProperty": {"Speed": 5.0, "MaxLifetime": 10.0}})}},
		world.player.position + Vector3.UP * 5.0, Vector3.RIGHT, Vector3.RIGHT * 500.0)
	world._add_projectile_visual(shot, world.player)
	probe.full_world = true
	Input.action_press("move_right")
	probe.set_physics_process(true)
	await _ticks(20)
	var start := world.player.position
	var shot_age := shot.age
	await _ticks(12)
	var normal_distance := start.distance_to(world.player.position)
	var normal_shot_age := shot.age - shot_age
	world._consume(world.player, {"type": "battle_time_scale", "phase": "Enter", "window": {"scale": 0.25, "duration": 10.0}})
	check(Engine.time_scale == 1.0, "Battle slow motion preserves the global UI clock")
	start = world.player.position
	shot_age = shot.age
	var player_clock: float = world.player.combat._clock
	var other_clock: float = other.combat._clock
	await _ticks(12)
	check(absf(start.distance_to(world.player.position) / maxf(normal_distance, 0.001) - 0.25) < 0.03, "Battle slow motion scales actual CharacterBody walking displacement")
	check(absf((shot.age - shot_age) / normal_shot_age - 0.25) < 0.01, "Battle slow motion scales projectile movement time")
	check(absf(world.player.combat._clock - player_clock - 0.05) < 0.001 and absf(other.combat._clock - other_clock - 0.05) < 0.001, "Both player and enemy combat clocks use battle time")
	check(world.player.simulation_scale == 0.25 and other.simulation_scale == 0.25 and world.presentation.simulation_scale == 0.25, "Actors and presentation share the active battle clock")
	world.paused = true
	var remaining: float = world._battle_scales[world.player.get_instance_id()].remaining
	await _ticks(6)
	check(world._battle_scales[world.player.get_instance_id()].remaining == remaining, "Paused play preserves source slow-motion duration")
	world.paused = false
	Input.action_release("move_right")
	probe.set_physics_process(false)
	world._consume(world.player, {"type": "battle_time_scale", "phase": "Enter", "window": {"scale": 0.8, "duration": 1.0}})
	check(world.simulation_scale == 0.8, "A unit replaces its previous slow-motion modifier")
	world._consume(other, {"type": "battle_time_scale", "phase": "Enter", "window": {"scale": 0.4, "duration": 0.25}})
	check(world.simulation_scale == 0.4, "Overlapping units select the strongest slow motion")
	world._advance_battle_scale(0.25)
	check(world.simulation_scale == 0.4, "A source window remains active exactly at zero duration")
	world._advance_battle_scale(0.001)
	check(world.simulation_scale == 0.8, "Expiry restores the remaining unit's modifier")
	world._consume(world.player, {"type": "battle_time_scale", "phase": "Exit"})
	check(world.simulation_scale == 1.0 and Engine.time_scale == 1.0, "Source exit restores battle speed without changing the UI clock")
