extends SceneTree

const Presentation = preload("res://scripts/presentation/combat_presentation.gd")
const PREFAB := "boss_summon_benchmark"
const ITERATIONS := 300

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _output_path() -> String:
	for value in OS.get_cmdline_user_args():
		if value.begins_with("--output="): return value.trim_prefix("--output=")
	return "/private/tmp/boss-summon-effect-performance.json"

func _run() -> void:
	var rows: Array[Dictionary] = []
	for low in [false, true]:
		var presentation := Presentation.new()
		root.add_child(presentation)
		presentation.configure({})
		presentation.set_process(false)
		presentation.audio_enabled = false
		presentation.effects_density = 2
		presentation.low_quality = low
		presentation.media.effects[PREFAB] = {
			"layers": [{"name": "benchmark", "duration": 1.0,
				"initial": {"startLifetime": {"scalar": 1.0}},
				"materials": [{"blend": "alpha"}],
				"emission": {"m_Bursts": [{"countCurve": {"scalar": 1.0}}]}}]
		}
		var boss := DungeonActor.new()
		boss.actor_id = 53001
		boss.combat = DungeonCombat.new()
		boss.combat.configure_enemy(boss.actor_id)
		root.add_child(boss)
		boss.set_physics_process(false)
		var count := 28 if low else 60
		var tokens: Array[int] = []
		for index in count:
			var token: int = presentation.summon_started(boss, {"Prefab": PREFAB}, Vector3(index, 0, 0))
			_check(token > 0, "Summon %d starts in %s mode" % [index, "low" if low else "full"])
			if token > 0: tokens.append(token)
		_check(presentation.active.size() == count, "All benchmark summons remain active")
		var started := Time.get_ticks_usec()
		for iteration in ITERATIONS:
			for index in tokens.size():
				presentation.summon_updated(tokens[index], Vector3(index, 0, iteration * 0.001), Vector3.BACK)
		var elapsed := Time.get_ticks_usec() - started
		if not tokens.is_empty():
			var first: Dictionary = presentation.active[0]
			_check(first.root.global_position.is_equal_approx(Vector3(0, 0, (ITERATIONS - 1) * 0.001)), "Summon updates reach the leased effect")
			var stale: int = tokens[0]
			presentation.summon_ended(stale)
			var replacement: int = presentation.summon_started(boss, {"Prefab": PREFAB}, Vector3(5, 0, 2))
			var replacement_entry: Dictionary = presentation.active.back()
			presentation.summon_updated(stale, Vector3(99, 0, 99))
			presentation.summon_ended(stale)
			_check(replacement > stale and replacement_entry.root.global_position.is_equal_approx(Vector3(5, 0, 2)), "A stale token cannot move or dispose a reused effect")
			_check(presentation.active.size() == count, "Stale disposal preserves the replacement")
			presentation.clear()
			presentation.summon_updated(replacement, Vector3.ONE)
			presentation.summon_ended(replacement)
			_check(presentation.active.is_empty(), "Clear invalidates remaining summon tokens")
		rows.append({"low_quality": low, "summons": count, "iterations": ITERATIONS,
			"updates": count * ITERATIONS, "update_ms": float(elapsed) / 1000.0})
		presentation.queue_free()
		boss.queue_free()
		await process_frame
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "rows": rows,
		"scope": "Repeated world-owned summon transform updates in headless Godot; CPU elapsed time only, not device FPS or GPU time."}
	var file := FileAccess.open(_output_path(), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "\t") + "\n")
	print("BOSS_SUMMON_EFFECT_PERFORMANCE ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
