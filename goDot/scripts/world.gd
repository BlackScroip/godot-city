class_name DungeonWorld
extends Node3D

signal enemy_defeated(enemy_id: int)
signal player_defeated
signal wave_cleared
signal room_rewards_ready
signal room_exit_ready
signal interact_requested
signal world_message(name: String, payload: Dictionary)
signal environment_action(kind: String, payload: Dictionary)
signal skill_request_resolved(slot: int, result: Dictionary)
signal impact_confirmed(impact: Dictionary)

var player: DungeonActor
var actors: Array[DungeonActor] = []
var camera: Camera3D
var environment_root: Node3D
var catalog: Dictionary = {}
var systems: RefCounted
var hud: DungeonHud
var paused := false
var fighting := false
var elapsed := 0.0
var received_hits := 0
var projectiles: Array[Dictionary] = []
var _projectile_visual_pool: Array[MeshInstance3D] = []
var _projectile_state_pool: Array[DungeonProjectile] = []
var _projectile_mesh: SphereMesh
var _projectile_materials: Array[StandardMaterial3D] = []
var _number_pool: Array[Label3D] = []
var _numbers: Array[Dictionary] = []
var _budget_warnings: Dictionary = {}
var _physics_serial := 0
var _perception: Dictionary = {}
var _enemy_scenes: Dictionary = {}
var _actor_index: Dictionary = {}
var _auto_attack := 0.0
var _wave_reported := true
var _scene_center := Vector3.ZERO
var environment_entry: Dictionary = {}
var collision_report: Dictionary = {}
var markers: Array = []
var _camera_offset := Vector3(0, 22, -17)
var test_driver := false
var defeated_count := 0
var diagnostics: Array[String] = []
var semantic_markers: Array = []
var auto_attack_mode := "normal"
var auto_attack_enabled: bool:
	get: return auto_attack_mode != "off"
	set(value): set_attack_mode("normal" if value else "off")
var _automatic_heavy_held := false
var navigation_region: NavigationRegion3D
var _navigation_cache: Dictionary = {}
var _environment_generation := 0
var _actor_serial := 0
var summon_units: Array[Dictionary] = []
var _summon_serial := 0
var room_spawn_points: Array = []
var enemy_stage_layer: int = 1
var monster_spawn_queue: Array[Dictionary] = []
var wave_spawn_queue: Array[Dictionary] = []
var _wave_spawn_wait := 0.0
var _wave_gate_remaining := 0.0
var _wave_clear_remaining := -1.0
var _wave_final := false
var room_stage := "unmanaged"
var room_fight_type := "Regular"
var _room_stage_wait := 0.0
var _entry_wave: Dictionary = {}
static var _monster_field_data: Dictionary = {}
var interactions: RefCounted
var _event_markers: Dictionary = {}
var _event_refresh_at := 0
var ground_loot = preload("res://scripts/ground_loot.gd").new()
var spirit_followers = preload("res://scripts/presentation/spirit_followers.gd").new()
var camera_closeup = preload("res://scripts/presentation/camera_closeup.gd").new()
var _outcome_camera := false

func update_event_markers(camp: bool) -> void:
	if not camp or not interactions or not systems: return
	var now := Time.get_ticks_msec()
	if now < _event_refresh_at: return
	_event_refresh_at = now + 250
	for item in interactions._items.values():
		var pending := false
		var npc_id := int(item.data.get("NpcId", 0))
		if npc_id > 0:
			for row in systems.catalog.rows("NPCFunctionData"):
				if int(row.get("npc_index", 0)) != npc_id or not row.get("is_onetime_option", false): continue
				if systems.npc_function_status(int(row.id)).get("success", false):
					pending = true
					break
		var page_id := str(interactions.prompt_for(item)[1])
		if page_id == "buildings":
			for row in systems.catalog.rows("Buildings"):
				var level: int = systems.rank(systems.profile.data.buildings, row.id)
				if level >= int(row.max_level) or not systems.is_unlocked(int(systems._part(row.unlock_data_id, level))): continue
				var price: Dictionary = systems.costs(systems._part(row.need_materials, level, ";"))
				systems._add(price, 101, int(systems._part(row.need_gold, level)))
				var affordable := true
				for key in price:
					if not str(key).is_valid_int() or int(price[key]) < 0 or systems.material(int(key)) < int(price[key]): affordable = false
				if affordable:
					pending = true
					break
		if page_id == "partners":
			for row in systems.catalog.rows("MonsterPartnerData"):
				if systems.rank(systems.profile.data.partners, row.id) == 0 and systems.stat("kill:" + str(int(row.enemy_id))) >= int(row.unlock_need_kill_count):
					pending = true
					break
		if page_id in ["tasks", "achievements"]:
			for row in systems.catalog.rows("SubAchieveData"):
				var status: Dictionary = systems.task_status(int(row.id))
				if status.get("available", false) and status.get("complete", false) and not status.get("claimed", false):
					pending = true
					break
		pending = pending and item.state.enabled and not item.state.broken
		var badge = _event_markers.get(item.id)
		if pending and not is_instance_valid(badge):
			badge = Label3D.new()
			badge.text = "!"
			badge.font_size = 80
			badge.pixel_size = 0.012
			badge.modulate = Color(1.0, 0.8, 0.15)
			badge.outline_size = 16
			badge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			badge.no_depth_test = true
			environment_root.add_child(badge)
			badge.position = item.position + Vector3.UP * 3.5
			_event_markers[item.id] = badge
		if is_instance_valid(badge): badge.visible = pending
const FEEL = preload("res://assets/feel_settings.tres")
var intent = preload("res://scripts/player_intent.gd").new()
var presentation: Node3D
var camera_shake_enabled := true
var low_effects := false
var _camera_focus := Vector3.ZERO
var _camp_camera := false
var _shake := 0.0
var _shake_clock := 0.0
var _auto_target: DungeonActor
var _automatic_action := false
var _background := false
var _input_suspended := false
const HitFeedback = preload("res://scripts/presentation/hit_feedback.gd")
const ImpactProfiles = preload("res://scripts/presentation/impact_profiles.gd")
var _camera_impulses: Array[Dictionary] = []
var _impact_clock := 0.0
var _impact_serial := 0
var _seen_impacts: Dictionary = {}
var _seen_blasts: Dictionary = {}

func _ready() -> void:
	add_child(ground_loot)
	add_child(spirit_followers)
	var file = FileAccess.open("res://assets/catalog.json", FileAccess.READ)
	if file: catalog = JSON.parse_string(file.get_as_text())
	var sky = WorldEnvironment.new()
	var environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("7b9c8c")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("c6deca")
	environment.ambient_light_energy = 0.45
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	sky.environment = environment
	add_child(sky)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_color = Color("fff0c3")
	sun.light_energy = 0.65
	sun.shadow_enabled = true
	add_child(sun)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = 19
	camera.far = 200
	camera.current = true
	add_child(camera)
	presentation = preload("res://scripts/presentation/combat_presentation.gd").new()
	add_child(presentation)
	presentation.configure(catalog)
	_projectile_mesh = SphereMesh.new()
	_projectile_mesh.radius = 0.13
	_projectile_mesh.height = 0.26
	for color in [Color("82e0cb"), Color("f4a65c")]:
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_projectile_materials.append(material)
	for index in 32:
		_projectile_visual_pool.append(_make_projectile_visual())
		_projectile_state_pool.append(DungeonProjectile.new())
	for index in 32: _number_pool.append(_make_damage_number())

func asset_path(kind: String, id: Variant) -> String:
	var entry = catalog.get(kind, {}).get(str(id), {})
	return str(entry.get("path", "")) if entry is Dictionary else str(entry)

func release_environment() -> void:
	# Callers may yield a frame here so queued GPU/scene resources retire before loading.
	_environment_generation += 1
	room_spawn_points.clear()
	enemy_stage_layer = 1
	monster_spawn_queue.clear()
	wave_spawn_queue.clear()
	_wave_spawn_wait = 0.0
	_wave_gate_remaining = 0.0
	_wave_clear_remaining = -1.0
	room_stage = "unmanaged"
	room_fight_type = "Regular"
	_room_stage_wait = 0.0
	_entry_wave.clear()
	camera_closeup.restore()
	_outcome_camera = false
	spirit_followers.clear()
	if not ground_loot.get_parent(): add_child(ground_loot)
	ground_loot.clear()
	_event_markers.clear()
	_event_refresh_at = 0
	intent.clear(player.combat if is_instance_valid(player) else null)
	intent.last_move = Vector3.ZERO
	_auto_target = null
	_automatic_action = false
	_automatic_heavy_held = false
	_perception.clear()
	_actor_index.clear()
	_enemy_scenes.clear()
	_budget_warnings.clear()
	for number in _numbers:
		number.node.hide()
		_number_pool.append(number.node)
	_numbers.clear()
	if presentation: presentation.release_room_resources()
	_camera_impulses.clear()
	_seen_impacts.clear()
	_seen_blasts.clear()
	for actor in actors:
		if is_instance_valid(actor): actor.queue_free()
	actors.clear()
	player = null
	for projectile in projectiles:
		_recycle_projectile(projectile)
	projectiles.clear()
	for unit in summon_units:
		if is_instance_valid(unit.get("visual")): unit.visual.queue_free()
	summon_units.clear()
	if is_instance_valid(environment_root):
		remove_child(environment_root)
		environment_root.queue_free()
	environment_root = null
	interactions = null
	navigation_region = null
	fighting = false

func load_environment(id: Variant, camp := false) -> void:
	release_environment()
	_camp_camera = camp
	environment_root = Node3D.new()
	add_child(environment_root)
	var path = asset_path("environments", id)
	if path.is_empty(): path = str(catalog.get("defaults", {}).get("camp" if camp else "environment", ""))
	if not path.is_empty() and ResourceLoader.exists(path):
		var source = load(path)
		if source is PackedScene: environment_root.add_child(source.instantiate())
	_scene_center = Vector3.ZERO
	var entry = catalog.get("environments", {}).get(str(id), {})
	environment_entry = entry if entry is Dictionary else {}
	if entry is Dictionary:
		var bounds = entry.get("bounds", {})
		if bounds is Dictionary and bounds.has("center"):
			_scene_center = vector(bounds.center)
	_load_collisions(path)
	interactions = load("res://scripts/world_interactions.gd").new()
	interactions.transition_requested.connect(func(context): environment_action.emit("transition", context))
	interactions.npc_requested.connect(func(id, context):
		context["npc_id"] = id
		environment_action.emit("npc", context))
	interactions.reward_requested.connect(func(context): environment_action.emit("reward", context))
	interactions.message_requested.connect(func(message, context):
		if message == "EnvUnit_InteractProtectTarget": start_protection_encounter()
		else: world_message.emit(message, context))
	interactions.player_trigger_entered.connect(func(id, _context):
		if id == 1: enter_room_encounter())
	interactions.trap_triggered.connect(_environment_trap)
	interactions.diagnostic_reported.connect(func(context): _diagnostic("Environment: " + str(context)))
	interactions.setup(environment_root, semantic_markers, {"colliders": markers, "catalog": systems.catalog if systems else null, "is_unlocked": func(id): return systems.is_unlocked(int(id)) if systems else false})
	_build_navigation(str(id))
	var angles: Array = environment_entry.get("camera_rotation", [45.0, -45.0])
	var elevation = deg_to_rad(float(angles[0]))
	var yaw = deg_to_rad(float(angles[1]))
	var distance = 29.0 if camp else FEEL.level_camera_height / (2.0 * tan(deg_to_rad(FEEL.level_camera_fov * 0.5)))
	_camera_offset = Vector3(-sin(yaw) * cos(elevation), sin(elevation), -cos(yaw) * cos(elevation)) * distance
	fighting = false
	elapsed = 0
	received_hits = 0
	_wave_reported = true
	DungeonWorldStyle.environment(self, int(str(id).substr(2, 1)), camp)
	camera.size = 17.0 if camp else FEEL.level_camera_height
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL if camp else Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = FEEL.level_camera_fov

