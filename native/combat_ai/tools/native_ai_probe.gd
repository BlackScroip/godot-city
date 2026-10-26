extends SceneTree

class ScriptAI extends DungeonEnemyAI:
	func _native_runtime_allowed() -> bool:
		return false
const FRAMES := 780
const BENCH_FRAMES := 360
var checks := 0
var failures: Array[String] = []
var catalog: Dictionary = {}
var graphs_checked := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value and failures.size() < 30: failures.append(message)

func _context(frame: int) -> Dictionary:
	return {"target_available": frame % 113 < 100, "distance": [1.0, 3.5, 8.0][(frame / 40) % 3], "line_blocked": frame % 90 > 60, "hp_ratio": 1.0 - frame / 850.0, "move_speed": 5.0, "attack_cooldown": 3.0, "self_buffs": ["10001", "900001"] if frame % 80 < 40 else [], "target_buffs": ["10001", "70101113"] if frame % 100 < 50 else [], "battle_time": frame / 60.0, "monster_index": frame % 3, "alive_monster_count": 24 - frame % 24}

func _new(kind: String) -> DungeonEnemyAI:
	return ScriptAI.new() if kind == "baseline" else DungeonEnemyAI.new()

func _release(_ai: DungeonEnemyAI) -> void:
	pass

func _graph_case(name: String, graph: Dictionary, seed_value := 731) -> void:
	var definition := {"ai": name, "ai_source": "runtime-probe"}
	var unchanged := graph.duplicate(true)
	var expected := ScriptAI.new()
	var okay := expected.configure(definition, graph, seed_value)
	var candidates: Array[DungeonEnemyAI] = [_new("native"), _new("native_restore")]
	for actual in candidates:
		check(actual.configure(definition, graph, seed_value) == okay and actual.diagnostics == expected.diagnostics, "Configure: " + name)
		if not actual._root.is_empty(): check(actual._native_runner != null, "Production native path: " + name)
	for frame in FRAMES:
		var context := _context(frame)
		var trace := frame < 600
		expected.trace_enabled = trace
		for actual in candidates: actual.trace_enabled = trace
		if frame % 60 == 0:
			var action: String = ["idle", "run", "attack", "attack2", "LastStand", "born_bosspose", "dive", "Attack1"][(frame / 60) % 8]
			expected.notify_action_started(action)
			for actual in candidates: actual.notify_action_started(action)
		if frame % 83 == 0:
			expected.notify_action_ended("attack")
			for actual in candidates: actual.notify_action_ended("attack")
		if frame % 90 == 0: context.blackboard = {"BB_AttackCDTimer": 3.0, "SYS_Timer": 2.0, "BB_NextAttackId": frame % 3}
		var result := expected.tick(1.0 / 60.0, context)
		var state := expected.snapshot()
		for index in candidates.size():
			var actual := candidates[index]
			check(actual.tick(1.0 / 60.0, context) == result, "Output kind %d: %s/%d" % [index, name, frame])
			check(actual.snapshot() == state and actual.diagnostics == expected.diagnostics, "Snapshot/RNG/diagnostic kind %d: %s/%d" % [index, name, frame])
		if frame % 23 == 0:
			check(candidates[1].restore(state), "Frequent native restore: " + name)
		if frame in [300, 650]:
			var saved: Dictionary = JSON.parse_string(JSON.stringify(state))
			check(expected.restore(saved), "Reference restore: " + name)
			for actual in candidates: check(actual.restore(saved) and actual.snapshot() == expected.snapshot(), "Compiled restore: " + name)
	for delta in [-1.0, INF, NAN]:
		var result := expected.tick(delta)
		for actual in candidates: check(actual.tick(delta) == result and actual.snapshot() == expected.snapshot(), "Invalid delta: " + name)
	check(graph == unchanged, "Source graph remains intact: " + name)
	for actual in candidates: _release(actual)
	graphs_checked += 1

