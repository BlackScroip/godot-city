class_name DungeonActor
extends CharacterBody3D

const COLLISION_RADIUS := 0.35
const COLLISION_CENTER := Vector3(0.0, 0.8, 0.0)

var actor_id := 1
var is_player := false
var combat: RefCounted
var visual: Node3D
var animation: AnimationPlayer
var facing := Vector3.FORWARD
var desired_velocity := Vector3.ZERO
var action_time := 0.0
var invulnerability := 0.0
var dead := false
var health_bar: Sprite3D
var hurt_timer := 0.0
var animations: Array[String] = []
var animation_aliases: Dictionary = {}
var visual_base_y := 0.0
var suspended := false:
	set(value):
		suspended = value
		if value: _reset_source_model_shake()
var simulation_scale := 1.0
var impulse := Vector3.ZERO
var weapon: Node3D
var visual_loaded := false
var navigation: NavigationAgent3D
var previous_position := Vector3.ZERO
var navigation_timer := 0.0
const FEEL = preload("res://assets/feel_settings.tres")
var locomotion := Vector3.ZERO
var dodge_elapsed := -1.0
var dodge_vector := Vector3.ZERO
var action_speed := 1.0
var flash_material: StandardMaterial3D
var flash_meshes: Array[MeshInstance3D] = []
var _flash_visible := false
var action_motion: Array[Dictionary] = []
const ACTION_MOTION = preload("res://scripts/action_motion.gd")
const ENEMY_HIT_REACTION = preload("res://scripts/domain/enemy_hit_reaction.gd")
var action_timeline_duration := 0.0
var action_cursor := 0.0
var action_target: DungeonActor
var action_target_resolver: Callable
var _motion_ignores_targets := false
var _motion_ignores_world := false
var born_position := Vector3.ZERO
var born_facing := Vector3.BACK
var field_center := Vector3.ZERO
var animation_state_speed := 1.0
var animation_states: Dictionary = {}
static var _monster_animation_data: Dictionary = {}
var direction_indicator: DungeonPlayerIndicator
var knockback_elapsed := -1.0
var knockback_distance := 0.0
var knockback_duration := 0.12
var knockback_direction := Vector3.ZERO
var _telegraph_sequence := -1
var _telegraph_turn_speed := 0.0
var impact_bounds := AABB(Vector3(-0.35, 0, -0.35), Vector3(0.7, 1.5, 0.7))
var _model_shake_root: Node3D
var _model_shake_active := false
var _model_shake_elapsed := 0.0
var _model_shake_count := 0
var _model_shake_rng := RandomNumberGenerator.new()

func begin_death() -> void:
	clear_impact_state()
	if combat: ENEMY_HIT_REACTION.clear_motion(combat)
	end_action_motion()
	clear_telegraph_aim()
	dead = true
	desired_velocity = Vector3.ZERO
	locomotion = Vector3.ZERO
	velocity = Vector3.ZERO
	dodge_elapsed = -1.0
	collision_layer = 0
	collision_mask = 1
	if health_bar: health_bar.hide()
	if is_player or combat == null or not combat.begin_enemy_death(): play_animation("death", true)

func advance_death(delta: float) -> void:
	if not dead or is_player or suspended or combat == null: return
	combat.tick_enemy_death(delta)
	if combat.custom_properties.get("_enemy_visual_hidden", false) and visual: visual.hide()
	if death_finished():
		hide()
		collision_mask = 0

func death_finished() -> bool:
	return dead and not is_player and combat != null and bool(combat.custom_properties.get("_enemy_deleted", false))

func apply_delete_event(definition: Dictionary) -> void:
	if bool(definition.get("Delete", true)):
		dead = true
		hide()
		collision_layer = 0
		collision_mask = 0
	elif visual:
		visual.hide()

func flash_hit() -> void:
	hit_flash(0.09)

