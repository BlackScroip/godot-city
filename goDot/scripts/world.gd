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
signal environment_sound(name: String)
signal skill_request_resolved(slot: int, result: Dictionary)
signal impact_confirmed(impact: Dictionary)

var player: DungeonActor
var actors: Array[DungeonActor] = []
var camera: Camera3D
var environment_root: Node3D
var catalog: Dictionary = {}
var systems: RefCounted
var _partner_skill_rules: RefCounted
var hud: DungeonHud
var paused := false
var boss_show_active := false
var _boss_show_speed := 1.0
var simulation_scale := 1.0
var _battle_scales: Dictionary = {}
var source_hit_stop_percent := 100
var runtime_settings: Dictionary = {}
var slow_motion_enabled := true
var camera_shake_percent := 100
var _source_stop_hits: Dictionary = {}
var _source_stop_projectiles: Dictionary = {}
var fighting := false
var elapsed := 0.0
var received_hits := 0
var projectiles: Array[Dictionary] = []
var pending_attack_entities: Array[Dictionary] = []
var active_attack_entities: Array[Dictionary] = []
var _projectile_visual_pool: Array[MeshInstance3D] = []
var _projectile_state_pool: Array[DungeonProjectile] = []
var _projectile_mesh: SphereMesh
var _projectile_materials: Array[StandardMaterial3D] = []
const DamageNumber = preload("res://scripts/presentation/damage_number.gd")
var _number_pool: Array[Node3D] = []
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
static var _settings_dodge_buffs: Dictionary = {}
var interactions: RefCounted
var _event_markers: Dictionary = {}
var _event_refresh_at := 0
var ground_loot = preload("res://scripts/ground_loot.gd").new()
var spirit_followers = preload("res://scripts/presentation/spirit_followers.gd").new()
var player_transfer = preload("res://scripts/presentation/player_transfer.gd").new()
var player_revival = preload("res://scripts/presentation/player_lifecycle.gd").new()
var camera_closeup = preload("res://scripts/presentation/camera_closeup.gd").new()
var camp_camera = preload("res://scripts/presentation/camp_camera.gd").new()
var camp_progression = preload("res://scripts/presentation/camp_progression.gd").new()
var camp_decorations = preload("res://scripts/presentation/camp_decorations.gd").new()
var camp_visitors = preload("res://scripts/presentation/camp_visitors.gd").new()
var camp_training = preload("res://scripts/camp_training.gd").new()
var _camp_destination := ""
var _camp_destination_page := ""
var _camp_stall_time := 0.0
var _camp_last_position := Vector3.ZERO
var _camp_pointer_id := -2
var _camp_pointer_start := Vector2.ZERO
var _camp_pointer_marker := ""
var _camp_pointer_dragged := false
var _camp_focus_nodes: Dictionary = {}
var _outcome_camera := false
var trial_room = preload("res://scripts/trial_room.gd").new()

func update_event_markers(camp: bool) -> void:
	if not camp or not interactions or not systems: return
	var now := Time.get_ticks_msec()
	if now < _event_refresh_at: return
	_event_refresh_at = now + 250
	var groups: Dictionary = {}
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
		var marker_id := "camp:tasks" if page_id == "tasks" or npc_id == 1300 else str(item.id)
		var group: Dictionary = groups.get(marker_id, {"pending": false, "position": item.position})
		group.pending = group.pending or pending
		if str(item.data.get("UIBtnName", "")) == "EnvUnit_MonoData_BtnDisplayName_Quest": group.position = item.position
		groups[marker_id] = group
	for marker_id in groups:
		var group: Dictionary = groups[marker_id]
		var pending := bool(group.pending)
		var badge = _event_markers.get(marker_id)
		if pending and not is_instance_valid(badge):
			badge = Sprite3D.new()
			badge.name = "CampEventMarker"
			badge.texture = DungeonStyle.texture("interaction_quest")
			badge.pixel_size = 0.006
			badge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			badge.no_depth_test = true
			badge.shaded = false
			environment_root.add_child(badge)
			badge.position = group.position + Vector3.UP * 3.5
			_event_markers[marker_id] = badge
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
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	get_viewport().size_changed.connect(func(): DungeonStyle.apply_options(self))
	add_child(ground_loot)
	add_child(spirit_followers)
	add_child(player_transfer)
	add_child(player_revival)
	var file = FileAccess.open("res://assets/catalog.json", FileAccess.READ)
	if file: catalog = JSON.parse_string(file.get_as_text())
	var sky = WorldEnvironment.new()
	var environment = Environment.new()
	var lighting: Array = DungeonWorldStyle.PROFILES[0]
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = lighting[0]
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = lighting[1]
	environment.ambient_light_energy = lighting[3]
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	sky.environment = environment
	add_child(sky)
	var sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_color = lighting[2]
	sun.light_energy = lighting[4]
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
	_projectile_mesh.radial_segments = 12
	_projectile_mesh.rings = 6
	for color in [Color("82e0cb"), Color("f4a65c")]:
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_projectile_materials.append(material)
	for index in 32:
		_projectile_visual_pool.append(_make_projectile_visual())
		_projectile_state_pool.append(DungeonProjectile.new())
	for index in 32: _number_pool.append(_make_damage_number())

func apply_settings(settings: Dictionary) -> void:
	runtime_settings = settings.duplicate()
	source_hit_stop_percent = int(settings.get("hit_stop", 100))
	slow_motion_enabled = bool(settings.get("slow_motion", true))
	camera_shake_percent = int(settings.get("camera_shake", 100))
	if source_hit_stop_percent == 0: _battle_scales.erase("UnitStopFrame")
	_refresh_battle_scale()
	if presentation: presentation.apply_settings(settings)
	ground_loot.apply_settings(settings)
	_refresh_dodge_settings()
	for index in range(_numbers.size() - 1, -1, -1):
		var entry: Dictionary = _numbers[index]
		if entry.get("dodge", false): continue
		var mode := int(settings.get("healing_numbers" if entry.get("healing", false) else "damage_numbers", 0))
		if mode == 2:
			entry.node.hide()
			_number_pool.append(entry.node)
			_numbers.remove_at(index)
		else: entry.node.text = number_text(float(entry.get("amount", 0)), mode, bool(entry.get("healing", false)))

func asset_path(kind: String, id: Variant) -> String:
	var entry = catalog.get(kind, {}).get(str(id), {})
	return str(entry.get("path", "")) if entry is Dictionary else str(entry)

func release_environment() -> void:
	# Callers may yield a frame here so queued GPU/scene resources retire before loading.
	camp_training.clear()
	trial_room.reset()
	_environment_generation += 1
	player_transfer.cancel()
	player_revival.cancel()
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
	camp_camera.reset()
	_cancel_camp_navigation()
	_camp_pointer_id = -2
	_camp_pointer_marker = ""
	_camp_focus_nodes.clear()
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
	DungeonWorldStyle.release_room_resources()
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
	pending_attack_entities.clear()
	active_attack_entities.clear()
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

func load_environment(id: Variant, camp := false, completion_chest_quality: String = "") -> void:
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
	if camp and systems:
		camp_progression.apply(environment_root, systems.profile.data.buildings)
		camp_decorations.apply(environment_root, systems.decorations)
	_load_collisions(path)
	if camp:
		_close_camp_portal_boundary()
		var training_marker: Dictionary = camp_training.marker(environment_root)
		if not training_marker.is_empty(): semantic_markers.append(training_marker)
		if systems: semantic_markers.append_array(camp_visitors.markers(self))
	interactions = load("res://scripts/world_interactions.gd").new()
	interactions.transition_requested.connect(func(context): environment_action.emit("transition", context))
	interactions.sound_requested.connect(func(name): environment_sound.emit(name))
	interactions.npc_requested.connect(func(id, context):
		context["npc_id"] = id
		environment_action.emit("npc", context))
	interactions.reward_requested.connect(func(context): environment_action.emit("reward", context))
	interactions.message_requested.connect(func(message, context):
		if message == "EnvUnit_DisableAllTraps": interactions.disable_traps()
		if message == "EnvUnit_InteractProtectTarget": start_protection_encounter()
		else: world_message.emit(message, context))
	interactions.player_trigger_entered.connect(func(id, _context):
		if id == 1: enter_room_encounter())
	interactions.trap_triggered.connect(_environment_trap)
	interactions.attraction_requested.connect(_environment_attract)
	interactions.diagnostic_reported.connect(func(context): _diagnostic("Environment: " + str(context)))
	interactions.setup(environment_root, semantic_markers, {"colliders": markers, "catalog": systems.catalog if systems else null, "camp": camp, "is_unlocked": func(id): return systems.is_unlocked(int(id)) if systems else false})
	if not camp: interactions.set_completion_chest_quality(completion_chest_quality)
	if camp: _apply_camp_interaction_states()
	_build_navigation(_camp_navigation_key() if camp else str(id))
	var angles: Array = environment_entry.get("camera_rotation", [45.0, -45.0])
	var elevation = deg_to_rad(float(angles[0]))
	var yaw = deg_to_rad(float(angles[1]))
	var distance = 29.0 if camp else FEEL.level_camera_height / (2.0 * tan(deg_to_rad(FEEL.level_camera_fov * 0.5)))
	_camera_offset = Vector3(-sin(yaw) * cos(elevation), sin(elevation), -cos(yaw) * cos(elevation)) * distance
	fighting = false
	elapsed = 0
	received_hits = 0
	defeated_count = 0
	_wave_reported = true
	DungeonWorldStyle.environment(self, int(str(id).substr(2, 1)), camp)
	camera.size = 17.0 if camp else FEEL.level_camera_height
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL if camp else Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = FEEL.level_camera_fov
	if camp:
		camp_camera.configure(camera, environment_entry)
		_camera_offset = camp_camera.offset()
		_apply_camp_interaction_states()
		camp_visitors.refresh(self)

func _camp_navigation_key() -> String:
	var colliders: Array = []
	for body in environment_root.find_children("*", "StaticBody3D", true, false):
		colliders.append([str(environment_root.get_path_to(body)), body.collision_layer, body.collision_mask, str(body.transform)])
	return "10000:" + JSON.stringify(colliders).sha256_text()