func _load_collisions(path: String) -> void:
	var sidecar_path = path.trim_suffix(".glb") + ".markers.json"
	markers.clear()
	semantic_markers.clear()
	collision_report = {"loaded": 0, "triggers": 0, "inactive": 0, "missing_mesh": []}
	if not FileAccess.file_exists(sidecar_path): return
	var sidecar = JSON.parse_string(FileAccess.get_file_as_string(sidecar_path))
	if not sidecar is Dictionary: return
	markers = sidecar.get("markers", [])
	semantic_markers = sidecar.get("semantic_markers", [])
	for item in markers:
		var properties: Dictionary = item.get("properties", {})
		if not item.get("active", true) or not properties.get("m_Enabled", 1):
			collision_report.inactive += 1
			continue
		if properties.get("m_IsTrigger", 0):
			collision_report.triggers += 1
			continue
		if int(item.get("kind", 0)) not in [64, 65, 135, 136]: continue
		var matrix = unity_matrix(item.get("world_matrix", []))
		var body = StaticBody3D.new()
		body.name = "Collider_" + str(item.get("fileID", ""))
		body.position = matrix.origin
		body.collision_layer = 1
		var shape = CollisionShape3D.new()
		var center = vector(properties.get("m_Center", {}))
		match int(item.kind):
			65:
				var half_size = vector(properties.get("m_Size", {})).abs().max(Vector3.ONE * 0.001) * 0.5
				var points = PackedVector3Array()
				for x in [-1, 1]:
					for y in [-1, 1]:
						for z in [-1, 1]: points.append(matrix.basis * (center + half_size * Vector3(x, y, z)))
				var convex = ConvexPolygonShape3D.new()
				convex.points = points
				shape.shape = convex
			135:
				var sphere = SphereShape3D.new()
				var sizes = matrix.basis.get_scale().abs()
				sphere.radius = maxf(0.001, float(properties.get("m_Radius", 0.5)) * sizes[sizes.max_axis_index()])
				shape.shape = sphere
				shape.position = matrix.basis * center
			136:
				var axis = int(properties.get("m_Direction", 1))
				var sizes = matrix.basis.get_scale().abs()
				var capsule = CapsuleShape3D.new()
				capsule.radius = maxf(0.001, float(properties.get("m_Radius", 0.5)) * maxf(sizes[(axis + 1) % 3], sizes[(axis + 2) % 3]))
				capsule.height = maxf(capsule.radius * 2, float(properties.get("m_Height", 2)) * sizes[axis])
				shape.shape = capsule
				shape.position = matrix.basis * center
				var direction = matrix.basis[axis].normalized()
				shape.quaternion = Quaternion(Vector3.UP, direction)
			64:
				var faces: Array = item.get("mesh_faces", [])
				var mesh_path = str(item.get("mesh_faces_path", ""))
				if faces.is_empty() and FileAccess.file_exists(mesh_path):
					var mesh_data = JSON.parse_string(FileAccess.get_file_as_string(mesh_path))
					if mesh_data is Dictionary: faces = mesh_data.get("faces", [])
				var vertices = PackedVector3Array()
				for index in range(0, faces.size() - 2, 3): vertices.append(matrix.basis * Vector3(faces[index], faces[index + 1], faces[index + 2]))
				if vertices.is_empty():
					collision_report.missing_mesh.append(str(item.get("fileID", "")))
					body.free()
					shape.free()
					continue
				var triangle_shape = ConcavePolygonShape3D.new()
				triangle_shape.set_faces(vertices)
				triangle_shape.backface_collision = true
				shape.shape = triangle_shape
		body.add_child(shape)
		environment_root.add_child(body)
		collision_report.loaded += 1

static func unity_matrix(values: Array) -> Transform3D:
	if values.size() != 16: return Transform3D.IDENTITY
	return Transform3D(Basis(Vector3(values[0], values[4], values[8]), Vector3(values[1], values[5], values[9]), Vector3(values[2], values[6], values[10])), Vector3(values[3], values[7], values[11]))

func _build_navigation(key: String) -> void:
	navigation_region = NavigationRegion3D.new()
	environment_root.add_child(navigation_region)
	var mesh: NavigationMesh = _navigation_cache.get(key)
	if mesh == null:
		mesh = NavigationMesh.new()
		mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
		mesh.geometry_collision_mask = 1
		mesh.cell_size = 0.25
		mesh.cell_height = 0.1
		mesh.agent_radius = 0.5
		mesh.agent_height = 1.5
		mesh.agent_max_climb = 0.3
		mesh.filter_walkable_low_height_spans = true
		var source = NavigationMeshSourceGeometryData3D.new()
		NavigationServer3D.parse_source_geometry_data(mesh, source, environment_root)
		NavigationServer3D.bake_from_source_geometry_data(mesh, source)
		_navigation_cache[key] = mesh
		while _navigation_cache.size() > 3:
			_navigation_cache.erase(_navigation_cache.keys()[0])
	navigation_region.navigation_mesh = mesh
	collision_report["navigation_polygons"] = mesh.get_polygon_count()
	NavigationServer3D.map_force_update(get_world_3d().navigation_map)

func _chase(actor: DungeonActor, target: Vector3, delta: float) -> Vector3:
	actor.navigation_timer -= delta
	if actor.navigation_timer <= 0:
		actor.navigation.target_position = target
		actor.navigation_timer = 0.25
	var next = actor.navigation.get_next_path_position() if not actor.navigation.is_navigation_finished() else target
	var direction = next - actor.position
	direction.y = 0
	return direction.normalized() * float(actor.combat.move_speed)

func create_player(combat: RefCounted, character_id: int, position_data: Variant = {}) -> DungeonActor:
	player = DungeonActor.new()
	player.actor_id = character_id
	player.is_player = true
	player.combat = combat
	player.combat.actor_key = "player"
	add_child(player)
	player.position = vector(environment_entry.get("player_start", {} ) if position_data is Dictionary and position_data.is_empty() else position_data) + Vector3.UP * 0.05
	player.previous_position = player.position
	player.set_visual(asset_path("characters", character_id), catalog.get("characters", {}).get(str(character_id), {}))
	DungeonWorldStyle.apply_models(player)
	var facing = vector(environment_entry.get("player_rotation", {}))
	player.face_direction(Vector3(sin(deg_to_rad(facing.y)), 0, cos(deg_to_rad(facing.y))))
	actors.append(player)
	_actor_index[str(player.combat.actor_key)] = player
	_bind_impact(player)
	if presentation:
		presentation.low_quality = low_effects
		presentation.prepare_combat([combat])
	snap_camera()
	return player

func _camera_target() -> Vector3:
	if _camp_camera: return player.position + Vector3.UP * 0.4
	var view_basis = Basis.looking_at(-_camera_offset.normalized(), Vector3.UP)
	# Keep the same world scale on wide phones; reserve the lower area for controls.
	return player.position + view_basis.y * camera.size * (FEEL.level_player_screen_y - 0.5)

func snap_camera() -> void:
	if not is_instance_valid(player): return
	_camera_focus = _camera_target()
	camera.position = _camera_focus + _camera_offset
	camera.look_at(_camera_focus)

func spawn_wave(spawns: Array, difficulty: int, seed_value: int) -> void:
	fighting = true
	_wave_reported = false
	var index = 0
	var combats: Array = []
	for spawn in spawns:
		var actor = DungeonActor.new()
		actor.actor_id = int(spawn.get("enemy_id", spawn.get("EnemyId", 11001)))
		actor.combat = load("res://scripts/domain/combat.gd").new()
		if not actor.combat.configure_enemy(actor.actor_id, seed_value + index, difficulty, null, int(spawn.get("enemy_stage", enemy_stage_layer)), int(spawn.get("enemy_chaos", 0))).success:
			_diagnostic("Unknown spawn enemy: %d" % actor.actor_id)
			actor.free()
			continue
		_actor_serial += 1
		actor.navigation_timer = float(_actor_serial % 15) / 60.0
		actor.combat.actor_key = "enemy:%d:%d" % [actor.actor_id, _actor_serial]
		var hp_override = float(spawn.get("health_override", spawn.get("HealthOverride", 0)))
		if hp_override > 0:
			actor.combat.max_health = hp_override
			actor.combat.health = hp_override
		var attack_override = float(spawn.get("attack_override", spawn.get("AttackOverride", 0)))
		if attack_override > 0: actor.combat.attack = attack_override
		for buff in spawn.get("passive_buff_ids", spawn.get("PassiveBuffIds", [])):
			actor.combat.add_buff(str(buff), 1)
		actor.combat.health = actor.combat.max_health
		add_child(actor)
		var point = vector(spawn.get("position", spawn.get("Position", {})))
		if not spawn.has("position") and not spawn.has("Position"):
			point = player.position + Vector3(sin(index * 2.4) * 7, 0, cos(index * 2.4) * 7)
		actor.position = point + Vector3.UP * 0.05
		actor.born_position = vector(spawn.get("born_position", point)) + Vector3.UP * 0.05
		var yaw = deg_to_rad(vector(spawn.get("rotation", spawn.get("Rotation", {}))).y)
		actor.born_facing = Vector3(sin(yaw), 0, cos(yaw))
		actor.face_direction(actor.born_facing)
		actor.field_center = _monster_field_center("300021", actor.born_position)
		actor.previous_position = actor.position
		actor.set_visual(asset_path("enemies", actor.actor_id), catalog.get("enemies", {}).get(str(actor.actor_id), {}), _prepare_enemy_scene(actor.actor_id))
		if actor.visual: actor.visual.rotation.y = yaw
		DungeonWorldStyle.apply_models(actor)
		actors.append(actor)
		_actor_index[str(actor.combat.actor_key)] = actor
		_bind_impact(actor)
		actor.combat.begin_enemy_spawn()
		for event in actor.combat.drain_events(): _consume(actor, event)
		combats.append(actor.combat)
		index += 1
	if presentation:
		presentation.low_quality = low_effects
		presentation.prepare_combat(combats)

func arm_room_encounter(spawns: Array, difficulty: int, seed_value: int, final_wave: bool) -> void:
	room_stage = "entry"
	fighting = false
	_entry_wave = {"spawns": spawns.duplicate(true), "difficulty": difficulty, "seed": seed_value, "final": final_wave}
	sync_room_gates()
	if interactions.set_trigger_active(1, true) == 0:
		_diagnostic("Combat room has no authored entry trigger 1")

func enter_room_encounter() -> void:
	if room_stage != "entry" or _entry_wave.is_empty() or not is_instance_valid(player) or player.dead: return
	if room_fight_type == "ProtectTarget":
		room_stage = "protection"
		sync_room_gates()
		return
	_start_entry_wave()

func start_protection_encounter() -> void:
	if room_stage != "protection" or _entry_wave.is_empty() or not is_instance_valid(player) or player.dead: return
	_start_entry_wave()

func _start_entry_wave() -> void:
	var request = _entry_wave
	_entry_wave = {}
	room_stage = "fighting"
	sync_room_gates()
	start_wave(request.spawns, int(request.difficulty), int(request.seed), 0.0, bool(request.final))

