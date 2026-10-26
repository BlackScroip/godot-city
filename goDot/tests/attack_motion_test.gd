extends SceneTree

const Motion = preload("res://scripts/action_motion.gd")
const Combat = preload("res://scripts/domain/combat.gd")
var failures: Array[String] = []
var assertions := 0
var rows: Array = []

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _actor(id := 1) -> DungeonActor:
	var actor := DungeonActor.new()
	actor.is_player = true
	actor.combat = Combat.new()
	actor.combat.configure(null, null, id)
	root.add_child(actor)
	actor.face_direction(Vector3.FORWARD)
	actor.desired_velocity = actor.facing * actor.combat.move_speed
	return actor

func _run() -> void:
	var inventory: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://reports/attack-movement-inventory.json"))
	var source_events := 0
	for action in inventory.actions:
		for event in action.events:
			if event.type != "EET_Move" or not event.enabled: continue
			source_events += 1
			for hz in [30, 60, 120]:
				for speed in [0.75, 1.0, 1.5]:
					var actor = _actor(int(action.character_id))
					var total = float(event.time) + float(event.duration)
					actor.begin_action({"duration": total / speed, "timeline_duration": total, "speed": speed})
					actor.add_action_motion(event, event.raw)
					var travel := Vector3.ZERO
					for frame in range(1, ceili(total / speed * hz) + 1):
						actor.combat.action_elapsed = minf(total / speed, float(frame) / hz)
						travel += actor._action_displacement()
					var expected = float(event.raw.CustomSpeed) * float(event.duration)
					if str(event.raw.MoveSpeedType).contains("SelfMoveSpeedAttribute"): expected *= actor.combat.move_speed
					check(absf(travel.dot(Vector3.FORWARD) - expected) < 0.001, "%s@%.3f travel %dHz speed%.2f: %.6f != %.6f" % [action.id, event.time, hz, speed, travel.dot(Vector3.FORWARD), expected])
					check(actor.action_motion.is_empty(), "%s motion expires at its authored end" % action.id)
					actor.free()
	check(source_events == 138, "All 138 enabled source movement events covered")
	var actor = _actor(4)
	var raw = {"MoveSpeedType": "EMST_SelfMoveSpeedAttribute", "CustomSpeed": 0.3, "CustomSpeed_ProtextContext": "WandAtkMoveSpeedModify"}
	actor.combat.custom_properties.WandAtkMoveSpeedModify = 0.2
	check(absf(Motion.distance(raw, 1.0, 0, 1, actor.combat) - actor.combat.move_speed * 0.5) < 0.0001, "Property modifiers apply before own movement attribute")
	actor.desired_velocity = Vector3.RIGHT * actor.combat.move_speed * 0.5
	check(Motion.direction({"MoveDirType": "EMDT_FrontFace", "MoveSpeedMultiInputDir": true}, actor).is_equal_approx(Vector3.RIGHT * 0.25), "MultiInput replaces forward with live analog input, including source magnitude branch")
	actor.desired_velocity = Vector3.ZERO
	check(Motion.direction({"MoveDirType": "EMDT_InputMoveDir", "MoveSpeedMultiInputDir": true}, actor) == Vector3.ZERO, "Releasing input stops scaled movement")
	check(Motion.direction({"MoveDirType": "EMDT_InputMoveDir"}, actor) == actor.facing, "Unscaled zero input falls back to facing")
	var first = Motion.distance({"CustomSpeed": 10, "MoveSpeedType": "EMST_GraduallyStop"}, 1, 0, 0.25, actor.combat)
	var last = Motion.distance({"CustomSpeed": 10, "MoveSpeedType": "EMST_GraduallyStop"}, 1, 0.75, 1, actor.combat)
	check(absf(first - 4.375) < 0.0001 and absf(last - 0.625) < 0.0001, "Native deceleration has a forceful start and short tail")
	Motion.turn(actor, Vector3.RIGHT, true, 1, 1.0 / 60)
	check(actor.facing.is_equal_approx(Vector3.RIGHT), "Source turn scale one snaps")
	actor.free()
	await _physical_cases()
	await _world_cases()
	_clock_cases()
	_action_matrix()
	var report = {"passed": failures.is_empty(), "assertions": assertions, "source_actions": inventory.actions.size(), "source_movement_events": source_events, "physics": rows, "failures": failures}
	FileAccess.open("res://reports/attack-motion.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("ATTACK_MOTION ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func _physical_cases() -> void:
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.2, 20, 20)
	shape.shape = box
	wall.add_child(shape)
	root.add_child(wall)
	wall.position.x = 100
	for hz in [30, 60, 120]:
		Engine.physics_ticks_per_second = hz
		# Let PhysicsServer adopt the new tick length before manual body steps.
		await physics_frame
		await physics_frame
		for paused in [false, true]:
			var actor = _actor()
			actor.face_direction(Vector3.RIGHT)
			actor.desired_velocity = Vector3.LEFT * actor.combat.move_speed
			actor.begin_action({"duration": 1, "timeline_duration": 1, "speed": 1})
			actor.add_action_motion({"type": "EET_Move", "time": 0.217, "duration": 0.45}, {"MoveDirType": "EMDT_FrontFace", "CustomSpeed": 5, "MoveSpeedType": "EMST_GraduallyStop"})
			var elapsed := 0.0
			var pause_left := 0
			for frame in range(hz + (ceili(hz * 0.08) if paused else 0)):
				await physics_frame
				actor.combat.action_step = 0.0 if pause_left > 0 else 1.0 / hz
				elapsed += actor.combat.action_step
				actor.combat.action_elapsed = elapsed
				actor.combat.impact_pause = 0.08 if pause_left > 0 else 0.0
				if paused and frame == ceili(hz * 0.3):
					pause_left = ceili(hz * 0.08)
					actor.combat.impact_pause = 0.08
				elif pause_left > 0: pause_left -= 1
				actor._physics_process(1.0 / hz)
			check(absf(actor.position.x - 2.25) < 0.003, "Physical travel and newly confirmed hit stop %dHz pause%s: %.6f" % [hz, paused, actor.position.x])
			check(actor.locomotion == Vector3.ZERO, "Held opposing input does not build hidden locomotion during action")
			rows.append({"hz": hz, "hit_stop": paused, "travel": actor.position.x, "expected": 2.25})
			actor.free()
		var actor = _actor()
		actor.face_direction(Vector3.RIGHT)
		actor.desired_velocity = Vector3.ZERO
		actor.begin_action({"duration": 0.5, "timeline_duration": 0.5, "speed": 1})
		actor.add_action_motion({"type": "EET_Move", "time": 0, "duration": 0.5}, {"CustomSpeed": 10, "IsIgnoreTargetCollider": true})
		wall.position.x = 1.5
		for frame in ceili(hz * 0.5):
			await physics_frame
			actor.combat.action_elapsed = float(frame + 1) / hz
			actor.combat.action_step = 1.0 / hz
			actor._physics_process(1.0 / hz)
		check(actor.position.x > 0.8 and actor.position.x < 1.06, "Authored pass-through dash still collides with walls at %dHz" % hz)
		actor.end_action_motion()
		check(actor.get_collision_mask_value(3), "Cancel restores opponent collision")
		wall.position.x = 100
		actor.free()
	wall.free()
	Engine.physics_ticks_per_second = 60