func _ready() -> void:
	set_physics_process(false)
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	collision_layer = 2 if is_player else 4
	collision_mask = 1 | (4 if is_player else 2)
	var shape = CollisionShape3D.new()
	var capsule = CapsuleShape3D.new()
	capsule.radius = COLLISION_RADIUS
	capsule.height = 1.5
	shape.shape = capsule
	shape.position = COLLISION_CENTER
	add_child(shape)
	navigation = NavigationAgent3D.new()
	navigation.radius = COLLISION_RADIUS
	navigation.height = 1.5
	navigation.path_desired_distance = 0.4
	navigation.target_desired_distance = 0.6
	add_child(navigation)
	if is_player:
		direction_indicator = DungeonPlayerIndicator.new()
		direction_indicator.name = "DirectionIndicator"
		add_child(direction_indicator)

func set_visual(path: String, metadata: Dictionary = {}, prepared_scene: PackedScene = null) -> void:
	_reset_source_model_shake()
	animation = null
	animations.clear()
	animation_aliases.clear()
	animation_states.clear()
	animation_state_speed = 1.0
	if not is_player:
		if _monster_animation_data.is_empty():
			_monster_animation_data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/monster_presentation.json"))
		animation_states = _monster_animation_data.get("enemies", {}).get(str(actor_id), {}).get("states", {})
	visual_loaded = false
	if is_instance_valid(visual):
		visual.queue_free()
	visual = null
	if not path.is_empty() and ResourceLoader.exists(path):
		var scene = prepared_scene if prepared_scene else load(path)
		if scene is PackedScene:
			visual = scene.instantiate()
			visual_loaded = true
	if visual == null:
		visual = Node3D.new()
		var mesh = MeshInstance3D.new()
		var capsule = CapsuleMesh.new()
		capsule.radius = 0.35
		capsule.height = 1.5
		mesh.mesh = capsule
		mesh.position.y = 0.75
		var material = StandardMaterial3D.new()
		material.albedo_color = Color("54b7ad") if is_player else Color("c88376")
		mesh.material_override = material
		visual.add_child(mesh)
	if not is_instance_valid(_model_shake_root):
		_model_shake_root = Node3D.new()
		_model_shake_root.name = "HitModelShake"
		_model_shake_root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(_model_shake_root)
	_align_player_prefab_origin()
	_model_shake_root.add_child(visual)
	# Position follows the physics body; facing still updates at render frequency.
	visual.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_flash_visible = false
	flash_meshes.clear()
	for mesh in visual.find_children("*", "MeshInstance3D", true, false): flash_meshes.append(mesh)
	var bounds_found := false
	for mesh in flash_meshes:
		if mesh.mesh == null: continue
		var bounds: AABB = (global_transform.affine_inverse() * mesh.global_transform) * mesh.get_aabb()
		impact_bounds = impact_bounds.merge(bounds) if bounds_found else bounds
		bounds_found = true
	_repair_skinned_impact_bounds()
	flash_material = StandardMaterial3D.new()
	flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_material.albedo_color = Color(1.0, 0.92, 0.75, 0.65)
	_find_animation(visual)
	if animation:
		animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		_prepare_in_place_animations()
		animations.assign(animation.get_animation_list())
		for clip in metadata.get("animations", []):
			var clip_name = str(clip.get("name", ""))
			if animation.has_animation(clip_name):
				var source_name = str(clip.get("source_name", clip_name))
				animation_aliases[source_name.to_lower()] = clip_name
				animation.get_animation(clip_name).loop_mode = Animation.LOOP_LINEAR if clip.get("loop", false) else Animation.LOOP_NONE
		for clip in metadata.get("animations", []):
			var alias = str(clip.get("source_name", "")).replace("@", "_").to_lower()
			if not animation_aliases.has(alias): animation_aliases[alias] = str(clip.name)
		play_animation("idle")

func _align_player_prefab_origin() -> void:
	if not is_player: return
	# Full APK prefabs may retain editor placement; the body owns world travel.
	for child in visual.get_children():
		if child is Node3D and str(child.name).begins_with("myplayer_"):
			child.position.x = 0.0
			child.position.z = 0.0

