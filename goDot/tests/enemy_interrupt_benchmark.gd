extends SceneTree

const Combat = preload("res://scripts/domain/combat.gd")
const Reference = preload("res://tests/fixtures/enemy_interrupt_reference.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _pool(compiled: bool, ids: Array) -> Array:
	var pool: Array = []
	for id in ids:
		var actor: DungeonCombat = Combat.new() if compiled else Reference.new()
		actor.configure_enemy(int(id), 731)
		actor.enemy_ai_enabled = true
		pool.append(actor)
	return pool

func _median(values: Array) -> float:
	var ordered := values.duplicate()
	ordered.sort()
	return float(ordered[ordered.size() / 2])

func _summary(samples: Dictionary, divisor: float, unit: String) -> Dictionary:
	var baseline := _median(samples.baseline) / divisor
	var compiled := _median(samples.compiled) / divisor
	return {"baseline": baseline, "compiled": compiled, "ratio": compiled / baseline, "unit": unit, "samples_us": samples}

func _preparation(catalog: Dictionary) -> Dictionary:
	var ids: Array = catalog.enemies.map(func(enemy): return int(enemy.id))
	var action_groups: Dictionary = {}
	var action_count := 0
	for enemy in catalog.enemies:
		var actions: Array = catalog.actions.filter(func(action): return action.group == enemy.group)
		action_groups[int(enemy.id)] = actions
		action_count += actions.size()
	var cold := {"baseline": [], "compiled": []}
	var warm := {"baseline": [], "compiled": []}
	for sample in 7:
		for compiled in ([false, true] if sample % 2 == 0 else [true, false]):
			var pool := _pool(compiled, ids)
			Combat._raw_json_cache.clear()
			Combat._raw_json_keys.clear()
			Combat._raw_json_cursor = 0
			var started := Time.get_ticks_usec()
			for actor in pool:
				for action in action_groups[actor.enemy_id]: actor._cache_enemy_timing(action)
			cold["compiled" if compiled else "baseline"].append(Time.get_ticks_usec() - started)
			started = Time.get_ticks_usec()
			for iteration in 20:
				for actor in pool:
					for action in action_groups[actor.enemy_id]: actor._cache_enemy_timing(action)
			warm["compiled" if compiled else "baseline"].append(Time.get_ticks_usec() - started)
	return {"enemies": ids.size(), "action_pairs": action_count, "cold": _summary(cold, action_count, "microseconds per first action preparation; empty raw JSON cache"), "warm": _summary(warm, action_count * 20, "microseconds per repeated action preparation")}

func _scan(ids: Array) -> Dictionary:
	var samples := {"baseline": [], "compiled": []}
	for sample in 7:
		for compiled in ([false, true] if sample % 2 == 0 else [true, false]):
			var pool := _pool(compiled, ids)
			for actor in pool:
				var action: Dictionary = actor._action(str(actor.enemy.group), "idle")
				if action.is_empty(): actor.begin_enemy_spawn()
				else: actor._start(action, 0)
				actor.custom_properties.OP_AIAction = "benchmark_unmatched"
				actor._tick_enemy_interrupts()
				actor.drain_events()
			var started := Time.get_ticks_usec()
			for frame in 1000:
				for actor in pool: actor._tick_enemy_interrupts()
			samples["compiled" if compiled else "baseline"].append(Time.get_ticks_usec() - started)
	return {"actors": ids.size(), "timing": _summary(samples, 1000, "microseconds per full roster interrupt scan; warm idle, unmatched AI request")}

func _start_and_restore(ids: Array) -> Dictionary:
	var cold_start := {"baseline": [], "compiled": []}
	var cold_restore := {"baseline": [], "compiled": []}
	var warm_restore := {"baseline": [], "compiled": []}
	var seeds := _pool(false, ids)
	var saved: Array = []
	for actor in seeds:
		actor.begin_enemy_spawn()
		saved.append(JSON.parse_string(JSON.stringify(actor.snapshot())))
	for sample in 7:
		for compiled in ([false, true] if sample % 2 == 0 else [true, false]):
			var key := "compiled" if compiled else "baseline"
			var pool := _pool(compiled, ids)
			Combat._raw_json_cache.clear()
			Combat._raw_json_keys.clear()
			Combat._raw_json_cursor = 0
			var started := Time.get_ticks_usec()
			for actor in pool: actor.begin_enemy_spawn()
			cold_start[key].append(Time.get_ticks_usec() - started)
			pool = _pool(compiled, ids)
			Combat._raw_json_cache.clear()
			Combat._raw_json_keys.clear()
			Combat._raw_json_cursor = 0
			var accepted := true
			started = Time.get_ticks_usec()
			for index in pool.size(): accepted = pool[index].restore(saved[index]) and accepted
			cold_restore[key].append(Time.get_ticks_usec() - started)
			started = Time.get_ticks_usec()
			for iteration in 20:
				for index in pool.size(): accepted = pool[index].restore(saved[index]) and accepted
			warm_restore[key].append(Time.get_ticks_usec() - started)
			if not accepted: failures.append("Start/restore benchmark rejected a snapshot")
	return {"actors": ids.size(), "cold_spawn": _summary(cold_start, ids.size(), "microseconds per first authored spawn; empty raw JSON and per-actor program cache"), "cold_restore": _summary(cold_restore, ids.size(), "microseconds per JSON snapshot restore into a fresh actor; empty raw JSON cache"), "warm_restore": _summary(warm_restore, ids.size() * 20, "microseconds per repeated JSON snapshot restore")}

func _simulate(pool: Array, frames: int) -> void:
	for frame in frames:
		var context := {"target_available": true, "distance": [1.4, 4.0, 8.0][(frame / 80) % 3], "line_blocked": false, "battle_time": frame / 60.0, "monster_index": 0, "target_buffs": []}
		for actor in pool:
			actor.tick_enemy_ai(1.0 / 60, context)
			actor.tick(1.0 / 60)
			actor.drain_events()

func _simulation(ids: Array) -> Dictionary:
	var samples := {"baseline": [], "compiled": []}
	for sample in 7:
		var states: Dictionary = {}
		for compiled in ([false, true] if sample % 2 == 0 else [true, false]):
			var pool := _pool(compiled, ids)
			_simulate(pool, 120)
			var started := Time.get_ticks_usec()
			_simulate(pool, 600)
			samples["compiled" if compiled else "baseline"].append(Time.get_ticks_usec() - started)
			states["compiled" if compiled else "baseline"] = pool.map(func(actor): return actor.snapshot())
		if states.compiled != states.baseline: failures.append("Simulation final snapshots differ: sample %d" % sample)
	return {"actors": ids.size(), "timing": _summary(samples, 600, "microseconds per full roster AI plus combat tick; warm authored skills")}

func _run() -> void:
	var fixture := Combat.new()
	fixture.configure()
	var stress: Array = []
	for index in 24: stress.append(13001 if index == 0 else 11001)
	var report := {"scope": "Desktop headless CPU benchmark, not Android FPS. Original enemy interrupt interpreter versus compiled immutable fields/predicates; same native AI on both paths. Seven samples in alternating order, medians; first preparation/start/restore measured separately from repeated preparation/restore and warm scanning/simulation. Catalog loading and enemy configure excluded from all timed scopes.", "preparation": _preparation(fixture.catalog), "source_crowd_24_start_restore": _start_and_restore(stress), "source_crowd_24_scan": _scan(stress), "all_enemies_scan": _scan(fixture.catalog.enemies.map(func(enemy): return int(enemy.id))), "source_crowd_24_simulation": _simulation(stress), "failures": failures, "passed": failures.is_empty()}
	FileAccess.open("res://reports/enemy-interrupt-benchmark.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("ENEMY_INTERRUPT_BENCHMARK ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
