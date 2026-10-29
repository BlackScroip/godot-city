extends SceneTree

const Presentation = preload("res://scripts/presentation/combat_presentation.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _run() -> void:
	var presentation := Presentation.new()
	root.add_child(presentation)
	presentation.configure({})
	presentation.set_process(false)
	presentation.audio_enabled = false
	var wolf := DungeonActor.new()
	wolf.actor_id = 13001
	wolf.combat = DungeonCombat.new()
	wolf.combat.configure_enemy(13001)
	root.add_child(wolf)
	wolf.set_physics_process(false)
	wolf.position = Vector3(3, 0, 5)
	wolf.face_direction(Vector3.RIGHT)
	presentation.prepare_combat([wolf.combat])
	while presentation.has_pending_preparation():
		presentation.prepare_step()
		await process_frame
	var prepared_builds: int = presentation.authored_builds
	for action_id in ["attack", "Attack_EX1", "attack2", "attack3", "attack4_Short", "attack5", "roar"]:
		presentation.action_started(wolf, {"sequence": 1, "action": action_id, "speed": 1.0})
		check(presentation.telegraphs.is_empty(), action_id + " does not add an unshipped warning")
	var action: Dictionary = wolf.combat._action("ActGroup_senlinlangwang", "attack4_Short")
	var command: Dictionary = action.events.filter(func(row): return row.get("enabled", false) and row.get("type", "") == "EET_PlayEffect")[0]
	var definition: Dictionary = DungeonWorld._raw_definition(command).EffectTriggerDef
	var source_copy := definition.duplicate(true)
	await _warning(presentation, wolf, definition, Vector3.INF, Vector3.ZERO)
	check(definition == source_copy, "Casting leaves the imported command unchanged")
	presentation.clear()
	var eruption: Dictionary = wolf.combat._action("ActGroup_senlinlangwang", "attack5")
	for row in eruption.events:
		if row.get("type", "") != "EET_PlayEffect" or not row.get("enabled", false): continue
		var raw := DungeonWorld._raw_definition(row)
		if "attackrange360" in str(raw.get("EffectTriggerDef", {}).get("EffectName", "")):
			await _warning(presentation, wolf, raw.EffectTriggerDef, Vector3(7, 0, -4), Vector3.FORWARD)
	await _projectile_warnings(presentation, wolf)
	check(presentation.authored_builds == prepared_builds, "Wolf source warnings are prepared during loading")
	await _effect_only_projectile(presentation, wolf)
	presentation.clear()
	var claw: Dictionary = action.events.filter(func(row): return row.get("enabled", false) and row.get("type", "") == "EET_PlayEffect" and "claw1" in str(row.get("raw", "")))[0]
	var claw_copy := claw.duplicate(true)
	wolf.combat.add_buff("41300101")
	presentation.command(wolf, {"command": claw, "sequence": wolf.combat._cast_sequence})
	check(presentation.active.size() == 1, "Rage claw retains one original prefab")
	if not presentation.active.is_empty():
		var expected := DungeonWorld.vector(DungeonWorld._raw_definition(claw).EffectTriggerDef.Scale) * 1.1
		check(presentation.active[0].authored.scale.is_equal_approx(expected), "Rage claw applies the APK custom-property scale once")
	check(claw == claw_copy, "Rage scaling does not mutate source action data")
	presentation.clear()
	var ground: Dictionary = wolf.combat._summon_index["41300120"].hit
	var delayed := {"definition": ground, "sequence": wolf.combat._cast_sequence - 1, "summon_id": "41300120"}
	presentation.entity_activated(wolf, delayed, Vector3(6, 0, 4), Vector3.RIGHT)
	presentation._process(0.1)
	check(presentation.active.size() == 1 and presentation.active[0].key == "24042901_fx_enemy_senlinlangwang_roar_eruption", "Delayed ground eruption survives the caster's subsequent action")
	if not presentation.active.is_empty():
		check(presentation.active[0].sequence == -1, "IsLoop does not override source DestoryWhenActionSwitch=false")
		check(is_finite(float(presentation.active[0].duration)), "Original one-shot particle layers have a finite lifetime")
	presentation.clear()
	await _embedded_rage(presentation, wolf)
	# A missing source asset must be observable, never replaced with a generic quad.
	presentation.emit_effect(wolf, "wolf_missing_source_fixture.prefab", Vector3.ZERO)
	check(presentation.active.is_empty(), "Missing wolf media never creates a substitute effect")
	check(presentation.missing.has("wolf_missing_source_fixture"), "Missing wolf media remains diagnosable")
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures,
		"scope": "Wolf 13001 source warning assets, transforms, loading, visibility, cancellation and absence of generic substitutes; Godot runtime verification, not original APK execution."}
	FileAccess.open("res://reports/wolf-boss-apk-effects-test.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t") + "\n")
	print("WOLF_BOSS_APK_EFFECTS ", JSON.stringify(report))
	presentation.clear()
	presentation.queue_free()
	wolf.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _embedded_rage(presentation: Node3D, wolf: DungeonActor) -> void:
	wolf.combat.remove_buff("41300101")
	wolf.set_visual("res://assets/enemies/enemy_13001.glb")
	await process_frame
	presentation.sync_actor_buffs(wolf)
	check(presentation.active.is_empty(), "Original disabled hair and tail remain hidden before rage")
	wolf.combat.add_buff("41300101")
	presentation.sync_actor_buffs(wolf)
	check(presentation.active.size() == 2, "Rage activates both original embedded particle roots")
	for effect in presentation.active:
		check(effect.source_only and effect.authored != null and effect.has("embedded_effect"), "Rage uses recovered embedded particles")
		check(effect.follow.get_ref() is BoneAttachment3D, "Rage particles follow the recovered skeleton bone")
		check(effect.sequence == -1 and effect.clock_sequence == -1, "Persistent rage is independent of action clocks")
		check(not effect.authored.emitters.is_empty(), "Rage root has visible source emitters")
	presentation.sync_actor_buffs(wolf)
	check(presentation.active.size() == 2, "Repeated synchronization does not duplicate rage particles")
	var names: Array = presentation._wolf_embedded.bindings.keys()
	presentation.command(wolf, {"sequence": wolf.combat._cast_sequence, "command": {"type": "EET_SetGameObjectActive", "raw": JSON.stringify({"gameobjectNames": names, "booleanToSet": true})}})
	check(presentation.active.size() == 2, "Roar activation and common buff share the original embedded roots")
	presentation.action_started(wolf, {"sequence": wolf.combat._cast_sequence + 1, "action": "attack", "speed": 1.0})
	check(presentation.active.size() == 2, "Rage particles persist across attacks")
	wolf.position += Vector3(2, 0, -3)
	presentation._process(0.1)
	for effect in presentation.active:
		var anchor: Node3D = effect.follow.get_ref()
		check(effect.root.global_position.is_equal_approx(anchor.to_global(effect.offset)), "Rage particle root follows bone motion")
	wolf.combat.remove_buff("41300101")
	presentation.sync_actor_buffs(wolf)
	check(presentation.active.is_empty(), "Removing rage deactivates both embedded roots")
	check(presentation.unresolved_anchors.is_empty(), "Both rage attachment bones resolve in the shipped model")
	presentation.clear()