func _repair_skinned_impact_bounds() -> void:
	if impact_bounds.size[impact_bounds.size.max_axis_index()] <= 20.0: return
	var bone_bounds := AABB()
	var found := false
	for skeleton in visual.find_children("*", "Skeleton3D", true, false):
		var local_transform: Transform3D = global_transform.affine_inverse() * skeleton.global_transform
		for index in skeleton.get_bone_count():
			var point: Vector3 = local_transform * skeleton.get_bone_global_pose(index).origin
			bone_bounds = bone_bounds.expand(point) if found else AABB(point, Vector3.ZERO)
			found = true
	if not found: return
	var bone_extent = bone_bounds.size[bone_bounds.size.max_axis_index()]
	# Some recovered skins expose unscaled bind-space mesh bounds.
	if bone_extent > 0.1 and impact_bounds.size[impact_bounds.size.max_axis_index()] > bone_extent * 8.0:
		impact_bounds = bone_bounds.grow(0.2)

func impact_anchor(contact := Vector3.INF) -> Vector3:
	var center = impact_bounds.get_center()
	center.y = maxf(0.55, center.y)
	var point = center if contact == Vector3.INF else to_local(contact)
	var radius = clampf(maxf(impact_bounds.size.x, impact_bounds.size.z) * 0.3, 0.2, 0.8)
	point.x = clampf(point.x, center.x - radius, center.x + radius)
	point.z = clampf(point.z, center.z - radius, center.z + radius)
	point.y = clampf(point.y, center.y - impact_bounds.size.y * 0.1, center.y + impact_bounds.size.y * 0.18)
	return to_global(point)

func _prepare_in_place_animations() -> void:
	var animation_root := animation.get_node(animation.root_node)
	for library_name in animation.get_animation_library_list():
		var source := animation.get_animation_library(library_name)
		var library: AnimationLibrary
		for clip_name in source.get_animation_list():
			var original := source.get_animation(clip_name)
			var clip: Animation
			for track in original.get_track_count():
				if original.track_get_type(track) != Animation.TYPE_POSITION_3D: continue
				var path := original.track_get_path(track)
				var node := animation_root.get_node_or_null(NodePath(path.get_concatenated_names()))
				var origin: Vector3
				if path.get_subname_count() == 1 and str(path.get_subname(0)).to_lower() == "root" and node is Skeleton3D:
					var bone: int = node.find_bone(path.get_subname(0))
					if bone < 0: continue
					origin = node.get_bone_rest(bone).origin
				elif path.get_subname_count() == 0 and node is Node3D and str(node.name).to_lower() == "root":
					origin = node.position
				else: continue
				if clip == null: clip = original.duplicate()
				# Skill physics owns horizontal travel; retain animated height and poses.
				for key in clip.track_get_key_count(track):
					var point: Vector3 = clip.track_get_key_value(track, key)
					point.x = origin.x
					point.z = origin.z
					clip.track_set_key_value(track, key, point)
			if clip != null:
				if library == null: library = source.duplicate()
				library.remove_animation(clip_name)
				library.add_animation(clip_name, clip)
		if library != null:
			animation.remove_animation_library(library_name)
			animation.add_animation_library(library_name, library)

func equip_weapon(path: String, socket_name := "dummy_hand_r") -> bool:
	if is_instance_valid(weapon): weapon.queue_free()
	weapon = null
	if not visual or path.is_empty() or not ResourceLoader.exists(path): return false
	var packed = load(path)
	if not packed is PackedScene: return false
	var socket = visual.find_child(socket_name, true, false)
	if socket == null: socket = visual.find_child("Bip001 R Hand", true, false)
	if socket == null:
		for node in visual.find_children("*", "Skeleton3D", true, false):
			var bone = node.find_bone(socket_name)
			if bone < 0: bone = node.find_bone("Bip001 R Hand")
			if bone >= 0:
				var attachment = BoneAttachment3D.new()
				attachment.bone_name = node.get_bone_name(bone)
				node.add_child(attachment)
				socket = attachment
				break
	if socket == null:
		push_warning("Weapon socket missing on actor %d" % actor_id)
		return false
	weapon = packed.instantiate()
	socket.add_child(weapon)
	return true

func _find_animation(node: Node) -> void:
	if node is AnimationPlayer:
		animation = node
	for child in node.get_children():
		_find_animation(child)

