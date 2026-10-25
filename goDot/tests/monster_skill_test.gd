extends SceneTree

var assertions := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message)

func _run() -> void:
	_arc_cases()
	var world := DungeonWorld.new()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.presentation.set_process(false)
	world.presentation.audio_enabled = false
	var player := _actor(world, true)
	world.player = player
	var monster := _actor(world, false)
	_carrier_cases(world, monster, player)
	_field_cases(world, monster, player)
	var report = {"passed": failures.is_empty(), "assertions": assertions, "failures": failures, "scope": "Source ARC horizontal angles and owner-local offsets; three zero-damage Griffin carriers, distinct landing explosions and JSON replay; source pull field boundaries, immunity and no damage, shake or hit stop. Original APK runtime, pitch/roll and original pull units are not validated."}
	FileAccess.open("res://reports/monster-skills.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("MONSTER_SKILLS ", JSON.stringify(report))
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _actor(world: DungeonWorld, is_player: bool) -> DungeonActor:
	var actor := DungeonActor.new()
	actor.is_player = is_player
	actor.combat = DungeonCombat.new()
	if is_player: actor.combat.configure()
	else: actor.combat.configure_enemy(23001, 731)
	actor.combat.actor_key = "player" if is_player else "griffin"
	actor.combat.drain_events()
	actor.facing = Vector3.BACK
	world.add_child(actor)
	world.actors.append(actor)
	return actor

func _arc_cases() -> void:
	var raw = {"EmitType": "EET_ARC", "EmitProperty": {"Num": 3, "IntervalDegree": 40, "EmitType": "EAE_Sector_RelativeSelfDir", "DegreeOffet": 90}}
	for index in 3:
		var direction = DungeonProjectile.emission_facing(raw, index, Vector3.BACK, Vector3.RIGHT)
		check(direction.is_equal_approx(Vector3.BACK.rotated(Vector3.UP, deg_to_rad(-40 + 40 * index))), "Three-shot fan has distinct source angles %d" % index)
	raw.EmitProperty.Num = 2
	raw.EmitProperty.IntervalDegree = 41
	check(DungeonProjectile.emission_facing(raw, 0, Vector3.BACK, Vector3.RIGHT).is_equal_approx(Vector3.BACK.rotated(Vector3.UP, deg_to_rad(-20))), "Odd negative sector start truncates toward zero")
	raw.EmitProperty.EmitType = "EAE_Sector_DirToTarget"
	raw.EmitProperty.Num = 1
	check(DungeonProjectile.emission_facing(raw, 0, Vector3.BACK, Vector3.RIGHT).is_equal_approx(Vector3.RIGHT), "Target sector follows target instead of owner")
	check(DungeonProjectile.emission_facing(raw, 0, Vector3.BACK, Vector3.ZERO).is_equal_approx(Vector3.BACK), "Coincident target keeps finite owner direction")
	raw.EmitProperty.EmitType = "EAE_Circle_DirToTarget"
	raw.EmitProperty.Num = 7
	check(DungeonProjectile.emission_facing(raw, 1, Vector3.BACK, Vector3.RIGHT).is_equal_approx(Vector3.BACK.rotated(Vector3.UP, deg_to_rad(141))), "Source circle uses owner basis, degree offset and integer interval")
	raw.EmitProperty.EmitType = "EAE_Circle_RelativeSelfDir"
	check(DungeonProjectile.emission_facing(raw, 0, Vector3.BACK, Vector3.RIGHT).is_equal_approx(Vector3.BACK), "Relative circle has zero initial phase")
	raw.EmitProperty.PosOffset = {"x": 1, "z": 2}
	raw.EmitProperty.RadiusOffset = 3
	raw.EmitProperty.EmitRotation = {"y": 90}
	var state := DungeonProjectile.new()
	state.configure({"definition": {"raw": JSON.stringify(raw)}}, Vector3.ZERO, Vector3.RIGHT, Vector3.ZERO, Vector3.BACK)
	check(state.position.is_equal_approx(Vector3(1, 0, 5)), "Arc origin offset follows owner, independently of scattered shot direction")
	check(state.direction.is_equal_approx(Vector3.RIGHT), "ARC EmitRotation.y is not an extra yaw")

func _drain(world: DungeonWorld, source: DungeonActor) -> Array:
	var events: Array = source.combat.drain_events()
	for event in events: world._consume(source, event)
	return events

func _carrier_cases(world: DungeonWorld, monster: DungeonActor, player: DungeonActor) -> void:
	check(monster.combat.spawn_summon("42300102"), "Original Griffin carrier can spawn without a damage definition")
	_drain(world, monster)
	monster.combat.tick(0.001)
	var emitted = _drain(world, monster).filter(func(event): return event.type == "hit")
	check(emitted.size() == 3 and world.projectiles.size() == 3, "Carrier emits all three physical shots")
	var before = player.combat.health
	var endpoints: Array = []
	for entry in world.projectiles:
		var state: DungeonProjectile = entry.state
		check(float(state.hit.damage) == 0 and not state.can_hit("player"), "Flying carrier has no direct damage or actor collision")
		endpoints.append(state.destination)
	check(endpoints[0].distance_to(endpoints[1]) > 5 and endpoints[1].distance_to(endpoints[2]) > 5, "Carrier destinations are spread across the fan")
	world._tick_projectiles(0.5)
	check(player.combat.health == before, "Carrier flight does not damage player")
	world._tick_projectiles(0.5)
	check(world.projectiles.is_empty(), "All carrier flights finish at authored duration")
	var children = _drain(world, monster).filter(func(event): return event.type == "summon" and event.id == "42300104")
	check(children.size() == 3, "Each carrier creates its landing explosion")
	player.position = endpoints[0]
	player.combat.clear_impact_state()
	monster.combat.tick(0.001)
	var impacts = monster.combat.drain_events().filter(func(event): return event.type == "hit")
	check(impacts.size() == 3, "Each landing explosion retains its damage event")
	for index in impacts.size():
		var point = world._hit_origin(monster, impacts[index])
		check(point.distance_to(endpoints[index]) < 0.001, "Same-ID landing explosion keeps its own center %d" % index)
		world._consume(monster, impacts[index])
	check(player.combat.health < before, "Landing explosion damages player at its own center")
	var saved = JSON.parse_string(JSON.stringify(world.transient_snapshot()))
	var expected: Array = []
	for event in impacts: expected.append(world._hit_origin(monster, event))
	for unit in world.summon_units.duplicate(): world._dispose_summon(unit, false)
	world.restore_transients(saved)
	for index in impacts.size():
		check(world._hit_origin(monster, impacts[index]).distance_to(expected[index]) < 0.001, "JSON replay keeps distinct summon instance identity %d" % index)
	check(world.diagnostics.is_empty() and monster.combat.diagnostics.is_empty(), "Carrier and landing chain have no unresolved diagnostics")
	monster.combat._spawn_summon("42300104", monster.combat._clock, "test", 0, 2.0)
	_drain(world, monster)
	check(world.summon_units.back().position.distance_to(monster.position + monster.facing * 2.0) < 0.001, "Instance token preserves legacy summon forward offset")

func _field_cases(world: DungeonWorld, monster: DungeonActor, player: DungeonActor) -> void:
	var raw: Dictionary = monster.combat._summon_index["42300502"].raw_data
	var unit = {"owner": "griffin", "position": Vector3.ZERO}
	var before = player.combat.health
	player.clear_impact_state()
	player.position = Vector3(0, 0, 2)
	world._camera_impulses.clear()
	world._monster_field_feedback(unit, raw, 0.1)
	check(player.knockback_elapsed == 0 and player.knockback_direction.dot(Vector3.FORWARD) > 0.99, "Source sand field pulls inward")
	check(player.combat.health == before and player.combat.impact_pause == 0 and player.combat.stagger_remaining == 0 and world._camera_impulses.is_empty(), "Continuous pull causes no damage, stagger, stop or shake")
	for protected in ["outside", "center", "height", "actor_invulnerability", "combat_invulnerability", "dodge", "block", "zero_power", "same_team"]:
		player.clear_impact_state()
		player.position = Vector3(0, 0, 5 if protected == "outside" else 2)
		if protected == "center": player.position = Vector3.ZERO
		if protected == "height": player.position.y = 10
		player.invulnerability = 1 if protected == "actor_invulnerability" else 0
		player.combat.invincible = 1 if protected == "combat_invulnerability" else 0
		player.combat._dodge_time = 1 if protected == "dodge" else 0
		player.combat._block_time = 1 if protected == "block" else 0
		player.is_player = protected != "same_team"
		var definition: Dictionary = monster.combat._summon_index["45200402"].raw_data if protected == "zero_power" else raw
		world._monster_field_feedback(unit, definition, 0.1)
		check(player.knockback_elapsed < 0, "Pull excludes " + protected)
	player.is_player = true
	player.invulnerability = 0
	player.combat.invincible = 0
