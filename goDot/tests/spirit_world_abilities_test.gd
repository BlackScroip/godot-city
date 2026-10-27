extends SceneTree

const STEP := 0.02
var checks := 0
var failures: Array[String] = []
var rows: Array = []
var world: ObservedWorld

class ObservedWorld extends DungeonWorld:
	var areas: Array = []
	var impacts: Array = []
	var summons: Array = []
	func _consume(actor: DungeonActor, event: Dictionary) -> void:
		if event.type == "area": areas.append(event.duplicate(true))
		super._consume(actor, event)

	func _create_summon(actor: DungeonActor, event: Dictionary) -> void:
		super._create_summon(actor, event)
		summons.append({"id": str(event.id), "owner": actor.combat.actor_key, "target": event.get("target_key", ""), "position": DungeonProjectile._array(summon_units.back().position)})

	func _on_impact(hit: Dictionary, target: DungeonActor) -> void:
		# Observe settled contacts without adding hit stop to the controlled test clock.
		impacts.append({"target": target.combat.actor_key, "source": hit.get("source_key", ""), "damage": hit.get("resolved_damage", 0), "origin": hit.get("impact_origin", [])})

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	world = ObservedWorld.new()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.presentation.set_process(false)
	world.presentation.audio_enabled = false
	world.low_effects = true
	for tier in ["50202400", "50202410", "50202420"]:
		_lightning(tier)
	_target_center()
	_random_restore()
	_magnetized_chain()
	_water_repeated_burst()
	var report = {"passed": failures.is_empty(), "checks": checks, "failures": failures, "scenarios": rows, "scope": "Godot world dispatch for source lightning tiers, bounded unique targets, saved RNG replay, recipient-centered caster-owned areas, actual magnetic periodic damage/earthquake and repeated water charges. Actors use real combat configuration with controlled positions and clock; feedback hit stop is disabled by the observer. No original APK runtime or device performance claim."}
	FileAccess.open("res://reports/spirit-world-abilities.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("SPIRIT_WORLD_ABILITIES ", JSON.stringify(report))
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _actor(key: String, friendly: bool, point: Vector3) -> DungeonActor:
	var actor := DungeonActor.new()
	actor.is_player = friendly
	actor.combat = DungeonCombat.new()
	actor.combat.configure(null, null, 1, 0, 193)
	actor.combat.statuses.clear()
	actor.combat._pending.clear()
	actor.combat.drain_events()
	actor.combat.actor_key = key
	actor.combat.attack = 100
	actor.combat.defense = 0
	actor.combat.max_health = 100000
	actor.combat.health = 100000
	world.add_child(actor)
	actor.set_process(false)
	actor.set_physics_process(false)
	actor.position = point
	world.actors.append(actor)
	world._actor_index[key] = actor
	world._bind_impact(actor)
	return actor

func _reset() -> void:
	world.presentation.clear()
	world.pending_attack_entities.clear()
	world.active_attack_entities.clear()
	for projectile in world.projectiles: world._recycle_projectile(projectile)
	world.projectiles.clear()
	for unit in world.summon_units.duplicate(): world._dispose_summon(unit, false)
	for actor in world.actors: actor.free()
	world.actors.clear()
	world._actor_index.clear()
	world.player = null
	world.areas.clear()
	world.impacts.clear()
	world.summons.clear()
	world.diagnostics.clear()
	world.player = _actor("player", true, Vector3.ZERO)

func _step(count: int = 1) -> void:
	for frame in count:
		for actor in world.actors: actor.combat.tick(STEP)
		for actor in world.actors:
			for event in actor.combat.drain_events(): world._consume(actor, event)
		world._tick_attack_entities(STEP)
		world._tick_projectiles(STEP)
		world._tick_summons(STEP)
		world.presentation._process(STEP)

func _lightning(tier: String) -> void:
	_reset()
	var source := world.player
	var points := [Vector3(4, 0, 0), Vector3(-4, 0, 0), Vector3(0, 0, 4), Vector3(0, 0, -4)]
	for index in points.size(): _actor("target:%d" % index, false, points[index])
	var ally := _actor("ally", true, Vector3(1, 0, 1))
	var distant := _actor("distant", false, Vector3(20, 0, 0))
	source.combat.custom_properties["EnemyDistances"] = [1.0, 2.0, 3.0, 4.0, 20.0]
	source.combat.add_buff(tier)
	for frame in 600:
		_step()
		if not world.areas.is_empty(): break
	_step(10)
	var expected := 3 if tier == "50202420" else 1
	var hit_targets: Array = []
	for actor in world.actors:
		if actor.combat.health < actor.combat.max_health: hit_targets.append(actor.combat.actor_key)
	_check(not world.areas.is_empty(), tier + " naturally charges and discharges lightning")
	_check(hit_targets.size() == expected, tier + " hits the configured number of unique nearby targets")
	_check(source.combat.health == source.combat.max_health and ally.combat.health == ally.combat.max_health, tier + " excludes caster and allies")
	_check(distant.combat.health == distant.combat.max_health, tier + " excludes targets outside seven meters")
	_check(world.impacts.all(func(hit): return hit.source == "player"), tier + " retains player damage ownership")
	_check(not source.combat.diagnostics.any(func(message): return "Unsupported area" in message), tier + " no longer uses the unsupported area branch")
	rows.append({"case": tier, "targets": hit_targets, "area_count": world.areas.size(), "summons": world.summons.duplicate(true), "diagnostics": source.combat.diagnostics.duplicate()})

func _target_center() -> void:
	_reset()
	world.player.position = Vector3(-20, 0, 0)
	var host := _actor("host", false, Vector3(10, 0, 0))
	var near_host := _actor("near_host", false, Vector3(11, 0, 0))
	var near_caster := _actor("near_caster", false, Vector3(-19, 0, 0))
	world._consume(host, {"type": "area", "host_key": "host", "source": world.player.combat, "damage": 100.0, "caster_attack": 100.0, "emission": "center", "definition": {"radius": 2.0, "includeSelf": true, "sameCamp": true, "element": "Thunder", "actType": "Spirit"}})
	_check(host.combat.health < host.combat.max_health and near_host.combat.health < near_host.combat.max_health, "Recipient-centered areas affect the host's configured camp")
	_check(near_caster.combat.health == near_caster.combat.max_health, "Recipient-centered areas never jump to the distant caster")
	_check(world.impacts.size() == 2 and world.impacts.all(func(hit): return hit.source == "player" and DungeonWorld.vector(hit.origin) == host.position), "Recipient-centered contacts keep caster attribution and host impact origin")
	rows.append({"case": "recipient_center", "contacts": world.impacts.duplicate(true)})

func _random_restore() -> void:
	_reset()
	for index in 8: _actor("random:%d" % index, false, Vector3(index * 0.2, 0, 1))
	var event := {"type": "area", "source": world.player.combat, "damage": 10.0, "caster_attack": 100.0, "definition": {"radius": 7.0, "randomTargets": true, "maxTargets": 3, "actType": "Spirit"}}
	var saved: Dictionary = JSON.parse_string(JSON.stringify(world.player.combat.snapshot()))
	world._consume(world.player, event.duplicate(true))
	var first: Array = world.impacts.map(func(hit): return hit.target)
	world.impacts.clear()
	world.player.combat.restore(saved)
	world._consume(world.player, event.duplicate(true))
	var replay: Array = world.impacts.map(func(hit): return hit.target)
	_check(first.size() == 3 and first == replay, "JSON-restored combat RNG selects the same three unique targets")
	event.definition.maxTargets = 0
	world.impacts.clear()
	world._consume(world.player, event)
	_check(world.impacts.is_empty(), "Zero target capacity emits no damage")
	rows.append({"case": "rng_restore", "first": first, "replay": replay})

func _magnetized_chain() -> void:
	_reset()
	var victim := _actor("magnetized", false, Vector3(4, 0, 0))
	world.player.combat.add_buff("50203400")
	world._apply_hit(world.player, victim, {"damage": 10.0, "sequence": 1, "emission": "magnetize", "attack_collision": false, "definition": {"actType": "DodgeAtk"}})
	_check(victim.combat.statuses.has("50203402"), "Source dodge attack installs magnetic periodic damage")
	_step(340)
	_check(victim.combat.statuses.has("800511"), "Magnetic lightning applies its source wound modifier")
	var earthquakes: Array = world.summons.filter(func(row): return row.id == "502025510")
	_check(not earthquakes.is_empty() and earthquakes.all(func(row): return row.owner == "player" and row.target == "magnetized"), "Five magnetic lightning ticks create a player-owned earthquake at the victim")
	_check(not earthquakes.is_empty() and earthquakes.all(func(unit): return DungeonWorld.vector(unit.position).is_equal_approx(victim.position + Vector3.UP)), "Magnetic earthquake world position includes the source offset at the recipient")
	_check(world.impacts.all(func(hit): return hit.source == "player"), "Magnetic damage and earthquake preserve player attribution")
	rows.append({"case": "magnetic_chain", "earthquakes": earthquakes, "contacts": world.impacts.size()})

func _water_repeated_burst() -> void:
	_reset()
	var victim := _actor("water_target", false, Vector3(0, 0, 3))
	world.player.combat.add_buff("50202200")
	for cycle in 2:
		for index in 10:
			world._apply_hit(world.player, victim, {"damage": 10.0, "sequence": cycle + 1, "emission": "water_normal:%d:%d" % [cycle, index], "attack_collision": false, "definition": {"actType": "NormalAtk"}})
			_step(6)
		_check(world.player.combat.buff_layers("50202201") == 5, "Water burst %d recharges five stacks" % cycle)
		world._apply_hit(world.player, victim, {"damage": 10.0, "sequence": cycle + 1, "emission": "water_heavy:%d" % cycle, "attack_collision": false, "definition": {"actType": "SpecAtk"}})
		_step(65)
		_check(world.player.combat.buff_layers("50202201") == 0, "Water burst %d consumes all stacks" % cycle)
	var rays: Array = world.summons.filter(func(row): return row.id == "50202201")
	_check(rays.size() == 10 and rays.all(func(row): return row.owner == "player"), "Two real world water bursts produce ten caster-owned ray summons")
	rows.append({"case": "water_twice", "rays": rays.size()})

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)
