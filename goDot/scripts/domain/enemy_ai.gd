class_name DungeonEnemyAI
extends RefCounted

# NodeCanvas task defaults are taken from the packaged constructors, not JSON omission.
const FAILURE := 0
const SUCCESS := 1
const RUNNING := 2
const RESTING := 3
const OPTIONAL := 5
const NUMERIC_EPSILON := 0.000000001
const NODE_TYPES := ["Parallel", "BinarySelector", "ActionNode", "ProbabilitySelector", "ConditionalEvaluator", "Filter", "Switch", "Selector", "Merge", "FlipSelector", "StepIterator", "WaitUntil", "Sequencer", "Repeater"]
const CONDITION_TYPES := ["ConditionList", "CheckString", "CheckNull", "CheckFloat", "CheckVectorDistance", "NCCondition_CheckTargetLineCollisionWall", "CheckInt", "CheckBoolean", "NCCondition_RoleUnit_CheckAttribute", "NCCondition_RoleUnit_CheckBuffExist"]
const TASK_TYPES := ["ActionList", "SetFloat", "SetInt", "SetVariable", "SetBoolean", "NCTask_RefreshMonsterIndex", "NCTask_AddBuffToUnit", "NCTask_RoleUnit_SetCustomPropertyFloat", "NCTask_MessageCenter_Send"]
const RUNTIME_TYPE := "__dungeon_ai_type"
const RUNTIME_PARAMETER_NAME := "__dungeon_ai_parameter_name"
const NATIVE_DESCRIPTOR := "res://addons/combat_ai/runtime/combat_ai.cfg"

static var _native_load_attempted := false

var blackboard: Dictionary = {}
var diagnostics: Array = []
var graph_name := ""
var source := ""
var trace_enabled := true
var needs_wall_query := false
var needs_target_buffs := false
var needs_self_buffs := false
var _nodes: Dictionary = {}
var _children: Dictionary = {}
var _variables: Dictionary = {}
var _states: Dictionary = {}
var _root := ""
var _random_state := 1
var _clock := 0.0
var _delta := 0.0
var _context: Dictionary = {}
var _properties: Dictionary = {}
var _buffs: Array = []
var _messages: Array = []
var _trace: Array = []
var _stack: Array = []
var _visited: Dictionary = {}
var _repeat := true
var _type_cache: Dictionary = {}
var _native_runner: RefCounted
var _native_timing: Dictionary = {}

func configure(definition: Dictionary, graph: Dictionary, seed_value: int = 1) -> bool:
	_native_runner = null
	needs_wall_query = false
	needs_target_buffs = false
	needs_self_buffs = false
	blackboard.clear()
	diagnostics.clear()
	_nodes.clear()
	_children.clear()
	_variables.clear()
	_states.clear()
	_root = ""
	_clock = 0.0
	_random_state = seed_value & 0xffffffff
	graph_name = str(definition.get("ai", ""))
	source = str(definition.get("ai_source", ""))
	_repeat = bool(graph.get("derivedData", {}).get("repeat", true))
	for name in graph.get("localBlackboard", {}).get("_variables", {}):
		var variable: Dictionary = graph.localBlackboard._variables[name]
		_variables[str(variable.get("_id", ""))] = str(name)
		blackboard[str(name)] = variable.get("_value", _default_variable(variable))
	for node in graph.get("nodes", []):
		# Serialized nodes without an id have no graph connections and are editor leftovers.
		if not node.has("$id"): continue
		var id = str(node["$id"])
		_nodes[id] = _prepare_node(node)
		_children[id] = []
		_states[id] = {"status": RESTING}
	var incoming: Dictionary = {}
	for edge in graph.get("connections", []):
		var parent = str(edge.get("_sourceNode", {}).get("$ref", ""))
		var child = str(edge.get("_targetNode", {}).get("$ref", ""))
		if not _nodes.has(parent) or not _nodes.has(child):
			_report("Dangling graph connection: %s -> %s" % [parent, child])
			continue
		_children[parent].append(child)
		incoming[child] = true
	for id in _nodes:
		if not incoming.has(id):
			_root = id
			break
	if _root.is_empty():
		_report("Missing behavior tree root")
		return false
	_audit(_root, {})
	_configure_native_runtime()
	return diagnostics.is_empty()

func _native_runtime_allowed() -> bool:
	return true

func backend_name() -> String:
	return "native" if _native_runner != null else "gdscript"

