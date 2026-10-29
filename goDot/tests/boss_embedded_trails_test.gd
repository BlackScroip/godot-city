extends SceneTree

const Presentation = preload("res://scripts/presentation/combat_presentation.gd")
const FIRE_TRAIL := "24122501_fx_enemy_feimolong_firewindbuff_trail"
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _command(presentation: Node3D, actor: DungeonActor, names: Array, enabled: bool) -> void:
	presentation.command(actor, {"sequence": actor.combat._cast_sequence, "command": {"type": "EET_SetGameObjectActive", "raw": JSON.stringify({"gameobjectNames": names, "booleanToSet": enabled})}})

func _stage(presentation: Node3D, actor: DungeonActor, action_id: String) -> void:
	var action: Dictionary = actor.combat._action(str(actor.combat.enemy.group), action_id)
	var commands: Array = action.events.filter(func(row): return row.get("enabled", false) and row.get("type", "") == "EET_SetGameObjectActive")
	commands.sort_custom(func(a, b): return float(a.time) < float(b.time))
	check(not commands.is_empty(), action_id + " has source phase commands")
	for command in commands: presentation.command(actor, {"sequence": actor.combat._cast_sequence, "command": command})

func _flush(presentation: Node3D) -> void:
	var frames := 0
	while presentation.has_pending_preparation() or not presentation._boss_embedded_queue.is_empty():
		presentation._process(0.016)
		frames += 1
		if frames > 10000:
			check(false, "Preparation finishes")
			return
		await process_frame

func _drain_queue(presentation: Node3D) -> void:
	var steps := 0
	while not presentation._boss_embedded_queue.is_empty() and steps < 100:
		presentation._process_boss_embedded_queue()
		steps += 1
	check(presentation._boss_embedded_queue.is_empty(), "Embedded queue drains")

func _trail_entries(presentation: Node3D, actor: DungeonActor) -> Array:
	var result: Array = []
	for key in presentation._boss_embedded_live.get(actor.get_instance_id(), {}):
		var effect: Dictionary = presentation._boss_embedded_live[actor.get_instance_id()][key]
		if not presentation.effect_definition(key).get("trails", []).is_empty(): result.append({"key": key, "effect": effect})
	return result

func _trails(entries: Array) -> Array:
	var result: Array = []
	for entry in entries:
		for trail in entry.effect.get("active_boss_trails", []): result.append(trail)
	return result

func _move(presentation: Node3D, actor: DungeonActor, frames: int) -> void:
	for index in frames:
		actor.position.x += 0.3
		presentation._process(0.001)

