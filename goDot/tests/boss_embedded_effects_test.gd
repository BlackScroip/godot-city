extends SceneTree

const Presentation = preload("res://scripts/presentation/combat_presentation.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _actor(id: int) -> DungeonActor:
	var actor := DungeonActor.new()
	actor.actor_id = id
	actor.combat = DungeonCombat.new()
	actor.combat.configure_enemy(id)
	root.add_child(actor)
	actor.set_physics_process(false)
	actor.set_visual("res://assets/enemies/enemy_%d.glb" % id)
	return actor

func _flush(presentation: Node3D) -> void:
	var frames := 0
	while presentation.has_pending_preparation() or not presentation._boss_embedded_queue.is_empty():
		presentation._process(0.016)
		frames += 1
		if frames > 10000:
			check(false, "Preparation and embedded queue finish")
			return
		await process_frame

func _command(presentation: Node3D, actor: DungeonActor, names: Array, enabled: bool) -> void:
	presentation.command(actor, {"sequence": actor.combat._cast_sequence, "command": {"type": "EET_SetGameObjectActive", "raw": JSON.stringify({"gameobjectNames": names, "booleanToSet": enabled})}})

func _stage(presentation: Node3D, actor: DungeonActor, action_id: String) -> void:
	var action: Dictionary = actor.combat._action(str(actor.combat.enemy.group), action_id)
	var commands: Array = action.events.filter(func(row): return row.get("enabled", false) and row.get("type", "") == "EET_SetGameObjectActive")
	commands.sort_custom(func(a, b): return float(a.time) < float(b.time))
	check(not commands.is_empty(), action_id + " contains source activation commands")
	for command in commands: presentation.command(actor, {"sequence": actor.combat._cast_sequence, "command": command})

func _matching_keys(presentation: Node3D, actor: DungeonActor, names: Array) -> Array:
	var keys: Array = []
	for key in presentation._boss_embedded.actors[str(actor.actor_id)]:
		if presentation._boss_embedded.bindings[key].name in names: keys.append(key)
	return keys

func _run() -> void:
	var presentation := Presentation.new()
	root.add_child(presentation)
	presentation.configure({})
	presentation.set_process(false)
	presentation.audio_enabled = false
	presentation.effects_density = 2
	var reaper := _actor(52003)
	var dragon := _actor(53001)
	check(reaper.visual_loaded and dragon.visual_loaded, "Both source boss models load")
	check(presentation._boss_embedded.actors["52003"].size() == 4, "Four source reaper roots are catalogued")
	check(presentation._boss_embedded.actors["53001"].size() == 24, "Twenty-four source dragon roots are catalogued")
	presentation.prepare_combat([reaper.combat, dragon.combat])
	presentation.register_boss_embedded(reaper)
	presentation.register_boss_embedded(dragon)
	check(presentation.active.is_empty(), "Default effects wait for media preparation")
	check(presentation._boss_embedded_actors[dragon.get_instance_id()].desired.is_empty(), "Dragon source roots are all inactive at spawn")
	var fire := ["24122501_fx_enemy_feimolong_firewindbuff_behind", "24122501_fx_enemy_feimolong_firewindbuff_front", "24122501_fx_enemy_feimolong_firewindbuff_trail"]
	var water := ["24122502_fx_enemy_feimolong_waterthunderbuff_behind", "24122502_fx_enemy_feimolong_waterthunderbuff_body", "24122502_fx_enemy_feimolong_waterthunderbuff_front", "24122502_fx_enemy_feimolong_waterthunderbuff_wing"]
	var light := ["24122503_fx_enemy_feimolong_lightdarkbuff_behind", "24122503_fx_enemy_feimolong_lightdarkbuff_front", "24122503_fx_enemy_feimolong_lightdarkbuff_wing"]
	# A phase command arriving during loading must survive until its assets are ready.
	_command(presentation, dragon, fire, true)
	_command(presentation, dragon, fire, false)
	_stage(presentation, dragon, "roar1")
	await _flush(presentation)
	var reaper_live: Dictionary = presentation._boss_embedded_live.get(reaper.get_instance_id(), {})
	var dragon_live: Dictionary = presentation._boss_embedded_live.get(dragon.get_instance_id(), {})
	check(reaper_live.size() == 4, "All four default reaper roots activate")
	check(dragon_live.size() == _matching_keys(presentation, dragon, fire).size(), "Pre-load activation reaches every fire/wind root")
	check(presentation.unresolved_anchors.is_empty(), "All active roots resolve their actual model anchors")
	var builds: int = presentation.authored_builds
	for effect in reaper_live.values() + dragon_live.values():
		check(effect.authored != null and effect.source_only and effect.follow.get_ref() != null, "Embedded root uses its source particles and a live anchor")
		check(effect.sequence == -1 and effect.clock_sequence == -1 and not effect.detached, "Embedded root follows actor lifetime rather than an action")
		var anchor: Node3D = effect.follow.get_ref()
		check(effect.root.global_position.is_equal_approx(anchor.to_global(effect.offset)), "Embedded root preserves its anchor-relative position")
	var before := presentation.spawned
	_command(presentation, dragon, fire, true)
	await _flush(presentation)
	check(presentation.spawned == before, "Repeated activation is idempotent")
	presentation.cancel_actor(reaper)
	presentation.cancel_actor(dragon)
	check(presentation._boss_embedded_live.get(reaper.get_instance_id(), {}).size() == 4, "Action cancellation preserves reaper roots")
	check(presentation._boss_embedded_live.get(dragon.get_instance_id(), {}).size() == _matching_keys(presentation, dragon, fire).size(), "Action cancellation preserves dragon phase")
	_stage(presentation, dragon, "roar2")
	await _flush(presentation)
	dragon_live = presentation._boss_embedded_live.get(dragon.get_instance_id(), {})
	check(dragon_live.size() == _matching_keys(presentation, dragon, water).size(), "Water/thunder transition removes fire and enables every matching root")
	_stage(presentation, dragon, "roar3")
	await _flush(presentation)
	dragon_live = presentation._boss_embedded_live.get(dragon.get_instance_id(), {})
	check(dragon_live.size() == _matching_keys(presentation, dragon, light).size(), "Light/dark transition removes water and enables every matching root")
	check(presentation.authored_builds == builds, "All tested phase roots were prewarmed")
	check(presentation._active_particles <= presentation.FEEL.particle_budget and presentation._active_emitters <= presentation.FEEL.emitter_budget, "Embedded effects obey global particle and emitter budgets")
	check(presentation.unresolved_anchors.is_empty(), "Every stage anchor resolves on the imported models")
	var snapshot: Dictionary = dragon.combat.snapshot()
	var restored := _actor(53001)
	check(restored.combat.restore(snapshot), "Dragon combat snapshot restores")
	presentation.register_boss_embedded(restored)
	await _flush(presentation)
	var restored_live: Dictionary = presentation._boss_embedded_live.get(restored.get_instance_id(), {})
	check(restored_live.size() == _matching_keys(presentation, restored, light).size(), "Snapshot restores the active light/dark roots without replaying roar")
	for key in restored_live: check(key in _matching_keys(presentation, restored, light), "Snapshot does not restore an earlier phase")
	var restored_spawned := presentation.spawned
	presentation.register_boss_embedded(restored)
	await _flush(presentation)
	check(presentation.spawned == restored_spawned, "Repeated registration after restore does not duplicate roots")
	reaper.dead = true
	presentation.sync_buffs([reaper, dragon])
	check(not presentation._boss_embedded_live.has(reaper.get_instance_id()), "Death recycles the reaper's embedded effects")
	check(presentation._boss_embedded_live.has(dragon.get_instance_id()), "One boss death leaves the other boss's roots intact")
	presentation.clear()
	check(presentation.active.is_empty() and presentation._boss_embedded_live.is_empty() and presentation._boss_embedded_actors.is_empty(), "Room clear releases embedded effects and ownership")
	check(presentation._active_particles == 0 and presentation._active_emitters == 0, "Room clear restores particle budgets")
	await _pressure(presentation, reaper, dragon)
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "scope": "Recovered reaper and flying dragon effects on imported Godot models; not original APK runtime or pixel-parity verification."}
	print("BOSS_EMBEDDED_EFFECTS ", JSON.stringify(report))
	presentation.queue_free()
	reaper.queue_free()
	dragon.queue_free()
	restored.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _pressure(presentation: Node3D, reaper: DungeonActor, dragon: DungeonActor) -> void:
	reaper.dead = false
	presentation.low_quality = true
	presentation.effects_density = 0
	var cosmetic_budget: int = maxi(4, int(presentation.FEEL.low_effect_budget * 0.35))
	for index in cosmetic_budget:
		presentation.emit_effect(dragon, "budget_fixture_missing", Vector3.ZERO, Vector3.ONE, INF, null, true, -1, true)
	check(presentation.active.size() == cosmetic_budget, "Pressure fixture fills the cosmetic effect budget with protected effects")
	presentation.register_boss_embedded(reaper)
	await _flush(presentation)
	check(not presentation._boss_embedded_live.has(reaper.get_instance_id()), "Default roots do not displace protected effects under pressure")
	var attempts: int = presentation.authored_builds
	var count: int = presentation.spawned
	for frame in 300: presentation._process(1.0 / 60.0)
	check(presentation.authored_builds == attempts and presentation.spawned == count and presentation._boss_embedded_queue.is_empty(), "Full-budget defaults do not retry every frame")
	while not presentation.active.is_empty(): presentation._recycle(presentation.active.size() - 1)
	for frame in 180: presentation._process(1.0 / 60.0)
	check(not presentation._boss_embedded_live.get(reaper.get_instance_id(), {}).is_empty(), "A default root recovers after budget pressure clears")
	check(presentation._active_particles <= presentation.FEEL.low_particle_budget and presentation._active_emitters <= presentation.FEEL.low_emitter_budget, "Low-quality recovery remains within hard limits")
	presentation.clear()
