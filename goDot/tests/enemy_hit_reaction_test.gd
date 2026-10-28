extends SceneTree

const Combat = preload("res://scripts/domain/combat.gd")
const Reaction = preload("res://scripts/domain/enemy_hit_reaction.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _enemy(id := 11001, action := "attack") -> DungeonCombat:
	var target := Combat.new()
	target.configure_enemy(id)
	target.max_health = 10000000
	target.health = target.max_health
	target.enemy_ai_enabled = true
	target.custom_properties["_enemy_spawn_entered"] = true
	target._start(target._action(str(target.enemy.group), action), 0)
	target.tick(0.0)
	target.drain_events()
	return target

func _hit(tenacity: float, push := 50.0, upper := 0.0) -> Dictionary:
	return {"damage": 1.0, "definition": {"raw": JSON.stringify({"FeedbackList": [{"FeedbackType": "EHT_HitAction", "AccTenacity": tenacity, "PushPower": push, "UpperPower": upper}]})}}

func _run() -> void:
	_source_rules()
	_tenacity_and_actions()
	_admission_and_force()
	_authored_windows()
	_clock_and_restore()
	_world_contacts()
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "scope": "APK monster parameters, native tenacity and hit-state routing, authored interrupt windows, world contacts, and JSON restore; no APK runtime execution."}
	FileAccess.open("res://reports/enemy-hit-reaction-tests.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("ENEMY HIT REACTION ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func _source_rules() -> void:
	var catalog := Combat.new()
	catalog.configure()
	for enemy in catalog.catalog.enemies:
		var rules := Reaction.rules_for(int(enemy.id))
		check(not rules.is_empty(), "Source hit parameters exist for enemy %s" % enemy.id)
	var wolf := _enemy()
	check(wolf.enemy_hit_rules.BaseTenacity == 100 and wolf.enemy_hit_rules.BaseTenacityAccReduce == 10000, "Wolf uses exact APK tenacity and recovery")
	check(is_equal_approx(wolf.enemy_hit_rules.BaseWeakTime, 0.1), "Wolf weakness uses its authored time")
	var elite := _enemy(12001, "idle")
	check(elite.enemy_hit_rules.BaseTenacity == 200 and elite.enemy_hit_rules.BaseTenacityAccReduce == 99999, "Elite uses its own source resistance")
	var boss := _enemy(13001, "idle")
	check(boss.enemy_hit_rules.BaseTenacity == 99999 and boss.enemy_hit_rules.Weight == 500, "Lord resistance comes from source data")

func _tenacity_and_actions() -> void:
	var target := _enemy()
	var sequence := target._cast_sequence
	var pending := target._pending.duplicate(true)
	target.receive(_hit(50))
	target._tick_enemy_interrupts()
	check(target.current_action == "attack" and target._cast_sequence == sequence and target._pending == pending, "Below-threshold hit preserves attack and pending damage")
	check(not Reaction.is_weak(target) and Reaction.state_for(target).accumulated == 50, "Weak hits accumulate source tenacity")
	target.tick(1.0 / 60)
	check(Reaction.state_for(target).accumulated == 0, "Source high recovery removes chip tenacity between attacks")
	target.receive(_hit(100))
	target._tick_enemy_interrupts()
	check(not Reaction.is_weak(target) and target.current_action == "attack", "Attack StableValue50 raises wolf interruption threshold from100 to150")
	target.tick(0.02)
	target.receive(_hit(150))
	check(Reaction.is_weak(target) and target.custom_properties._enemy_hit_action == "hit_1", "Threshold hit sets native low hit state")
	target._tick_enemy_interrupts()
	check(target.current_action == "behit", "Source attack routes through sys_checkbehit into low reaction")
	check(target.custom_properties._enemy_hit_action == "", "Entering state6 consumes hit state before rechecking interrupts")
	check(is_equal_approx(target.busy, 0.5) and target.stagger_remaining == 0, "Reaction duration is authored rather than generic stagger")
	check(not target._pending.any(func(event): return event.has("hit") and int(event.sequence) == sequence), "Actual reaction removes the interrupted action's unissued hits")
	var reacted := target._cast_sequence
	target._tick_enemy_interrupts()
	check(target._cast_sequence == reacted, "Consumed hit does not create a reaction loop")
	target.tick(0.11)
	target.receive(_hit(50))
	target._tick_enemy_interrupts()
	check(target._cast_sequence == reacted, "Chip damage cannot restart a reaction after weakness expires")
	target.tick(0.4)
	target._tick_enemy_interrupts()
	check(target.current_action == "idle", "Source reaction returns to idle at its timeline end")
	var no_feedback := _enemy()
	no_feedback.receive({"damage": 10.0, "definition": {}})
	no_feedback._tick_enemy_interrupts()
	check(no_feedback.current_action == "attack" and not Reaction.is_weak(no_feedback), "Damage without a source HitAction does not invent interruption")
	check(not no_feedback.apply_stagger(10, true) and no_feedback.current_action == "attack", "Generic stagger API cannot bypass monster source resistance")

func _admission_and_force() -> void:
	for protection in ["shield", "armor", "invincible", "dodge", "block", "collision", "super_armor"]:
		var target := _enemy()
		match protection:
			"shield": target.shield = 100
			"armor": target.armor = 100
			"invincible": target.invincible = 1
			"dodge": target._dodge_time = 1
			"block": target._block_time = 1
			"collision": target.custom_properties._action_can_hit = false
			"super_armor": target.custom_properties.SuperArmor = true
		target.receive(_hit(1000, 1000, 1000))
		target._tick_enemy_interrupts()
		check(target.current_action == "attack" and not Reaction.is_weak(target), "%s prevents tenacity interruption" % protection)
	for power in [0.0, 9.0, 10.0, -10.0]:
		var target := _enemy()
		target.receive(_hit(150, power))
		target._tick_enemy_interrupts()
		check(target.current_action == ("attack" if absf(power) < 10 else "behit"), "Native force/weight0.1 boundary for %s" % power)
	var high := _enemy()
	high.receive(_hit(150, 0, 100))
	high._tick_enemy_interrupts()
	check(high.current_action == "behit_high" and is_equal_approx(high.busy, 2), "Upper>=weight selects authored high reaction even with zero horizontal force")
	var resistant := _enemy()
	resistant.set_external_attributes({"PushForceResist": 45})
	resistant.receive(_hit(150, 50))
	resistant._tick_enemy_interrupts()
	check(resistant.current_action == "attack", "Push resistance can prevent a hit-state request after weakness")
	var additive := _enemy()
	additive.set_external_attributes({"TenacityAccAddRate": 1000})
	additive.receive(_hit(50))
	check(Reaction.state_for(additive).accumulated == 51, "Tenacity rate is additive rather than multiplying the hit")
	var diving := _enemy(52002, "idletodive")
	check(diving.busy == 0 and not diving.can_receive_attack(), "Source CanHit protects idle-prefixed dive actions even with zero busy time")
	diving.receive(_hit(100000, 100000, 100000))
	check(not Reaction.is_weak(diving) and diving.health == diving.max_health, "Protected dive rejects both damage and tenacity")
	diving.custom_properties._action_can_hit = true
	diving.action_elapsed = 0.501
	diving._tick_attack_collision_gate()
	check(not diving.can_receive_attack(), "Authored CanBeHit event closes the gate even with zero busy time")
	diving._start(diving._action(str(diving.enemy.group), "divetoidle"), 0)
	check(diving.can_receive_attack(), "Emerging shark restores its source CanHit default")

func _authored_windows() -> void:
	var target := _enemy(11001, "behit_high")
	var sequence := target._cast_sequence
	target.receive(_hit(150))
	target._tick_enemy_interrupts()
	check(target.current_action == "behit_high" and target._cast_sequence == sequence, "Early hit does not bypass the source high-reaction protected window")
	check(not Reaction.is_weak(target) and Reaction.action_rules_for(target).StableValue == 99999, "High reaction uses its source armor value rather than extending generic stagger")
	# Exercise the authored delayed window with an already requested native hit state.
	target.custom_properties["_enemy_hit_action"] = "hit_1"
	target._tick_enemy_interrupts()
	check(target.custom_properties._enemy_hit_action == "hit_1", "Blocked source action preserves its pending hit state")
	target.tick(2.0)
	target._tick_enemy_interrupts()
	check(target.current_action == "behit" and target.custom_properties._enemy_hit_action == "", "Pending hit is consumed when the authored window opens")
	var boss := _enemy(13001, "attack")
	sequence = boss._cast_sequence
	boss.receive(_hit(300, 300, 300))
	boss._tick_enemy_interrupts()
	check(boss._cast_sequence == sequence and not Reaction.is_weak(boss), "Normal heavy power cannot cancel lord attacks")
	for index in 4:
		var predicate := {"InterruptType": "EIT_CheckHitAction", "Behit_BackLow": index == 0, "Behit_BackHigh": index == 1, "Behit_Fly": index == 2, "Behit_Down": index == 3}
		var raw := {"Conditions": [predicate]}
		var compiled = target._compile_enemy_interrupt({"raw": JSON.stringify(raw)})
		for state_index in 4:
			target.custom_properties._enemy_hit_action = ["hit_1", "hit_2", "hitfly", "hitdown"][state_index]
			check(target._compiled_enemy_interrupt_conditions(compiled) == (index == state_index) and target._interrupt_conditions(raw) == (index == state_index), "Compiled and interpreted hit flags match %s/%s" % [index, state_index])

func _clock_and_restore() -> void:
	for fps in [30, 60, 120]:
		var target := _enemy()
		target.receive(_hit(150, 0))
		for frame in int(fps / 10) - 1: target.tick(1.0 / fps)
		check(Reaction.is_weak(target), "Weakness lasts until source boundary at %sHz" % fps)
		target.tick(1.0 / fps)
		check(not Reaction.is_weak(target), "Float32 weak timer expires at source boundary at %sHz" % fps)
	var frozen := _enemy()
	frozen.receive(_hit(50))
	frozen.frozen = 1.0
	frozen.tick(0.01)
	check(Reaction.state_for(frozen).accumulated == 0, "Recovery follows unit update time while action motion is frozen")
	var original := _enemy()
	original.receive(_hit(150))
	original.tick(0.04)
	var restored := _enemy()
	check(restored.restore(JSON.parse_string(JSON.stringify(original.snapshot()))), "Reaction snapshot restores through JSON")
	check(Reaction.state_for(restored) == Reaction.state_for(original) and restored.custom_properties._enemy_hit_action == "hit_1", "JSON preserves weak timer and pending source hit state")
	original.tick(0.07)
	restored.tick(0.07)
	check(Reaction.state_for(restored) == Reaction.state_for(original), "Restored tenacity state advances identically")
	var diving := _enemy(52002, "idletodive")
	var legacy := diving.snapshot()
	legacy.custom_properties.erase("_action_can_hit")
	var restored_diving := _enemy(52002, "idle")
	check(restored_diving.restore(legacy) and not restored_diving.can_receive_attack(), "Legacy snapshot rebuilds source CanHit rather than the player-heavy default")

func _world_contacts() -> void:
	var world := DungeonWorld.new()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.presentation.set_process(false)
	world.presentation.audio_enabled = false
	var player := DungeonActor.new()
	player.is_player = true
	player.combat = Combat.new()
	player.combat.configure()
	player.combat.actor_key = "player"
	world.add_child(player)
	world.player = player
	world.actors.append(player)
	var target := DungeonActor.new()
	target.combat = _enemy()
	target.combat.actor_key = "target"
	world.add_child(target)
	world.actors.append(target)
	var sequence: int = target.combat._cast_sequence
	world._apply_hit(player, target, _hit(50))
	check(target.combat.current_action == "attack" and target.combat._cast_sequence == sequence and target.combat.stagger_remaining == 0, "Real world weak contact preserves monster attack")
	check(target.knockback_elapsed < 0 and target.velocity.is_zero_approx(), "Generic feedback adds no monster knockback or upper impulse")
	target.combat.clear_impact_state()
	target.combat.tick(0.02)
	var heavy := _hit(150)
	heavy.slot = 4
	heavy.source_heavy = true
	world._apply_hit(player, target, heavy)
	target.combat.clear_impact_state()
	target.combat._tick_enemy_interrupts()
	check(target.combat.current_action == "behit" and target.combat.stagger_remaining == 0, "Source-heavy world contacts use the same tenacity/action path")
	var without_feedback := _enemy()
	var settings: Resource = without_feedback.FEEL
	var impact_enabled: bool = settings.impact_enabled
	settings.impact_enabled = false
	without_feedback.receive(_hit(150))
	without_feedback._tick_enemy_interrupts()
	check(without_feedback.current_action == "behit", "Combat reactions remain active with impact settings disabled and no presentation subscriber")
	settings.impact_enabled = impact_enabled
	world.free()
