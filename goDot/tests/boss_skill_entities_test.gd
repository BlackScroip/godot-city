extends "res://tests/spirit_world_abilities_test.gd"

func _run() -> void:
	world = ObservedWorld.new()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.presentation.set_process(false)
	world.presentation.audio_enabled = false
	_delay_and_restore()
	_continuous_field()
	_physical_delay()
	_end_summon()
	_end_carrier()
	_zero_continuous_cap()
	_action_changed()
	var report = {"passed": failures.is_empty(), "checks": checks, "failures": failures, "scenarios": rows, "scope": "Actual serialized Boss attack definitions through world entity creation, source delay, fixed emission origin/facing, active CheckTime window, per-target continuous cadence and JSON checkpoint, physical activation and end-created summon. Controlled headless Godot reconstruction; no original APK runtime equivalence claim."}
	FileAccess.open("res://reports/boss-skill-entities.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("BOSS_SKILL_ENTITIES ", JSON.stringify(report))
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _boss(id: int, action: String, select: Callable) -> Dictionary:
	_reset()
	var boss := _actor("boss", false, Vector3.ZERO)
	boss.actor_id = id
	boss.combat.configure_enemy(id, 991)
	boss.combat.actor_key = "boss"
	boss.face_direction(Vector3.BACK)
	var definition: Dictionary = boss.combat._action(str(boss.combat.enemy.group), action)
	for hit in definition.get("hits", []):
		if hit.get("enabled", false) and select.call(DungeonWorld._raw_definition(hit)):
			var event := {"type": "hit", "definition": hit.duplicate(true), "source": boss.combat, "damage": 100.0, "sequence": boss.combat._cast_sequence, "emission": action, "action": action, "slot": 0}
			var raw := DungeonWorld._raw_definition(hit)
			world.player.position = Vector3(0, 0, 2)
			var point = world._hit_origin(boss, event)
			var emit: Dictionary = raw.get("EmitProperty", {})
			var yaw = deg_to_rad(float(emit.get("EmitRotation", {}).get("y", 0)))
			var offset = DungeonWorld.vector(emit.get("EmitOffset", {})) + Basis(Vector3.UP, yaw) * (DungeonWorld.vector(emit.get("AfterRotateEmitOffset", {})) + Vector3(0, 0, float(hit.get("offset", 0))))
			var center: Vector3 = point + DungeonProjectile.orient(offset, boss.facing)
			world.player.position = center
			world._consume(boss, event)
			return {"boss": boss, "raw": raw, "hit": hit, "center": center}
	failures.append("Missing source entity: %d %s" % [id, action])
	return {}

func _delay_and_restore() -> void:
	var test := _boss(52001, "attack5", func(raw): return raw.get("EntityType", "") == "EET_FrameFan" and float(raw.get("EntityProperty", {}).get("Delay", 0)) == 1.0)
	if test.is_empty(): return
	_check(world.impacts.is_empty() and world.pending_attack_entities.size() == 1, "Chimera range creates its telegraph without early damage")
	world._tick_attack_entities(0.4)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(world.transient_snapshot()))
	test.boss.position += Vector3(30, 0, 30)
	test.boss.face_direction(Vector3.FORWARD)
	world.restore_transients(saved)
	world._tick_attack_entities(0.599)
	_check(world.impacts.is_empty(), "Restored Chimera delay retains the remaining wait")
	var before: int = world.presentation.spawned
	world._tick_attack_entities(0.001)
	_check(world.impacts.size() == 1 and world.player.combat.health < world.player.combat.max_health, "Chimera damage begins at its source one-second delay")
	_check(world.presentation.spawned > before, "Chimera delayed activation emits its exact source effect")
	_check(world.impacts.size() == 1 and DungeonWorld.vector(world.impacts[0].origin).is_equal_approx(test.center), "Moving the caster does not move an already emitted field")
	world._tick_attack_entities(0.05)
	_check(world.impacts.size() == 1, "Noncontinuous CheckTime does not repeatedly damage an existing target")
	world.player.position += Vector3(50, 0, 0)
	var entrant := _actor("late_entrant", true, test.center)
	world._tick_attack_entities(0.02)
	_check(entrant.combat.health < entrant.combat.max_health, "An actor entering an active range can still be hit during CheckTime")
	world._tick_attack_entities(0.05)
	_check(world.active_attack_entities.is_empty(), "The Chimera field ends after its configured CheckTime")
	rows.append({"case": "chimera_delay_restore", "contacts": world.impacts.size(), "center": str(test.center)})

func _continuous_field() -> void:
	var test := _boss(13001, "attack5", func(raw): return bool(raw.get("EntityProperty", {}).get("CheckTimeCauseContinuousTrigger", false)))
	if test.is_empty(): return
	var entity: Dictionary = test.raw.EntityProperty
	world._tick_attack_entities(float(entity.Delay))
	_check(world.impacts.size() == 1, "Wolf continuous field hits on activation")
	world._tick_attack_entities(0.25)
	_check(world.impacts.size() == 1, "Wolf continuous field waits its per-target half-second interval")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(world.transient_snapshot()))
	_check(_json_values_only(world.active_attack_entities), "Continuous entity checkpoint contains no Objects or Vector3 runtime values")
	world.restore_transients(saved)
	for index in 9: world._tick_attack_entities(0.25)
	_check(world.impacts.size() == 5, "Wolf 2.5-second field deals five half-second pulses without a duplicate checkpoint hit")
	_check(world.active_attack_entities.is_empty(), "Wolf continuous field expires at the source boundary")
	rows.append({"case": "wolf_continuous", "contacts": world.impacts.size(), "duration": entity.CheckTime})