func _apply_camp_interaction_states() -> void:
	if not interactions: return
	for item in interactions._items.values():
		var node_name := str(item.marker.get("exported_node_name", ""))
		var active := bool(camp_progression.active_nodes.get(node_name, true)) and bool(item.data.get("InitActive", item.data.get("IsInitStateActive", true)))
		var page := str(interactions.prompt_for(item)[1])
		var npc_id := int(item.data.get("NpcId", 0))
		if npc_id == 1000: page = "talents"
		elif npc_id == 1100: page = "weapons"
		elif npc_id == 1200: page = "archive"
		elif npc_id == 1300: page = "task_npc"
		elif npc_id == 1400: page = "storage"
		elif npc_id == 1500: page = "characters"
		# The commission board remains interactable while its facility is locked.
		if systems and page in ["characters", "weapons", "talents", "awakening", "tokens", "storage", "archive", "partners", "work", "meals", "training", "extra_challenges"]:
			active = active and bool(systems.camp_feature_status(page).available)
		elif systems and page == "history":
			active = active and bool(systems.camp_feature_status("history").available)
		elif systems and page == "task_npc":
			active = active and bool(systems.camp_feature_status("tasks").available)
		elif not camp_progression.controls(node_name): continue
		item.state.enabled = active
		interactions._apply(item)
	for label in environment_root.find_children("*", "Label3D", true, false):
		if not label.has_meta("camp_marker_id"): continue
		var item: Dictionary = interactions._items.get(str(label.get_meta("camp_marker_id")), {})
		label.visible = not item.is_empty() and bool(item.get("visible", false)) and bool(item.state.enabled)

func refresh_camp_progression() -> void:
	if not _camp_camera or not systems or not is_instance_valid(environment_root): return
	_cancel_camp_navigation()
	camp_progression.apply(environment_root, systems.profile.data.buildings)
	camp_decorations.apply(environment_root, systems.decorations)
	for marker in markers:
		var body := environment_root.get_node_or_null("Collider_" + str(marker.get("fileID", "")))
		if body is StaticBody3D and camp_progression.controls(str(marker.get("exported_node_name", ""))):
			body.collision_layer = 1 if camp_progression.collider_active(marker) else 0
	_apply_camp_interaction_states()
	camp_visitors.refresh(self)
	_build_navigation(_camp_navigation_key())
	_event_refresh_at = 0
	if is_instance_valid(player): camp_training.refresh()

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
		var active := camp_progression.collider_active(item) if _camp_camera else bool(item.get("active", true))
		var staged := _camp_camera and camp_progression.controls(str(item.get("exported_node_name", "")))
		if (not active and not staged) or not properties.get("m_Enabled", 1):
			collision_report.inactive += 1
			continue
		if properties.get("m_IsTrigger", 0):
			collision_report.triggers += 1
			continue
		if int(item.get("kind", 0)) not in [64, 65, 135, 136]: continue
		var matrix = unity_matrix(item.get("world_matrix", []))
		if _camp_camera and str(item.get("path", "")).ends_with("/EnvColliderItem_Wall (67)"):
			# 1061664 MainCity bundle, BoxCollider 7645: updated riverbank wall.
			var rotation := Quaternion(0.00028932225541211665, -0.26370468735694885, 0.00009007633343571797, 0.9646034836769104)
			matrix = Transform3D(Basis(rotation) * Basis.from_scale(Vector3(0.9440160989761353, 16, 6.1600260734558105)), Vector3(35.349998474121094, 0, 68.73999786376953))
		var body = StaticBody3D.new()
		body.name = "Collider_" + str(item.get("fileID", ""))
		body.position = matrix.origin
		body.collision_layer = 1 if active else 0
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

func _close_camp_portal_boundary() -> void:
	for marker in semantic_markers:
		if str(marker.get("ObjectName", "")) != "EnvUnit_Interactable_StartNewRun": continue
		# The imported bridge side walls end behind this trigger. Close their
		# open rear seam so the shared flat floor cannot lead onto the river.
		var body := StaticBody3D.new()
		body.name = "CampPortalRearBoundary"
		body.position = unity_matrix(marker.get("world_matrix", [])).origin + Vector3(0, 0, 1.0)
		body.collision_layer = 1
		var collider := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(3.2, 16.0, 0.5)
		collider.shape = box
		body.add_child(collider)
		environment_root.add_child(body)
		collision_report["camp_portal_boundary"] = true
		return

static func unity_matrix(values: Array) -> Transform3D:
	if values.size() != 16: return Transform3D.IDENTITY
	return Transform3D(Basis(Vector3(values[0], values[4], values[8]), Vector3(values[1], values[5], values[9]), Vector3(values[2], values[6], values[10])), Vector3(values[3], values[7], values[11]))

func _build_navigation(key: String) -> void:
	if not is_instance_valid(navigation_region) or navigation_region.get_parent() != environment_root:
		navigation_region = NavigationRegion3D.new()
		environment_root.add_child(navigation_region)
	var mesh: NavigationMesh = _navigation_cache.get(key)
	if mesh != null and navigation_region.navigation_mesh == mesh:
		return
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
	player.reset_physics_interpolation()
	player.set_visual(_player_visual_path(character_id), catalog.get("characters", {}).get(str(character_id), {}))
	DungeonWorldStyle.apply_models(player)
	var facing = vector(environment_entry.get("player_rotation", {}))
	player.face_direction(Vector3(sin(deg_to_rad(facing.y)), 0, cos(deg_to_rad(facing.y))))
	actors.append(player)
	_actor_index[str(player.combat.actor_key)] = player
	_bind_impact(player)
	for window in combat.battle_time_scale_windows(): _register_battle_scale(player, window)
	if presentation:
		presentation.low_quality = low_effects
		presentation.prepare_combat([combat])
	snap_camera()
	if _camp_camera: camp_training.configure(self)
	return player

func _player_visual_path(character_id: int) -> String:
	if systems and systems.has_method("character_fashion_equipped"):
		var equipped: Dictionary = systems.character_fashion_equipped()
		var path := preload("res://scripts/presentation/character_fashion_models.gd").path_for(int(equipped.get(str(character_id), 0)))
		if not path.is_empty(): return path
	return asset_path("characters", character_id)

func refresh_player_fashion() -> bool:
	if not is_instance_valid(player): return false
	var path := _player_visual_path(player.actor_id)
	if is_instance_valid(player.visual) and player.visual.scene_file_path == path: return false
	player.set_visual(path, catalog.get("characters", {}).get(str(player.actor_id), {}))
	player.visual.rotation.y = atan2(player.facing.x, player.facing.z)
	DungeonWorldStyle.apply_models(player.visual)
	return true

func camp_training_status() -> Dictionary:
	return camp_training.status()

func start_camp_training() -> Dictionary:
	return camp_training.start()

func end_camp_training() -> Dictionary:
	return camp_training.finish()

func reset_camp_training() -> Dictionary:
	return camp_training.reset_statistics()

func clear_training_effects() -> void:
	if is_instance_valid(player):
		player.end_action_motion()
		player.clear_impact_state()
		player.action_time = 0.0
		if presentation: presentation.cancel_actor(player)
	for projectile in projectiles: _recycle_projectile(projectile)
	projectiles.clear()
	pending_attack_entities.clear()
	active_attack_entities.clear()
	for unit in summon_units:
		if is_instance_valid(unit.get("visual")): unit.visual.queue_free()
	summon_units.clear()
	_battle_scales.clear()
	_source_stop_hits.clear()
	_source_stop_projectiles.clear()
	_refresh_battle_scale()
	camera_closeup.restore()
	_camera_impulses.clear()
	_seen_impacts.clear()
	_seen_blasts.clear()
	for number in _numbers:
		number.node.hide()
		_number_pool.append(number.node)
	_numbers.clear()
	_auto_target = null

func _camera_target(interpolated := false) -> Vector3:
	var point := to_local(player.get_global_transform_interpolated().origin) if interpolated else player.position
	if _camp_camera: return camp_camera.target(point)
	var view_basis = Basis.looking_at(-_camera_offset.normalized(), Vector3.UP)
	# Keep the same world scale on wide phones; reserve the lower area for controls.
	return point + view_basis.y * camera.size * (FEEL.level_player_screen_y - 0.5)

func snap_camera() -> void:
	if not is_instance_valid(player): return
	_camera_focus = _camera_target()
	camera.position = _camera_focus + _camera_offset
	camera.look_at(_camera_focus)

func _camp_facility_available(item: Dictionary) -> bool:
	return not item.is_empty() and interactions.is_interaction_available(item) and item.position.y > -10.0 and not str(interactions.prompt_for(item)[1]).is_empty()

func camp_facility(page: String) -> Dictionary:
	if not _camp_camera or not interactions: return {}
	page = {"difficulty": "primary", "recruit": "characters", "weapon_upgrade": "weapons", "partner_skill": "partners", "work_rare": "work", "work_precious": "work"}.get(page, page)
	for item in interactions._items.values():
		if page == "talents" and int(item.data.get("NpcId", 0)) == 1000 and _camp_facility_available(item): return item
		if page in ["treasure", "chests", "storage"] and int(item.data.get("NpcId", 0)) == 1400 and _camp_facility_available(item): return item
		if page == "history" and str(interactions.prompt_for(item)[1]) == "history" and _camp_facility_available(item): return item
		if _camp_facility_available(item) and str(interactions.prompt_for(item)[1]) == page: return item
	return {}

func _camp_focus_node(source_name: String) -> Node3D:
	if _camp_focus_nodes.is_empty():
		for node in interactions._nodes.values():
			if node is Node3D and is_instance_valid(node):
				_camp_focus_nodes[str(node.get_meta("extras", {}).get("unityName", str(node.name)))] = node
	return _camp_focus_nodes.get(source_name)

func _camp_marker(marker_id: String) -> Dictionary:
	if not interactions: return {}
	if marker_id == "camp:work":
		for item in interactions._items.values():
			if str(item.marker.get("Type", "")) == "EEUT_Special_MonsterWork": return item
	return interactions._items.get(marker_id, {})

func focus_camp_facility(page: String, duration := 2.4) -> bool:
	var item := camp_facility(page)
	if item.is_empty(): return false
	_cancel_camp_navigation()
	camp_camera.focus(item.position + Vector3.UP * 0.7, duration)
	return true

func focus_camp_building(building_id: int, stage: int, duration := 2.4) -> bool:
	if not _camp_camera or not systems or not interactions: return false
	var row: Dictionary = systems.catalog.find("Buildings", building_id)
	var targets := str(row.get("build_anim_target_transform_name", "")).split("|", false)
	if stage < 1 or stage > targets.size(): return false
	var target_name := str(targets[stage - 1])
	var node := _camp_focus_node(target_name)
	if node:
		_cancel_camp_navigation()
		camp_camera.focus(node.global_position + Vector3.UP * 0.7, duration)
		return true
	return false

func navigate_to_camp_facility(page: String) -> bool:
	var item := camp_facility(page)
	var accepted := _navigate_to_camp_marker(str(item.get("id", "")))
	if accepted and page in ["work", "talents", "treasure", "chests", "storage", "training", "history"]: _camp_destination_page = page
	return accepted