static func _native_platform_supported(platform: String, arm64: bool) -> bool:
	return arm64 and platform in ["Android", "macOS"]

static func _load_native_runtime() -> bool:
	if not _native_platform_supported(OS.get_name(), OS.has_feature("arm64")): return false
	if ClassDB.class_exists("CombatAIProbe"): return true
	if _native_load_attempted: return false
	_native_load_attempted = true
	if not FileAccess.file_exists(NATIVE_DESCRIPTOR): return false
	# Android libraries live in the APK's native library directory after export.
	if OS.has_feature("macos"):
		var configuration := "debug" if OS.has_feature("debug") else "release"
		var library_name := "libcombat_ai.macos.%s.arm64.dylib" % configuration
		var framework_path := OS.get_executable_path().get_base_dir().path_join("../Frameworks").path_join(library_name)
		if not FileAccess.file_exists(NATIVE_DESCRIPTOR.get_base_dir().path_join(library_name)) and not FileAccess.file_exists(framework_path): return false
	var status := GDExtensionManager.load_extension(NATIVE_DESCRIPTOR)
	return status in [GDExtensionManager.LOAD_STATUS_OK, GDExtensionManager.LOAD_STATUS_ALREADY_LOADED] and ClassDB.class_exists("CombatAIProbe")

func _configure_native_runtime() -> void:
	if not _native_runtime_allowed() or not _load_native_runtime(): return
	var runner = ClassDB.instantiate("CombatAIProbe")
	_native_timing = {"clock": _clock, "random_state": _random_state}
	if runner.configure({"nodes": _nodes, "children": _children, "states": _states, "blackboard": blackboard, "variables": _variables, "diagnostics": diagnostics, "root": _root, "repeat": _repeat, "timing": _native_timing}):
		_native_runner = runner

func _prepare_node(node: Dictionary) -> Dictionary:
	# Keep P1 requests out of the flower's P2 entrance and re-arm its EX stun.
	# These narrow runtime repairs leave the packaged graph unchanged.
	if graph_name == "EnemyAIBT_MoJieHua":
		var compatibility: Array = {"1": ["P2Attack", "roar"], "30": ["Dizziness", "Dizziness_EX"]}.get(str(node.get("$id", "")), [])
		var condition: Dictionary = node.get("_condition", {})
		if compatibility.size() == 2 and _type(condition) == "CheckString" and condition.get("valueA", {}).get("_name", "") == "IP_CurAction" and condition.get("valueB", {}).get("_value", "") == compatibility[0]:
			var compatible = node.duplicate(true)
			var alternate = condition.duplicate(true)
			alternate.valueB = {"_value": compatibility[1]}
			compatible._condition = {"$type": "NodeCanvas.Framework.ConditionList", "checkMode": 1, "conditions": [condition, alternate]}
			return _prepare_value(compatible)
	return _prepare_value(node)

func _prepare_value(value: Variant) -> Variant:
	if value is Array:
		var result: Array = []
		for item in value: result.append(_prepare_value(item))
		return result
	if not value is Dictionary: return value
	var result: Dictionary = {}
	for key in value:
		# Parameter values remain the original data; only serialized bindings compile.
		result[key] = value[key] if key == "_value" else _prepare_value(value[key])
	if value.has("$type"):
		var type := _type(value)
		result[RUNTIME_TYPE] = type
		if type == "NCCondition_CheckTargetLineCollisionWall": needs_wall_query = true
		if type == "NCCondition_RoleUnit_CheckBuffExist":
			if _name(value.get("SelfGo", {})) == "IP_Target": needs_target_buffs = true
			else: needs_self_buffs = true
	if value.has("_targetVariableID") or value.has("_name") or value.has("_value"):
		result[RUNTIME_PARAMETER_NAME] = _name(value)
	return result

func notify_action_started(action_name: String) -> void:
	blackboard["IP_ActionBeforeChanged"] = blackboard.get("IP_CurAction", "")
	blackboard["IP_ActionAfterChanged"] = action_name
	blackboard["IP_CurActionStarted"] = action_name
	blackboard["IP_CurAction"] = action_name
	blackboard["IP_ActionEnterTrigger"] = true

func notify_action_ended(action_name: String) -> void:
	blackboard["IP_CurActionEnded"] = action_name

