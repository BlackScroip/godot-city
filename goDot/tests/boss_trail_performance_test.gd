extends SceneTree

const Presentation = preload("res://scripts/presentation/combat_presentation.gd")
const FIRE_TRAIL := "24122501_fx_enemy_feimolong_firewindbuff_trail"
const FIRE_ORDINARY := ["24122501_fx_enemy_feimolong_firewindbuff_behind", "24122501_fx_enemy_feimolong_firewindbuff_front"]
const WARMUP_FRAMES := 120
const SAMPLE_FRAMES := 240
const SAMPLES := 7

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _output_path() -> String:
	for value in OS.get_cmdline_user_args():
		if value.begins_with("--output="): return value.trim_prefix("--output=")
	return "/private/tmp/boss-trail-performance.json"

func _flush(presentation: Node3D) -> void:
	var frames := 0
	while presentation.has_pending_preparation() or not presentation._boss_embedded_queue.is_empty():
		presentation._process(1.0 / 60.0)
		frames += 1
		if frames > 10000:
			_check(false, "Boss effect preparation finishes")
			return
		await process_frame

func _trails(presentation: Node3D, dragon: DungeonActor) -> Array:
	var result: Array = []
	for effect in presentation._boss_embedded_live.get(dragon.get_instance_id(), {}).values():
		for trail in effect.get("active_boss_trails", []): result.append(trail)
	return result

func _move(trails: Array, camera: Camera3D, step: float, camera_step: float) -> void:
	for trail in trails:
		trail._owner.position.x += step
	if camera_step != 0.0: camera.rotate_y(camera_step)

func _vertices(trail) -> int:
	if trail._mesh.get_surface_count() == 0: return 0
	var arrays: Array = trail._mesh.surface_get_arrays(0)
	return arrays[Mesh.ARRAY_VERTEX].size()

func _run_case(trails: Array, camera: Camera3D, scenario: Dictionary, low: bool) -> Dictionary:
	var positions: Array[Vector3] = []
	for trail in trails: positions.append(trail._owner.position)
	var all_frames: Array[int] = []
	var sample_means: Array[float] = []
	var max_points := 0
	var max_vertices := 0
	var delta: float = scenario.delta
	var step: float = scenario.step
	var camera_step: float = scenario.camera_step
	for sample in SAMPLES:
		camera.rotation = Vector3.ZERO
		for index in trails.size():
			trails[index]._owner.position = positions[index]
			trails[index].restart()
		for frame in WARMUP_FRAMES:
			_move(trails, camera, step, camera_step)
			for trail in trails: trail.advance(delta)
		var total_usec := 0
		for frame in SAMPLE_FRAMES:
			_move(trails, camera, step, camera_step)
			var started := Time.get_ticks_usec()
			for trail in trails: trail.advance(delta)
			var elapsed := Time.get_ticks_usec() - started
			total_usec += elapsed
			all_frames.append(elapsed)
		for frame in 4:
			_move(trails, camera, step, camera_step)
			for trail in trails:
				trail.advance(delta)
				max_points = maxi(max_points, trail._points.size())
				max_vertices = maxi(max_vertices, _vertices(trail))
		sample_means.append(float(total_usec) / SAMPLE_FRAMES)
	all_frames.sort()
	sample_means.sort()
	var cap := 16 if low else 24
	_check(max_points <= cap, "%s %s respects point cap" % [scenario.name, low])
	_check(max_vertices <= (cap + 1) * 2, "%s %s respects vertex cap including the current head" % [scenario.name, low])
	if scenario.name == "saturated":
		_check(max_points == cap, "Saturated %s mode reaches its point cap" % low)
	if step > 0:
		_check(max_vertices >= 6, "%s %s produces nonempty mesh geometry" % [scenario.name, low])
	return {"scenario": scenario.name, "low_quality": low, "delta_seconds": delta,
		"translation_per_frame": step, "camera_rotation_per_frame_radians": camera_step,
		"frames_per_sample": SAMPLE_FRAMES, "samples": SAMPLES,
		"median_sample_mean_usec_per_frame": sample_means[SAMPLES / 2],
		"median_frame_usec": all_frames[all_frames.size() / 2],
		"p95_frame_usec": all_frames[int(floor((all_frames.size() - 1) * 0.95))],
		"point_cap_per_trail": cap, "max_points_at_sample_end": max_points,
		"vertex_cap_per_trail": (cap + 1) * 2, "max_vertices_at_sample_end": max_vertices}