func _navigate_to_camp_marker(marker_id: String) -> bool:
	if not _camp_camera or not interactions or not is_instance_valid(player) or player.dead or paused or _background or (hud and hud.modal_open): return false
	var item := _camp_marker(marker_id)
	if not _camp_facility_available(item): return false
	camp_camera.focus_remaining = 0.0
	_camp_destination = str(item.id)
	_camp_destination_page = ""
	_camp_stall_time = 0.0
	_camp_last_position = player.position
	player.navigation_timer = 0.0
	return true

func _cancel_camp_navigation() -> void:
	_camp_destination = ""
	_camp_destination_page = ""
	_camp_stall_time = 0.0

func interact_camp_marker(marker_id: String) -> Dictionary:
	if not _camp_camera or not interactions or not is_instance_valid(player) or player.dead or paused or _background or (hud and hud.modal_open):
		return {"success": false, "reason": "interaction_paused"}
	var item := _camp_marker(marker_id)
	if item.is_empty() or not interactions.is_interaction_available(item) or item.position.y <= -10.0: return {"success": false, "reason": "unavailable"}
	if not interactions.can_interact_at(str(item.id), player.position): return {"success": false, "reason": "out_of_range"}
	_cancel_camp_navigation()
	return interactions.interact(str(item.id))

func _camp_navigation_velocity(delta: float) -> Vector3:
	if _camp_destination.is_empty(): return Vector3.ZERO
	var item := _camp_marker(_camp_destination)
	if not _camp_facility_available(item):
		_cancel_camp_navigation()
		return Vector3.ZERO
	if interactions.can_interact_at(str(item.id), player.position):
		var destination := _camp_destination
		var page := _camp_destination_page
		_cancel_camp_navigation()
		if not page.is_empty(): world_message.emit("camp_page", {"page": page})
		else: interact_camp_marker(destination)
		return Vector3.ZERO
	_camp_stall_time = _camp_stall_time + delta if player.position.distance_squared_to(_camp_last_position) < 0.00001 else 0.0
	_camp_last_position = player.position
	if _camp_stall_time > 1.5:
		_cancel_camp_navigation()
		if hud: hud.toast("无法到达设施，请调整位置后重试")
		return Vector3.ZERO
	return _chase(player, item.position, delta)

func camp_marker_at_screen(point: Vector2) -> String:
	if not _camp_camera or not interactions or not camera: return ""
	var closest := ""
	var best := 40.0 * maxf(1.0, get_viewport().get_visible_rect().size.y / 900.0)
	var candidates: Array = interactions._items.values()
	var work := _camp_marker("camp:work")
	if not work.is_empty(): candidates.append(work)
	for item in candidates:
		if not _camp_facility_available(item): continue
		var anchor: Vector3 = item.position + Vector3.UP * 0.7
		if camera.is_position_behind(anchor): continue
		var projected := camera.unproject_position(anchor)
		if not get_viewport().get_visible_rect().has_point(projected): continue
		var distance := point.distance_to(projected)
		if distance < best:
			best = distance
			closest = str(item.id)
	return closest

func _unhandled_input(event: InputEvent) -> void:
	if not _camp_camera or paused or _background or (hud and hud.modal_open): return
	if event is InputEventScreenDrag and event.index == _camp_pointer_id:
		_camp_pointer_dragged = _camp_pointer_dragged or event.position.distance_to(_camp_pointer_start) > 18.0
		return
	if event is InputEventMouseMotion and _camp_pointer_id == -1:
		_camp_pointer_dragged = _camp_pointer_dragged or event.position.distance_to(_camp_pointer_start) > 18.0
		return
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		camp_camera.zoom(-1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0)
		get_viewport().set_input_as_handled()
		return
	var pointer := -2
	var pressed := false
	var point := Vector2.ZERO
	if event is InputEventScreenTouch:
		pointer = event.index
		pressed = event.pressed
		point = event.position
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		pointer = -1
		pressed = event.pressed
		point = event.position
	else: return
	if pressed:
		if _camp_pointer_id != -2: return
		_camp_pointer_id = pointer
		_camp_pointer_start = point
		_camp_pointer_marker = camp_marker_at_screen(point)
		_camp_pointer_dragged = false
	elif pointer == _camp_pointer_id:
		var marker := _camp_pointer_marker
		var dragged: bool = _camp_pointer_dragged or (event is InputEventScreenTouch and event.canceled)
		_camp_pointer_id = -2
		_camp_pointer_marker = ""
		_camp_pointer_dragged = false
		if not dragged and not marker.is_empty() and point.distance_to(_camp_pointer_start) <= 18.0 and camp_marker_at_screen(point) == marker:
			if _navigate_to_camp_marker(marker): get_viewport().set_input_as_handled()

func _update_camp_camera(delta: float, hold_focus := false) -> void:
	camp_camera.step(delta, hold_focus)
	_camera_offset = camp_camera.offset()
	_camera_focus = _camera_focus.lerp(_camera_target(true), camp_camera.follow_weight(delta))
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
		var saved_combat: Dictionary = spawn.get("combat_snapshot", {})
		var restoring := not saved_combat.is_empty()
		var hp_override = float(spawn.get("health_override", spawn.get("HealthOverride", 0)))
		if hp_override > 0:
			actor.combat.max_health = hp_override
			actor.combat.health = hp_override
		var attack_override = float(spawn.get("attack_override", spawn.get("AttackOverride", 0)))
		if attack_override > 0: actor.combat.attack = attack_override
		for buff in spawn.get("passive_buff_ids", spawn.get("PassiveBuffIds", [])):
			actor.combat.add_buff(str(buff), 1)
		actor.combat.health = actor.combat.max_health
		if restoring:
			if not actor.combat.restore(saved_combat):
				_diagnostic("Invalid saved enemy combat: %d" % actor.actor_id)
				actor.free()
				continue
		elif systems:
			for buff in systems.enemy_creation_buffs(actor.actor_id): actor.combat.add_buff(str(buff), 1)
			actor.combat.apply_enemy_enhancements(systems.enemy_enhancements(actor.actor_id))
			actor.combat.health = actor.combat.max_health
		if actor.combat.is_mohua(): actor.scale = Vector3.ONE * 1.1
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
		actor.reset_physics_interpolation()
		actor.set_visual(asset_path("enemies", actor.actor_id), catalog.get("enemies", {}).get(str(actor.actor_id), {}), _prepare_enemy_scene(actor.actor_id))
		if actor.visual: actor.visual.rotation.y = yaw
		DungeonWorldStyle.apply_models(actor)
		actors.append(actor)
		_actor_index[str(actor.combat.actor_key)] = actor
		_bind_impact(actor)
		if not restoring: actor.combat.begin_enemy_spawn()
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
	if room_fight_type == "ProtectTarget": interactions.complete_protection()
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
	interactions.set_battle_boundaries_active(room_stage in ["protection", "fighting", "clearing", "trial"])
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
	if not player or player.dead or paused or boss_show_active or _background or (hud and hud.modal_open): result = {"success": false, "status": "rejected"}
	else:
		if pressed:
			_release_auto_heavy()
			_automatic_action = false
			if slot == 0 and auto_attack_enabled: player.combat.request_attack(4, false)
		if slot in [5, 6]:
			result = _partner_controller().request(player.combat, slot - 5) if pressed and systems else {"success": not pressed}
			if pressed and result.get("success", false):
				systems.effects.dispatch_message("Rogue_MonsterPartnerSkillUsed", {"slot": slot - 5})
				var target := _nearest_enemy(player.position)
				if is_instance_valid(target) and player.position.distance_squared_to(target.position) <= 400.0 and int(runtime_settings.get("target_mode", 0)) != 2:
					player.face_direction(target.position - player.position)
		else: result = intent.attack_button(player.combat, pressed) if slot == 0 else intent.request(player.combat, slot, pressed)
	skill_request_resolved.emit(slot, result)
	return result

func _partner_controller() -> RefCounted:
	if _partner_skill_rules == null:
		_partner_skill_rules = preload("res://scripts/domain/partner_skills.gd").new(systems)
	return _partner_skill_rules

func partner_skill_state() -> Dictionary:
	if not systems or not systems.profile.data.run.active or not is_instance_valid(player): return {}
	return _partner_controller().state(player.combat)

func advance_partner_skills(delta: float) -> void:
	if not systems or not systems.profile.data.run.active or not is_instance_valid(player): return
	var in_range := false
	if fighting:
		for actor in actors:
			if is_instance_valid(actor) and not actor.is_player and not actor.dead and player.position.distance_squared_to(actor.position) <= 400.0:
				in_range = true
				break
	_partner_controller().tick(player.combat, delta, in_range)

func set_attack_mode(mode: String) -> void:
	var normalized = mode if mode in ["normal", "heavy", "off"] else "normal"
	if normalized == auto_attack_mode: return
	_release_auto_heavy()
	_automatic_action = false
	auto_attack_mode = normalized
	_auto_attack = 0.0

func cancel_skill(slot: int) -> void:
	if is_instance_valid(player): intent.cancel_button(player.combat, slot)

func _release_auto_heavy() -> void:
	if not _automatic_heavy_held: return
	_automatic_heavy_held = false
	if is_instance_valid(player):
		player.combat.request_attack(4, false)
		# The wand otherwise keeps its authored alternating mode after release.
		player.combat.custom_properties.AttackModeStr = "normal"

func clear_input() -> void:
	_cancel_camp_navigation()
	_camp_pointer_id = -2
	_camp_pointer_marker = ""
	_camp_pointer_dragged = false
	_release_auto_heavy()
	intent.clear(player.combat if is_instance_valid(player) else null)
	if player:
		player.desired_velocity = Vector3.ZERO
		player.locomotion = Vector3.ZERO
	if hud:
		hud.joystick._reset()
		for key in hud.skill_buttons: key.release(true)
		hud.attack_mode_button.release(true)

func set_boss_show(enabled: bool, speed: float = 1.0) -> void:
	var entering := enabled and not boss_show_active
	boss_show_active = enabled
	_boss_show_speed = speed if enabled else 1.0
	if enabled: clear_input()
	if entering and is_instance_valid(player) and not player.dead:
		_automatic_action = false
		var idle: Dictionary = player.combat._action("ActGroup_playerchara", "sys_idle")
		if not idle.is_empty():
			player.combat._start(idle, -1)
			for event in player.combat.drain_events(): _consume(player, event)
	_refresh_battle_scale()

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
		var score: float = distance * (0.64 if actor == _auto_target else 1.0)
		if int(runtime_settings.get("target_mode", 0)) == 0 and player.desired_velocity.length_squared() > 0.0001:
			var direction := (actor.position - player.position).normalized()
			var alignment := player.desired_velocity.normalized().dot(direction)
			if alignment < 0.0: continue
			score *= 1.0 + (1.0 - alignment) * 4.0
		candidates.append({"actor": actor, "score": score})
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
	if int(runtime_settings.get("attack_priority", 0)) == 1: return false
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
		intent.heavy_held = false
	elif target and int(runtime_settings.get("target_mode", 0)) != 2: player.face_direction(target.position - player.position)
	return true