func tick(delta: float, context: Dictionary = {}) -> Dictionary:
	if _native_runner != null:
		var result: Dictionary = _native_runner.tick(delta, context, trace_enabled)
		_clock = float(_native_timing.clock)
		_random_state = int(_native_timing.random_state)
		return result
	_properties = {}
	_buffs = []
	_messages = []
	if trace_enabled or not _trace.is_empty(): _trace = []
	_stack = []
	if trace_enabled or not _visited.is_empty(): _visited = {}
	if _root.is_empty() or not is_finite(delta) or delta < 0:
		return _result(FAILURE)
	_delta = delta
	_clock += delta
	_context = context
	blackboard["IP_SelfObj"] = true
	blackboard["IP_Target"] = true if bool(context.get("target_available", false)) else null
	blackboard["IP_MoveSpeed"] = float(context.get("move_speed", 0.0))
	blackboard["IP_BattleClipTimer"] = float(context.get("battle_time", _clock))
	# AIStatus_BT refreshes this role runtime attribute every update.
	if context.has("attack_cooldown") and blackboard.has("BB_AttackCD"):
		blackboard["BB_AttackCD"] = float(context.attack_cooldown)
	if context.has("current_action"):
		blackboard["IP_CurAction"] = str(context.current_action)
	if context.has("blackboard"):
		for name in context.blackboard:
			if blackboard.has(name): blackboard[name] = context.blackboard[name]
	if _repeat and int(_states[_root].status) not in [RESTING, RUNNING]:
		_reset_node(_root, {})
	var status = _tick_node(_root)
	return _result(status)

func snapshot() -> Dictionary:
	return {"schema": 1, "graph": graph_name, "clock": _clock, "random_state": _random_state, "blackboard": blackboard.duplicate(true), "states": _states.duplicate(true)}

func restore(value: Dictionary) -> bool:
	if value.get("graph", "") != graph_name or int(value.get("schema", 0)) != 1: return false
	_clock = maxf(0.0, float(value.get("clock", 0.0)))
	_random_state = int(value.get("random_state", 1)) & 0xffffffff
	for name in value.get("blackboard", {}):
		if blackboard.has(name) or str(name).begins_with("IP_"): blackboard[name] = value.blackboard[name]
	for id in value.get("states", {}):
		if _nodes.has(id) and value.states[id] is Dictionary:
			_states[id] = value.states[id].duplicate(true)
			if _states[id].has("failed"):
				_states[id].failed = _states[id].failed.map(func(index): return int(index))
	if _native_runner != null: _native_runner.sync_timing(_clock, _random_state)
	return true

func _result(status: int) -> Dictionary:
	return {"action": str(blackboard.get("OP_AIAction", "")), "properties": _properties, "buffs": _buffs, "messages": _messages, "status": status, "trace": _trace, "visited": _visited.keys()}

func _tick_node(id: String) -> int:
	if _stack.has(id) or _stack.size() > 128:
		_report("Behavior tree cycle at " + id)
		return FAILURE
	if not _nodes.has(id): return FAILURE
	var state: Dictionary = _states[id]
	var status = int(state.get("status", RESTING))
	if status not in [RESTING, RUNNING]: return status
	_stack.append(id)
	if trace_enabled: _visited[id] = true
	status = _execute_node(id, _nodes[id], state, _children[id])
	_states[id].status = status
	_stack.pop_back()
	return status

