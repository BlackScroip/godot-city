extends SceneTree

const Combat = preload("res://scripts/domain/combat.gd")
const Reference = preload("res://tests/fixtures/status_substeps_reference.gd")
const Boundaries = preload("res://tests/fixtures/empty_status_cases.gd")
var checks := 0
var boundary_checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok and failures.size() < 30: failures.append(label)

func _pool(optimized: bool) -> Array:
	var result: Array = []
	for index in 24:
		var actor: DungeonCombat = Combat.new() if optimized else Reference.new()
		actor.configure_enemy(13001 if index == 0 else 11001, 731)
		result.append(actor)
	return result

func _simulate(pool: Array, frames: int) -> void:
	for frame in frames:
		var context := {"target_available": true, "distance": [1.4, 4.0, 8.0][(frame / 80) % 3], "line_blocked": false, "battle_time": frame / 60.0, "monster_index": 0, "target_buffs": []}
		for actor in pool:
			actor.tick_enemy_ai(1.0 / 60, context)
			actor.tick(1.0 / 60)
			actor.drain_events()

func _median(values: Array) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return float(sorted[sorted.size() / 2])

func _run() -> void:
	Boundaries.run(func(ok, label):
		boundary_checks += 1
		check(ok, label))
	var samples := {"baseline": [], "optimized": []}
	for sample in 7:
		var snapshots: Dictionary = {}
		for optimized in ([false, true] if sample % 2 == 0 else [true, false]):
			var pool := _pool(optimized)
			_simulate(pool, 120)
			var before := Time.get_ticks_usec()
			_simulate(pool, 600)
			var name := "optimized" if optimized else "baseline"
			samples[name].append(Time.get_ticks_usec() - before)
			snapshots[name] = pool.map(func(actor): return actor.snapshot())
		check(snapshots.baseline == snapshots.optimized, "Warm workload complete snapshots differ: sample %d" % sample)
	var baseline := _median(samples.baseline) / 600
	var optimized := _median(samples.optimized) / 600
	var report := {"passed": failures.is_empty(), "checks": checks, "boundary_checks": boundary_checks, "failures": failures, "engine": Engine.get_version_info().string, "platform": OS.get_name(), "median_us_per_roster_tick": {"baseline": baseline, "optimized": optimized}, "optimized_ratio": optimized / baseline, "samples_us": samples, "scope": "24 authored source enemies: one 13001 boss plus 23 11001 wolves, seven alternating samples, 120 warmup ticks then 600 timed 60Hz ticks. One outer timer around AI plus combat, same native AI/interrupt backend on both paths. Original status substeps versus empty-status fast path. Desktop CPU scope, not world/rendering time or Android FPS. Configure, startup and snapshot comparisons are outside the timed section."}
	FileAccess.open("res://reports/empty-status-benchmark.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("EMPTY_STATUS_BENCHMARK ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
