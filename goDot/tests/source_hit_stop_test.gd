extends SceneTree

const Combat = preload("res://scripts/domain/combat.gd")
const Profiles = preload("res://scripts/presentation/impact_profiles.gd")
const Feedback = preload("res://scripts/presentation/hit_feedback.gd")
var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _actor(world: DungeonWorld, key: String, player_owned := false) -> DungeonActor:
	var actor := DungeonActor.new()
	actor.is_player = player_owned
	actor.combat = Combat.new()
	if player_owned: actor.combat.configure(null, null, 3)
	else: actor.combat.configure_enemy(11001)
	actor.combat.actor_key = key
	actor.combat.defense = 0
	actor.combat.max_health = 100000
	actor.combat.health = actor.combat.max_health
	world.add_child(actor)
	actor.set_process(false)
	actor.set_physics_process(false)
	world.actors.append(actor)
	return actor

func _packet(source: DungeonActor, emission: int, weight := 0.4) -> Dictionary:
	var definition: Dictionary = source.combat._action("ActGroup_playerchara", "axe_satk_end").hits[0].duplicate(true)
	var raw: Dictionary = JSON.parse_string(definition.raw)
	raw.FeedbackList = [{"FeedbackType": "EHT_HitStopFrame", "StopFrameWeight": weight, "SelfAffectedRatio": 0.9}]
	definition.raw = JSON.stringify(raw)
	return {"definition": definition, "damage": 32.0, "uncritical_damage": 32.0, "critical_rate": 0.0, "critical_roll": 1.0, "action": "axe_satk_end", "slot": 4, "sequence": source.combat._cast_sequence, "emission": emission, "source_key": source.combat.actor_key}

func _register(world: DungeonWorld, source: DungeonActor, hit: Dictionary) -> void:
	world._register_source_hit_stop(hit, source, Feedback.normalize(hit.definition))

func _reset_stop(world: DungeonWorld) -> void:
	world._battle_scales.clear()
	world._source_stop_hits.clear()
	world._seen_impacts.clear()
	world.source_hit_stop_percent = 100
	world._refresh_battle_scale()

func _remaining(world: DungeonWorld) -> float:
	return float(world._battle_scales.get("UnitStopFrame", {}).get("remaining", -1))

func _buff(ids: Array, addition: float, type := "EBT_ModifyAttackDef") -> Dictionary:
	return {"type": type, "maxLayers": 99, "duration": -1, "raw_data": {"BuffSettingDataList": [{"AttackDefIdList": ids, "HitFeedBack_StopFrameAdd": addition}]}}

func _identity_cases() -> void:
	for sequence in [7, 7.25]:
		for emission in [9, 9.5, "world:009", "projectile:0/1"]:
			var hit := {"source_key": "player", "sequence": sequence, "emission": emission, "summon_id": "fixture"}
			var restored: Dictionary = JSON.parse_string(JSON.stringify(hit))
			check(Profiles.instance_id(restored) == Profiles.instance_id(hit), "JSON numeric conversion preserves AttackHit identity %s/%s" % [sequence, emission])
	check(Profiles.instance_id({"emission": "world:009"}) != Profiles.instance_id({"emission": "world:010"}), "Different string emission identities remain distinct")
	check(Profiles.instance_id({"emission": 9.25}) != Profiles.instance_id({"emission": 9.5}), "Fractional numeric emission identities are not truncated together")

