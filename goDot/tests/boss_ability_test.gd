extends SceneTree

const Combat = preload("res://scripts/domain/combat.gd")
const STEP := 1.0 / 60.0
const EX_BUFFS := ["45400001", "45400002", "45400003", "45400004", "45400005", "45400006", "45400010"]

class ScriptOnlyAI extends DungeonEnemyAI:
	func _native_runtime_allowed() -> bool:
		return false

var checks := 0
var failures: Array[String] = []
var actions: Array = []
var flower_phases: Array = []
var replay_samples: Array = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var fixture = Combat.new()
	fixture.configure()
	var bosses: Array = fixture.catalog.enemies.filter(func(enemy): return enemy.get("rank") == "Boss")
	_compatibility_scope(fixture)
	for enemy in bosses:
		for action in fixture.catalog.actions:
			if action.group != enemy.group: continue
			for enhanced in [false, true]: _action_case(enemy, action, enhanced)
	for enhanced in [false, true]:
		for hz in [30, 60, 120]:
			for script_only in [false, true]: _flower_phase(enhanced, hz, script_only)
	_check(bosses.size() == 10, "All ten packaged Boss definitions are audited")
	var report = {"passed": failures.is_empty(), "checks": checks, "failures": failures, "bosses": bosses.size(), "action_cases": actions, "flower_phases": flower_phases, "scope": "Every imported action in all ten Boss groups runs its own uninterrupted timeline in normal and cumulative EX modes, with all emitted payloads validated and a JSON checkpoint replay. The action matrix deliberately isolates timelines from AI cancellation; real spawn/AI/receive-damage flower phase tests cover first P1, P2, normal/EX tentacle message thresholds and recovery at 30/60/120Hz. This executes the Godot reconstruction, not the original APK, rendered effects or device runtime."}
	FileAccess.open("res://reports/boss-ability-test.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("BOSS_ABILITY ", JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failure_count": failures.size(), "failures": failures.slice(0, 12), "replay_samples": replay_samples, "bosses": bosses.size(), "action_cases": actions.size(), "flower_phases": flower_phases.size()}))
	quit(0 if failures.is_empty() else 1)

func _enemy(id: int, enhanced: bool, script_only := false) -> DungeonCombat:
	var unit = Combat.new()
	_check(unit.configure_enemy(id, 731, 9 if enhanced else 0).success, "%s configures" % id)
	if script_only:
		unit.enemy_ai = ScriptOnlyAI.new()
		unit.enemy_ai.trace_enabled = false
		_check(unit.enemy_ai.configure(unit.enemy, unit.catalog.ai_graphs[unit.enemy.ai], 731), "Script AI backend configures")
	unit.custom_properties["EnemyDistances"] = [2.0]
	if enhanced:
		for buff in EX_BUFFS: unit.add_buff(buff)
	return unit

func _action_case(enemy: Dictionary, action: Dictionary, enhanced: bool) -> void:
	var unit = _enemy(int(enemy.id), enhanced)
	unit.enemy_ai_enabled = true
	unit._start(action, 0)
	var ledger := {"commands": {}, "hits": 0, "summons": {}, "damage_ids": {}, "buffs": {}, "events": []}
	_collect(unit, ledger)
	var elapsed := 0.0
	var replay: DungeonCombat = null
	var duration = float(action.duration) / maxf(0.01, float(action.get("speed", 1)))
	var replayed := false
	while unit.action_elapsed * float(action.get("speed", 1)) <= float(action.duration) + 0.05 and elapsed < 90.0 and unit.health > 0:
		unit.tick(STEP)
		var observed = _collect(unit, ledger)
		if replay != null:
			replay.tick(STEP)
			var replay_events = _event_signature(replay.drain_events())
			if observed != replay_events and replay_samples.size() < 2: replay_samples.append({"enemy": enemy.id, "action": action.id, "time": elapsed, "original": observed, "replay": replay_events})
			_check(observed == replay_events, "%s %s EX=%s checkpoint event replay at %.3f" % [enemy.id, action.id, enhanced, elapsed])
		elif elapsed >= duration * 0.5:
			replay = _enemy(int(enemy.id), enhanced)
			_check(replay.restore(JSON.parse_string(JSON.stringify(unit.snapshot()))), "%s %s EX=%s restores checkpoint" % [enemy.id, action.id, enhanced])
			replay.drain_events()
			replayed = true
		elapsed += STEP
	_check(elapsed < 90.0, "%s %s finishes authored clock" % [enemy.id, action.id])
	_check(replayed, "%s %s reaches midpoint checkpoint" % [enemy.id, action.id])
	var unsupported = unit.diagnostics.filter(func(message): return not str(message).begins_with("Summon behavior requires world adapter:"))
	_check(unsupported.is_empty(), "%s %s EX=%s has no unsupported domain operations: %s" % [enemy.id, action.id, enhanced, unsupported])
	for command in action.events:
		if not command.enabled or command.type == "EET_Interrupt" or not command.conditions.is_empty(): continue
		if float(command.time) > float(action.duration): continue
		_check(int(ledger.commands.get(_command_key(command), 0)) > 0, "%s %s EX=%s executes authored %s at %s" % [enemy.id, action.id, enhanced, command.type, command.time])
	actions.append({"enemy": enemy.id, "action": action.id, "enhanced": enhanced, "timeline_seconds": elapsed, "commands": ledger.commands.size(), "hit_payloads": ledger.hits, "summons": ledger.summons.keys(), "damage_ids": ledger.damage_ids.keys(), "buffs": ledger.buffs.keys(), "diagnostics": unit.diagnostics.duplicate()})

