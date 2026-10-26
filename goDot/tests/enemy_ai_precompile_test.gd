extends SceneTree

class RawAI extends DungeonEnemyAI:
	func _native_runtime_allowed() -> bool:
		return false

	func _prepare_node(node: Dictionary) -> Dictionary:
		return node

var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok and failures.size() < 100: failures.append(message)

func _initialize() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/combat.json"))
	var seen: Dictionary = {}
	for definition in catalog.enemies:
		var name := str(definition.get("ai", ""))
		if seen.has(name) or not catalog.ai_graphs.has(name): continue
		seen[name] = true
		var graph: Dictionary = catalog.ai_graphs[name]
		var unchanged := graph.duplicate(true)
		var expected := RawAI.new()
		var actual := DungeonEnemyAI.new()
		check(expected.configure(definition, graph, 731), "Raw graph loads: " + name)
		check(actual.configure(definition, graph, 731), "Compiled graph loads: " + name)
		for frame in 600:
			var context := {"target_available": frame % 113 < 100, "distance": [1.0, 3.5, 8.0][(frame / 40) % 3], "line_blocked": frame % 90 > 60, "hp_ratio": 1.0 - frame / 650.0, "move_speed": 5.0, "attack_cooldown": 3.0, "self_buffs": ["10001"] if frame % 80 < 40 else [], "target_buffs": ["10001"] if frame % 100 < 50 else [], "battle_time": frame / 60.0, "monster_index": frame % 3, "alive_monster_count": 24 - frame % 24}
			if frame % 60 == 0:
				var action: String = ["idle", "run", "Attack1", "Attack_EX1"][(frame / 60) % 4]
				expected.notify_action_started(action)
				actual.notify_action_started(action)
			if frame % 83 == 0:
				expected.notify_action_ended("Attack1")
				actual.notify_action_ended("Attack1")
			check(actual.tick(1.0 / 60.0, context) == expected.tick(1.0 / 60.0, context), "Tick output differs: %s / %d" % [name, frame])
			check(actual.snapshot() == expected.snapshot(), "Tree state or random sequence differs: %s / %d" % [name, frame])
			if frame == 300:
				var snapshot := actual.snapshot()
				check(actual.restore(snapshot) and expected.restore(snapshot), "Both paths restore: " + name)
		check(graph == unchanged, "Preparation and evaluation preserve source graph: " + name)
		actual.trace_enabled = false
		expected.trace_enabled = false
		for frame in 120:
			check(actual.tick(1.0 / 60.0, {"target_available": true, "distance": 2.0}) == expected.tick(1.0 / 60.0, {"target_available": true, "distance": 2.0}), "Quiet output differs: %s / %d" % [name, frame])
			check(actual.snapshot() == expected.snapshot(), "Quiet state differs: %s / %d" % [name, frame])
	_binding_cases()
	print("ENEMY_AI_PRECOMPILE ", JSON.stringify({"graphs": seen.size(), "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func _binding_cases() -> void:
	var constant := {"_name": "literal data", "nested": [1, 2, 3]}
	var graph := {"localBlackboard": {"_variables": {"Alpha": {"_id": "target", "_value": 0}}}, "nodes": [{"$id": "1", "$type": "NodeCanvas.BehaviourTrees.ActionNode", "_action": {"$type": "NodeCanvas.Tasks.Actions.SetVariable", "valueA": {"_targetVariableID": "target", "_name": "Fallback"}, "valueB": {"_value": constant}}}], "connections": []}
	var ai := DungeonEnemyAI.new()
	check(ai.configure({"ai": "bindings"}, graph), "Binding fixture configures")
	ai.tick(0.0)
	check(ai.blackboard.Alpha == constant and not ai.blackboard.has("Fallback"), "Target variable ID retains precedence over the fallback name")
	check(is_same(ai.blackboard.Alpha, constant), "Literal parameter data retains its original object and contents")
	graph.localBlackboard._variables = {"Beta": {"_id": "target", "_value": 0}}
	check(ai.configure({"ai": "bindings"}, graph), "The same AI can be reconfigured")
	ai.tick(0.0)
	check(ai.blackboard.Beta == constant and not ai.blackboard.has("Alpha"), "Reconfiguration resolves parameter bindings against the new blackboard")
