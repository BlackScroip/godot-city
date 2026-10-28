extends SceneTree

const Presentation = preload("res://scripts/presentation/combat_presentation.gd")
const BURSTS := {
	"24042901_fx_enemy_senlinlangwang_roar_fireball": 50,
	"24041801_fx_enemy_senlinlangwang_fireball_explosion": 8,
	"24042901_fx_enemy_senlinlangwang_roar_eruption": 4,
	"24042501_fx_enemy_senlinlangwang_attack4_flyslash": 4,
}
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var rows: Array = []
	for low in [false, true]:
		var presentation := Presentation.new()
		root.add_child(presentation)
		presentation.configure({})
		presentation.low_quality = low
		presentation.audio_enabled = false
		presentation.set_process(false)
		var wolf := DungeonActor.new()
		wolf.actor_id = 13001
		wolf.combat = DungeonCombat.new()
		wolf.combat.configure_enemy(13001)
		root.add_child(wolf)
		wolf.set_physics_process(false)
		presentation.prepare_combat([wolf.combat])
		while presentation.has_pending_preparation():
			presentation.prepare_step()
			await process_frame
		var prepared := presentation.authored_builds
		for key in BURSTS:
			var reused := presentation.authored_reuses
			var spawned := presentation.spawned
			var started := Time.get_ticks_usec()
			for index in int(BURSTS[key]):
				presentation.emit_effect(wolf, key, Vector3.ZERO, Vector3.ONE, 1.0)
			var spawn_ms := float(Time.get_ticks_usec() - started) / 1000.0
			var clones := presentation.spawned - spawned - (presentation.authored_reuses - reused)
			var updates: Array[float] = []
			for frame in 60:
				started = Time.get_ticks_usec()
				presentation._process(1.0 / 60.0)
				updates.append(float(Time.get_ticks_usec() - started) / 1000.0)
				await process_frame
			updates.sort()
			rows.append({"effect": key, "low": low, "requested": BURSTS[key], "spawned": presentation.spawned - spawned, "runtime_instances": clones, "spawn_ms": spawn_ms, "update_p95_ms": updates[56]})
			if not "--baseline" in OS.get_cmdline_user_args() and clones > 0: failures.append("Runtime particle construction: " + key + " low=" + str(low))
			if presentation.authored_builds != prepared: failures.append("Runtime template construction: " + key)
			if presentation.spawned - spawned != int(BURSTS[key]): failures.append("Dropped source effect: " + key)
			for effect in presentation.active:
				if not effect.source_only or effect.authored == null: failures.append("Non-source visual: " + key)
			presentation.clear()
		presentation.queue_free()
		wolf.queue_free()
		await process_frame
	var report := {"passed": failures.is_empty(), "failures": failures, "rows": rows, "scope": "First dense wolf particle burst after room preparation, full/reduced quality. CPU allocation and update timings; no GPU or device FPS claim."}
	var label := "before" if "--baseline" in OS.get_cmdline_user_args() else "after"
	FileAccess.open("res://reports/wolf-combat-performance-" + label + ".json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("WOLF_COMBAT_PERFORMANCE ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