func _run() -> void:
	var presentation := Presentation.new()
	root.add_child(presentation)
	presentation.configure({})
	presentation.set_process(false)
	presentation.audio_enabled = false
	presentation.effects_density = 2
	var dragon := DungeonActor.new()
	dragon.actor_id = 53001
	dragon.combat = DungeonCombat.new()
	dragon.combat.configure_enemy(53001)
	root.add_child(dragon)
	dragon.set_physics_process(false)
	dragon.set_visual("res://assets/enemies/enemy_53001.glb")
	check(dragon.visual_loaded, "Real flying dragon model loads")
	presentation.prepare_combat([dragon.combat])
	presentation.register_boss_embedded(dragon)
	await _flush(presentation)
	check(_trail_entries(presentation, dragon).is_empty(), "Dragon trails are inactive at spawn")
	_stage(presentation, dragon, "roar1")
	_drain_queue(presentation)
	var entries := _trail_entries(presentation, dragon)
	var trails := _trails(entries)
	check(entries.size() == 6 and trails.size() == 6, "Fire/wind stage activates all six source wing trails")
	var source_ids: Dictionary = {}
	for entry in entries:
		var effect: Dictionary = entry.effect
		var definition: Dictionary = presentation.effect_definition(entry.key)
		var live: Array = effect.get("active_boss_trails", [])
		check(live.size() == 1, "Each wing root owns one trail helper")
		if live.size() != 1: continue
		var trail = live[0]
		var source: Dictionary = definition.trails[0]
		source_ids[trail._source_id] = true
		check(trail._source_id == str(source.source_file_id) and trail._owner == effect.root and trail.node.get_parent() == effect.root, "Helper uses its source descriptor and effect root")
		check(effect.follow.get_ref() != null and effect.follow.get_ref() != dragon, "Trail root follows its imported wing anchor")
		check(trail._material.get_shader_parameter("main_texture") is Texture2D and trail._material.get_shader_parameter("source_fade") is Texture2D, "Source trail and fade textures load")
		check(is_equal_approx(trail._duration, 0.2) and is_equal_approx(trail._width_multiplier, 1.5), "Source lifetime and width are applied")
		check(is_equal_approx(trail._widths[0], 1.0) and is_equal_approx(trail._widths[-1], 0.525974), "Source width curve is baked")
		check(is_zero_approx(trail._colors[0].a) and is_zero_approx(trail._colors[-1].a) and trail._colors[32].a > 0.0, "Source alpha gradient is baked")
		check(trail._points.is_empty() and not trail.node.visible, "New helper starts without stale geometry")
	check(source_ids.size() == 6, "Six distinct source trail components are represented")
	check(presentation.unresolved_anchors.is_empty(), "Every trail wing anchor resolves")

	presentation.apply_settings({"effects_density": 2, "effects_opacity": 37})
	for trail in trails: check(is_equal_approx(trail.node.transparency, 0.63), "Settings opacity reaches active trail")
	presentation.apply_settings({"effects_density": 2, "effects_opacity": 100})
	_move(presentation, dragon, 35)
	for entry in entries:
		var effect: Dictionary = entry.effect
		for trail in effect.get("active_boss_trails", []):
			check(trail._points.size() == 24 and trail._max_points == 24, "Full-quality trail sample count is bounded")
			check(trail.node.visible and trail._mesh.get_surface_count() == 1, "Movement produces visible trail geometry")
			check(trail._points.back().position.is_equal_approx((effect.root.global_transform * trail._source_transform).origin), "Latest sample follows the source anchor transform")
			check(is_zero_approx(trail.node.transparency), "Full opacity is restored")

	var times: Array = []
	var points: Array = []
	for trail in trails:
		times.append(trail._time)
		points.append(trail._points.duplicate(true))
	presentation.suspended = true
	dragon.position.x += 3.0
	presentation._process(1.0)
	for index in trails.size():
		check(is_equal_approx(trails[index]._time, times[index]) and trails[index]._points == points[index] and trails[index].node.visible, "Pause preserves trail time, samples and visibility")
	presentation.suspended = false
	presentation._process(0.001)
	presentation._process(0.3)
	for trail in trails:
		check(trail._points.size() == 1 and not trail.node.visible and trail._mesh.get_surface_count() == 0, "Stationary trail expires after its source lifetime")

	_move(presentation, dragon, 2)
	_command(presentation, dragon, [FIRE_TRAIL], false)
	check(_trail_entries(presentation, dragon).is_empty(), "Phase disable removes all six trail roots")
	for trail in trails: check(trail._points.is_empty() and not trail.node.visible, "Disabled trail clears its samples and mesh")
	var recycled: Dictionary = presentation.pool.back()
	var recycled_root: Node3D = recycled.root
	check(not recycled.get("boss_trail_pool", []).is_empty(), "A disabled trail effect is retained for reuse")
	presentation.emit_effect(dragon, "trail_pool_fixture_missing", dragon.position, Vector3.ONE, 1.0)
	var ordinary: Dictionary = presentation.active.back()
	check(ordinary.root == recycled_root and not ordinary.has("active_boss_trails"), "Ordinary effect reuses a trail root without activating trails")
	_move(presentation, dragon, 2)
	for trail in ordinary.get("boss_trail_pool", []): check(not trail.node.visible and trail._points.is_empty(), "Ordinary effect never shows recycled trail geometry")
	presentation._recycle(presentation.active.find(ordinary))
	var previous_ids: Dictionary = {}
	for trail in trails: previous_ids[trail.get_instance_id()] = true
	_command(presentation, dragon, [FIRE_TRAIL], true)
	_drain_queue(presentation)
	entries = _trail_entries(presentation, dragon)
	trails = _trails(entries)
	var reused := 0
	for trail in trails:
		if previous_ids.has(trail.get_instance_id()): reused += 1
		check(trail._points.is_empty() and not trail.node.visible, "Reactivated helper is reset before first update")
	check(trails.size() == 6 and reused > 0, "Reactivation reuses helpers for all six source roots")
	_move(presentation, dragon, 2)
	dragon.dead = true
	presentation.sync_buffs([dragon])
	check(not presentation._boss_embedded_live.has(dragon.get_instance_id()), "Boss death releases embedded ownership")
	for trail in trails: check(trail._points.is_empty() and not trail.node.visible, "Boss death clears active trail geometry")
	dragon.dead = false
	presentation.register_boss_embedded(dragon)
	_drain_queue(presentation)
	trails = _trails(_trail_entries(presentation, dragon))
	check(trails.size() == 6, "Phase state restores six trails after re-registration")
	_move(presentation, dragon, 2)
	presentation.clear()
	check(presentation.active.is_empty() and presentation._boss_embedded_live.is_empty(), "Room clear releases all active embedded effects")
	for trail in trails: check(trail._points.is_empty() and not trail.node.visible, "Room clear clears retained trail geometry")

	dragon.combat.custom_properties.erase("_boss_embedded_objects")
	presentation.low_quality = true
	presentation.register_boss_embedded(dragon)
	_command(presentation, dragon, [FIRE_TRAIL], true)
	_drain_queue(presentation)
	trails = _trails(_trail_entries(presentation, dragon))
	check(trails.size() == 6, "Low quality retains the six source trail roots")
	_move(presentation, dragon, 35)
	for trail in trails: check(trail._max_points == 16 and trail._points.size() == 16, "Low-quality trail sample count is bounded")
	presentation.clear()
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "scope": "Recovered flying-dragon embedded trail lifecycle and bounded geometry; not original APK runtime or pixel comparison."}
	print("BOSS_EMBEDDED_TRAILS ", JSON.stringify(report))
	presentation.queue_free()
	dragon.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
