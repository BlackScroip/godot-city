extends Node

const Metrics = preload("res://scripts/combat_metrics.gd")
const SEED := 731
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

func _ready() -> void:
	var startup := Time.get_ticks_usec()
	barrage = OS.has_feature("combat_stress")
	for action in ["move_left", "move_right", "move_up", "move_down"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--seconds="): seconds = maxf(1, float(argument.get_slice("=", 1)))
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		if argument == "--low-effects": low = true
		if argument == "--barrage": barrage = true
	seed(SEED)
	Engine.physics_ticks_per_second = 60
	world = DungeonWorld.new()
	add_child(world)
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
	_spawn(24)
	world.prepare_enemy_media([11001, 13001])
	while world.presentation.has_pending_preparation():
		world.presentation.prepare_step()
		await get_tree().process_frame
	await world.prepare_feedback_rendering()
	world.environment_action.connect(func(kind, _payload):
		if kind == "auto_loot": _save_sample("pickup_save"))
	world.paused = false
	startup_ms = (Time.get_ticks_usec() - startup) / 1000.0
	metrics = Metrics.new()
	ready_to_run = true

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
	result["fixture"] = "extended-barrage" if barrage else "initial-baseline"
	result["save_error"] = store.warning
	result["viewport"] = [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y]
	result["scope"] = "Fixed physics-tick combat workload, rendered wall frame times. Headless results are CPU diagnostics only. Device thermal state must be recorded externally."
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(result, "\t"))
	print("COMBAT_STRESS ", JSON.stringify({"output": output, "summary": result.all, "headless": result.headless}))
	print("COMBAT_STRESS_PHASES ", JSON.stringify({"cold": result.cold, "warm": result.warm}))
	print("COMBAT_STRESS_DEVICE ", JSON.stringify({"device": result.device, "platform": result.platform, "os_version": result.os_version, "renderer": result.renderer, "debug": result.debug, "fixture": result.fixture, "quality": result.quality, "startup_preparation_ms": startup_ms, "save_error": store.warning}))
	get_tree().quit(0 if file else 1)

func _exit_tree() -> void:
	store.flush()