func _projectile_warnings(presentation: Node3D, wolf: DungeonActor) -> void:
	for action_id in ["attack2", "attack3"]:
		presentation.clear()
		var action: Dictionary = wolf.combat._action("ActGroup_senlinlangwang", action_id)
		var definitions: Array = action.hits.filter(func(row): return row.get("enabled", false) and "enemyatkrangerectangle_fowardz" in str(row.get("raw", "")).to_lower())
		check(definitions.size() == 1, action_id + " has one source projectile warning definition")
		if definitions.is_empty(): continue
		var definition: Dictionary = definitions[0]
		var source_copy := definition.duplicate(true)
		var raw := DungeonWorld._raw_definition(definition)
		var warning: Dictionary = raw.EntityProperty.EffectTriggerDef
		var points: Array = raw.EmitProperty.PointData
		var origin := Vector3(7, 0, -4)
		var reused: int = presentation.authored_reuses
		for index in points.size():
			var hit := {"definition": definition, "sequence": wolf.combat._cast_sequence, "emit_index": index}
			var transform_data := DungeonProjectile.multipoint_transform(hit, origin, wolf.facing)
			presentation.attack_emitted(wolf, hit, transform_data.position, transform_data.facing)
			check(presentation.active.size() == index + 1, "%s emits warning %d at creation" % [action_id, index])
			if presentation.active.size() != index + 1: continue
			var effect: Dictionary = presentation.active.back()
			var yaw := atan2(transform_data.facing.x, transform_data.facing.z)
			var expected: Vector3 = transform_data.position + Basis(Vector3.UP, yaw) * DungeonWorld.vector(warning.Position)
			check(effect.source_warning and effect.source_only and effect.key == presentation._key(warning.EffectName), "%s warning %d retains its source prefab" % [action_id, index])
			check(effect.root.global_position.is_equal_approx(expected), "%s warning %d uses the emission point and rotation" % [action_id, index])
			check(effect.authored.scale.is_equal_approx(DungeonWorld.vector(warning.Scale)), "%s warning %d retains its source scale" % [action_id, index])
		check(presentation.authored_reuses - reused == points.size(), action_id + " reuses all prewarmed warning instances")
		check(definition == source_copy, action_id + " warning preserves the imported source definition")
	presentation.clear()
	await process_frame