func _domain_cases() -> void:
	var owner = Combat.new()
	var definition := {"raw": JSON.stringify({"Id": 77})}
	check(owner.source_stop_frame_modifier(definition) == 0, "No statuses give no source stop modifier")
	owner._buff_index = {"a": _buff([77], 0.2), "b": _buff(["77", 99], 0.3), "other_id": _buff([88], 4), "other_type": _buff([77], 100, "EBT_NumericalBuff"), "zero_id": _buff([0], 7)}
	for id in owner._buff_index:
		check(owner.add_buff(id, 3, 0), "Modifier fixture applies through normal buff API %s" % id)
	check(is_equal_approx(owner.source_stop_frame_modifier(definition), 0.5), "Only matching modify-attack buffs add together without multiplying three layers")
	check(is_equal_approx(owner.source_stop_frame_modifier({"raw": {"Id": 77}}), 0.5), "Dictionary raw attack IDs use the same buff filter")
	check(is_equal_approx(owner.source_stop_frame_modifier({"Id": 77}), 0.5), "Direct attack definitions use the same buff filter")
	check(is_equal_approx(owner.source_stop_frame_modifier({"damageId": 77}), 0.5), "Normalized attack ID fallback remains available")
	check(owner.source_stop_frame_modifier({"raw": {"Id": 0}, "damageId": 77}) == 0, "Explicit zero source attack ID cannot match even with a normalized nonzero fallback")
	check(owner.source_stop_frame_modifier({"Id": 0}) == 0 and owner.source_stop_frame_modifier({}) == 0, "Zero and missing attack IDs never contribute a modifier")
	check(owner.source_stop_frame_modifier({"Id": 88}) == 4, "A different source ID selects only its own modifier")
	check(is_equal_approx(owner.source_stop_frame_modifier({"Id": 99}), 0.3), "Any matching ID in an authored ID list is accepted")
	for invalid in ["[]", "null", [], 17]:
		check(owner.source_stop_frame_modifier({"raw": invalid}) == 0, "Non-dictionary source definitions add no modifier %s" % str(invalid))
	owner.remove_buff("a")
	check(is_equal_approx(owner.source_stop_frame_modifier(definition), 0.3), "Removing a matching buff removes its contribution immediately")
	owner.remove_buff("b")
	check(owner.source_stop_frame_modifier(definition) == 0, "Unrelated remaining statuses cannot contribute a stop modifier")
	owner.statuses.clear()
	check(owner.source_stop_frame_modifier(definition) == 0, "Removing every status returns to the empty-status path")

func _percent_cases(world: DungeonWorld, source: DungeonActor) -> void:
	check(world.source_hit_stop_percent == 100, "Default source hit-stop setting is 100 percent")
	for percent in [100, 50, 0, -1, 25, 101]:
		_reset_stop(world)
		world.source_hit_stop_percent = percent
		var hit := _packet(source, 100 + percent)
		_register(world, source, hit)
		if percent == 0:
			check(world._battle_scales.is_empty() and world._source_stop_hits.is_empty() and world.simulation_scale == 1, "Zero percent registers neither a stop nor a dedup entry")
		else:
			var effective := 50 if percent == 50 else 100
			check(is_equal_approx(_remaining(world), 0.4 * 0.12 * effective / 100.0), "Percent %d uses the native duration formula or invalid-value default" % percent)
			check(world._battle_scales.size() == 1 and world.simulation_scale == 0.12 and world.presentation.simulation_scale == 0.12, "Percent %d retains one global 0.12 stop scale" % percent)
	for weight in [-1.0, 0.0]:
		_reset_stop(world)
		_register(world, source, _packet(source, 210, weight))
		check(world._battle_scales.is_empty() and world._source_stop_hits.is_empty(), "Nonpositive unmodified weight does not register or deduplicate %s" % weight)
	_reset_stop(world)
	world._register_source_hit_stop(_packet(source, 211), source, {})
	check(world._battle_scales.is_empty() and world._source_stop_hits.is_empty(), "Missing source stop feedback does nothing")
	for ratio in [0.0, 0.5, 1.0]:
		_reset_stop(world)
		var hit := _packet(source, 220)
		var feedback := Feedback.normalize(hit.definition)
		feedback.hit_stops[0].self_affected_ratio = ratio
		world._register_source_hit_stop(hit, source, feedback)
		check(is_equal_approx(_remaining(world), 0.048), "Serialized SelfAffectedRatio does not alter the global native stop %s" % ratio)
	_reset_stop(world)
	var modified := _packet(source, 230, -0.4)
	var id := int(JSON.parse_string(modified.definition.raw).Id)
	source.combat._buff_index = source.combat._buff_index.duplicate()
	source.combat._buff_index["stop_fixture"] = _buff([id], 0.5)
	check(source.combat.add_buff("stop_fixture", 3, 0), "World modifier fixture applies with three layers")
	_register(world, source, modified)
	check(is_equal_approx(_remaining(world), 0.012), "Positive buff-adjusted sum can activate a negative source weight without multiplying layers")
	for weight in [-0.5, -0.6]:
		_reset_stop(world)
		_register(world, source, _packet(source, 231, weight))
		check(world._battle_scales.is_empty() and world._source_stop_hits.is_empty(), "Zero or negative buff-adjusted sum remains unregistered %s" % weight)
	_reset_stop(world)
	_register(world, source, _packet(source, 232))
	check(is_equal_approx(_remaining(world), 0.108), "Positive source weight combines once with its matching modifier")
	source.combat.remove_buff("stop_fixture")
	_reset_stop(world)
	_register(world, source, _packet(source, 233))
	check(is_equal_approx(_remaining(world), 0.048), "Removing the source modifier restores the unmodified duration")
	source.combat._buff_index.erase("stop_fixture")

