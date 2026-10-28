extends Node

const Metrics = preload("res://scripts/combat_metrics.gd")
const SEED := 731

class MeasuredWorld:
	extends DungeonWorld
	var cpu_scopes: Dictionary = {}

	func _record_scope(key: String, before: int) -> void:
		var elapsed := Time.get_ticks_usec() - before
		if not cpu_scopes.has(key): cpu_scopes[key] = {"calls": 0, "total_us": 0, "max_us": 0}
		var entry: Dictionary = cpu_scopes[key]
		entry.calls += 1
		entry.total_us += elapsed
		entry.max_us = maxi(entry.max_us, elapsed)

	func _physics_process(delta: float) -> void:
		var before := Time.get_ticks_usec()
		super._physics_process(delta)
		_record_scope("world_tick", before)

	func _tick_projectiles(delta: float) -> void:
		var before := Time.get_ticks_usec()
		super._tick_projectiles(delta)
		_record_scope("projectiles", before)

	func _tick_summons(delta: float) -> void:
		var before := Time.get_ticks_usec()
		super._tick_summons(delta)
		_record_scope("summons", before)

	func _consume(actor: DungeonActor, event: Dictionary) -> void:
		var before := Time.get_ticks_usec()
		super._consume(actor, event)
		_record_scope("event_dispatch", before)

	func timing_report() -> Dictionary:
		var result := {}
		for key in cpu_scopes:
			var row: Dictionary = cpu_scopes[key]
			result[key] = {"calls": row.calls, "total_ms": row.total_us / 1000.0,
				"mean_ms": float(row.total_us) / maxi(1, row.calls) / 1000.0, "max_ms": row.max_us / 1000.0}
		return result

var world: DungeonWorld
var hud: DungeonHud
var profile := DungeonProfile.new()
var store := DungeonSaveStore.new("user://combat-stress-profile.json")
var metrics = Metrics.new()
var ticks := 0
var frames := 0
var ready_to_run := false
var seconds := 600.0
var output := "user://combat-stress.json"
var low := false
var finish_requested := false
var barrage := false
var _save_pending := false
var _save_wait := 0.0
var startup_ms := 0.0
var ignore_focus := false
var fixed_fps := -1
var confirmed_impacts := 0

