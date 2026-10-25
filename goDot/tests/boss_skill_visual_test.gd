extends "res://tests/impact_visual_test.gd"

const CASES = {
	13001: "Attack_EX1", 23001: "attack7", 33001: "EX_Attack3",
	43001: "EX_Attack3", 52001: "attack6", 52003: "ComboAttack2", 53001: "attack5"
}

func _run() -> void:
	root.size = Vector2i(960, 540)
	world = DungeonWorld.new()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.presentation.set_process(false)
	world.presentation.audio_enabled = false
	_ground()
	world.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	world.camera.size = 22
	world.camera.position = Vector3(10, 14, -18)
	world.camera.look_at(Vector3(0, 0, 1))
	for low in [false, true]:
		if _arg("quality", "") != "" and low != (_arg("quality", "") == "low"): continue
		world.low_effects = low
		for id in CASES:
			if _arg("boss", "") != "" and int(_arg("boss", "0")) != int(id): continue
			await _cast(int(id), str(CASES[id]), low)
	var report = {"shots": rows, "failures": failures, "passed": failures.is_empty(), "rendered": DisplayServer.get_name() != "headless", "scope": "Seven bosses cast recovered skills in full/reduced quality with real world projectile, summon, hit and warning paths. Desktop rendering and scripted simulation timings; no mobile device FPS claim."}
	FileAccess.open("res://reports/boss-skill-visual.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("BOSS_SKILL_VISUAL ", JSON.stringify(report))
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _cast(id: int, action: String, low: bool) -> void:
	world.presentation.clear()
	for projectile in world.projectiles:
		if is_instance_valid(projectile.visual): projectile.visual.queue_free()
	world.projectiles.clear()
	for unit in world.summon_units:
		if is_instance_valid(unit.get("visual")): unit.visual.queue_free()
	world.summon_units.clear()
	for actor in world.actors: actor.queue_free()
	world.actors.clear()
	world.player = null
	await process_frame
	var combat := DungeonCombat.new()
	combat.configure()
	combat.max_health = 1000000000
	combat.health = combat.max_health
	var player = world.create_player(combat, 1, Vector3(0, 0, 4))
	world.spawn_wave([{"enemy_id": id, "position": Vector3(0.1, 0, 0.1)}], 0, SEED)
	var boss: DungeonActor = world.actors.back()
	boss.face_direction(Vector3.BACK)
	if id == 13001: boss.combat.add_buff("41300101", 1)
	while world.presentation.has_pending_preparation():
		world.presentation.prepare_step()
		await process_frame
	await physics_frame
	var definition = boss.combat._action(str(boss.combat.enemy.group), action)
	if definition.is_empty():
		failures.append("Missing boss action %d %s" % [id, action])
		return
	var before_builds: int = world.presentation.authored_builds
	var before_spawned: int = world.presentation.spawned
	boss.combat._start(definition, 0)
	var timings: Array[float] = []
	var max_emitters := 0
	var max_particles := 0
	var max_warnings := 0
	var slow_frames: Array[Dictionary] = []
	var frames = maxi(300, int(float(definition.duration) * HZ) + 30)
	for frame in frames:
		var started = Time.get_ticks_usec()
		var event_costs: Array[Dictionary] = []
		for actor in world.actors.duplicate():
			actor.combat.custom_properties["EnemyDistances"] = [actor.position.distance_to(player.position)]
			actor.combat.tick(1.0 / HZ)
			for event in actor.combat.drain_events():
				var before_event = Time.get_ticks_usec()
				world._consume(actor, event)
				var event_ms = (Time.get_ticks_usec() - before_event) / 1000.0
				if event_ms > 4: event_costs.append({"type": event.type, "command": event.get("command", {}).get("type", ""), "ms": event_ms})
		var after_events = Time.get_ticks_usec()
		for actor in world.actors: actor._physics_process(1.0 / HZ)
		var after_actors = Time.get_ticks_usec()
		world._tick_projectiles(1.0 / HZ)
		world._tick_summons(1.0 / HZ)
		var after_transients = Time.get_ticks_usec()
		world.presentation._process(1.0 / HZ)
		world.camera.position = boss.position + Vector3(10, 14, -18)
		world.camera.look_at(boss.position + Vector3(0, 0, 1))
		timings.append((Time.get_ticks_usec() - started) / 1000.0)
		if timings.back() > 10: slow_frames.append({"frame": frame, "events_ms": (after_events - started) / 1000.0, "actors_ms": (after_actors - after_events) / 1000.0, "transients_ms": (after_transients - after_actors) / 1000.0, "presentation_ms": (Time.get_ticks_usec() - after_transients) / 1000.0, "events": event_costs})
		max_particles = maxi(max_particles, world.presentation._active_particles)
		max_emitters = maxi(max_emitters, world.presentation._active_emitters)
		max_warnings = maxi(max_warnings, world.presentation.telegraphs.size())
		await process_frame
		if frame in [35, 75, 165] and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://reports/boss-skill-%d-%s-%d.png" % [id, "low" if low else "full", frame])
	timings.sort()
	var new_builds: int = world.presentation.authored_builds - before_builds
	if world.presentation.spawned <= before_spawned: failures.append("No effects in boss skill %d (%s)" % [id, low])
	if new_builds > 0: failures.append("Boss %d builds %d unprepared effects during casting (%s)" % [id, new_builds, low])
	if max_particles > (world.FEEL.low_particle_budget if low else world.FEEL.particle_budget) or max_emitters > (world.FEEL.low_emitter_budget if low else world.FEEL.emitter_budget): failures.append("Boss %d exceeds effect budget (%s)" % [id, low])
	rows.append({"boss": id, "action": action, "low_quality": low, "effects": world.presentation.spawned - before_spawned, "peak_emitters": max_emitters, "peak_particles": max_particles, "peak_warnings": max_warnings, "runtime_effect_builds": new_builds, "simulation_p95_ms": timings[int(frames * 0.95)], "simulation_max_ms": timings.back(), "slow_frames": slow_frames})
