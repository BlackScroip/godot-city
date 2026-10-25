extends SceneTree

const Combat = preload("res://scripts/domain/combat.gd")
const SEED := 731
const HZ := 60
const SHOT_FRAMES := 240
var world: DungeonWorld
var label: Label
var rows: Array[Dictionary] = []
var cpu_ms: Array[float] = []
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _arg(name: String, fallback: String) -> String:
	for value in OS.get_cmdline_user_args():
		if value.begins_with("--%s=" % name): return value.get_slice("=", 1)
	return fallback

func _run() -> void:
	root.size = Vector2i(960, 540)
	Engine.physics_ticks_per_second = HZ
	seed(SEED)
	world = DungeonWorld.new()
	root.add_child(world)
	world.set_physics_process(false)
	world._camera_offset = Vector3(0, 10, -9)
	world.camera.size = 10
	world.paused = false
	world._background = false
	world.fighting = true
	world.low_effects = _arg("quality", "full") == "low"
	_ground()
	var canvas := CanvasLayer.new()
	root.add_child(canvas)
	label = Label.new()
	label.position = Vector2(24, 18)
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	canvas.add_child(label)
	var shots: Array[Dictionary] = [
		{"name": "sword-single", "title": "SWORD / SINGLE TARGET", "character": 1, "slot": 0, "enemy": 11001, "points": [Vector3(0, 0, 2.4)]},
		{"name": "axe-group", "title": "AXE / HEAVY GROUP IMPACT", "character": 3, "slot": 3, "enemy": 11001, "points": [Vector3(-1.2, 0, 1.6), Vector3(0, 0, 1.6), Vector3(1.2, 0, 1.6)]},
		{"name": "orb-explosion", "title": "ORB / DISCRETE EXPLOSION", "character": 6, "slot": 0, "enemy": 11001, "points": [Vector3(-0.9, 0, 2.8), Vector3(0, 0, 2.8), Vector3(0.9, 0, 2.8)]},
		{"name": "sword-boss", "title": "SWORD / BOSS RESISTANCE", "character": 1, "slot": 3, "enemy": 13001, "points": [Vector3(0, 0, 2.1)]},
		{"name": "wand-ranged", "title": "WAND / RANGED CONTACT", "character": 4, "slot": 0, "enemy": 11001, "points": [Vector3(0, 0, 3.5)]}
	]
	for shot in shots:
		if not _arg("shot", "").is_empty() and str(shot.name) != _arg("shot", ""): continue
		await _shot(shot)
	cpu_ms.sort()
	var report := {
		"schema": 1, "label": _arg("label", "current"), "seed": SEED, "hz": HZ,
		"viewport": str(root.size), "quality": _arg("quality", "full"), "shots": rows, "failures": failures,
		"simulation_cpu_ms_p50": cpu_ms[int(cpu_ms.size() * 0.5)],
		"simulation_cpu_ms_p95": cpu_ms[int(cpu_ms.size() * 0.95)],
		"missing_effects": world.presentation.missing.keys(),
		"scope": "Same authored attacks, seed, equipment, target positions and fixed simulation steps before/after. Enemy AI is disabled so contact reactions are visible. Dummy target HP is raised, player statistics and resource costs remain original. CPU samples cover scripted simulation only; MovieWriter changes rendering cost and this is not a device FPS benchmark."
	}
	FileAccess.open("res://reports/impact-visual-%s.json" % report.label, FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("IMPACT_VISUAL ", JSON.stringify(report))
	world.queue_free()
	canvas.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _ground() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 1, 80)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -0.5
	world.add_child(floor_body)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	ground.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("49645c")
	material.roughness = 1.0
	ground.material_override = material
	world.add_child(ground)