func _ready() -> void:
	var startup := Time.get_ticks_usec()
	barrage = OS.has_feature("combat_stress") and not OS.has_feature("combat_source_crowd")
	if OS.has_feature("combat_stress_short"): seconds = 45.0
	if OS.has_feature("combat_source_crowd"): output = "user://combat-source-crowd.json"
	for action in ["move_left", "move_right", "move_up", "move_down"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seconds="): seconds = maxf(1, float(argument.get_slice("=", 1)))
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		if argument == "--low-effects": low = true
		if argument == "--barrage": barrage = true
		if argument == "--no-barrage": barrage = false
		if argument == "--ignore-focus": ignore_focus = true
		if argument.begins_with("--fps="): fixed_fps = clampi(int(argument.get_slice("=", 1)), 0, 120)
	seed(SEED)
	Engine.physics_ticks_per_second = 60
	world = MeasuredWorld.new() if OS.has_feature("combat_stress_short") or "--profile-cpu" in OS.get_cmdline_user_args() else DungeonWorld.new()
	add_child(world)
	DungeonStyle.apply_options(world)
	if fixed_fps >= 0: Engine.max_fps = fixed_fps
	if ignore_focus: world._background = false
	world.paused = true
	world.low_effects = low
	world.presentation.audio_enabled = false
	var catalog = preload("res://scripts/domain/catalog.gd").new()
	catalog.load_all()
	profile.data.run = DungeonProfile.new_run(SEED, 1, 1000000000)
	profile.data.run.active = true
	world.systems = preload("res://scripts/domain/systems.gd").new(catalog, profile)
	hud = DungeonHud.new()
	add_child(hud)
	world.hud = hud
	hud.skill.connect(func(slot, pressed): world.use_skill(slot, pressed))
	hud.action.connect(func(kind, mode, _extra):
		if kind == "auto_attack_mode":
			world.set_attack_mode(str(mode))
			hud.set_attack_mode(str(mode)))
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(60, 0.2, 60)
	collision.shape = shape
	floor_body.add_child(collision)
	var floor_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = shape.size
	floor_mesh.mesh = box
	floor_body.add_child(floor_mesh)
	floor_body.position.y = -0.1
	world.add_child(floor_body)
	var combat := DungeonCombat.new()
	combat.configure(null, null, 1, 0, SEED)
	combat.max_health = 1000000000
	combat.health = combat.max_health
	world.create_player(combat, 1, Vector3.ZERO)
	world.set_attack_mode("normal")
	world.fighting = true
	world.impact_confirmed.connect(func(_hit): confirmed_impacts += 1)
	_spawn(24)
	world.prepare_enemy_media([11001, 13001])
	while world.presentation.has_pending_preparation():
		world.presentation.prepare_step()
		await get_tree().process_frame
	await world.prepare_feedback_rendering()
	if fixed_fps >= 0:
		world.get_node("SettingsEffects").settings["fps"] = fixed_fps
		Engine.max_fps = fixed_fps
	world.environment_action.connect(func(kind, _payload):
		if kind == "auto_loot": _save_sample("pickup_save"))
	world.paused = false
	startup_ms = (Time.get_ticks_usec() - startup) / 1000.0
	metrics = Metrics.new()
	metrics.measure_rendering(get_viewport())
	if world is MeasuredWorld: world.cpu_scopes.clear()
	ready_to_run = true
	print("COMBAT_STRESS_READY ", JSON.stringify({"seconds": seconds, "actors": world.actors.size(),
		"renderer": RenderingServer.get_current_rendering_method(), "driver": RenderingServer.get_current_rendering_driver_name(), "scale_3d": get_viewport().scaling_3d_scale,
		"fps_cap": Engine.max_fps, "barrage": barrage, "ai_backends": _ai_backends()}))

func _ai_backends() -> Dictionary:
	var result: Dictionary = {}
	for actor in world.actors:
		if not is_instance_valid(actor) or actor.combat.enemy_ai == null: continue
		var ai: RefCounted = actor.combat.enemy_ai
		var backend := str(ai.backend_name()) if ai.has_method("backend_name") else "gdscript"
		result[backend] = int(result.get(backend, 0)) + 1
	return result

func _spawn(count: int) -> void:
	var batch: Array = []
	for index in count:
		var angle := TAU * index / count
		batch.append({"enemy_id": 13001 if index == 0 else 11001, "position": Vector3(cos(angle), 0, sin(angle)) * (3.0 + index % 4)})
	world.spawn_wave(batch, 0, SEED + ticks)
	for actor in world.actors:
		actor.combat.max_health = 1000000000
		actor.combat.health = actor.combat.max_health

func _physics_process(_delta: float) -> void:
	if not ready_to_run or finish_requested: return
	# Automated measurements must explicitly opt out of desktop focus suspension.
	if ignore_focus: world._background = false
	ticks += 1
	if ticks % 120 == 1:
		world.use_skill(2)
		metrics.mark("skill")
		if barrage: _barrage()
	if ticks % 180 == 60:
		world.use_skill(4)
	if ticks % 180 == 120: world.use_skill(4, false)
	if ticks % 240 == 1:
		for actor in world.actors:
			if actor.actor_id == 13001:
				actor.combat._start(actor.combat._action(str(actor.combat.enemy.group), "Attack_EX1"), 0)
		metrics.mark("boss_cast")
	if ticks % 300 == 1:
		for index in 12: world.ground_loot.spawn(101, world.player.position + Vector3(index * 0.04, 0, 0), 1, true)
		metrics.mark("loot")
	if ticks % 600 == 0: _save_sample("periodic_save")
	if ticks == 900:
		_spawn(8)
		metrics.mark("reinforcements")
	if ticks >= int(seconds * 60):
		finish_requested = true
		_finish.call_deferred()

func _save_sample(kind: String) -> void:
	# Keep the original fixture for before/after comparison. The extended fixture
	# also exercises the production request-coalescing interval.
	if barrage and kind == "pickup_save":
		_save_pending = true
		return
	var before := Time.get_ticks_usec()
	profile.data.run.battle = {"player": world.player.combat.snapshot(), "enemies": world.actors.filter(func(actor): return not actor.is_player).map(func(actor): return actor.combat.snapshot()), "transients": world.transient_snapshot()}
	var snapshot_us := Time.get_ticks_usec() - before
	if store.has_method("request_save"): store.call("request_save", profile.data)
	else: store.save(profile.data)
	metrics.mark(kind, {"snapshot_ms": snapshot_us / 1000.0, "request_ms": (Time.get_ticks_usec() - before) / 1000.0})

func _process(_delta: float) -> void:
	if not ready_to_run or finish_requested: return
	if ignore_focus: world._background = false
	frames += 1
	metrics.sample(world, "cold" if ticks < 600 else "warm")
	hud.update_combat(world.player.combat, false)
	if store.has_method("poll"): store.call("poll")
	if _save_pending:
		_save_wait += _delta
		if _save_wait >= 0.25:
			_save_pending = false
			_save_wait = 0.0
			_save_sample("coalesced_pickup_save")

func _barrage() -> void:
	var source: DungeonActor = world.actors[1]
	for index in 96:
		var angle := TAU * index / 96.0
		var direction := Vector3(cos(angle), 0, sin(angle))
		var event := {"damage": 10.0, "sequence": source.combat._cast_sequence, "source_key": str(source.combat.actor_key), "action": "stress_explosion", "definition": {"projectile": true, "raw": JSON.stringify({"MotionAnimatorType": "EMAT_Line", "MotionAnimatorProperty": {"Speed": 8, "MaxLifetime": 4}, "EntityProperty": {"MaxPassNum": 3, "ColliderType": "Sphere", "ModelBoxColliderSize": {"x": 0.3, "y": 0.3, "z": 0.3}}})}}
		var state: DungeonProjectile = world._projectile_state_pool.pop_back() if not world._projectile_state_pool.is_empty() else DungeonProjectile.new()
		state.configure(event, world.player.position + Vector3.UP * 0.8 - direction * 3, direction, world.player.position)
		state.source_key = str(source.combat.actor_key)
		state.source_player = false
		world._add_projectile_visual(state, source)
	for actor in world.actors:
		if actor.is_player: continue
		var hit := {"damage": 20.0, "sequence": world.player.combat._cast_sequence, "action": "stress_explosion", "emission": ticks, "contact": actor.get_instance_id(), "source_key": "player", "definition": {"raw": "{}"}, "impact_category": "explosion", "ranged": true}
		hit["impact_origin"] = DungeonProjectile._array(world.player.position)
		hit["impact_radius"] = 12.0
		world._apply_hit(world.player, actor, hit)
	metrics.mark("barrage", {"shots": 96})

func _finish() -> void:
	world.paused = true
	if store.has_method("flush"): store.call("flush")
	var result: Dictionary = metrics.report()
	result["seed"] = SEED
	result["startup_preparation_ms"] = startup_ms
	result["simulation_seconds"] = ticks / 60.0
	result["quality"] = "low" if low else "full"
	result["renderer_method"] = RenderingServer.get_current_rendering_method()
	result["renderer_driver"] = RenderingServer.get_current_rendering_driver_name()
	result["render_scale"] = get_viewport().scaling_3d_scale
	result["fps_cap"] = Engine.max_fps
	result["ai_backends"] = _ai_backends()
	if world.has_method("timing_report"): result["cpu_scopes"] = world.timing_report()
	result["fixture"] = "extended-barrage" if barrage else "initial-baseline"
	if OS.has_feature("combat_source_crowd") or "--no-barrage" in OS.get_cmdline_user_args(): result["fixture"] = "source-crowd"
	result["save_error"] = store.warning
	result["activity"] = {"confirmed_impacts": confirmed_impacts, "player_casts": world.player.combat._cast_sequence, "effects_spawned": world.presentation.spawned, "ignore_focus": ignore_focus}
	result["valid_combat_sample"] = confirmed_impacts > 0 and world.presentation.spawned > 0
	result["viewport"] = [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y]
	result["scope"] = "Fixed physics-tick combat workload, rendered wall frame times. Headless results are CPU diagnostics only. Device thermal state must be recorded externally."
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(result, "\t"))
	print("COMBAT_STRESS ", JSON.stringify({"output": output, "summary": result.all, "headless": result.headless}))
	print("COMBAT_STRESS_PHASES ", JSON.stringify({"cold": result.cold, "warm": result.warm}))
	if result.has("cpu_scopes"): print("COMBAT_STRESS_CPU ", JSON.stringify(result.cpu_scopes))
	print("COMBAT_STRESS_RENDER ", JSON.stringify(result.render_timing))
	print("COMBAT_STRESS_DEVICE ", JSON.stringify({"device": result.device, "platform": result.platform, "os_version": result.os_version, "renderer": result.renderer, "renderer_method": result.renderer_method, "renderer_driver": result.renderer_driver, "debug": result.debug, "fixture": result.fixture, "quality": result.quality, "startup_preparation_ms": startup_ms, "save_error": store.warning, "ai_backends": result.ai_backends}))
	print("COMBAT_STRESS_ACTIVITY ", JSON.stringify(result.activity))
	get_tree().quit(0 if file and result.valid_combat_sample else 1)

func _exit_tree() -> void:
	store.flush()