func _process(delta: float) -> void:
	delta *= simulation_scale
	player_transfer.advance(delta, _background)
	player_revival.advance(delta, _background)
	if not paused and not _background and not (hud and hud.modal_open): _tick_damage_numbers(delta)
	if not is_instance_valid(player) or player.dead: return
	var stopped = paused or _background or (hud and hud.modal_open)
	if presentation:
		presentation.suspended = stopped
		presentation.low_quality = low_effects
	camera_closeup.pause(stopped)
	if stopped:
		if _camp_camera and not paused and not _background and camp_camera.focus_remaining > 0.0: _update_camp_camera(delta, true)
		return
	_tick_monster_spawns()
	if _camp_camera:
		_update_camp_camera(delta)
		return
	if not _outcome_camera:
		camera_closeup.update_action(player, player.combat.action_elapsed * float(player.combat.custom_properties.get("_feel_action_speed", 1)) * 1000.0)
	camera_closeup.step(delta)
	var focus = _camera_target(true) + player.locomotion.limit_length(1.0) * FEEL.camera_lookahead
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
	offset *= float(camera_shake_percent) / 100.0
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
	if not stopped: _advance_battle_scale(delta * simulation_scale)
	var input_delta = delta
	delta *= simulation_scale
	spirit_followers.advance(delta, player, stopped)
	if stopped and not _input_suspended: clear_input()
	_input_suspended = stopped
	for actor in actors:
		if is_instance_valid(actor):
			actor.suspended = stopped
			actor.simulation_scale = simulation_scale
	if stopped:
		for actor in actors:
			if is_instance_valid(actor): actor.desired_velocity = Vector3.ZERO
		return
	camp_training.advance(delta)
	advance_partner_skills(delta)
	_physics_serial += 1
	_prune_source_stop_hits()
	_tick_room_sequence(delta)
	trial_room.advance(delta)
	if systems and not player.dead:
		var collected := ground_loot.advance_collection(delta, player.position, systems)
		if not collected.is_empty():
			environment_action.emit("auto_loot", {"coin": collected.any(func(entry): return int(entry.get("id", 0)) == 101)})
	_impact_clock += delta
	for cache in [_seen_impacts, _seen_blasts]:
		for key in cache.keys():
			if _impact_clock - float(cache[key]) > 8.0: cache.erase(key)
	if fighting: elapsed += delta
	_tick_wave_spawns(delta)
	var movement = Vector2.ZERO
	if not boss_show_active and (not hud or not hud.modal_open):
		movement = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if hud: movement += hud.joystick.value
		movement = movement.limit_length()
	var right = camera.global_basis.x
	var forward = -camera.global_basis.z
	right.y = 0
	forward.y = 0
	player.desired_velocity = (right.normalized() * movement.x - forward.normalized() * movement.y) * float(player.combat.move_speed)
	if _camp_camera:
		if movement.length_squared() > 0.0001:
			_cancel_camp_navigation()
			camp_camera.focus_remaining = 0.0
		elif not _camp_destination.is_empty():
			player.desired_velocity = _camp_navigation_velocity(delta)
	if player.desired_velocity.length_squared() > 0.0001: intent.last_move = player.desired_velocity.normalized()
	if test_driver and fighting and not boss_show_active:
		var nearest = _nearest_enemy(player.position)
		if nearest:
			var direction = nearest.position - player.position
			direction.y = 0
			player.desired_velocity = _chase(player, nearest.position, delta) if direction.length() > 1.5 else Vector3.ZERO
	if _automatic_action and player.combat._current_slot == 0 and player.desired_velocity.length_squared() >= 0.04:
		if not _movement_allows_auto_attack(_auto_target):
			player.combat.cancel_normal_attack()
			_automatic_action = false
	_tick_player_input(input_delta)
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
		if actor.get_meta("camp_training", false):
			actor.desired_velocity = Vector3.ZERO
			actor.combat._tick_enemy_interrupts()
		elif not actor.is_player:
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
	presentation.sync_buffs(actors)
	_tick_attack_entities(delta)
	_tick_projectiles(delta)
	_tick_summons(delta)
	if interactions:
		var targets: Array = []
		for actor in actors:
			if is_instance_valid(actor) and not actor.dead and not actor.is_player: targets.append({"id": str(actor.combat.actor_key), "position": actor.position, "camp": 3})
		interactions.tick(delta, player.position, targets)
	_tick_wave_clear(delta)

func _tick_player_input(delta: float) -> void:
	_refresh_dodge_settings()
	if boss_show_active: return
	intent.advance_hold(player.combat, delta)
	if _automatic_heavy_held:
		if player.dead or intent.manual_attack_active() or not (fighting or camp_training.active) or not _movement_allows_auto_attack(_attack_target(4)):
			_release_auto_heavy()
		elif player.combat.busy <= 0:
			_release_auto_heavy()
	var requested = intent.take_ready(player.combat, delta)
	if requested >= 0:
		var executed = _execute_player(requested)
		skill_request_resolved.emit(requested, {"success": executed, "status": "executed" if executed else "rejected"})
	elif not intent.manual_attack_active() and auto_attack_enabled and (fighting or camp_training.active) and not player.dead and player.dodge_elapsed < 0:
		var slot = 4 if auto_attack_mode == "heavy" else 0
		var target = _attack_target(slot)
		if not _movement_allows_auto_attack(target): return
		if slot == 0:
			_auto_attack += delta
			if _auto_attack + 0.000001 < 0.25: return
		if player.combat.busy <= 0 and player.combat.input_block_reason(slot).is_empty() and player.combat.cooldowns[slot] <= 0:
			if slot == 0: player.combat.request_attack(4, false)
			if _execute_player(slot, true, target):
				_automatic_heavy_held = slot == 4
				if slot == 0: _auto_attack = 0.0

func _refresh_dodge_settings() -> void:
	if not is_instance_valid(player) or not runtime_settings.has("dodge_priority"): return
	if _settings_dodge_buffs.is_empty():
		var source: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/settings/dodge_buffs.json"))
		if source is Dictionary: _settings_dodge_buffs = source
	for id in _settings_dodge_buffs:
		if player.combat._buff_index.has(id): continue
		var raw: Dictionary = _settings_dodge_buffs[id].raw
		var definition: Dictionary = player.combat._buff_index.get("26081001", {}).duplicate(true)
		definition.merge({"id": id, "type": raw.BuffType, "name": raw.BuffData.Name_EDT, "raw": JSON.stringify(raw), "raw_data": raw.BuffData, "apk_source": _settings_dodge_buffs[id].apk_source}, true)
		player.combat._buff_index = player.combat._buff_index.duplicate()
		player.combat._buff_index[id] = definition
	var mode := int(runtime_settings.dodge_priority)
	var chain := mode == 0 and is_instance_valid(_attack_target(0))
	for id in ["26080801", "26081001"]:
		var wanted: bool = mode == 2 if id == "26080801" else chain
		if wanted and not player.combat.statuses.has(id): player.combat.add_buff(id)
		elif not wanted and player.combat.statuses.has(id): player.combat.remove_buff(id)

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

func _register_battle_scale(actor: DungeonActor, window: Dictionary) -> void:
	# The APK registers by unit, replacing that unit's previous modifier.
	_battle_scales[actor.get_instance_id()] = {"actor": weakref(actor), "scale": maxf(0, float(window.scale)), "remaining": float(window.duration)}
	_refresh_battle_scale()

func _advance_battle_scale(delta: float) -> void:
	for key in _battle_scales.keys():
		var entry: Dictionary = _battle_scales[key]
		entry.remaining -= delta
		var expired: bool = entry.remaining < 0
		if entry.has("actor"):
			var actor = entry.actor.get_ref()
			expired = expired or not is_instance_valid(actor) or actor.dead
		if expired: _battle_scales.erase(key)
	_refresh_battle_scale()

func _register_source_hit_stop(hit: Dictionary, source: DungeonActor, feedback: Dictionary) -> void:
	var percent := source_hit_stop_percent if source_hit_stop_percent in [0, 50, 100] else 100
	if percent <= 0 or feedback.get("hit_stops", []).is_empty(): return
	var key := ImpactProfiles.instance_id(hit)
	if _source_stop_hits.has(key): return
	var modifier: float = source.combat.source_stop_frame_modifier(hit.get("definition", {})) if source else 0.0
	for stop in feedback.hit_stops:
		var weight := maxf(0.0, float(stop.weight) + modifier)
		if weight <= 0: continue
		_source_stop_hits[key] = _physics_serial
		# The APK uses one global UnitStopFrame key and its battle-scaled clock.
		_battle_scales["UnitStopFrame"] = {"scale": 0.12, "remaining": weight * 0.12 * float(percent) / 100.0}
		_refresh_battle_scale()
		return

func _prune_source_stop_hits() -> void:
	if _source_stop_hits.is_empty(): return
	for key in _source_stop_hits.keys():
		if int(_source_stop_hits[key]) < _physics_serial - 1 and not _source_stop_projectiles.has(key): _source_stop_hits.erase(key)

func _refresh_battle_scale() -> void:
	simulation_scale = 1.0
	for key in _battle_scales:
		if not slow_motion_enabled and key != "UnitStopFrame": continue
		simulation_scale = minf(simulation_scale, float(_battle_scales[key].scale))
	simulation_scale *= _boss_show_speed
	if presentation: presentation.simulation_scale = simulation_scale