func begin_room_clear() -> void:
	if room_stage in ["clearing", "rewards", "open"]: return
	fighting = false
	room_stage = "clearing"
	_room_stage_wait = 0.0 if room_fight_type in ["DodgeBattle", "ProtectTarget"] else 1.0
	sync_room_gates()

func prepare_noncombat_gate(flow: String, completed: bool) -> void:
	room_stage = "open"
	if not completed:
		if flow == "Curse": room_stage = "event_locked"
		elif flow in ["Entrance", "Treasure"]:
			room_stage = "opening"
			_room_stage_wait = 0.1 if flow == "Entrance" else 1.0
	sync_room_gates()

func _tick_room_sequence(delta: float) -> void:
	if room_stage not in ["clearing", "rewards", "opening"] or not is_instance_valid(player) or player.dead: return
	_room_stage_wait = maxf(0.0, _room_stage_wait - delta)
	if _room_stage_wait > 0.000001: return
	if room_stage == "clearing":
		room_stage = "rewards"
		_room_stage_wait = 1.0
		sync_room_gates()
		room_rewards_ready.emit()
	else:
		room_stage = "open"
		sync_room_gates()
		room_exit_ready.emit()

func sync_room_gates() -> void:
	if not interactions or room_stage == "unmanaged": return
	interactions.set_trigger_active(1, room_stage == "entry")
	interactions.set_battle_boundaries_active(room_stage in ["protection", "fighting", "clearing"])
	interactions.set_protection_enabled(room_stage == "protection")
	interactions.set_exit_enabled(room_stage == "open")
	interactions.set_completion_chests_enabled(room_stage in ["rewards", "open", "opening"])

func start_wave(spawns: Array, difficulty: int, seed_value: int, delay := 0.0, final_wave := false) -> void:
	wave_spawn_queue.clear()
	for index in spawns.size():
		wave_spawn_queue.append({"spawn": spawns[index].duplicate(true), "difficulty": difficulty, "seed": seed_value + index})
	fighting = true
	_wave_reported = false
	_wave_spawn_wait = maxf(0.0, delay)
	_wave_gate_remaining = _wave_spawn_wait + 2.0
	_wave_clear_remaining = -1.0
	_wave_final = final_wave
	_tick_wave_spawns(0.0)

func _tick_wave_spawns(delta: float) -> void:
	_wave_gate_remaining = maxf(0.0, _wave_gate_remaining - delta)
	if wave_spawn_queue.is_empty(): return
	_wave_spawn_wait -= delta
	while not wave_spawn_queue.is_empty() and _wave_spawn_wait <= 0.000001:
		var request: Dictionary = wave_spawn_queue.pop_front()
		spawn_wave([request.spawn], int(request.difficulty), int(request.seed))
		_wave_spawn_wait += 0.2

func _tick_wave_clear(delta: float) -> void:
	if not fighting or _wave_reported or _wave_gate_remaining > 0 or _enemy_count() > 0: return
	if _wave_final:
		if _wave_clear_remaining < 0:
			_wave_clear_remaining = 0.05
			return
		_wave_clear_remaining -= delta
		if _wave_clear_remaining > 0: return
	_wave_reported = true
	wave_cleared.emit()

func prepare_enemy_media(ids: Array) -> void:
	var combats: Array = []
	for id in ids:
		_prepare_enemy_scene(int(id))
		var combat := DungeonCombat.new()
		if combat.configure_enemy(int(id)).success: combats.append(combat)
	presentation.low_quality = low_effects
	presentation.prepare_combat(combats)

func _prepare_enemy_scene(id: int) -> PackedScene:
	if _enemy_scenes.has(id): return _enemy_scenes[id]
	var path = asset_path("enemies", id)
	if path.is_empty() or not ResourceLoader.exists(path): return null
	var scene = load(path)
	if not scene is PackedScene: return null
	if _enemy_scenes.size() >= 32: _enemy_scenes.erase(_enemy_scenes.keys()[0])
	_enemy_scenes[id] = scene
	return scene

func prepare_feedback_rendering() -> void:
	if DisplayServer.get_name() == "headless": return
	var generation := _environment_generation
	var viewport := SubViewport.new()
	viewport.size = Vector2i(64, 64)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var warm_camera := Camera3D.new()
	warm_camera.position = Vector3(0, 0.8, 4)
	warm_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	warm_camera.size = 4
	viewport.add_child(warm_camera)
	var warmed: Dictionary = {}
	for actor in actors:
		if not is_instance_valid(actor): continue
		var identity := "%s:%d" % [actor.is_player, actor.actor_id]
		if not is_instance_valid(actor.visual) or warmed.has(identity): continue
		warmed[identity] = true
		var model = actor.visual.duplicate(0)
		viewport.add_child(model)
		model.position = Vector3.ZERO
		for mesh in model.find_children("*", "MeshInstance3D", true, false): mesh.material_overlay = actor.flash_material
		await get_tree().process_frame
		if generation != _environment_generation or not is_inside_tree():
			if is_instance_valid(viewport): viewport.queue_free()
			return
		await RenderingServer.frame_post_draw
		model.queue_free()
	var label := Label3D.new()
	label.text = "0123456789"
	label.font_size = 48
	label.pixel_size = 0.008
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	viewport.add_child(label)
	for material in _projectile_materials:
		var mesh := MeshInstance3D.new()
		mesh.mesh = _projectile_mesh
		mesh.material_override = material
		viewport.add_child(mesh)
	if not presentation.pool.is_empty():
		var effect = presentation.pool[0]
		for key in ["mesh", "burst", "sparks"]:
			var node = effect[key].duplicate(0)
			viewport.add_child(node)
			node.rotation = Vector3.ZERO
			node.show()
			if node is CPUParticles3D:
				node.restart()
				node.request_particles_process(1.0 / 60)
	for frame in 3:
		await get_tree().process_frame
		if generation != _environment_generation or not is_inside_tree():
			if is_instance_valid(viewport): viewport.queue_free()
			return
		await RenderingServer.frame_post_draw
	viewport.queue_free()

func use_skill(slot: int, pressed := true) -> Dictionary:
	var result: Dictionary
	if not player or player.dead or paused or _background or (hud and hud.modal_open): result = {"success": false, "status": "rejected"}
	else:
		if pressed:
			_release_auto_heavy()
			_automatic_action = false
		result = intent.attack_button(player.combat, pressed) if slot == 0 else intent.request(player.combat, slot, pressed)
	skill_request_resolved.emit(slot, result)
	return result

func set_attack_mode(mode: String) -> void:
	var normalized = mode if mode in ["normal", "heavy", "off"] else "normal"
	if normalized == auto_attack_mode: return
	_release_auto_heavy()
	_automatic_action = false
	auto_attack_mode = normalized

func _release_auto_heavy() -> void:
	if not _automatic_heavy_held: return
	_automatic_heavy_held = false
	if is_instance_valid(player):
		player.combat.request_attack(4, false)
		# The wand otherwise keeps its authored alternating mode after release.
		player.combat.custom_properties.AttackModeStr = "normal"

func clear_input() -> void:
	_release_auto_heavy()
	intent.clear(player.combat if is_instance_valid(player) else null)
	if player:
		player.desired_velocity = Vector3.ZERO
		player.locomotion = Vector3.ZERO
	if hud:
		hud.joystick._reset()
		for key in hud.skill_buttons: key.release()
		hud.attack_mode_button.release()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		_background = true
		clear_input()
	elif what in [NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED]: _background = false

func _attack_target(slot: int) -> DungeonActor:
	var reach = _heavy_reach() if slot == 4 else 7.0 if slot != 0 else _normal_reach()
	var nearest: DungeonActor
	var candidates: Array = []
	for actor in actors:
		if not is_instance_valid(actor) or actor.dead or actor.is_player: continue
		var distance = player.position.distance_squared_to(actor.position)
		if distance > reach * reach: continue
		candidates.append({"actor": actor, "score": distance * (0.64 if actor == _auto_target else 1.0)})
	candidates.sort_custom(func(a, b): return a.score < b.score)
	for candidate in candidates:
		var actor: DungeonActor = candidate.actor
		var query = PhysicsRayQueryParameters3D.create(player.position + Vector3.UP * 0.8, actor.position + Vector3.UP * 0.8, 1)
		if not get_world_3d().direct_space_state.intersect_ray(query).is_empty(): continue
		nearest = actor
		break
	_auto_target = nearest
	return nearest

func _heavy_reach() -> float:
	# Ranged heavy families retain the existing ranged targeting distance.
	return 7.0 if player.combat.character_id in [4, 5, 6] else 3.0

func _normal_reach() -> float:
	var combo: Array = player.combat.fighter.get("combo", [])
	if combo.is_empty(): return 2.0
	var next = str(player.combat.custom_properties.get("_feel_next_combo", ""))
	if player.combat._clock > player.combat._combo_expiry: next = str(combo[0])
	if next.is_empty(): next = str(combo[player.combat._combo % combo.size()])
	var action = player.combat._action("ActGroup_playerchara", next)
	var reach = 1.0
	for hit in action.get("hits", []):
		if not hit.get("enabled", false): continue
		if hit.get("projectile", false): return 7.0
		reach = maxf(reach, float(hit.get("offset", 0)) + float(hit.get("length", 1)) * 0.5 + 0.35)
	return clampf(reach, 1.0, 7.0)

func _movement_allows_auto_attack(target: DungeonActor) -> bool:
	if not is_instance_valid(target): return false
	if player.desired_velocity.length_squared() < 0.04: return true
	var direction = target.position - player.position
	direction.y = 0
	return player.desired_velocity.normalized().dot(direction.normalized()) >= FEEL.auto_attack_move_alignment

func _execute_player(slot: int, automatic := false, selected_target: DungeonActor = null) -> bool:
	var target = selected_target if is_instance_valid(selected_target) else _attack_target(slot) if slot != 1 else null
	var result = player.combat.request_attack(slot)
	if not result.get("success", false): return false
	player.combat.custom_properties["_auto_heavy_only"] = automatic and slot == 4
	_automatic_action = automatic
	if slot == 1:
		player.face_direction(intent.dodge_direction(player.desired_velocity, player.facing))
		intent.clear()
	elif target: player.face_direction(target.position - player.position)
	return true

func _process(delta: float) -> void:
	if not paused and not _background and not (hud and hud.modal_open): _tick_damage_numbers(delta)
	if not is_instance_valid(player) or player.dead: return
	var stopped = paused or _background or (hud and hud.modal_open)
	if presentation:
		presentation.suspended = stopped
		presentation.low_quality = low_effects
	camera_closeup.pause(stopped)
	if stopped: return
	_tick_monster_spawns()
	if not _outcome_camera:
		camera_closeup.update_action(player, player.combat.action_elapsed * float(player.combat.custom_properties.get("_feel_action_speed", 1)) * 1000.0)
	camera_closeup.step(delta)
	var focus = _camera_target() + player.locomotion.limit_length(1.0) * FEEL.camera_lookahead
	_camera_focus = _camera_focus.lerp(focus, 1.0 - exp(-FEEL.camera_response * delta))
	var offset = Vector3.ZERO
	for i in range(_camera_impulses.size() - 1, -1, -1):
		var shake = _camera_impulses[i]
		shake.age += delta
		var age = float(shake.age) - float(shake.delay)
		if age < 0: continue
		if age >= float(shake.duration):
			_camera_impulses.remove_at(i)
			continue
		var phase = age / maxf(0.001, float(shake.duration))
		var magnitude = float(shake.get("amplitude", float(shake.get("intensity", 0)) * 0.22)) * pow(1.0 - phase, 2)
		var wave = sin(phase * TAU * maxi(1, int(shake.get("times", 3))))
		offset += Vector3(0 if shake.get("disable_x", false) else wave, 0 if shake.get("disable_y", false) else cos(phase * TAU * maxi(1, int(shake.get("times", 3)))), 0) * magnitude
	if not camera_shake_enabled: offset = Vector3.ZERO
	offset = offset.limit_length(FEEL.camera_impact_limit)
	camera_closeup.apply(camera, _camera_focus, _camera_offset)
	camera.position += camera.basis * offset

