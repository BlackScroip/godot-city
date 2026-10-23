class_name DungeonActor
extends CharacterBody3D

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
var suspended := false
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
var action_motion: Array[Dictionary] = []
var direction_indicator: DungeonPlayerIndicator
var knockback_elapsed := -1.0
var knockback_distance := 0.0
var knockback_duration := 0.12
var knockback_direction := Vector3.ZERO
var _telegraph_sequence := -1
var _telegraph_turn_speed := 0.0
var impact_bounds := AABB(Vector3(-0.35, 0, -0.35), Vector3(0.7, 1.5, 0.7))

func flash_hit() -> void:
	hit_flash(0.09)

func _ready() -> void:
	set_physics_process(false)
	collision_layer = 2 if is_player else 4
	collision_mask = 1 | (4 if is_player else 2)
	var shape = CollisionShape3D.new()
	var capsule = CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.5
	shape.shape = capsule
	shape.position.y = 0.8
	add_child(shape)
	navigation = NavigationAgent3D.new()
	navigation.radius = 0.35
	navigation.height = 1.5
	navigation.path_desired_distance = 0.4
	navigation.target_desired_distance = 0.6
	add_child(navigation)
	if is_player:
		direction_indicator = DungeonPlayerIndicator.new()
		direction_indicator.name = "DirectionIndicator"
		add_child(direction_indicator)

func set_visual(path: String, metadata: Dictionary = {}) -> void:
	animation = null
	animations.clear()
	animation_aliases.clear()
	visual_loaded = false
	if is_instance_valid(visual):
		visual.queue_free()
	visual = null
	if not path.is_empty() and ResourceLoader.exists(path):
		var scene = load(path)
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
	add_child(visual)
	flash_meshes.clear()
	for mesh in visual.find_children("*", "MeshInstance3D", true, false): flash_meshes.append(mesh)
	var bounds_found := false
	for mesh in flash_meshes:
		if mesh.mesh == null: continue
		var bounds: AABB = (global_transform.affine_inverse() * mesh.global_transform) * mesh.get_aabb()
		impact_bounds = impact_bounds.merge(bounds) if bounds_found else bounds
		bounds_found = true
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
	kind = str(animation_aliases.get(kind.to_lower(), kind))
	if animation.has_animation(kind):
		if restart or animation.current_animation != kind or not animation.is_playing(): animation.play(kind, 0.05)
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
					animation.play(name, 0.12)
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
	action_motion.clear()
	dodge_vector = direction.normalized()
	face_direction(dodge_vector)
	dodge_elapsed = 0.0
	impulse = Vector3.ZERO
	locomotion = Vector3.ZERO

func clear_impact_state() -> void:
	knockback_elapsed = -1.0
	knockback_distance = 0.0
	impulse = Vector3.ZERO
	hurt_timer = 0.0
	if combat: combat.clear_impact_state()
	for mesh in flash_meshes:
		if is_instance_valid(mesh): mesh.material_overlay = null

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

func _process(delta: float) -> void:
	if suspended: return
	hurt_timer = maxf(0.0, hurt_timer - delta)
	for mesh in flash_meshes:
		if is_instance_valid(mesh): mesh.material_overlay = flash_material if hurt_timer > 0 else null
	if visual: visual.rotation.y = lerp_angle(visual.rotation.y, atan2(facing.x, facing.z), 1.0 - exp(-FEEL.turn_response * delta))
	if direction_indicator:
		direction_indicator.visible = not dead
		direction_indicator.rotation.y = visual.rotation.y if visual else atan2(facing.x, facing.z)

func _physics_process(delta: float) -> void:
	if suspended: return
	invulnerability = maxf(0, invulnerability - delta)
	var step = combat.action_step if combat and combat.action_step >= 0 else delta
	var paused_pose = combat != null and combat.impact_pause > 0
	var staggered = combat != null and combat.stagger_remaining > 0
	action_time = float(combat.busy) if combat else maxf(0, action_time - step)
	if animation:
		animation.speed_scale = 1.0
		animation.advance(step * (action_speed if action_time > 0 else 1.0))
	if dead:
		return
	var response = FEEL.braking if desired_velocity.length_squared() < locomotion.length_squared() else FEEL.acceleration
	if locomotion.dot(desired_velocity) < 0: response = FEEL.reverse_acceleration
	locomotion = locomotion.move_toward(desired_velocity, response * delta)
	var horizontal = locomotion + impulse
	if not action_motion.is_empty():
		horizontal = impulse
		for i in range(action_motion.size() - 1, -1, -1):
			var motion = action_motion[i]
			if motion.get("input_motion", false):
				var strength = clampf(desired_velocity.length() / maxf(0.01, combat.move_speed), 0, 1) if motion.get("scale_input", false) else 1.0
				motion.velocity = desired_velocity.normalized() * float(motion.speed) * strength
			horizontal += motion.velocity * minf(step, float(motion.remaining)) / maxf(delta, 0.00001)
			motion.remaining -= step
			if motion.remaining <= 0: action_motion.remove_at(i)
	if paused_pose or staggered: horizontal = Vector3.ZERO
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
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	impulse = impulse.move_toward(Vector3.ZERO, delta * 24)
	velocity.y = maxf(-25, velocity.y - 24 * delta)
	if is_on_floor():
		velocity.y = 0
	move_and_slide()
	if knockback_elapsed >= 0:
		for index in get_slide_collision_count():
			if get_slide_collision(index).get_normal().dot(knockback_direction) < -0.25:
				knockback_elapsed = -1.0
				break
	if action_time <= 0 and not paused_pose and not staggered:
		if desired_velocity.length_squared() > 0.2:
			face_direction(desired_velocity)
			play_animation("run")
		else:
			play_animation("idle")
