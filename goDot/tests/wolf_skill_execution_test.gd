extends "res://tests/spirit_world_abilities_test.gd"

const GROUP := "ActGroup_senlinlangwang"

func _run() -> void:
	world = ObservedWorld.new()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.presentation.set_process(false)
	world.presentation.audio_enabled = false
	for hz in [30, 60, 120]:
		_zero_time_emit(hz)
		_attack_loop(hz)
	_multipoint_geometry()
	_visual_carrier()
	_generation_chain()
	_rage_scale()
	_emitter_lifetime()
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "scenarios": rows, "scope": "APK wolf action execution: zero-time event ordering, five-loop Add counter, native MultiPoint total count and point delays/offsets/rotations, saved spherical random offsets, no-damage boss entry carriers, buff-generated wolves, and custom-property rage scaling applied once."}
	FileAccess.open("res://reports/wolf-skill-execution-test.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("WOLF_SKILL_EXECUTION ", JSON.stringify(report))
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _wolf() -> DungeonActor:
	_reset()
	world.monster_spawn_queue.clear()
	var wolf := _actor("wolf", false, Vector3(3, 0, 7))
	wolf.actor_id = 13001
	wolf.combat.configure_enemy(13001, 991)
	wolf.combat.actor_key = "wolf"
	wolf.combat.statuses.clear()
	wolf.combat._pending.clear()
	wolf.combat.drain_events()
	wolf.combat.enemy_ai_enabled = true
	wolf.combat.custom_properties["OP_AIAction"] = ""
	wolf.face_direction(Vector3.BACK)
	world.player.position = Vector3(100, 0, 100)
	return wolf

func _source_hit(wolf: DungeonActor, action: String, emit_type: String = "EET_MultiPoint") -> Dictionary:
	for hit in wolf.combat._action(GROUP, action).get("hits", []):
		if bool(hit.get("enabled", false)) and DungeonWorld._raw_definition(hit).get("EmitType", "") == emit_type: return hit
	failures.append("Missing wolf source hit: " + action)
	return {}

func _hits(combat: DungeonCombat) -> Array:
	return combat.drain_events().filter(func(event): return event.type == "hit")

func _zero_time_emit(hz: int) -> void:
	var wolf := _wolf()
	wolf.combat._start(wolf.combat._action(GROUP, "EX_RandomFireRange"), 0)
	wolf.combat._tick_enemy_interrupts()
	_check(wolf.combat.current_action == "EX_RandomFireRange", "%dHz zero-time interrupt waits for its payload" % hz)
	wolf.combat.tick(1.0 / hz)
	var emitted := _hits(wolf.combat)
	_check(emitted.size() == 4, "%dHz emits all four zero-delay source points together" % hz)
	_check(emitted.all(func(event): return is_equal_approx(float(event.clock), 1.0 / hz)), "%dHz MultiPoint ignores inherited one-second interval" % hz)
	for event in emitted:
		world._consume(wolf, event)
		var raw := DungeonWorld._raw_definition(event.definition)
		var selected: Dictionary = raw.EmitProperty.PointData[int(event.emit_index)]
		var center: Vector3 = world._frame_entity_transform(wolf, event).position
		var nominal := wolf.position + DungeonProjectile.orient(DungeonWorld.vector(selected.Offset), wolf.facing)
		var delta := center - nominal
		_check(is_zero_approx(delta.y) and delta.length() <= 5.00001, "%dHz source random offset stays in the projected five-meter sphere" % hz)
		_check(delta.is_equal_approx(DungeonWorld.vector(event.get("emit_random_offset", []))), "%dHz emitted random point is fixed for presentation and collision" % hz)
	wolf.combat._tick_enemy_interrupts()
	_check(wolf.combat.current_action == "idle", "%dHz helper returns to idle after creating its fields" % hz)
	_check(world.pending_attack_entities.size() == 4, "%dHz all four delayed fields survive their source action" % hz)
	rows.append({"case": "zero_time_range", "hz": hz, "emissions": emitted.size(), "pending_fields": world.pending_attack_entities.size()})

func _attack_loop(hz: int) -> void:
	var wolf := _wolf()
	wolf.combat.custom_properties["attack4_loopcount"] = 99
	wolf.combat._start(wolf.combat._action(GROUP, "attack4"), 0)
	var starts: Array = []
	var loop_hits := 0
	for frame in 13 * hz:
		wolf.combat._tick_enemy_interrupts()
		wolf.combat.tick(1.0 / hz)
		for event in wolf.combat.drain_events():
			if event.type == "action_started": starts.append(str(event.get("action", "")))
			if event.type == "hit" and event.action == "attack4_loop": loop_hits += 1
	_check(int(wolf.combat.property_value("attack4_loopcount")) == 5, "%dHz loop Set resets and Add advances to five" % hz)
	_check(starts.count("attack4_loop") == 5 and starts.has("attack2"), "%dHz source combo exits after five loops" % hz)
	_check(loop_hits == 10, "%dHz five loops emit both authored claw hits" % hz)
	rows.append({"case": "attack4_chain", "hz": hz, "loop_hits": loop_hits, "starts": starts})

func _multipoint_geometry() -> void:
	var wolf := _wolf()
	wolf.face_direction(Vector3.RIGHT)
	wolf.combat.add_buff("41300101", 1)
	var hit := _source_hit(wolf, "attack3")
	wolf.combat._schedule(hit, wolf.combat._clock, "attack3", 0, 0)
	wolf.combat.tick(0)
	var emitted := _hits(wolf.combat)
	_check(emitted.size() == 5, "Wolf fan emits its five source projectile points")
	var points: Array = DungeonWorld._raw_definition(hit).EmitProperty.PointData
	for event in emitted:
		var point: Dictionary = points[int(event.emit_index)]
		var expected := wolf.position + DungeonProjectile.orient(DungeonWorld.vector(point.Offset), wolf.facing)
		var facing := wolf.facing.rotated(Vector3.UP, deg_to_rad(float(point.Rotate.y)))
		var state := world._projectile(wolf, event)
		_check(state.position.is_equal_approx(expected), "Fan projectile %d uses its source offset once" % int(event.emit_index))
		_check(state.direction.is_equal_approx(facing), "Fan projectile %d uses its source rotation" % int(event.emit_index))
		var field := world._frame_entity_transform(wolf, event)
		_check(field.position.is_equal_approx(expected) and field.facing.is_equal_approx(facing), "Frame and physical emitters share the same point transform")
	rows.append({"case": "fan_points", "count": emitted.size()})

func _visual_carrier() -> void:
	var wolf := _wolf()
	var hit := _source_hit(wolf, "bosspose")
	wolf.combat._schedule(hit, wolf.combat._clock, "bosspose", 0, 0)
	wolf.combat.tick(0)
	var emitted := _hits(wolf.combat)
	_check(emitted.size() == 4 and emitted.all(func(event): return bool(event.definition.get("carrier_only", false))), "Boss entry retains all four no-damage eruption carriers")
	world.player.position = wolf.position + Vector3(6, 0, 0)
	var before: int = world.presentation.spawned
	for event in emitted: world._consume(wolf, event)
	_check(world.presentation.spawned > before, "No-damage boss entry dispatches its APK eruption effects")
	_check(world.impacts.is_empty() and world.player.combat.health == world.player.combat.max_health, "Visual carriers do not create phantom damage or contact feedback")
	rows.append({"case": "boss_entry_carriers", "count": emitted.size()})

func _generation_chain() -> void:
	var wolf := _wolf()
	world.room_spawn_points.clear()
	for index in 8: world.room_spawn_points.append({"Id": 10 + index, "Position": {"x": index * 2, "y": 0, "z": 20}})
	wolf.combat.add_buff("41300113", 3)
	for frame in 60:
		wolf.combat.tick(1.0 / 60)
		for event in wolf.combat.drain_events():
			if event.type == "spawn_monster": world._consume(wolf, event)
	_check(world.monster_spawn_queue.size() == 3, "Source 41300113/14/15 chain queues three wolves")
	_check(world.monster_spawn_queue.all(func(request): return int(request.spawn.enemy_id) == 11001 and float(request.spawn.position[2]) == 20.0), "Generated wolves use source monster ID and room markers")
	world.monster_spawn_queue.clear()
	world._spawn_monsters(wolf, {"definition": {"MonsterId": 11001, "SpawnPoints": [10, 11], "GenerationMode": 0, "GenerationTotalCount": 0}})
	_check(world.monster_spawn_queue.is_empty(), "Explicit action generation total zero remains empty")
	rows.append({"case": "buff_wolf_generation", "expected": 3})

func _rage_scale() -> void:
	var wolf := _wolf()
	var hit := _source_hit(wolf, "attack3", "EET_Normal")
	var original := DungeonWorld._raw_definition(hit)
	wolf.combat.add_buff("41300101", 1)
	_check(is_equal_approx(float(wolf.combat.property_value("kuangbao-100")), 100), "Real rage buff exposes custom scale value 100")
	var modified: Dictionary = wolf.combat._modified_attack_definition(hit)
	var raw := DungeonWorld._raw_definition(modified)
	for field in ["ModelBoxColliderSize", "ModlePrefabSize"]:
		if original.EntityProperty.has(field):
			_check(DungeonWorld.vector(raw.EntityProperty[field]).is_equal_approx(DungeonWorld.vector(original.EntityProperty[field]) * 1.1), "Rage scales source " + field + " by 1.1")
	for field in ["EffectTriggerDef", "EffectDelayTriggerDef"]:
		if original.EntityProperty.get(field, {}).has("Scale"):
			_check(DungeonWorld.vector(raw.EntityProperty[field].Scale).is_equal_approx(DungeonWorld.vector(original.EntityProperty[field].Scale) * 1.1), "Rage scales source " + field + " once")
	_check(wolf.combat._modified_attack_definition(modified) == modified, "Resolved rage entity scaling cannot apply twice")
	_check(DungeonWorld._raw_definition(hit) == original, "Rage scaling preserves the immutable APK definition")
	rows.append({"case": "rage_entity_scale", "factor": 1.1})

func _emitter_lifetime() -> void:
	for cancel in [false, true]:
		var wolf := _wolf()
		wolf.combat.add_buff("41300101", 1)
		var hit := _source_hit(wolf, "attack3").duplicate(true)
		var raw := DungeonWorld._raw_definition(hit).duplicate(true)
		raw.EmitProperty.EndEmitWhenActionChange = cancel
		raw.EmitProperty.PointData[0].Delay = 0.25
		raw.EmitProperty.PointData[1].Delay = 0.5
		raw.EmitProperty.PointData.resize(2)
		hit.count = 2
		hit.raw = JSON.stringify(raw)
		wolf.combat._schedule(hit, wolf.combat._clock, "attack3", 0, 0)
		wolf.combat.tick(0)
		_check(_hits(wolf.combat).is_empty(), "PointData delay defers the first shot")
		wolf.combat._cancel_sequence(wolf.combat._cast_sequence)
		var saved: Dictionary = JSON.parse_string(JSON.stringify(wolf.combat.snapshot()))
		wolf.combat.tick(0.25)
		var first := _hits(wolf.combat)
		wolf.combat.tick(0.25)
		var second := _hits(wolf.combat)
		_check(first.size() == (0 if cancel else 1) and second.size() == (0 if cancel else 1), "Emitter lifecycle honors EndEmitWhenActionChange=%s" % cancel)
		_check(wolf.combat.restore(saved), "Emitter timeline checkpoint restores")
		wolf.combat.tick(0.5)
		_check(_hits(wolf.combat).size() == (0 if cancel else 2), "Restored emitter retains both point delays and action independence")
	var wolf := _wolf()
	var hit := _source_hit(wolf, "attack3")
	wolf.combat._schedule(hit, wolf.combat._clock + 1, "attack3", 0, 0)
	wolf.combat._cancel_sequence(wolf.combat._cast_sequence)
	wolf.combat.tick(2)
	_check(_hits(wolf.combat).is_empty(), "An action cancelled before its emitter begins emits no future shots")
