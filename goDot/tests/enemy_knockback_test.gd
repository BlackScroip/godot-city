extends SceneTree

const Combat = preload("res://scripts/domain/combat.gd")
const Reaction = preload("res://scripts/domain/enemy_hit_reaction.gd")
const FEEL = preload("res://assets/feel_settings.tres")
const BASE_DURATION := 0.15849624574184418
var checks := 0
var failures: Array[String] = []
var motion_rows: Array[Dictionary] = []
var physics_rows: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _enemy(action := "idle", id := 11001) -> DungeonCombat:
	var target := Combat.new()
	target.configure_enemy(id)
	target.max_health = 10000000
	target.health = target.max_health
	target.enemy_ai_enabled = true
	target.custom_properties["_enemy_spawn_entered"] = true
	target._start(target._action(str(target.enemy.group), action), 0)
	target.tick(0)
	target.drain_events()
	return target

func _hit(tenacity := 100.0, power := 50.0, upper := 0.0, extra: Dictionary = {}) -> Dictionary:
	var feedback := {
		"FeedbackType": "EHT_HitAction", "AccTenacity": tenacity,
		"PushPower": power, "UpperPower": upper,
		"PushMode": "AttackerForward",
		"AttackDirIsFromAttackerOrHitPoint": true,
		"AttackDirIsAttackerForwardOrHitPointDir": true,
	}
	feedback.merge(extra, true)
	return {
		"damage": 1.0, "definition": {"raw": JSON.stringify({"FeedbackList": [feedback]})},
		"hit_geometry": {
			"attacker_position": [-2.0, 0.0, 0.0], "attacker_forward": [1.0, 0.0, 0.0],
			"attackee_position": [0.0, 0.0, 0.0], "attackee_forward": [0.0, 0.0, -1.0],
			"entity_position": [-2.0, 0.0, 0.0], "entity_forward": [1.0, 0.0, 0.0],
		},
	}

func _motion(target: RefCounted) -> Dictionary:
	return target.custom_properties.get("_enemy_hit_motion", {})

func _force(target: RefCounted) -> Vector3:
	var value: Array = _motion(target).get("force", [0.0, 0.0, 0.0])
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

func _remaining(target: RefCounted) -> float:
	return float(_motion(target).get("remaining", 0.0))

