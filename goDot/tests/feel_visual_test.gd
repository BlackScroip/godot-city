extends SceneTree

var scene: Node
var world: DungeonWorld
var frames := 0
var samples: Array[float] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	scene = load("res://scenes/main.tscn").instantiate()
	scene.save_store = DungeonSaveStore.new("res://reports/feel-visual-profile.json")
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	world = scene.world
	world.set_physics_process(false)
	world.load_environment(-1)
	if world.environment_root:
		world.environment_root.queue_free()
	world.environment_entry = {}
	world._camera_offset = Vector3(0, 12, -10)
	world.camera.size = 12
	var ground = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(80, 80)
	ground.mesh = plane
	var material = StandardMaterial3D.new()
	material.albedo_color = Color("435b51")
	material.roughness = 1
	ground.material_override = material
	world.add_child(ground)
	var floor_body = StaticBody3D.new()
	var floor_shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(80, 1, 80)
	floor_shape.shape = box
	floor_body.position.y = -0.5
	floor_body.add_child(floor_shape)
	world.add_child(floor_body)
	var rows: Array = []
	for id in range(1, 8):
		world.presentation.clear()
		for projectile in world.projectiles: projectile.visual.queue_free()
		world.projectiles.clear()
		for unit in world.summon_units:
			if is_instance_valid(unit.get("visual")): unit.visual.queue_free()
		world.summon_units.clear()
		for actor in world.actors: actor.queue_free()
		world.actors.clear()
		await process_frame
		var combat = load("res://scripts/domain/combat.gd").new()
		combat.configure(null, null, id)
		if id == 4: combat.add_buff(str(combat.fighter.jp), 30)
		var actor = world.create_player(combat, id, Vector3.ZERO)
		actor.face_direction(Vector3.FORWARD)
		var weapons: Dictionary = world.catalog.weapons
		for weapon_id in weapons:
			if int(weapon_id) / 100 == id:
				actor.equip_weapon(world.asset_path("weapons", weapon_id))
				break
		var target = DungeonActor.new()
		target.actor_id = 11001
		target.combat = load("res://scripts/domain/combat.gd").new()
		target.combat.configure_enemy(11001)
		target.combat.max_health = 100000
		target.combat.health = 100000
		world.add_child(target)
		target.position = Vector3(0, 0, -1.6)
		target.set_visual(world.asset_path("enemies", 11001))
		world.actors.append(target)
		var best := 0
		var hit_start: int = world.presentation.impacts
		var spawned_start: int = world.presentation.spawned
		for slot in [0, 2, 3, 4, 1]:
			combat.busy = 0
			combat.cooldowns[slot] = 0
			combat.energy[slot] = combat.fighter.skills[slot].maxSp
			combat.request_attack(slot)
			for step in range(maxi(90, int(combat.busy * 60) + 20)):
				var started = Time.get_ticks_usec()
				if step == 40 and slot == 4: combat.request_attack(4, false)
				combat.tick(1.0 / 60)
				for event in combat.drain_events(): world._consume(actor, event)
				actor._physics_process(1.0 / 60)
				world._tick_projectiles(1.0 / 60)
				world._tick_summons(1.0 / 60)
				scene.hud.update_combat(combat, false)
				scene.hud.update_state("技能演练", combat.health, combat.max_health, "", "", "")
				await process_frame
				frames += 1
				if step > 10: samples.append((Time.get_ticks_usec() - started) / 1000.0)
				if world.presentation.active.size() > best and step > 2:
					best = world.presentation.active.size()
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png("res://reports/feel-character-%d.png" % id)
			actor.position = Vector3.ZERO
			actor.impulse = Vector3.ZERO
			actor.locomotion = Vector3.ZERO
			actor.face_direction(Vector3.FORWARD)
		rows.append({"character": id, "effects": world.presentation.spawned - spawned_start, "impacts": world.presentation.impacts - hit_start, "peak_effects": best})
	samples.sort()
	var report = {"characters": rows, "frames": frames, "frame_ms_p50": samples[int(samples.size() * 0.5)], "frame_ms_p95": samples[int(samples.size() * 0.95)], "missing": world.presentation.missing.keys(), "scope": "Controlled desktop presentation arena, not phone acceptance or original VFX equivalence"}
	FileAccess.open("res://reports/feel-visual.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("FEEL_VISUAL ", JSON.stringify(report))
	scene.queue_free()
	await process_frame
	quit()
