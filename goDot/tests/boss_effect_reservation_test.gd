extends SceneTree

const Presentation = preload("res://scripts/presentation/combat_presentation.gd")
const POISON := "26071801_fx_enemy_mojiehua_attack3_duyejidang"
const HIT := "26072201_fx_enemy_mojiehua_attack_hit"
const FILLER := "26072001_fx_enemy_mojiehua_baozidanmu"
const SUMMON_ID := "41300220"
const PARTICLE_FIXTURE := "boss_reservation_particle_fixture"

var checks := 0
var failures: Array[String] = []
var rows: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _run() -> void:
	var presentation := Presentation.new()
	root.add_child(presentation)
	presentation.configure({})
	presentation.set_process(false)
	presentation.audio_enabled = false
	var flower := DungeonActor.new()
	flower.actor_id = 13002
	flower.combat = DungeonCombat.new()
	flower.combat.configure_enemy(13002)
	root.add_child(flower)
	flower.set_physics_process(false)
	var action: Dictionary = flower.combat._action("ActGroup_mojiehua", "attack3")
	var poison_events: Array = action.events.filter(func(event): return event.get("enabled", false) and POISON in str(event.get("raw", "")).to_lower())
	var summon: Dictionary = flower.combat._summon_index.get(SUMMON_ID, {}).get("raw_data", {})
	_check(poison_events.size() == 1, "Real flower attack3 poison event is available")
	_check(not str(summon.get("Prefab", "")).is_empty(), "Real flower poison-pool summon is available")
	if poison_events.size() == 1 and not summon.is_empty():
		var trigger: Dictionary = DungeonWorld._raw_definition(poison_events[0]).get("EffectTriggerDef", {})
		for low in [false, true]:
			for density in [0, 1]:
				_check_summon_pressure(presentation, flower, summon, trigger, low, density)
				_check_unsatisfiable_request(presentation, flower, trigger, low, density)
	_check_effect_count_limit(presentation, flower)
	_check_particle_limit(presentation, flower)
	_check_empty_pool(presentation, flower)
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "rows": rows,
		"scope": "Headless budget stress using the flower Boss's real poison-pool summon, poison action and hit effects; not APK device or visual comparison."}
	print("BOSS_EFFECT_RESERVATION ", JSON.stringify(report))
	presentation.clear()
	presentation.queue_free()
	flower.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _quality_limits(presentation: Node3D, low: bool) -> Dictionary:
	return {"effects": presentation.FEEL.low_effect_budget if low else presentation.FEEL.effect_budget,
		"emitters": presentation.FEEL.low_emitter_budget if low else presentation.FEEL.emitter_budget,
		"particles": presentation.FEEL.low_particle_budget if low else presentation.FEEL.particle_budget}

func _within_limits(presentation: Node3D, limits: Dictionary) -> bool:
	return presentation.active.size() <= int(limits.effects) and presentation._active_emitters <= int(limits.emitters) and presentation._active_particles <= int(limits.particles)

func _check_summon_pressure(presentation: Node3D, flower: DungeonActor, summon: Dictionary, trigger: Dictionary, low: bool, density: int) -> void:
	presentation.clear()
	presentation.low_quality = low
	presentation.effects_density = density
	flower.combat._cast_sequence = 11
	var suffix := " low=%s density=%s" % [low, density]
	var limits := _quality_limits(presentation, low)
	var started := 0
	# This intentionally stresses beyond normal pacing, while using the real summon definition.
	for index in 64:
		if presentation.summon_started(flower, summon, Vector3.ZERO) > 0: started += 1
	var summon_count: int = presentation.active.filter(func(entry): return int(entry.get("summon_token", 0)) > 0).size()
	_check(summon_count > 0, "A flower summon remains visible" + suffix)
	_check(_within_limits(presentation, limits), "Summons respect hard limits" + suffix)
	var poison_before: int = presentation.spawned
	presentation.trigger(flower, trigger, 11)
	var poison: Array = presentation.active.filter(func(entry): return entry.key == POISON)
	_check(presentation.spawned > poison_before and poison.size() == 1, "Poison remains admissible after sustained summons" + suffix)
	if not poison.is_empty(): _check(poison[0].priority and not poison[0].detached, "Poison preserves its priority and action ownership" + suffix)
	for index in 2: presentation.emit_effect(flower, HIT, Vector3.ZERO, Vector3.ONE, 1.0, null, false, -1, false, true)
	var hits: Array = presentation.active.filter(func(entry): return entry.key == HIT)
	_check(not poison.is_empty() and presentation.active.has(poison[0]) and hits.size() >= 2, "Poison and two hit effects coexist under summon pressure" + suffix)
	_check(_within_limits(presentation, limits), "Boss feedback respects hard limits" + suffix)
	flower.combat._cast_sequence = 12
	presentation._process(0.01)
	_check(presentation.active.filter(func(entry): return entry.key == POISON).is_empty(), "Poison is cancelled on action change" + suffix)
	rows.append({"case": "summon_pressure", "low": low, "density": density, "started_summons": started,
		"summons_before_poison": summon_count, "poison_admitted": not poison.is_empty(), "hits_admitted": hits.size(), "emitter_limit": limits.emitters})