func _pressure(presentation: Node3D, dragon: DungeonActor, low: bool) -> Dictionary:
	var budget: int = presentation.FEEL.low_effect_budget if low else presentation.FEEL.effect_budget
	var particle_budget: int = presentation.FEEL.low_particle_budget if low else presentation.FEEL.particle_budget
	var emitter_budget: int = presentation.FEEL.low_emitter_budget if low else presentation.FEEL.emitter_budget
	var before_particles: int = presentation._active_particles
	var before_emitters: int = presentation._active_emitters
	for index in budget:
		presentation.emit_effect(dragon, "trail_budget_fixture_missing", Vector3.ZERO, Vector3.ONE, INF, null, true, -1, true)
	_check(presentation.active.size() == budget, "Protected effects fill the %s mode effect budget" % low)
	_check(_trails(presentation, dragon).is_empty(), "Budget pressure evicts the six cosmetic trails in %s mode" % low)
	var spawned_at_pressure: int = presentation.spawned
	for frame in 180: presentation._process(1.0 / 60.0)
	_check(presentation.active.size() == budget and _trails(presentation, dragon).is_empty(), "Trails remain evicted while %s mode is fully protected" % low)
	_check(presentation.spawned == spawned_at_pressure, "Blocked trails do not churn under %s mode pressure" % low)
	_check(presentation._active_particles <= particle_budget and presentation._active_emitters <= emitter_budget, "%s mode stays within particle and emitter limits" % low)
	for index in 2: presentation._recycle(presentation.active.size() - 1)
	for frame in 180: presentation._process(1.0 / 60.0)
	var partial_trails := _trails(presentation, dragon).size()
	_check(partial_trails == 2 and presentation.active.size() == budget, "Two available %s mode slots recover two trails" % low)
	var spawned_at_partial: int = presentation.spawned
	for frame in 180: presentation._process(1.0 / 60.0)
	_check(_trails(presentation, dragon).size() == 2 and presentation.spawned == spawned_at_partial, "Partial %s mode recovery remains stable without churn" % low)
	while not presentation.active.is_empty(): presentation._recycle(presentation.active.size() - 1)
	for frame in 180: presentation._process(1.0 / 60.0)
	var recovered := _trails(presentation, dragon).size()
	_check(recovered == 6, "All six trails recover after %s mode budget pressure clears" % low)
	_check(presentation.active.size() <= budget and presentation._active_particles <= particle_budget and presentation._active_emitters <= emitter_budget, "Recovered %s mode stays within shared budgets" % low)
	return {"low_quality": low, "effect_budget": budget, "particle_budget": particle_budget,
		"emitter_budget": emitter_budget, "initial_particles": before_particles,
		"initial_emitters": before_emitters, "protected_effects": budget,
		"partially_recovered_trails": partial_trails, "recovered_trails": recovered, "recovered_active_effects": presentation.active.size(),
		"recovered_particles": presentation._active_particles, "recovered_emitters": presentation._active_emitters}

func _mixed_queue(presentation: Node3D, dragon: DungeonActor, low: bool) -> Dictionary:
	var budget: int = presentation.FEEL.low_effect_budget if low else presentation.FEEL.effect_budget
	var particle_budget: int = presentation.FEEL.low_particle_budget if low else presentation.FEEL.particle_budget
	var emitter_budget: int = presentation.FEEL.low_emitter_budget if low else presentation.FEEL.emitter_budget
	while not presentation.active.is_empty(): presentation._recycle(presentation.active.size() - 1)
	presentation._boss_embedded_retry_remaining = presentation.BOSS_EMBEDDED_RETRY_SECONDS
	presentation._recover_boss_embedded()
	_check(presentation._boss_embedded_queue.size() == 1 and bool(presentation._boss_embedded_queue[0].recovery), "%s mode starts with one recovery request" % low)
	presentation.command(dragon, {"sequence": dragon.combat._cast_sequence, "command": {"type": "EET_SetGameObjectActive", "raw": JSON.stringify({"gameobjectNames": FIRE_ORDINARY, "booleanToSet": true})}})
	var ordinary_keys: Array = []
	for key in presentation._boss_embedded.actors[str(dragon.combat.enemy_id)]:
		if presentation._boss_embedded.bindings[key].name in FIRE_ORDINARY: ordinary_keys.append(key)
	_check(ordinary_keys.size() == 5 and presentation._boss_embedded_queue.size() == 6, "%s mode queues five real normal roots behind the recovery" % low)
	var initial_spawned: int = presentation.spawned
	presentation._process_boss_embedded_queue()
	_check(_trails(presentation, dragon).size() == 1 and not presentation._boss_embedded_queue.is_empty(), "%s mode processes recovery before a cross-frame normal backlog" % low)
	var within_budget := true
	for frame in 40:
		presentation._process(1.0 / 60.0)
		within_budget = within_budget and presentation.active.size() <= budget and presentation._active_particles <= particle_budget and presentation._active_emitters <= emitter_budget
	var live: Dictionary = presentation._boss_embedded_live.get(dragon.get_instance_id(), {})
	var normal_count := 0
	for key in ordinary_keys:
		if live.has(key): normal_count += 1
	var recovered := _trails(presentation, dragon).size()
	_check(presentation._boss_embedded_retry_remaining > 0.0, "%s mode mixed queue finishes before the periodic retry" % low)
	_check(normal_count == ordinary_keys.size() and recovered == 6, "%s mode continues recovering all missing trails after the normal backlog" % low)
	_check(within_budget and presentation.active.size() == ordinary_keys.size() + 6, "%s mode mixed queue stays within all budgets" % low)
	_check(presentation.spawned - initial_spawned == ordinary_keys.size() + 6, "%s mode mixed queue creates each root once without churn" % low)
	var stable_spawned: int = presentation.spawned
	for frame in 30: presentation._process(1.0 / 60.0)
	_check(presentation.spawned == stable_spawned and _trails(presentation, dragon).size() == 6 and presentation.active.size() == ordinary_keys.size() + 6, "%s mode mixed recovery remains stable" % low)
	return {"low_quality": low, "ordinary_roots": normal_count, "recovered_trails": recovered,
		"spawned_roots": stable_spawned - initial_spawned, "within_budget": within_budget}