func _consume(actor: DungeonActor, event: Dictionary) -> void:
	match str(event.get("type", event.get("kind", ""))):
		"battle_time_scale":
			if str(event.get("phase", "")) == "Enter": _register_battle_scale(actor, event.window)
			else:
				_battle_scales.erase(actor.get_instance_id())
				_refresh_battle_scale()
		"action_started":
			if actor.is_player and not _outcome_camera: camera_closeup.enter(actor, str(event.get("action", "")), _camera_conditions)
			_cancel_attached_projectiles(actor, int(event.sequence), true)
			actor.begin_action(event)
			if not actor.is_player: actor.action_target = player if is_instance_valid(player) and not player.dead else null
			presentation.action_started(actor, event)
			var action_name = str(event.get("action", ""))
			actor.play_animation(action_name if actor.animations.has(action_name) else "idle" if action_name == "sys_idle" else "dodge" if int(event.get("slot", 0)) == 1 else "attack", true)
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
			if actor.get_meta("chest_trial", false) and trial_room.consume_hit(event): return
			var definition: Dictionary = event.get("definition", {})
			var raw = _raw_definition(definition)
			if raw.get("EntityType", "EET_Physical" if definition.get("projectile", false) else "") == "EET_Physical":
				if raw.get("EmitType", "") == "EET_MultiPoint":
					var transform_data := DungeonProjectile.multipoint_transform(event, _hit_origin(actor, event), _hit_facing(actor, event))
					presentation.attack_emitted(actor, event, transform_data.position, transform_data.facing)
				else:
					presentation.attack_emitted(actor, event, _hit_origin(actor, event))
			else:
				var transform_data = _frame_entity_transform(actor, event)
				presentation.attack_emitted(actor, event, transform_data.position, transform_data.facing)
			_start_attack_entity(actor, event)
		"summon": _create_summon(actor, event)
		"summon_trigger_effect":
			var raw: Dictionary = event.get("definition", {})
			presentation.summon_trigger(actor, raw, _resolve_origin(actor, event), str(event.get("phase", "")), ImpactProfiles.is_source_heavy(event, actor.combat))
		"pickup_spawn": pass # The paired summon event owns this pickup's persistent state.
		"spawn_monster": _spawn_monsters(actor, event)
		"delete_unit":
			actor.apply_delete_event(event.get("definition", {}))
		"ai_message":
			var message: Dictionary = event.get("message", {})
			if str(message.get("name", "")) == "Rogue_RewardSlimeBeHit":
				_drop_reward_slime(actor, str(message.get("parameters", {}).get("Arg1", "")))
		"message":
			var definition: Dictionary = event.get("definition", event)
			var message = str(definition.get("MessageName", definition.get("MsgName", event.get("name", ""))))
			if message == "EnvUnit_DisableAllTraps" and interactions: interactions.disable_traps()
			if message == "Rogue_RewardSlimeBeHit":
				_drop_reward_slime(actor, str(definition.get("MsgArg1", definition.get("Arg1", event.get("argument", "")))))
				return
			if actor.is_player: spirit_followers.trigger_message(message, actor, presentation)
			for recipient in actors:
				if is_instance_valid(recipient) and not recipient.dead: recipient.combat.notify_gameplay("message", {"name": message, "argument": definition.get("MsgArg1", definition.get("Arg1", ""))})
			if not camp_training.active: world_message.emit(message, definition)
		"buff_effect":
			presentation.buff_effect(actor, event)
		"partner_charge":
			if actor.is_player and systems: _partner_controller().charge(event.get("settings", {}))
		"heal":
			if float(event.get("amount", 0)) > 0: _healing_number(actor.position + Vector3.UP * 1.8, float(event.amount))
		"evaded_hit":
			if str(event.get("dodge_type", "")) != "Block": _dodge_number(actor, str(event.get("dodge_type", "")) == "BeHiterAutoDodge")
		"area":
			_consume_area(actor, event)
		"command":
			var command: Dictionary = event.get("command", event)
			if int(event.get("sequence", -1)) != actor.combat._cast_sequence: return
			presentation.command(actor, event)
			if str(command.get("type", "")) == "EET_CameraEffect":
				var settings_effects := get_node_or_null("SettingsEffects")
				var camera_effect := _raw_definition(command)
				if settings_effects and str(camera_effect.get("EffectType", "")) in ["ECET_FlashLight", "3"]:
					var effect_data: Dictionary = camera_effect.get("EffectData", {})
					var color: Color = presentation.color_for(actor)
					if bool(effect_data.get("UseOverrideColor", false)):
						var raw_color: Dictionary = effect_data.get("FlashLightColor", {})
						color = Color(float(raw_color.get("r", 1)), float(raw_color.get("g", 1)), float(raw_color.get("b", 1)), 1)
					settings_effects.screen_flash(float(effect_data.get("Intensity", 1)), float(command.get("duration", 0.5)), color, actor, int(event.get("sequence", -1)))
			if str(command.get("type", "")) == "EET_CameraShake" and actor.is_player:
				var raw_shake = _raw_definition(command)
				raw_shake["FeedbackType"] = "EHT_CameraShake"
				_queue_source_shakes(HitFeedback.normalize({"FeedbackList": [raw_shake]}).camera_shakes)
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

func _consume_area(actor: DungeonActor, event: Dictionary) -> void:
	var host = _actor_by_key(str(event.get("host_key", "")))
	if not is_instance_valid(host): host = actor
	var definition: Dictionary = event.get("definition", {})
	var center = host.position + host.facing * float(event.get("forward_offset", 0))
	event["impact_origin"] = DungeonProjectile._array(center)
	var radius_squared = pow(maxf(0.0, float(definition.get("radius", 0))), 2)
	var targets: Array[DungeonActor] = []
	for target in actors:
		if not is_instance_valid(target) or target.dead: continue
		if target == host:
			if not bool(definition.get("includeSelf", false)): continue
		elif (target.is_player == host.is_player) != bool(definition.get("sameCamp", false)): continue
		if target.position.distance_squared_to(center) <= radius_squared: targets.append(target)
	var maximum = int(definition.get("maxTargets", -1))
	if bool(definition.get("randomTargets", false)) and targets.size() > 1:
		var source = event.get("source", host.combat)
		if not source is DungeonCombat: source = host.combat
		# Use the saved combat RNG so a restored random-target skill is reproducible.
		for index in range(targets.size() - 1, 0, -1):
			var chosen = mini(index, int(source._random() * (index + 1)))
			var previous = targets[index]
			targets[index] = targets[chosen]
			targets[chosen] = previous
	if maximum >= 0 and targets.size() > maximum: targets.resize(maximum)
	for target in targets:
		if target.get_meta("camp_training", false) and not camp_training.active: continue
		_bind_impact(target)
		target.combat.apply_area(event, host.is_player == target.is_player, target.position.distance_squared_to(center), host == target)
		if target.combat.health <= 0: _die(target)

func _start_attack_entity(actor: DungeonActor, hit: Dictionary) -> void:
	var raw = _raw_definition(hit.get("definition", {}))
	var delay = maxf(0.0, float(raw.get("EntityProperty", {}).get("Delay", 0)))
	if delay <= 0:
		_activate_attack_entity(actor, hit)
		return
	var saved = hit.duplicate(true)
	saved.erase("source")
	saved["entity_origin"] = DungeonProjectile._array(_hit_origin(actor, hit))
	saved["entity_facing"] = DungeonProjectile._array(_hit_facing(actor, hit))
	pending_attack_entities.append({"owner": actor.combat.actor_key, "remaining": delay, "hit": saved})

func _tick_attack_entities(delta: float) -> void:
	if delta <= 0: return
	for entry in active_attack_entities.duplicate():
		var source = _actor_by_key(str(entry.owner))
		if not is_instance_valid(source):
			active_attack_entities.erase(entry)
			continue
		var raw = _read_definition(entry.hit.get("definition", {}))
		if bool(raw.get("DeadActionChanged", false)) and int(entry.hit.get("sequence", -1)) != source.combat._cast_sequence:
			active_attack_entities.erase(entry)
			continue
		entry.age = float(entry.age) + delta
		if float(entry.age) + 0.000001 >= float(entry.life):
			_finish_attack_entity(source, entry.hit)
			active_attack_entities.erase(entry)
			continue
		entry.hit["entity_age"] = entry.age
		_hit_area(source, entry.hit)
	for entry in pending_attack_entities.duplicate():
		var source = _actor_by_key(str(entry.owner))
		if not is_instance_valid(source):
			pending_attack_entities.erase(entry)
			continue
		var raw = _read_definition(entry.hit.get("definition", {}))
		if bool(raw.get("DeadActionChanged", false)) and int(entry.hit.get("sequence", -1)) != source.combat._cast_sequence:
			pending_attack_entities.erase(entry)
			continue
		entry.remaining = maxf(0.0, float(entry.remaining) - delta)
		if float(entry.remaining) > 0.000001: continue
		pending_attack_entities.erase(entry)
		_activate_attack_entity(source, entry.hit)

func _activate_attack_entity(actor: DungeonActor, hit: Dictionary) -> void:
	var definition: Dictionary = hit.get("definition", {})
	var raw = _raw_definition(definition)
	if raw.get("EntityType", "EET_Physical" if definition.get("projectile", false) else "") == "EET_Physical":
		var state = _projectile(actor, hit)
		presentation.entity_activated(actor, hit, state.position, state.direction)
	else:
		var saved = hit.duplicate(true)
		saved.erase("source")
		saved["entity_origin"] = DungeonProjectile._array(_hit_origin(actor, hit))
		saved["entity_facing"] = DungeonProjectile._array(_hit_facing(actor, hit))
		saved["entity_contacts"] = {}
		saved["entity_age"] = 0.0
		var transform_data = _frame_entity_transform(actor, saved)
		saved["entity_hit_origin"] = DungeonProjectile._array(transform_data.position)
		presentation.entity_activated(actor, saved, transform_data.position, transform_data.facing)
		_hit_area(actor, saved)
		var lifetime = maxf(0.0, float(raw.get("EntityProperty", {}).get("CheckTime", 0)))
		if lifetime > 0: active_attack_entities.append({"owner": actor.combat.actor_key, "age": 0.0, "life": lifetime, "hit": saved})
		else: _finish_attack_entity(actor, saved)

func _finish_attack_entity(actor: DungeonActor, hit: Dictionary) -> void:
	var raw = _raw_definition(hit.get("definition", {}))
	var point = vector(hit.get("impact_origin", DungeonProjectile._array(_hit_origin(actor, hit))))
	var ending: Dictionary = raw.get("EntityProperty", {}).get("AddSummonUnitDefOnEnd", {}).duplicate(true)
	ending["world_facing"] = DungeonProjectile._array(_frame_entity_transform(actor, hit).facing)
	_spawn_from_definition(actor, ending, point, hit)

func _frame_entity_transform(source: DungeonActor, hit: Dictionary) -> Dictionary:
	var definition: Dictionary = hit.get("definition", hit.get("area", {}))
	var raw = _read_definition(definition)
	var facing = _hit_facing(source, hit)
	var center = _hit_origin(source, hit) + facing * (float(hit.get("forward_offset", 0)) + float(definition.get("offset", 0)))
	var hit_facing = vector(hit.get("trial_facing", facing))
	var emit: Dictionary = raw.get("EmitProperty", {})
	if raw.get("EmitType", "") == "EET_MultiPoint":
		return DungeonProjectile.multipoint_transform(hit, _hit_origin(source, hit) + facing * float(hit.get("forward_offset", 0)), hit_facing)
	if not emit.is_empty():
		var yaw = deg_to_rad(float(emit.get("EmitRotation", {}).get("y", 0)))
		var local_offset = float(hit.get("forward_offset", 0)) + (0.0 if emit.has("EmitOffset") else float(definition.get("offset", 0)))
		var offset = vector(emit.get("EmitOffset", {})) + Basis(Vector3.UP, yaw) * (vector(emit.get("AfterRotateEmitOffset", {})) + Vector3(0, 0, local_offset))
		center = _hit_origin(source, hit) + DungeonProjectile.orient(offset, facing)
		hit_facing = hit_facing.rotated(Vector3.UP, yaw)
	return {"position": center, "facing": hit_facing}