func _camera_conditions(event: Dictionary) -> bool:
	var conditions: Array = []
	for raw in event.get("Conditions", []):
		conditions.append({"type": str(raw.get("ConditionType", "")), "buff": str(raw.get("BuffId", "")), "exists": bool(raw.get("IsExist", true)), "layers": int(raw.get("CheckLayerCount", 1)), "compare": str(raw.get("CompareType", "ECT_GreaterEqual")), "property": str(raw.get("CustomProperty", "")), "value": raw.get("CompareVal", 0), "raw": JSON.stringify(raw)})
	return player.combat._conditions(conditions, bool(event.get("CheckAllCondition", true)))

func begin_outcome_camera(action: String) -> void:
	_outcome_camera = true
	camera_closeup.pause(false)
	camera_closeup.enter(player, action, _camera_conditions)

func tick_outcome_camera(elapsed_time: float, delta: float) -> void:
	if not _outcome_camera or _background: return
	camera_closeup.pause(false)
	camera_closeup.update_action(player, elapsed_time * 1000.0)
	camera_closeup.step(delta)
	camera_closeup.apply(camera, _camera_focus, _camera_offset)

func end_outcome_camera() -> void:
	_outcome_camera = false
	camera_closeup.exit(player)

func _physics_process(delta: float) -> void:
	if not player: return
	spirit_followers.sync_from_run(systems, player)
	var stopped = paused or _background or (hud and hud.modal_open)
	if stopped and not _input_suspended: clear_input()
	_input_suspended = stopped
	for actor in actors:
		if is_instance_valid(actor): actor.suspended = stopped
	if stopped:
		for actor in actors:
			if is_instance_valid(actor): actor.desired_velocity = Vector3.ZERO
		return
	_physics_serial += 1
	_tick_room_sequence(delta)
	spirit_followers.advance(delta, player)
	if systems and not player.dead:
		if not ground_loot.advance_collection(delta, player.position, systems).is_empty():
			environment_action.emit("auto_loot", {})
	_impact_clock += delta
	for cache in [_seen_impacts, _seen_blasts]:
		for key in cache.keys():
			if _impact_clock - float(cache[key]) > 8.0: cache.erase(key)
	if fighting: elapsed += delta
	_tick_wave_spawns(delta)
	var movement = Vector2.ZERO
	if not hud or not hud.modal_open:
		movement = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if hud: movement += hud.joystick.value
		movement = movement.limit_length()
	var right = camera.global_basis.x
	var forward = -camera.global_basis.z
	right.y = 0
	forward.y = 0
	player.desired_velocity = (right.normalized() * movement.x - forward.normalized() * movement.y) * float(player.combat.move_speed)
	if player.desired_velocity.length_squared() > 0.0001: intent.last_move = player.desired_velocity.normalized()
	if test_driver and fighting:
		var nearest = _nearest_enemy(player.position)
		if nearest:
			var direction = nearest.position - player.position
			direction.y = 0
			player.desired_velocity = _chase(player, nearest.position, delta) if direction.length() > 1.5 else Vector3.ZERO
	if _automatic_action and player.combat._current_slot == 0 and player.desired_velocity.length_squared() >= 0.04:
		if not _movement_allows_auto_attack(_auto_target):
			player.combat.cancel_normal_attack()
			_automatic_action = false
	_tick_player_input(delta)
	var monster_indices: Dictionary = {}
	_warn_budget("actors", actors.size(), FEEL.actor_warning_budget)
	for actor in actors.duplicate():
		if not is_instance_valid(actor): continue
		if actor.dead:
			if not actor.is_player:
				actor.advance_death(delta)
				for event in actor.combat.drain_events(): _consume(actor, event)
				if actor.death_finished():
					_perception.erase(actor.get_instance_id())
					_actor_index.erase(str(actor.combat.actor_key))
					actors.erase(actor)
					actor.queue_free()
			continue
		_bind_impact(actor)
		var enemy_distances: Array = []
		if actor.is_player:
			for other in actors:
				if is_instance_valid(other) and not other.dead and not other.is_player: enemy_distances.append(actor.position.distance_to(other.position))
		elif not player.dead: enemy_distances.append(actor.position.distance_to(player.position))
		actor.combat.custom_properties["EnemyDistances"] = enemy_distances
		var travelled = actor.position.distance_to(actor.previous_position)
		actor.previous_position = actor.position
		actor.combat.custom_properties["InputMove"] = actor.desired_velocity.length_squared() > 0.01
		actor.combat.notify_gameplay("move", {"moving": actor.desired_velocity.length_squared() > 0.01, "distance": travelled, "delta": delta})
		if not actor.is_player:
			var direction = player.position - actor.position
			direction.y = 0
			var monster_index = int(monster_indices.get(actor.actor_id, 0))
			monster_indices[actor.actor_id] = monster_index + 1
			var blocked = _line_blocked(actor, direction.length_squared())
			actor.combat.custom_properties["_navigation_steer"] = blocked
			actor.combat.tick_enemy_ai(delta, {"target_available": not player.dead, "distance": direction.length(), "line_blocked": blocked, "battle_time": elapsed, "monster_index": monster_index, "target_buffs": player.combat.statuses.keys()})
			actor.desired_velocity = _chase(actor, player.position, delta) if actor.combat.enemy_navigation_requested() and not player.dead else Vector3.ZERO
		actor.combat.tick(delta)
		for event in actor.combat.drain_events(): _consume(actor, event)
		if actor.combat.health <= 0: _die(actor)
	for actor in actors:
		if is_instance_valid(actor): actor._physics_process(delta)
	_tick_projectiles(delta)
	_tick_summons(delta)
	if interactions:
		var targets: Array = []
		for actor in actors:
			if is_instance_valid(actor) and not actor.dead and not actor.is_player: targets.append({"id": str(actor.combat.actor_key), "position": actor.position, "camp": 1})
		interactions.tick(delta, player.position, targets)
	_tick_wave_clear(delta)

func _tick_player_input(delta: float) -> void:
	intent.advance_hold(player.combat, delta)
	if _automatic_heavy_held:
		if player.dead or intent.manual_attack_active() or not fighting or not _movement_allows_auto_attack(_attack_target(4)):
			_release_auto_heavy()
		elif player.combat.busy <= 0:
			_release_auto_heavy()
	var requested = intent.take_ready(player.combat, delta)
	if requested >= 0:
		var executed = _execute_player(requested)
		skill_request_resolved.emit(requested, {"success": executed, "status": "executed" if executed else "rejected"})
	elif not intent.manual_attack_active() and auto_attack_enabled and fighting and not player.dead and player.combat.busy <= 0 and player.dodge_elapsed < 0:
		var slot = 4 if auto_attack_mode == "heavy" else 0
		if player.combat.input_block_reason(slot).is_empty() and player.combat.cooldowns[slot] <= 0:
			var target = _attack_target(slot)
			if _movement_allows_auto_attack(target) and _execute_player(slot, true, target):
				_automatic_heavy_held = slot == 4

func _line_blocked(actor: DungeonActor, distance_squared: float) -> bool:
	var key := actor.get_instance_id()
	var cached: Dictionary = _perception.get(key, {})
	var stride := maxi(1, roundi(FEEL.perception_interval * Engine.physics_ticks_per_second))
	var urgent: bool = distance_squared <= 36.0 or actor.combat.busy > 0 or cached.is_empty()
	if not cached.is_empty():
		urgent = urgent or actor.position.distance_squared_to(cached.origin) > 0.25 or player.position.distance_squared_to(cached.target) > 0.25 or bool(cached.blocked)
	if urgent or (_physics_serial + key) % stride == 0:
		var query = PhysicsRayQueryParameters3D.create(actor.position + Vector3.UP * 0.8, player.position + Vector3.UP * 0.8, 1)
		cached = {"origin": actor.position, "target": player.position, "blocked": not get_world_3d().direct_space_state.intersect_ray(query).is_empty()}
		_perception[key] = cached
	return bool(cached.blocked)

func _consume(actor: DungeonActor, event: Dictionary) -> void:
	match str(event.get("type", event.get("kind", ""))):
		"action_started":
			if actor.is_player and not _outcome_camera: camera_closeup.enter(actor, str(event.get("action", "")), _camera_conditions)
			_cancel_attached_projectiles(actor, int(event.sequence), true)
			actor.begin_action(event)
			if not actor.is_player: actor.action_target = player if is_instance_valid(player) and not player.dead else null
			presentation.action_started(actor, event)
			var action_name = str(event.get("action", ""))
			actor.play_animation(action_name if actor.animations.has(action_name) else "dodge" if int(event.get("slot", 0)) == 1 else "attack", true)
			if int(event.get("slot", 0)) == 1:
				actor.invulnerability = 0.35
				actor.start_dodge(actor.facing)
		"action_cancelled":
			if actor.is_player and not _outcome_camera: camera_closeup.exit(actor)
			_cancel_attached_projectiles(actor, int(event.get("sequence", -1)))
			actor.action_time = 0
			actor.end_action_motion()
			presentation.cancel_actor(actor)
		"hit":
			presentation.attack_emitted(actor, event, _hit_origin(actor, event))
			var definition: Dictionary = event.get("definition", {})
			var raw = _raw_definition(definition)
			if raw.get("EntityType", "EET_Physical" if definition.get("projectile", false) else "") == "EET_Physical": _projectile(actor, event)
			else: _hit_area(actor, event)
		"summon": _create_summon(actor, event)
		"pickup_spawn": pass # The paired summon event owns this pickup's persistent state.
		"spawn_monster": _spawn_monsters(actor, event)
		"delete_unit":
			actor.apply_delete_event(event.get("definition", {}))
		"message":
			var definition: Dictionary = event.get("definition", event)
			var message = str(definition.get("MessageName", definition.get("MsgName", event.get("name", ""))))
			for recipient in actors:
				if is_instance_valid(recipient) and not recipient.dead: recipient.combat.notify_gameplay("message", {"name": message, "argument": definition.get("MsgArg1", definition.get("Arg1", ""))})
			world_message.emit(message, definition)
		"buff_effect":
			presentation.buff_effect(actor, event)
		"area":
			var center = actor.position + actor.facing * float(event.get("forward_offset", 0))
			event["impact_origin"] = DungeonProjectile._array(center)
			for target in actors:
				if not is_instance_valid(target) or target.dead: continue
				_bind_impact(target)
				target.combat.apply_area(event, actor.is_player == target.is_player, target.position.distance_squared_to(center), actor == target)
				if target.combat.health <= 0: _die(target)
		"command":
			var command: Dictionary = event.get("command", event)
			if int(event.get("sequence", -1)) != actor.combat._cast_sequence: return
			presentation.command(actor, event)
			if str(command.get("type", "")) == "EET_CameraShake" and actor.is_player:
				var raw_shake = _raw_definition(command)
				raw_shake["FeedbackType"] = "EHT_CameraShake"
				for shake in HitFeedback.normalize({"FeedbackList": [raw_shake]}).camera_shakes:
					shake["age"] = 0.0
					if not shake.is_delay: shake.delay = 0.0
					if _camera_impulses.size() >= 8: _camera_impulses.pop_front()
					_camera_impulses.append(shake)
			if str(command.get("type", "")) == "EET_PlayAnim":
				actor.action_speed = float(event.get("speed", 1))
				actor.play_animation(str(command.get("anim", "")), true)
			if str(command.get("type", "")) in ["EET_Move", "EET_MoveToPoint", "EET_Navigation", "EET_FindTarget", "EET_TargetDisCompensation"] and int(event.get("slot", 0)) != 1:
				var raw = _raw_definition(command)
				if command.type == "EET_FindTarget":
					actor.action_target_resolver = _find_motion_target.bind(actor)
					actor.action_target = _find_motion_target(raw, actor)
					preload("res://scripts/action_motion.gd").aim(actor, raw, 0)
				actor.add_action_motion(command, raw)
		"diagnostic":
			_diagnostic(str(event.get("message", "")))