func _world_cases() -> void:
	var world := DungeonWorld.new()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	var combat = Combat.new()
	combat.configure()
	var actor = world.create_player(combat, 1, Vector3.ZERO)
	actor.desired_velocity = Vector3.RIGHT * combat.move_speed
	combat._start(combat._action("ActGroup_playerchara", "sword_atk1"), 0)
	combat.custom_properties._rhythm_enabled = false
	for event in combat.drain_events(): world._consume(actor, event)
	combat.custom_properties.InputMove = true
	combat.tick(0.3)
	for event in combat.drain_events(): world._consume(actor, event)
	check(actor.action_timeline_duration > 0, "Movement input cannot cancel normal attack before source run window")
	combat.tick(0.25)
	for event in combat.drain_events(): world._consume(actor, event)
	check(actor.action_motion.is_empty() and actor.action_timeline_duration == 0, "Held movement cancels in source run window and clears future motion")
	combat._start(combat._action("ActGroup_playerchara", "skill_bow_jianyu"), 3)
	combat.custom_properties.InputMove = false
	combat.custom_properties._rhythm_enabled = false
	for event in combat.drain_events(): world._consume(actor, event)
	combat.tick(0.5)
	for event in combat.drain_events(): world._consume(actor, event)
	actor._action_displacement()
	check(combat.busy == 0 and actor.action_cursor < actor.action_timeline_duration, "Short input recovery does not end the movement timeline")
	check(combat.input_action_delay(0) > 0.5, "Ultimate cannot lose its late attack to the old short busy cutoff")
	check(actor.animation != null and not actor.animation.current_animation.is_empty(), "Actual player animation is available for save-pose verification")
	actor.animation.seek(0.217, true)
	var saved = JSON.parse_string(JSON.stringify(world.transient_snapshot()))
	var cursor = actor.action_cursor
	var facing = actor.facing
	var saved_clip = actor.animation.current_animation
	var saved_pose = actor.animation.current_animation_position
	actor.face_direction(Vector3.LEFT)
	actor.play_animation("idle", true)
	actor.animation.advance(0)
	world.restore_transients(saved)
	check(actor.action_cursor == cursor and actor.action_timeline_duration == 2, "Save restores local cursor and complete skill duration")
	check(actor.facing.is_equal_approx(facing), "Save restores dash direction")
	check(actor.animation.current_animation == saved_clip and absf(actor.animation.current_animation_position - saved_pose) < 0.00001, "Save restores the actual animation clip and pose without replaying startup")
	combat.tick(0.25)
	for event in combat.drain_events(): world._consume(actor, event)
	check(actor.action_motion.any(func(motion): return motion.type == "EET_Move" and is_equal_approx(float(motion.start), 0.7)), "Late ultimate backstep remains attached after restore")
	var target = _actor()
	target.is_player = false
	target.combat.actor_key = "target"
	target.position = Vector3.RIGHT * 2
	world.actors.append(target)
	actor.face_direction(Vector3.FORWARD)
	world._consume(actor, {"type": "command", "sequence": combat._cast_sequence, "slot": 3, "command": {"type": "EET_FindTarget", "time": 0.7, "duration": 0.3, "raw_data": {"IsFaceTarget": true, "OnlyEnterFindTarget": true, "IsSmoothFaceTarget": true, "RotateSpeedScale": 1}}})
	check(actor.facing.dot(Vector3.RIGHT) > 0.99, "Only-enter target search retains source instant facing")
	combat.record_input(2, true)
	check(not combat.custom_properties.get("InputSkill1_LongPress", false) and combat.custom_properties.LastInputAttackKeyName == "skill_1", "Skill down records its key without premature long-press input")
	combat.custom_properties["InputSkill1_LongPress"] = true
	combat.record_input(2, false)
	check(not combat.custom_properties.InputSkill1_LongPress, "Skill release clears source hold flag")
	world.restore_transients({})
	check(actor.action_motion.is_empty() and combat.busy == 0 and not combat._pending.any(func(event): return event.get("action_timeline", true)), "Legacy saves consistently cancel attached action and preserve detached payloads")
	world.actors.erase(target)
	target.free()
	world.free()