func _check_unsatisfiable_request(presentation: Node3D, flower: DungeonActor, trigger: Dictionary, low: bool, density: int) -> void:
	presentation.clear()
	presentation.low_quality = low
	presentation.effects_density = density
	flower.combat._cast_sequence = 21
	var suffix := " low=%s density=%s" % [low, density]
	var limits := _quality_limits(presentation, low)
	var poison_template: Node3D = presentation._authored_template(POISON, presentation._authored_cache_key(POISON, false), low, false)
	var filler_template: Node3D = presentation._authored_template(FILLER, presentation._authored_cache_key(FILLER, false), low, false)
	var poison_emitters: int = poison_template.emitters.size()
	var filler_emitters: int = filler_template.emitters.size()
	_check(poison_emitters > 0 and filler_emitters > 0, "Pressure fixture has real emitters" + suffix)
	if poison_emitters <= 0 or filler_emitters <= 0: return
	presentation.emit_effect(flower, FILLER, Vector3.ZERO, Vector3.ONE, 5.0)
	if presentation.active.is_empty():
		_check(false, "Ordinary effect starts before hard-budget pressure" + suffix)
		return
	var ordinary: Dictionary = presentation.active.back()
	var blocker_count := int((int(limits.emitters) - filler_emitters) / poison_emitters)
	for index in blocker_count: presentation.trigger(flower, trigger, 21)
	var actual_blockers: int = presentation.active.filter(func(entry): return entry.key == POISON and entry.priority).size()
	_check(actual_blockers == blocker_count and blocker_count * poison_emitters + poison_emitters > int(limits.emitters), "Protected effects make the request impossible even without ordinary effects" + suffix)
	var spawned_before: int = presentation.spawned
	var emitters_before: int = presentation._active_emitters
	presentation.emit_effect(flower, POISON, Vector3.ZERO, Vector3.ONE, 1.0)
	_check(presentation.spawned == spawned_before, "Impossible ordinary request is rejected" + suffix)
	_check(presentation.active.has(ordinary) and presentation._active_emitters == emitters_before, "Rejected ordinary request leaves existing ordinary effect intact" + suffix)
	_check(_within_limits(presentation, limits), "Impossible request leaves hard limits intact" + suffix)
	rows.append({"case": "unsatisfiable_request", "low": low, "density": density, "blockers": actual_blockers,
		"blocker_emitters": poison_emitters, "ordinary_preserved": presentation.active.has(ordinary), "emitter_limit": limits.emitters})

func _check_effect_count_limit(presentation: Node3D, flower: DungeonActor) -> void:
	presentation.clear()
	presentation.low_quality = true
	presentation.effects_density = 0
	var effect_limit := maxi(4, int(presentation.FEEL.low_effect_budget * 0.35))
	var particle_limit := maxi(128, int(presentation.FEEL.low_particle_budget * 0.35))
	var emitter_limit := maxi(8, int(presentation.FEEL.low_emitter_budget * 0.35))
	var filler: Node3D = presentation._authored_template(FILLER, presentation._authored_cache_key(FILLER, false), true, false)
	presentation.emit_effect(flower, FILLER, Vector3.ZERO, Vector3.ONE, 5.0)
	_check(not presentation.active.is_empty(), "Effect-count fixture starts an ordinary effect")
	if presentation.active.is_empty(): return
	var ordinary: Dictionary = presentation.active.back()
	# Empty generic priority bursts occupy effect slots without consuming particle or emitter slots.
	for index in effect_limit: presentation.emit_effect(flower, "", Vector3.ZERO, Vector3.ONE, 5.0, null, false, -1, false, true)
	var protected: int = presentation.active.filter(func(entry): return entry.priority).size()
	_check(protected == effect_limit and not presentation.pool.is_empty(), "Effect slots, not the pool, prevent the ordinary request")
	_check(presentation._active_particles + filler.particle_count <= particle_limit and presentation._active_emitters + filler.emitters.size() <= emitter_limit, "Particle and emitter limits allow the effect-count request")
	var spawned_before: int = presentation.spawned
	var count_before: int = presentation.active.size()
	presentation.emit_effect(flower, FILLER, Vector3.ZERO, Vector3.ONE, 5.0)
	_check(presentation.spawned == spawned_before, "Impossible effect-count request is rejected")
	_check(presentation.active.size() == count_before and presentation.active.has(ordinary), "Effect-count rejection preserves the ordinary effect")
	rows.append({"case": "effect_count", "protected": protected, "limit": effect_limit, "ordinary_preserved": presentation.active.has(ordinary)})

