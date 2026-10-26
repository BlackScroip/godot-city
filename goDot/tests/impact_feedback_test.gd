extends SceneTree

const Combat = preload("res://scripts/domain/combat.gd")
const Profiles = preload("res://scripts/presentation/impact_profiles.gd")
const Intent = preload("res://scripts/player_intent.gd")
const FEEL = preload("res://assets/feel_settings.tres")
var failures: Array[String] = []
var assertions := 0

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func packet(emission := 1) -> Dictionary:
	return {"definition": {"damageId": 210001}, "damage": 100.0, "sequence": 1, "emission": emission}

func _run() -> void:
	var source = Combat.new()
	source.configure(null, null, 1, 0, 731)
	var target = Combat.new()
	target.configure_enemy(11001)
	target.defense = 0
	var confirmed: Array = []
	target.impact_confirmed.connect(func(hit): confirmed.append(hit))
	var hit = packet()
	hit.source = source
	target.shield = 150
	var returned = target.receive(hit)
	check(returned == 0 and target.shield == 50 and target.health == target.max_health, "Shield absorption preserves receive float result")
	check(confirmed.size() == 1 and confirmed[0].resolved_absorbed == 100 and not confirmed[0].has("source"), "Shield emits settled, serializable result exactly once")
	check(Profiles.resolve(hit, source).category == "shield", "Absorbed hit uses shield profile")
	target.invincible = 1
	var rejected = packet(2)
	target.receive(rejected)
	check(not rejected.resolved_accepted and confirmed.size() == 1, "Invincibility rejects impact without false contact")
	target.invincible = 0
	target.shield = 0
	var critical = packet(3)
	critical.merge({"critical_roll": 0.0, "critical_rate": 1.0, "critical_multi": 2.0, "definition": {"critical": true}}, true)
	target.receive(critical)
	check(critical.resolved_critical and Profiles.resolve(critical).category == "heavy", "Final critical result upgrades feedback")
	check(is_equal_approx(float(Profiles.resolve(critical).stop), 0.08), "Light critical upgrades to heavy stop")
	check(is_equal_approx(float(Profiles.resolve({"impact_category": "heavy", "resolved_critical": true}).stop), 0.1), "Heavy critical stop is capped at100 ms")
	target.health = target.max_health
	var area = {"definition": {"radius": 5, "enableDamage": true}, "damage": 1.0, "source": source, "continuous": true, "impact_origin": [2, 0, 0], "emission": 4}
	target.apply_area(area, false, 1)
	check(confirmed.back().continuous and confirmed.back().impact_origin == [2, 0, 0], "Area contact retains origin and continuous context")
	check(Profiles.resolve(confirmed.back(), source).stop == 0, "Persistent area does not freeze actors")
	check(Profiles.ranged({"summon_id": "4001021"}), "Detached summons never freeze their owner")
	check(Profiles.ranged({"definition": {"raw": {"EmitProperty": {"PosType": "EEPT_TargetPos"}, "MotionAnimatorType": "EMAT_None"}}}), "Target-position spell is ranged without a moving projectile")
	check(not Profiles.ranged({"origin": [0, 0, 0]}), "World-space origin preserves melee classification")
	var dot = Combat.new()
	dot.configure_enemy(11001)
	dot._buff_index = {"test_dot": {"type": "EBT_SpecialTriggerRangeDamage", "selfOnlyDamage": true, "fixedDamage": 100, "interval": 1.0}}
	dot.statuses = {"test_dot": {"id": "test_dot", "time": 1.0, "tick": 0.0, "layers": 1, "attack": 1.0, "modifier_cooldown": 0.0}}
	dot.health = 5
	var ticks: Array = []
	dot.impact_confirmed.connect(func(event): ticks.append(event))
	dot.tick(0.02)
	check(ticks.size() == 1 and ticks[0].resolved_damage == 5, "Lethal continuous tick reports actual health lost exactly once")
	for fps in [30, 60, 120]:
		var combat = Combat.new()
		combat.configure()
		combat.request_attack(0)
		combat.drain_events()
		combat.cooldowns[2] = 2.0
		var pending_at = float(combat._pending[0].at)
		check(combat.apply_hit_stop(0.08, true), "Melee stop starts at %s Hz" % fps)
		check(not combat.apply_hit_stop(0.09) and is_equal_approx(combat.impact_pause, 0.09), "Crowd contacts use strongest duration without restarting at %s Hz" % fps)
		combat.tick(1.0 / fps)
		check(combat.action_step == 0 and combat.action_elapsed == 0, "Action clock holds at %s Hz" % fps)
		check(combat.cooldowns[2] < 2 and combat._clock > 0, "Cooldown and independent clock continue at %s Hz" % fps)
		check(combat._pending[0].at >= pending_at, "Action events share local stop at %s Hz" % fps)
		var snapshot = combat.snapshot()
		var restored = Combat.new()
		restored.configure()
		check(restored.restore(snapshot) and restored.impact_pause == 0 and restored.action_elapsed == combat.action_elapsed, "Save restores local timeline without transient freeze")
		var old = snapshot.duplicate(true)
		old.custom_properties.erase("_local_action_elapsed")
		old.custom_properties.erase("_recovery_credit")
		check(restored.restore(old), "Legacy v1 save still loads")
		combat._recovery_credit = -0.015
		check(restored.restore(combat.snapshot()) and is_equal_approx(restored._recovery_credit, -0.015), "Save retains signed phase recovery credit")
		combat.clear_impact_state()
		check(combat.apply_stagger(0.4, false) and combat.stagger_remaining <= 0.08, "Player reaction capped at80 ms")
		check(not combat.apply_stagger(0.4, true), "Player repeated hits do not refresh active stagger")
		combat.tick(0.09)
		check(not combat.apply_stagger(0.4, true), "Player grace prevents chain stun")
		combat.clear_impact_state()
		combat.apply_hit_stop(0.1)
		combat.apply_stagger(0.08, false)
		check(combat.request_attack(1).success and combat.stagger_remaining == 0 and combat.impact_pause == 0, "Dodge immediately leaves reaction")
		var buffered = Combat.new()
		buffered.configure()
		buffered.busy = 0.08
		buffered.apply_hit_stop(0.08, true)
		var intent = Intent.new()
		check(intent.request(buffered, 2, true).success, "Skill press remains accepted during stop at%s Hz" % fps)
		var executions = 0
		for frame in ceili(fps * 0.4):
			buffered.tick(1.0 / fps)
			var ready = intent.take_ready(buffered, 1.0 / fps)
			if ready >= 0:
				if buffered.request_attack(ready).success: executions += 1
			buffered.drain_events()
		check(executions == 1 and intent.pending.is_empty(), "Buffered skill executes once after local pause at%s Hz" % fps)
		var lance = Combat.new()
		lance.configure(null, null, 7)
		lance.request_attack(4)
		lance.drain_events()
		lance.apply_hit_stop(0.08, true)
		var charge_input = Intent.new()
		charge_input.heavy_held = true
		charge_input.request(lance, 4, false)
		var releases = 0
		for frame in fps:
			lance.tick(1.0 / fps)
			for event in lance.drain_events():
				if event.type == "action_started": releases += 1
		check(not lance.charging and releases == 1, "Charge release during local pause is retained once at%s Hz" % fps)
		var victim = Combat.new()
		victim.configure_enemy(11001)
		victim.request_enemy_attack()
		var before_sequence: int = victim._cast_sequence
		check(not victim.apply_stagger(0.18, true) and victim.busy > 0 and victim._cast_sequence == before_sequence, "Generic presentation stagger cannot cancel a monster's source action")
	for rank in ["Normal", "Elite", "Boss"]:
		var fighter = Combat.new()
		fighter.configure_enemy(11001)
		fighter.enemy = fighter.enemy.duplicate(true)
		fighter.enemy.rank = rank
		check(is_equal_approx(Profiles.reaction_scale(fighter), {"Normal": 1.0, "Elite": 0.5, "Boss": 0.0}[rank]), "Reaction scale for " + rank)
		fighter.custom_properties.SuperArmor = true
		check(Profiles.reaction_scale(fighter) == 0, "Explicit super armor resists reaction")
	for category in ["light", "heavy", "explosion"]:
		var profile: Dictionary = FEEL.impact_profiles[category]
		for fps in [30, 60, 120]:
			var distance = 0.0
			var elapsed = 0.0
			while elapsed < float(profile.travel):
				var after = elapsed + 1.0 / fps
				distance += float(profile.distance) * (DungeonActor.knockback_progress(after / float(profile.travel)) - DungeonActor.knockback_progress(elapsed / float(profile.travel)))
				elapsed = after
			check(absf(distance - float(profile.distance)) < 0.0001, "%s knockback integrates at%s Hz" % [category, fps])
	var world = DungeonWorld.new()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.presentation.set_process(false)
	var player = DungeonActor.new()
	player.is_player = true
	player.combat = source
	source.actor_key = "player"
	world.add_child(player)
	world.player = player
	world.actors.append(player)
	world.camera.position = Vector3(0, 12, -10)
	world.camera.look_at(Vector3.ZERO)
	var received: Array = []
	world.impact_confirmed.connect(func(event): received.append(event))
	for index in 3:
		var enemy = DungeonActor.new()
		enemy.combat = Combat.new()
		enemy.combat.configure_enemy(11001)
		enemy.combat.actor_key = "target:%s" % index
		world.add_child(enemy)
		world.actors.append(enemy)
		enemy.position = Vector3(index * 0.75, 0, 0)
		var explosion = packet(90)
		explosion.merge({"impact_category": "explosion", "impact_origin": [0, 0, 0], "impact_radius": 4.0})
		world._apply_hit(player, enemy, explosion)
	check(received.size() == 3 and world._seen_blasts.size() == 1 and world._camera_impulses.size() == 1, "One explosion gives three contacts and one camera impulse")
	check(world.actors[1].knockback_elapsed < 0 and world.actors[1].combat.stagger_remaining == 0, "Explosion presentation alone cannot invent monster knockback or stagger")
	check(world.actors[2].knockback_elapsed < 0 and world.actors[3].knockback_elapsed < 0, "Explosion radius does not bypass source monster hit admission")
	var before = received.size()
	var immune: DungeonActor = world.actors[1]
	immune.combat.invincible = 1
	world._apply_hit(player, immune, packet(91))
	check(received.size() == before, "World does not present invincible contact")
	immune.combat.invincible = 0
	immune.clear_impact_state()
	immune.position = Vector3(0, 0, 1)
	player.face_direction(Vector3.BACK)
	var pull = packet(92)
	pull.merge({"action": "orb_satk_loop_1", "slot": 4, "definition": {"damageId": 210001, "raw": JSON.stringify({"FeedbackList": [{"FeedbackType": "EHT_HitAction", "PushPower": -20, "AttackDirIsAttackerForwardOrHitPointDir": true}]})}}, true)
	world._apply_hit(player, immune, pull)
	check(immune.knockback_elapsed < 0 and is_zero_approx(immune.combat.stagger_remaining) and is_zero_approx(immune.combat.impact_pause), "Source orb accumulation does not add a hand-authored pull, stagger or hit pause")
	check(Profiles.resolve(pull, source).source_only and is_zero_approx(Profiles.resolve(pull, source).distance) and Profiles.resolve(pull, source).source_feedback.hit_actions[0].push_power == -20, "Source orb push power remains unconverted without a hand-authored distance override")
	check(Profiles.resolve(pull, source).stop == 0 and Profiles.resolve(pull, source).amplitude == 0, "Orb pull does not spam hit stop or camera shake")
	var environmental = received.size()
	immune.combat._buff_index = immune.combat._buff_index.duplicate()
	immune.combat._buff_index["test_trap"] = {"type": "EBT_SpecialBuffHP", "healPercent": -10}
	world._environment_trap({"target_id": immune.combat.actor_key, "buff_id": "test_trap", "layers": 1, "position": [0, 0, 0], "radius": 4, "explosion": true})
	check(received.size() == environmental + 1 and received.back().resolved_damage > 0 and received.back().profile.category == "explosion", "Instant environmental HP damage shares settled feedback entry")
	immune.combat.invincible = 1
	world._environment_trap({"target_id": immune.combat.actor_key, "buff_id": "test_trap", "layers": 1})
	check(received.size() == environmental + 1, "Invulnerable direct environmental changes do not play body feedback")
	source._cast_sequence = 7
	source.busy = 1.0
	source.action_step = 0.0
	var attached_hit = {"sequence": 7, "definition": {"raw": JSON.stringify({"MotionAnimatorType": "EMAT_FollowOwner", "MotionAnimatorProperty": {"LastTime": 200}, "EntityProperty": {"IsCheckRoleUnitCollider": false}})}}
	world._projectile(player, attached_hit)
	var attached: DungeonProjectile = world.projectiles.back().state
	var missile_hit = {"sequence": 7, "definition": {"raw": JSON.stringify({"MotionAnimatorType": "EMAT_Line", "MotionAnimatorProperty": {"Speed": 2.0, "MaxLifetime": 2.0}, "EntityProperty": {"IsCheckRoleUnitCollider": false, "IsCheckEnvCollider": false}})}}
	world._projectile(player, missile_hit)
	var missile: DungeonProjectile = world.projectiles.back().state
	world._tick_projectiles(0.016)
	check(attached.age == 0 and missile.age > 0, "Local stop holds attached hitbox while released missile keeps moving")
	source.action_tick_delta = 0.016
	world.presentation.emit_effect(player, "", Vector3.ZERO, Vector3.ONE, 1.0, null, false, 7)
	world.presentation.active.back().clock_sequence = 7
	var local_effect = world.presentation.active.back()
	world.presentation._process(0.008)
	check(local_effect.age == 0, "Current action visual clock holds during local stop at higher display rate")
	source.action_step = 0.008
	world.presentation._process(0.008)
	world.presentation._process(0.008)
	check(is_equal_approx(local_effect.age, 0.008), "Effect phase speed remains stable across display and physics rates")
	world._consume(player, {"type": "action_cancelled", "sequence": 7})
	check(world.projectiles.size() == 1 and world.projectiles[0].state == missile, "Action cancel removes attached judgment and retains released missile")
	world.camera_shake_enabled = false
	world._process(0.01)
	check(world.camera.position.is_equal_approx(world._camera_focus + world._camera_offset), "Disabled camera shake restores stable camera")
	world.restore_transients({})
	check(world._camera_impulses.is_empty() and world._seen_blasts.is_empty() and world.actors[1].knockback_elapsed < 0, "Restore clears transient camera and motion")
	world.presentation.clear()
	var slash_definition = {"EffectName": "23090401_fx_sword_atk_slash1.prefab", "DummyType": "EEDT_DummyChild"}
	for direction in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
		player.face_direction(direction)
		world.presentation.trigger(player, slash_definition, 7)
		var slash = world.presentation.active.back()
		check(slash.root.global_basis.z.dot(direction) < -0.99, "Sword arc faces the authored forward hemisphere in " + str(direction))
		check((slash.root.global_position - player.global_position).dot(direction) >= 0.54, "Sword arc starts in front of the player")
		for emitter in slash.authored.emitters:
			var material: ShaderMaterial = emitter.node.material_override
			check(material.get_shader_parameter("crimson_blade") == true and is_equal_approx(float(material.get_shader_parameter("visual_gain")), FEEL.sword_light_gain), "Sword uses dim crimson material")
		world.presentation.clear()
	var hits_before = world.presentation.spawned
	world._projectile(player, {"sequence": 7, "definition": {"raw": JSON.stringify({"MotionAnimatorType": "EMAT_FollowOwner", "MotionAnimatorProperty": {"LastTime": 200}, "EntityProperty": {"EffectTriggerDef": slash_definition, "IsCheckRoleUnitCollider": false}})}})
	check(world.presentation.spawned == hits_before and not world.projectiles.back().visual.visible, "Attached judgment does not duplicate its emitted slash or show a debug sphere")
	var anchor = immune.impact_anchor(immune.position + Vector3(40, -10, 40))
	check(anchor.y > immune.position.y + 0.5 and anchor.distance_to(immune.position) < 2, "Impact anchor clamps distant/ground contact onto the body")
	immune.hurt_timer = 0
	world.presentation.impact(player, immune, {"profile": Profiles.resolve({"impact_category": "heavy"}), "impact_position": DungeonProjectile._array(immune.position)})
	var body_burst = world.presentation.active.filter(func(entry): return entry.body_burst).back()
	check(body_burst.follow.get_ref() == immune and body_burst.burst.visible, "Contact slashes attach to the struck monster")
	var burst_start: Vector3 = body_burst.root.position
	immune.position.x += 0.5
	world.presentation._process(0.016)
	check(is_equal_approx(body_burst.root.position.x - burst_start.x, 0.5), "Body contact stays on the monster during knockback")
	for entry in world.presentation.active:
		for node in entry.root.get_children():
			check(not (node is MeshInstance3D and node.mesh is TorusMesh), "Offensive feedback has no floor circle")
	for shot in world.projectiles:
		if is_instance_valid(shot.visual): shot.visual.queue_free()
	world.projectiles.clear()
	for other in world.actors:
		if other != player and other != immune: other.position = Vector3(100, 0, 100)
	player.face_direction(Vector3.BACK)
	immune.position = Vector3(0, 0, 1)
	immune.invulnerability = 0
	immune.combat.invincible = 0
	immune.combat.health = immune.combat.max_health
	immune.combat.busy = 1.0
	immune.combat.custom_properties["_action_can_hit"] = false
	var gated_hit = {"damage": 10.0, "definition": {"speed": 10, "raw": JSON.stringify({"EntityType": "EET_Physical", "MotionAnimatorType": "EMAT_Line", "MotionAnimatorProperty": {"Speed": 10, "Distance": 10, "MaxLifetime": 2}, "EntityProperty": {"MaxPassNum": 0, "IsCheckEnvCollider": false}})}}
	world._projectile(player, gated_hit)
	var gated: DungeonProjectile = world.projectiles.back().state
	var contacts_before = received.size()
	world._tick_projectiles(0.12)
	check(not gated.finished and gated.hits.is_empty(), "Source collision protection does not consume a passing projectile")
	check(received.size() == contacts_before, "Protected projectile intersection emits no impact")
	immune.combat._start(immune.combat._action(str(immune.combat.enemy.group), "idle"), 0)
	immune.position = gated.position + Vector3.BACK * 0.2 - Vector3.UP * 0.75
	world._tick_projectiles(0.02)
	check(world.projectiles.is_empty() and received.size() == contacts_before + 1 and immune.combat.health < immune.combat.max_health, "Projectile can contact again after action protection ends and is recycled")
	world.free()
	var coverage: Array = []
	for character in range(1, 8):
		var fighter = Combat.new()
		fighter.configure(null, null, character)
		var actions: Array = []
		for definition in fighter.catalog.actions:
			if definition.group != "ActGroup_playerchara": continue
			var prefix = str(fighter.fighter.combo[0]).get_slice("_", 0)
			if not str(definition.id).contains(prefix): continue
			for attack in definition.get("hits", []):
				if not attack.get("enabled", false): continue
				var p = Profiles.resolve({"action": definition.id, "definition": attack}, fighter)
				check(p.stop <= 0.1 and p.distance >= 0, "Valid profile for " + str(definition.id))
				actions.append({"action": definition.id, "category": p.category, "ranged": p.ranged})
		coverage.append({"character": character, "actions": actions})
	var report = {"passed": failures.is_empty(), "assertions": assertions, "failures": failures, "coverage": coverage, "enemy_ranks": {"Normal": 1.0, "Elite": 0.5, "Boss": 0.0}}
	FileAccess.open("res://reports/impact-feedback.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("IMPACT_FEEDBACK ", JSON.stringify({"passed": failures.is_empty(), "assertions": assertions, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
