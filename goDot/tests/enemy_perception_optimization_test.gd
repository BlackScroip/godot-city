extends SceneTree

class CountingWorld extends DungeonWorld:
	var perception_checks := 0
	func _line_blocked(actor: DungeonActor, distance_squared: float) -> bool:
		perception_checks += 1
		return super._line_blocked(actor, distance_squared)

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value and failures.size() < 40: failures.append(message)

func _scan_flags(value: Variant, variables: Dictionary, flags: Dictionary) -> void:
	if value is Array:
		for child in value: _scan_flags(child, variables, flags)
	elif value is Dictionary:
		var type := str(value.get("$type", ""))
		if type.contains("NCCondition_CheckTargetLineCollisionWall"): flags.wall = true
		if type.contains("NCCondition_RoleUnit_CheckBuffExist"):
			var binding: Dictionary = value.get("SelfGo", {})
			var name := str(binding.get("_name", ""))
			var id := str(binding.get("_targetVariableID", ""))
			if variables.has(id): name = str(variables[id])
			flags["target" if name == "IP_Target" else "self"] = true
		for key in value:
			if key != "_value": _scan_flags(value[key], variables, flags)

func _check_graph_flags(catalog: Dictionary) -> void:
	var ai := DungeonEnemyAI.new()
	for graph_name in catalog.ai_graphs:
		var graph: Dictionary = catalog.ai_graphs[graph_name]
		var variables: Dictionary = {}
		for name in graph.get("localBlackboard", {}).get("_variables", {}):
			var variable: Dictionary = graph.localBlackboard._variables[name]
			variables[str(variable.get("_id", ""))] = str(name)
		var expected := {"wall": false, "target": false, "self": false}
		for node in graph.get("nodes", []):
			if node.has("$id"): _scan_flags(node, variables, expected)
		check(ai.configure({"ai": graph_name}, graph), "AI graph configures: %s" % graph_name)
		check(ai.needs_wall_query == expected.wall, "Wall input detection: %s" % graph_name)
		check(ai.needs_target_buffs == expected.target, "Target buff detection: %s" % graph_name)
		check(ai.needs_self_buffs == expected.self, "Self buff detection: %s" % graph_name)

func _make_world(reference: bool) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 360)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	var world := CountingWorld.new()
	viewport.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.presentation.set_process(false)
	world.presentation.audio_enabled = false
	world.auto_attack_enabled = false
	var floor := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(40, 1, 40)
	floor_shape.shape = floor_box
	floor.add_child(floor_shape)
	world.add_child(floor)
	floor.position.y = -0.5
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(0.5, 3, 4)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	world.add_child(wall)
	wall.position = Vector3(3.5, 1.5, 2)
	var region := NavigationRegion3D.new()
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-19, 0, -19), Vector3(-19, 0, 19), Vector3(19, 0, 19), Vector3(19, 0, -19)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_mesh = mesh
	world.add_child(region)
	NavigationServer3D.map_force_update(world.get_world_3d().navigation_map)
	var player_combat := DungeonCombat.new()
	player_combat.configure()
	player_combat.max_health = 10000000.0
	player_combat.health = player_combat.max_health
	world.create_player(player_combat, 1, Vector3.ZERO)
	var spawns: Array = []
	for index in 8:
		var angle := TAU * float(index) / 8.0
		spawns.append({"enemy_id": 11001, "position": [sin(angle) * 5.0, 0, cos(angle) * 5.0]})
	spawns.append({"enemy_id": 11002, "position": [7, 0, 2]})
	spawns.append({"enemy_id": 90001, "position": [7, 0, -3]})
	world.spawn_wave(spawns, 0, 731)
	world.actors.back().combat.health *= 0.7
	if reference:
		for actor in world.actors:
			if not actor.is_player:
				actor.combat.enemy_ai.needs_wall_query = true
				actor.combat.enemy_ai.needs_self_buffs = true
				actor.combat.enemy_ai.needs_target_buffs = true
	return {"viewport": viewport, "world": world, "wall": wall}

func _run() -> void:
	for name in ["move_left", "move_right", "move_up", "move_down"]:
		if not InputMap.has_action(name): InputMap.add_action(name)
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/combat.json"))
	_check_graph_flags(catalog)
	var reference := _make_world(true)
	var optimized := _make_world(false)
	var baseline: CountingWorld = reference.world
	var candidate: CountingWorld = optimized.world
	await physics_frame
	await physics_frame
	for frame in 360:
		await physics_frame
		if frame == 60:
			var first: DungeonActor = baseline._actor_by_key("enemy:90001:10")
			var second: DungeonActor = candidate._actor_by_key("enemy:90001:10")
			check(is_instance_valid(first) and is_instance_valid(second), "Slime remains active for self-buff comparison")
			if is_instance_valid(first) and is_instance_valid(second):
				first.combat.add_buff("900001")
				second.combat.add_buff("900001")
				check(first.combat.statuses.has("900001") and second.combat.statuses.has("900001"), "Slime self buff is active")
		if frame == 100:
			var first: DungeonActor = baseline._actor_by_key("enemy:90001:10")
			var second: DungeonActor = candidate._actor_by_key("enemy:90001:10")
			if is_instance_valid(first) and is_instance_valid(second):
				first.combat.remove_buff("900001")
				second.combat.remove_buff("900001")
		if frame == 120:
			reference.wall.position = Vector3(3.5, 1.5, -2)
			optimized.wall.position = reference.wall.position
		if frame == 180:
			baseline.player.combat.add_buff("70101113")
			candidate.player.combat.add_buff("70101113")
			check(baseline.player.combat.statuses.has("70101113") and candidate.player.combat.statuses.has("70101113"), "Target buff is active")
		if frame == 220:
			baseline.player.combat.remove_buff("70101113")
			candidate.player.combat.remove_buff("70101113")
		if frame == 240:
			baseline.player.position.x = 1.0
			candidate.player.position.x = 1.0
		baseline._physics_process(1.0 / 60.0)
		candidate._physics_process(1.0 / 60.0)
		check(baseline.actors.size() == candidate.actors.size(), "Actor count, frame %d" % frame)
		if baseline.actors.size() != candidate.actors.size(): break
		check(is_equal_approx(baseline.player.combat.health, candidate.player.combat.health), "Player health, frame %d" % frame)
		for index in range(1, baseline.actors.size()):
			var a: DungeonActor = baseline.actors[index]
			var b: DungeonActor = candidate.actors[index]
			check(a.combat.current_action == b.combat.current_action, "Enemy %d action, frame %d" % [index, frame])
			check(a.position.distance_to(b.position) < 0.001, "Enemy %d position, frame %d" % [index, frame])
			check(a.desired_velocity.distance_to(b.desired_velocity) < 0.001, "Enemy %d steering, frame %d" % [index, frame])
	check(candidate.perception_checks < baseline.perception_checks, "Unused wall queries are skipped")
	print("ENEMY_PERCEPTION_OPTIMIZATION ", JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures, "reference_queries": baseline.perception_checks, "optimized_queries": candidate.perception_checks, "scope": "Paired fixed-step worlds with eight wolves, a wall-sensitive bat and slime, a moving wall and player displacement; headless script/physics behavior, not mobile thermals or GPU."}))
	reference.viewport.queue_free()
	optimized.viewport.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