func _clock_cases() -> void:
	var world := DungeonWorld.new()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	var combat = Combat.new()
	combat.configure()
	var actor = world.create_player(combat, 1, Vector3.ZERO)
	combat.request_attack(4)
	combat.custom_properties._rhythm_enabled = false
	for event in combat.drain_events(): world._consume(actor, event)
	var branches := 0
	for frame in 100:
		var sequence = combat._cast_sequence
		combat.tick(1.0 / 60)
		for event in combat.drain_events(): world._consume(actor, event)
		actor._physics_process(1.0 / 60)
		if sequence != combat._cast_sequence:
			branches += 1
			check(absf(actor.animation.current_animation_position - combat.action_elapsed * actor.action_speed) < 0.00001, "Heavy branch starts animation at the new local cursor, without the previous action's frame")
	check(branches >= 2, "Clock regression crosses actual sword ready and strike branches")
	combat._start(combat._action("ActGroup_playerchara", "skill_sword_tujinzhan"), 2)
	for event in combat.drain_events(): world._consume(actor, event)
	combat.tick(0.1)
	for event in combat.drain_events(): world._consume(actor, event)
	actor._physics_process(0.1)
	var initial_speed = actor.action_speed
	var initial_cursor = actor.action_cursor
	combat.set_external_attributes({"AttackSpeedRate": 1000})
	combat._execute({"command": {"type": "EET_PlayAnim", "anim": actor.animation.current_animation}, "action": combat.current_action, "slot": 2, "sequence": combat._cast_sequence})
	for event in combat.drain_events(): world._consume(actor, event)
	check(is_equal_approx(actor.action_speed, initial_speed), "A later PlayAnim command keeps the cast's speed after a mid-action attack-speed buff")
	check(actor.action_cursor == initial_cursor, "A mid-action buff cannot jump the authored movement cursor")
	combat.tick(1.0 / 60)
	for event in combat.drain_events(): world._consume(actor, event)
	actor._physics_process(1.0 / 60)
	check(absf(actor.action_cursor - combat.action_elapsed * initial_speed) < 0.00001, "Motion and events retain the same local clock after a mid-action buff")
	world.free()