func _effect_only_projectile(presentation: Node3D, wolf: DungeonActor) -> void:
	var action: Dictionary = wolf.combat._action("ActGroup_Chimera", "attack4")
	var definitions: Array = action.hits.filter(func(row): return row.get("enabled", false) and "25030501_fx_enemy_qimeila_attack4_stormwarning" in str(row.get("raw", "")))
	check(not definitions.is_empty(), "Effect-only projectile fixture exists")
	if definitions.is_empty(): return
	var definition: Dictionary = definitions[0]
	var raw := DungeonWorld._raw_definition(definition)
	check(str(raw.EntityProperty.get("ModlePrefab", "")).is_empty(), "Effect-only projectile has no separate source model")
	var state := DungeonProjectile.new()
	state.hit = {"definition": definition}
	state.entity = raw.EntityProperty
	state.motion_type = str(raw.get("MotionAnimatorType", ""))
	state.position = Vector3(1, 0, 2)
	state.lifetime = 2.0
	var visual := Node3D.new()
	root.add_child(visual)
	presentation.attack_emitted(wolf, state.hit, state.position)
	check(presentation.active.is_empty(), "Effect-only projectile does not duplicate its creation visual")
	presentation.projectile_started(wolf, state, visual)
	check(presentation.active.size() == 1 and presentation.active[0].key == presentation._key(raw.EntityProperty.EffectTriggerDef.EffectName), "Effect-only projectile retains one moving source visual")
	presentation.clear()
	visual.queue_free()
	await process_frame

func _warning(presentation: Node3D, wolf: DungeonActor, definition: Dictionary, point: Vector3, facing: Vector3) -> void:
	wolf.combat._cast_sequence = 31
	presentation.trigger(wolf, definition, 31, point, true, true, facing)
	check(presentation.telegraphs.is_empty(), "Wolf warning never uses the procedural telegraph shader")
	check(presentation.active.size() == 1, "Wolf warning emits exactly one packaged prefab")
	if presentation.active.is_empty(): return
	var effect: Dictionary = presentation.active[0]
	check(effect.authored != null and effect.source_only and effect.source_warning, "Wolf warning uses the authored APK renderer")
	check(not effect.mesh.visible and not effect.burst.visible and not effect.sparks.emitting, "Wolf warning has no generic overlays")
	check(effect.important and not effect.authored.emitters.is_empty(), "Packaged warning layers retain combat visibility")
	check(effect.key == presentation._key(definition.EffectName), "Wolf warning keeps the exact source prefab")
	var direction := wolf.facing if facing.is_zero_approx() else facing
	var yaw := atan2(direction.x, direction.z)
	var origin := wolf.position if point == Vector3.INF else point
	check(effect.root.position.is_equal_approx(origin + Basis(Vector3.UP, yaw) * DungeonWorld.vector(definition.Position)), "Source warning position has no synthetic floor or rectangle offset")
	check(effect.authored.scale.is_equal_approx(DungeonWorld.vector(definition.Scale)), "Source warning retains its prefab scale")
	check(effect.root.basis.is_equal_approx(Basis.from_euler(Vector3(0, yaw, 0) + DungeonWorld.vector(definition.Euler) * PI / 180.0)), "Source warning retains entity facing and original Euler angles")
	for emitter in effect.authored.emitters:
		check(emitter.node.mesh != null and emitter.node.material_override is ShaderMaterial, "Warning layer has recovered mesh and material")
	presentation.apply_settings({"effects_density": 0, "effects_opacity": 0, "reduce_player_effects": true})
	check(is_equal_approx(float(effect.settings_opacity), 1.0), "Cosmetic opacity does not hide the source warning")
	presentation.cancel_actor(wolf, 32)
	if definition.get("DestoryWhenActionSwitch", false) or definition.get("IsLoop", false):
		check(presentation.active.is_empty(), "Source action-owned warning cancels on the next action")
	presentation.clear()
	await process_frame