func _hit_area(source: DungeonActor, hit: Dictionary, area := false) -> void:
	var definition: Dictionary = hit.get("definition", hit.get("area", {}))
	var raw = _read_definition(definition)
	var entity: Dictionary = raw.get("EntityProperty", {})
	var width = maxf(0, float(definition.get("width", 1)))
	var length_value = maxf(0, float(definition.get("length", 1)))
	var transform_data = _frame_entity_transform(source, hit)
	var center: Vector3 = transform_data.position
	var hit_facing: Vector3 = transform_data.facing
	hit["impact_origin"] = DungeonProjectile._array(center)
	hit["impact_forward"] = DungeonProjectile._array(hit_facing)
	hit["impact_entity_type"] = "frame"
	if not hit.has("entity_hit_origin"): hit["entity_hit_origin"] = DungeonProjectile._array(center)
	hit["impact_radius"] = maxf(width, length_value) * 0.5
	for target in actors:
		if not is_instance_valid(target) or target.dead or target.is_player == source.is_player: continue
		var contacts: Dictionary = hit.get("entity_contacts", {})
		var target_key = str(target.combat.actor_key)
		var previous: Dictionary = contacts.get(target_key, {})
		if hit.has("entity_contacts") and not previous.is_empty():
			if not bool(entity.get("CheckTimeCauseContinuousTrigger", false)): continue
			var frame_limit = int(entity.get("CheckActiveEffectTargetMaxCount", 0))
			var attack_limit = int(raw.get("EffectActiveTotalCountToEachUnit", 999999))
			var maximum = mini(frame_limit if frame_limit > 0 else 2147483647, attack_limit if attack_limit > 0 else 2147483647)
			var interval = maxf(float(entity.get("CheckActiveEffectTargetCDTime", 0)), float(raw.get("EffectActiveIntervalToEachUnit", 0)))
			if int(previous.count) >= maximum or float(hit.get("entity_age", 0)) - float(previous.at) + 0.000001 < interval: continue
		var difference = target.position - center
		difference.y = 0
		var intersects = difference.length() <= maxf(width, length_value) * 0.5 + 0.35 if definition.get("shape", "Cube") == "Sphere" else absf(difference.dot(hit_facing)) <= length_value * 0.5 + 0.35 and absf(difference.dot(Vector3.UP.cross(hit_facing))) <= width * 0.5 + 0.35
		if raw.get("EntityType", "") == "EET_FrameFan":
			var degrees = float(entity.get("Degree", 360))
			intersects = difference.length() <= float(entity.get("Radius", maxf(width, length_value) * 0.5)) + 0.35 and (degrees >= 359 or difference.length() < 0.4 or absf(rad_to_deg(hit_facing.signed_angle_to(difference.normalized(), Vector3.UP))) <= degrees * 0.5)
		if intersects:
			# Settled hit payloads contain live caster references and target-specific data.
			var contact = hit.duplicate(true)
			if hit.has("entity_contacts"): contact["contact"] = int(previous.get("count", 0))
			_apply_hit(source, target, contact)
			if contact.has("emission"): hit["emission"] = contact.emission
			if hit.has("entity_contacts") and bool(contact.get("resolved_accepted", false)):
				contacts[target_key] = {"count": int(previous.get("count", 0)) + 1, "at": float(hit.get("entity_age", 0))}
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
	for feedback in HitFeedback.read(hit.get("definition", hit)).hit_actions:
		amount += int(feedback.acc_tenacity)
		result.append(maxi(0, amount))
	return result

func _environment_hit_id(source: DungeonActor, hit: Dictionary) -> String:
	if not hit.has("emission"):
		_impact_serial += 1
		hit["emission"] = "environment-hit:%d" % _impact_serial
	return str(source.combat.actor_key) + ":" + ImpactProfiles.instance_id(hit)

func _apply_hit(source: DungeonActor, target: DungeonActor, hit: Dictionary) -> void:
	if target.dead: return
	if target.invulnerability > 0:
		if target.dodge_elapsed >= 0: _dodge_number(target)
		return
	if target.get_meta("camp_training", false) and not camp_training.active: return
	_bind_impact(target)
	hit["source"] = source.combat
	var entity_origin := vector(hit.get("entity_hit_origin", hit.get("impact_origin", DungeonProjectile._array(source.position))))
	var center := target.position + target.COLLISION_CENTER
	var toward_entity := entity_origin - center
	var normal := toward_entity.normalized() if toward_entity.length() > 0.00001 else Vector3.ZERO
	var hit_point := center + Vector3(normal.x, 0.0, normal.z) * target.COLLISION_RADIUS * 0.9
	var hit_direction := vector(hit.get("impact_forward", DungeonProjectile._array(source.facing))) if hit.get("impact_entity_type", "frame") == "physical" else center - entity_origin
	hit["hit_geometry"] = {
		"attacker_position": DungeonProjectile._array(source.position),
		"attacker_forward": DungeonProjectile._array(source.facing),
		"attackee_position": DungeonProjectile._array(target.position),
		"attackee_forward": DungeonProjectile._array(target.facing),
		"entity_position": DungeonProjectile._array(hit_point),
		"entity_forward": DungeonProjectile._array(hit_direction),
	}
	if not hit.has("emission"):
		_impact_serial += 1
		hit["emission"] = "world:%s" % _impact_serial
	if not hit.has("impact_position"): hit["impact_position"] = DungeonProjectile._array(target.position + Vector3.UP * 0.65)
	hit["distance"] = source.position.distance_to(target.position)
	target.combat.receive(hit, source.combat.effective_attack_power())
	if not target.is_player:
		var hit_facing := target.ENEMY_HIT_REACTION.take_facing(target.combat)
		if not hit_facing.is_zero_approx(): target.facing = hit_facing
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
	if camp_training.active: camp_training.record_impact(hit, target)
	if bool(profile.get("source_only", false)):
		_register_source_hit_stop(hit, source, profile.get("source_feedback", {}))
	if FEEL.impact_enabled:
		var visual_source = source if source else target
		presentation.impact(visual_source, target, hit)
		if bool(profile.get("source_only", false)):
			_queue_source_shakes(profile.get("source_feedback", {}).get("camera_shakes", []))
			if ImpactProfiles.is_source_wolf(hit, source.combat if source else null) and damage > 0 and (profile.category != "continuous" or float(profile.distance) > 0):
				_apply_feedback(source, target, hit)
		else:
			target.hit_flash(float(profile.flash))
			target.combat.apply_hit_stop(float(profile.stop) * float(source_hit_stop_percent) / 100.0)
			if source and not profile.ranged and int(hit.get("sequence", -1)) == source.combat._cast_sequence:
				source.combat.apply_hit_stop(float(profile.stop) * float(source_hit_stop_percent) / 100.0, true)
			if damage > 0 and (profile.category != "continuous" or float(profile.distance) > 0): _apply_feedback(source, target, hit)
			if profile.category == "explosion":
				_blast(visual_source, hit, profile, vector(hit.get("impact_origin", hit.impact_position)))
			else:
				_queue_impact_shake(profile, point)
	if damage > 0:
		_damage_number(target.position + Vector3.UP * 1.8, damage, target.is_player, bool(hit.get("resolved_critical", false)), str(hit.get("definition", {}).get("element", "Physical")))
		if target.is_player and not camp_training.active: received_hits += 1
	if not camp_training.active and not target.get_meta("camp_training", false): impact_confirmed.emit(hit)

func _queue_source_shakes(shakes: Array) -> void:
	for definition in shakes:
		var shake: Dictionary = definition.duplicate()
		shake["age"] = 0.0
		if not shake.is_delay: shake.delay = 0.0
		if _camera_impulses.size() >= 8: _camera_impulses.pop_front()
		_camera_impulses.append(shake)

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

func _projectile(source: DungeonActor, hit: Dictionary) -> DungeonProjectile:
	var state = _projectile_state_pool.pop_back() if not _projectile_state_pool.is_empty() else DungeonProjectile.new()
	var target = _nearest_opponent(source)
	var origin = _hit_origin(source, hit)
	var target_point = target.position if target else origin + source.facing * 8
	var raw := _raw_definition(hit.get("definition", {}))
	var facing = _hit_facing(source, hit)
	var direction = DungeonProjectile.emission_facing(raw, int(hit.get("emit_index", 0)), facing, target_point - origin)
	var dummy := str(raw.get("EmitProperty", {}).get("DummyData", {}).get("DummyType", ""))
	hit["owner_height"] = 0.0 if dummy == "Unit_FootBottom" else 0.75
	state.configure(hit, origin + Vector3.UP * float(hit.owner_height) + facing * float(hit.get("forward_offset", 0)), direction, target_point, facing)
	state.source_key = str(source.combat.actor_key)
	state.source_player = source.is_player
	state.target_key = str(target.combat.actor_key) if target else ""
	for message in state.diagnostics: _diagnostic(message)
	_add_projectile_visual(state, source)
	return state

func _add_projectile_visual(state: DungeonProjectile, source: DungeonActor) -> void:
	state.hit["source_key"] = state.source_key
	var source_only := ImpactProfiles.is_source_heavy(state.hit, source.combat) or ImpactProfiles.is_source_wolf(state.hit, source.combat)
	if source_only:
		var key := ImpactProfiles.instance_id(state.hit)
		state.hit["_source_stop_identity"] = key
		_source_stop_projectiles[key] = int(_source_stop_projectiles.get(key, 0)) + 1
	var mesh: MeshInstance3D = _projectile_visual_pool.pop_back() if not _projectile_visual_pool.is_empty() else _make_projectile_visual()
	mesh.transform = Transform3D.IDENTITY
	mesh.material_override = _projectile_materials[0 if source.is_player else 1]
	mesh.position = state.position
	mesh.visible = not source_only and not (_attached_projectile(state) and str(state.entity.get("ModlePrefab", "")).is_empty())
	presentation.projectile_started(source, state, mesh)
	projectiles.append({"source": source, "state": state, "visual": mesh})
	_warn_budget("projectiles", projectiles.size(), FEEL.projectile_warning_budget)