func _action_matrix() -> void:
	for input_action in ["move_left", "move_right", "move_up", "move_down"]:
		if not InputMap.has_action(input_action): InputMap.add_action(input_action)
	var world := DungeonWorld.new()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.auto_attack_enabled = false
	world.paused = false
	world._background = false
	var cases: Array = []
	for id in range(1, 8):
		for slot in [0, 4, 2, 3]:
			world.presentation.clear()
			world.projectiles.clear()
			world.summon_units.clear()
			var actor = _actor(id)
			actor.combat.actor_key = "player"
			world.player = actor
			world.actors.assign([actor])
			var combat = actor.combat
			combat.energy[slot] = combat.fighter.skills[slot].maxSp
			combat.add_buff(str(combat.fighter.jp), 300 if id == 7 else 75)
			check(world.use_skill(slot, true).success, "Character %d slot%d accepts the original action input" % [id, slot])
			if slot == 0: check(world.use_skill(slot, false).success, "Character %d short release requests normal attack" % id)
			var actions: Array = []
			var moves := 0
			for frame in 240:
				if frame == 30: Input.action_press("move_right")
				if frame == 75:
					Input.action_release("move_right")
					Input.action_press("move_left")
				if frame == 110: Input.action_release("move_left")
				if frame == 120: world.use_skill(slot, false)
				world._physics_process(1.0 / 60)
				if actions.is_empty() or actions.back() != combat.current_action: actions.append(combat.current_action)
				moves = maxi(moves, actor.action_motion.size())
				check(actor.position.is_finite() and actor.facing.is_finite(), "Character %d slot%d input turn/release frame%d stays finite" % [id, slot, frame])
			check(not actions.is_empty() and not str(actions[0]).is_empty(), "Character %d slot%d runs through world input" % [id, slot])
			check(world.use_skill(1).success, "Character %d slot%d can immediately escape by dodge" % [id, slot])
			world._physics_process(1.0 / 60)
			check(actor.action_motion.is_empty(), "Dodge removes all authored attack movement")
			cases.append({"character": id, "slot": slot, "actions": actions, "peak_motion_events": moves, "end": str(actor.position)})
			world.intent.clear(combat)
			world.actors.clear()
			actor.free()
	FileAccess.open("res://reports/attack-motion-input-matrix.json", FileAccess.WRITE).store_string(JSON.stringify({"cases": cases, "scope": "All seven characters x normal/heavy/subskill/ultimate, actual world.use_skill and world physics dispatch; held movement, direction reversal, release and dodge. Visual actors are omitted; physical collisions are verified separately."}, "\t"))
	world.free()
