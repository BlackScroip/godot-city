extends SceneTree

var failures: Array[String] = []
var checks := 0
var captures: Array[String] = []
var canvas: SubViewport
var world: DungeonWorld

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _run() -> void:
	canvas = SubViewport.new()
	canvas.size = Vector2i(2460, 1080)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var display = TextureRect.new()
	display.texture = canvas.get_texture()
	display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	root.add_child(display)
	world = DungeonWorld.new()
	canvas.add_child(world)
	world.set_physics_process(false)
	world.set_process(false)
	world.presentation.set_process(false)
	world.presentation.audio_enabled = false
	world.load_environment(1010101)
	var combat = load("res://scripts/domain/combat.gd").new()
	combat.configure(null, null, 1)
	var player = world.create_player(combat, 1)
	player.equip_weapon(world.asset_path("weapons", 101))
	world.camera.size = 19
	world.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	world.camera.position = player.position + Vector3.UP * 0.4 + world._camera_offset
	world.camera.look_at(player.position + Vector3.UP * 0.4)
	await capture("before")
	world.camera.size = world.FEEL.level_camera_height
	world.camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	for dimensions in [Vector2i(2460, 1080), Vector2i(1280, 720), Vector2i(844, 390), Vector2i(1200, 900)]:
		canvas.size = dimensions
		world.snap_camera()
		await process_frame
		var foot = world.camera.unproject_position(player.position) / Vector2(dimensions)
		var head = world.camera.unproject_position(player.position + Vector3.UP * 1.8) / Vector2(dimensions)
		check(absf(foot.x - 0.5) < 0.001 and absf(foot.y - 0.58) < 0.001, "Player anchor matches reference " + str(dimensions))
		check(foot.y - head.y > 0.12 and foot.y - head.y < 0.15, "Character scale remains consistent " + str(dimensions))
		check(is_equal_approx(world.camera.global_basis.z.dot(Vector3.UP), sin(deg_to_rad(45))), "Authored camera elevation retained")
		var ground_forward = -world.camera.basis.z
		ground_forward.y = 0
		ground_forward = ground_forward.normalized()
		var right = world.camera.basis.x
		var near_point = player.position - ground_forward * 2
		var far_point = player.position + ground_forward * 2
		var near_width = world.camera.unproject_position(near_point + right).distance_to(world.camera.unproject_position(near_point - right))
		var far_width = world.camera.unproject_position(far_point + right).distance_to(world.camera.unproject_position(far_point - right))
		check(near_width > far_width * 1.15, "Ground perspective matches the reference trapezoid " + str(dimensions))
		await capture("after-%dx%d" % [dimensions.x, dimensions.y])
	canvas.size = Vector2i(2460, 1080)
	world.snap_camera()
	var forward = -world.camera.basis.z
	forward.y = 0
	forward = forward.normalized()
	world.spawn_wave([{"enemy_id": 11005, "position": player.position - forward * 2.0}], 0, 123)
	var enemy: DungeonActor = world.actors.back()
	enemy.face_direction(forward)
	enemy.visual.rotation.y = atan2(forward.x, forward.z)
	var action: Dictionary = enemy.combat._action(str(enemy.combat.enemy.group), "attack")
	enemy.combat._start(action, 0)
	for event in enemy.combat.drain_events(): world._consume(enemy, event)
	enemy.combat.tick(0.21)
	for event in enemy.combat.drain_events(): world._consume(enemy, event)
	check(world.presentation.telegraphs.size() == 1, "Recovered charge warning replaces generic VFX exactly once")
	if not world.presentation.telegraphs.is_empty():
		var entry: Dictionary = world.presentation.telegraphs[0]
		check(entry.node.dimensions.is_equal_approx(Vector2(2.5, 15)), "Charge uses original 2.5 by 15 warning dimensions")
		var near_edge: Vector3 = entry.node.position - forward * 7.5
		check(Vector2(near_edge.x, near_edge.z).distance_to(Vector2(enemy.position.x, enemy.position.z)) < 0.001, "Forward rectangle begins at monster feet")
		enemy.combat.action_elapsed = 1.1
		world.presentation._process(0.016)
		await capture("charge-warning")
		enemy.position += Vector3.RIGHT
		enemy.face_direction(Vector3.RIGHT)
		world.presentation._process(0.016)
		check(enemy.facing.is_equal_approx(forward), "Warning locks the monster's attack direction")
		check((entry.node.position - enemy.position - Vector3.UP * 0.12).is_equal_approx(forward * 7.5), "Warning keeps its locked direction when the monster moves")
		var phase: float = entry.node.material.get_shader_parameter("progress")
		world.presentation.suspended = true
		world.presentation._process(10.0)
		check(is_equal_approx(entry.node.material.get_shader_parameter("progress"), phase), "Pause keeps telegraph timing stable")
		world.presentation.suspended = false
		world.presentation.low_quality = true
		check(entry.node.visible, "Low effects keeps gameplay warning visible")
		world.presentation.cancel_actor(enemy)
		check(world.presentation.telegraphs.is_empty(), "Interrupted attack immediately removes warning")
		enemy.face_direction(Vector3.RIGHT)
		check(enemy.facing.is_equal_approx(Vector3.RIGHT), "Interruption releases the direction lock")
	var warning = {"EffectName": "fx_other_enemyatkrange120.prefab", "Scale": {"x": 1, "y": 1, "z": 1}, "Euler": {"y": 180}}
	world.presentation.trigger(enemy, warning, enemy.combat._cast_sequence)
	check(world.presentation.telegraphs[0].node.shape == 2, "Fan warning retains sector shape")
	world.presentation.clear()
	check(world.presentation.telegraphs.is_empty(), "Room transitions clear every warning")
	world.presentation.trigger(enemy, warning, enemy.combat._cast_sequence)
	enemy.combat.action_elapsed += 2.0
	world.presentation._process(0.016)
	check(world.presentation.telegraphs.is_empty(), "Warning expires on the action clock")
	warning.EffectName = "fx_other_enemyatkrange360.prefab"
	world.presentation.trigger(enemy, warning, enemy.combat._cast_sequence)
	enemy.dead = true
	world.presentation._process(0.016)
	check(world.presentation.telegraphs.is_empty(), "Monster death clears warning")
	if DisplayServer.get_name() != "headless":
		enemy.dead = false
		enemy.position = Vector3(250, 0, 250)
		enemy.face_direction(Vector3.FORWARD)
		player.position = enemy.position + Vector3.RIGHT * 5
		var floor_mesh = MeshInstance3D.new()
		var plane = PlaneMesh.new()
		plane.size = Vector2(30, 30)
		floor_mesh.mesh = plane
		var surface = StandardMaterial3D.new()
		surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		surface.albedo_color = Color(0.25, 0.3, 0.3)
		floor_mesh.material_override = surface
		floor_mesh.position = enemy.position - Vector3.UP * 0.02
		world.add_child(floor_mesh)
		world.camera.position = enemy.position + world._camera_offset
		world.camera.look_at(enemy.position)
		warning.EffectName = "fx_other_enemyatkrange120.prefab"
		world.presentation.trigger(enemy, warning, enemy.combat._cast_sequence)
		enemy.combat.action_elapsed += 0.7
		world.presentation._process(0.016)
		await capture("sector-direction")
		var frame = canvas.get_texture().get_image()
		var inside = world.camera.unproject_position(enemy.position + Vector3.FORWARD * 1.5)
		var outside = world.camera.unproject_position(enemy.position + Vector3.BACK * 1.9)
		var red = frame.get_pixelv(Vector2i(inside))
		var ground = frame.get_pixelv(Vector2i(outside))
		check(red.r > red.g * 1.5, "Rendered sector fills the attack's forward direction")
		check(ground.r < ground.g * 1.2, "Rendered sector leaves the rear direction clear")
	var report = {"passed": failures.is_empty(), "checks": checks, "failures": failures, "captures": captures}
	FileAccess.open("res://reports/level-framing.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("LEVEL_FRAMING ", JSON.stringify(report))
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	for step in 5: await process_frame
	await RenderingServer.frame_post_draw
	var path = "res://reports/level-" + label + ".png"
	canvas.get_texture().get_image().save_png(path)
	captures.append(path)
