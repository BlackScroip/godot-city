extends SceneTree

const Combat = preload("res://scripts/domain/combat.gd")
const Motion = preload("res://scripts/action_motion.gd")
var checks := 0
var failures: Array[String] = []
var rows: Array = []
var clock_rows: Array = []
var source_gap_rows: Array = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _run() -> void:
	var fixture = Combat.new()
	fixture.configure()
	for enemy in fixture.catalog.enemies:
		_behavior(enemy)
	_clock_matrix(fixture)
	_movement_cases(fixture)
	await _physical_point_cases()
	_generation_cases()
	_source_fallback_cases()
	var report = {"passed": failures.is_empty(), "checks": checks, "failures": failures, "behavior": rows, "segment_clocks": clock_rows, "known_source_gaps": source_gap_rows, "scope": "All 42 source behavior graphs integrated with authored interrupt windows. All 43 enabled enemy segment speed windows at 30/60/120Hz, point movement, collision flags, summon counts and snapshot replay. Exact known missing packaged references are retained separately; no replacement damage or action is invented. Static reconstruction tested locally; original APK runtime and mobile devices were not executed."}
	FileAccess.open("res://reports/monster-combat.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("MONSTER_COMBAT ", JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures, "enemies": rows.size(), "segment_actions": clock_rows.size()}))
	quit(0 if failures.is_empty() else 1)

func _behavior(enemy: Dictionary) -> void:
	var combat = Combat.new()
	check(combat.configure_enemy(int(enemy.id), 731).success, "Enemy %d configures" % int(enemy.id))
	var actions: Dictionary = {}
	var hits := 0
	var max_transitions := 0
	for frame in 3600:
		var distance = [12.0, 2.0, 6.0, 1.0][mini(3, frame / 900)]
		combat.health = combat.max_health * (1.0 if frame < 1800 else 0.25)
		combat.custom_properties["EnemyDistances"] = [distance]
		var before_sequence: int = combat._cast_sequence
		combat.tick_enemy_ai(1.0 / 60, {"target_available": true, "distance": distance, "line_blocked": false, "battle_time": float(frame) / 60, "monster_index": 0, "target_buffs": []})
		combat.tick(1.0 / 60)
		max_transitions = maxi(max_transitions, combat._cast_sequence - before_sequence)
		for event in combat.drain_events():
			if event.type == "action_started": actions[event.action] = true
			if event.type in ["hit", "projectile", "summon_spawned"]: hits += 1
		if frame == 1799:
			var saved = JSON.parse_string(JSON.stringify(combat.snapshot()))
			var replay = Combat.new()
			replay.configure_enemy(int(enemy.id), 731)
			check(replay.restore(saved), "Enemy %d combat and graph restore" % int(enemy.id))
			for step in 90:
				var context = {"target_available": true, "distance": 2.0, "line_blocked": false, "monster_index": 0}
				var first = combat.tick_enemy_ai(1.0 / 60, context)
				var second = replay.tick_enemy_ai(1.0 / 60, context)
				combat.tick(1.0 / 60)
				replay.tick(1.0 / 60)
				check(first.action == second.action and combat.current_action == replay.current_action and combat._cast_sequence == replay._cast_sequence and absf(combat.action_elapsed - replay.action_elapsed) < 0.000001, "Enemy %d replay frame %d" % [int(enemy.id), step])
				combat.drain_events()
				replay.drain_events()
	check(not actions.is_empty(), "Enemy %d enters source actions" % int(enemy.id))
	if int(enemy.id) < 90000: check(hits > 0, "Enemy %d reaches an actual attack through source AI and interrupts" % int(enemy.id))
	var unresolved = combat.diagnostics.filter(func(message): return not str(message).begins_with("Summon behavior requires world adapter:") or not str(message).ends_with(" ESUT_Funnel"))
	if int(enemy.id) == 410031 and unresolved.has("Missing damage 444100311"):
		var source_report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://reports/region-combat-import.json"))
		check(source_report.apk_sha256 == "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505" and source_report.known_source_gaps.damage == ["444100311"] and combat._damage_data(444100311).is_empty(), "Lava mage missing coefficient is the exact retained packaged-source gap")
		source_gap_rows.append({"enemy": 410031, "damage_id": "444100311", "status": "missing in supplied APK; no fabricated coefficient"})
		unresolved.erase("Missing damage 444100311")
	check(unresolved.is_empty(), "Enemy %d has no unresolved combat diagnostics: %s" % [int(enemy.id), unresolved])
	check(combat.enemy_ai.diagnostics.is_empty(), "Enemy %d graph has no unsupported tasks" % int(enemy.id))
	check(max_transitions < 12, "Enemy %d never burns the per-tick transition budget" % int(enemy.id))
	rows.append({"enemy": enemy.id, "actions": actions.keys(), "attack_events": hits, "max_action_transitions_per_tick": max_transitions})
	# An AI decision must not bypass an attack's authored cancel gate.
	if enemy.get("actions", []).is_empty(): return
	var attack = combat._action(str(enemy.group), str(enemy.actions[0]))
	if not attack.is_empty():
		# Do not reuse units whose authored lifetime buffs have already killed them.
		var healthy = Combat.new()
		healthy.configure_enemy(int(enemy.id), 731)
		healthy.enemy_ai_enabled = true
		healthy._start(attack, 0)
		var sequence = healthy._cast_sequence
		healthy.custom_properties["OP_AIAction"] = "run"
		healthy.action_elapsed = 0.001
		healthy._tick_enemy_interrupts()
		var allows_run = healthy._enemy_interrupts.any(func(command): return command.get("target", "") == "run" and float(command.get("time", 0)) <= 0.001)
		if not allows_run: check(healthy._cast_sequence == sequence, "Enemy %d preserves attack windup when AI requests run" % int(enemy.id))

func _source_fallback_cases() -> void:
	var actor = Combat.new()
	actor.configure_enemy(33002, 731)
	actor.enemy_ai_enabled = true
	for requested in ["attack1_EX", "attack3_EX", "attack7_EX"]:
		check(actor._action(str(actor.enemy.group), requested).is_empty(), "Supplied tiger source contains no invented EX action %s" % requested)
		actor._start(actor._action(str(actor.enemy.group), "idle"), 0)
		actor.custom_properties.OP_AIAction = requested
		actor.drain_events()
		var before: int = actor._cast_sequence
		actor._tick_enemy_interrupts()
		var starts: Array = actor.drain_events().filter(func(event): return event.type == "action_started")
		check(actor.current_action == "idle" and actor._cast_sequence - before == 2 and starts.map(func(event): return event.action) == ["sys_checkatk", "idle"], "Unavailable EX follows exact helper/fallback once without same-update recursion %s" % requested)
		check(actor.diagnostics.is_empty(), "Source fallback has no transition budget exhaustion %s" % requested)
		source_gap_rows.append({"enemy": 33002, "action": requested, "status": "referenced by source interrupts but absent from supplied manifest; authored helper fallback retained"})
	actor.custom_properties.OP_AIAction = "attack1"
	actor._tick_enemy_interrupts()
	check(actor.current_action == "attack1", "Later supported AI decision still traverses source helper normally")
	actor.drain_events()

func _clock_matrix(fixture: RefCounted) -> void:
	var windows := 0
	for enemy in fixture.catalog.enemies:
		for action in fixture.catalog.actions:
			if action.group != enemy.group: continue
			var commands: Array = action.events.filter(func(event): return event.get("enabled", false) and event.get("type", "") == "EET_ActionSpeedScale")
			if commands.is_empty(): continue
			windows += commands.size()
			var expected = float(action.duration)
			for command in commands:
				var raw = JSON.parse_string(command.raw)
				expected += minf(float(command.duration), float(action.duration) - float(command.time)) * (1.0 / float(raw.ScaleSpeed) - 1.0)
			expected /= maxf(0.01, float(action.speed))
			var samples: Array = []
			for hz in [30, 60, 120]:
				var combat = Combat.new()
				combat.configure_enemy(int(enemy.id), 731)
				combat.enemy_ai_enabled = true
				combat._start(action, 0)
				var elapsed := 0.0
				while combat.action_elapsed * float(action.speed) < float(action.duration) - 0.000001 and elapsed < 120:
					combat.tick(1.0 / hz)
					combat.drain_events()
					elapsed += 1.0 / hz
				check(absf(elapsed - expected) <= 1.0 / hz + 0.00001, "%d %s segment clock %dHz %.6f expected %.6f" % [int(enemy.id), action.id, hz, elapsed, expected])
				samples.append({"hz": hz, "seconds": elapsed})
			clock_rows.append({"enemy": enemy.id, "action": action.id, "expected_seconds": expected, "samples": samples})
	check(windows == 43, "All 43 enabled enemy segment speed events covered, including four new region windows")

func _movement_cases(fixture: RefCounted) -> void:
	check(not Motion.source_bool("False") and Motion.source_bool("True"), "Source string booleans do not enable collisions accidentally")
	var actor := DungeonActor.new()
	actor.combat = Combat.new()
	actor.combat.configure_enemy(52001)
	root.add_child(actor)
	var target := DungeonActor.new()
	target.combat = Combat.new()
	target.combat.configure()
	root.add_child(target)
	for hz in [30, 60, 120]:
		actor.position = Vector3.ZERO
		actor.born_position = Vector3(7, 0, 3)
		actor.begin_action({"duration": 1, "timeline_duration": 1, "speed": 1})
		actor.add_action_motion({"type": "EET_MoveToPoint", "time": 0, "duration": 1}, {"MoveDirType": "EMDT_ToInitPos", "PosOffset": {"x": 1, "z": 2}, "EnableMoveIgnoreAllCollistion": "False"})
		for frame in hz:
			actor.combat.action_elapsed = float(frame + 1) / hz
			actor.position += actor._action_displacement()
		check(actor.position.distance_to(Vector3(8, 0, 5)) < 0.0001, "Born point plus world offset movement %dHz" % hz)
		check(not actor._motion_ignores_world, "String False preserves world collisions")
		actor.position = Vector3.ZERO
		target.position = Vector3(10, 0, 0)
		actor.begin_action({"duration": 1, "timeline_duration": 1, "speed": 1})
		actor.action_target = target
		actor.add_action_motion({"type": "EET_MoveToPoint", "time": 0, "duration": 1}, {"MoveDirType": "EMDT_ToCurrentTargetPos", "MaxMoveDistance": "4", "EnableMoveIgnoreAllCollistion": "True"})
		target.position = Vector3(-20, 0, 0)
		for frame in hz:
			actor.combat.action_elapsed = float(frame + 1) / hz
			actor.position += actor._action_displacement()
		check(actor.position.distance_to(Vector3(4, 0, 0)) < 0.0001, "Target snapshot respects max range and ignores later target movement %dHz" % hz)
		actor.end_action_motion()
		check(not actor._motion_ignores_world and actor.get_collision_mask_value(2), "Cancellation restores movement collision flags")
	actor.position = Vector3(13, 0, 0)
	actor.born_position = Vector3.ZERO
	var direction = Motion.direction({"MoveDirType": "EMDT_Perpendicular2BornPoint", "TargetRadius": 13, "TargetRadius_Nearfarspeed": 0.5}, actor)
	check(direction.is_equal_approx(Vector3.FORWARD), "Orbit tangent matches native handedness at authored radius")
	actor.free()
	target.free()

func _generation_cases() -> void:
	var world := DungeonWorld.new()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	var player_combat = Combat.new()
	player_combat.configure()
	world.create_player(player_combat, 1)
	world.spawn_wave([{"enemy_id": 13001, "position": [0, 0, 0]}], 0, 731)
	var source: DungeonActor = world.actors.back()
	world.room_spawn_points = [{"Id": 10, "Position": {"X": 3, "Y": 0, "Z": 2}}, {"Id": 11, "Position": {"X": 5, "Y": 0, "Z": 2}}]
	var definition = {"MonsterId": 11001, "GenerationMode": 1, "GenerationTotalCount": 0, "SpawnPoints": [10, 11]}
	world._spawn_monsters(source, {"definition": definition})
	check(world.monster_spawn_queue.is_empty(), "Zero authored summon count does not spawn one monster per point")
	definition.GenerationTotalCount = 3
	definition.GenerationMode = 99
	world._spawn_monsters(source, {"definition": definition})
	check(world.monster_spawn_queue.is_empty(), "Unknown source generation mode does not spawn monsters")
	definition.GenerationMode = 1
	definition.GenerationTotalCount = 3
	world._spawn_monsters(source, {"definition": definition})
	check(world.monster_spawn_queue.size() == 3, "Three summons cycle through two markers")
	check(world.monster_spawn_queue[0].spawn.position == world.monster_spawn_queue[2].spawn.position, "Sequential summon placement cycles source points")
	var before = world.actors.size()
	world._tick_monster_spawns()
	check(world.actors.size() == before + 1 and world.monster_spawn_queue.size() == 2, "Native coroutine emits one queued monster per physics tick")
	var saved = JSON.parse_string(JSON.stringify(world.transient_snapshot()))
	world.restore_transients(saved)
	check(world.monster_spawn_queue.size() == 2, "Pending summons survive JSON save and restore")
	world.monster_spawn_queue.clear()
	source.combat.custom_properties["SummonA"] = 1.9
	source.combat.custom_properties["SummonB"] = -0.9
	definition.GenerationTotalCount = 1
	definition.GenerationTotalCountModifyAddValue = "SummonA|SummonB"
	world._spawn_monsters(source, {"definition": definition})
	check(world.monster_spawn_queue.size() == 2, "Each summon count modifier truncates independently")
	world.monster_spawn_queue.clear()
	var hit = {"definition": {"shape": "Cube", "width": 0.1, "length": 0.1, "offset": 0.0, "raw": JSON.stringify({"EmitProperty": {"EmitOffset": {"z": 1.5}, "EmitRotation": {"y": 90}, "AfterRotateEmitOffset": {"z": 1.0}}})}, "damage": 10.0}
	var expected = source.position + Vector3(1, 0, 1.5)
	world.player.position = expected
	source.facing = Vector3.BACK
	world._hit_area(source, hit)
	check(world.vector(hit.impact_origin).is_equal_approx(expected), "Enemy instant damage applies source emission offset, rotated secondary offset and facing")
	world.queue_free()

func _physical_point_cases() -> void:
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(30, 1, 30)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	root.add_child(floor_body)
	floor_body.position.y = -0.5
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.2, 20, 20)
	shape.shape = box
	wall.add_child(shape)
	root.add_child(wall)
	wall.position.x = 1.5
	for hz in [30, 60, 120]:
		Engine.physics_ticks_per_second = hz
		await physics_frame
		await physics_frame
		for ignore_world in [false, true]:
			var actor := DungeonActor.new()
			actor.combat = Combat.new()
			actor.combat.configure_enemy(52001)
			root.add_child(actor)
			actor.born_position = Vector3(4, 0, 0)
			actor.begin_action({"duration": 1, "timeline_duration": 1, "speed": 1})
			actor.add_action_motion({"type": "EET_MoveToPoint", "time": 0, "duration": 1}, {"MoveDirType": "EMDT_ToInitPos", "FinalSetPosToGoal": "True", "EnableMoveIgnoreEnemyCollistion": "True", "EnableMoveIgnoreAllCollistion": "True" if ignore_world else "False"})
			for frame in hz:
				await physics_frame
				actor.combat.tick(1.0 / hz)
				actor._physics_process(1.0 / hz)
			if ignore_world:
				check(absf(actor.position.x - 4) < 0.001, "Source collisionless point move reaches goal %dHz: %s" % [hz, actor.position])
			else:
				check(actor.position.x > 0.8 and actor.position.x < 1.06, "Point move respects walls and never final-snaps through them %dHz: %s" % [hz, actor.position])
			actor.end_action_motion()
			check(actor.get_collision_mask_value(1) and actor.get_collision_mask_value(2) and not actor._motion_ignores_world, "Point move restores collisions %dHz" % hz)
			actor.free()
	wall.free()
	floor_body.free()
	Engine.physics_ticks_per_second = 60
