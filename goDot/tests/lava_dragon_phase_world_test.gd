extends SceneTree

const STEP := 1.0 / 60.0
var checks := 0
var failures: Array[String] = []
var _case_difficulty := 0

class ObservedWorld:
	extends DungeonWorld
	var test_time := 0.0
	var phase_summons: Array = []
	var timer_entities: Array = []
	var shield_drains: Array = []

	func _consume(actor: DungeonActor, event: Dictionary) -> void:
		if actor.actor_id == 23002:
			if event.type == "summon" and str(event.get("id", "")) == "42300255":
				phase_summons.append({"time": test_time, "shield": actor.combat.shield, "health": actor.combat.health, "lock_present": actor.combat.statuses.has("42300205")})
			if event.type == "hit" and str(event.get("summon_id", "")) == "42300255":
				timer_entities.append({"time": test_time, "index": int(event.get("emit_index", -1)), "damage": float(event.get("damage", 0)), "damage_id": int(event.get("definition", {}).get("damageId", 0))})
		super._consume(actor, event)

	func _apply_raw_buff(target: RefCounted, definition: Dictionary, caster: RefCounted) -> void:
		var draining = str(definition.get("BuffTriggerId", "")) == "42300204" and target is DungeonCombat
		var before = target.shield if draining else 0.0
		super._apply_raw_buff(target, definition, caster)
		if draining:
			shield_drains.append({"time": test_time, "owner": target.actor_key, "before": before, "after": target.shield})

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scenarios: Array = []
	for difficulty in [0, 2]:
		_case_difficulty = difficulty
		scenarios.append(await _scenario(difficulty))
	var report = {"passed": failures.is_empty(), "checks": checks, "failures": failures, "scenarios": scenarios, "scope": "Unmodified world actor spawn, serialized AI observer, lethal receive HP lock, deferred trigger package, actual funnel physical entities and owner-only disposal buffs at source difficulty zero and two. Shield is never assigned or observer/trigger buffs manually added. Difficulty two gives a fractional shield amount and distinguishes integer truncation from rounding. Headless Godot reconstruction; no original APK runtime or device performance claim."}
	FileAccess.open("res://reports/lava-dragon-phase-world-test.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("LAVA_DRAGON_PHASE_WORLD ", JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures, "scenarios": scenarios.map(func(row): return {"difficulty": row.difficulty, "max_health": row.max_health, "entities": row.timer_entities.size(), "shield_drains": row.shield_drains.size(), "reduction": row.shield_reduction_per_entity, "final_shield": row.final_shield})}))
	quit(0 if failures.is_empty() else 1)

func _scenario(difficulty: int) -> Dictionary:
	for name in ["move_left", "move_right", "move_up", "move_down"]:
		if not InputMap.has_action(name): InputMap.add_action(name)
	var world := ObservedWorld.new()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.auto_attack_enabled = false
	world.presentation.set_process(false)
	world.presentation.audio_enabled = false
	world.low_effects = true
	_create_arena(world)
	var player_combat := DungeonCombat.new()
	_check(player_combat.configure().success, "Test player configures")
	player_combat.max_health = 1000000000.0
	player_combat.health = player_combat.max_health
	world.create_player(player_combat, 1, Vector3(0, 0, 7))
	world.spawn_wave([{"enemy_id": 23002, "position": [0, 0, 0]}], difficulty, 731)
	await physics_frame
	await physics_frame
	var boss: DungeonActor = world.actors.back()
	_check(boss.actor_id == 23002 and boss.combat.custom_properties.get("_enemy_spawn_entered", false), "Real world spawn enters the source lava dragon action")
	for actor in world.actors:
		actor.set_process(false)
		actor.set_physics_process(false)
	var combat := boss.combat
	var maximum = combat.max_health
	_check(combat.health == maximum and combat.shield == 0.0, "Lava dragon begins with source full HP and no shield")
	for frame in 900:
		if combat.statuses.has("42300205"): break
		_tick(world)
	_check(combat.statuses.has("42300205"), "Serialized source AI installs the half-HP observer")
	_check(world.phase_summons.is_empty() and world.shield_drains.is_empty(), "No shield timer runs before the half-HP gate")
	combat.receive({"damage": maximum * 1000.0, "attack_collision": false, "definition": {}}, combat.attack)
	var locked_health = combat.health
	_check(is_equal_approx(locked_health, maximum * 0.5), "Actual lethal receive damage stops at fifty percent HP")
	_check(combat.statuses.has("42300205") and not combat.statuses.has("42300206") and combat.shield == 0.0, "Lock activation leaves its trigger package queued until the next update")
	var phase_time = world.test_time
	_tick(world)
	_check(not combat.statuses.has("42300205"), "The next world update applies 42300206 and removes the observer")
	_check(combat.statuses.has("42300206"), "The authored trigger package exists on its first update")
	_check(world.phase_summons.size() == 1, "42300207 creates exactly one real 42300255 timer summon")
	if not world.phase_summons.is_empty():
		var activation: Dictionary = world.phase_summons[0]
		_check(is_equal_approx(float(activation.shield), float(int(maximum))), "42300203 grants one hundred percent max-HP shield before the first timer entity expires")
		_check(not bool(activation.lock_present), "The summon is created after the half-HP observer is cleared")
	for frame in 2700:
		_tick(world)
	var reduction = int(maximum * 34.0 / 1000.0)
	if difficulty == 2:
		_check(not is_equal_approx(float(reduction), maximum * 34.0 / 1000.0), "The source difficulty produces a fractional shield amount before truncation")
	_check(world.timer_entities.size() == 30, "The authored funnel emits exactly thirty invisible physical entities")
	_check(world.shield_drains.size() == 30, "Thirty entity disposals apply 42300204 to their owner")
	for index in world.timer_entities.size():
		var entity: Dictionary = world.timer_entities[index]
		_check(int(entity.index) == index and float(entity.damage) == 0.0 and int(entity.damage_id) == -1, "Timer entity %d preserves its zero-damage source definition and emission index" % index)
	for index in world.shield_drains.size():
		var drain: Dictionary = world.shield_drains[index]
		var expected_before = maxf(0.0, float(int(maximum)) - index * reduction)
		var expected_after = maxf(0.0, expected_before - reduction)
		_check(str(drain.owner) == combat.actor_key and is_equal_approx(float(drain.before), expected_before) and is_equal_approx(float(drain.after), expected_after), "Disposal %d deducts source integer-truncated shield from its owner" % index)
		if index > 0:
			_check(absf(float(drain.time) - float(world.shield_drains[index - 1].time) - 1.0) <= STEP + 0.000001, "Shield decay %d occurs one second after the previous entity" % index)
	_check(combat.health == locked_health and not boss.dead, "Shield decay does not consume the boss's remaining HP")
	_check(combat.shield == maxf(0.0, float(int(maximum)) - 30.0 * reduction), "Shield reaches the exact result of thirty truncated reductions")
	_check(player_combat.shield == 0 and not player_combat.statuses.has("42300204"), "Owner-only timer disposal never grants the shield-reduction buff to the player")
	_check(world.summon_units.all(func(unit): return str(unit.id) != "42300255"), "The forty-second timer summon disposes after its authored lifetime")
	_check(world.diagnostics.is_empty() and combat.diagnostics.is_empty() and combat.enemy_ai.diagnostics.is_empty(), "Real world phase has no unresolved diagnostics")
	var report = {"enemy": 23002, "difficulty": difficulty, "max_health": maximum, "locked_health": locked_health, "shield_reduction_per_entity": reduction, "final_shield": combat.shield, "phase_time": phase_time, "simulated_seconds_after_phase": world.test_time - phase_time, "phase_summons": world.phase_summons, "timer_entities": world.timer_entities, "shield_drains": world.shield_drains, "world_diagnostics": world.diagnostics, "combat_diagnostics": combat.diagnostics}
	world.queue_free()
	await process_frame
	return report

func _tick(world: ObservedWorld) -> void:
	world.test_time += STEP
	world._physics_process(STEP)
	world.presentation._process(STEP)

func _create_arena(world: DungeonWorld) -> void:
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(200, 1, 200)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	world.add_child(floor_body)
	floor_body.position.y = -0.5
	var region := NavigationRegion3D.new()
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-99, 0, -99), Vector3(-99, 0, 99), Vector3(99, 0, 99), Vector3(99, 0, -99)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_mesh = mesh
	world.add_child(region)
	NavigationServer3D.map_force_update(world.get_world_3d().navigation_map)

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append("Difficulty %d: %s" % [_case_difficulty, message])