func _run() -> void:
	_admission_and_interrupts()
	_directions()
	_force_and_weight()
	_timing_and_overwrite()
	_action_clock()
	_restore_and_clear()
	await _world_motion()
	var report := {
		"passed": failures.is_empty(), "checks": checks, "failures": failures,
		"motion": motion_rows, "physics": physics_rows,
		"scope": "APK-derived hit admission, force/weight timers, snapshot restore and real Godot collision movement; no APK runtime execution.",
	}
	FileAccess.open("res://reports/enemy-knockback-tests.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("ENEMY KNOCKBACK ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func _admission_and_interrupts() -> void:
	for action in ["idle", "run"]:
		var target := _enemy(action)
		target.receive(_hit())
		check(Reaction.is_weak(target), "%s accepts ordinary AccTenacity100" % action)
		check(_force(target).is_equal_approx(Vector3.RIGHT * 50), "%s records source horizontal force" % action)
		check(absf(_remaining(target) - BASE_DURATION) < 0.000001, "%s starts the source knockback timer" % action)
		target._tick_enemy_interrupts()
		check(target.current_action == "behit", "%s follows its authored low-hit interrupt" % action)
		check(absf(_remaining(target) - BASE_DURATION) < 0.000001, "Entering hit action preserves %s movement" % action)
		check(Reaction.advance_motion(target, 1.0 / 60).x > 0.1, "%s physically moves after entering hit action" % action)
	var attack := _enemy("attack")
	var sequence := attack._cast_sequence
	attack.receive(_hit())
	attack._tick_enemy_interrupts()
	check(not Reaction.is_weak(attack) and attack.current_action == "attack" and attack._cast_sequence == sequence, "Attack StableValue50 preserves a cast against AccTenacity100")
	check(Reaction.advance_motion(attack, 1.0 / 60).is_zero_approx(), "Unbroken attack tenacity gives no knockback")
	attack.tick(0.02)
	attack.receive(_hit(150))
	attack._tick_enemy_interrupts()
	check(attack.current_action == "behit" and Reaction.advance_motion(attack, 1.0 / 60).x > 0, "AccTenacity150 uses attack's source interrupt and movement")
	var boss := _enemy("attack", 13001)
	boss.receive(_hit(300, 300))
	boss._tick_enemy_interrupts()
	check(not Reaction.is_weak(boss) and Reaction.advance_motion(boss, 1.0 / 60).is_zero_approx(), "Lord's source tenacity prevents ordinary knockback")
	for protection in ["shield", "armor", "invincible", "dodge", "block", "collision", "super_armor"]:
		var protected := _enemy()
		match protection:
			"shield": protected.shield = 100
			"armor": protected.armor = 100
			"invincible": protected.invincible = 1
			"dodge": protected._dodge_time = 1
			"block": protected._block_time = 1
			"collision": protected.custom_properties._action_can_hit = false
			"super_armor": protected.custom_properties.SuperArmor = true
		protected.receive(_hit(1000, 1000))
		check(Reaction.advance_motion(protected, 1.0 / 60).is_zero_approx(), "%s prevents source knockback" % protection)
	var no_feedback := _enemy()
	no_feedback.receive({"damage": 1.0, "definition": {}})
	check(Reaction.advance_motion(no_feedback, 1.0 / 60).is_zero_approx(), "Damage without HitAction does not create movement")

func _directions() -> void:
	var geometry := {
		"attacker_position": [-3.0, 2.0, 0.0], "attacker_forward": [0.0, 1.0, 4.0],
		"attackee_position": [0.0, 7.0, 0.0], "attackee_forward": [0.0, 0.0, -1.0],
		"entity_position": [0.0, 3.0, 2.0], "entity_forward": [-4.0, 5.0, 0.0],
	}
	var modes := ["AttackerForward", "AttackerToAttackeeDir", "AttackEntityForward", "AttackEntityToAttackeeDir"]
	var expected := [Vector3.BACK, Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD]
	for index in modes.size():
		for mode in [modes[index], index]:
			var target := _enemy()
			var hit := _hit(100, 50, 0, {"PushMode": mode})
			hit.hit_geometry = geometry
			target.receive(hit)
			check(_force(target).is_equal_approx(expected[index] * 50), "PushMode%s uses its authored geometric source" % mode)
			check(Reaction.take_facing(target).is_equal_approx(-expected[index]), "PushMode%s turns the target against push direction" % mode)
			check(Reaction.take_facing(target).is_zero_approx(), "Pending hit facing is consumed once")
	var empty_entity := geometry.duplicate(true)
	empty_entity.entity_forward = [0.0, 0.0, 0.0]
	empty_entity.entity_position = [0.0, 0.0, 0.0]
	for mode in ["AttackEntityForward", "AttackEntityToAttackeeDir"]:
		check(Reaction.push_direction({"PushMode": mode}, empty_entity).is_equal_approx(Vector3.RIGHT), "Missing %s geometry falls back to attacker-to-target" % mode)
	var vertical_entity := geometry.duplicate(true)
	vertical_entity.entity_forward = [0.0, 2.0, 0.0]
	check(Reaction.push_direction({"PushMode": "AttackEntityForward"}, vertical_entity).is_zero_approx(), "Entity fallback checks xyz before dropping vertical direction")
	var overlap := geometry.duplicate(true)
	overlap.attacker_position = overlap.attackee_position
	check(Reaction.push_direction({"PushMode": "AttackerToAttackeeDir"}, overlap).is_zero_approx(), "Coincident actors do not invent a forward push")

func _force_and_weight() -> void:
	for power in [0.0, 9.0, 10.0, -10.0, 50.0, -50.0]:
		var target := _enemy()
		target.receive(_hit(100, power))
		var displacement := Reaction.advance_motion(target, 1.0 / 60)
		check(displacement.y == 0.0 and is_zero_approx(displacement.z), "Push%s has no fabricated vertical or sideways impulse" % power)
		check(displacement.is_zero_approx() if absf(power) < 10 else signf(displacement.x) == signf(power), "Push%s respects the 0.1 force/weight threshold and sign" % power)
	var resistant := _enemy()
	resistant.set_external_attributes({"PushForceResist": 45})
	resistant.receive(_hit())
	check(Reaction.is_weak(resistant) and Reaction.advance_motion(resistant, 1.0 / 60).is_zero_approx(), "Resistance can suppress movement even after tenacity breaks")
	var source := Combat.new()
	source.configure()
	source.custom_properties.Bonus = 500
	source.set_external_attributes({"PushForceAddRate": 500})
	var modified := _enemy()
	modified.set_external_attributes({"Weight": 100, "PushForceResist": 9})
	var modified_hit := _hit(100, 31, 0, {"PushPowerModifyPropertyName": "Bonus"})
	modified_hit.source = source
	modified.receive(modified_hit)
	check(_force(modified).is_equal_approx(Vector3.RIGHT * 60), "Property truncation then source rate then target resistance yields force60")
	check(absf(float(_motion(modified).get("duration", 0)) - 0.13785116374492645) < 0.000001, "External Weight100 changes the source duration to weight200")
	var changing_weight := _enemy()
	changing_weight.receive(_hit())
	var initial_timer := _remaining(changing_weight)
	changing_weight._start(changing_weight._action(str(changing_weight.enemy.group), "behit_high"), 0)
	check(float(Reaction.action_rules_for(changing_weight).WeightAddValue) == 99999.0, "High-hit action supplies the actual APK WeightAddValue99999")
	check(_remaining(changing_weight) == initial_timer, "Changing authored action weight preserves active timer")
	var weighted_step := Reaction.advance_motion(changing_weight, 1.0 / 60)
	check(weighted_step.x > 0 and weighted_step.x < 0.0002, "Each movement tick reads current authored action weight")
	var high := _enemy()
	high.receive(_hit())
	Reaction.advance_motion(high, 0.02)
	high.receive(_hit(0, 50, 100))
	check(high.custom_properties.get("_enemy_hit_action", "") == "hit_2", "UpperPower>=weight requests the authored high reaction")
	check(_remaining(high) <= 0 and Reaction.advance_motion(high, 1.0 / 60).is_zero_approx(), "High reaction clears planar timer without adding a vertical impulse")

func _timing_and_overwrite() -> void:
	# Reference totals retain native explicit Euler sampling rather than a fixed-distance curve.
	var reference := {30: [4, 0.5758581757545471], 60: [7, 0.5038759037852287], 120: [14, 0.4845250528305769]}
	for fps in [30, 60, 120]:
		var target := _enemy()
		target.receive(_hit())
		var distance := 0.0
		var active_steps := 0
		var first_step := 0.0
		for frame in 40:
			var displacement := Reaction.advance_motion(target, 1.0 / fps)
			if frame == 0: first_step = displacement.x
			if displacement.length_squared() > 0: active_steps += 1
			distance += displacement.x
		check(active_steps == reference[fps][0], "APK remaining<=0.05 cutoff takes %s steps at %sHz" % [reference[fps][0], fps])
		check(absf(distance - float(reference[fps][1])) < 0.000003, "APK Euler total is retained at %sHz: %s" % [fps, distance])
		check(absf(first_step - 1.0 / BASE_DURATION / fps) < 0.000001, "First step samples full remaining timer at %sHz" % fps)
		motion_rows.append({"fps": fps, "steps": active_steps, "distance": distance, "first_step": first_step})
	var target := _enemy()
	target.receive(_hit())
	Reaction.advance_motion(target, 0.04)
	var previous_remaining := _remaining(target)
	var previous_duration := float(_motion(target).get("duration", 0))
	target.receive(_hit(0, -5))
	check(_force(target).is_equal_approx(Vector3.LEFT * 5), "A new weak hit overwrites force even below the start threshold")
	check(_remaining(target) == previous_remaining and float(_motion(target).get("duration", 0)) == previous_duration, "Below-threshold overwrite preserves an existing timer")
	check(Reaction.advance_motion(target, 0.01).x < 0, "Below-threshold overwrite reverses existing movement instead of preserving old force")
	target.receive(_hit(0, 100))
	check(absf(_remaining(target) - 0.2) < 0.000001 and _force(target).x == 100, "A qualifying new hit restarts the timer using its own force")
	var before_tick := _remaining(target)
	target.tick(0.02)
	check(_remaining(target) == before_tick, "Combat tick cannot consume actor motion a second time")

func _action_clock() -> void:
	var target := _enemy()
	target.receive(_hit())
	for fps in [30, 60, 120]:
		var expected := {30: 0.033, 60: 0.016, 120: 0.008}
		check(absf(Reaction.motion_delta(target, 1.0 / fps) - float(expected[fps])) < 0.000001, "Source action truncates a%sHz step to whole milliseconds" % fps)
	target.custom_properties._feel_action_speed = 2.0
	check(absf(Reaction.motion_delta(target, 1.0 / 60) - 0.0165) < 0.000001, "Local action scale is removed after millisecond truncation")
	# Exercise the packaged legacy wolf timeline without changing its enemy catalog.
	target.enemy = target.enemy.duplicate()
	target.enemy.group = "ActGroup_wolf"
	target._start(target._action(str(target.enemy.group), "attack2"), 0)
	target.tick(0.0)
	target.custom_properties._feel_action_speed = 2.0
	check(absf(Reaction.motion_delta(target, 1.0 / 60) - 0.016) < 0.000001, "Entered authored speed event contributes to local source time")
	var ending := _enemy("behit")
	ending.receive(_hit())
	ending.tick(0.499)
	check(absf(Reaction.motion_delta(ending, 1.0 / 60) - 0.001) < 0.000001, "Source displacement clips its clock to the current action end")
	var integer_clock := _enemy("behit")
	integer_clock.receive(_hit())
	for frame in 31: integer_clock.tick(1.0 / 60)
	check(int(integer_clock.custom_properties._enemy_hit_clock.elapsed_ms) == 496, "The knockback clock accumulates whole milliseconds independently of floating action time")
	integer_clock.tick(1.0 / 60)
	check(absf(integer_clock.enemy_hit_motion_step - 0.004) < 0.000001, "Final source action step clips 496ms to 500ms")
	integer_clock.tick(1.0 / 60)
	check(integer_clock.enemy_hit_motion_step == 0.0, "A completed source action does not advance its remaining force until action changes")
	var changing := _enemy()
	changing.receive(_hit())
	changing.enemy = changing.enemy.duplicate()
	changing.enemy.group = "ActGroup_wolf"
	changing._start(changing._action(str(changing.enemy.group), "attack2"), 0)
	changing.tick(1.0 / 60)
	check(absf(changing.enemy_hit_motion_step - 0.032) < 0.000001, "A time-zero half-speed event enters after the first 16ms quantization")
	for frame in 23: changing.tick(1.0 / 60)
	check(int(changing.custom_properties._enemy_hit_clock.elapsed_ms) == 200 and absf(changing.enemy_hit_motion_step - 0.016) < 0.000001, "Speed event stays active when runtime equals its 200ms duration")
	var restored_clock := _enemy()
	restored_clock.enemy = restored_clock.enemy.duplicate()
	restored_clock.enemy.group = "ActGroup_wolf"
	check(restored_clock.restore(JSON.parse_string(JSON.stringify(changing.snapshot()))), "Active speed-event runtime survives JSON restoration")
	check(restored_clock.custom_properties._enemy_hit_clock == changing.custom_properties._enemy_hit_clock, "JSON restoration canonicalizes the integer clock and active event timers")
	var before_preview: Dictionary = restored_clock.custom_properties._enemy_hit_clock.duplicate(true)
	var preview_step := Reaction.motion_delta(restored_clock, 1.0 / 60)
	check(absf(preview_step - 0.008) < 0.000001 and restored_clock.custom_properties._enemy_hit_clock == before_preview, "Preview computes the pending speed-event exit without advancing the restored clock")
	for actor in [changing, restored_clock]: actor.tick(1.0 / 60)
	check(absf(changing.enemy_hit_motion_step - 0.008) < 0.000001, "Speed event exits only after 208ms and movement divides by the new rate")
	check(restored_clock.enemy_hit_motion_step == changing.enemy_hit_motion_step and restored_clock.custom_properties._enemy_hit_clock == changing.custom_properties._enemy_hit_clock, "Restored speed-event exit matches the original clock")
	changing._start(changing._action(str(changing.enemy.group), "idle"), 0)
	check(not changing.custom_properties.has("_enemy_hit_clock") and not _motion(changing).is_empty(), "Action changes reset the native clock while preserving force")
	for field in ["frozen", "impact_pause"]:
		var held := _enemy()
		held.receive(_hit())
		held.set(field, 0.1)
		held.tick(1.0 / 60)
		check(held.enemy_hit_motion_step == 0.0, "%s pauses the source movement clock" % field)
		held.set(field, 0.01)
		held.tick(1.0 / 60)
		check(absf(held.enemy_hit_motion_step - 0.006) < 0.000001, "%s release uses only the unpaused whole milliseconds" % field)

func _restore_and_clear() -> void:
	var original := _enemy()
	original.receive(_hit())
	Reaction.advance_motion(original, 0.025)
	var restored := _enemy()
	check(restored.restore(JSON.parse_string(JSON.stringify(original.snapshot()))), "Active knockback survives a JSON save round trip")
	check(_motion(restored) == _motion(original), "JSON restoration preserves force, duration, remaining and pending facing")
	for frame in 12:
		check(Reaction.advance_motion(original, 1.0 / 60).is_equal_approx(Reaction.advance_motion(restored, 1.0 / 60)), "Restored source displacement matches frame%s" % frame)
	var cleared := _enemy()
	cleared.receive(_hit())
	Reaction.clear_motion(cleared)
	check(Reaction.advance_motion(cleared, 1.0 / 60).is_zero_approx() and Reaction.take_facing(cleared).is_zero_approx(), "Explicit cleanup clears both source movement and pending facing")
	var settings: Resource = FEEL
	var enabled: bool = settings.impact_enabled
	settings.impact_enabled = false
	var disabled_feedback := _enemy()
	disabled_feedback.receive(_hit())
	check(Reaction.advance_motion(disabled_feedback, 1.0 / 60).x > 0.1, "Source knockback remains gameplay when impact presentation is disabled")
	settings.impact_enabled = enabled

func _body(box_size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = box_size
	collision.shape = box
	body.add_child(collision)
	body.position = at
	return body

func _world_geometry(world: DungeonWorld, player: DungeonActor) -> void:
	var target := DungeonActor.new()
	target.combat = _enemy()
	target.combat.actor_key = "geometry_target"
	target.position = Vector3(1, 0, 1)
	world.add_child(target)
	world.actors.append(target)
	var contacts: Array[Dictionary] = []
	target.combat.impact_confirmed.connect(func(hit: Dictionary): contacts.append(hit))
	var frame_hit := _hit(100, 50, 0, {"PushMode": "AttackEntityForward"})
	var raw: Dictionary = JSON.parse_string(frame_hit.definition.raw)
	raw.EntityType = "EET_FrameCube"
	raw.EntityProperty = {"CheckTime": 1.0, "CheckTimeCauseContinuousTrigger": true}
	frame_hit.definition.merge({"raw": JSON.stringify(raw), "width": 8.0, "length": 8.0}, true)
	world._activate_attack_entity(player, frame_hit)
	check(contacts.size() == 1 and world.active_attack_entities.size() == 1, "Frame entity reaches the world damage path and remains active")
	var geometry: Dictionary = contacts.back().get("hit_geometry", {}) if not contacts.is_empty() else {}
	var expected_point := Vector3(1, 0.8, 1) + Vector3(-3, 0, -1) * (0.35 * 0.9 / sqrt(10.64))
	check(world.vector(geometry.get("entity_position", [])).distance_to(expected_point) < 0.000001, "Frame hit point normalizes the full 3D center offset before flattening")
	check(world.vector(geometry.get("entity_forward", [])).is_equal_approx(Vector3(3, 0.8, 1)), "Frame HitPointDir comes from target center minus entity start position")
	check(_force(target.combat).is_equal_approx(Vector3(3, 0, 1).normalized() * 50), "Frame PushMode2 uses its radial hit direction instead of attacker facing")
	check(target.facing.is_equal_approx(-Vector3(3, 0, 1).normalized()), "World consumes the source facing immediately after frame impact")
	player.position = Vector3(0, 0, 3)
	player.facing = Vector3.LEFT
	world._tick_attack_entities(0.1)
	geometry = contacts.back().get("hit_geometry", {}) if not contacts.is_empty() else {}
	check(contacts.size() == 2, "Continuous frame entity reaches its second target contact")
	check(world.vector(geometry.get("entity_forward", [])).is_equal_approx(Vector3(3, 0.8, 1)), "Later frame contacts retain StartPosition after the attacker moves")
	check(world.vector(geometry.get("attacker_position", [])).is_equal_approx(player.position), "Frame contact still records the current attacker for other direction modes")
	world.active_attack_entities.clear()
	contacts.clear()
	player.position = Vector3(-2, 0, 0)
	player.facing = Vector3.RIGHT
	for mode in ["AttackEntityForward", "AttackEntityToAttackeeDir"]:
		var projectile_hit := _hit(0, 50, 0, {"PushMode": mode})
		var projectile_raw: Dictionary = JSON.parse_string(projectile_hit.definition.raw)
		projectile_raw.merge({"EntityType": "EET_Physical", "MotionAnimatorType": "EMAT_Line", "MotionAnimatorProperty": {"Speed": 1.0, "LifeTime": 1.0}, "EntityProperty": {"IsCheckEnvCollider": false, "MaxPassNum": 10}})
		projectile_hit.definition.raw = JSON.stringify(projectile_raw)
		var state := world._projectile(player, projectile_hit)
		state.position = Vector3(1, 0.75, 0.9)
		state.direction = Vector3.BACK
		world._tick_projectiles(0.01)
		geometry = contacts.back().get("hit_geometry", {}) if not contacts.is_empty() else {}
		check(contacts.size() == 1, "%s physical entity hits through the actual projectile collision loop" % mode)
		check(world.vector(geometry.get("entity_forward", [])).is_equal_approx(Vector3.BACK), "Physical HitPointDir follows the projectile instead of attacker facing")
		var physical_point := Vector3(1, 0.8, 1) + Vector3(0, 0, -0.09) * (0.35 * 0.9 / sqrt(0.0106))
		check(world.vector(geometry.get("entity_position", [])).distance_to(physical_point) < 0.000001, "Physical hit point uses current projectile position after movement")
		check(_force(target.combat).is_equal_approx(Vector3.BACK * 50), "%s resolves the projectile's current contact geometry" % mode)
		for projectile in world.projectiles.duplicate(): world._recycle_projectile(projectile)
		world.projectiles.clear()
		contacts.clear()
	world.actors.erase(target)
	target.free()

func _world_motion() -> void:
	var original_fps := Engine.physics_ticks_per_second
	var world := DungeonWorld.new()
	root.add_child(world)
	var settings: Resource = world.FEEL
	var enabled: bool = settings.impact_enabled
	settings.impact_enabled = false
	world.set_process(false)
	world.set_physics_process(false)
	world.source_hit_stop_percent = 0
	world.presentation.set_process(false)
	world.presentation.audio_enabled = false
	world.add_child(_body(Vector3(40, 0.2, 40), Vector3(0, -0.15, 0)))
	var wall := _body(Vector3(0.2, 10, 10), Vector3(100, 0, 0))
	world.add_child(wall)
	var player := DungeonActor.new()
	player.is_player = true
	player.combat = Combat.new()
	player.combat.configure()
	player.combat.actor_key = "player"
	player.position = Vector3(-2, 0, 0)
	player.facing = Vector3.RIGHT
	world.add_child(player)
	world.player = player
	world.actors.append(player)
	_world_geometry(world, player)
	for fps in [30, 60, 120]:
		Engine.physics_ticks_per_second = fps
		await process_frame
		await physics_frame
		for blocked in [false, true]:
			wall.position.x = 0.65 if blocked else 100.0
			var actor := DungeonActor.new()
			actor.combat = _enemy()
			actor.combat.actor_key = "target_%s_%s" % [fps, blocked]
			world.add_child(actor)
			world.actors.append(actor)
			await physics_frame
			world._apply_hit(player, actor, _hit())
			check(_force(actor.combat).is_equal_approx(Vector3.RIGHT * 50), "World passes attacker/target geometry at%sHz blocked%s" % [fps, blocked])
			check(actor.knockback_elapsed < 0 and actor.impulse.is_zero_approx(), "World avoids generic feel impulse for a source monster")
			var steps: Array[Dictionary] = []
			for frame in 24:
				await physics_frame
				actor.combat.tick(1.0 / fps)
				var source_step: float = actor.combat.enemy_hit_motion_step
				actor._physics_process(1.0 / fps)
				if frame < 16 and not blocked:
					steps.append({"source_step": source_step, "position": actor.position.x, "remaining": _remaining(actor.combat), "action": actor.combat.current_action})
			var expected := {30: 0.5727267563343048, 60: 0.49263760820031166, 120: 0.4748039562255144}
			if blocked:
				check(actor.position.x > 0.18 and actor.position.x < 0.201, "A physical wall stops source monster knockback at%sHz: %s" % [fps, actor.position.x])
			else:
				check(absf(actor.position.x - float(expected[fps])) < 0.00002, "Real actor follows source displacement at%sHz: %s" % [fps, actor.position.x])
			check(absf(actor.position.z) < 0.0001 and actor.position.y < 0.001, "World knockback stays planar at%sHz" % fps)
			physics_rows.append({"fps": fps, "blocked": blocked, "distance": actor.position.x, "steps": steps})
			world.actors.erase(actor)
			actor.free()
	Engine.physics_ticks_per_second = 60
	wall.position.x = 100
	await process_frame
	await physics_frame
	for scale in [0.25, 2.0]:
		var scaled := DungeonActor.new()
		scaled.combat = _enemy()
		scaled.combat.actor_key = "scaled_target_%s" % scale
		world.add_child(scaled)
		world.actors.append(scaled)
		await physics_frame
		world._apply_hit(player, scaled, _hit())
		scaled.simulation_scale = scale
		var scaled_delta: float = scale / 60.0
		var expected_step := float(int(scaled_delta * 1000.0)) / 1000.0
		scaled.combat.tick(scaled_delta)
		scaled._physics_process(scaled_delta)
		check(absf(scaled.position.x - expected_step / BASE_DURATION) < 0.000002, "Battle scale%s advances actual knockback once through CharacterBody movement" % scale)
		check(absf(_remaining(scaled.combat) - (BASE_DURATION - expected_step)) < 0.000001, "Battle scale%s advances the same source timer as displacement" % scale)
		var paused_position := scaled.position
		var paused_remaining := _remaining(scaled.combat)
		scaled.simulation_scale = 0.0
		scaled._physics_process(1.0 / 60)
		check(scaled.position == paused_position and _remaining(scaled.combat) == paused_remaining, "Zero battle scale holds both displacement and timer")
		world.actors.erase(scaled)
		scaled.free()
	var moving := DungeonActor.new()
	moving.combat = _enemy()
	moving.combat.actor_key = "moving_target"
	world.add_child(moving)
	world.actors.append(moving)
	await physics_frame
	world._apply_hit(player, moving, _hit())
	moving.combat.tick(1.0 / 60)
	moving.begin_action({"duration": 0.5, "timeline_duration": 0.5})
	moving.add_action_motion({"type": "EET_Move", "time": 0.0, "duration": 0.5}, {"MoveDirType": "EMDT_Custom", "CustomDirection": {"x": 1, "y": 0, "z": 0}, "CustomSpeed": 3.0, "MoveSpeedType": "EMST_Line"})
	moving.combat.action_elapsed = 1.0 / 60
	moving._physics_process(1.0 / 60)
	physics_rows.append({"case": "additive", "position": [moving.position.x, moving.position.y, moving.position.z], "remaining": _remaining(moving.combat)})
	check(moving.position.x > 0.1 and absf(moving.position.z) > 0.001, "Source knockback is added to existing authored action movement")
	var held_position := moving.position
	var held_timer := _remaining(moving.combat)
	moving.combat.frozen = 0.2
	moving.combat.tick(1.0 / 60)
	await physics_frame
	moving._physics_process(1.0 / 60)
	check(absf(moving.position.x - held_position.x) < 0.000001 and _remaining(moving.combat) == held_timer, "Actor freezes source displacement and its remaining timer together")
	moving.begin_death()
	check(Reaction.advance_motion(moving.combat, 1.0 / 60).is_zero_approx(), "Actor death discards pending source knockback")
	world.free()
	settings.impact_enabled = enabled
	Engine.physics_ticks_per_second = original_fps