func _physical_delay() -> void:
	var test := _boss(52003, "attack4", func(raw): return raw.get("EntityType", "") == "EET_Physical" and float(raw.get("EntityProperty", {}).get("Delay", 0)) > 0)
	if test.is_empty(): return
	var delay = float(test.raw.EntityProperty.Delay)
	_check(world.projectiles.is_empty() and world.pending_attack_entities.size() == 1, "Death's delayed physical entity does not fly before activation")
	world._tick_attack_entities(delay - 0.001)
	_check(world.projectiles.is_empty(), "Physical entity retains its complete source delay")
	world._tick_attack_entities(0.001)
	_check(world.projectiles.size() == 1 and world.pending_attack_entities.is_empty(), "Physical entity enters the real projectile simulation once at activation")
	rows.append({"case": "death_physical", "delay": delay, "projectiles": world.projectiles.size()})

func _end_summon() -> void:
	var test := _boss(33001, "EX_Attack3", func(raw): return str(raw.get("EntityProperty", {}).get("AddSummonUnitDefOnEnd", {}).get("AddSummonUnitId", "")) == "43300103")
	if test.is_empty(): return
	var entity: Dictionary = test.raw.EntityProperty
	world._tick_attack_entities(float(entity.Delay))
	_check(world.summons.is_empty(), "Deer waits for field expiration before creating its end summon")
	test.boss.face_direction(Vector3.FORWARD)
	world._tick_attack_entities(float(entity.CheckTime))
	for event in test.boss.combat.drain_events(): world._consume(test.boss, event)
	_check(world.summons.size() == 1 and world.summons[0].id == "43300103", "Deer creates the exact authored end summon once")
	_check(world.summons.size() == 1 and DungeonWorld.vector(world.summons[0].position).is_equal_approx(test.center), "Deer's end summon inherits the completed field's location")
	_check(world.summon_units.size() == 1 and DungeonWorld.vector(world.summon_units[0].get("fixed_facing", [])).is_equal_approx(Vector3.BACK), "Deer's end summon retains the completed field's facing after its caster turns")
	world._tick_attack_entities(1.0)
	_check(world.summons.size() == 1, "Ended fields cannot duplicate child summons on later updates")
	rows.append({"case": "deer_end_summon", "summons": world.summons.duplicate(true)})

func _end_carrier() -> void:
	_reset()
	var boss := _actor("boss", false, Vector3.ZERO)
	boss.actor_id = 43001
	boss.combat.configure_enemy(43001, 991)
	boss.combat.actor_key = "boss"
	var action: Dictionary = boss.combat._action(str(boss.combat.enemy.group), "EX_Attack3")
	for hit in action.get("hits", []):
		var raw := DungeonWorld._raw_definition(hit)
		if int(hit.get("damageId", 0)) > 0 or raw.get("EntityProperty", {}).get("AddSummonUnitDefOnEnd", {}).get("AddSummonUnitId", "") != "44300191": continue
		boss.combat._emit_hit({"hit": hit, "action": "EX_Attack3", "at": 0.0, "slot": 0, "sequence": boss.combat._cast_sequence})
		var emitted: Array = boss.combat.drain_events().filter(func(event): return event.type == "hit")
		_check(emitted.size() == 1 and emitted[0].definition.get("carrier_only", false), "Golem emits its real nonphysical zero-damage carrier")
		for event in emitted: world._consume(boss, event)
		_check(world.impacts.is_empty() and world.player.combat.health == world.player.combat.max_health, "Carrier contact causes no phantom damage or hit callback")
		world._tick_attack_entities(float(raw.EntityProperty.CheckTime))
		for event in boss.combat.drain_events(): world._consume(boss, event)
		_check(world.summons.size() == 1 and world.summons[0].id == "44300191", "Golem carrier emits its authored ending shockwave")
		rows.append({"case": "golem_zero_damage_carrier", "summons": world.summons.duplicate(true)})
		return
	failures.append("Missing golem source carrier")

func _zero_continuous_cap() -> void:
	var test := _boss(13001, "attack5", func(raw): return bool(raw.get("EntityProperty", {}).get("CheckTimeCauseContinuousTrigger", false)))
	if test.is_empty(): return
	var raw: Dictionary = test.raw.duplicate(true)
	raw.EntityProperty.CheckActiveEffectTargetMaxCount = 0
	world.pending_attack_entities[0].hit.definition.raw = JSON.stringify(raw)
	world._tick_attack_entities(float(raw.EntityProperty.Delay))
	world._tick_attack_entities(0.5)
	_check(world.impacts.size() == 2, "Native CheckShouldHit maxCount zero means unlimited continuous contacts")

func _action_changed() -> void:
	var test := _boss(33001, "roar", func(raw): return bool(raw.get("DeadActionChanged", false)) and raw.get("EntityType", "").begins_with("EET_Frame"))
	if test.is_empty(): return
	world._tick_attack_entities(float(test.raw.EntityProperty.Delay))
	_check(not world.active_attack_entities.is_empty(), "Deer source field remains alive during its originating action")
	test.boss.combat._cast_sequence += 1
	world._tick_attack_entities(0.01)
	_check(world.active_attack_entities.is_empty(), "DeadActionChanged removes an active field when the source action switches")

func _json_values_only(value: Variant) -> bool:
	if value is Dictionary:
		for child in value.values():
			if not _json_values_only(child): return false
		return true
	if value is Array:
		for child in value:
			if not _json_values_only(child): return false
		return true
	return value == null or value is bool or value is int or value is float or value is String