func _execute_node(id: String, node: Dictionary, state: Dictionary, children: Array) -> int:
	var type = _type(node)
	match type:
		"ActionNode":
			return _task(node.get("_action", {}), id)
		"BinarySelector":
			if children.size() < 2: return OPTIONAL
			if not state.has("selection") or bool(node.get("dynamic", false)):
				var selection = 0 if _condition(node.get("_condition", {})) else 1
				if state.has("selection") and int(state.selection) != selection: _reset_node(str(children[int(state.selection)]), {})
				state.selection = selection
			return _tick_node(str(children[int(state.selection)]))
		"ConditionalEvaluator":
			if children.is_empty(): return OPTIONAL
			if not state.has("condition") or bool(node.get("dynamic", false)):
				state.condition = _condition(node.get("_condition", {}))
			if not bool(state.condition):
				if bool(node.get("dynamic", false)): _reset_node(str(children[0]), {})
				return int(node.get("falseReturnStatus", FAILURE))
			return _tick_node(str(children[0]))
		"Merge":
			return _tick_node(str(children[0])) if not children.is_empty() else OPTIONAL
		"WaitUntil":
			if not bool(state.get("condition", false)): state.condition = _condition(node.get("_condition", {}))
			if not bool(state.condition): return RUNNING
			return _tick_node(str(children[0])) if not children.is_empty() else SUCCESS
		"Filter":
			if children.is_empty(): return OPTIONAL
			var mode = int(node.get("filterMode", 1))
			# Decimal JSON roundoff must not shift a cooldown by a whole frame.
			var limited = int(state.get("count", 0)) >= int(_value(node.get("maxCount", {}), 1)) if mode == 0 else _clock + NUMERIC_EPSILON < float(state.get("ready_at", 0.0))
			if limited: return OPTIONAL if bool(node.get("inactiveWhenLimited", true)) else FAILURE
			var result = _tick_node(str(children[0]))
			if result in [SUCCESS, FAILURE]:
				if mode == 1:
					state.ready_at = _clock + maxf(0.0, float(_value(node.get("coolDownTime", {}), 5.0)))
				elif int(node.get("policy", 0)) == 0 or (int(node.get("policy", 0)) == 1 and result == SUCCESS) or (int(node.get("policy", 0)) == 2 and result == FAILURE):
					state.count = int(state.get("count", 0)) + 1
			return result
		"Switch":
			if children.is_empty(): return FAILURE
			if not state.has("selection") or bool(node.get("dynamic", false)):
				var selection = int(_value(node.get("intCase", {})))
				if int(node.get("outOfRangeMode", 1)) == 1: selection = posmod(selection, children.size())
				if selection < 0 or selection >= children.size(): return FAILURE
				if state.has("selection") and int(state.selection) != selection: _reset_node(str(children[int(state.selection)]), {})
				state.selection = selection
			return _tick_node(str(children[int(state.selection)]))
		"StepIterator":
			return _tick_node(str(children[posmod(int(state.get("step", 0)), children.size())])) if not children.is_empty() else OPTIONAL
		"ProbabilitySelector":
			return _probability(node, state, children)
		"Selector", "FlipSelector", "Sequencer":
			var order: Array = state.order if state.has("order") else children.duplicate()
			if not state.has("order"): state.order = order
			var start = 0 if bool(node.get("dynamic", false)) else int(state.get("cursor", 0))
			for index in range(start, order.size()):
				var result = _tick_node(str(order[index]))
				if result == RUNNING:
					if state.has("cursor") and int(state.cursor) != index: _reset_node(str(order[int(state.cursor)]), {})
					state.cursor = index
					return RUNNING
				if type == "Sequencer" and result == FAILURE: return FAILURE
				if type != "Sequencer" and result == SUCCESS:
					if type == "FlipSelector":
						var successful = order.pop_at(index)
						order.append(successful)
					return SUCCESS
			return SUCCESS if type == "Sequencer" else FAILURE
		"Parallel":
			var result = RESTING
			var completed = 0
			var policy = int(node.get("policy", 0))
			for child in children:
				var child_id = str(child)
				if bool(node.get("dynamic", false)) and int(_states[child_id].get("status", RESTING)) not in [RESTING, RUNNING]: _reset_node(child_id, {})
				var status = _tick_node(child_id)
				if status != RUNNING: completed += 1
				if result == RESTING and ((status == FAILURE and policy in [0, 2]) or (status == SUCCESS and policy in [1, 2])): result = status
			if result != RESTING:
				for child in children:
					if int(_states[str(child)].get("status", RESTING)) == RUNNING: _reset_node(str(child), {})
				return result
			if completed == children.size(): return FAILURE if policy == 1 else SUCCESS if policy == 0 else RUNNING
			return RUNNING
		"Repeater":
			if children.is_empty(): return OPTIONAL
			var child_id = str(children[0])
			if int(_states[child_id].get("status", RESTING)) not in [RESTING, RUNNING]: _reset_node(child_id, {})
			var status = _tick_node(child_id)
			if status == RUNNING: return RUNNING
			state.iterations = int(state.get("iterations", 0)) + 1
			var mode = int(node.get("repeaterMode", 0))
			if mode == 0 and int(state.iterations) >= int(_value(node.get("repeatTimes", {}), 1)): return status
			if mode == 1 and status == int(node.get("repeatUntilStatus", 0)): return status
			return RUNNING
	_report("Unsupported node " + type)
	return FAILURE