func play_animation(kind: String, restart := false) -> void:
	if not animation:
		return
	var state: Dictionary = animation_states.get(kind.to_lower(), {})
	animation_state_speed = float(state.get("speed", 1))
	if not state.is_empty() and animation.has_animation(str(state.get("animation", ""))):
		kind = str(state.animation)
		animation.get_animation(kind).loop_mode = Animation.LOOP_LINEAR if state.get("loop", false) else Animation.LOOP_NONE
	kind = str(animation_aliases.get(kind.to_lower(), kind))
	if animation.has_animation(kind):
		if restart or animation.current_animation != kind or not animation.is_playing(): animation.play(kind, 0.05, 1.0, animation_state_speed < 0)
		return
	var candidates: Array[String] = []
	match kind:
		"idle": candidates.assign(["idle", "stand", "wait"])
		"run": candidates.assign(["run", "walk", "move"])
		"attack": candidates.assign(["attack", "atk", "skill"])
		"dodge": candidates.assign(["dodge", "roll", "dash", "run"])
		"death": candidates.assign(["death", "die", "dead"])
		"hit": candidates.assign(["hit_1", "behit", "hurt", "hit"])
		_: candidates.assign([kind])
	for token in candidates:
		for name in animations:
			if token.to_lower() in name.to_lower():
				if restart or animation.current_animation != name or not animation.is_playing():
					animation.play(name, 0.12, 1.0, animation_state_speed < 0)
				return

func face_direction(direction: Vector3) -> void:
	if has_telegraph_aim(): return
	if direction.length_squared() > 0.01:
		facing = direction.normalized()

func has_telegraph_aim() -> bool:
	return not is_player and not dead and combat != null and combat.busy > 0 and _telegraph_sequence == combat._cast_sequence

func lock_telegraph_aim(sequence: int) -> void:
	if is_player or has_telegraph_aim(): return
	_telegraph_sequence = sequence
	_telegraph_turn_speed = 0.0
	if combat.enemy.get("rank", "") == "Boss":
		_telegraph_turn_speed = deg_to_rad(float(FEEL.telegraph_tracking_actions.get(str(actor_id), {}).get(str(combat.current_action), 0.0)))
	desired_velocity = Vector3.ZERO
	locomotion = Vector3.ZERO
	if visual: visual.rotation.y = atan2(facing.x, facing.z)

func clear_telegraph_aim() -> void:
	_telegraph_sequence = -1
	_telegraph_turn_speed = 0.0

func aim_enemy(direction: Vector3, delta: float) -> void:
	if not has_telegraph_aim():
		face_direction(direction)
		return
	if _telegraph_turn_speed <= 0 or direction.length_squared() < 0.01: return
	var turn = facing.signed_angle_to(direction.normalized(), Vector3.UP)
	facing = facing.rotated(Vector3.UP, clampf(turn, -_telegraph_turn_speed * delta, _telegraph_turn_speed * delta)).normalized()

func start_dodge(direction: Vector3) -> void:
	clear_impact_state()
	end_action_motion()
	dodge_vector = direction.normalized()
	face_direction(dodge_vector)
	dodge_elapsed = 0.0
	impulse = Vector3.ZERO
	locomotion = Vector3.ZERO

func begin_action(event: Dictionary) -> void:
	end_action_motion()
	action_time = float(event.get("duration", 0.5))
	action_speed = float(event.get("speed", 1.0))
	action_timeline_duration = float(event.get("timeline_duration", action_time * action_speed))
	action_cursor = 0.0
	locomotion = Vector3.ZERO

func end_action_motion() -> void:
	action_motion.clear()
	action_timeline_duration = 0.0
	action_cursor = 0.0
	action_target = null
	_set_motion_collision(false)

func add_action_motion(command: Dictionary, raw: Dictionary) -> void:
	if float(command.get("duration", 0.0)) <= 0.0: return
	var motion = {"type": str(command.type), "start": float(command.get("time", 0.0)), "duration": float(command.duration), "raw": raw}
	if command.type == "EET_MoveToPoint":
		var goal = born_position
		if str(raw.get("MoveDirType", "")) == "EMDT_ToCurrentTargetPos":
			goal = action_target.position if is_instance_valid(action_target) and not action_target.dead else position
			var toward = goal - position
			toward.y = 0
			goal = position + toward.limit_length(maxf(0, float(raw.get("MaxMoveDistance", 0))))
		var offset: Dictionary = raw.get("PosOffset", {})
		goal += Vector3(float(offset.get("x", 0)), 0, float(offset.get("z", 0)))
		goal.y = position.y
		motion["goal"] = [goal.x, goal.y, goal.z]
		motion["distance"] = position.distance_to(goal)
	action_motion.append(motion)

