extends SceneTree

const EnemyAI = preload("res://scripts/domain/enemy_ai.gd")
var assertions := 0
var failures: Array = []
var catalog: Dictionary = {}
var cases: Array = []

func _initialize() -> void:
	catalog = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/combat.json"))
	_test_source_distances_and_cooldowns()
	_test_phase_and_reward_rules()
	_test_shark_cohort()
	_test_catalog_sweep()
	var file = FileAccess.open("res://reports/enemy-ai-test.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"schema": 1, "assertions": assertions, "failures": failures, "cases": cases, "evidence": "Serialized APK NodeCanvas graphs plus packaged node constructors and enum metadata. Tests execute the Godot interpreter; they do not establish APK runtime parity."}, "\t"))
	print("ENEMY AI TEST: %s assertions, %s failures" % [assertions, failures.size()])
	for failure in failures: printerr(failure)
	quit(0 if failures.is_empty() else 1)

func _test_source_distances_and_cooldowns() -> void:
	var wolf = _ai(11001)
	var context = _context(2.5)
	_check(wolf.tick(0.1, context).action in ["runaway", "waitattack"], "Wolf keeps distance before source three second cooldown")
	wolf.blackboard.BB_AttackCDTimer = 3.0
	_check(wolf.tick(0.0, context).action == "attack", "Wolf chooses near attack below three meters")
	context.distance = 4.0
	_check(wolf.tick(0.0, context).action == "attack2", "Wolf chooses authored leap between three and five meters")
	context.distance = 5.01
	_check(wolf.tick(0.0, context).action == "run", "Wolf closes beyond source five meter attack range")
	wolf.notify_action_started("attack2")
	wolf.tick(0.5, context)
	_check(is_zero_approx(float(wolf.blackboard.BB_AttackCDTimer)), "Wolf attack resets cooldown while source action is active")
	wolf.notify_action_started("idle")
	wolf.tick(0.5, context)
	_check(is_equal_approx(float(wolf.blackboard.BB_AttackCDTimer), 0.5), "Wolf cooldown advances during idle")
	context.target_available = false
	_check(wolf.tick(0.1, context).action == "idle", "Wolf idles without target")
	var archer = _ai(21002)
	context = _context(3.0)
	var retreat: Dictionary = archer.tick(0.1, context)
	_check(retreat.action in ["runaway", "waitattack"], "Archer uses source keep out branch during reload")
	archer.blackboard.BB_AttackCDTimer = 5.0
	_check(archer.tick(0, context).action == "attack", "Archer shoots at source range when ready")
	var bat = _ai(11002)
	context = _context(4.0)
	context.line_blocked = true
	bat.blackboard.BB_AttackCDTimer = 2.0
	var blocked: Dictionary = bat.tick(0, context)
	_check(not ["attack", "attack2"].has(blocked.action), "Bat projectile branch respects source wall predicate")
	context.line_blocked = false
	var clear: Dictionary = bat.tick(0, context)
	_check(clear.action in ["attack", "attack2"], "Bat shoots through source unobstructed branch")
	var lizard = _ai(12001, 5)
	lizard.blackboard.BB_AttackCDTimer = 1.0
	for index in 180:
		lizard.tick(1.0 / 60.0, _context(3.0))
	_check(lizard.diagnostics.is_empty(), "Lizard cooldown filters keep valid fallback selection")
	_check(int(lizard.blackboard.BB_NextAttackId) >= 0, "Lizard chooses source next attack id rather than action round robin")

func _test_phase_and_reward_rules() -> void:
	var bee = _ai(41002)
	var context = _context(2.0)
	context.hp_ratio = 0.19
	_check(bee.tick(0, context).action == "attack2", "Poison bee source low HP branch selects explosion")
	var chimera = _ai(52001)
	context.hp_ratio = 0.5
	_check(chimera.tick(0, context).action == "LastStand", "Chimera source half health branch enters LastStand")
	chimera.notify_action_started("LastStand")
	chimera.tick(0.1, context)
	_check(bool(chimera.blackboard.BB_IsLastStand), "Chimera records LastStand through source acknowledgement")
	var slime = _ai(90001)
	context = _context(3.0)
	_check(slime.tick(0, context).action == "idle", "Uninjured reward slime starts idle")
	context.hp_ratio = 0.79
	var result: Dictionary = slime.tick(0.1, context)
	_check(result.action == "runaway" and result.messages.size() == 1, "Reward slime flees and signals eighty percent threshold")
	_check(slime.tick(0.1, context).messages.is_empty(), "Reward slime threshold reward does not repeat")
	context.hp_ratio = 0.1
	var rewards := 0
	for index in 10:
		var step: Dictionary = slime.tick(0.1, context)
		rewards += step.messages.size()
	_check(rewards == 2 and int(slime.blackboard.BB_HpChecker) == 3, "Reward slime source graph emits sixty and forty percent rewards; incomplete twenty percent BinarySelector stays optional")
	context.self_buffs = ["900001"]
	_check(slime.tick(0.1, context).action == "run", "Reward slime slow buff changes authored flee branch to run")
	context.self_buffs = []
	context.target_buffs = ["70101113"]
	_check(slime.tick(0.1, context).action == "run", "Reward slime source target buff predicate is distinct from self buff")

func _test_shark_cohort() -> void:
	for index in 3:
		var shark = _ai(52002)
		var context = _context(5.0)
		context.monster_index = index
		shark.notify_action_started("born_bosspose")
		shark.tick(0.1, context)
		_check(int(shark.blackboard.SYS_ShayuIndex) == index, "Shark records cohort index %s" % index)
		_check(int(shark.blackboard.SYS_NextMode) == index + 1, "Shark cohort chooses distinct source initial mode %s" % index)
		shark.notify_action_started("dive")
		context.battle_time = 6.1
		shark.tick(0.1, context)
		_check(bool(shark.blackboard.SYS_AttackReady), "Shark leaves source opening wait %s" % index)
		_check(is_equal_approx(float(shark.blackboard.SYS_Timer), 2.1), "Shark source opening timer starts at two seconds %s" % index)

func _test_catalog_sweep() -> void:
	var action_index: Dictionary = {}
	for action in catalog.actions: action_index[action.key] = action
	var mapped_outputs: Dictionary = {}
	for action in catalog.actions:
		for event in action.events:
			if not event.enabled or event.type != "EET_Interrupt" or not action_index.has(str(action.group) + "/" + str(event.target)): continue
			var raw: Dictionary = JSON.parse_string(event.raw)
			for condition in raw.get("Conditions", []):
				if condition.get("InterruptType", "") == "EIT_CheckAI": mapped_outputs[str(action.group) + "/" + str(condition.get("CompareVal", ""))] = true
	for definition in catalog.enemies:
		var ai = _ai(int(definition.id), 12345)
		var emitted: Dictionary = {}
		var visited: Dictionary = {}
		var assignments := 0
		var missing: Array = []
		for mode in [0, 1, 2]:
			var context = _context(2.0)
			context.monster_index = mode
			ai.notify_action_started("born_bosspose" if int(definition.id) == 52002 else "idle")
			for frame in 720:
				context.distance = [1.0, 3.5, 5.5, 9.0][(frame / 90) % 4]
				context.hp_ratio = [1.0, 0.79, 0.59, 0.49, 0.29, 0.19][mini(5, frame / 120)]
				context.target_available = frame % 240 < 230
				context.line_blocked = frame % 200 > 190
				context.battle_time = frame / 10.0
				if int(definition.id) == 52002 and frame == 1: ai.notify_action_started("dive")
				var result: Dictionary = ai.tick(0.1, context)
				for node in result.visited: visited[node] = true
				assignments += result.trace.size()
				if result.action.is_empty(): continue
				emitted[result.action] = true
				var key = str(definition.group) + "/" + result.action
				if not action_index.has(key) and not mapped_outputs.has(key) and not missing.has(key): missing.append(key)
				# The real action engine acknowledges accepted actions; this bounded sweep
				# supplies acknowledgements to cover state conditions, not combat physics.
				if frame % 10 == 0: ai.notify_action_started(result.action)
				elif frame % 10 == 9:
					ai.notify_action_ended(result.action)
					ai.notify_action_started("idle")
		_check(ai.diagnostics.is_empty(), "All tasks supported for enemy %s: %s" % [definition.id, ai.diagnostics])
		_check(assignments > 0, "Enemy graph evaluates state assignments %s" % definition.id)
		_check(not emitted.is_empty(), "Enemy graph produces actions %s" % definition.id)
		var expected_missing = ["ActGroup_juchifeiyao/meaninglessrunaway"]
		_check(missing.all(func(key): return expected_missing.has(key)), "No unexpected unmapped AI outputs %s: %s" % [definition.id, missing])
		var snapshot: Dictionary = JSON.parse_string(JSON.stringify(ai.snapshot()))
		var copy = _ai(int(definition.id), 999)
		_check(copy.restore(snapshot), "Enemy graph restores matching state %s" % definition.id)
		for frame in 20:
			var context = _context(4.0)
			context.hp_ratio = 0.25
			var a: Dictionary = ai.tick(0.1, context)
			var b: Dictionary = copy.tick(0.1, context)
			_check(_equivalent(a, b), "Enemy graph deterministic replay %s frame %s" % [definition.id, frame])
		cases.append({"enemy": definition.id, "graph": definition.ai, "emitted_actions": emitted.keys(), "visited_nodes": visited.size(), "connected_nodes": ai._nodes.size(), "diagnostics": ai.diagnostics.duplicate(), "missing_actions": missing})

func _ai(id: int, seed_value := 1) -> RefCounted:
	for definition in catalog.enemies:
		if int(definition.id) != id: continue
		var ai = EnemyAI.new()
		_check(ai.configure(definition, catalog.ai_graphs[definition.ai], seed_value), "Graph loads %s" % id)
		return ai
	_check(false, "Unknown source enemy %s" % id)
	return EnemyAI.new()

func _context(distance: float) -> Dictionary:
	return {"target_available": true, "distance": distance, "line_blocked": false, "hp_ratio": 1.0, "move_speed": 5.0, "self_buffs": [], "target_buffs": []}

func _equivalent(a: Variant, b: Variant) -> bool:
	# JSON persistence rounds floats and converts integral values to floating point.
	if (a is int or a is float) and (b is int or b is float):
		return absf(float(a) - float(b)) <= 0.000000001 * maxf(1.0, maxf(absf(float(a)), absf(float(b))))
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for index in a.size():
			if not _equivalent(a[index], b[index]): return false
		return true
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not _equivalent(a[key], b[key]): return false
		return true
	return a == b

func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition: failures.append(message)
