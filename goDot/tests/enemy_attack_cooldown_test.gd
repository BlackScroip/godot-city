extends SceneTree

const Combat = preload("res://scripts/domain/combat.gd")
var checks := 0
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	_test_source_buffs()
	_test_behavior_tree_gate()
	_test_fallback_and_action_timing()
	_test_restore()
	var result = {"checks": checks, "passed": failures.is_empty(), "failures": failures}
	FileAccess.open("res://reports/enemy-attack-cooldown.json", FileAccess.WRITE).store_string(JSON.stringify(result, "\t"))
	print("ENEMY_ATTACK_COOLDOWN_TEST ", JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)

func _enemy(id: int) -> RefCounted:
	var combat = Combat.new()
	check(combat.configure_enemy(id, 77).success, "Source enemy config loads")
	return combat

func _test_source_buffs() -> void:
	var wolf = _enemy(11001)
	check(is_equal_approx(wolf.enemy_attack_cooldown(), 3.0), "Unmodified wolf uses the source three second interval")
	wolf.add_buff("101000040")
	check(is_equal_approx(wolf.attribute("Monster_AttackCDRate"), -500), "Normal difficulty buff exposes its original per mille stat")
	check(is_equal_approx(wolf.enemy_attack_cooldown(), 1.5), "Normal difficulty buff halves the source interval")
	check(not wolf.diagnostics.any(func(message): return "Monster_AttackCDRate" in message), "Attack interval attribute has a runtime adapter")
	wolf.add_buff("101000040")
	check(is_equal_approx(wolf.enemy_attack_cooldown(), 1.5), "Max one layer prevents duplicate difficulty buff multiplication")
	wolf.set_external_attributes({"Monster_AttackCDRate": 200})
	check(is_equal_approx(wolf.enemy_attack_cooldown(), 2.1), "Numerical sources add before applying the per mille factor")
	wolf.remove_buff("101000040")
	check(is_equal_approx(wolf.enemy_attack_cooldown(), 3.6), "Removing the passive restores its interval contribution")
	wolf.set_external_attributes({"Monster_AttackCDRate": -1000})
	check(is_zero_approx(wolf.enemy_attack_cooldown()), "Native formula permits a zero interval")
	wolf.set_external_attributes({"Monster_AttackCDRate": -1500})
	check(is_equal_approx(wolf.enemy_attack_cooldown(), -1.5), "Native formula has no fabricated minimum clamp")
	var boss = _enemy(13002)
	boss.add_buff("45400010")
	check(is_equal_approx(boss.enemy_attack_cooldown(), 1.0), "Boss difficulty passive halves the flower's two second interval")
	check(is_equal_approx(boss.effective_attack_power(), boss.attack * 1.25), "Boss passive retains its separate attack modifier")
	check(is_zero_approx(boss.attribute("AttackSpeedRate")), "Attack interval reduction does not become animation speed")
	var player = Combat.new()
	player.configure()
	check(is_zero_approx(player.enemy_attack_cooldown()), "Player has no monster attack interval")

func _context() -> Dictionary:
	return {"target_available": true, "distance": 2.5, "line_blocked": false, "battle_time": 0.0, "target_buffs": []}

func _test_behavior_tree_gate() -> void:
	var baseline = _enemy(21002)
	var enhanced = _enemy(21002)
	enhanced.add_buff("101000040")
	baseline.enemy_ai.blackboard.BB_AttackCDTimer = 3.0
	enhanced.enemy_ai.blackboard.BB_AttackCDTimer = 3.0
	check(baseline.tick_enemy_ai(0.0, _context()).action in ["runaway", "waitattack"], "Unmodified source tree still waits after three seconds")
	check(enhanced.tick_enemy_ai(0.0, _context()).action == "attack", "Reduced interval opens the real source tree attack gate after three seconds")
	check(is_equal_approx(float(enhanced.enemy_ai.blackboard.BB_AttackCD), 2.5), "Behavior tree receives the effective interval")
	check(enhanced.current_action == "born", "Shorter interval preserves the authored spawn action gate")
	enhanced.remove_buff("101000040")
	enhanced.tick_enemy_ai(0.0, _context())
	check(is_equal_approx(float(enhanced.enemy_ai.blackboard.BB_AttackCD), 5.0), "AI refreshes the interval after a passive is removed")
	enhanced.set_external_attributes({"Monster_AttackCDRate": 500})
	enhanced.tick_enemy_ai(0.0, _context())
	check(is_equal_approx(float(enhanced.enemy_ai.blackboard.BB_AttackCD), 7.5), "AI refreshes positive interval changes without respawning")
	var wolf = _enemy(11001)
	wolf.add_buff("101000040")
	wolf.enemy_ai.blackboard.BB_AttackCDTimer = 1.6
	check(wolf.tick_enemy_ai(0.0, _context()).action in ["runaway", "waitattack"], "Wolf source graph retains its separate fixed SYS_AttackCD gate")
	check(is_equal_approx(float(wolf.enemy_ai.blackboard.SYS_AttackCD), 3.0), "Runtime adapter does not overwrite authored fixed graph constants")

func _test_fallback_and_action_timing() -> void:
	var baseline = _enemy(21002)
	var enhanced = _enemy(21002)
	enhanced.add_buff("101000040")
	check(baseline.request_enemy_attack().success and enhanced.request_enemy_attack().success, "Fallback actors select their real source attack")
	check(baseline.current_action == "attack" and enhanced.current_action == "attack", "Interval passive leaves attack selection unchanged")
	check(is_equal_approx(baseline.busy, 5.0), "Baseline fallback waits for the source five second interval")
	check(is_equal_approx(enhanced.busy, 3.0), "Reduced fallback interval still completes the source three second action")
	check(is_equal_approx(float(baseline.custom_properties._feel_action_speed), float(enhanced.custom_properties._feel_action_speed)), "Cooldown passive preserves source action playback speed")
	var baseline_hits: Array = baseline._pending.filter(func(event): return event.has("hit"))
	var enhanced_hits: Array = enhanced._pending.filter(func(event): return event.has("hit"))
	check(not baseline_hits.is_empty() and baseline_hits.size() == enhanced_hits.size(), "Source attack keeps its hit timeline")
	check(is_equal_approx(float(baseline_hits[0].at), float(enhanced_hits[0].at)), "Cooldown passive does not move the source hit time")
	var overridden = _enemy(21002)
	overridden.add_buff("101000040")
	overridden.custom_properties.BB_AttackCD = 7.0
	check(overridden.request_enemy_attack().success and is_equal_approx(overridden.busy, 7.0), "Explicit blackboard interval remains a final value without double scaling")

func _test_restore() -> void:
	var original = _enemy(21002)
	original.add_buff("101000040")
	original.enemy_ai.blackboard.BB_AttackCDTimer = 3.0
	original.tick_enemy_ai(0.0, _context())
	var snapshot = JSON.parse_string(JSON.stringify(original.snapshot()))
	var restored = _enemy(21002)
	check(restored.restore(snapshot), "Enemy interval buff and AI state survive JSON save reload")
	check(is_equal_approx(restored.enemy_attack_cooldown(), original.enemy_attack_cooldown()), "Reloaded interval is recalculated from the persisted buff")
	var before = restored._random_state
	check(restored.tick_enemy_ai(0.0, _context()).action == original.tick_enemy_ai(0.0, _context()).action, "Restored attack gate matches the uninterrupted enemy")
	check(restored._random_state == before, "Interval recomputation consumes no combat random draws")