func _set_motion_collision(ignore_targets: bool, ignore_world := false) -> void:
	ignore_targets = ignore_targets or dead
	if _motion_ignores_world != ignore_world:
		_motion_ignores_world = ignore_world
		set_collision_mask_value(1, not ignore_world)
	if _motion_ignores_targets == ignore_targets: return
	_motion_ignores_targets = ignore_targets
	set_collision_mask_value(3 if is_player else 2, not ignore_targets)

func _action_displacement() -> Vector3:
	var now = minf(action_timeline_duration, maxf(action_cursor, combat.action_elapsed * action_speed))
	var displacement := Vector3.ZERO
	var ignores_targets := false
	var ignores_world := false
	for motion in action_motion:
		if motion.type == "EET_Navigation" and now > float(motion.start) and action_cursor < float(motion.start) + float(motion.duration):
			ACTION_MOTION.turn(self, desired_velocity, false, 1, 0)
	for index in range(action_motion.size() - 1, -1, -1):
		var motion = action_motion[index]
		var first = maxf(action_cursor, float(motion.start)) - float(motion.start)
		var last = minf(now, float(motion.start) + float(motion.duration)) - float(motion.start)
		var raw: Dictionary = motion.raw
		if last > first:
			var elapsed = (last - first) / maxf(0.01, action_speed)
			match str(motion.type):
				"EET_FindTarget":
					if not raw.get("OnlyEnterFindTarget", true) and action_target_resolver.is_valid(): action_target = action_target_resolver.call(raw)
					ACTION_MOTION.aim(self, raw, elapsed)
				"EET_Move":
					var direction = ACTION_MOTION.direction(raw, self)
					if not is_player and combat.custom_properties.get("_navigation_steer", false) and combat.current_action in ["run", "forward", "move"] and str(raw.get("MoveDirType", "")) == "EMDT_FrontFace" and desired_velocity.length_squared() > 0.01:
						direction = desired_velocity.normalized()
						ACTION_MOTION.turn(self, direction, false, 1, elapsed)
					displacement += direction * ACTION_MOTION.distance(raw, float(motion.duration), first, last, combat)
					ignores_targets = ignores_targets or bool(raw.get("IsIgnoreTargetCollider", false))
					var aim := Vector3.ZERO
					match str(raw.get("RotateType", "EMRT_Keep")):
						"EMRT_FaceToMoveDir": aim = direction
						"EMRT_FaceToInputDir": aim = desired_velocity
						"EMRT_FaceToTargetDir":
							if is_instance_valid(action_target) and not action_target.dead: aim = action_target.position - position
					ACTION_MOTION.turn(self, aim, bool(raw.get("IsSmoothRotate", false)), float(raw.get("RotateSpeedScale", 1.0)), elapsed)
				"EET_MoveToPoint":
					var goal: Array = motion.get("goal", [position.x, position.y, position.z])
					var toward = Vector3(float(goal[0]), position.y, float(goal[2])) - position - displacement
					var travel = float(motion.get("distance", 0)) * (last - first) / float(motion.duration)
					displacement += toward.normalized() * minf(toward.length(), maxf(0, travel))
					ignores_targets = ignores_targets or ACTION_MOTION.source_bool(raw.get("EnableMoveIgnoreEnemyCollistion", false))
					ignores_world = ignores_world or ACTION_MOTION.source_bool(raw.get("EnableMoveIgnoreAllCollistion", false))
					var aim = toward
					match str(raw.get("RotateType", "EMRT_Keep")):
						"EMRT_Keep": aim = Vector3.ZERO
						"EMRT_FaceBackToMoveDir": aim = -toward
						"EMRT_AlignToInitPosDir": aim = born_facing
					ACTION_MOTION.turn(self, aim, false, 1, elapsed)
				"EET_TargetDisCompensation":
					if is_instance_valid(action_target) and not action_target.dead:
						var to_target = action_target.position - position - displacement
						to_target.y = 0
						var gap = maxf(0.0, to_target.length() - 0.7)
						var travel = float(raw.get("CompensationDis", 0)) * (ACTION_MOTION.curve_integral("EMST_GraduallyStop", last / float(motion.duration)) - ACTION_MOTION.curve_integral("EMST_GraduallyStop", first / float(motion.duration)))
						displacement += to_target.normalized() * minf(gap, maxf(0.0, travel))
		if now >= float(motion.start) + float(motion.duration) - 0.000001: action_motion.remove_at(index)
	action_cursor = now
	_set_motion_collision(ignores_targets, ignores_world)
	return displacement