func _run() -> void:
	var scenarios := [
		{"name": "idle", "delta": 1.0 / 60.0, "step": 0.0, "camera_step": 0.0},
		{"name": "idle_turning_camera", "delta": 1.0 / 60.0, "step": 0.0, "camera_step": 0.01},
		{"name": "moving_6_units_per_second", "delta": 1.0 / 60.0, "step": 0.1, "camera_step": 0.0},
		{"name": "moving_18_units_per_second", "delta": 1.0 / 60.0, "step": 0.3, "camera_step": 0.0},
		{"name": "saturated", "delta": 0.001, "step": 0.1, "camera_step": 0.0},
	]
	var rows: Array[Dictionary] = []
	var budgets: Array[Dictionary] = []
	var mixed_queues: Array[Dictionary] = []
	var functional_only := "--functional-only" in OS.get_cmdline_user_args()
	for low in [false, true]:
		var presentation := Presentation.new()
		root.add_child(presentation)
		presentation.configure({})
		presentation.set_process(false)
		presentation.audio_enabled = false
		presentation.effects_density = 2
		presentation.low_quality = low
		var camera := Camera3D.new()
		root.add_child(camera)
		camera.position = Vector3(0, 8, 18)
		camera.make_current()
		var dragon := DungeonActor.new()
		dragon.actor_id = 53001
		dragon.combat = DungeonCombat.new()
		dragon.combat.configure_enemy(53001)
		root.add_child(dragon)
		dragon.set_physics_process(false)
		dragon.set_visual("res://assets/enemies/enemy_53001.glb")
		_check(dragon.visual_loaded, "Real dragon model loads for %s mode" % low)
		presentation.prepare_combat([dragon.combat])
		presentation.register_boss_embedded(dragon)
		presentation.command(dragon, {"sequence": dragon.combat._cast_sequence, "command": {"type": "EET_SetGameObjectActive", "raw": JSON.stringify({"gameobjectNames": [FIRE_TRAIL], "booleanToSet": true})}})
		await _flush(presentation)
		var trails := _trails(presentation, dragon)
		_check(trails.size() == 6, "%s mode activates six real source wing trails" % low)
		if trails.size() == 6:
			if not functional_only:
				for scenario in scenarios: rows.append(_run_case(trails, camera, scenario, low))
			budgets.append(_pressure(presentation, dragon, low))
			mixed_queues.append(_mixed_queue(presentation, dragon, low))
		presentation.clear()
		presentation.queue_free()
		dragon.queue_free()
		camera.queue_free()
		await process_frame
	var scope := "Desktop headless boss trail budget pressure and mixed recovery queue functional checks; no timing, device FPS, GPU, or original APK comparison." if functional_only else "Desktop headless wall-clock timing of six real dragon trail advance calls per synthetic-motion frame, excluding owner movement and camera rotation. Includes GDScript, ImmediateMesh API and timer overhead; no real boss animation, rendering thread/GPU, device frame time, or original APK comparison. Saturated case uses an intentionally unrealistic 100 units/s at 1000 Hz solely to exercise geometry caps. Shared budgets account for effect roots/particle emitters; trails have separate geometry point caps."
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures,
		"rows": rows, "budgets": budgets, "mixed_queues": mixed_queues, "functional_only": functional_only, "scope": scope}
	var file := FileAccess.open(_output_path(), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "\t") + "\n")
	print("BOSS_TRAIL_PERFORMANCE ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
