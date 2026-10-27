extends "res://tests/impact_visual_test.gd"

const SPIRIT_CASES := [
	{"name": "lightning", "buff": "50202420", "frames": 260, "shots": [185, 200]},
	{"name": "water", "buff": "50202200", "frames": 200, "shots": [125, 155]},
	{"name": "magnetic", "buff": "50203400", "frames": 440, "shots": [335, 380]},
	{"name": "firethunder", "buff": "50202800", "frames": 420, "shots": [125, 335]}
]

func _run() -> void:
	var viewport := _arg("viewport", "960x540").split("x")
	root.size = Vector2i(int(viewport[0]), int(viewport[1]))
	world = DungeonWorld.new()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.presentation.set_process(false)
	world.presentation.audio_enabled = false
	world.low_effects = _arg("quality", "full") == "low"
	_ground()
	world.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	world.camera.size = 14
	world.camera.position = Vector3(9, 13, -14)
	world.camera.look_at(Vector3(0, 0, 1))
	for scenario in SPIRIT_CASES:
		if not _arg("shot", "").is_empty() and _arg("shot", "") != scenario.name: continue
		await _scenario(scenario)
	var report := {"passed": failures.is_empty(), "failures": failures, "rendered": DisplayServer.get_name() != "headless", "viewport": str(root.size), "quality": _arg("quality", "full"), "scenarios": rows, "missing_effects": world.presentation.missing.keys(), "scope": "Recovered spirit skills through real world hit, buff, entity and summon dispatch with stationary source actors. Captures and pixel variation verify rendering, not Unity pixel equivalence or device FPS."}
	FileAccess.open("res://reports/spirit-skill-visual-%s-%s.json" % [_arg("viewport", "960x540"), _arg("quality", "full")], FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("SPIRIT_SKILL_VISUAL ", JSON.stringify(report))
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _scenario(scenario: Dictionary) -> void:
	world.presentation.clear()
	world.pending_attack_entities.clear()
	world.active_attack_entities.clear()
	for projectile in world.projectiles: world._recycle_projectile(projectile)
	world.projectiles.clear()
	for unit in world.summon_units.duplicate(): world._dispose_summon(unit, false)
	for actor in world.actors: actor.queue_free()
	world.actors.clear()
	world._actor_index.clear()
	world.player = null
	await process_frame
	var combat := DungeonCombat.new()
	combat.configure(null, null, 1, 0, SEED)
	combat.actor_key = "spirit-player"
	combat.add_buff(str(scenario.buff))
	var player := world.create_player(combat, 1, Vector3.ZERO)
	player.face_direction(Vector3.BACK)
	var targets: Array[DungeonActor] = []
	for index in 3:
		var target := DungeonActor.new()
		target.actor_id = 11001
		target.combat = DungeonCombat.new()
		target.combat.configure_enemy(11001, SEED + index)
		target.combat.actor_key = "spirit-target:%d" % index
		target.combat.max_health = 1000000000
		target.combat.health = target.combat.max_health
		world.add_child(target)
		target.position = [Vector3(0, 0, 3), Vector3(-3.2, 0, 2), Vector3(3.2, 0, 2)][index]
		target.previous_position = target.position
		target.set_visual(world.asset_path("enemies", 11001), world.catalog.enemies["11001"])
		world.actors.append(target)
		target.set_process(false)
		target.set_physics_process(false)
		targets.append(target)
	world.presentation.prepare_combat([combat])
	while world.presentation.has_pending_preparation():
		world.presentation.prepare_step()
		await process_frame
	await physics_frame
	await process_frame
	world.camera.position = Vector3(9, 13, -14)
	world.camera.look_at(Vector3(0, 0, 1))
	var before: int = world.presentation.spawned
	var before_impacts: int = world.presentation.impacts
	var baseline: Image
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		baseline = root.get_texture().get_image()
	var styles: Dictionary = {}
	var captures: Array = []
	var peak_particles := 0
	var peak_emitters := 0
	for frame in int(scenario.frames):
		if scenario.name == "water":
			if frame in [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]: _input_hit(targets[0], "NormalAtk", frame)
			if frame == 110: _input_hit(targets[0], "SpecAtk", frame)
		elif scenario.name == "magnetic" and frame == 10: _input_hit(targets[0], "DodgeAtk", frame)
		combat.custom_properties["EnemyDistances"] = targets.map(func(target): return target.position.distance_to(player.position))
		for actor in world.actors: actor.combat.tick(1.0 / HZ)
		for actor in world.actors:
			for event in actor.combat.drain_events(): world._consume(actor, event)
		world._tick_attack_entities(1.0 / HZ)
		world._tick_projectiles(1.0 / HZ)
		world._tick_summons(1.0 / HZ)
		world.presentation.sync_buffs(world.actors)
		world.presentation._process(1.0 / HZ)
		for effect in world.presentation.active: styles[effect.key] = true
		peak_particles = maxi(peak_particles, world.presentation._active_particles)
		peak_emitters = maxi(peak_emitters, world.presentation._active_emitters)
		await process_frame
		if frame in scenario.shots and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var capture := root.get_texture().get_image()
			var path := "res://reports/spirit-skill-%s-%s-%s-%d.png" % [scenario.name, _arg("viewport", "960x540"), _arg("quality", "full"), frame]
			capture.save_png(path)
			var changed := _changed_pixels(baseline, capture)
			if changed < 20: failures.append("No visible rendering change in " + path)
			captures.append({"frame": frame, "path": path, "changed_sample_pixels": changed})
	var effects: int = world.presentation.spawned - before
	var contacts: int = world.presentation.impacts - before_impacts
	if effects <= 0 or contacts <= 0: failures.append("Missing spirit effects or actual contacts: " + str(scenario.name))
	if peak_particles > (world.FEEL.low_particle_budget if world.low_effects else world.FEEL.particle_budget): failures.append("Spirit particle budget exceeded: " + str(scenario.name))
	if peak_emitters > (world.FEEL.low_emitter_budget if world.low_effects else world.FEEL.emitter_budget): failures.append("Spirit emitter budget exceeded: " + str(scenario.name))
	rows.append({"name": scenario.name, "buff": scenario.buff, "effects": effects, "contacts": contacts, "styles": styles.keys(), "peak_particles": peak_particles, "peak_emitters": peak_emitters, "captures": captures})

func _input_hit(target: DungeonActor, act_type: String, frame: int) -> void:
	# Controlled input contacts charge the source skill; its children use world dispatch.
	var hit := {"damage": 1.0, "source": world.player.combat, "sequence": frame, "emission": "visual-input:%d" % frame, "definition": {"actType": act_type}}
	target.combat.receive(hit, world.player.combat.attack)
	world.player.combat.confirm_hit(hit)

func _changed_pixels(before: Image, after: Image) -> int:
	var changed := 0
	for y in range(0, after.get_height(), 4):
		for x in range(0, after.get_width(), 4):
			if before.get_pixel(x, y) != after.get_pixel(x, y): changed += 1
	return changed
