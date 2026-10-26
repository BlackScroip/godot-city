extends RefCounted

const SOURCE := "res://assets/camp_training/source.json"
const Combat = preload("res://scripts/domain/combat.gd")
const SERVICE_KEY := "camp_training"
const START_RANGE := 6.0
const LEAVE_RANGE := 12.0

var active := false
var dummies: Array[DungeonActor] = []
var elapsed := 0.0
var total_damage := 0.0
var hits := 0
var maximum_hit := 0.0
var last_reason := ""
var _world: Node3D
var _source: Dictionary = {}
var _original_combat: RefCounted
var _original_actor_state: Dictionary = {}

func marker(environment: Node3D) -> Dictionary:
	for node in environment.find_children("*", "Node3D", true, false):
		if str(node.get_meta("extras", {}).get("unityName", "")) != "PosChecker_训练场": continue
		var point: Vector3 = environment.to_local(node.global_position)
		return {"SceneName": "EnvDesignMap_MainCity", "SourceGameObjectId": "camp:training", "Type": "EEUT_UIInteractable",
			"Path": ["CampTrainingService"], "DataJson": JSON.stringify({"UIBtnName": SERVICE_KEY}),
			"exported_node_name": str(node.name), "world_position": [point.x, point.y, point.z], "reconstructed_service": true}
	return {}

func configure(world: Node3D) -> void:
	_world = world
	if _source.is_empty() and FileAccess.file_exists(SOURCE):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
		if parsed is Dictionary: _source = parsed
	refresh()

func target_position() -> Vector3:
	if not is_instance_valid(_world) or not _world.interactions: return Vector3.INF
	var item: Dictionary = _world.interactions._items.get("camp:training", {})
	return item.get("position", Vector3.INF)

func status() -> Dictionary:
	var available: bool = is_instance_valid(_world) and _world._camp_camera and _world.systems != null and bool(_world.systems.camp_feature_status("training").available)
	var point := target_position()
	var in_range: bool = point.is_finite() and is_instance_valid(_world.player) and _world.player.position.distance_to(point) <= START_RANGE if is_instance_valid(_world) else false
	var reason := ""
	if not available: reason = "请先建设训练场（铁匠铺等级 2）"
	elif not is_instance_valid(_world.player) or _world.player.dead or _world.player.combat.health <= 0: reason = "角色当前无法开始训练"
	elif _world.systems.profile.data.run.active: reason = "请先结束当前冒险"
	elif _source.is_empty() or dummies.size() != 3: reason = "训练木桩资源尚未准备完成"
	elif not active and not in_range: reason = "请先前往训练场"
	return {"available": available, "active": active, "can_start": available and reason.is_empty(), "in_range": in_range,
		"position": point, "elapsed": elapsed, "total_damage": total_damage, "hits": hits,
		"maximum_hit": maximum_hit, "dps": total_damage / elapsed if elapsed > 0 else 0.0,
		"reason": reason, "last_reason": last_reason}

func refresh() -> void:
	if not is_instance_valid(_world) or not _world._camp_camera or _source.is_empty(): return
	if not bool(_world.systems.camp_feature_status("training").available):
		finish("facility_locked")
		_clear_dummies()
		return
	if not dummies.is_empty(): return
	var model: Dictionary = _source.get("model", {})
	if not ResourceLoader.exists(str(model.get("path", ""))): return
	for index in range(1, 4):
		var anchor: Node3D = _world._camp_focus_node("EnvPosChecker_Smith_ScareCrow_" + str(index))
		if anchor == null: continue
		var dummy := DungeonActor.new()
		dummy.name = "CampScarecrow" + str(index)
		dummy.actor_id = 90010
		dummy.set_meta("camp_training", true)
		dummy.combat = _dummy_combat(index)
		_world.add_child(dummy)
		dummy.transform = _world.global_transform.affine_inverse() * anchor.global_transform
		dummy.born_position = dummy.position
		dummy.previous_position = dummy.position
		dummy.reset_physics_interpolation()
		dummy.set_visual(str(model.path), model)
		dummy.visual.scale = dummy.scale
		dummy.scale = Vector3.ONE
		dummy.combat._start(dummy.combat._action("ActGroup_cityscarecrow", "idle"), 0)
		dummy.combat.drain_events()
		_world.actors.append(dummy)
		_world._actor_index[str(dummy.combat.actor_key)] = dummy
		_world._bind_impact(dummy)
		dummies.append(dummy)

func _dummy_combat(index: int) -> RefCounted:
	var catalog: Dictionary = _world.player.combat.catalog.duplicate()
	var actor: Dictionary = _source.source["MonsterActionCfg_[90010]"]
	var definition := {"id": 90010, "name": "训练稻草人", "rank": "Normal", "hp": float(_source.source["EnvUnitCfg_[90010]"].EnvUnitData.Hp),
		"attack": 0.0, "defense": 0.0, "group": str(actor.ActionGroup), "speed": 0.0, "actions": [], "cooldown": 0.0}
	catalog["enemies"] = [definition]
	var combat := Combat.new()
	combat.configure_enemy(90010, 90010 + index, 0, catalog)
	# The source tree is empty; authored idle/hit action transitions run directly.
	combat.enemy_ai = null
	combat.enemy_ai_enabled = true
	combat.diagnostics.clear()
	combat.drain_events()
	combat.actor_key = "camp_scarecrow:" + str(index)
	combat.max_health = float(definition.hp)
	combat.health = combat.max_health
	combat.enemy_hit_rules = {"BaseTenacity": float(actor.BaseTenacity), "BaseTenacityAccReduce": float(actor.BaseTenacityAccReduce),
		"BaseWeakTime": float(actor.BaseWeakTime), "Weight": float(actor.Weight), "PushForceResist": float(actor.PushForceResist)}
	return combat