func _hit_area(source: DungeonActor, hit: Dictionary, area := false) -> void:
	var definition: Dictionary = hit.get("definition", hit.get("area", {}))
	var raw = _raw_definition(definition)
	var entity: Dictionary = raw.get("EntityProperty", {})
	var width = maxf(0, float(definition.get("width", 1)))
	var length_value = maxf(0, float(definition.get("length", 1)))
	var center = _hit_origin(source, hit) + source.facing * (float(hit.get("forward_offset", 0)) + float(definition.get("offset", 0)))
	var hit_facing = source.facing
	if not source.is_player:
		var emit: Dictionary = raw.get("EmitProperty", {})
		var yaw = deg_to_rad(float(emit.get("EmitRotation", {}).get("y", 0)))
		var offset = vector(emit.get("EmitOffset", {})) + Basis(Vector3.UP, yaw) * (vector(emit.get("AfterRotateEmitOffset", {})) + Vector3(0, 0, float(hit.get("forward_offset", 0)) + float(definition.get("offset", 0))))
		center = _hit_origin(source, hit) + DungeonProjectile.orient(offset, source.facing)
		hit_facing = source.facing.rotated(Vector3.UP, yaw)
	hit["impact_origin"] = DungeonProjectile._array(center)
	hit["impact_radius"] = maxf(width, length_value) * 0.5
	for target in actors:
		if not is_instance_valid(target) or target.dead or target.is_player == source.is_player: continue
		var difference = target.position - center
		difference.y = 0
		var intersects = difference.length() <= maxf(width, length_value) * 0.5 + 0.35 if definition.get("shape", "Cube") == "Sphere" else absf(difference.dot(hit_facing)) <= length_value * 0.5 + 0.35 and absf(difference.dot(Vector3.UP.cross(hit_facing))) <= width * 0.5 + 0.35
		if raw.get("EntityType", "") == "EET_FrameFan":
			var degrees = float(entity.get("Degree", 360))
			intersects = difference.length() <= float(entity.get("Radius", maxf(width, length_value) * 0.5)) + 0.35 and (degrees >= 359 or difference.length() < 0.4 or absf(rad_to_deg(hit_facing.signed_angle_to(difference.normalized(), Vector3.UP))) <= degrees * 0.5)
		if intersects:
			_apply_hit(source, target, hit)
	if interactions:
		var tenacities := _environment_tenacities(hit)
		var hit_id := _environment_hit_id(source, hit)
		var size := Vector3(width, maxf(1.0, vector(entity.get("ModelBoxColliderSize", {})).y), length_value)
		_damage_environment_shape(center, center, hit_facing, size, str(definition.get("shape", "Cube")), tenacities, source, hit_id)

func _damage_environment_shape(from: Vector3, to: Vector3, direction: Vector3, size: Vector3, shape_type: String, tenacities: Array[int], source: DungeonActor, hit_id: String) -> void:
	if tenacities.is_empty(): return
	var shape: Shape3D
	if shape_type == "Sphere":
		shape = SphereShape3D.new()
		shape.radius = maxf(0.01, maxf(size.x, size.z) * 0.5)
	else:
		shape = BoxShape3D.new()
		shape.size = size.abs().max(Vector3.ONE * 0.01)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1
	var basis := Basis(Vector3.UP, atan2(direction.x, direction.z))
	var steps := maxi(1, ceili(from.distance_to(to) / maxf(0.1, minf(size.x, size.z) * 0.5)))
	for step in range(steps + 1):
		query.transform = Transform3D(basis, from.lerp(to, float(step) / steps))
		for contact in get_world_3d().direct_space_state.intersect_shape(query, 128):
			for index in tenacities.size():
				interactions.damage_collider(contact.collider, tenacities[index], 2 if source.is_player else 1, hit_id + ":" + str(index))

func _environment_tenacities(hit: Dictionary) -> Array[int]:
	var amount := 0
	var result: Array[int] = []
	for feedback in HitFeedback.normalize(hit.get("definition", hit)).hit_actions:
		amount += int(feedback.acc_tenacity)
		result.append(maxi(0, amount))
	return result

func _environment_hit_id(source: DungeonActor, hit: Dictionary) -> String:
	if not hit.has("emission"):
		_impact_serial += 1
		hit["emission"] = "environment-hit:%d" % _impact_serial
	return str(source.combat.actor_key) + ":" + ImpactProfiles.instance_id(hit)

func _apply_hit(source: DungeonActor, target: DungeonActor, hit: Dictionary) -> void:
	if target.dead or target.invulnerability > 0: return
	_bind_impact(target)
	hit["source"] = source.combat
	if not hit.has("emission"):
		_impact_serial += 1
		hit["emission"] = "world:%s" % _impact_serial
	if not hit.has("impact_position"): hit["impact_position"] = DungeonProjectile._array(target.position + Vector3.UP * 0.65)
	hit["distance"] = source.position.distance_to(target.position)
	target.combat.receive(hit, source.combat.effective_attack_power())
	if bool(hit.get("resolved_accepted", false)): source.combat.confirm_hit(hit)
	if target.combat.health <= 0: _die(target)

func _bind_impact(actor: DungeonActor) -> void:
	var callback = _on_impact.bind(actor)
	if not actor.combat.impact_confirmed.is_connected(callback): actor.combat.impact_confirmed.connect(callback)

func _on_impact(hit: Dictionary, target: DungeonActor) -> void:
	if not is_instance_valid(target) or target.dead: return
	var source = _actor_by_key(str(hit.get("source_key", "")))
	var instance = ImpactProfiles.instance_id(hit)
	var key = instance + ":" + str(hit.get("contact", 0)) + ":" + str(target.combat.actor_key)
	if _seen_impacts.has(key): return
	_seen_impacts[key] = _impact_clock
	var point = vector(hit.get("impact_position", DungeonProjectile._array(target.position + Vector3.UP * 0.65)))
	var profile = ImpactProfiles.resolve(hit, source.combat if source else null)
	hit["impact_position"] = DungeonProjectile._array(point)
	hit["profile"] = profile
	hit["attack_instance"] = instance
	var damage = float(hit.get("resolved_damage", 0))
	if FEEL.impact_enabled:
		var visual_source = source if source else target
		presentation.impact(visual_source, target, hit)
		target.hit_flash(float(profile.flash))
		target.combat.apply_hit_stop(float(profile.stop))
		if source and not profile.ranged and int(hit.get("sequence", -1)) == source.combat._cast_sequence:
			source.combat.apply_hit_stop(float(profile.stop), true)
		if damage > 0 and (profile.category != "continuous" or float(profile.distance) > 0): _apply_feedback(source, target, hit)
		if profile.category == "explosion":
			_blast(visual_source, hit, profile, vector(hit.get("impact_origin", hit.impact_position)))
		else:
			_queue_impact_shake(profile, point)
	if damage > 0:
		_damage_number(target.position + Vector3.UP * 1.8, damage, target.is_player)
		if target.is_player: received_hits += 1
	impact_confirmed.emit(hit)

func _queue_impact_shake(profile: Dictionary, point: Vector3) -> void:
	if not camera_shake_enabled or float(profile.get("amplitude", 0)) <= 0 or not is_instance_valid(player): return
	var attenuation = clampf(1.0 - player.position.distance_to(point) / 24.0, 0, 1)
	if camera.is_position_behind(point): attenuation *= 0.15
	else:
		var rect = get_viewport().get_visible_rect()
		if not rect.has_point(camera.unproject_position(point)): attenuation *= 0.25
	if _camera_impulses.size() >= 8: _camera_impulses.pop_front()
	_camera_impulses.append({"age": 0.0, "delay": 0.0, "duration": float(profile.shake), "amplitude": float(profile.amplitude) * attenuation, "times": 3})

func _blast(source: DungeonActor, hit: Dictionary, profile: Dictionary, point: Vector3) -> void:
	var key = ImpactProfiles.instance_id(hit)
	if _seen_blasts.has(key): return
	_seen_blasts[key] = _impact_clock
	_queue_impact_shake(profile, point)
	presentation.explosion(source, point, profile)

func _projectile(source: DungeonActor, hit: Dictionary) -> void:
	var state = _projectile_state_pool.pop_back() if not _projectile_state_pool.is_empty() else DungeonProjectile.new()
	var target = _nearest_opponent(source)
	var origin = _hit_origin(source, hit)
	var target_point = target.position if target else origin + source.facing * 8
	var raw := _raw_definition(hit.get("definition", {}))
	var direction = DungeonProjectile.emission_facing(raw, int(hit.get("emit_index", 0)), source.facing, target_point - origin)
	var dummy := str(raw.get("EmitProperty", {}).get("DummyData", {}).get("DummyType", ""))
	hit["owner_height"] = 0.0 if dummy == "Unit_FootBottom" else 0.75
	state.configure(hit, origin + Vector3.UP * float(hit.owner_height) + source.facing * float(hit.get("forward_offset", 0)), direction, target_point, source.facing)
	state.source_key = str(source.combat.actor_key)
	state.source_player = source.is_player
	state.target_key = str(target.combat.actor_key) if target else ""
	for message in state.diagnostics: _diagnostic(message)
	_add_projectile_visual(state, source)

func _add_projectile_visual(state: DungeonProjectile, source: DungeonActor) -> void:
	var mesh: MeshInstance3D = _projectile_visual_pool.pop_back() if not _projectile_visual_pool.is_empty() else _make_projectile_visual()
	mesh.transform = Transform3D.IDENTITY
	mesh.material_override = _projectile_materials[0 if source.is_player else 1]
	mesh.position = state.position
	mesh.visible = not (_attached_projectile(state) and str(state.entity.get("ModlePrefab", "")).is_empty())
	presentation.projectile_started(source, state, mesh)
	projectiles.append({"source": source, "state": state, "visual": mesh})
	_warn_budget("projectiles", projectiles.size(), FEEL.projectile_warning_budget)

func _make_projectile_visual() -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = _projectile_mesh
	mesh.hide()
	mesh.process_mode = Node.PROCESS_MODE_DISABLED
	add_child(mesh)
	return mesh

func _recycle_projectile(projectile: Dictionary) -> void:
	var mesh: MeshInstance3D = projectile.visual
	if is_instance_valid(mesh):
		presentation.release_anchor(mesh)
		mesh.hide()
		if _projectile_visual_pool.size() < FEEL.projectile_pool_capacity: _projectile_visual_pool.append(mesh)
		else: mesh.queue_free()
	var state: DungeonProjectile = projectile.state
	state.reset()
	if _projectile_state_pool.size() < FEEL.projectile_pool_capacity: _projectile_state_pool.append(state)

