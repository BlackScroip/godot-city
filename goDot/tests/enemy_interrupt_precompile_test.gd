extends SceneTree

const Combat = preload("res://scripts/domain/combat.gd")
const Reference = preload("res://tests/fixtures/enemy_interrupt_reference.gd")
var checks := 0
var failures: Array[String] = []
var action_pairs := 0
var source_predicates: Dictionary = {}

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok and failures.size() < 50: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var fixture := Combat.new()
	fixture.configure()
	var catalog: Dictionary = fixture.catalog
	var unchanged := catalog.duplicate(true)
	for enemy in catalog.enemies:
		_source_actions(enemy, catalog.actions)
		_runtime(enemy)
	_predicate_cases()
	_transition_cases()
	_reconfiguration()
	check(catalog == unchanged, "Compilation and evaluation preserve the entire source catalog")
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "enemies": catalog.enemies.size(), "source_action_pairs": action_pairs, "source_predicate_types": source_predicates.keys(), "scope": "Exact original-interpreter comparisons of full snapshots, pending events, emitted events and impact timers. Every source enemy/action, authored boundary/epsilon, dynamic properties, mixed 30/60/120Hz AI and combat ticks, JSON restore, all implemented/unknown predicate kinds, source order, cycle yield and the 12-transition guard."}
	FileAccess.open("res://reports/enemy-interrupt-precompile.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("ENEMY_INTERRUPT_PRECOMPILE ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func _pair(id: int, data: Variant = null) -> Array:
	var pair := [Combat.new(), Reference.new()]
	for actor in pair:
		check(actor.configure_enemy(id, 731, 0, data).success, "Enemy configures: %d" % id)
		actor.enemy_ai_enabled = true
	return pair

func _equal(pair: Array, label: String) -> void:
	check(pair[0].snapshot() == pair[1].snapshot(), "Snapshot differs: " + label)
	check(pair[0].impact_pause == pair[1].impact_pause and pair[0].stagger_remaining == pair[1].stagger_remaining and pair[0].action_step == pair[1].action_step and pair[0].action_tick_delta == pair[1].action_tick_delta, "Timers differ: " + label)
	var actual: Array = _normalized_events(pair[0])
	var expected: Array = _normalized_events(pair[1])
	check(actual == expected, "Events differ: " + label)

func _normalized_events(actor: DungeonCombat) -> Array:
	var result := actor.drain_events().duplicate(true)
	for event in result:
		if event.get("source") is DungeonCombat:
			check(is_same(event.source, actor), "Emitted event retains its own combat source")
			event.source = actor.actor_key
	return result

func _source_actions(enemy: Dictionary, actions: Array) -> void:
	var pair := _pair(int(enemy.id))
	for action in actions:
		if action.group != enemy.group: continue
		action_pairs += 1
		var probes: Array = [{"elapsed": 0.0}, {"elapsed": 1.0 / 120}, {"elapsed": 1.0 / 60}, {"elapsed": 1.0 / 30}, {"elapsed": float(action.duration)}]
		for command in action.events:
			if not command.get("enabled", false) or command.get("type", "") != "EET_Interrupt": continue
			var raw = Combat._read_raw_json(str(command.get("raw", "{}")))
			var requested := ""
			if raw is Dictionary:
				for condition in raw.get("Conditions", []):
					source_predicates[str(condition.get("InterruptType", ""))] = true
					if condition.get("InterruptType") == "EIT_CheckAI": requested = str(condition.get("CompareVal", ""))
			for offset in [-0.000002, -0.0000005, 0.0, 0.0000005]:
				probes.append({"elapsed": maxf(0, float(command.get("time", 0)) + offset), "request": requested})
			if float(command.get("duration", 0)) > 0:
				for offset in [-0.0000005, 0.0, 0.0000005]:
					probes.append({"elapsed": float(command.get("time", 0)) + float(command.duration) + offset, "request": requested})
		for index in probes.size():
			var probe: Dictionary = probes[index]
			for actor in pair:
				actor.clear_impact_state()
				actor.frozen = 0
				actor._start(action, 0)
				actor.health = 0 if index % 7 == 6 else actor.max_health
				actor.custom_properties["OP_AIAction"] = probe.get("request", ["idle", "run", "attack1"][index % 3])
				actor.custom_properties["AttackModeStr"] = "satk" if index % 3 == 0 else "normal"
				actor.custom_properties["InputAttack"] = index % 2 == 0
				actor.custom_properties["BB_HpChecker"] = index % 4
				actor.action_elapsed = float(probe.elapsed) / maxf(0.01, float(actor.custom_properties.get("_feel_action_speed", 1)))
				if index % 29 == 11: actor.frozen = 0.1
				if index % 29 == 12: actor.impact_pause = 0.1
				if index % 29 == 13: actor.stagger_remaining = 0.1
				actor._tick_enemy_interrupts()
			_equal(pair, "%d/%s/%d" % [int(enemy.id), action.id, index])

func _runtime(enemy: Dictionary) -> void:
	var pair := _pair(int(enemy.id))
	for frame in 240:
		var delta: float = [1.0 / 30, 1.0 / 60, 1.0 / 120][frame % 3]
		var context := {"target_available": frame % 43 < 37, "distance": [1.0, 3.5, 9.0][(frame / 20) % 3], "line_blocked": frame % 50 > 40, "battle_time": frame / 60.0, "monster_index": frame % 3, "target_buffs": []}
		var decisions: Array = []
		for actor in pair:
			actor.health = actor.max_health * (1.0 if frame < 120 else 0.25)
			actor.custom_properties["EnemyDistances"] = [context.distance]
			if frame == 35: actor.frozen = 0.05
			if frame == 65: actor.apply_hit_stop(0.04)
			if frame == 95: actor.apply_stagger(0.05)
			decisions.append(actor.tick_enemy_ai(delta, context))
			actor.tick(delta)
		check(decisions[0] == decisions[1], "AI decisions differ: %d/%d" % [int(enemy.id), frame])
		_equal(pair, "runtime %d/%d" % [int(enemy.id), frame])
		if frame in [79, 159]:
			for actor in pair:
				check(actor.restore(JSON.parse_string(JSON.stringify(actor.snapshot()))), "JSON snapshot restores: %d/%d" % [int(enemy.id), frame])
			_equal(pair, "restored %d/%d" % [int(enemy.id), frame])

func _predicate_cases() -> void:
	var actor := Combat.new()
	actor.configure_enemy(33002)
	var predicates: Array = [
		{}, {"InterruptType": "Unknown"}, {"InterruptType": "EIT_CheckHitAction"},
		{"InterruptType": "EIT_CheckCustomPropertyBool"}, {"InterruptType": "EIT_CheckCustomPropertyBool", "Property": "Flag", "CompareVal": true},
		{"InterruptType": "EIT_CheckCustomPropertyString", "Property": "Text", "CompareVal": "hello"}, {"InterruptType": "EIT_CheckCustomPropertyString", "Property": "AttackModeStr", "CompareVal": "satk"},
		{"InterruptType": "EIT_CheckCustomPropertyString", "Property": "Absent", "CompareVal": "<null>"},
		{"InterruptType": "EIT_CheckAttackMode", "ModeType": "Special"}, {"InterruptType": "EIT_CheckAttackMode"},
		{"InterruptType": "EIT_CheckDead"}, {"InterruptType": "EIT_CheckAI", "CompareVal": "run"},
		{"InterruptType": "EIT_CheckCustomPropertyInt", "Property": "Number", "MinVal": -1, "MaxVal": 2},
		{"InterruptType": "EIT_CheckCustomPropertyInt", "CustomProperty": "Other", "Property": "Number", "MinVal": 2, "MaxVal": 2},
		{"InterruptType": "EIT_CheckCustomPropertyInt", "CustomProperty": "", "Property": "Number"}
	]
	var raws: Array = [{}, {"CheckAllCondition": false}, {"Conditions": predicates}, {"Conditions": predicates, "CheckAllCondition": false}]
	for predicate in predicates:
		for all_required in [true, false]: raws.append({"Conditions": [predicate], "CheckAllCondition": all_required})
	for raw in raws:
		var compiled = actor._compile_enemy_interrupt({"raw": JSON.stringify(raw)})
		var command := _command("passed")
		command.raw = JSON.stringify(raw)
		var actions := [_action("entry", [command]), _action("passed", [])]
		var pair := _fixture(actions)
		for index in 36:
			actor._current_slot = 4 if index % 2 == 0 else 0
			actor.health = -1 if index % 3 == 0 else 1
			actor.custom_properties = {"Flag": index % 2 == 0, "Text": "hello" if index % 3 == 0 else "other", "Number": index % 6 - 2, "Other": 2, "OP_AIAction": "run" if index % 2 == 0 else "idle"}
			if index % 4 == 0: actor.custom_properties["AttackModeStr"] = "normal"
			if index % 5 == 0: actor.custom_properties["Flag"] = 1
			check(actor._compiled_enemy_interrupt_conditions(compiled) == actor._interrupt_conditions(raw), "Predicate/default/coercion differs: %s/%d" % [JSON.stringify(raw), index])
			for candidate in pair:
				candidate._start(actions[0], 0)
				candidate._current_slot = actor._current_slot
				candidate.health = actor.health
				candidate.custom_properties.erase("AttackModeStr")
				candidate.custom_properties.merge(actor.custom_properties, true)
				candidate._tick_enemy_interrupts()
			_equal(pair, "synthetic predicate %s/%d" % [JSON.stringify(raw), index])
	for raw in ["null", "[]", "123", "\"text\""]:
		check(not actor._compiled_enemy_interrupt_conditions(actor._compile_enemy_interrupt({"raw": raw})), "Non-dictionary payload remains rejected: " + raw)

func _action(id: String, commands: Array) -> Dictionary:
	return {"id": id, "key": "Fixture/" + id, "group": "Fixture", "speed": 1.0, "duration": 2.0, "hits": [], "events": commands}

func _command(target: String, time := 0.0, duration := 0.0) -> Dictionary:
	return {"enabled": true, "type": "EET_Interrupt", "time": time, "duration": duration, "target": target, "raw": "{}"}

func _fixture(actions: Array) -> Array:
	var data := {"actions": actions, "enemies": [{"id": 1, "group": "Fixture", "attack": 1, "hp": 100, "ai": "none"}], "buffs": [], "summons": []}
	var pair := _pair(1, data)
	for actor in pair:
		actor._start(actions[0], 0)
		actor.drain_events()
	return pair

func _transition_cases() -> void:
	var first := _command("first")
	first["all"] = false
	var pair := _fixture([_action("entry", [_command("missing"), first, _command("second")]), _action("first", []), _action("second", [])])
	for actor in pair: actor._tick_enemy_interrupts()
	_equal(pair, "Missing target skips; source order and empty any conditions remain true")
	check(pair[0].current_action == "first", "Source order chooses the first valid target")
	pair = _fixture([_action("A", [_command("B")]), _action("B", [_command("A")])])
	for actor in pair: actor._tick_enemy_interrupts()
	_equal(pair, "Cycle yields after the authored return transition")
	check(pair[0].current_action == "A" and pair[0]._cast_sequence == 3, "Cycle preserves both transitions once")
	var chain: Array = []
	for index in 14: chain.append(_action(str(index), [_command(str(index + 1))] if index < 13 else []))
	pair = _fixture(chain)
	for actor in pair: actor._tick_enemy_interrupts()
	_equal(pair, "12-transition guard")
	check(pair[0].current_action == "12" and pair[0].diagnostics.has("Enemy action transition budget exceeded: 1"), "Guard retains exactly twelve transitions and diagnostic")
	for elapsed in [0.999998, 0.9999995, 1.0, 1.25, 1.2500005]:
		pair = _fixture([_action("entry", [_command("done", 1.0, 0.25)]), _action("done", [])])
		for actor in pair:
			actor.action_elapsed = elapsed
			actor._tick_enemy_interrupts()
		_equal(pair, "Exact time/epsilon %.9f" % elapsed)
		check((pair[0].current_action == "done") == (elapsed + 0.000001 >= 1.0 and elapsed <= 1.25), "Authored boundary remains inclusive without extending the end")

func _reconfiguration() -> void:
	var actor := Combat.new()
	actor.configure_enemy(33002)
	actor.begin_enemy_spawn()
	check(not actor._enemy_timing_cache.is_empty(), "First action prepares immutable timing")
	actor.configure()
	check(actor._enemy_timing_cache.is_empty() and actor._enemy_interrupt_program.is_empty(), "Player reconfiguration clears enemy compiled state")
	actor.configure_enemy(52001)
	actor.begin_enemy_spawn()
	check(actor._enemy_interrupts == actor._action(str(actor.enemy.group), actor.current_action).events.filter(func(command): return command.get("enabled", false) and command.get("type", "") == "EET_Interrupt"), "Source interrupt dictionaries remain available after reconfiguration")