func start() -> Dictionary:
	if active: return {"success": true, "message": "训练已开始"}
	var state := status()
	if not state.can_start: return {"success": false, "message": state.reason, "reason": "out_of_range" if state.available and not state.in_range else "unavailable"}
	if _world.paused or _world._background or (_world.hud and _world.hud.modal_open): return {"success": false, "message": "请关闭当前页面后开始训练", "reason": "interaction_paused"}
	_world.clear_input()
	_original_combat = _world.player.combat
	_disconnect_impact(_original_combat, _world.player)
	_original_actor_state = {"layer": _world.player.collision_layer, "mask": _world.player.collision_mask,
		"visible": _world.player.visible, "visual_visible": _world.player.visual.visible if is_instance_valid(_world.player.visual) else true}
	var training := Combat.new()
	training.configure(_original_combat.catalog, null, _original_combat.character_id, _original_combat.difficulty, 90010)
	training.restore(_original_combat.snapshot())
	training.actor_key = _original_combat.actor_key
	training._random_state = 90010
	_world.player.combat = training
	_world._actor_index[str(training.actor_key)] = _world.player
	_world._bind_impact(_world.player)
	active = true
	reset_statistics()
	_world.presentation.prepare_combat([training])
	return {"success": true, "message": "训练开始"}

func reset_statistics() -> Dictionary:
	elapsed = 0.0
	total_damage = 0.0
	hits = 0
	maximum_hit = 0.0
	last_reason = ""
	if active:
		for index in _world.player.combat.energy.size():
			_world.player.combat.energy[index] = _world.player.combat.skill_capacity(index)
			_world.player.combat.cooldowns[index] = 0.0
		for dummy in dummies:
			if is_instance_valid(dummy): dummy.combat.health = dummy.combat.max_health
	return {"success": true, "message": "训练统计已重置"}

func advance(delta: float) -> void:
	if not active: return
	if is_instance_valid(_world.player) and (_world.player.dead or _world.player.combat.health <= 0):
		finish("player_exhausted")
		return
	if not is_instance_valid(_world.player) or _world.player.position.distance_to(target_position()) > LEAVE_RANGE:
		finish("left_range")
		return
	elapsed += maxf(0, delta)

func record_impact(hit: Dictionary, target: DungeonActor) -> void:
	if not active or not target.get_meta("camp_training", false): return
	var damage := maxf(0, float(hit.get("resolved_damage", 0)))
	if damage <= 0: return
	hits += 1
	total_damage += damage
	maximum_hit = maxf(maximum_hit, damage)
	target.combat.health = target.combat.max_health
	target.combat._start(target.combat._action("ActGroup_cityscarecrow", "behit"), 0)

func finish(reason := "finished") -> Dictionary:
	var was_active := active
	active = false
	if was_active and is_instance_valid(_world):
		_world.clear_input()
		_world.clear_training_effects()
		if is_instance_valid(_world.player) and _original_combat != null:
			_disconnect_impact(_world.player.combat, _world.player)
			_world.player.combat = _original_combat
			_world._actor_index[str(_original_combat.actor_key)] = _world.player
			_world._bind_impact(_world.player)
			_world.player.dead = false
			_world.player.suspended = _world.paused or _world._background or (_world.hud and _world.hud.modal_open)
			_world.player.end_action_motion()
			_world.player.collision_layer = int(_original_actor_state.get("layer", 2))
			_world.player.collision_mask = int(_original_actor_state.get("mask", 5))
			_world.player.visible = bool(_original_actor_state.get("visible", true))
			if is_instance_valid(_world.player.visual): _world.player.visual.visible = bool(_original_actor_state.get("visual_visible", true))
			_world.player.desired_velocity = Vector3.ZERO
			_world.player.velocity = Vector3.ZERO
			_world.player.locomotion = Vector3.ZERO
			_world.player.dodge_elapsed = -1.0
			_world.player.play_animation("idle", true)
		for index in dummies.size():
			var dummy := dummies[index]
			if not is_instance_valid(dummy): continue
			_disconnect_impact(dummy.combat, dummy)
			dummy.combat = _dummy_combat(index + 1)
			dummy.combat._start(dummy.combat._action("ActGroup_cityscarecrow", "idle"), 0)
			dummy.combat.drain_events()
			dummy.action_time = 0.0
			dummy.clear_impact_state()
			dummy.play_animation("idle", true)
			_world._bind_impact(dummy)
		last_reason = reason
	_original_combat = null
	_original_actor_state.clear()
	return {"success": true, "message": "训练结束", "statistics": status()}

func clear() -> void:
	finish("scene_changed")
	_clear_dummies()
	_world = null

func _clear_dummies() -> void:
	for dummy in dummies:
		if not is_instance_valid(dummy): continue
		if is_instance_valid(_world):
			_disconnect_impact(dummy.combat, dummy)
			_world.actors.erase(dummy)
			_world._actor_index.erase(str(dummy.combat.actor_key))
		dummy.queue_free()
	dummies.clear()

func _disconnect_impact(combat: RefCounted, actor: DungeonActor) -> void:
	var callback: Callable = _world._on_impact.bind(actor)
	if combat.impact_confirmed.is_connected(callback): combat.impact_confirmed.disconnect(callback)