func _probability(node: Dictionary, state: Dictionary, children: Array) -> int:
	if not state.has("weights"):
		state.weights = []
		state.failed = []
		state.dice = _random()
		state.fail_weight = maxf(0.0, float(_value(node.get("failChance", {}))))
		state.total = state.fail_weight
		for index in children.size():
			var weight = maxf(0.0, float(_value(node.get("childWeights", [])[index])))
			state.weights.append(weight)
			state.total += weight
	var total = float(state.total)
	if total <= 0: return FAILURE
	var cumulative = float(state.fail_weight) / total
	if float(state.dice) < cumulative: return FAILURE
	for index in children.size():
		if state.failed.has(index): continue
		cumulative += float(state.weights[index]) / total
		if float(state.dice) > cumulative: continue
		var result = _tick_node(str(children[index]))
		if result in [SUCCESS, RUNNING]: return result
		if result == FAILURE:
			state.failed.append(index)
			state.total = total - float(state.weights[index])
			return RUNNING
		# Optional cooldown children fall through in source connection order.
	return FAILURE

func _condition(condition: Dictionary) -> bool:
	var type = _type(condition)
	var result := false
	match type:
		"ConditionList":
			var any = int(condition.get("checkMode", 0)) == 1
			result = not any
			for item in condition.get("conditions", []):
				var passed = _condition(item)
				if any and passed: result = true; break
				if not any and not passed: result = false; break
		"CheckString": result = str(_value(condition.get("valueA", {}), "")) == str(_value(condition.get("valueB", {}), ""))
		"CheckBoolean": result = bool(_value(condition.get("valueA", {}), false)) == bool(_value(condition.get("valueB", {}), false))
		"CheckNull": result = _value(condition.get("variable", {}), null) == null
		"CheckFloat", "CheckInt":
			var threshold = float(condition.get("differenceThreshold", 0.05)) if type == "CheckFloat" else 0.0
			result = _compare(float(_value(condition.get("valueA", {}))), float(_value(condition.get("valueB", {}))), int(condition.get("checkType", 0)), threshold)
		"CheckVectorDistance": result = bool(_context.get("target_available", false)) and _compare(float(_context.get("distance", INF)), float(_value(condition.get("distance", {}))), int(condition.get("comparison", 0)))
		"NCCondition_CheckTargetLineCollisionWall": result = bool(_context.get("line_blocked", false))
		"NCCondition_RoleUnit_CheckAttribute":
			if int(condition.get("CheckAttribute", 0)) == 3:
				result = _compare(float(_context.get("hp_ratio", 1.0)) * 1000.0, float(_value(condition.get("CheckVale", {}))), int(condition.get("CheckType", 0)))
		"NCCondition_RoleUnit_CheckBuffExist":
			var target = _name(condition.get("SelfGo", {})) == "IP_Target"
			var buffs = _context.get("target_buffs" if target else "self_buffs", [])
			var buff_id = str(_value(condition.get("CheckBuffId", {}), ""))
			result = buffs.has(buff_id)
		_: _report("Unsupported condition " + type)
	return not result if bool(condition.get("_invert", false)) else result

func _task(task: Dictionary, node_id: String) -> int:
	if bool(task.get("_isDisabled", false)): return SUCCESS
	var type = _type(task)
	match type:
		"ActionList":
			for action in task.get("actions", []):
				var status = _task(action, node_id)
				if status == FAILURE: return FAILURE
		"SetVariable": _assign(task.get("valueA", {}), _value(task.get("valueB", {}), _typed_default(str(task.get("$type", "")))), node_id)
		"SetFloat", "SetInt":
			var target: Dictionary = task.get("valueA", {})
			var a = float(_value(target))
			var b = float(_value(task.get("valueB", {})))
			if bool(task.get("perSecond", false)): b *= _delta
			match int(task.get("Operation", 0)):
				0: a = b
				1: a += b
				2: a -= b
				3: a *= b
				4: a = a / b if not is_zero_approx(b) else a
			_assign(target, int(a) if type == "SetInt" else a, node_id)
		"SetBoolean":
			var target: Dictionary = task.get("boolVariable", {})
			var mode = int(task.get("setTo", 1))
			_assign(target, not bool(_value(target, false)) if mode == 2 else mode == 1, node_id)
		"NCTask_RefreshMonsterIndex":
			var index = int(_context.get("alive_monster_count", 0)) if int(task.get("mode", 0)) == 1 else int(_context.get("monster_index", 0))
			_assign(task.get("MonsterIndex", {}), index, node_id)
		"NCTask_AddBuffToUnit":
			var buff_id = str(_value(task.get("BuffId", {}), ""))
			if not buff_id.is_empty() and not _buffs.has(buff_id): _buffs.append(buff_id)
		"NCTask_RoleUnit_SetCustomPropertyFloat": _properties[str(_value(task.get("PropertyName", {}), ""))] = float(_value(task.get("PropertyValue", {})))
		"NCTask_MessageCenter_Send":
			var message = {"name": str(_value(task.get("MessageName", {}), "")), "parameters": {}}
			for index in range(1, 4):
				var name = str(_value(task.get("MessageParams%sName" % index, {}), ""))
				if not name.is_empty(): message.parameters[name] = _value(task.get("MessageParams%sValue" % index, {}), "")
			_messages.append(message)
		_: _report("Unsupported task " + type); return FAILURE
	return SUCCESS