func _command_key(command: Dictionary) -> String:
	return "%s@%s:%s" % [command.type, command.time, command.raw]

func _collect(unit: DungeonCombat, ledger: Dictionary) -> Array:
	var events = unit.drain_events()
	for event in events:
		match str(event.type):
			"command":
				var command: Dictionary = event.command
				var key = _command_key(command)
				ledger.commands[key] = int(ledger.commands.get(key, 0)) + 1
				if command.type == "EET_AddBuff": ledger.buffs[str(command.buff)] = true
			"hit":
				ledger.hits += 1
				var id = int(event.definition.get("damageId", 0))
				if id > 0:
					ledger.damage_ids[str(id)] = true
					_check(not unit._damage_data(id).is_empty(), "%s has recovered damage %s" % [unit.enemy_id, id])
				_check(is_finite(float(event.damage)) and float(event.damage) >= 0.0, "%s payload damage is finite and nonnegative" % unit.enemy_id)
			"summon": ledger.summons[str(event.id)] = true
	return _event_signature(events)

func _event_signature(events: Array) -> Array:
	var result: Array = []
	for event in events:
		var value = {"type": event.type, "action": event.get("action", ""), "sequence": int(event.get("sequence", -1))}
		match str(event.type):
			"command": value.command = _command_key(event.command)
			"hit":
				value.damage = snappedf(float(event.damage), 0.000001)
				value.damage_id = int(event.definition.get("damageId", 0))
				value.index = int(event.get("emit_index", 0))
			"summon": value.id = event.id
		result.append(value)
	return result

func _step_ai(unit: DungeonCombat, ledger: Dictionary, delta: float) -> void:
	unit.tick_enemy_ai(delta, {"target_available": true, "distance": 2.0, "line_blocked": false, "battle_time": unit._clock, "monster_index": 0, "target_buffs": []})
	unit.tick(delta)
	for event in unit.drain_events():
		if event.type == "action_started":
			ledger.actions.append(str(event.action))
			ledger.transitions.append({"time": unit._clock, "action": event.action, "op": unit.custom_properties.get("OP_AIAction", ""), "stacks": unit.buff_layers("13000202"), "p2_reduction": unit.statuses.has("13000212")})
		if event.type == "spawn_monster": ledger.spawns.append(event.definition)

func _advance_until(unit: DungeonCombat, ledger: Dictionary, delta: float, seconds: float, predicate: Callable) -> bool:
	for frame in int(ceil(seconds / delta)):
		if predicate.call(): return true
		_step_ai(unit, ledger, delta)
	return bool(predicate.call())