func _fixtures() -> void:
	var action := {"$id": "leaf", "$type": "ActionNode", "_action": {"$type": "SetFloat", "valueA": {"_name": "X"}, "valueB": {"_value": 1}, "Operation": 1}}
	var shared := {"nodes": [{"$id": "root", "$type": "Parallel", "dynamic": true}, {"$id": "A", "$type": "Merge"}, {"$id": "B", "$type": "Merge"}, action], "connections": [_edge("root", "A"), _edge("root", "B"), _edge("A", "leaf"), _edge("B", "leaf")]}
	_graph_case("fixture_shared_dag", shared)
	var cycle := {"nodes": [{"$id": "root", "$type": "Merge"}, {"$id": "A", "$type": "Sequencer"}, {"$id": "B", "$type": "Merge"}], "connections": [_edge("root", "A"), _edge("A", "B"), _edge("B", "A")]}
	_graph_case("fixture_cycle", cycle)
	_graph_case("fixture_missing_root", {"nodes": [], "connections": []})
	_graph_case("fixture_dangling", {"nodes": [action], "connections": [_edge("leaf", "unknown")]})
	var constant := {"_name": "literal data", "nested": [1, 2, 3]}
	var binding := {"localBlackboard": {"_variables": {"Alpha": {"_id": "target", "_value": 0}}}, "nodes": [{"$id": "1", "$type": "ActionNode", "_action": {"$type": "SetVariable", "valueA": {"_targetVariableID": "target", "_name": "Fallback"}, "valueB": {"_value": constant}}}], "connections": []}
	_graph_case("fixture_parameter_identity", binding)
	for kind in ["baseline", "native"]:
		var ai := _new(kind)
		check(ai.configure({"ai": "binding"}, binding), "Binding loads: " + kind)
		ai.tick(0)
		check(is_same(ai.blackboard.Alpha, constant), "Parameter identity: " + kind)
		binding.localBlackboard._variables = {"Beta": {"_id": "target", "_value": 0}}
		check(ai.configure({"ai": "binding"}, binding), "Reconfigure: " + kind)
		ai.tick(0)
		check(ai.blackboard.Beta == constant and not ai.blackboard.has("Alpha"), "Reconfigure binding: " + kind)
		binding.localBlackboard._variables = {"Alpha": {"_id": "target", "_value": 0}}
		_release(ai)

func _edge(parent: String, child: String) -> Dictionary:
	return {"_sourceNode": {"$ref": parent}, "_targetNode": {"$ref": child}}

func _pool(kind: String, roster: Array) -> Array[DungeonEnemyAI]:
	var result: Array[DungeonEnemyAI] = []
	for index in roster.size():
		var name: String = roster[index]
		var ai := _new(kind)
		ai.configure({"ai": name}, catalog.ai_graphs[name], 731 + index)
		ai.trace_enabled = false
		result.append(ai)
	return result

func _measure(pool: Array[DungeonEnemyAI], contexts: Array[Dictionary]) -> float:
	var begin := Time.get_ticks_usec()
	for frame in contexts.size():
		var context := contexts[frame]
		for ai in pool:
			if frame % 60 == 0: ai.notify_action_started("idle" if frame % 120 == 0 else "attack")
			ai.tick(1.0 / 60.0, context)
	return float(Time.get_ticks_usec() - begin) / contexts.size()

func _benchmark(roster: Array) -> Dictionary:
	var contexts: Array[Dictionary] = []
	for frame in BENCH_FRAMES: contexts.append(_context(frame))
	var samples := {"baseline": [], "native": []}
	for round_index in 7:
		var order := ["baseline", "native"] if round_index % 2 == 0 else ["native", "baseline"]
		for kind in order:
			var pool := _pool(kind, roster)
			var elapsed := _measure(pool, contexts)
			if round_index > 0: samples[kind].append(elapsed)
			for ai in pool: _release(ai)
	var medians: Dictionary = {}
	for kind in samples:
		samples[kind].sort()
		medians[kind] = (samples[kind][2] + samples[kind][3]) * 0.5
	return {"actors": roster.size(), "median_us_per_tick": medians, "native_ratio": medians.native / medians.baseline, "samples_us": samples}


func _run() -> void:
	catalog = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/combat.json"))
	if OS.get_cmdline_user_args().has("--fallback-only"):
		for name in catalog.ai_graphs:
			var expected := ScriptAI.new()
			var actual := DungeonEnemyAI.new()
			var definition := {"ai": name}
			expected.configure(definition, catalog.ai_graphs[name], 731)
			actual.configure(definition, catalog.ai_graphs[name], 731)
			check(actual._native_runner == null, "Missing library uses script: " + name)
			for frame in 120:
				check(actual.tick(1.0 / 60.0, _context(frame)) == expected.tick(1.0 / 60.0, _context(frame)), "Fallback output: " + name)
				check(actual.snapshot() == expected.snapshot(), "Fallback state: " + name)
		print("NATIVE_AI_FALLBACK ", JSON.stringify({"checks": checks, "failures": failures}))
		quit(0 if failures.is_empty() else 1)
		return
	for name in catalog.ai_graphs: _graph_case(name, catalog.ai_graphs[name])
	_fixtures()
	var stress: Array = []
	for index in 24:
		var id := 13001 if index == 0 else 11001
		for enemy in catalog.enemies:
			if int(enemy.id) == id:
				stress.append(str(enemy.ai))
				break
	var benchmark := {"stress_24": _benchmark(stress), "all_source_graphs": _benchmark(catalog.ai_graphs.keys())}
	var report := {"graphs_checked": graphs_checked, "checks": checks, "failures": failures, "passed": failures.is_empty(), "benchmark": benchmark, "scope": "Production optional native C++ path versus forced original GDScript. Exact outputs, trace/visited ordering, snapshots, RNG and JSON/frequent restore over all source graphs plus edge fixtures; desktop CPU timings, not Android FPS."}
	var report_path: String = get_script().resource_path.get_base_dir().path_join("../reports/native-ai-probe.json").simplify_path()
	FileAccess.open(report_path, FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("NATIVE_AI_PROBE ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