func _contact_cases(world: DungeonWorld, source: DungeonActor, first: DungeonActor, second: DungeonActor) -> void:
	_reset_stop(world)
	world._physics_serial = 100
	var hit := _packet(source, 300)
	var hp: float = first.combat.health
	world._apply_hit(source, first, hit)
	check(first.combat.health < hp and world._source_stop_hits.size() == 1, "A real accepted source contact settles damage and registers its AttackHit once")
	check(is_equal_approx(_remaining(world), 0.048), "Real world impact uses the native source weight duration")
	check(source.combat.impact_pause == 0 and first.combat.impact_pause == 0, "Source contact uses the global stop without adding local FEEL pauses")
	world._advance_battle_scale(0.01)
	var remaining := _remaining(world)
	hp = second.combat.health
	world._apply_hit(source, second, hit.duplicate(true))
	check(second.combat.health < hp and _remaining(world) == remaining and world._source_stop_hits.size() == 1, "The same AttackHit damages a second target without restarting its global stop")
	var repeated := hit.duplicate(true)
	repeated.contact = 1
	hp = first.combat.health
	world._apply_hit(source, first, repeated)
	check(first.combat.health < hp and _remaining(world) == remaining and world._source_stop_hits.size() == 1, "A repeated contact of the same AttackHit settles without registering again")
	_register(world, source, hit)
	check(_remaining(world) == remaining, "Direct repeat registration also preserves remaining time")
	world._apply_hit(source, first, _packet(source, 301, 0.1))
	check(is_equal_approx(_remaining(world), 0.012) and world._battle_scales.size() == 1, "A distinct shorter AttackHit replaces the global UnitStopFrame register")
	world._apply_hit(source, first, _packet(source, 302, 0.8))
	check(is_equal_approx(_remaining(world), 0.096) and world._battle_scales.size() == 1, "A distinct longer AttackHit also replaces that same global register")
	world._physics_serial = 101
	world._prune_source_stop_hits()
	check(world._source_stop_hits.size() == 3, "One-tick-old instant AttackHit identities remain deduplicated")
	world._physics_serial = 102
	world._prune_source_stop_hits()
	check(world._source_stop_hits.is_empty(), "Expired instant AttackHit identities are pruned without retaining old contacts")

func _scale_cases(world: DungeonWorld, source: DungeonActor, other: DungeonActor) -> void:
	_reset_stop(world)
	world._register_battle_scale(source, {"scale": 0.4, "duration": 1.0})
	_register(world, source, _packet(source, 400))
	check(world._battle_scales.size() == 2 and world.simulation_scale == 0.12, "Source hit stop stacks with an actor's action modifier by minimum scale")
	world._register_battle_scale(other, {"scale": 0.05, "duration": 0.02})
	check(world._battle_scales.size() == 3 and world.simulation_scale == 0.05, "An action modifier below 0.12 takes precedence over source hit stop")
	world._advance_battle_scale(0.02)
	check(world._battle_scales.has(other.get_instance_id()) and world._battle_scales[other.get_instance_id()].remaining == 0 and world.simulation_scale == 0.05, "An action register at exactly zero remains active")
	world._advance_battle_scale(0.000001)
	check(not world._battle_scales.has(other.get_instance_id()) and world.simulation_scale == 0.12, "Action expiry reveals the still-active source stop")
	world._advance_battle_scale(_remaining(world))
	check(world._battle_scales.has("UnitStopFrame") and _remaining(world) == 0 and world.simulation_scale == 0.12, "Source stop remains registered when its battle-clock duration is exactly zero")
	world._advance_battle_scale(0.000001)
	check(not world._battle_scales.has("UnitStopFrame") and world.simulation_scale == 0.4, "Negative remaining duration expires source stop and reveals the action modifier")
	world._register_battle_scale(source, {"scale": 0.7, "duration": 2.0})
	check(world._battle_scales.size() == 1 and world.simulation_scale == 0.7, "A later modifier from the same actor replaces only that actor's prior register")
	world._consume(source, {"type": "battle_time_scale", "phase": "Exit"})
	check(world._battle_scales.is_empty() and world.simulation_scale == 1, "Action-window exit restores normal scale after source stop expired")
	_reset_stop(world)
	var actors := world.actors.duplicate()
	world.actors.clear()
	world.actors.append(source)
	source.combat.clear_impact_state()
	source.combat.drain_events()
	_register(world, source, _packet(source, 410))
	var clock: float = source.combat._clock
	world._physics_process(0.1)
	check(is_equal_approx(_remaining(world), 0.036), "Actual world physics advances stop duration by 0.1 times the current battle scale")
	check(is_equal_approx(source.combat._clock - clock, 0.012), "Actual world physics advances combat with the same scaled delta")
	check(Engine.time_scale == 1, "Source battle scaling leaves the engine clock unchanged")
	world.actors.assign(actors)

