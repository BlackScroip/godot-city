extends RefCounted

var world
var campaign
var turret: DungeonActor
var center := Vector3.ZERO
var _wave := -1
var _reported := false
var _areas: Array = []

func configure(source, route) -> void:
	world = source
	campaign = route
	var status: Dictionary = campaign.trial_status()
	center = world.interactions.setup_trial_chests(float(status.get("side_offset", 2.5)))
	var props = world.environment_root.get_node_or_null("RoomProps")
	if props != null: props.refresh_chests()
	if not center.is_finite(): center = world.player.position + Vector3(0, 0, 5)
	sync()

func reset() -> void:
	if is_instance_valid(turret): turret.queue_free()
	turret = null
	world = null
	campaign = null
	_wave = -1
	_reported = false
	_areas.clear()

func sync() -> void:
	if campaign == null: return
	var status: Dictionary = campaign.trial_status()
	if status.is_empty(): return
	world.interactions.sync_trial_chests(int(status.chest_index) if status.phase != "choice" else -1)
	world.room_stage = "trial" if status.active else "open"
	world.fighting = bool(status.active)
	world.sync_room_gates()
	if not status.active: return
	if not is_instance_valid(turret): _create_turret(int(status.turret_id))
	if is_instance_valid(turret) and status.phase == "wave" and _wave != int(status.wave_index):
		_wave = int(status.wave_index)
		var action: Dictionary = turret.combat._action(str(turret.combat.enemy.group), str(status.action))
		if not action.is_empty():
			turret.combat._start(action, 0)
			for event in turret.combat.drain_events(): world._consume(turret, event)
			world.environment_action.emit("trial_wave", {"wave": _wave + 1, "total": int(status.wave_count)})

func _create_turret(id: int) -> void:
	var combat = DungeonCombat.new()
	if not combat._load_catalog(null): return
	var source: Dictionary = combat.catalog.get("special_actors", {}).get(str(id), {})
	if source.is_empty(): return
	combat._reset()
	combat.enemy = {"id": id, "group": str(source.ActionGroup), "speed": 0.0, "cooldown": 0.0}
	combat.enemy_id = id
	combat.actor_key = "trial:%d" % id
	combat.max_health = 1000000
	combat.health = combat.max_health
	combat.attack = 0
	combat.defense = 0
	combat.add_buff("24102801", 1)
	turret = DungeonActor.new()
	turret.actor_id = id
	turret.combat = combat
	turret.set_meta("chest_trial", true)
	world.add_child(turret)
	turret.position = center
	turret.face_direction(Vector3.BACK)
	turret.collision_layer = 0
	turret.collision_mask = 0
	world._actor_index[combat.actor_key] = turret
	world.presentation.prepare_combat([combat])

func advance(delta: float) -> void:
	if campaign == null or not is_instance_valid(world.player) or world.player.dead: return
	var status: Dictionary = campaign.trial_status()
	if not status.get("active", false):
		if status.get("phase", "") == "complete" and not status.get("reward_claimed", false) and not _reported:
			_reported = true
			world.environment_action.emit("trial_complete", {"position": reward_position()})
		return
	sync()
	if is_instance_valid(turret):
		turret.combat.tick(delta)
		for event in turret.combat.drain_events(): world._consume(turret, event)
	for area in _areas.duplicate():
		area.remaining = float(area.remaining) - delta
		if float(area.remaining) <= 0:
			if is_instance_valid(turret): world._hit_area(turret, area.hit)
			_areas.erase(area)
	campaign.tick_trial(delta, attacks_alive())
	var after: Dictionary = campaign.trial_status()
	if after.phase != status.phase or int(after.wave_index) != int(status.wave_index): sync()

func reward_position() -> Vector3:
	var status: Dictionary = campaign.trial_status() if campaign != null else {}
	return center + Vector3.RIGHT * float(status.get("side_offset", 2.5)) * (int(status.get("chest_index", 1)) - 1)