func _make_projectile_visual() -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = _projectile_mesh
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	var stop_key := str(state.hit.get("_source_stop_identity", ""))
	if not stop_key.is_empty():
		var remaining := int(_source_stop_projectiles.get(stop_key, 0)) - 1
		if remaining <= 0: _source_stop_projectiles.erase(stop_key)
		else: _source_stop_projectiles[stop_key] = remaining
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
		for definition in state.drain_interval_summons():
			_spawn_from_definition(source, definition, state.position, state.hit)
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
				contact_hit["impact_forward"] = DungeonProjectile._array(state.direction)
				contact_hit["impact_entity_type"] = "physical"
				contact_hit["impact_radius"] = state.radius
				contact_hit["contact"] = int(state.hits.get(key, 0))
				contact_hit["ranged"] = state.motion_type not in ["EMAT_FollowOwner", "EMAT_RotateOwner"]
				_apply_hit(source, target, contact_hit)
				if contact_hit.get("skill_charge_attempted", false): state.hit["skill_charge_attempted"] = true
				state.record_hit(key)
				if state.finished: break
		state.finished = state.finished or expires_now
		if state.finished:
			var end_profile = ImpactProfiles.resolve(state.hit, source.combat)
			if end_profile.category == "explosion" and FEEL.impact_enabled: _blast(source, state.hit, end_profile, state.position)
			presentation.projectile_ended(source, state)
			_apply_raw_buff(source.combat, state.entity.get("AddBuffOwnerWhenDispose", {}), source.combat)
			_spawn_from_definition(source, state.entity.get("AddSummonUnitDef", {}), state.position, state.hit)
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
	if target.get_meta("camp_training", false): return
	var profile: Dictionary = hit.profile if hit.has("profile") else ImpactProfiles.resolve(hit, source.combat if source else null)
	# Monster force is settled by EnemyHitReaction, independently of visual feedback.
	if not target.is_player: return
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
		if str(feedback.get("PushMode", "")) == "AttackEntityToAttackeeDir": direction = target.position - origin
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
		var interrupt = profile.category in ["heavy", "explosion"]
		target.combat.apply_stagger(float(profile.stagger) * factor, interrupt)

func _diagnostic(message: String) -> void:
	if not diagnostics.has(message): diagnostics.append(message)

static func _raw_definition(definition: Dictionary) -> Dictionary:
	# Callers may edit commands, including nested fields; keep their payload private.
	return _read_definition(definition).duplicate(true)

static func _read_definition(definition: Dictionary) -> Dictionary:
	return HitFeedback.raw({"raw": definition.get("raw", "{}")})

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
	if source.is_player and int(runtime_settings.get("target_mode", 0)) == 2: return null
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
	var total = int(event.get("generation_count", definition.get("GenerationTotalCount", 0)))
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
	if hit.has("entity_origin"): return vector(hit.entity_origin)
	if hit.has("trial_origin"): return vector(hit.trial_origin)
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
		var token := str(value.get("_summon_token", ""))
		if not token.is_empty():
			for unit in summon_units:
				if str(unit.get("token", "")) == token and str(unit.owner) == str(source.combat.actor_key): return unit.position
		if value.has("x") or value.has("X"): return vector(value)
		if value.has("world_position"): return vector(value.world_position)
		var target = _actor_by_key(str(event.get("target_key", "")))
		if target and str(value.get("OriginType", "")) == "targetPosAndSelfDir": return target.position
	return source.position

func _hit_facing(source: DungeonActor, event: Dictionary) -> Vector3:
	if event.has("entity_facing"): return vector(event.entity_facing)
	var origin: Dictionary = event.get("origin", {}) if event.get("origin", {}) is Dictionary else {}
	return vector(origin.world_facing) if origin.has("world_facing") else source.facing

func _create_summon(source: DungeonActor, event: Dictionary) -> void:
	var definition: Dictionary = event.get("definition", {})
	var raw: Dictionary = definition.get("raw_data", {})
	var origin = _resolve_origin(source, event)
	var origin_def: Dictionary = event.get("origin", {}) if event.get("origin", {}) is Dictionary else {}
	var offset = vector(raw.get("InitPosOffset", {})) + vector(origin_def.get("InitPosOffset", {}))
	var facing = _hit_facing(source, event)
	if origin_def.is_empty() or (origin_def.size() == 1 and origin_def.has("_summon_token")): offset += Vector3(0, 0, float(event.get("forward_offset", 0)))
	_summon_serial += 1
	var unit = {"serial": _summon_serial, "id": str(event.id), "owner": str(source.combat.actor_key), "position": origin + DungeonProjectile.orient(offset, facing), "offset": offset, "age": 0.0, "life": maxf(0.05, float(event.get("lifetime", 1))), "next": 0.0, "raw": raw, "type": str(definition.get("type", "")), "triggered": false, "children": {}, "action": event.get("action", source.combat.current_action), "slot": event.get("slot", source.combat._current_slot), "sequence": event.get("sequence", source.combat._cast_sequence)}
	if origin_def.has("world_facing"): unit["fixed_facing"] = DungeonProjectile._array(facing)
	unit["source_heavy"] = ImpactProfiles.is_source_heavy(event, source.combat)
	unit["token"] = str(origin_def.get("_summon_token", ""))
	var limit = int(raw.get("MaxExistCount", -1))
	var existing: Array = []
	for previous_unit in summon_units:
		if previous_unit.id == unit.id and previous_unit.owner == unit.owner: existing.append(previous_unit)
	while limit > 0 and existing.size() >= limit: _dispose_summon(existing.pop_front(), false)
	if not source.is_player or not spirit_followers.handles_prefab(str(raw.get("Prefab", ""))):
		unit["effect_token"] = presentation.summon_started(source, raw, unit.position, facing, unit.source_heavy)
	if not unit.source_heavy and unit.type == "ESUT_PickupableItem" and int(unit.get("effect_token", 0)) == 0:
		var mesh = Sprite3D.new()
		mesh.texture = DungeonStyle.texture("material:" + str(unit.id))
		mesh.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		mesh.pixel_size = 0.007
		add_child(mesh)
		mesh.position = unit.position + Vector3.UP * 0.3
		unit["visual"] = mesh
	presentation.summon_created(source, raw, unit.position, unit.source_heavy)
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
		presentation.summon_updated(int(unit.get("effect_token", 0)), unit.position, vector(unit.get("fixed_facing", owner.facing)))
		if unit.type == "ESUT_PickupableItem" and player and not player.dead and player.position.distance_to(unit.position) <= float(raw.get("PickUpRange", 2)):
			_apply_raw_buff(player.combat, raw.get("BuffTrigger_Picker", {}), owner.combat)
			player.combat.notify_gameplay("pickup", {"id": unit.id})
			presentation.summon_pickup(player, raw, unit.position, bool(unit.get("source_heavy", false)))
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
				_spawn_from_definition(owner, child.get("AddData", {}), unit.position, unit)
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
		if degrees < 359 and toward.length() > 0.01 and absf(rad_to_deg(vector(unit.get("fixed_facing", owner.facing)).signed_angle_to(toward.normalized(), Vector3.UP))) > degrees * 0.5: continue
		_apply_feedback(null, target, {"definition": {"raw": JSON.stringify(raw)}, "impact_origin": DungeonProjectile._array(unit.position), "profile": {"category": "continuous", "distance": absf(power) * FEEL.monster_field_pull_per_power, "travel": interval, "stagger": 0.0}})

func _summon_area(unit: Dictionary, owner: DungeonActor, phase: String) -> void:
	var raw: Dictionary = unit.raw
	if phase in ["Start", "End"] and not raw.get("Trigger" + phase, false): return
	presentation.summon_phase(owner, raw, unit.position, phase, bool(unit.get("source_heavy", false)))
	var radius = float(raw.get("EffectRadius", 1))
	for target in actors:
		if not is_instance_valid(target) or target.dead or (target == owner and not raw.get("EffectToSelf", false)): continue
		if (target.is_player == owner.is_player) != bool(raw.get("TargetCampIsSelf", false)): continue
		if target.position.distance_squared_to(unit.position) > radius * radius: continue
		_apply_raw_buff(target.combat, raw.get("AddBuffData_" + phase, {}), owner.combat)
		if raw.get("EnableCauseDamage", false):
			var definition: Dictionary = owner.combat._damage_data(int(raw.get("DamageDefId", 0)))
			if not definition.is_empty(): _apply_hit(owner, target, {"source": owner.combat, "definition": {"damageId": int(raw.get("DamageDefId", 0)), "element": str(definition.get("DamageType", "Physical")), "attribute": str(definition.get("DamageAttribType", "FinalAtk"))}, "damage": owner.combat._damage_value(definition, owner.combat.effective_attack_power()), "summon_id": unit.id, "action": unit.get("action", ""), "slot": unit.get("slot", 0), "sequence": unit.get("sequence", 0), "source_heavy": bool(unit.get("source_heavy", false)), "emission": "summon:%s:%s" % [unit.serial, unit.age], "ranged": true, "continuous": phase == "Loop", "impact_origin": DungeonProjectile._array(unit.position), "impact_radius": radius})

func _spawn_from_definition(owner: DungeonActor, definition: Dictionary, point: Vector3, provenance: Dictionary = {}) -> void:
	var id = str(definition.get("AddSummonUnitId", ""))
	if id.is_empty() or id == "0": return
	for index in range(clampi(int(definition.get("AddSummonUnitQuantity", 1)), 1, 30)):
		var origin = definition.duplicate(true)
		origin["world_position"] = DungeonProjectile._array(point)
		if ImpactProfiles.is_source_heavy(provenance, owner.combat): origin["_source_heavy"] = true
		owner.combat.spawn_summon(id, origin, "", provenance)

func _dispose_summon(unit: Dictionary, trigger_end: bool) -> void:
	var owner = _actor_by_key(unit.owner)
	if owner and trigger_end:
		if unit.type == "ESUT_StaticRangeTrigger": _summon_area(unit, owner, "End")
		presentation.summon_disposed(owner, unit.raw, unit.position, bool(unit.get("source_heavy", false)))
		_apply_raw_buff(owner.combat, unit.raw.get("AddBuffOwnerWhenDispose", {}), owner.combat)
		_spawn_from_definition(owner, unit.raw.get("DeadCreateSummonUnit", {}), unit.position, unit)
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
	var source_stop := {"hits": _source_stop_hits.keys(), "register": _battle_scales.get("UnitStopFrame", {}).duplicate()}
	return {"projectiles": bullets, "pending_attack_entities": pending_attack_entities.duplicate(true), "active_attack_entities": active_attack_entities.duplicate(true), "summons": units, "source_hit_stop": source_stop, "actor_serial": _actor_serial, "summon_serial": _summon_serial, "ground_loot": ground_loot.snapshot(), "action_motion": motion_states, "monster_spawn_queue": monster_spawn_queue.duplicate(true), "wave_spawns": wave_spawn_queue.duplicate(true), "wave_spawn_wait": _wave_spawn_wait, "wave_gate": _wave_gate_remaining, "wave_clear_wait": _wave_clear_remaining, "wave_final": _wave_final, "chest_trial": trial_room.snapshot(), "room_flow": {"stage": room_stage, "fight_type": room_fight_type, "remaining": _room_stage_wait, "entry_wave": _entry_wave.duplicate(true), "defeated_count": defeated_count}}

