extends "res://tests/impact_visual_test.gd"

const BOSS_ID := 13001
const GROUP := "ActGroup_senlinlangwang"
const FIRE_BUFF := "41300101"
const EX_BUFF := "45400001"
const SPECIAL_BUFF := "101000022"

var _case: Dictionary = {}
var _boss: DungeonActor
var _effects: Dictionary = {}
var _event_counts: Dictionary = {}
var _action_trace: Array[Dictionary] = []
var _shots: Array[Dictionary] = []
var _observed_actions: Dictionary = {}
var _pending_shots: Dictionary = {}
var _expected_effects: Dictionary = {}
var _frame := 0
var _prefix := ""
var _rendered := false

func _run() -> void:
	var dimensions := _arg("viewport", "960x540").split("x")
	root.size = Vector2i(int(dimensions[0]), int(dimensions[1]))
	Engine.physics_ticks_per_second = HZ
	seed(SEED)
	_rendered = DisplayServer.get_name() != "headless"
	_prefix = "res://reports/wolf-boss-%s-%s-%s" % [_arg("label", "current"), _arg("viewport", "960x540"), _arg("quality", "full")]
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
	source.configure_enemy(BOSS_ID, SEED)
	var cases := _catalog_cases(source)
	for scenario in cases:
		if not _arg("case", "").is_empty() and _arg("case", "") != str(scenario.name): continue
		await _run_case(scenario)
	if rows.is_empty(): failures.append("No matching wolf scenario")
	var report := {
		"schema": 1, "boss": BOSS_ID, "seed": SEED, "hz": HZ,
		"viewport": str(root.size), "quality": _arg("quality", "full"), "rendered": _rendered,
		"catalog_actions": _combat_actions(source), "selected_case": _arg("case", ""),
		"observed_actions": _observed_actions.keys(), "scenarios": rows,
		"passed": failures.is_empty(), "failures": failures,
		"apk_sha256": world.presentation.media.get("apk_sha256", ""),
		"scope": "Catalog-enumerated wolf actions and their buff-gated variants use actual combat events, world entities, projectiles, source interrupts and summon paths. AI selection is never ticked. Fixed simulation steps and effect-hidden images isolate visible effects at the same actor pose; this is reconstruction validation, not an original APK runtime comparison or mobile FPS benchmark."
	}
	FileAccess.open(_prefix + ".json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("WOLF_BOSS_SKILL_VISUAL ", JSON.stringify(report))
	await _clear_fixture()
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _combat_actions(source: DungeonCombat) -> Array[String]:
	var result: Array[String] = []
	for definition in source.catalog.get("actions", []):
		if str(definition.get("group", "")) != GROUP: continue
		var action := str(definition.id)
		if action.to_lower().begins_with("attack") or action.begins_with("EX_") or action in ["roar", "bosspose"]: result.append(action)
	result.sort()
	return result

func _catalog_cases(source: DungeonCombat) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for action in _combat_actions(source):
		var definition: Dictionary = source._action(GROUP, action)
		var gates: Array[String] = []
		for event in definition.get("events", []) + definition.get("hits", []):
			if not event.get("enabled", false): continue
			if "kuangbao-100" in str(event.get("raw", "")) and not gates.has(FIRE_BUFF): gates.append(FIRE_BUFF)
			for condition in event.get("conditions", []):
				var id := str(condition.get("buff", ""))
				if id in [FIRE_BUFF, EX_BUFF, SPECIAL_BUFF] and bool(condition.get("exists", true)) and not gates.has(id): gates.append(id)
		if action == "attack4" and not gates.has(FIRE_BUFF): gates.append(FIRE_BUFF)
		result.append({"name": action + "-normal", "action": action, "buffs": [], "phase": action == "roar"})
		if not gates.is_empty():
			result.append({"name": action + "-gated", "action": action, "buffs": gates, "phase": action == "roar"})
	result.append({"name": "buff-rage", "action": "idle", "buffs": [], "add_buff": FIRE_BUFF, "duration": 1.5})
	result.append({"name": "buff-wolf-summon", "action": "idle", "buffs": [], "add_buff": "41300113", "layers": 3, "duration": 2.5})
	result.append({"name": "buff-ex-ground-summon", "action": "idle", "buffs": [EX_BUFF], "add_buff": "41300120", "duration": 7.0})
	return result

func _clear_fixture() -> void:
	world.presentation.clear()
	for projectile in world.projectiles:
		world._recycle_projectile(projectile)
	world.projectiles.clear()
	for unit in world.summon_units.duplicate(): world._dispose_summon(unit, false)
	world._tick_damage_numbers(2.0)
	if not world.presentation.active.is_empty() or not world.presentation.telegraphs.is_empty() or world.presentation._active_particles != 0 or world.presentation._active_emitters != 0: _fail("Clearing the previous cast left presentation state")
	world.pending_attack_entities.clear()
	world.active_attack_entities.clear()
	world.monster_spawn_queue.clear()
	world.wave_spawn_queue.clear()
	for actor in world.actors:
		if is_instance_valid(actor): actor.queue_free()
	world.actors.clear()
	world._actor_index.clear()
	world._perception.clear()
	world.player = null
	world.restore_transients({})
	world.presentation.missing.clear()
	world.presentation.unresolved_anchors.clear()
	await process_frame

func _fixture() -> void:
	var combat := DungeonCombat.new()
	combat.configure(null, null, 1, 0, SEED)
	combat.max_health = 1000000000
	combat.health = combat.max_health
	world.create_player(combat, 1, Vector3(0, 0, 3))
	world.spawn_wave([{"enemy_id": BOSS_ID, "position": Vector3.ZERO}], 0, SEED)
	_boss = world.actors.back()
	_boss.face_direction(Vector3.BACK)
	_boss.combat.enemy_ai_enabled = true
	_boss.combat.custom_properties["OP_AIAction"] = ""
	# Source spawn IDs are resolved to deterministic fixture locations, not invented summons.
	world.room_spawn_points.clear()
	for index in 8:
		var angle := float(index) * TAU / 8.0
		world.room_spawn_points.append({"Id": 10 + index, "Position": {"x": cos(angle) * 5.0, "y": 0.0, "z": sin(angle) * 5.0}})
	for actor in world.actors:
		actor.suspended = false
		actor.simulation_scale = 1.0
		actor.set_process(false)
		actor.set_physics_process(false)
		actor.desired_velocity = Vector3.ZERO
	world.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	world.camera.size = 25.0 if _case.name in ["EX_RandomFireRange-normal", "buff-ex-ground-summon"] else 19.0
	world.camera.position = Vector3(10, 15, -19)
	world.camera.look_at(Vector3(0, 0, 2))
	if _case.name == "buff-rage":
		world.camera.size = 11.0
		world.camera.position = Vector3(12, 9, 14)
		world.camera.look_at(Vector3(0, 1, 0))
	world.presentation.low_quality = world.low_effects
	world.presentation.simulation_scale = 1.0
	for id in _case.get("buffs", []): _boss.combat.add_buff(str(id))
	var preparation := DungeonCombat.new()
	preparation.configure_enemy(BOSS_ID, SEED)
	for id in [FIRE_BUFF, EX_BUFF, "41300120", "41300113"]: preparation.add_buff(id)
	var minion := DungeonCombat.new()
	minion.configure_enemy(11001, SEED)
	world.presentation.prepare_combat([_boss.combat, preparation, minion])
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
	await _fixture()
	var definition: Dictionary = _boss.combat._action(GROUP, str(_case.action))
	_collect_expected_effects(definition)
	var failures_before := failures.size()
	var builds_before: int = world.presentation.authored_builds
	var spawned_before: int = world.presentation.spawned
	var impacts_before: int = world.presentation.impacts
	var samples: Array[float] = []
	var peak := {"effects": 0, "emitters": 0, "particles": 0, "projectiles": 0, "summons": 0, "minions": 0}
	if _case.action == "attack4_loop": _boss.combat.custom_properties["attack4_loopcount"] = 4
	if _case.get("phase", false):
		_boss.combat._cancel_sequence(_boss.combat._cast_sequence)
		_boss.combat.busy = 0.0
		_boss.combat.health = _boss.combat.max_health * 0.5
		var result: Dictionary = _boss.combat.request_enemy_attack()
		if not result.success or _boss.combat.current_action != "roar": _fail("50% health phase did not select roar")
	else:
		_boss.combat._start(definition, 0)
	if _case.has("add_buff"): _boss.combat.add_buff(str(_case.add_buff), int(_case.get("layers", 1)))
	if _case.name == "buff-rage":
		for name in ["24041201_fx_enemy_senlinlangwang_buff_hair", "24041201_fx_enemy_senlinlangwang_buff_tail"]: _expected_effects[name] = true
		_pending_shots[30] = _expected_effects.keys()
		_pending_shots[60] = _expected_effects.keys()
	if _case.name == "buff-ex-ground-summon":
		for name in ["24042201_fx_enemy_senlinlangwang_attack2_rangepointer", "24042901_fx_enemy_senlinlangwang_roar_eruption"]: _expected_effects[name] = true
	var frames := int(ceil(_case_duration(definition) * HZ))
	for frame in frames:
		_frame = frame
		var started := Time.get_ticks_usec()
		_step()
		samples.append(float(Time.get_ticks_usec() - started) / 1000.0)
		_observe_effects()
		peak.effects = maxi(peak.effects, world.presentation.active.size())
		peak.emitters = maxi(peak.emitters, world.presentation._active_emitters)
		peak.particles = maxi(peak.particles, world.presentation._active_particles)
		peak.projectiles = maxi(peak.projectiles, world.projectiles.size())
		peak.summons = maxi(peak.summons, world.summon_units.size())
		peak.minions = maxi(peak.minions, world.actors.size() - 2)
		await process_frame
		if _pending_shots.has(frame):
			await _capture(frame, _pending_shots[frame])
	if _case.action in ["attack4", "attack4_loop"] and (int(_boss.combat.custom_properties.get("attack4_loopcount", 0)) != 5 or not _action_trace.any(func(item): return item.action == "attack2")): _fail("Claw sequence did not complete five source counter layers and transition to attack2")
	if _case.name == "EX_WolfCall-normal" and int(_event_counts.get("spawn_monster", 0)) != 0: _fail("Disabled EX_WolfCall monster generation was executed")
	if _case.name == "buff-wolf-summon" and int(peak.minions) != 3: _fail("Three source counter layers did not summon three wolves")
	if _case.name == "buff-ex-ground-summon" and int(_event_counts.get("summon:41300120", 0)) == 0: _fail("EX buff did not emit source ground summon 41300120")
	if _case.get("phase", false) and _boss.combat.buff_layers(FIRE_BUFF) != 1: _fail("Roar did not enable the source rage buff")
	if _case.name != "buff-wolf-summon" and _effects.is_empty(): _fail("No source effects observed")
	for key in _expected_effects:
		if not _effects.has(key): _fail("Enabled source effect was never visible: " + str(key))
	if world.presentation.authored_builds > builds_before: _fail("Effect templates were built during the active cast")
	if int(peak.emitters) > (world.FEEL.low_emitter_budget if world.low_effects else world.FEEL.emitter_budget) or int(peak.particles) > (world.FEEL.low_particle_budget if world.low_effects else world.FEEL.particle_budget): _fail("Source effect budget exceeded")
	if not world.presentation.missing.is_empty(): _fail("Missing source effects: " + str(world.presentation.missing.keys()))
	if not world.presentation.unresolved_anchors.is_empty(): _fail("Unresolved source anchors: " + str(world.presentation.unresolved_anchors.keys()))
	if _rendered and (_shots.is_empty() or not _shots.any(func(shot): return int(shot.get("effect_changed_pixels", 0)) >= 12)) and _case.name != "buff-wolf-summon": _fail("No screenshot with a visible source effect")
	if _rendered:
		for key in _effects:
			if not _effects[key].source_warning and _case.name != "buff-rage": continue
			if not _shots.any(func(shot): return int(shot.get("isolated_effect_changed_pixels", {}).get(key, 0)) >= 3): _fail("APK warning or embedded flame has no visible pixels: " + str(key))
	if _case.name == "buff-rage":
		_boss.combat.remove_buff(FIRE_BUFF)
		world.presentation.sync_actor_buffs(_boss)
		if world.presentation.active.any(func(entry): return entry.actor.get_ref() == _boss and entry.has("embedded_effect")): _fail("Rage flames survived source buff removal")
	samples.sort()
	rows.append({
		"case": _case.name, "action": _case.action, "initial_buffs": _case.get("buffs", []), "trigger_buff": _case.get("add_buff", ""),
		"frames": frames, "action_trace": _action_trace.duplicate(true), "events": _event_counts.duplicate(),
		"effects": _effects.values().duplicate(true), "shots": _shots.duplicate(true), "peak": peak,
		"expected_effects": _expected_effects.keys(),
		"effects_spawned": world.presentation.spawned - spawned_before, "impacts": world.presentation.impacts - impacts_before,
		"runtime_effect_builds": world.presentation.authored_builds - builds_before,
		"missing_effects": world.presentation.missing.keys(), "unresolved_anchors": world.presentation.unresolved_anchors.keys(),
		"simulation_p95_ms": samples[int(samples.size() * 0.95)], "simulation_max_ms": samples.back(),
		"passed": failures.size() == failures_before
	})
	print("WOLF_VISUAL_CASE ", _case.name, " ", "PASS" if failures.size() == failures_before else "FAIL", " effects=", _effects.size(), " shots=", _shots.size())

func _case_duration(definition: Dictionary) -> float:
	if _case.has("duration"): return float(_case.duration)
	if _case.action == "attack4": return 17.0
	if _case.action == "attack4_loop": return 7.5
	var speed := maxf(0.1, float(definition.get("speed", 1)))
	var duration := float(definition.get("duration", 1)) / speed + 2.0
	for hit in definition.get("hits", []):
		if not hit.get("enabled", false) or not _boss.combat._conditions(hit.get("conditions", []), bool(hit.get("all", true))): continue
		var raw := DungeonWorld._raw_definition(hit)
		var entity: Dictionary = raw.get("EntityProperty", {})
		var emit: Dictionary = raw.get("EmitProperty", {})
		var repeated := maxf(float(emit.get("TotalEmitTime", 0)), float(emit.get("Interval", 0)) * maxf(0, float(emit.get("Num", 1)) - 1))
		var lifetime := float(entity.get("CheckTime", 0))
		if raw.get("EntityType", "") == "EET_Physical":
			var motion: Dictionary = raw.get("MotionAnimatorProperty", {})
			lifetime = minf(float(hit.get("lifetime", 0)), 5.0)
			if float(motion.get("Speed", 0)) > 0 and float(motion.get("Distance", 0)) > 0: lifetime = float(motion.Distance) / float(motion.Speed) + 0.5
		duration = maxf(duration, float(hit.time) / speed + repeated + float(entity.get("Delay", 0)) + lifetime + 1.0)
	return minf(20.0, duration)

func _collect_expected_effects(definition: Dictionary) -> void:
	for event in definition.get("events", []) + definition.get("hits", []):
		if not event.get("enabled", false) or not _boss.combat._conditions(event.get("conditions", []), bool(event.get("all", true))): continue
		var raw := DungeonWorld._raw_definition(event)
		if event.get("type", "") == "EET_PlayEffect": _expect_name(str(raw.get("EffectTriggerDef", {}).get("EffectName", "")))
		if event.has("damageId"):
			var entity: Dictionary = raw.get("EntityProperty", {})
			_expect_name(str(entity.get("EffectTriggerDef", {}).get("EffectName", "")))
			_expect_name(str(entity.get("EffectDelayTriggerDef", {}).get("EffectName", "")))
			_expect_name(str(entity.get("ModlePrefab", "")))
	if definition.get("id", "") == "attack4": _collect_expected_effects(_boss.combat._action(GROUP, "attack4_loop"))

func _expect_name(name: String) -> void:
	if not name.is_empty(): _expected_effects[name.get_file().trim_suffix(".prefab").to_lower()] = true

func _step() -> void:
	var delta := 1.0 / HZ
	world._physics_serial += 1
	world._prune_source_stop_hits()
	world._advance_battle_scale(delta)
	world.elapsed += delta
	for actor in world.actors.duplicate():
		actor.suspended = false
		actor.simulation_scale = world.simulation_scale
		actor.set_process(false)
		actor.desired_velocity = Vector3.ZERO
		actor.combat.custom_properties["EnemyDistances"] = [actor.position.distance_to(world.player.position)]
		if not actor.is_player: actor.combat._tick_enemy_interrupts()
		actor.combat.tick(delta * world.simulation_scale)
		for event in actor.combat.drain_events():
			var key := str(event.type)
			_event_counts[key] = int(_event_counts.get(key, 0)) + 1
			if event.type == "summon":
				key = "summon:" + str(event.get("id", ""))
				_event_counts[key] = int(_event_counts.get(key, 0)) + 1
			if event.type == "spawn_monster" and _case.name == "buff-wolf-summon": _pending_shots[_frame + 30] = ["spawn_monster:11001"]
			if event.type == "action_started" and actor == _boss:
				_observed_actions[str(event.action)] = true
				_action_trace.append({"frame": _frame, "action": event.action})
			world._consume(actor, event)
	for actor in world.actors:
		actor._physics_process(delta * world.simulation_scale)
		actor._process(delta)
	world.presentation.sync_buffs(world.actors)
	world._tick_attack_entities(delta * world.simulation_scale)
	world._tick_projectiles(delta * world.simulation_scale)
	world._tick_summons(delta * world.simulation_scale)
	world._tick_monster_spawns()
	world.presentation._process(delta)
	world._tick_damage_numbers(delta)

func _observe_effects() -> void:
	for entry in world.presentation.telegraphs:
		if entry.actor.get_ref() == _boss: _fail("Procedural telegraph replaces an APK wolf effect")
	for entry in world.presentation.active:
		if entry.actor.get_ref() != _boss: continue
		var key := str(entry.key)
		if not entry.authored or not bool(entry.get("source_only", false)) or entry.mesh.visible or entry.burst.visible or entry.sparks.emitting: _fail("Non-source effect overlay: " + key)
		if _effects.has(key): continue
		var source: Dictionary = world.presentation.media.get("effects", {}).get(key, {})
		if str(source.get("source", "")).is_empty() or str(source.get("source_sha256", "")).is_empty(): _fail("Effect has no APK source identity: " + key)
		_effects[key] = {"key": key, "first_frame": _frame, "source": source.get("source", ""), "source_sha256": source.get("source_sha256", ""), "scale": str(entry.authored.scale) if entry.authored else "", "source_only": bool(entry.get("source_only", false)), "source_warning": bool(entry.get("source_warning", false))}
		var capture_frame := _frame + 6
		if not _pending_shots.has(capture_frame): _pending_shots[capture_frame] = []
		_pending_shots[capture_frame].append(key)
		if bool(entry.get("source_warning", false)):
			if not _pending_shots.has(_frame + 18): _pending_shots[_frame + 18] = []
			_pending_shots[_frame + 18].append(key)
		if key.ends_with("_roar_fireball") or key.ends_with("_rangepointer"):
			for offset in [45, 90]:
				if not _pending_shots.has(_frame + offset): _pending_shots[_frame + offset] = []
				_pending_shots[_frame + offset].append(key)
	for projectile in world.projectiles:
		if projectile.state.source_key == str(_boss.combat.actor_key) and is_instance_valid(projectile.visual) and projectile.visual.visible: _fail("Visible generic wolf projectile mesh")

func _capture(frame: int, keys: Array) -> void:
	if not _rendered: return
	var frozen: Array[Dictionary] = []
	for entry in world.presentation.active:
		if not entry.authored: continue
		for emitter in entry.authored.emitters:
			frozen.append({"node": emitter.node, "speed": emitter.node.speed_scale})
			emitter.node.speed_scale = 0.0
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := "%s-%s-%04d.png" % [_prefix, _case.name, frame]
	image.save_png(path)
	var hidden: Array[Node3D] = []
	for entry in world.presentation.active:
		if entry.actor.get_ref() == _boss and keys.has(str(entry.key)) and entry.root.visible:
			hidden.append(entry.root)
			entry.root.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	var baseline := root.get_texture().get_image()
	var baseline_path := path.trim_suffix(".png") + "-without-selected-effects.png"
	baseline.save_png(baseline_path)
	for node in hidden:
		if is_instance_valid(node): node.show()
	var changed := _different_pixels(image, baseline)
	var nonblank := 0
	var reference := image.get_pixel(0, 0)
	for y in range(0, image.get_height(), 2):
		for x in range(0, image.get_width(), 2):
			var pixel := image.get_pixel(x, y)
			if _color_distance(pixel, reference) > 0.08: nonblank += 1
	var isolated_pixels: Dictionary = {}
	for key in keys:
		if not _effects.has(key): continue
		if keys.size() == 1:
			isolated_pixels[key] = changed
			continue
		var selected_roots: Array[Node3D] = []
		for entry in world.presentation.active:
			if entry.actor.get_ref() == _boss and str(entry.key) == str(key) and entry.root.visible:
				selected_roots.append(entry.root)
				entry.root.hide()
		await process_frame
		await RenderingServer.frame_post_draw
		isolated_pixels[key] = _different_pixels(image, root.get_texture().get_image())
		for node in selected_roots: node.show()
	for particle in frozen:
		if is_instance_valid(particle.node): particle.node.speed_scale = particle.speed
	if nonblank < 100: _fail("Blank rendered frame: " + str(frame))
	_shots.append({"frame": frame, "time": float(frame) / HZ, "selected_effects": keys, "image": path, "baseline": baseline_path, "effect_changed_pixels": changed, "isolated_effect_changed_pixels": isolated_pixels, "nonblank_pixels": nonblank, "sample_stride": 2, "projectiles": world.projectiles.size(), "active_fields": world.active_attack_entities.size(), "minions": world.actors.size() - 2})

func _different_pixels(first: Image, second: Image) -> int:
	var changed := 0
	for y in range(0, first.get_height(), 2):
		for x in range(0, first.get_width(), 2):
			if _color_distance(first.get_pixel(x, y), second.get_pixel(x, y)) > 0.045: changed += 1
	return changed

func _color_distance(first: Color, second: Color) -> float:
	return maxf(absf(first.r - second.r), maxf(absf(first.g - second.g), absf(first.b - second.b)))

func _fail(message: String) -> void:
	var text := str(_case.get("name", "setup")) + ": " + message
	if not failures.has(text): failures.append(text)