func _warn_budget(kind: String, count: int, budget: int) -> void:
	if count <= budget or _budget_warnings.has(kind): return
	_budget_warnings[kind] = count
	_diagnostic("%s budget exceeded (%d > %d); gameplay preserved" % [kind, count, budget])

func _tick_projectiles(delta: float) -> void:
	for projectile in projectiles.duplicate():
		var state: DungeonProjectile = projectile.state
		var visual: MeshInstance3D = projectile.visual
		if not is_instance_valid(projectile.source):
			_recycle_projectile(projectile)
			projectiles.erase(projectile)
			continue
		var source: DungeonActor = projectile.source
		var attached = _attached_projectile(state)
		if attached and (source.dead or source.combat.busy <= 0 or int(state.hit.get("sequence", -1)) != source.combat._cast_sequence):
			presentation.projectile_ended(source, state)
			_recycle_projectile(projectile)
			projectiles.erase(projectile)
			continue
		var tracked: DungeonActor
		if state.motion_type == "EMAT_Line" and bool(state.motion.get("TraceTarget", false)):
			tracked = _actor_by_key(state.target_key)
			if not tracked or tracked.dead:
				tracked = _nearest_opponent(source, state.position)
				state.target_key = str(tracked.combat.actor_key) if tracked else ""
		var step = maxf(0, source.combat.action_step) if attached and source.combat.action_step >= 0 else delta
		if attached and step <= 0: continue
		var was_finished := state.finished
		state.advance(step, source.position + Vector3.UP * float(state.hit.get("owner_height", 0.75)), source.facing, tracked.position + Vector3.UP * 0.75 if tracked else Vector3.INF)
		# Expiry still owns its final swept segment. Hit/pass and wall termination
		# remain authoritative while that last segment is checked.
		var expires_now := state.finished and not was_finished
		if expires_now: state.finished = false
		var props_enabled := interactions != null and bool(state.entity.get("IsCheckEnvUnitCollider", true)) and state.age >= float(state.entity.get("EnableGlobalCollisionDelayTime", 0))
		var tenacities: Array = _environment_tenacities(state.hit) if props_enabled else []
		var prop_hit_id := _environment_hit_id(source, state.hit) if props_enabled else ""
		if bool(state.entity.get("IsCheckEnvCollider", true)) and state.previous.distance_squared_to(state.position) > 0.00001:
			var query = PhysicsRayQueryParameters3D.create(state.previous, state.position, 1)
			var wall = get_world_3d().direct_space_state.intersect_ray(query)
			if not wall.is_empty():
				if props_enabled:
					for index in tenacities.size():
						interactions.damage_collider(wall.collider, tenacities[index], 2 if source.is_player else 1, prop_hit_id + ":" + str(index))
				state.wall_collision(wall.position, wall.normal)
		if props_enabled:
			var prop_offset := DungeonProjectile.orient(vector(state.entity.get("ModelBoxColliderCenterOffset", {})), state.direction)
			var prop_size := vector(state.entity.get("ModelBoxColliderSize", {}))
			if prop_size.length_squared() < 0.001: prop_size = Vector3.ONE * state.radius * 2.0
			_damage_environment_shape(state.previous + prop_offset, state.position + prop_offset, state.direction, prop_size, str(state.entity.get("ColliderType", "Cube")), tenacities, source, prop_hit_id)
		visual.position = state.position
		var targets: Array = actors if source.is_player else [player]
		for target in targets:
			if not is_instance_valid(target) or target.dead or target.is_player == source.is_player: continue
			if not target.combat.can_receive_attack(): continue
			var key = str(target.combat.actor_key)
			if state.can_hit(key) and state.intersects(target.position + Vector3.UP * 0.75):
				var contact_hit = state.hit.duplicate(true)
				var contact = Geometry3D.get_closest_point_to_segment(target.position + Vector3.UP * 0.65, state.previous, state.position)
				contact_hit["impact_position"] = DungeonProjectile._array(contact)
				contact_hit["impact_origin"] = DungeonProjectile._array(state.position)
				contact_hit["impact_radius"] = state.radius
				contact_hit["contact"] = int(state.hits.get(key, 0))
				contact_hit["ranged"] = state.motion_type not in ["EMAT_FollowOwner", "EMAT_RotateOwner"]
				_apply_hit(source, target, contact_hit)
				state.record_hit(key)
				if state.finished: break
		state.finished = state.finished or expires_now
		if state.finished:
			var end_profile = ImpactProfiles.resolve(state.hit, source.combat)
			if end_profile.category == "explosion" and FEEL.impact_enabled: _blast(source, state.hit, end_profile, state.position)
			presentation.projectile_ended(source, state)
			_apply_raw_buff(source.combat, state.entity.get("AddBuffOwnerWhenDispose", {}), source.combat)
			_spawn_from_definition(source, state.entity.get("AddSummonUnitDef", {}), state.position)
			_recycle_projectile(projectile)
			projectiles.erase(projectile)

func _attached_projectile(state: DungeonProjectile) -> bool:
	return state.motion_type in ["EMAT_FollowOwner", "EMAT_RotateOwner"] and str(state.hit.get("summon_id", "")).is_empty()

func _cancel_attached_projectiles(source: DungeonActor, sequence: int, keep := false) -> void:
	for projectile in projectiles.duplicate():
		var state: DungeonProjectile = projectile.state
		if projectile.source != source or not _attached_projectile(state): continue
		var matches = int(state.hit.get("sequence", -1)) == sequence
		if matches == keep: continue
		presentation.projectile_ended(source, state)
		_recycle_projectile(projectile)
		projectiles.erase(projectile)

func _apply_feedback(source: DungeonActor, target: DungeonActor, hit: Dictionary) -> void:
	var profile: Dictionary = hit.get("profile", ImpactProfiles.resolve(hit, source.combat if source else null))
	var factor = ImpactProfiles.reaction_scale(target.combat)
	var origin = vector(hit.get("impact_origin", DungeonProjectile._array(source.position if source else target.position)))
	var direction = target.position - origin if profile.category == "explosion" or not source else target.position - source.position
	if profile.category == "explosion":
		var flat = target.position - origin
		flat.y = 0
		factor *= clampf(1.0 - flat.length() / maxf(0.5, float(hit.get("impact_radius", 3))), 0.0, 1.0)
	if target.is_player: factor *= 0.35
	for feedback in _raw_definition(hit.get("definition", {})).get("FeedbackList", []):
		if feedback.get("FeedbackType", "") != "EHT_HitAction": continue
		if profile.category == "explosion": break
		if source and feedback.get("AttackDirIsAttackerForwardOrHitPointDir", false): direction = source.facing
		if str(feedback.get("PushMode", "")) in ["AttackeeToAttackerDir", "ToAttacker"]: direction = -direction
		var power = float(feedback.get("PushPower", 0))
		var modifier = str(feedback.get("PushPowerModifyPropertyName", ""))
		if source and not modifier.is_empty():
			var value = source.combat.property_value(modifier)
			if value != null: power += float(value)
		if power < 0: direction = -direction
		if factor > 0: target.velocity.y += minf(3.0, float(feedback.get("UpperPower", 0)) * 0.01) * factor
	target.start_knockback(direction, float(profile.distance) * factor, float(profile.travel))
	if factor > 0:
		var interrupt = not target.is_player or profile.category in ["heavy", "explosion"]
		if target.combat.apply_stagger(float(profile.stagger) * factor, interrupt) and not target.is_player: target.play_animation("hit", true)

func _diagnostic(message: String) -> void:
	if not diagnostics.has(message): diagnostics.append(message)

static func _raw_definition(definition: Dictionary) -> Dictionary:
	var raw = JSON.parse_string(str(definition.get("raw", "{}")))
	return raw if raw is Dictionary else {}

func _actor_by_key(key: String) -> DungeonActor:
	if key.is_empty(): return null
	if key == "player": return player if is_instance_valid(player) else null
	var cached = _actor_index.get(key)
	if is_instance_valid(cached) and str(cached.combat.actor_key) == key: return cached
	_actor_index.erase(key)
	for actor in actors:
		if is_instance_valid(actor) and str(actor.combat.actor_key) == key:
			_actor_index[key] = actor
			return actor
	return null

func _nearest_opponent(source: DungeonActor, from: Vector3 = Vector3.INF) -> DungeonActor:
	if not source.is_player: return player if is_instance_valid(player) and not player.dead else null
	var found: DungeonActor
	var distance = INF
	var point = from if from.is_finite() else source.position
	for actor in actors:
		if not is_instance_valid(actor) or actor.dead or actor.is_player == source.is_player: continue
		var value = actor.position.distance_squared_to(point)
		if value < distance:
			distance = value
			found = actor
	return found

func _find_motion_target(raw: Dictionary, source: DungeonActor) -> DungeonActor:
	var found: DungeonActor
	var radius = float(raw.get("SearchRadius", 0))
	var distance = pow(radius if radius > 0 else 7.0, 2) if source.is_player else (radius * radius if radius > 0 else INF)
	for actor in actors:
		if not is_instance_valid(actor) or actor.dead or actor.is_player == source.is_player: continue
		var value = actor.position.distance_squared_to(source.position)
		if value >= distance: continue
		var query = PhysicsRayQueryParameters3D.create(source.position + Vector3.UP * 0.8, actor.position + Vector3.UP * 0.8, 1)
		if not get_world_3d().direct_space_state.intersect_ray(query).is_empty(): continue
		distance = value
		found = actor
	return found

func _monster_field_center(id: String, fallback: Vector3) -> Vector3:
	if _monster_field_data.is_empty():
		_monster_field_data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/monster_field_centers.json"))
	var environment = str(environment_entry.get("scene_name", "")).trim_prefix("LevelMap_")
	var field: Dictionary = _monster_field_data.get("environments", {}).get(environment, {}).get(id, {})
	if field.has("position"): return vector(field.position)
	for marker in environment_entry.get("events", []):
		if str(marker.get("id", "")) == id: return vector(marker.get("position", fallback))
	for marker in environment_entry.get("spawns", []):
		if str(marker.get("id", "")) == id: return vector(marker.get("position", fallback))
	return fallback

func _spawn_monsters(source: DungeonActor, event: Dictionary) -> void:
	var definition: Dictionary = event.get("definition", event)
	var enemy_id = int(event.get("enemy_id", definition.get("MonsterId", 0)))
	if enemy_id <= 0:
		_diagnostic("Monster generation has no enemy ID")
		return
	var points: Array = event.get("spawn_points", definition.get("SpawnPoints", []))
	var total = int(definition.get("GenerationTotalCount", 0))
	for property in str(definition.get("GenerationTotalCountModifyAddValue", "")).split("|", false):
		var value: Variant = source.combat.property_value(property)
		if value is int or value is float: total += int(value)
	if total <= 0 or points.is_empty(): return
	var mode = int(definition.get("GenerationMode", 0))
	if mode not in [0, 1]: return
	for index in total:
		var point: Variant = points[mini(points.size() - 1, int(source.combat._random() * points.size())) if mode == 0 else index % points.size()]
		var position := Vector3.ZERO
		var rotation: Variant = {}
		var found = point is Dictionary or point is Array
		if found: position = vector(point)
		else:
			for marker in room_spawn_points + environment_entry.get("spawns", []):
				if int(marker.get("Id", marker.get("id", -1))) == int(point):
					position = vector(marker.get("Position", marker.get("position", {})))
					rotation = marker.get("Rotation", marker.get("rotation", {}))
					found = true
					break
		if not found:
			_diagnostic("Monster generation skipped missing point " + str(point))
			continue
		monster_spawn_queue.append({"spawn": {"enemy_id": enemy_id, "position": DungeonProjectile._array(position), "rotation": rotation, "enemy_stage": int(source.combat.custom_properties.get("enemy_stage", enemy_stage_layer)), "enemy_chaos": int(source.combat.custom_properties.get("enemy_chaos", 0))}, "difficulty": source.combat.difficulty, "seed": int(source.combat._random_state) + index})