func restore_transients(snapshot: Dictionary) -> void:
	pending_attack_entities.assign(snapshot.get("pending_attack_entities", []).duplicate(true))
	active_attack_entities.assign(snapshot.get("active_attack_entities", []).duplicate(true))
	_source_stop_hits.clear()
	_battle_scales.erase("UnitStopFrame")
	var source_stop: Dictionary = snapshot.get("source_hit_stop", {})
	for key in source_stop.get("hits", []): _source_stop_hits[str(key)] = _physics_serial
	var stop_register: Dictionary = source_stop.get("register", {})
	if not stop_register.is_empty() and float(stop_register.get("remaining", -1)) >= 0:
		_battle_scales["UnitStopFrame"] = {"scale": 0.12, "remaining": float(stop_register.remaining)}
	_refresh_battle_scale()
	trial_room.restore(snapshot.get("chest_trial", {}))
	var room_flow: Dictionary = snapshot.get("room_flow", {})
	if not room_flow.is_empty():
		room_stage = str(room_flow.get("stage", "unmanaged"))
		room_fight_type = str(room_flow.get("fight_type", room_fight_type))
		_room_stage_wait = maxf(0.0, float(room_flow.get("remaining", 0)))
		_entry_wave = room_flow.get("entry_wave", {}).duplicate(true)
		defeated_count = maxi(0, int(room_flow.get("defeated_count", 0)))
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
		_create_summon(source, {"id": unit.id, "definition": {"raw_data": unit.raw, "type": unit.type}, "lifetime": unit.life, "origin": unit.position - DungeonProjectile.orient(unit.offset, source.facing), "source_heavy": bool(unit.get("source_heavy", false)), "action": unit.get("action", ""), "slot": unit.get("slot", 0), "sequence": unit.get("sequence", 0)})
		var restored = summon_units.back()
		for field in unit:
			if field != "effect_token": restored[field] = unit[field]

func _environment_attract(context: Dictionary) -> void:
	var force: Variant = context.get("force")
	if not force is Vector3 or not force.is_finite(): return
	for actor in actors:
		if not is_instance_valid(actor) or actor.dead or actor.suspended or not actor.is_inside_tree() or actor.is_queued_for_deletion() or actor.combat == null: continue
		if str(context.get("target_id", "")) != ("player" if actor.is_player else str(actor.combat.actor_key)): continue
		if not DungeonWorldInteractions.camp_allows(str(context.get("camp_mask", "")), 2 if actor.is_player else 3) or not actor.combat.can_be_attracted(): continue
		actor.move_and_collide(force / actor.combat.attraction_weight())
		context["position_after"] = actor.global_position

func _environment_trap(context: Dictionary) -> void:
	_impact_serial += 1
	var emission = "environment:%s" % _impact_serial
	for actor in actors:
		if not is_instance_valid(actor) or actor.dead: continue
		if not DungeonWorldInteractions.camp_allows(str(context.get("camp_mask", "111")), 2 if actor.is_player else 3): continue
		var target_id = str(context.get("target_id", ""))
		if not target_id.is_empty():
			if target_id != ("player" if actor.is_player else str(actor.combat.actor_key)): continue
		else:
			if actor.position.distance_to(vector(context.get("position", {}))) > float(context.get("radius", 0)): continue
		_bind_impact(actor)
		var buff_id := str(context.get("buff_id", ""))
		var definition: Dictionary = actor.combat._buff_index.get(buff_id, {})
		var layers := maxi(1, int(context.get("layers", 1)))
		var caster: DungeonCombat = player.combat if is_instance_valid(player) else actor.combat
		# Instant environment hits use the same immunity, shield and on-hit rules as attacks.
		# Retaining a zero-lifetime status until the next tick loses its recipient-specific damage tier.
		if str(definition.get("type", "")) == "EBT_SpecialTriggerRangeDamage" and float(definition.get("duration", -1)) == 0 and float(definition.get("firstDelay", 0)) == 0:
			var area: Dictionary = actor.combat._status_area(definition, caster)
			actor.combat._status_range_visual(definition, caster)
			_consume_area(actor, {"type": "area", "id": buff_id, "host_key": actor.combat.actor_key, "source": caster, "definition": area, "layers": layers, "caster_attack": caster.effective_attack_power(), "damage": float(area.get("damage", 0)) * layers, "emission": emission + ":" + str(actor.combat.actor_key), "continuous": false, "ranged": true, "impact_category": "explosion" if context.get("explosion", false) else "light", "impact_origin": context.get("position", DungeonProjectile._array(actor.position)), "impact_radius": context.get("radius", 1.0)})
		else:
			var previous = actor.combat.health
			actor.combat.bind_buff_caster(buff_id, caster)
			actor.combat.add_buff(buff_id, layers, caster.effective_attack_power())
			actor.combat.confirm_direct_damage(previous, {"source_key": "environment", "emission": emission, "ranged": true, "impact_category": "explosion" if context.get("explosion", false) else "light", "impact_origin": context.get("position", DungeonProjectile._array(actor.position)), "impact_radius": context.get("radius", 1.0)})
		if actor.combat.health <= 0: _die(actor)

func _drop_reward_slime(actor: DungeonActor, event: String) -> void:
	if actor.is_player or not systems or camp_training.active: return
	for drop in systems.reward_slime_drops(actor.actor_id, event):
		ground_loot.spawn(int(drop.id), actor.position, int(drop.amount), true)

func _die(actor: DungeonActor) -> void:
	if actor.get_meta("camp_training", false):
		actor.combat.health = actor.combat.max_health
		return
	if actor.is_player and camp_training.active:
		camp_training.finish("player_exhausted")
		return
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
			var drops = systems.monster_drops(actor.actor_id, actor.combat.is_mohua())
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

func _damage_number(point: Vector3, amount: float, received: bool, critical := false, element := "Physical") -> void:
	_spawn_number(point, amount, received, false, critical, element)

func _dodge_number(actor: DungeonActor, automatic := false) -> void:
	if not actor.is_player or actor.dead: return
	if _impact_clock - float(actor.get_meta("last_dodge_caption", -10.0)) < 0.3: return
	actor.set_meta("last_dodge_caption", _impact_clock)
	var caption := DungeonLocale.keyed("keyword_AutoDodge" if automatic else "keyword_Dodge", "自动闪避" if automatic else "闪避")
	_spawn_number(actor.position + Vector3.UP * 1.8, 1.0, false, false, false, "Physical", true, caption)

func _healing_number(point: Vector3, amount: float) -> void:
	_spawn_number(point, amount, false, true)

static func number_text(amount: float, mode: int, healing := false) -> String:
	var value := str(int(amount))
	if mode == 1:
		if amount >= 1000000: value = ("%.1f" % (amount / 1000000.0)).trim_suffix(".0") + "M"
		elif amount >= 1000: value = ("%.1f" % (amount / 1000.0)).trim_suffix(".0") + "K"
	return ("+" if healing else "") + value

func _spawn_number(point: Vector3, amount: float, received: bool, healing: bool, critical := false, element := "Physical", dodge := false, caption := "") -> void:
	var mode := int(runtime_settings.get("healing_numbers" if healing else "damage_numbers", 0))
	if (mode == 2 and not dodge) or amount <= 0.0: return
	var text: Node3D
	if not _number_pool.is_empty(): text = _number_pool.pop_back()
	elif _numbers.size() < FEEL.damage_number_budget: text = _make_damage_number()
	else: text = _numbers.pop_front().node
	var style := element.to_lower()
	if style not in ["fire", "water", "wind", "thunder", "light", "dark", "soil", "ice", "toxin"]: style = "normal"
	if healing: style = "heal"
	elif received: style = "hurt"
	if dodge: style = "dodge"
	text.configure(caption if dodge else number_text(amount, mode, healing), style, critical and not dodge and not healing)
	var nearby := 0
	for entry in _numbers:
		if entry.age < 0.25 and entry.origin.distance_squared_to(point) < 1.0: nearby += 1
	var right := camera.global_basis.x if is_instance_valid(camera) else Vector3.RIGHT
	var up := camera.global_basis.y if is_instance_valid(camera) else Vector3.UP
	var lane := float((nearby % 3) - 1)
	var origin := point + right * lane * 0.45 + up * float(nearby / 3) * 0.25
	text.position = origin
	text.scale = Vector3.ONE * _number_screen_scale(origin)
	text.show()
	_numbers.append({"node": text, "origin": origin, "travel": right * lane * 0.65 + up * 1.1, "age": 0.0, "amount": amount, "healing": healing, "dodge": dodge})

func _make_damage_number() -> Node3D:
	var text := DamageNumber.new()
	add_child(text)
	text.hide()
	return text

func _number_screen_scale(point: Vector3) -> float:
	if not is_instance_valid(camera) or camera.is_position_behind(point): return 1.0
	var pixels_per_unit := camera.unproject_position(point).distance_to(camera.unproject_position(point + camera.global_basis.y))
	# APK PopEffect_Damage: 20 pt; Canvas reference height 1080. Preserve UI size across camera zooms.
	return (20.0 / 68.0) * get_viewport().get_visible_rect().size.y / 1080.0 / maxf(0.001, pixels_per_unit * 0.007)

func _tick_damage_numbers(delta: float) -> void:
	for index in range(_numbers.size() - 1, -1, -1):
		var entry = _numbers[index]
		entry.age += delta
		var is_dodge: bool = entry.get("dodge", false)
		var lifetime := 0.95 if is_dodge else 1.0
		if entry.age >= lifetime:
			entry.node.hide()
			_number_pool.append(entry.node)
			_numbers.remove_at(index)
		else:
			var progress := clampf(float(entry.age) / 0.5, 0.0, 1.0)
			entry.node.position = entry.origin + entry.travel * (1.0 - pow(1.0 - progress, 3.0))
			var pop_scale := lerpf(1.0, 1.5, minf(float(entry.age) / 0.04, 1.0)) if is_dodge else lerpf(1.0, 2.205, minf(float(entry.age) / 0.1, 1.0))
			entry.node.scale = Vector3.ONE * _number_screen_scale(entry.node.position) * pop_scale
			var fade_in := 0.1 if is_dodge else 0.05
			var fade_out := 0.3 if is_dodge else 0.2
			entry.node.modulate = Color(1, 1, 1, minf(float(entry.age) / fade_in, 1.0) * clampf((lifetime - float(entry.age)) / fade_out, 0.0, 1.0))

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