func clear_impact_state() -> void:
	_reset_source_model_shake()
	knockback_elapsed = -1.0
	knockback_distance = 0.0
	impulse = Vector3.ZERO
	hurt_timer = 0.0
	if combat: combat.clear_impact_state()
	for mesh in flash_meshes:
		if is_instance_valid(mesh): mesh.material_overlay = null
	_flash_visible = false

static func knockback_progress(t: float) -> float:
	t = clampf(t, 0, 1)
	return t * t / 0.15 if t < 0.15 else 1.0 - (1.0 - t) * (1.0 - t) / 0.85

func start_knockback(direction: Vector3, distance: float, duration: float) -> void:
	if distance <= 0 or dodge_elapsed >= 0: return
	if knockback_elapsed >= 0 and distance < knockback_distance * (1.0 - knockback_progress(knockback_elapsed / knockback_duration)): return
	direction.y = 0
	knockback_direction = direction.normalized() if direction.length_squared() > 0.00001 else -facing
	knockback_distance = distance
	knockback_duration = maxf(0.01, duration)
	knockback_elapsed = 0.0
	locomotion = Vector3.ZERO

static func dodge_progress(t: float) -> float:
	return 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), 2)

func hit_flash(duration := 0.08) -> void:
	hurt_timer = maxf(hurt_timer, duration)

func start_source_model_shake() -> void:
	if dead or suspended or not is_instance_valid(visual) or not is_instance_valid(_model_shake_root): return
	_model_shake_active = true
	_model_shake_elapsed = 0.0
	_model_shake_count = 0

func _reset_source_model_shake() -> void:
	_model_shake_active = false
	_model_shake_elapsed = 0.0
	_model_shake_count = 0
	if is_instance_valid(_model_shake_root): _model_shake_root.position = Vector3.ZERO

func _advance_source_model_shake(delta: float) -> void:
	if not _model_shake_active: return
	if dead or suspended or not is_instance_valid(visual) or not is_instance_valid(_model_shake_root):
		_reset_source_model_shake()
		return
	_model_shake_elapsed += delta
	# APK URoleUnit.UpdateShake: strict interval, one sample per render update.
	if _model_shake_elapsed <= 0.02: return
	_model_shake_elapsed = 0.0
	_model_shake_count += 1
	if _model_shake_count > 5:
		_reset_source_model_shake()
		return
	# Unity's integer Range(-1, 1) excludes 1; visual RNG leaves combat rolls alone.
	_model_shake_root.position = Vector3(_model_shake_rng.randi_range(-1, 0) * 0.05, 0.0, _model_shake_rng.randi_range(-1, 0) * 0.05)

func _process(delta: float) -> void:
	if suspended: return
	_advance_source_model_shake(delta)
	delta *= simulation_scale
	hurt_timer = maxf(0.0, hurt_timer - delta)
	var flashing := hurt_timer > 0
	if flashing != _flash_visible:
		_flash_visible = flashing
		for mesh in flash_meshes:
			if is_instance_valid(mesh): mesh.material_overlay = flash_material if flashing else null
	if visual: visual.rotation.y = lerp_angle(visual.rotation.y, atan2(facing.x, facing.z), 1.0 - exp(-FEEL.turn_response * delta))
	if direction_indicator:
		direction_indicator.visible = not dead
		direction_indicator.rotation.y = visual.rotation.y if visual else atan2(facing.x, facing.z)