func _flower_phase(enhanced: bool, hz: int, script_only: bool) -> void:
	var unit = _enemy(13002, enhanced, script_only)
	var ledger := {"actions": [], "spawns": [], "transitions": []}
	_check(unit.begin_enemy_spawn(), "Flower real spawn starts EX=%s %sHz" % [enhanced, hz])
	var delta = 1.0 / hz
	var installed = _advance_until(unit, ledger, delta, 8.0, func(): return unit.statuses.has("13000210"))
	_check(installed, "Flower first P1 installs authored damage observer EX=%s %sHz" % [enhanced, hz])
	if not installed:
		flower_phases.append({"enhanced": enhanced, "hz": hz, "observer_installed": false, "actions": ledger.actions})
		return
	var cycles: Array = []
	for cycle in 2:
		_advance_until(unit, ledger, delta, 15.0, func(): return unit.current_action in ["attack", "attack2", "attack3", "Attack_EX1"])
		var before = unit.health
		for strike in 20:
			if before - unit.health >= unit.max_health * 0.34: break
			unit.receive({"damage": unit.max_health * 0.1, "attack_collision": false, "definition": {}}, unit.attack)
		_check(before - unit.health >= unit.max_health * 0.33, "Flower receives real cumulative damage above authored 33 percent threshold")
		var spawn_before = ledger.spawns.size()
		var phase = _advance_until(unit, ledger, delta, 20.0, func(): return unit.statuses.has("13000212") and unit.buff_layers("13000202") == 1)
		_check(phase and ledger.actions.has("roar"), "Flower reaches P2 through actual damage cycle=%s EX=%s %sHz" % [cycle + 1, enhanced, hz])
		_check(ledger.spawns.size() > spawn_before, "Flower each roar emits authored tentacle generation")
		if not phase: break
		var required = 4 if enhanced else 3
		for index in required - 1:
			unit.notify_gameplay("message", {"name": "MojiehuaTentacleDead"})
			_step_ai(unit, ledger, delta)
		_check(unit.buff_layers("13000202") == required, "Flower preserves one initial stack and each nonfinal tentacle death")
		_check(not unit.statuses.has("13000219" if enhanced else "13000205"), "Flower does not stun before authored tentacle threshold")
		unit.notify_gameplay("message", {"name": "MojiehuaTentacleDead"})
		var stunned_action = "Dizziness_EX" if enhanced else "Dizziness"
		var stunned = _advance_until(unit, ledger, delta, 10.0, func(): return unit.current_action == stunned_action)
		_check(stunned, "Flower enters %s after %s tentacle messages cycle=%s at %sHz" % [stunned_action, required, cycle + 1, hz])
		_step_ai(unit, ledger, delta)
		_check(not unit.statuses.has("13000212"), "Flower removes P2 reduction on authored stun")
		var recovered = _advance_until(unit, ledger, delta, 15.0, func(): return (cycle == 1 or unit.statuses.has("13000210")) and unit.current_action != stunned_action)
		_check(recovered, "Flower leaves stun and re-arms P1 observer above one third HP cycle=%s EX=%s %sHz" % [cycle + 1, enhanced, hz])
		cycles.append({"cycle": cycle + 1, "phase_reached": phase, "stunned": stunned, "recovered": recovered, "tentacle_messages": required})
	_check(unit.diagnostics.is_empty() and unit.enemy_ai.diagnostics.is_empty(), "Flower complete phase has no unsupported operations")
	_check(cycles.size() == 2, "Flower completes both phase cycles")
	flower_phases.append({"enhanced": enhanced, "hz": hz, "backend": unit.enemy_ai.backend_name(), "observer_installed": installed, "cycles": cycles, "generation_commands": ledger.spawns.size(), "actions": ledger.actions, "transitions": ledger.transitions})

func _compatibility_scope(fixture: DungeonCombat) -> void:
	var unit = _enemy(13002, false)
	var graph: Dictionary = fixture.catalog.ai_graphs.EnemyAIBT_MoJieHua
	var source: Dictionary = graph.nodes.filter(func(node): return str(node.get("$id", "")) == "30")[0]
	_check(source._condition.valueB._value == "Dizziness", "Packaged flower graph remains unchanged")
	_check(unit.enemy_ai._type(unit.enemy_ai._nodes["30"]._condition) == "ConditionList", "Flower reset compiles its narrow normal/EX compatibility predicate")
	var p2_source: Dictionary = graph.nodes.filter(func(node): return str(node.get("$id", "")) == "1")[0]
	_check(p2_source._condition.valueB._value == "P2Attack", "Packaged P2 entrance predicate remains unchanged")
	_check(unit.enemy_ai._type(unit.enemy_ai._nodes["1"]._condition) == "ConditionList", "Flower P2 entry suppresses stale P1 requests during roar")
	_check(unit.enemy_ai._type(unit.enemy_ai._nodes["2"]._condition) == "CheckString", "Flower P2 command still requires actual P2Attack")
	var other_node = source.duplicate(true)
	other_node["$id"] = "31"
	_check(unit.enemy_ai._type(unit.enemy_ai._prepare_node(other_node)._condition) == "CheckString", "Compatibility cannot change another node")
	unit.enemy_ai.graph_name = "EnemyAIBT_JianChihu"
	_check(unit.enemy_ai._type(unit.enemy_ai._prepare_node(source)._condition) == "CheckString", "Compatibility cannot change another graph")

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)