func consume_hit(hit: Dictionary) -> bool:
	if not is_instance_valid(turret): return false
	var raw: Dictionary = world._raw_definition(hit.get("definition", {}))
	var emit: Dictionary = raw.get("EmitProperty", {})
	var direction = DungeonProjectile.emission_facing(raw, int(hit.get("emit_index", 0)), turret.facing, world.player.position - center)
	var point: Vector3 = world._hit_origin(turret, hit) + DungeonProjectile.orient(world.vector(emit.get("PosOffset", {})), turret.facing) + direction * float(emit.get("RadiusOffset", 0))
	if str(raw.get("EmitType", "")) == "EET_MultiPoint":
		var points: Array = emit.get("PointData", [])
		var index = int(hit.get("emit_index", 0))
		if index < points.size():
			point += DungeonProjectile.orient(world.vector(points[index].get("Offset", {})), turret.facing)
			direction = direction.rotated(Vector3.UP, deg_to_rad(float(points[index].get("Rotate", {}).get("y", 0))))
	else:
		direction = direction.rotated(Vector3.UP, deg_to_rad(float(emit.get("EmitRotation", {}).get("y", 0))))
		point += DungeonProjectile.orient(world.vector(emit.get("EmitOffset", {})), turret.facing) + DungeonProjectile.orient(world.vector(emit.get("AfterRotateEmitOffset", {})), direction)
	var event: Dictionary = hit.duplicate(true)
	event["origin"] = {"world_position": DungeonProjectile._array(point)}
	event["trial_origin"] = DungeonProjectile._array(point)
	event["trial_facing"] = DungeonProjectile._array(direction)
	raw = raw.duplicate(true)
	raw["EmitType"] = "EET_Once"
	raw["EmitProperty"] = {}
	event.definition["raw"] = JSON.stringify(raw)
	world.presentation.attack_emitted(turret, event, point)
	if raw.get("EntityType", "") == "EET_Physical":
		var previous = turret.facing
		turret.facing = direction
		world._projectile(turret, event)
		turret.facing = previous
		return true
	_areas.append({"remaining": maxf(0, float(raw.get("EntityProperty", {}).get("Delay", 0))), "hit": event})
	return true

func attacks_alive() -> bool:
	if not _areas.is_empty(): return true
	if not is_instance_valid(turret): return false
	for projectile in world.projectiles:
		if projectile.source == turret: return true
	for unit in world.summon_units:
		if str(unit.owner) == str(turret.combat.actor_key): return true
	return turret.combat._pending.any(func(event): return event.has("hit") or str(event.get("command", {}).get("type", "")) == "EET_AddSummonUnit")

func finish() -> void:
	_areas.clear()
	if is_instance_valid(turret):
		for projectile in world.projectiles.duplicate():
			if projectile.source != turret: continue
			world.presentation.projectile_ended(turret, projectile.state)
			world._recycle_projectile(projectile)
			world.projectiles.erase(projectile)
		for unit in world.summon_units.duplicate():
			if str(unit.owner) != str(turret.combat.actor_key): continue
			if is_instance_valid(unit.get("visual")): unit.visual.queue_free()
			world.summon_units.erase(unit)
		world._actor_index.erase(str(turret.combat.actor_key))
		turret.queue_free()
		turret = null
	world.fighting = false
	world.room_stage = "open"
	world.sync_room_gates()

func snapshot() -> Dictionary:
	if campaign == null: return {}
	return {"wave": _wave, "center": DungeonProjectile._array(center), "areas": _areas.duplicate(true), "turret": turret.combat.snapshot() if is_instance_valid(turret) else {}}

func restore(saved: Dictionary) -> void:
	if campaign == null or saved.is_empty(): return
	_wave = int(saved.get("wave", -1))
	center = world.vector(saved.get("center", center))
	_areas = saved.get("areas", []).duplicate(true)
	if not saved.get("turret", {}).is_empty():
		if not is_instance_valid(turret): _create_turret(int(campaign.trial_status().turret_id))
		if is_instance_valid(turret): turret.combat.restore(saved.turret)
