extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var scene = load("res://scenes/main.tscn").instantiate()
	scene.save_store = DungeonSaveStore.new("res://reports/feel-continuous-profile.json")
	root.add_child(scene)
	await process_frame
	scene.set_process(false)
	var world: DungeonWorld = scene.world
	world.load_environment(-1)
	if world.environment_root: world.environment_root.queue_free()
	world.environment_entry = {}
	for actor in world.actors: actor.queue_free()
	world.actors.clear()
	await process_frame
	world._camera_offset = Vector3(0, 12, -10)
	world.camera.size = 12
	var floor_body = StaticBody3D.new()
	var shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(80, 1, 80)
	shape.shape = box
	floor_body.position.y = -0.5
	floor_body.add_child(shape)
	world.add_child(floor_body)
	var ground = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(80, 80)
	ground.mesh = plane
	var material = StandardMaterial3D.new()
	material.albedo_color = Color("435b51")
	ground.material_override = material
	world.add_child(ground)
	var combat = preload("res://scripts/domain/combat.gd").new()
	combat.configure()
	combat.max_health = 100000
	combat.health = combat.max_health
	var player = world.create_player(combat, 1, Vector3.ZERO)
	player.equip_weapon(world.asset_path("weapons", 101))
	for index in 3:
		var enemy = DungeonActor.new()
		enemy.actor_id = 11001
		enemy.combat = preload("res://scripts/domain/combat.gd").new()
		enemy.combat.configure_enemy(11001)
		enemy.combat.max_health = 100000
		enemy.combat.health = 100000
		world.add_child(enemy)
		enemy.position = Vector3((index - 1) * 2, 0, 3)
		enemy.set_visual(world.asset_path("enemies", 11001))
		world.actors.append(enemy)
	world.fighting = true
	world.paused = false
	world._background = false
	var accepted: Array[int] = []
	for frame in 1080:
		var phase = frame % 180
		if phase == 0:
			Input.action_release("move_down")
			Input.action_press("move_up")
		if phase == 45: Input.action_release("move_up")
		if phase == 75:
			combat.cooldowns[2] = 0
			combat.energy[2] = combat.fighter.skills[2].maxSp
			if world.use_skill(2).success: accepted.append(frame)
		if phase == 110: Input.action_press("move_down")
		if phase == 125:
			combat.cooldowns[1] = 0
			combat.energy[1] = combat.fighter.skills[1].maxSp
			if world.use_skill(1).success: accepted.append(frame)
		if phase == 155: Input.action_release("move_down")
		scene.hud.update_combat(combat, false)
		scene.hud.update_state("连续操作测试", combat.health, combat.max_health, "", "", "")
		await process_frame
		if frame == 480:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://reports/feel-continuous.png")
	Input.action_release("move_up")
	Input.action_release("move_down")
	var report = {"frames": 1080, "accepted_manual_inputs": accepted.size(), "impacts": world.presentation.impacts, "effects": world.presentation.spawned, "missing": world.presentation.missing.keys(), "scope": "Scripted desktop continuous combat; physical controls and subjective feel need user/device validation"}
	FileAccess.open("res://reports/feel-continuous.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("FEEL_CONTINUOUS ", JSON.stringify(report))
	scene.queue_free()
	await process_frame
	quit()