func _check_particle_limit(presentation: Node3D, flower: DungeonActor) -> void:
	presentation.clear()
	presentation.low_quality = true
	presentation.effects_density = 0
	presentation.media.effects[PARTICLE_FIXTURE] = {
		"layers": [{"name": "single_burst", "duration": 1.0,
			"initial": {"maxNumParticles": 32, "startLifetime": {"scalar": 1.0}},
			"materials": [{"blend": "alpha"}],
			"emission": {"m_Bursts": [{"countCurve": {"scalar": 32.0}}]}}]
	}
	var effect_limit := maxi(4, int(presentation.FEEL.low_effect_budget * 0.35))
	var particle_limit := maxi(128, int(presentation.FEEL.low_particle_budget * 0.35))
	var emitter_limit := maxi(8, int(presentation.FEEL.low_emitter_budget * 0.35))
	var particle_fixture: Node3D = presentation._authored_template(PARTICLE_FIXTURE, presentation._authored_cache_key(PARTICLE_FIXTURE, false), true, false)
	_check(particle_fixture.particle_count == 32 and particle_fixture.emitters.size() == 1, "Particle fixture has one 32-particle emitter")
	if particle_fixture.particle_count <= 0: return
	presentation.emit_effect(flower, FILLER, Vector3.ZERO, Vector3.ONE, 5.0)
	_check(not presentation.active.is_empty(), "Particle-limit fixture starts an ordinary effect")
	if presentation.active.is_empty(): return
	var ordinary: Dictionary = presentation.active.back()
	var blocker_count := int(particle_limit / particle_fixture.particle_count)
	for index in blocker_count: presentation.emit_effect(flower, PARTICLE_FIXTURE, Vector3.ZERO, Vector3.ONE, 5.0, null, false, -1, false, true)
	var protected: int = presentation.active.filter(func(entry): return entry.key == PARTICLE_FIXTURE and entry.priority).size()
	_check(protected == blocker_count and (protected + 1) * particle_fixture.particle_count > particle_limit, "Protected particles make the ordinary request impossible")
	_check(presentation.active.size() < effect_limit and presentation._active_emitters + particle_fixture.emitters.size() <= emitter_limit and not presentation.pool.is_empty(), "Effect, emitter and pool limits allow the particle request")
	var spawned_before: int = presentation.spawned
	var count_before: int = presentation.active.size()
	var particles_before: int = presentation._active_particles
	presentation.emit_effect(flower, PARTICLE_FIXTURE, Vector3.ZERO, Vector3.ONE, 5.0)
	_check(presentation.spawned == spawned_before, "Impossible particle request is rejected")
	_check(presentation.active.size() == count_before and presentation.active.has(ordinary) and presentation._active_particles == particles_before, "Particle rejection preserves the ordinary effect and particle count")
	rows.append({"case": "particles", "protected": protected, "particle_limit": particle_limit, "ordinary_preserved": presentation.active.has(ordinary)})

func _check_empty_pool(presentation: Node3D, flower: DungeonActor) -> void:
	presentation.clear()
	presentation.low_quality = true
	presentation.effects_density = 0
	var initial_pool_size: int = presentation.pool.size()
	var held: Array[Dictionary] = []
	while presentation.pool.size() > 2: held.append(presentation.pool.pop_back())
	for index in 2: presentation.emit_effect(flower, "", Vector3.ZERO, Vector3.ONE, 5.0, null, false, -1, false, true)
	_check(presentation.pool.is_empty() and presentation.active.size() == 2, "Pool fixture exhausts its two available effect roots")
	var protected: Array = presentation.active.duplicate()
	var spawned_before: int = presentation.spawned
	presentation.emit_effect(flower, FILLER, Vector3.ZERO, Vector3.ONE, 5.0)
	_check(presentation.spawned == spawned_before and protected.all(func(entry): return presentation.active.has(entry)), "Unreclaimable empty pool rejects without changing protected effects")
	presentation.emit_effect(flower, FILLER, Vector3.ZERO, Vector3.ONE, 5.0, null, true)
	_check(presentation.spawned == spawned_before + 1 and presentation.active.size() == 2 and presentation.active.filter(func(entry): return entry.important).size() == 1, "Critical request reclaims an eligible root from an empty pool")
	presentation.clear()
	for entry in held: presentation.pool.append(entry)
	_check(presentation.pool.size() == initial_pool_size, "Pool fixture restores all roots")
	rows.append({"case": "empty_pool", "initial_roots": initial_pool_size, "restored_roots": presentation.pool.size()})