func _tick_monster_spawns() -> void:
	if monster_spawn_queue.is_empty(): return
	var request: Dictionary = monster_spawn_queue.pop_front()
	spawn_wave([request.spawn], int(request.difficulty), int(request.seed))

func _hit_origin(source: DungeonActor, hit: Dictionary) -> Vector3:
	var summon_id = str(hit.get("summon_id", ""))
	if not summon_id.is_empty():
		var token = str(hit.get("origin", {}).get("_summon_token", ""))
		for index in range(summon_units.size() - 1, -1, -1):
			var unit = summon_units[index]
			if unit.id == summon_id and unit.owner == str(source.combat.actor_key) and (token.is_empty() or unit.get("token", "") == token): return unit.position
	var emit: Dictionary = _raw_definition(hit.get("definition", {})).get("EmitProperty", {})
	if str(emit.get("PosType", "")) in ["EEPT_TargetPos", "EEPT_TargetPos_Ground"]:
		var target = _actor_by_key(str(hit.get("target_key", "")))
		if not is_instance_valid(target) or target.dead: target = _nearest_opponent(source)
		if is_instance_valid(target): return target.position
	return _resolve_origin(source, hit)

func _resolve_origin(source: DungeonActor, event: Dictionary) -> Vector3:
	var value = event.get("origin", {})
	if value is Vector3 or value is Array: return vector(value)
	if value is Dictionary:
		if value.has("x") or value.has("X"): return vector(value)
		if value.has("world_position"): return vector(value.world_position)
		var target = _actor_by_key(str(event.get("target_key", "")))
		if target and str(value.get("OriginType", "")) == "targetPosAndSelfDir": return target.position
	return source.position

func _create_summon(source: DungeonActor, event: Dictionary) -> void:
	var definition: Dictionary = event.get("definition", {})
	var raw: Dictionary = definition.get("raw_data", {})
	var origin = _resolve_origin(source, event)
	var origin_def: Dictionary = event.get("origin", {}) if event.get("origin", {}) is Dictionary else {}
	var offset = vector(raw.get("InitPosOffset", {})) + vector(origin_def.get("InitPosOffset", {}))
	if origin_def.is_empty() or (origin_def.size() == 1 and origin_def.has("_summon_token")): offset += Vector3(0, 0, float(event.get("forward_offset", 0)))
	_summon_serial += 1
	var unit = {"serial": _summon_serial, "id": str(event.id), "owner": str(source.combat.actor_key), "position": origin + DungeonProjectile.orient(offset, source.facing), "offset": offset, "age": 0.0, "life": maxf(0.05, float(event.get("lifetime", 1))), "next": 0.0, "raw": raw, "type": str(definition.get("type", "")), "triggered": false, "children": {}, "action": event.get("action", source.combat.current_action), "slot": event.get("slot", source.combat._current_slot), "sequence": event.get("sequence", source.combat._cast_sequence)}
	unit["token"] = str(origin_def.get("_summon_token", ""))
	var limit = int(raw.get("MaxExistCount", -1))
	var existing: Array = []
	for previous_unit in summon_units:
		if previous_unit.id == unit.id and previous_unit.owner == unit.owner: existing.append(previous_unit)
	while limit > 0 and existing.size() >= limit: _dispose_summon(existing.pop_front(), false)
	if unit.type == "ESUT_PickupableItem":
		var mesh = Sprite3D.new()
		mesh.texture = DungeonStyle.texture("material:" + str(unit.id))
		mesh.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		mesh.pixel_size = 0.007
		add_child(mesh)
		mesh.position = unit.position + Vector3.UP * 0.3
		unit["visual"] = mesh
	else:
		unit["effect_token"] = presentation.summon_started(source, raw, unit.position, source.facing)
	summon_units.append(unit)

func _tick_summons(delta: float) -> void:
	for unit in summon_units.duplicate():
		var owner = _actor_by_key(unit.owner)
		if not owner:
			_dispose_summon(unit, false)
			continue
		unit.age += delta
		var raw: Dictionary = unit.raw
		match str(raw.get("FunnelPosType", "FixedPoint")):
			"FollowOwner":
				var destination = owner.position + DungeonProjectile.orient(unit.offset, owner.facing)
				if str(raw.get("FollowPosType", "")) == "MoveToOwner":
					var distance = (unit.position as Vector3).distance_to(destination)
					var minimum = maxf(0, float(raw.get("MoveToOwnerMinDistance", 1.5)))
					if distance > minimum:
						var speed = maxf(0, float(raw.get("MoveToOwnerSpeed", 1.5)) + float(raw.get("MoveToOwnerAcceleration", 0.1)) * float(unit.age))
						unit.position = (unit.position as Vector3).move_toward(destination, minf(speed * delta, distance - minimum))
				else: unit.position = destination
			"MoveToNearestEnemyTarget":
				var target = _nearest_opponent(owner, unit.position)
				if target: unit.position = unit.position.move_toward(target.position, float(raw.get("MoveToNearestTargetMaxSpeed", 8)) * delta)
		presentation.summon_updated(int(unit.get("effect_token", 0)), unit.position, owner.facing)
		if unit.type == "ESUT_PickupableItem" and player and not player.dead and player.position.distance_to(unit.position) <= float(raw.get("PickUpRange", 2)):
			_apply_raw_buff(player.combat, raw.get("BuffTrigger_Picker", {}), owner.combat)
			player.combat.notify_gameplay("pickup", {"id": unit.id})
			_dispose_summon(unit, false)
			continue
		if unit.type == "ESUT_StaticRangeTrigger" and float(unit.age) >= float(unit.next):
			unit.next = float(unit.age) + maxf(0.05, float(raw.get("TriggerDuration", 1)))
			_summon_area(unit, owner, "Start" if not unit.triggered else "Loop")
			unit.triggered = true
		if unit.type == "ESUT_Funnel" and int(raw.get("DamageDefId", 0)) <= 0 and raw.get("EntityType", "") == "EET_FrameFan" and float(unit.age) >= float(unit.next):
			var interval = maxf(0.05, float(raw.get("EmitProperty", {}).get("Interval", 0.1)))
			unit.next = float(unit.next) + interval
			_monster_field_feedback(unit, raw, interval)
		for index in raw.get("AddSummonUnitList", []).size():
			var child: Dictionary = raw.AddSummonUnitList[index]
			if not unit.children.has(str(index)) and float(unit.age) >= float(child.get("DelayTime", 0)) / 1000:
				unit.children[str(index)] = true
				_spawn_from_definition(owner, child.get("AddData", {}), unit.position)
		if float(unit.age) >= float(unit.life): _dispose_summon(unit, true)

func _monster_field_feedback(unit: Dictionary, raw: Dictionary, interval: float) -> void:
	var power := 0.0
	for feedback in raw.get("FeedbackList", []):
		if feedback.get("FeedbackType", "") == "EHT_HitAction": power += float(feedback.get("PushPower", 0))
	if is_zero_approx(power): return
	var owner = _actor_by_key(unit.owner)
	if not owner or owner.is_player: return
	var entity: Dictionary = raw.get("EntityProperty", {})
	var radius = maxf(0, float(entity.get("Radius", 0)))
	for target in actors:
		if not is_instance_valid(target) or target.dead or target.is_player == owner.is_player or target.invulnerability > 0 or target.combat.invincible > 0 or target.combat._dodge_time > 0 or target.combat._block_time > 0 or not target.combat.can_receive_attack(): continue
		var toward: Vector3 = target.position - unit.position
		if absf(toward.y) > maxf(0.1, float(entity.get("Height", 2))): continue
		toward.y = 0
		if toward.length_squared() < 0.00001 or toward.length() > radius: continue
		var degrees = float(entity.get("Degree", 360))
		if degrees < 359 and toward.length() > 0.01 and absf(rad_to_deg(owner.facing.signed_angle_to(toward.normalized(), Vector3.UP))) > degrees * 0.5: continue
		_apply_feedback(null, target, {"definition": {"raw": JSON.stringify(raw)}, "impact_origin": DungeonProjectile._array(unit.position), "profile": {"category": "continuous", "distance": absf(power) * FEEL.monster_field_pull_per_power, "travel": interval, "stagger": 0.0}})

func _summon_area(unit: Dictionary, owner: DungeonActor, phase: String) -> void:
	var raw: Dictionary = unit.raw
	if phase in ["Start", "End"] and not raw.get("Trigger" + phase, false): return
	var radius = float(raw.get("EffectRadius", 1))
	for target in actors:
		if not is_instance_valid(target) or target.dead or (target == owner and not raw.get("EffectToSelf", false)): continue
		if (target.is_player == owner.is_player) != bool(raw.get("TargetCampIsSelf", false)): continue
		if target.position.distance_squared_to(unit.position) > radius * radius: continue
		_apply_raw_buff(target.combat, raw.get("AddBuffData_" + phase, {}), owner.combat)
		if raw.get("EnableCauseDamage", false):
			var definition: Dictionary = owner.combat._damage_data(int(raw.get("DamageDefId", 0)))
			if not definition.is_empty(): _apply_hit(owner, target, {"source": owner.combat, "definition": {"damageId": int(raw.get("DamageDefId", 0)), "element": str(definition.get("DamageType", "Physical")), "attribute": str(definition.get("DamageAttribType", "FinalAtk"))}, "damage": owner.combat._damage_value(definition, owner.combat.effective_attack_power()), "summon_id": unit.id, "action": unit.get("action", ""), "slot": unit.get("slot", 0), "sequence": unit.get("sequence", 0), "emission": "summon:%s:%s" % [unit.serial, unit.age], "ranged": true, "continuous": phase == "Loop", "impact_origin": DungeonProjectile._array(unit.position), "impact_radius": radius})

func _spawn_from_definition(owner: DungeonActor, definition: Dictionary, point: Vector3) -> void:
	var id = str(definition.get("AddSummonUnitId", ""))
	if id.is_empty() or id == "0": return
	for index in range(clampi(int(definition.get("AddSummonUnitQuantity", 1)), 1, 30)):
		var origin = definition.duplicate(true)
		origin["world_position"] = DungeonProjectile._array(point)
		owner.combat.spawn_summon(id, origin)

func _dispose_summon(unit: Dictionary, trigger_end: bool) -> void:
	var owner = _actor_by_key(unit.owner)
	if owner and trigger_end:
		if unit.type == "ESUT_StaticRangeTrigger": _summon_area(unit, owner, "End")
		_apply_raw_buff(owner.combat, unit.raw.get("AddBuffOwnerWhenDispose", {}), owner.combat)
		_spawn_from_definition(owner, unit.raw.get("DeadCreateSummonUnit", {}), unit.position)
	if is_instance_valid(unit.get("visual")): unit.visual.queue_free()
	presentation.summon_ended(int(unit.get("effect_token", 0)))
	summon_units.erase(unit)

func _apply_raw_buff(target: RefCounted, definition: Dictionary, caster: RefCounted) -> void:
	var id = str(definition.get("BuffTriggerId", ""))
	if not id.is_empty():
		target.bind_buff_caster(id, caster)
		target.add_buff(id, int(definition.get("BuffAddLayer", 1)), caster.effective_attack_power())

