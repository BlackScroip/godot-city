extends SceneTree

const Combat = preload("res://scripts/domain/combat.gd")
const Reference = preload("res://tests/fixtures/navigation_reference.gd")
const Candidate = preload("res://scripts/domain/combat.gd")
const Measured = preload("res://tests/fixtures/navigation_measured.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _pool(kind: String, ids: Array) -> Array:
	var pool: Array = []
	for id in ids:
		var actor: DungeonCombat = Candidate.new() if kind == "candidate" else Measured.new() if kind == "measured" else Reference.new()
		actor.configure_enemy(int(id), 731)
		pool.append(actor)
	return pool

func _median(samples: Array) -> float:
	var ordered := samples.duplicate()
	ordered.sort()
	return float(ordered[ordered.size() / 2])

func _summary(samples: Dictionary, divisor: float, unit: String) -> Dictionary:
	var baseline := _median(samples.reference) / divisor
	var candidate := _median(samples.candidate) / divisor
	return {"reference": baseline, "candidate": candidate, "ratio": candidate / baseline, "unit": unit, "samples_us": samples}

func _warm_scan(ids: Array) -> Dictionary:
	var samples := {"reference": [], "candidate": []}
	for sample in 7:
		var checksums: Dictionary = {}
		for kind in (["reference", "candidate"] if sample % 2 == 0 else ["candidate", "reference"]):
			var pool := _pool(kind, ids)
			for actor in pool:
				actor.current_action = "idle"
				actor.action_elapsed = 0.25
				actor.enemy_navigation_requested()
			var checksum := 0
			var started := Time.get_ticks_usec()
			for frame in 2000:
				for actor in pool: checksum += int(actor.enemy_navigation_requested())
			samples[kind].append(Time.get_ticks_usec() - started)
			checksums[kind] = checksum
		if checksums.reference != checksums.candidate: failures.append("warm scan result differs")
	return _summary(samples, 2000.0, "microseconds per 24-actor warm idle navigation scan")

func _cold_scan(catalog: Dictionary) -> Dictionary:
	var ids: Array = catalog.enemies.map(func(enemy): return int(enemy.id))
	var samples := {"reference": [], "candidate": []}
	var groups: Dictionary = {}
	var count := 0
	for enemy in catalog.enemies:
		groups[int(enemy.id)] = catalog.actions.filter(func(action): return action.group == enemy.group)
		count += groups[int(enemy.id)].size()
	for sample in 7:
		var checksums: Dictionary = {}
		for kind in (["reference", "candidate"] if sample % 2 == 0 else ["candidate", "reference"]):
			var pool := _pool(kind, ids)
			var checksum := 0
			var started := Time.get_ticks_usec()
			for actor in pool:
				for action in groups[actor.enemy_id]:
					actor.current_action = str(action.id)
					actor.action_elapsed = 0.25
					checksum += int(actor.enemy_navigation_requested())
			samples[kind].append(Time.get_ticks_usec() - started)
			checksums[kind] = checksum
		if checksums.reference != checksums.candidate: failures.append("cold scan result differs")
	return {"source_action_pairs": count, "timing": _summary(samples, count, "microseconds per first action scan including current_action assignment")}

func _simulate(pool: Array, frames: int) -> int:
	var checksum := 0
	for frame in frames:
		var context := {"target_available": true, "distance": [1.4, 4.0, 8.0][(frame / 80) % 3], "line_blocked": false, "battle_time": frame / 60.0, "monster_index": 0, "target_buffs": []}
		for actor in pool:
			actor.tick_enemy_ai(1.0 / 60, context)
			checksum += int(actor.enemy_navigation_requested())
			actor.tick(1.0 / 60)
			actor.drain_events()
	return checksum

func _combined(ids: Array) -> Dictionary:
	var samples := {"reference": [], "candidate": []}
	for sample in 7:
		var states: Dictionary = {}
		var checksums: Dictionary = {}
		for kind in (["reference", "candidate"] if sample % 2 == 0 else ["candidate", "reference"]):
			var pool := _pool(kind, ids)
			_simulate(pool, 120)
			var started := Time.get_ticks_usec()
			checksums[kind] = _simulate(pool, 600)
			samples[kind].append(Time.get_ticks_usec() - started)
			states[kind] = pool.map(func(actor): return actor.snapshot())
		if states.reference != states.candidate or checksums.reference != checksums.candidate: failures.append("combined final states/result differ: sample %d" % sample)
	return _summary(samples, 600.0, "microseconds per 24-actor AI/navigation/combat tick, no rendering/physics")

func _fraction(ids: Array) -> Dictionary:
	var pool := _pool("measured", ids)
	_simulate(pool, 120)
	for actor in pool:
		actor.navigation_us = 0
		actor.navigation_calls = 0
	var started := Time.get_ticks_usec()
	_simulate(pool, 600)
	var total := Time.get_ticks_usec() - started
	var navigation := 0
	var calls := 0
	for actor in pool:
		navigation += int(actor.navigation_us)
		calls += int(actor.navigation_calls)
	return {"combined_us": total, "navigation_us": navigation, "calls": calls, "fraction": float(navigation) / total, "navigation_us_per_roster_tick": navigation / 600.0, "scope": "Instrumented original method only. Nested per-call clock/dispatch overhead means diagnostic attribution, not a precise uninstrumented fraction."}

func _run() -> void:
	var tested_source := {"started_utc": Time.get_datetime_string_from_system(true) + "Z", "before_sha256": FileAccess.get_sha256("res://scripts/domain/combat.gd")}
	var actor := Combat.new()
	actor.configure()
	var ids: Array = []
	for index in 24: ids.append(13001 if index == 0 else 11001)
	var report := {"scope": "Desktop headless CPU only, not Android FPS or full world cost. Single-current-action immutable float64 window/fallback cache versus exact original method; current definition identity, elapsed and speed read dynamically. Seven samples alternate order; configure/catalog excluded. Cold first-action costs are separate. Combined is authored native AI + navigation query + combat, no actor movement or rendering.", "warm_scan_24": _warm_scan(ids), "cold_all_actions": _cold_scan(actor.catalog), "combined_24": _combined(ids), "instrumented_fraction_24": _fraction(ids), "failures": failures, "passed": failures.is_empty()}
	tested_source["after_sha256"] = FileAccess.get_sha256("res://scripts/domain/combat.gd")
	report["tested_source"] = tested_source
	FileAccess.open("res://reports/enemy-navigation-cache-benchmark.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("NAVIGATION_BENCHMARK ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