func _projectile_cases(world: DungeonWorld, source: DungeonActor, first: DungeonActor, second: DungeonActor) -> void:
	_reset_stop(world)
	world._physics_serial = 500
	var packet := _packet(source, 500)
	var raw: Dictionary = JSON.parse_string(packet.definition.raw)
	raw.EntityType = "EET_Physical"
	raw.EntityProperty = {"ColliderType": "Sphere", "ModelBoxColliderSize": {"x": 4, "y": 4, "z": 4}, "MaxPassNum": 99, "MaxCollisionCountPerTarget": 20, "IsCheckEnvCollider": false, "IsCheckEnvUnitCollider": false}
	raw.MotionAnimatorType = "EMAT_Fixed"
	raw.MotionAnimatorProperty = {"Speed": 0, "MaxLifetime": 10}
	raw.EffectActiveIntervalToEachUnit = 0.01
	raw.EffectActiveTotalCountToEachUnit = 20
	packet.definition.raw = JSON.stringify(raw)
	var state := DungeonProjectile.new()
	state.configure(packet, Vector3(0, 0.75, -1), Vector3.FORWARD, Vector3.ZERO)
	state.source_key = str(source.combat.actor_key)
	state.source_player = true
	world._add_projectile_visual(state, source)
	check(state.hit.source_key == source.combat.actor_key, "Runtime projectile hit carries its stable source identity before contacts")
	var first_hp: float = first.combat.health
	var second_hp: float = second.combat.health
	world._tick_projectiles(0.02)
	var key := Profiles.instance_id(state.hit)
	check(first.combat.health < first_hp and second.combat.health < second_hp and state.hits.size() == 2, "Actual projectile collision settles the same AttackHit against multiple targets")
	check(world._source_stop_hits.has(key) and world._source_stop_hits.size() == 1 and is_equal_approx(_remaining(world), 0.048), "A multi-target projectile registers one source stop identity")
	check(world._source_stop_projectiles.get(key, 0) == 1, "Source projectile creation tracks one live reference to its AttackHit")
	world._physics_serial += 3
	world._prune_source_stop_hits()
	first_hp = first.combat.health
	world._tick_projectiles(0.02)
	check(first.combat.health < first_hp and world._source_stop_hits.has(key) and is_equal_approx(_remaining(world), 0.048), "A live projectile keeps its dedup entry and cannot restart source stop across physics ticks")
	world._advance_battle_scale(0.01)
	var saved_remaining := _remaining(world)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(world.transient_snapshot()))
	check(saved.source_hit_stop.hits == [key] and is_equal_approx(saved.source_hit_stop.register.remaining, saved_remaining), "JSON transient snapshot preserves the live AttackHit identity and remaining source stop")
	for projectile in world.projectiles: world._recycle_projectile(projectile)
	world.projectiles.clear()
	world._physics_serial = 900
	world._source_stop_hits["stale"] = -1
	world._battle_scales["UnitStopFrame"] = {"scale": 0.12, "remaining": 999}
	world.restore_transients(saved)
	check(world.projectiles.size() == 1 and world._source_stop_hits.keys() == [key] and is_equal_approx(_remaining(world), saved_remaining), "Restoration replaces stale stop state and reconstructs its live projectile")
	check(world.simulation_scale == 0.12 and Profiles.instance_id(world.projectiles[0].state.hit) == key, "Restored battle scale and projectile identity match the snapshot (before %s, after %s)" % [key, Profiles.instance_id(world.projectiles[0].state.hit)])
	check(world._source_stop_projectiles.get(key, 0) == 1, "Restoration reconstructs the live projectile identity reference count")
	var twin := DungeonProjectile.new()
	twin.restore(world.projectiles[0].state.snapshot())
	world._add_projectile_visual(twin, source)
	check(world._source_stop_projectiles.get(key, 0) == 2, "Two live projectiles sharing an AttackHit retain two references")
	var recycled_twin: Dictionary = world.projectiles.pop_back()
	world._recycle_projectile(recycled_twin)
	world._physics_serial += 3
	world._prune_source_stop_hits()
	check(world._source_stop_projectiles.get(key, 0) == 1 and world._source_stop_hits.has(key), "Recycling one shared-identity projectile preserves dedup for the remaining live projectile")
	first_hp = first.combat.health
	world._tick_projectiles(0.02)
	check(first.combat.health < first_hp and is_equal_approx(_remaining(world), saved_remaining), "A restored projectile can repeat contact without restarting its saved source stop")
	world._physics_serial += 10
	world._prune_source_stop_hits()
	check(world._source_stop_hits.has(key), "Live projectile identity survives pruning after many physics ticks")
	world._advance_battle_scale(saved_remaining + 0.000001)
	world._tick_projectiles(0.02)
	check(not world._battle_scales.has("UnitStopFrame") and world._source_stop_hits.has(key), "The same live projectile cannot reapply hit stop after its original duration expires")
	for projectile in world.projectiles: world._recycle_projectile(projectile)
	world.projectiles.clear()
	world._prune_source_stop_hits()
	check(world._source_stop_hits.is_empty() and world._source_stop_projectiles.is_empty(), "Finished projectile identity is released after its last live reference is removed")
	_register(world, source, _packet(source, 510))
	world._battle_scales.UnitStopFrame.remaining = 0.0
	var exact: Dictionary = JSON.parse_string(JSON.stringify(world.transient_snapshot()))
	world.restore_transients(exact)
	check(world._battle_scales.has("UnitStopFrame") and _remaining(world) == 0 and world.simulation_scale == 0.12, "Zero-remaining source stop survives JSON restoration until a later advance")
	world.restore_transients({"projectiles": [], "summons": []})
	check(world._source_stop_hits.is_empty() and not world._battle_scales.has("UnitStopFrame") and world.simulation_scale == 1, "Loading an old snapshot without source-stop fields clears prior transient stop state")
	_register(world, source, _packet(source, 511))
	world.restore_transients({})
	check(world._source_stop_hits.is_empty() and world._battle_scales.is_empty() and world.simulation_scale == 1, "An empty transient snapshot also clears prior source stop and dedup state")