func _physics_process(delta: float) -> void:
	if suspended or simulation_scale <= 0: return
	if not is_player and not dead and combat:
		var hit_facing := ENEMY_HIT_REACTION.take_facing(combat)
		if not hit_facing.is_zero_approx(): facing = hit_facing
	invulnerability = maxf(0, invulnerability - delta)
	var step = combat.action_step if combat and combat.action_step >= 0 else delta
	var paused_pose = combat != null and combat.impact_pause > 0
	var staggered = combat != null and combat.stagger_remaining > 0
	var timeline_active = combat != null and action_cursor < action_timeline_duration - 0.000001
	action_time = maxf(float(combat.busy), (action_timeline_duration - action_cursor) / maxf(0.01, action_speed)) if combat else maxf(0, action_time - step)
	if animation:
		animation.speed_scale = 1.0
		var animation_step = maxf(0.0, minf(action_timeline_duration, combat.action_elapsed * action_speed) - action_cursor) if timeline_active else step * (action_speed if action_time > 0 else 1.0)
		animation.advance(animation_step * animation_state_speed)
	if dead and (is_player or combat == null or not combat.custom_properties.get("_enemy_death_started", false)):
		return
	var response = FEEL.braking if desired_velocity.length_squared() < locomotion.length_squared() else FEEL.acceleration
	if locomotion.dot(desired_velocity) < 0: response = FEEL.reverse_acceleration
	locomotion = Vector3.ZERO if timeline_active else locomotion.move_toward(desired_velocity, response * delta)
	var horizontal = locomotion + impulse
	if timeline_active:
		var displacement = _action_displacement()
		horizontal = impulse + displacement / maxf(delta, 0.00001)
	else:
		_set_motion_collision(false)
	# A pause confirmed after combat.tick applies to the next local clock step.
	if (paused_pose or staggered) and step <= 0.000001: horizontal = Vector3.ZERO
	if knockback_elapsed >= 0 and not paused_pose:
		var before = knockback_progress(knockback_elapsed / knockback_duration)
		knockback_elapsed += delta
		var after = knockback_progress(knockback_elapsed / knockback_duration)
		horizontal = knockback_direction * knockback_distance * (after - before) / maxf(delta, 0.00001)
		if knockback_elapsed >= knockback_duration: knockback_elapsed = -1.0
	if dodge_elapsed >= 0:
		var before = dodge_progress(dodge_elapsed / FEEL.dodge_duration)
		dodge_elapsed += delta
		var after = dodge_progress(dodge_elapsed / FEEL.dodge_duration)
		horizontal = dodge_vector * FEEL.dodge_distance * (after - before) / maxf(delta, 0.00001)
		if dodge_elapsed >= FEEL.dodge_duration: dodge_elapsed = -1.0
	if not is_player and not dead and combat:
		var hit_step: float = combat.enemy_hit_motion_step
		if hit_step < 0:
			hit_step = ENEMY_HIT_REACTION.motion_delta(combat, maxf(0.0, delta - maxf(combat.frozen, maxf(combat.impact_pause, combat.stagger_remaining))), true)
		horizontal += ENEMY_HIT_REACTION.advance_motion(combat, hit_step) / maxf(delta, 0.00001)
		combat.enemy_hit_motion_step = -1.0
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	impulse = impulse.move_toward(Vector3.ZERO, delta * 24)
	velocity.y = maxf(-25, velocity.y - 24 * delta)
	# Source collisionless point moves stay on their starting plane.
	if is_on_floor() or _motion_ignores_world:
		velocity.y = 0
	# CharacterBody3D integrates with the engine tick, while battle time is local.
	velocity *= simulation_scale
	move_and_slide()
	velocity /= simulation_scale
	if knockback_elapsed >= 0:
		for index in get_slide_collision_count():
			if get_slide_collision(index).get_normal().dot(knockback_direction) < -0.25:
				knockback_elapsed = -1.0
				break
	if not dead and action_time <= 0 and not paused_pose and not staggered:
		if desired_velocity.length_squared() > 0.2:
			face_direction(desired_velocity)
			play_animation("run")
		else:
			play_animation("idle")
