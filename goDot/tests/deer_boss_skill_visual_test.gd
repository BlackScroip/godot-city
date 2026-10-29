extends "res://tests/wolf_boss_skill_visual_test.gd"

const DEER_ID := 33001
const DEER_GROUP := "ActGroup_jiaolu"
const RAGE_BUFF := "43300101"
const DEER_EX_BUFF := "45400003"

var _expected_summons: Dictionary = {}
var _observed_summons: Dictionary = {}
var _expects_projectiles := false
var _phantom_animation_samples: Dictionary = {}
var _phantom_model_count := 0
var _projectile_direction_checks := 0

func _fail(message: String) -> void:
	var text := str(_case.get("name", "setup")) + ": " + message
	if failures.has(text): return
	failures.append(text)
	print("DEER_VISUAL_FAILURE ", text)

func _run() -> void:
	var dimensions := _arg("viewport", "960x540").split("x")
	root.size = Vector2i(int(dimensions[0]), int(dimensions[1]))
	Engine.physics_ticks_per_second = HZ
	seed(SEED)
	_rendered = DisplayServer.get_name() != "headless"
	_prefix = "res://reports/deer-boss-%s-%s-%s" % [_arg("label", "current"), _arg("viewport", "960x540"), _arg("quality", "full")]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://reports"))
	world = DungeonWorld.new()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.paused = false
	world._background = false
	world.fighting = true
	world.low_effects = _arg("quality", "full") == "low"
	world.presentation.set_process(false)
	world.presentation.suspended = false
	world.presentation.audio_enabled = false
	world.presentation.effects_density = 2
	world.presentation.effects_opacity = 1.0
	_ground()
	var source := DungeonCombat.new()
	source.configure_enemy(DEER_ID, SEED)
	var cases := _catalog_cases(source)
	for scenario in cases:
		if not _arg("case", "").is_empty() and _arg("case", "") != str(scenario.name): continue
		await _run_case(scenario)
	if rows.is_empty(): failures.append("No matching deer scenario")
	if _arg("case", "").is_empty():
		for action in _combat_actions(source):
			if not _observed_actions.has(action): failures.append("Catalog action never started: " + action)
	var report := {
		"schema": 1, "boss": DEER_ID, "seed": SEED, "hz": HZ,
		"viewport": str(root.size), "quality": _arg("quality", "full"), "rendered": _rendered,
		"catalog_actions": _combat_actions(source), "catalog_cases": cases, "selected_case": _arg("case", ""),
		"observed_actions": _observed_actions.keys(), "scenarios": rows,
		"passed": failures.is_empty(), "failures": failures,
		"apk_sha256": world.presentation.media.get("apk_sha256", ""),
		"scope": "Every catalog deer attack, EX action, roar, RoarAttack and bosspose, with every combination of source buff gates. Actual world entities, projectiles and summons are stepped; AI selection is disabled. Rendered runs compare effects against the same pose with selected effects hidden. CPU samples exclude screenshot capture and preparation; they are not mobile FPS or original APK runtime measurements."
	}
	FileAccess.open(_prefix + ".json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("DEER_BOSS_SKILL_VISUAL ", JSON.stringify(report))
	await _clear_fixture()
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _combat_actions(source: DungeonCombat) -> Array[String]:
	var result: Array[String] = []
	for definition in source.catalog.get("actions", []):
		if str(definition.get("group", "")) != DEER_GROUP: continue
		var action := str(definition.id)
		if action.to_lower().begins_with("attack") or action.begins_with("EX_") or action in ["roar", "RoarAttack", "bosspose"]: result.append(action)
	result.sort()
	return result

func _catalog_cases(source: DungeonCombat) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for action in _combat_actions(source):
		var definition: Dictionary = source._action(DEER_GROUP, action)
		var gates: Array[String] = []
		for event in definition.get("events", []) + definition.get("hits", []):
			if not event.get("enabled", false): continue
			for condition in event.get("conditions", []):
				var id := str(condition.get("buff", ""))
				if not id.is_empty() and not gates.has(id): gates.append(id)
		gates.sort()
		for mask in range(1 << gates.size()):
			var buffs: Array[String] = []
			for index in gates.size():
				if mask & (1 << index): buffs.append(gates[index])
			var suffix := "normal" if buffs.is_empty() else "buff-" + "-".join(buffs)
			result.append({"name": action + "-" + suffix, "action": action, "buffs": buffs, "gates": gates})
	result.append({"name": "roar-action-switch", "action": "roar", "buffs": [], "gates": [], "switch_action": true})
	return result

func _fixture() -> void:
	var combat := DungeonCombat.new()
	combat.configure(null, null, 1, 0, SEED)
	combat.max_health = 1000000000
	combat.health = combat.max_health
	world.create_player(combat, 1, Vector3(0, 0, 4))
	world.spawn_wave([{"enemy_id": DEER_ID, "position": Vector3.ZERO}], 0, SEED)
	_boss = world.actors.back()
	_boss.face_direction(Vector3.BACK)
	_boss.combat.enemy_ai_enabled = true
	_boss.combat.custom_properties["OP_AIAction"] = ""
	for actor in world.actors:
		actor.suspended = false
		actor.simulation_scale = 1.0
		actor.set_process(false)
		actor.set_physics_process(false)
		actor.desired_velocity = Vector3.ZERO
	world.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	world.camera.size = 30.0 if _case.action in ["EX_Attack2", "RoarAttack"] else 24.0
	world.camera.position = Vector3(12, 18, -21)
	world.camera.look_at(Vector3(0, 0, 3))
	world.presentation.low_quality = world.low_effects
	world.presentation.simulation_scale = 1.0
	for id in _case.get("gates", []): _boss.combat.remove_buff(str(id))
	for id in _case.get("buffs", []): _boss.combat.add_buff(str(id))
	var preparation := DungeonCombat.new()
	preparation.configure_enemy(DEER_ID, SEED)
	for id in [RAGE_BUFF, DEER_EX_BUFF]: preparation.add_buff(id)
	world.presentation.prepare_combat([_boss.combat, preparation])
	while world.presentation.has_pending_preparation():
		world.presentation.prepare_step()
		await process_frame
	world.presentation.clear()
	await physics_frame
	await process_frame

func _run_case(scenario: Dictionary) -> void:
	await _clear_fixture()
	seed(SEED)
	_case = scenario
	_effects.clear()
	_event_counts.clear()
	_action_trace.clear()
	_shots.clear()
	_pending_shots.clear()
	_expected_effects.clear()
	_expected_summons.clear()
	_observed_summons.clear()
	_expects_projectiles = false
	_phantom_animation_samples.clear()
	_phantom_model_count = 0
	_projectile_direction_checks = 0
	var failures_before := failures.size()
	await _fixture()
	var definition: Dictionary = _boss.combat._action(DEER_GROUP, str(_case.action))
	_collect_expected_effects(definition)
	var builds_before: int = world.presentation.authored_builds
	var allocations_before := _instance_allocations()
	var by_key_before: Dictionary = world.presentation.authored_runtime_by_key.duplicate()
	var spawned_before: int = world.presentation.spawned
	var samples: Array[float] = []
	var peak := {"effects": 0, "emitters": 0, "particles": 0, "projectiles": 0, "summons": 0}
	_boss.combat._start(definition, 0)
	var frames := int(ceil(_case_duration(definition) * HZ))
	var conversion_key := "24072201_fx_enemy_jiaolu_conversion_roar"
	var snowwind_key := "24111301_fx_env_snowwind"
	var switched := false
	var roar_loop_verified := false
	for frame in frames:
		_frame = frame
		if bool(_case.get("switch_action", false)) and _effects.has(conversion_key) and frame == int(_effects[conversion_key].first_frame) + 30:
			_boss.combat._start(_boss.combat._action(DEER_GROUP, "idle"), 0)
			switched = true
		var started := Time.get_ticks_usec()
		_step()
		samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
		_observe_effects()
		if _case.action == "roar" and _effects.has(snowwind_key):
			var snowwind_active: bool = world.presentation.active.any(func(entry): return str(entry.key) == snowwind_key)
			if _boss.combat.current_action == "roar" and frame - int(_effects[snowwind_key].first_frame) >= 150:
				roar_loop_verified = true
				if not snowwind_active: _fail("Source looping snowwind expired while roar was still active")
			if _boss.combat.current_action != "roar" and snowwind_active: _fail("Action-bound snowwind survived leaving roar")
		if switched and _effects.has(conversion_key):
			var since_start := frame - int(_effects[conversion_key].first_frame)
			var conversion_active: bool = world.presentation.active.any(func(entry): return str(entry.key) == conversion_key)
			if since_start == 60 and not conversion_active: _fail("Conversion roar was destroyed on action switch before its 2233 ms source lifetime")
			if since_start == 150 and conversion_active: _fail("Conversion roar survived beyond its 2233 ms source lifetime")
		for unit in world.summon_units: _observed_summons[str(unit.id)] = true
		peak.effects = maxi(peak.effects, world.presentation.active.size())
		peak.emitters = maxi(peak.emitters, world.presentation._active_emitters)
		peak.particles = maxi(peak.particles, world.presentation._active_particles)
		peak.projectiles = maxi(peak.projectiles, world.projectiles.size())
		peak.summons = maxi(peak.summons, world.summon_units.size())
		await process_frame
		if _pending_shots.has(frame): await _capture(frame, _pending_shots[frame])
	if _effects.is_empty(): _fail("No source effects observed")
	for key in _expected_effects:
		if not _effects.has(key): _fail("Enabled source effect was never visible: " + str(key))
	for id in _expected_summons:
		if not _observed_summons.has(id): _fail("Source summon never entered the world: " + str(id))
	if _expects_projectiles and int(peak.projectiles) == 0: _fail("Source projectile never entered the world")
	if _expected_effects.has("24070801_fx_enemy_jiaolu_attack3_soul"):
		if _phantom_model_count == 0: _fail("Phantom effect has particles but no recovered skinned deer model")
		if _phantom_animation_samples.is_empty(): _fail("Phantom effect has no AnimationPlayer")
		for sample in _phantom_animation_samples.values():
			if int(sample.max_continuous_frames) > 2 and int(sample.advances) == 0: _fail("Phantom AnimationPlayer never advanced")
	if _case.action == "roar" and not _case.get("switch_action", false) and _boss.combat.buff_layers(RAGE_BUFF) != 1: _fail("Roar did not enable source rage buff")
	if _case.action == "roar" and not _case.get("switch_action", false) and not roar_loop_verified: _fail("Roar did not exercise looping snowwind beyond its initial particle lifetime")
	if _case.get("switch_action", false) and not switched: _fail("Conversion roar was never observed for the action-switch check")
	if world.presentation.authored_builds > builds_before: _fail("Effect templates were built during the active cast")
	if int(peak.emitters) > (world.FEEL.low_emitter_budget if world.low_effects else world.FEEL.emitter_budget) or int(peak.particles) > (world.FEEL.low_particle_budget if world.low_effects else world.FEEL.particle_budget): _fail("Source effect budget exceeded")
	if not world.presentation.missing.is_empty(): _fail("Missing source effects: " + str(world.presentation.missing.keys()))
	if not world.presentation.unresolved_anchors.is_empty(): _fail("Unresolved source anchors: " + str(world.presentation.unresolved_anchors.keys()))
	if _rendered:
		if _shots.is_empty() or not _shots.any(func(shot): return int(shot.get("effect_changed_pixels", 0)) >= 12): _fail("No screenshot with a visible source effect")
		for key in _expected_effects:
			if not _shots.any(func(shot): return int(shot.get("isolated_effect_changed_pixels", {}).get(key, 0)) >= 3): _fail("Source effect has no visible pixels: " + str(key))
	samples.sort()
	var p95: float = samples[int(samples.size() * 0.95)]
	var budget := float(_arg("max-p95-ms", "16.667"))
	if p95 > budget: _fail("Simulation p95 %.3f ms exceeds %.3f ms budget" % [p95, budget])
	var allocations_after := _instance_allocations()
	var runtime_by_key: Dictionary = {}
	for key in world.presentation.authored_runtime_by_key:
		var difference: int = int(world.presentation.authored_runtime_by_key[key]) - int(by_key_before.get(key, 0))
		if difference > 0: runtime_by_key[key] = difference
	if allocations_before >= 0 and allocations_after > allocations_before: _fail("Authored instances allocated during active cast: " + str(allocations_after - allocations_before))
	rows.append({
		"case": _case.name, "action": _case.action, "initial_buffs": _case.get("buffs", []),
		"frames": frames, "action_trace": _action_trace.duplicate(true), "events": _event_counts.duplicate(),
		"effects": _effects.values().duplicate(true), "shots": _shots.duplicate(true), "peak": peak,
		"expected_effects": _expected_effects.keys(), "expected_summons": _expected_summons.keys(), "observed_summons": _observed_summons.keys(),
		"effects_spawned": world.presentation.spawned - spawned_before,
		"runtime_effect_builds": world.presentation.authored_builds - builds_before,
		"runtime_instance_allocations": allocations_after - allocations_before if allocations_before >= 0 else -1,
		"runtime_instances_by_key": runtime_by_key,
		"phantom_skinned_models": _phantom_model_count, "phantom_animation_samples": _phantom_animation_samples.values(), "projectile_direction_checks": _projectile_direction_checks,
		"roar_loop_verified": roar_loop_verified,
		"instance_allocation_counter_available": allocations_before >= 0,
		"missing_effects": world.presentation.missing.keys(), "unresolved_anchors": world.presentation.unresolved_anchors.keys(),
		"simulation_p95_ms": p95, "simulation_max_ms": samples.back(), "simulation_p95_budget_ms": budget,
		"passed": failures.size() == failures_before
	})
	print("DEER_VISUAL_CASE ", _case.name, " ", "PASS" if failures.size() == failures_before else "FAIL", " effects=", _effects.size(), " shots=", _shots.size(), " p95_ms=", p95)

func _instance_allocations() -> int:
	for property in world.presentation.get_property_list():
		if str(property.name) in ["authored_runtime_instances", "authored_instance_allocations", "authored_instances_created", "authored_allocations"]: return int(world.presentation.get(property.name))
	return -1

func _case_duration(definition: Dictionary) -> float:
	var duration := float(definition.get("duration", 1)) / maxf(0.1, float(definition.get("speed", 1))) + 6.0
	return maxf(duration, 16.0 if _case.action == "attack5" else 8.0)

func _collect_expected_effects(definition: Dictionary) -> void:
	for event in definition.get("events", []) + definition.get("hits", []):
		if not event.get("enabled", false) or not _boss.combat._conditions(event.get("conditions", []), bool(event.get("all", true))): continue
		var raw := DungeonWorld._raw_definition(event)
		if event.get("type", "") == "EET_PlayEffect": _expect_name(str(raw.get("EffectTriggerDef", {}).get("EffectName", "")))
		if event.get("type", "") == "EET_AddSummonUnit": _expect_summon(str(raw.get("AddSummonUnitDef", {}).get("AddSummonUnitId", "")))
		if event.has("damageId"): _expect_entity(raw)

func _expect_entity(raw: Dictionary) -> void:
	var entity: Dictionary = raw.get("EntityProperty", {})
	_expect_name(str(entity.get("EffectTriggerDef", {}).get("EffectName", "")))
	_expect_name(str(entity.get("EffectDelayTriggerDef", {}).get("EffectName", "")))
	_expect_name(str(entity.get("ModlePrefab", "")))
	if raw.get("EntityType", "") == "EET_Physical": _expects_projectiles = true
	_expect_summon(str(entity.get("AddSummonUnitDefOnEnd", {}).get("AddSummonUnitId", "")))

func _expect_summon(id: String) -> void:
	if id.is_empty() or id == "0" or _expected_summons.has(id): return
	_expected_summons[id] = true
	for definition in _boss.combat.catalog.get("summons", []):
		if str(definition.id) != id: continue
		var raw: Dictionary = definition.get("raw_data", {})
		for field in ["Prefab", "InitEffect", "DestoryEffect"]: _expect_name(str(raw.get(field, "")))
		_expect_entity(raw)
		for child in raw.get("AddSummonUnitList", []): _expect_summon(str(child.get("AddData", {}).get("AddSummonUnitId", "")))
		return
	_fail("Source summon absent from catalog: " + id)

func _observe_effects() -> void:
	for entry in world.presentation.telegraphs:
		if entry.actor.get_ref() == _boss: _fail("Procedural telegraph replaces an APK deer effect")
	for entry in world.presentation.active:
		if entry.actor.get_ref() != _boss: continue
		var key := str(entry.key)
		if not entry.authored or not bool(entry.get("source_only", false)) or entry.mesh.visible or entry.burst.visible or entry.sparks.emitting: _fail("Non-source effect overlay: " + key)
		if key == "24070801_fx_enemy_jiaolu_attack3_soul" and entry.authored: _observe_phantom_model(entry.authored)
		if _effects.has(key): continue
		var source: Dictionary = world.presentation.media.get("effects", {}).get(key, {})
		if str(source.get("source", "")).is_empty() or str(source.get("source_sha256", "")).is_empty(): _fail("Effect has no APK source identity: " + key)
		_effects[key] = {"key": key, "first_frame": _frame, "source": source.get("source", ""), "source_sha256": source.get("source_sha256", ""), "scale": str(entry.authored.scale) if entry.authored else "", "source_only": bool(entry.get("source_only", false)), "source_warning": bool(entry.get("source_warning", false))}
		var capture_offsets := [2, 6, 18, 24, 48] if key.ends_with("_attack3_soul") else [2, 6, 18]
		# Some APK warning commands have a seven-millisecond destruction delay.
		if bool(entry.get("source_warning", false)): capture_offsets.push_front(0)
		for offset in capture_offsets:
			var capture_frame: int = _frame + offset
			if not _pending_shots.has(capture_frame): _pending_shots[capture_frame] = []
			_pending_shots[capture_frame].append(key)
	for projectile in world.projectiles:
		if projectile.state.source_key != str(_boss.combat.actor_key) or not is_instance_valid(projectile.visual): continue
		if projectile.visual.visible: _fail("Visible generic deer projectile mesh")
		var direction: Vector3 = projectile.state.direction
		direction.y = 0.0
		if direction.length_squared() < 0.0001: continue
		_projectile_direction_checks += 1
		if projectile.visual.global_basis.z.normalized().dot(direction.normalized()) < 0.999: _fail("Projectile visual does not face its own travel direction")
		if str(projectile.state.entity.get("ModlePrefab", "")).is_empty(): continue
		for entry in world.presentation.active:
			if entry.follow and entry.follow.get_ref() == projectile.visual:
				if not entry.follow_rotation or entry.root.global_basis.z.normalized().dot(direction.normalized()) < 0.999: _fail("Source projectile effect does not follow individual projectile rotation")

func _observe_phantom_model(authored: Node3D) -> void:
	var model_count := 0
	for mesh in authored.find_children("*", "MeshInstance3D", true, false):
		if mesh.skin != null and mesh.mesh != null and mesh.visible:
			model_count += 1
			if mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF: _fail("Phantom mesh casts a shadow despite source m_CastShadows=0")
	_phantom_model_count = maxi(_phantom_model_count, model_count)
	if model_count == 0: _fail("Phantom effect lacks a visible skinned mesh")
	for entry in authored.model_players:
		var player: AnimationPlayer = entry.node
		var id := str(player.get_instance_id())
		var position := player.current_animation_position
		if not _phantom_animation_samples.has(id):
			_phantom_animation_samples[id] = {"frames": 0, "advances": 0, "position": position, "animation": player.current_animation, "last_frame": -1, "age": -1.0, "continuous_frames": 0, "max_continuous_frames": 0}
		var sample: Dictionary = _phantom_animation_samples[id]
		# A pooled phantom can die on contact in one frame, then restart several casts later.
		var same_lifetime: bool = int(sample.last_frame) == _frame - 1 and float(authored.age) > float(sample.age)
		sample.continuous_frames = int(sample.continuous_frames) + 1 if same_lifetime else 1
		sample.max_continuous_frames = maxi(int(sample.max_continuous_frames), int(sample.continuous_frames))
		if same_lifetime and absf(position - float(sample.position)) > 0.00001: sample.advances += 1
		sample.frames += 1
		sample.position = position
		sample.last_frame = _frame
		sample.age = authored.age
		if not player.is_playing(): _fail("Phantom AnimationPlayer is stopped")