func _shot(shot: Dictionary) -> void:
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
	world._camera_impulses.clear()
	world.restore_transients({})
	await process_frame
	seed(SEED)
	var combat := Combat.new()
	combat.configure(null, null, int(shot.character), 0, SEED)
	if shot.has("ultimate_energy"): combat.energy[3] = float(shot.ultimate_energy)
	var player := world.create_player(combat, int(shot.character), Vector3.ZERO)
	player.face_direction(Vector3.BACK)
	for key in world.catalog.weapons:
		if int(key) / 100 == int(shot.character):
			player.equip_weapon(world.asset_path("weapons", key))
			break
	for index in shot.points.size():
		var target := DungeonActor.new()
		target.actor_id = int(shot.enemy)
		target.combat = Combat.new()
		target.combat.configure_enemy(target.actor_id, SEED + index)
		target.combat.actor_key = "fixture:%d" % index
		target.combat.max_health = 1000000
		target.combat.health = target.combat.max_health
		world.add_child(target)
		target.position = shot.points[index] + Vector3.UP * 0.05
		target.previous_position = target.position
		target.set_visual(world.asset_path("enemies", target.actor_id), world.catalog.enemies.get(str(target.actor_id), {}))
		target.face_direction(Vector3.FORWARD)
		world.actors.append(target)
	await physics_frame
	await process_frame
	var start_impacts: int = world.presentation.impacts
	var start_effects: int = world.presentation.spawned
	var max_effects := 0
	var damage := 0.0
	var contacts_at: Array[int] = []
	var previous_impacts := start_impacts
	var first_contact_saved := false
	var released := false
	var action_trace: Array[String] = []
	var frames = int(shot.get("frames", SHOT_FRAMES))
	label.text = "%s   |   %s" % [_arg("label", "current").to_upper(), shot.title]
	for frame in frames:
		var started := Time.get_ticks_usec()
		if frame == 30:
			if int(shot.get("resource", 0)) > 0: combat.add_buff(str(combat.fighter.jp), int(shot.resource))
			for buff in shot.get("buffs", []): combat.add_buff(str(buff))
		if frame >= 30 and not combat.is_busy():
			if int(shot.slot) == 0 or frame == 30: world._execute_player(int(shot.slot))
		if int(shot.slot) == 4 and not released and frame >= 30 + int(float(shot.get("release", 0.75)) * HZ):
			combat.request_attack(4, false)
			released = true
		for actor in world.actors:
			actor.desired_velocity = Vector3.ZERO
			if actor.is_player:
				for move in shot.get("moves", []):
					if frame >= int(move.start) and frame < int(move.end): actor.desired_velocity = move.direction * actor.combat.move_speed
			actor.combat.custom_properties.InputMove = actor.desired_velocity.length_squared() > 0.01
			actor.combat.custom_properties["EnemyDistances"] = [actor.position.distance_to(player.position)]
			actor.combat.tick(1.0 / HZ)
			for event in actor.combat.drain_events():
				if actor.is_player and event.type == "action_started": action_trace.append(event.action)
				world._consume(actor, event)
		for actor in world.actors:
			actor._physics_process(1.0 / HZ)
		world._tick_projectiles(1.0 / HZ)
		world._tick_summons(1.0 / HZ)
		cpu_ms.append((Time.get_ticks_usec() - started) / 1000.0)
		max_effects = maxi(max_effects, world.presentation.active.size())
		if world.presentation.impacts > previous_impacts:
			contacts_at.append(frame)
			previous_impacts = world.presentation.impacts
		await process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
		if not contacts_at.is_empty() and not first_contact_saved and DisplayServer.get_name() != "headless":
			first_contact_saved = true
			root.get_texture().get_image().save_png("res://reports/impact-%s-%s-contact.png" % [_arg("label", "current"), shot.name])
		elif frame in [55, 95, 150] and DisplayServer.get_name() != "headless":
			root.get_texture().get_image().save_png("res://reports/impact-%s-%s-%d.png" % [_arg("label", "current"), shot.name, frame])
	var positions: Array[Dictionary] = []
	for actor in world.actors:
		if actor.is_player: continue
		damage += actor.combat.max_health - actor.combat.health
		positions.append({"id": actor.actor_id, "position": {"x": actor.position.x, "y": actor.position.y, "z": actor.position.z}})
	var hits: int = world.presentation.impacts - start_impacts
	if hits == 0 and shot.get("require_contact", true): failures.append("No contacts in " + str(shot.name))
	rows.append({"name": shot.name, "character": shot.character, "slot": shot.slot, "enemy": shot.enemy, "frames": frames, "actions": action_trace, "damage": damage, "impacts": hits, "effects": world.presentation.spawned - start_effects, "peak_effects": max_effects, "contact_frames": contacts_at, "target_end_positions": positions, "player_end_position": str(player.position)})