func transient_snapshot() -> Dictionary:
	var bullets: Array = []
	for projectile in projectiles: bullets.append(projectile.state.snapshot())
	var units: Array = []
	for unit in summon_units:
		var saved = unit.duplicate(true)
		saved.erase("visual")
		saved.erase("effect_token")
		saved.position = DungeonProjectile._array(unit.position)
		saved.offset = DungeonProjectile._array(unit.offset)
		units.append(saved)
	var motion_states: Dictionary = {}
	for actor in actors:
		if not is_instance_valid(actor) or actor.dead: continue
		motion_states[str(actor.combat.actor_key)] = {"sequence": actor.combat._cast_sequence, "duration": actor.action_timeline_duration, "cursor": actor.action_cursor, "speed": actor.action_speed, "events": actor.action_motion.duplicate(true), "target": str(actor.action_target.combat.actor_key) if is_instance_valid(actor.action_target) else "", "facing": DungeonProjectile._array(actor.facing), "animation": str(actor.animation.current_animation) if actor.animation else "", "animation_position": actor.animation.current_animation_position if actor.animation else 0.0}
		motion_states[str(actor.combat.actor_key)].merge({"born_position": DungeonProjectile._array(actor.born_position), "born_facing": DungeonProjectile._array(actor.born_facing), "field_center": DungeonProjectile._array(actor.field_center), "animation_state_speed": actor.animation_state_speed})
	return {"projectiles": bullets, "summons": units, "actor_serial": _actor_serial, "summon_serial": _summon_serial, "ground_loot": ground_loot.snapshot(), "action_motion": motion_states, "monster_spawn_queue": monster_spawn_queue.duplicate(true), "wave_spawns": wave_spawn_queue.duplicate(true), "wave_spawn_wait": _wave_spawn_wait, "wave_gate": _wave_gate_remaining, "wave_clear_wait": _wave_clear_remaining, "wave_final": _wave_final, "room_flow": {"stage": room_stage, "fight_type": room_fight_type, "remaining": _room_stage_wait, "entry_wave": _entry_wave.duplicate(true)}}

func restore_transients(snapshot: Dictionary) -> void:
	var room_flow: Dictionary = snapshot.get("room_flow", {})
	if not room_flow.is_empty():
		room_stage = str(room_flow.get("stage", "unmanaged"))
		room_fight_type = str(room_flow.get("fight_type", room_fight_type))
		_room_stage_wait = maxf(0.0, float(room_flow.get("remaining", 0)))
		_entry_wave = room_flow.get("entry_wave", {}).duplicate(true)
		if room_stage != "unmanaged": fighting = room_stage == "fighting"
	monster_spawn_queue.assign(snapshot.get("monster_spawn_queue", []))
	wave_spawn_queue.assign(snapshot.get("wave_spawns", []))
	_wave_spawn_wait = maxf(0.0, float(snapshot.get("wave_spawn_wait", 0)))
	_wave_gate_remaining = maxf(0.0, float(snapshot.get("wave_gate", 0)))
	_wave_clear_remaining = float(snapshot.get("wave_clear_wait", -1))
	_wave_final = bool(snapshot.get("wave_final", false))
	camera_closeup.restore()
	ground_loot.restore(snapshot.get("ground_loot", []))
	_camera_impulses.clear()
	_seen_impacts.clear()
	_seen_blasts.clear()
	for actor in actors:
		if is_instance_valid(actor):
			actor.clear_impact_state()
			actor.end_action_motion()
			var motion: Dictionary = snapshot.get("action_motion", {}).get(str(actor.combat.actor_key), {})
			if not motion.is_empty() and int(motion.get("sequence", -1)) == actor.combat._cast_sequence:
				actor.born_position = vector(motion.get("born_position", actor.born_position))
				actor.born_facing = vector(motion.get("born_facing", actor.born_facing))
				actor.field_center = vector(motion.get("field_center", actor.field_center))
				actor.animation_state_speed = float(motion.get("animation_state_speed", 1))
				actor.action_timeline_duration = maxf(0.0, float(motion.get("duration", 0)))
				actor.action_cursor = clampf(float(motion.get("cursor", 0)), 0, actor.action_timeline_duration)
				actor.action_speed = maxf(0.01, float(motion.get("speed", 1)))
				actor.action_motion.assign(motion.get("events", []))
				actor.action_target = _actor_by_key(str(motion.get("target", "")))
				actor.action_target_resolver = _find_motion_target.bind(actor)
				actor.face_direction(vector(motion.get("facing", [0, 0, -1])))
				if actor.visual: actor.visual.rotation.y = atan2(actor.facing.x, actor.facing.z)
				var clip = str(motion.get("animation", ""))
				if actor.animation and not clip.is_empty() and actor.animation.has_animation(clip):
					actor.animation.play(clip)
					actor.animation.seek(maxf(0, float(motion.get("animation_position", 0))), true)
			elif not actor.combat.current_action.is_empty():
				# Old saves have no motion cursor; cancel their attached action consistently.
				actor.combat._cancel_sequence(actor.combat._cast_sequence, true)
				actor.combat.busy = 0
	_actor_serial = maxi(_actor_serial, int(snapshot.get("actor_serial", 0)))
	if is_instance_valid(player) and not player.combat.current_action.is_empty():
		camera_closeup.enter(player, player.combat.current_action, _camera_conditions)
		camera_closeup.update_action(player, player.combat.action_elapsed * float(player.combat.custom_properties.get("_feel_action_speed", 1)) * 1000.0)
	_summon_serial = int(snapshot.get("summon_serial", 0))
	for data in snapshot.get("projectiles", []):
		var state = DungeonProjectile.new()
		state.restore(data)
		var source = _actor_by_key(state.source_key)
		if source: _add_projectile_visual(state, source)
	for data in snapshot.get("summons", []):
		var unit: Dictionary = data.duplicate(true)
		unit.position = vector(data.position)
		unit.offset = vector(data.offset)
		var source = _actor_by_key(str(unit.owner))
		if not source: continue
		_create_summon(source, {"id": unit.id, "definition": {"raw_data": unit.raw, "type": unit.type}, "lifetime": unit.life, "origin": unit.position - DungeonProjectile.orient(unit.offset, source.facing)})
		var restored = summon_units.back()
		for field in unit:
			if field != "effect_token": restored[field] = unit[field]

func _environment_trap(context: Dictionary) -> void:
	_impact_serial += 1
	var emission = "environment:%s" % _impact_serial
	for actor in actors:
		if not is_instance_valid(actor) or actor.dead: continue
		var target_id = str(context.get("target_id", ""))
		if not target_id.is_empty():
			if target_id != ("player" if actor.is_player else str(actor.combat.actor_key)): continue
		else:
			if not DungeonWorldInteractions.camp_allows(str(context.get("camp_mask", "")), 2 if actor.is_player else 1): continue
			if actor.position.distance_to(vector(context.get("position", {}))) > float(context.get("radius", 0)): continue
		_bind_impact(actor)
		var previous = actor.combat.health
		actor.combat.add_buff(str(context.get("buff_id", "")), int(context.get("layers", 1)))
		actor.combat.confirm_direct_damage(previous, {"source_key": "environment", "emission": emission, "ranged": true, "impact_category": "explosion" if context.get("explosion", false) else "light", "impact_origin": context.get("position", DungeonProjectile._array(actor.position)), "impact_radius": context.get("radius", 1.0)})
		if actor.combat.health <= 0: _die(actor)

func _die(actor: DungeonActor) -> void:
	if actor.dead: return
	actor.clear_impact_state()
	actor.end_action_motion()
	presentation.cancel_actor(actor)
	if actor.is_player: intent.clear(actor.combat)
	actor.begin_death()
	for event in actor.combat.drain_events(): _consume(actor, event)
	if actor.is_player: player_defeated.emit()
	else:
		defeated_count += 1
		if systems and systems.profile.data.run.active:
			var drops = systems.monster_drops(actor.actor_id)
			for index in drops.size():
				var drop: Dictionary = drops[index]
				var angle: float = index * TAU / maxi(1, drops.size())
				ground_loot.spawn(int(drop.id), actor.position + Vector3(cos(angle), 0, sin(angle)) * 0.45, int(drop.amount), bool(drop.material))
		DungeonWorldStyle.effect(self, actor.position, Color("ffe0a4"), 1.2, 0.5)
		enemy_defeated.emit(actor.actor_id)

func _nearest_enemy(point: Vector3) -> DungeonActor:
	var found: DungeonActor
	var distance = INF
	for actor in actors:
		if not is_instance_valid(actor) or actor.is_player or actor.dead: continue
		var current = point.distance_squared_to(actor.position)
		if current < distance:
			distance = current
			found = actor
	return found

func _enemy_count() -> int:
	var count = monster_spawn_queue.size() + wave_spawn_queue.size()
	for actor in actors:
		if is_instance_valid(actor) and not actor.is_player and not actor.dead: count += 1
	return count

func _damage_number(point: Vector3, amount: float, received: bool) -> void:
	var text: Label3D
	if not _number_pool.is_empty(): text = _number_pool.pop_back()
	elif _numbers.size() < FEEL.damage_number_budget: text = _make_damage_number()
	else: text = _numbers.pop_front().node
	text.text = str(int(amount))
	text.modulate = Color("ff9b80") if received else Color("fff1a6")
	text.position = point
	text.show()
	_numbers.append({"node": text, "origin": point, "age": 0.0})

func _make_damage_number() -> Label3D:
	var text := Label3D.new()
	text.font_size = 48
	text.pixel_size = 0.008
	text.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(text)
	text.hide()
	return text

func _tick_damage_numbers(delta: float) -> void:
	for index in range(_numbers.size() - 1, -1, -1):
		var entry = _numbers[index]
		entry.age += delta
		if entry.age >= 0.7:
			entry.node.hide()
			_number_pool.append(entry.node)
			_numbers.remove_at(index)
		else:
			entry.node.position = entry.origin + Vector3.UP * (1.2 * entry.age / 0.7)
			entry.node.modulate.a = 1.0 - entry.age / 0.7

func show_material_gain(point: Vector3, id: int, amount: int) -> void:
	var feedback := Node3D.new()
	feedback.name = "GatheredMaterial"
	add_child(feedback)
	feedback.position = point + Vector3.UP * 0.8
	var icon := Sprite3D.new()
	icon.texture = DungeonStyle.texture("material:" + str(id))
	icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	icon.shaded = false
	icon.pixel_size = 0.65 / maxf(1.0, icon.texture.get_width() if icon.texture else 128)
	feedback.add_child(icon)
	var count := Label3D.new()
	count.text = "+%d" % amount
	count.font_size = 40
	count.pixel_size = 0.009
	count.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	count.position.y = 0.6
	feedback.add_child(count)
	var tween := create_tween().set_parallel()
	tween.tween_property(feedback, "position:y", feedback.position.y + 1.4, 1.0)
	tween.tween_property(icon, "modulate:a", 0.0, 0.35).set_delay(0.65)
	tween.tween_property(count, "modulate:a", 0.0, 0.35).set_delay(0.65)
	tween.chain().tween_callback(feedback.queue_free)

static func vector(value: Variant) -> Vector3:
	if value is Vector3: return value
	if value is Array and value.size() >= 3: return Vector3(value[0], value[1], value[2])
	if value is Dictionary: return Vector3(float(value.get("x", value.get("X", 0))), float(value.get("y", value.get("Y", 0))), float(value.get("z", value.get("Z", 0))))
	return Vector3.ZERO