func _assign(parameter: Dictionary, value: Variant, node_id: String) -> void:
	var name = _name(parameter)
	if name.is_empty(): return
	blackboard[name] = value
	if trace_enabled: _trace.append({"node": node_id, "variable": name, "value": value})

func _value(parameter: Dictionary, fallback: Variant = 0.0) -> Variant:
	var name = _name(parameter)
	if not name.is_empty(): return blackboard.get(name, fallback)
	return parameter.get("_value", fallback)

func _name(parameter: Dictionary) -> String:
	if parameter.has(RUNTIME_PARAMETER_NAME): return parameter[RUNTIME_PARAMETER_NAME]
	return str(_variables.get(str(parameter.get("_targetVariableID", "")), parameter.get("_name", "")))

func _default_variable(variable: Dictionary) -> Variant:
	var type = str(variable.get("$type", ""))
	if type.contains("GameObject") or type.contains("Transform"): return null
	return _typed_default(type)

func _typed_default(type: String) -> Variant:
	if type.contains("System.Boolean"): return false
	if type.contains("System.String"): return ""
	if type.contains("System.Int32"): return 0
	return 0.0

func _compare(a: float, b: float, method: int, threshold := 0.0) -> bool:
	match method:
		0: return absf(a - b) <= threshold
		1: return a - b > NUMERIC_EPSILON
		2: return b - a > NUMERIC_EPSILON
		3: return a - b >= -NUMERIC_EPSILON
		4: return b - a >= -NUMERIC_EPSILON
	return false

func _reset_node(id: String, visited: Dictionary) -> void:
	if visited.has(id) or not _states.has(id): return
	visited[id] = true
	var state: Dictionary = _states[id]
	if int(state.get("status", RESTING)) == RESTING: return
	var type = _type(_nodes[id])
	var retained: Dictionary = {"status": RESTING}
	if type == "Filter":
		retained.count = state.get("count", 0)
		retained.ready_at = state.get("ready_at", 0.0)
	elif type == "StepIterator": retained.step = int(state.get("step", 0)) + 1
	elif type == "FlipSelector" and state.has("order"): retained.order = state.order
	_states[id] = retained
	for child in _children[id]: _reset_node(str(child), visited)

func _audit(id: String, seen: Dictionary) -> void:
	if seen.has(id): return
	seen[id] = true
	if not NODE_TYPES.has(_type(_nodes[id])): _report("Unsupported node " + _type(_nodes[id]))
	_audit_tasks(_nodes[id].get("_condition", {}), CONDITION_TYPES)
	_audit_tasks(_nodes[id].get("_action", {}), TASK_TYPES)
	for child in _children[id]: _audit(str(child), seen)

func _audit_tasks(value: Dictionary, supported: Array) -> void:
	if value.is_empty(): return
	if not supported.has(_type(value)): _report("Unsupported task " + _type(value))
	for field in ["conditions", "actions"]:
		for item in value.get(field, []): _audit_tasks(item, supported)

func _random() -> float:
	_random_state = (1664525 * _random_state + 1013904223) & 0xffffffff
	return float(_random_state) / 4294967296.0

func _type(value: Dictionary) -> String:
	if value.has(RUNTIME_TYPE): return value[RUNTIME_TYPE]
	var encoded := str(value.get("$type", ""))
	if _type_cache.has(encoded): return _type_cache[encoded]
	var qualified := encoded.get_slice("`", 0)
	var result := qualified.get_slice(".", qualified.count("."))
	if _type_cache.size() >= 128: _type_cache.clear()
	_type_cache[encoded] = result
	return result

func _report(message: String) -> void:
	if not diagnostics.has(message): diagnostics.append(message)