func _normal_case(world: DungeonWorld, source: DungeonActor, target: DungeonActor) -> void:
	_reset_stop(world)
	source.combat.clear_impact_state()
	target.clear_impact_state()
	var hit := {"definition": source.combat._action("ActGroup_playerchara", "sword_atk1").hits[0], "damage": 32.0, "uncritical_damage": 32.0, "critical_rate": 0.0, "critical_roll": 1.0, "action": "sword_atk1", "slot": 0, "sequence": source.combat._cast_sequence, "emission": 600, "source_key": source.combat.actor_key}
	world._apply_hit(source, target, hit)
	check(not Profiles.resolve(hit, source.combat).get("source_only", false), "An ordinary source attack retains its normal feedback profile")
	check(target.combat.impact_pause > 0 and source.combat.impact_pause > 0, "An ordinary attack retains existing local target and attacker pause behavior")
	check(world._battle_scales.is_empty() and world._source_stop_hits.is_empty() and world.simulation_scale == 1, "Normal feedback creates no source UnitStopFrame register or dedup entry")
	var state := DungeonProjectile.new()
	state.configure(hit, source.position, source.facing, target.position)
	state.source_key = str(source.combat.actor_key)
	world._add_projectile_visual(state, source)
	check(world._source_stop_projectiles.is_empty() and not state.hit.has("_source_stop_identity"), "An ordinary projectile adds no source-stop lifecycle reference")
	world._recycle_projectile(world.projectiles.pop_back())

func _run() -> void:
	for action in ["move_left", "move_right", "move_up", "move_down"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	_identity_cases()
	_domain_cases()
	var world := DungeonWorld.new()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.presentation.set_process(false)
	world.set_attack_mode("off")
	var source := _actor(world, "player", true)
	var first := _actor(world, "target_a")
	var second := _actor(world, "target_b")
	world.player = source
	source.position = Vector3(5, 0, 0)
	first.position = Vector3(0, 0, -1)
	second.position = Vector3(0, 0, -2)
	_percent_cases(world, source)
	_contact_cases(world, source, first, second)
	_scale_cases(world, source, first)
	_projectile_cases(world, source, first, second)
	_normal_case(world, source, first)
	world.free()
	var result := {"checks": checks, "failures": failures, "native_evidence": "reports/combat-timing-native-static.json", "scope": "Real world/domain source hit-stop formula, modifier filtering, attack identity, scaled clock, projectile lifetime, JSON restoration and unchanged normal feedback."}
	FileAccess.open("res://reports/source-hit-stop-tests.json", FileAccess.WRITE).store_string(JSON.stringify(result, "\t") + "\n")
	print("SOURCE_HIT_STOP ", JSON.stringify(result))
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
