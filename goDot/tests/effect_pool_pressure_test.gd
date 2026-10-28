extends SceneTree

const Presentation = preload("res://scripts/presentation/combat_presentation.gd")
const KEY := "24080201_fx_sword_satk_dimensionalslash"
var checks := 0
var failures: Array[String] = []

class MeasuredPresentation extends Presentation:
	var clones := 0
	func _take_authored(key: String, cache_key: String, low: bool, source_only := false) -> Node3D:
		if authored_pool.get(cache_key, []).is_empty(): clones += 1
		return super._take_authored(key, cache_key, low, source_only)

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _run() -> void:
	var actor := DungeonActor.new()
	actor.combat = DungeonCombat.new()
	actor.combat.configure()
	root.add_child(actor)
	actor.set_process(false)
	var presentation := MeasuredPresentation.new()
	root.add_child(presentation)
	presentation.configure({})
	presentation.set_process(false)
	presentation.audio_enabled = false
	presentation.effects_density = 2
	for low in [false, true]:
		presentation.low_quality = low
		presentation.clear()
		var ids: Dictionary = {}
		# Reach the existing particle/emitter budget with the same complete effect.
		for index in 80:
			presentation.emit_effect(actor, KEY, Vector3.ZERO)
			ids[presentation.active.back().authored.get_instance_id()] = true
		var before_clones: int = presentation.clones
		var before_ids := ids.duplicate()
		var before_count: int = presentation.active.size()
		var before_particles: int = presentation._active_particles
		var before_emitters: int = presentation._active_emitters
		var before_spawned: int = presentation.spawned
		var timings: Array[float] = []
		for index in 200:
			var started := Time.get_ticks_usec()
			presentation.emit_effect(actor, KEY, Vector3.ZERO)
			timings.append(float(Time.get_ticks_usec() - started))
			check(before_ids.has(presentation.active.back().authored.get_instance_id()), "Pressure reuses an existing complete effect")
		check(presentation.clones == before_clones, "Steady pressure creates no extra authored instances")
		check(presentation.active.size() == before_count and presentation._active_particles == before_particles and presentation._active_emitters == before_emitters, "Visible capacity and source particle/emitter counts are unchanged")
		check(presentation.spawned == before_spawned + 200, "Every pressure request is still presented")
		for entry in presentation.active: entry.important = true
		# Consume any idle copy so the denied request exposes eager cloning.
		var cache_key: String = presentation._authored_cache_key(KEY, false)
		var held: Array[Node3D] = []
		while not presentation.authored_pool.get(cache_key, []).is_empty():
			held.append(presentation._take_authored(KEY, cache_key, low))
		before_clones = presentation.clones
		before_spawned = presentation.spawned
		presentation.emit_effect(actor, KEY, Vector3.ZERO)
		check(presentation.clones == before_clones, "Denied effect does not allocate an unused clone")
		check(presentation.spawned == before_spawned and presentation.active.size() == before_count, "Protected effects retain the existing admission behavior")
		for authored in held: presentation._store_authored(cache_key, authored)
		timings.sort()
		print("EFFECT_POOL_PRESSURE ", JSON.stringify({"low": low, "active": before_count, "particles": before_particles, "emitters": before_emitters, "instances_seen": ids.size(), "spawn_median_us": timings[timings.size() / 2], "spawn_p95_us": timings[int(timings.size() * 0.95)]}))
		presentation.clear()
		check(presentation._active_particles == 0 and presentation._active_emitters == 0 and presentation.pool.size() == presentation.FEEL.effect_budget, "Cleanup restores pool accounting")
	presentation.free()
	actor.free()
	print("EFFECT_POOL_PRESSURE_RESULT ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
