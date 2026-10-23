extends Node3D

const FEEL = preload("res://assets/feel_settings.tres")
const COLORS = [Color("ffba68"), Color("ff7649"), Color("bf86ff"), Color("ffe05c"), Color("59cbff"), Color("75efba"), Color("fff0a0"), Color("91dfff")]
const HEAVY_ACTIONS = [
	"sword_satk_normal", "sword_satk_normal_ready", "sword_satk_normal_attack", "sword_satk_upgrade", "sword_SmiteDerivative", "sword_SmiteDerivative_Normal",
	"sickle_satk", "sickle_satk_special", "axe_satk_start", "axe_satk_loop", "axe_satk_end", "wand_satk1", "wand_satk2",
	"bow_satk", "bow_fullsatk", "bow_satk0_weapon4", "bow_satk1_weapon4", "bow_fullsatk_weapon4_combine",
	"orb_satk_start", "orb_satk_loop_1", "orb_satk_shoot", "orb_smite_0jp", "lance_satk", "lance_satk_nomal", "lance_satk_nomal2", "lance_satk_special"
]
var suspended := false
var low_quality := false
var audio_enabled := true
var catalog: Dictionary = {}
var media: Dictionary = {}
var active: Array[Dictionary] = []
var pool: Array[Dictionary] = []
var voices: Array[AudioStreamPlayer3D] = []
var sound_queue: Array[Dictionary] = []
var texture_cache: Dictionary = {}
var sound_cache: Dictionary = {}
var missing: Dictionary = {}
var spawned := 0
var impacts := 0
var authored_pool: Dictionary = {}
var _authored_pool_size := 0
var _sound_serial := 0
var _summon_serial := 0
var prewarmed_heavy_sounds: Dictionary = {}
const Telegraph = preload("res://scripts/presentation/attack_telegraph.gd")
var telegraphs: Array[Dictionary] = []

func configure(value: Dictionary) -> void:
	catalog = value
	var path = "res://assets/combat_presentation/catalog.json"
	if FileAccess.file_exists(path): media = JSON.parse_string(FileAccess.get_file_as_string(path))
	for index in FEEL.audio_budget:
		var voice = AudioStreamPlayer3D.new()
		voice.max_distance = 28
		voice.unit_size = 8
		add_child(voice)
		voices.append(voice)
	for index in FEEL.effect_budget: pool.append(_make_effect())
	for key in media.get("texture_sources", {}):
		var texture_path = "res://assets/combat_presentation/" + str(key)
		if ResourceLoader.exists(texture_path): texture_cache[texture_path] = load(texture_path)
	# Decode impact clips before the first contact rather than on its display frame.
	for key in media.get("audio", {}):
		if "hit" not in key and "explos" not in key and "shield" not in key: continue
		for layer in media.audio[key]:
			for clip in layer.get("clips", []):
				if ResourceLoader.exists(str(clip)): sound_cache[str(clip)] = load(str(clip))
	_prewarm_heavy_audio()

func _collect_heavy_audio(value: Variant, sounds: Dictionary, summons: Dictionary) -> void:
	if value is Dictionary:
		for field in value:
			var child: Variant = value[field]
			if field in ["SoundName", "Sound", "VoiceName"] and child is String and not child.is_empty(): sounds[_key(child)] = true
			elif field == "VoiceList" and child is Array:
				for name in child:
					if not str(name).is_empty(): sounds[_key(name)] = true
			elif field == "AddSummonUnitId" and not str(child).is_empty(): summons[str(child)] = true
			_collect_heavy_audio(child, sounds, summons)
	elif value is Array:
		for child in value: _collect_heavy_audio(child, sounds, summons)

func _prewarm_heavy_audio() -> void:
	var source = DungeonCombat.new()
	if not source._load_catalog(null): return
	var sounds: Dictionary = {}
	var pending: Dictionary = {}
	var seen: Dictionary = {}
	for action in source.catalog.get("actions", []):
		var name = str(action.get("key", "")).get_file()
		if name not in HEAVY_ACTIONS: continue
		for event in action.get("events", []) + action.get("hits", []):
			if event.get("enabled", false): _collect_heavy_audio(DungeonWorld._raw_definition(event), sounds, pending)
	while not pending.is_empty():
		var id = str(pending.keys()[0])
		pending.erase(id)
		if seen.has(id): continue
		seen[id] = true
		_collect_heavy_audio(source._summon_index.get(id, {}).get("raw_data", {}), sounds, pending)
	for key in sounds:
		var layers: Array = media.get("audio", {}).get(key, [])
		if layers.is_empty() and catalog.get("audio", {}).has(key): layers = [{"clips": [catalog.audio[key]]}]
		for layer in layers:
			for path in layer.get("clips", []):
				if ResourceLoader.exists(str(path)):
					if not sound_cache.has(path): sound_cache[path] = load(str(path))
					prewarmed_heavy_sounds[key] = true

func _make_effect() -> Dictionary:
	var root = Node3D.new()
	add_child(root)
	var mesh = MeshInstance3D.new()
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var quad = QuadMesh.new()
	quad.size = Vector2.ONE
	mesh.mesh = quad
	mesh.rotation.x = -PI / 2
	var material = StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = false
	mesh.material_override = material
	root.add_child(mesh)
	var burst = MeshInstance3D.new()
	burst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	burst.mesh = quad
	var burst_material = ShaderMaterial.new()
	burst_material.shader = preload("res://scripts/presentation/impact_burst.gdshader")
	burst.material_override = burst_material
	burst.hide()
	root.add_child(burst)
	var sparks = CPUParticles3D.new()
	sparks.emitting = false
	sparks.one_shot = true
	sparks.amount = 12
	sparks.lifetime = 0.3
	sparks.explosiveness = 1.0
	sparks.direction = Vector3.UP
	sparks.spread = 75
	sparks.initial_velocity_min = 1.5
	sparks.initial_velocity_max = 4
	sparks.gravity = Vector3(0, -8, 0)
	sparks.scale_amount_min = 0.025
	sparks.scale_amount_max = 0.06
	var spark_mesh = PrismMesh.new()
	spark_mesh.size = Vector3(0.3, 1.3, 0.12)
	sparks.mesh = spark_mesh
	var spark_material = StandardMaterial3D.new()
	spark_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_material.vertex_color_use_as_albedo = true
	sparks.material_override = spark_material
	root.add_child(sparks)
	root.hide()
	return {"root": root, "mesh": mesh, "burst": burst, "burst_material": burst_material, "material": material, "sparks": sparks, "authored": null}

func color_for(actor: DungeonActor) -> Color:
	return COLORS[clampi(actor.actor_id, 0, 7)] if actor.is_player else Color("ff614f")

func _key(value: Variant) -> String:
	return str(value).get_file().trim_suffix(".prefab").to_lower()

func emit_effect(actor: DungeonActor, name: String, point: Vector3, dimensions := Vector3(2, 1, 2), duration := 0.35, follow: Node3D = null, important := false, sequence := -1, loop := false, priority := false) -> void:
	var budget = FEEL.low_effect_budget if low_quality else FEEL.effect_budget
	if not important and get_viewport().get_camera_3d() and point.distance_to(get_viewport().get_camera_3d().global_position) > 48: return
	if active.size() >= budget or pool.is_empty():
		if not important and not priority: return
		var victim = -1
		for i in active.size():
			if not active[i].important and (important or not active[i].get("priority", false)):
				victim = i
				break
		if victim < 0: return
		_recycle(victim)
	var entry: Dictionary = pool.pop_back()
	var key = _key(name)
	var textures: Array = media.get("effects", {}).get(key, {}).get("textures", [])
	if not key.is_empty() and not media.get("effects", {}).has(key): missing[key] = true
	var mat: StandardMaterial3D = entry.material
	mat.albedo_texture = texture_cache.get(textures[0]) if not textures.is_empty() else null
	mat.albedo_color = color_for(actor)
	entry.mesh.visible = mat.albedo_texture != null
	entry.burst.hide()
	entry.root.position = point
	entry.root.rotation = Vector3(0, atan2(actor.facing.x, actor.facing.z), 0)
	entry.root.scale = Vector3.ONE
	entry.mesh.scale = Vector3(maxf(0.2, dimensions.x), maxf(0.2, dimensions.z), 1)
	entry.root.show()
	entry.merge({"actor": weakref(actor), "sequence": sequence, "clock_sequence": -1, "playback_speed": 1.0, "detach_after": 0.0, "summon_token": 0, "age": 0.0, "duration": maxf(0.05, duration), "follow": weakref(follow) if follow else null, "offset": follow.to_local(point) if follow else Vector3.ZERO, "follow_rotation": false, "rotation_offset": Basis.IDENTITY, "important": important, "priority": priority, "detached": priority, "loop": loop, "key": key, "color": color_for(actor), "body_burst": false}, true)
	entry.sparks.emitting = false
	entry.sparks.direction = Vector3.UP
	entry.sparks.spread = 75
	entry.sparks.color = color_for(actor)
	var definition: Dictionary = media.get("effects", {}).get(key, {})
	if not definition.get("layers", []).is_empty():
		var cache_key = key + (":low" if low_quality else ":full")
		var authored: Node3D
		if not authored_pool.get(cache_key, []).is_empty():
			authored = authored_pool[cache_key].pop_back()
			_authored_pool_size -= 1
		else:
			authored = preload("res://scripts/presentation/authored_effect.gd").new()
			authored.configure(definition, low_quality, texture_cache, FEEL.effect_emitter_suppressions.get(key, []))
		entry.root.add_child(authored)
		authored.transform = Transform3D.IDENTITY
		authored.set_visual_gain(FEEL.sword_light_gain if _sword_slash(key) else FEEL.skill_light_gain, _sword_slash(key))
		authored.restart()
		entry.authored = authored
		entry["cache_key"] = cache_key
		entry.mesh.hide()
		if not loop and follow == null: entry.duration = maxf(float(entry.duration), minf(authored.lifetime, 4.0))
	active.append(entry)
	spawned += 1

func _sword_slash(key: String) -> bool:
	return key.begins_with("23090401_fx_sword_atk_slash")

func _contact_burst(actor: DungeonActor, point: Vector3, profile: Dictionary, target: DungeonActor = null, seed_value := 0.0) -> void:
	var category = str(profile.category)
	var duration = 0.15 if category == "continuous" else 0.28 if category in ["heavy", "explosion"] else 0.2
	var before = spawned
	emit_effect(actor, "", point, Vector3.ONE, duration, target, false, -1, false, true)
	if spawned == before: return
	var effect = active.back()
	effect.body_burst = true
	effect.burst.show()
	var scale_value = clampf(float(profile.scale), 0.6, 1.8)
	effect.burst.scale = Vector3.ONE * scale_value * (1.65 if category == "explosion" else 1.3)
	var variant = 3.0 if category == "shield" else 4.0 if category == "continuous" else 2.0 if category == "explosion" else 1.0 if profile.get("ranged", false) else 0.0
	effect.burst_material.set_shader_parameter("phase", 0.0)
	effect.burst_material.set_shader_parameter("variant", variant)
	effect.burst_material.set_shader_parameter("seed_value", seed_value)
	var accent = Color("c73c20") if category in ["heavy", "explosion"] else Color("d57d26")
	if variant == 1.0: accent = color_for(actor).darkened(0.2)
	if category == "shield": accent = Color("6ac7e5")
	effect.burst_material.set_shader_parameter("accent", accent)
	effect.burst_material.set_shader_parameter("strength", 0.75 if low_quality else 1.0)
	if not low_quality and category in ["heavy", "explosion"]:
		effect.sparks.amount = 10 if category == "heavy" else 16
		effect.sparks.direction = Vector3.UP if not target else (target.position - actor.position + Vector3.UP * 0.6).normalized()
		effect.sparks.spread = 45 if category == "heavy" else 110
		effect.sparks.color = Color("e9a447")
		effect.sparks.restart()
		effect.sparks.emitting = true

func _anchor(actor: DungeonActor, definition: Dictionary) -> Node3D:
	var dummy: Dictionary = definition.get("DummyData", {})
	var name = str(dummy.get("CustomDummyName", ""))
	if name.is_empty(): name = str(dummy.get("DummyType", ""))
	if "hand" in name.to_lower() or "weapon" in name.to_lower():
		if is_instance_valid(actor.weapon): return actor.weapon
	if actor.visual:
		var node = actor.visual.find_child(name, true, false)
		if node is Node3D: return node
	return actor

func trigger(actor: DungeonActor, definition: Dictionary, sequence := -1, point := Vector3.INF, use_action_clock := true) -> void:
	var name = str(definition.get("EffectName", ""))
	if name.is_empty(): return
	if not actor.is_player and "enemyatkrange" in name.to_lower():
		_authored_telegraph(actor, definition, sequence, point)
		return
	var anchor = _anchor(actor, definition)
	var follows = str(definition.get("DummyType", "")) in ["EEDT_DummyChild", "EEDT_DummyPosFollow_WithoutRotate"]
	var offset = DungeonWorld.vector(definition.get("Position", {}))
	if _sword_slash(_key(name)): offset.z += 0.55
	var location = anchor.global_position + Basis(Vector3.UP, atan2(actor.facing.x, actor.facing.z)) * offset if point == Vector3.INF else point + offset
	location.y += 0.08
	var dimensions = DungeonWorld.vector(definition.get("Scale", {}))
	if dimensions.length_squared() < 0.01: dimensions = Vector3.ONE
	var duration = float(definition.get("DelayTimeToDestroy", 0)) / 1000.0
	var loop = bool(definition.get("IsLoop", false))
	if duration <= 0: duration = maxf(actor.action_time, 0.3) if loop else 0.45
	var playback_speed = maxf(0.1, float(definition.get("EffectSpeed", 1)))
	duration /= playback_speed
	var owned = sequence if loop or definition.get("DestoryWhenActionSwitch", false) else -1
	var emitted_before = spawned
	emit_effect(actor, name, location, dimensions, duration, anchor if follows else null, false, owned, loop)
	if spawned > emitted_before:
		active.back().clock_sequence = sequence if use_action_clock and definition.get("SpeedScaleByOwnerActionSpeed", true) else -1
		active.back().playback_speed = playback_speed
		active.back().detach_after = maxf(0, float(definition.get("DelayTimeToWorldPos", 0))) / 1000.0
		if not loop and float(definition.get("DelayTimeToDestroy", 0)) <= 0 and active.back().authored:
			active.back().duration = maxf(0.05, minf(active.back().authored.lifetime, 4.0) / playback_speed)
		active.back().root.rotation += DungeonWorld.vector(definition.get("Euler", {})) * PI / 180.0
		if _sword_slash(_key(name)): active.back().root.rotate_y(PI)
		if str(definition.get("DummyType", "")) == "EEDT_DummyChild":
			active.back().follow_rotation = true
			active.back().rotation_offset = anchor.global_basis.inverse() * active.back().root.global_basis
		if active.back().authored: active.back().authored.scale = dimensions
	play_sound(str(definition.get("InitSoundDef", {}).get("SoundName", "")), location, actor, sequence)

func action_started(actor: DungeonActor, event: Dictionary) -> void:
	cancel_actor(actor, int(event.sequence))
	if not actor.is_player:
		var definition = actor.combat._action(str(actor.combat.enemy.group), str(event.action))
		var authored: Array = definition.get("events", []).filter(func(command): return command.get("enabled", false) and "enemyatkrange" in str(command.get("raw", "")).to_lower())
		var selected: Array = authored.filter(func(command): return actor.combat._conditions(command.get("conditions", []), bool(command.get("all", true))))
		# Some normal attacks only authored a warning for their empowered variant.
		if selected.is_empty() and not authored.is_empty(): selected = [authored[0]]
		for command_data in selected:
			var raw = DungeonWorld._raw_definition(command_data)
			_authored_telegraph(actor, raw.get("EffectTriggerDef", raw), int(event.sequence), Vector3.INF, float(command_data.get("time", 0)) / maxf(0.01, float(event.get("speed", 1))))
		if authored.is_empty():
			for hit in definition.get("hits", []):
				if not hit.get("enabled", false) or float(hit.get("time", 0)) <= 0.08: continue
				var raw = DungeonWorld._raw_definition(hit)
				if raw.get("EntityType", "") == "EET_Physical" or hit.get("projectile", false): continue
				var size = Vector2(float(hit.get("width", 1)), float(hit.get("length", 1)))
				var shape = 1 if hit.get("shape", "Cube") == "Sphere" else 0
				var degrees = 360.0
				if raw.get("EntityType", "") == "EET_FrameFan":
					shape = 2
					degrees = float(raw.get("EntityProperty", {}).get("Degree", 360))
					size = Vector2.ONE * float(raw.get("EntityProperty", {}).get("Radius", maxf(size.x, size.y) * 0.5)) * 2.0
				elif shape == 1: size = Vector2.ONE * maxf(size.x, size.y)
				_add_telegraph(actor, int(event.sequence), size, shape, degrees, Vector3(0, 0, float(hit.get("offset", 0))), 0.0, float(hit.time) / maxf(0.01, float(event.get("speed", 1))))
	for effect in active:
		if effect.actor.get_ref() == actor and effect.sequence == int(event.sequence): effect.clock_sequence = int(event.sequence)

func _authored_telegraph(actor: DungeonActor, definition: Dictionary, sequence: int, point: Vector3, start := -1.0) -> void:
	var key = _key(str(definition.EffectName))
	if start < 0 and telegraphs.any(func(entry): return entry.actor.get_ref() == actor and entry.sequence == sequence and entry.get("key", "") == key): return
	var scale_value = DungeonWorld.vector(definition.get("Scale", {})).abs()
	if scale_value.is_zero_approx(): scale_value = Vector3.ONE
	var rectangle = "rectangle" in key
	var forward_z = "forwardz" in key or "fowardz" in key
	# Recovered warning prefabs use a five-unit base; forward-Z rectangles scale it by 0.2.
	var size = Vector2(scale_value.x, scale_value.z) * (1.0 if rectangle and forward_z else 5.0)
	var shape = 0 if rectangle else 1
	var degrees = 360.0
	for angle in [90, 120, 150]:
		if str(angle) in key:
			shape = 2
			degrees = float(angle)
	if not rectangle: size = Vector2.ONE * size.x
	var offset = DungeonWorld.vector(definition.get("Position", {}))
	var yaw = deg_to_rad(float(definition.get("Euler", {}).get("y", 0))) + (0.0 if forward_z else PI)
	if rectangle: offset += Basis(Vector3.UP, yaw) * Vector3(0, 0, size.y * 0.5)
	var speed = maxf(0.01, float(actor.combat.custom_properties.get("_feel_action_speed", 1)))
	var duration = 1.0 / maxf(0.01, float(definition.get("EffectSpeed", 1)))
	if float(definition.get("DelayTimeToDestroy", 0)) > 0: duration = float(definition.DelayTimeToDestroy) / 1000.0
	_add_telegraph(actor, sequence, size, shape, degrees, offset, yaw, duration / speed, point, start)
	telegraphs.back()["key"] = key
	_place_telegraph(telegraphs.back(), actor)

func _add_telegraph(actor: DungeonActor, sequence: int, size: Vector2, shape: int, degrees: float, offset: Vector3, yaw: float, duration: float, point := Vector3.INF, start := -1.0) -> void:
	var node = Telegraph.new()
	node.configure(size, shape, degrees)
	add_child(node)
	var entry = {"node": node, "actor": weakref(actor), "sequence": sequence, "start": float(actor.combat.action_elapsed) if start < 0 else start, "duration": maxf(0.01, duration), "offset": offset, "yaw": yaw, "point": point}
	telegraphs.append(entry)
	_place_telegraph(entry, actor)

func _place_telegraph(entry: Dictionary, actor: DungeonActor) -> void:
	entry.node.visible = float(actor.combat.action_elapsed) >= float(entry.start)
	if entry.node.visible: actor.lock_telegraph_aim(int(entry.sequence))
	var facing = Basis(Vector3.UP, atan2(actor.facing.x, actor.facing.z))
	entry.node.position = (actor.position if entry.point == Vector3.INF else entry.point) + facing * entry.offset + Vector3.UP * 0.12
	entry.node.rotation.y = atan2(actor.facing.x, actor.facing.z) + float(entry.yaw)
	entry.node.set_progress((float(actor.combat.action_elapsed) - float(entry.start)) / float(entry.duration))

func _remove_telegraph(index: int) -> void:
	telegraphs[index].node.hide()
	telegraphs[index].node.queue_free()
	telegraphs.remove_at(index)

func command(actor: DungeonActor, event: Dictionary) -> void:
	var command_data: Dictionary = event.command
	var raw = DungeonWorld._raw_definition(command_data)
	match str(command_data.get("type", "")):
		"EET_PlayEffect": trigger(actor, raw.get("EffectTriggerDef", raw), int(event.sequence), Vector3.INF, not raw.get("IgnoreActionSpeed", false))
		"EET_StopEffect":
			var key = _key(raw.get("EffectName", raw.get("EffectId", "")))
			for i in range(active.size() - 1, -1, -1):
				if active[i].actor.get_ref() == actor and (key.is_empty() or active[i].key == key): _recycle(i)
		"EET_PlaySound": play_sound(str(raw.get("SoundName", "")), actor.position, actor, int(event.sequence))
		"EET_PlayVoice": play_sound(str(raw.get("VoiceName", "")), actor.position, actor, int(event.sequence))

func attack_emitted(actor: DungeonActor, hit: Dictionary, origin: Vector3) -> void:
	var definition: Dictionary = hit.get("definition", {})
	var raw = DungeonWorld._raw_definition(definition)
	var entity: Dictionary = raw.get("EntityProperty", {})
	var effect: Dictionary = entity.get("EffectTriggerDef", {})
	var emitted_before = spawned
	var attached = str(raw.get("MotionAnimatorType", "")) in ["EMAT_FollowOwner", "EMAT_RotateOwner"]
	if not str(effect.get("EffectName", "")).is_empty() and (raw.get("EntityType", "") != "EET_Physical" or attached): trigger(actor, effect, int(hit.get("sequence", -1)), origin)
	if spawned > emitted_before:
		if preload("res://scripts/presentation/impact_profiles.gd").ranged(hit): active.back().clock_sequence = -1
	play_sound(str(entity.get("CreateSound", {}).get("SoundName", "")), origin, actor, int(hit.get("sequence", -1)))

func impact(source: DungeonActor, target: DungeonActor, hit: Dictionary) -> void:
	impacts += 1
	var position = target.impact_anchor(DungeonWorld.vector(hit.get("impact_position", DungeonProjectile._array(target.position + Vector3.UP * 0.65))))
	var camera = get_viewport().get_camera_3d()
	if camera: position += (camera.global_position - position).normalized() * clampf(target.impact_bounds.size.z * 0.25, 0.22, 0.6)
	var profile: Dictionary = hit.get("profile", preload("res://scripts/presentation/impact_profiles.gd").resolve(hit, source.combat))
	var category = str(profile.category)
	if category == "continuous" and target.hurt_timer > 0: return
	_contact_burst(source, position, profile, target, float(impacts % 11))
	if category == "shield":
		play_sound("audio_fx_swordhit_body_02", position, source, -1, 0.55, 1.15, true)
		return
	var sounded := false
	for feedback in DungeonWorld._raw_definition(hit.get("definition", {})).get("FeedbackList", []):
		if feedback.get("FeedbackType", "") == "EHT_HitEffect":
			var before = spawned
			emit_effect(source, str(feedback.get("Effect", "")), position, Vector3.ONE * float(profile.scale) * 0.7, 0.24, target, false, -1, false, true)
			if spawned > before:
				active.back().root.rotation += DungeonWorld.vector(feedback.get("EffectOffsetRotate", {})) * PI / 180.0
				if active.back().authored: active.back().authored.scale = Vector3.ONE * float(profile.scale) * 0.7
		elif feedback.get("FeedbackType", "") == "EHT_HitSound":
			var name = str(feedback.get("HitSoundDef", {}).get("SoundName", ""))
			if not name.is_empty():
				play_sound(name, position, source, -1, float(profile.gain), 0.94 if category == "heavy" else 1.0, true)
				sounded = true
	if not sounded: play_sound("audio_sound_axe_hit" if category == "heavy" else "audio_fx_swordhit_body_01", position, source, -1, float(profile.gain), 0.94 if category == "heavy" else 1.0, true)
	if category == "heavy":
		play_sound("audio_monster_rockexplosion", position, source, -1, 0.12, 0.75, true)

func explosion(source: DungeonActor, point: Vector3, profile: Dictionary) -> void:
	_contact_burst(source, point + Vector3.UP * 0.8, profile, null, float(impacts % 11))
	play_sound("audio_monster_rockexplosion", point, source, -1, 0.6, 0.86, true)

func projectile_started(actor: DungeonActor, state: DungeonProjectile, visual: Node3D) -> void:
	var definition: Dictionary = state.entity.get("EffectTriggerDef", {})
	var name = str(state.entity.get("ModlePrefab", definition.get("EffectName", "")))
	if name.is_empty(): name = str(definition.get("EffectName", ""))
	# Attached hitboxes already emitted their action-owned slash at the actor anchor.
	if state.motion_type in ["EMAT_FollowOwner", "EMAT_RotateOwner"] and str(state.entity.get("ModlePrefab", "")).is_empty(): return
	emit_effect(actor, name, state.position, Vector3.ONE * clampf(state.radius * 2, 0.6, 3), state.lifetime, visual, false, -1, true)

func projectile_ended(actor: DungeonActor, state: DungeonProjectile) -> void:
	var name = str(state.entity.get("EntityEndEffect", ""))
	emit_effect(actor, name, state.position, Vector3.ONE * clampf(state.radius * 2, 0.8, 4), 0.24)
	play_sound(str(state.entity.get("EntityEndSoundDef", {}).get("SoundName", state.entity.get("EntityEndSound", ""))), state.position, actor)

func summon_started(actor: DungeonActor, raw: Dictionary, point: Vector3, facing := Vector3.ZERO) -> int:
	if not raw.get("PrefabIsEffect", false) or str(raw.get("Prefab", "")).is_empty(): return 0
	var dimensions = DungeonWorld.vector(raw.get("PrefabScale", {}))
	if dimensions.is_zero_approx(): dimensions = Vector3.ONE
	var before = spawned
	emit_effect(actor, str(raw.Prefab), point, dimensions, 1.0, null, false, -1, true, true)
	if spawned == before: return 0
	_summon_serial += 1
	var entry: Dictionary = active.back()
	entry.summon_token = _summon_serial
	entry.detached = true
	entry.duration = INF
	if entry.authored: entry.authored.scale = dimensions
	summon_updated(_summon_serial, point, actor.facing if facing.is_zero_approx() else facing)
	return _summon_serial

func _summon_effect_index(token: int) -> int:
	if token <= 0: return -1
	for index in active.size():
		if int(active[index].get("summon_token", 0)) == token: return index
	return -1

func summon_updated(token: int, point: Vector3, facing := Vector3.ZERO) -> void:
	var index = _summon_effect_index(token)
	if index < 0: return
	active[index].root.global_position = point
	if not facing.is_zero_approx(): active[index].root.global_rotation = Vector3(0, atan2(facing.x, facing.z), 0)

func summon_ended(token: int) -> void:
	var index = _summon_effect_index(token)
	if index >= 0: _recycle(index)

func buff_effect(actor: DungeonActor, event: Dictionary) -> void:
	var raw: Dictionary = event.get("definition", {})
	var emitted_before = spawned
	trigger(actor, raw.get("EffectTriggerDef", raw), actor.combat._cast_sequence)
	if spawned > emitted_before: active.back().clock_sequence = -1

func play_sound(name: String, point: Vector3, actor: DungeonActor, sequence := -1, gain := 1.0, pitch := 1.0, priority := false) -> void:
	if name.is_empty() or not audio_enabled: return
	var key = _key(name)
	var layers: Array = media.get("audio", {}).get(key, [])
	if layers.is_empty():
		var path = str(catalog.get("audio", {}).get(name.trim_suffix(".prefab"), ""))
		if path.is_empty():
			missing["audio:" + key] = true
			return
		layers = [{"clips": [path]}]
	for layer in layers.slice(0, 3):
		if sound_queue.size() >= FEEL.audio_budget * 2:
			if not priority: break
			var victim = -1
			for index in sound_queue.size():
				if not sound_queue[index].get("priority", false):
					victim = index
					break
			if victim < 0: break
			sound_queue.remove_at(victim)
		_sound_serial += 1
		var variation = 1.0 + (float((_sound_serial * 17) % 7) - 3) * 0.008 if priority else 1.0
		sound_queue.append({"delay": float(layer.get("delay", 0)), "layer": layer, "point": point, "actor": weakref(actor), "sequence": sequence, "gain": gain, "pitch": pitch * variation, "priority": priority, "clip": _sound_serial % maxi(1, layer.get("clips", []).size())})

func _process(delta: float) -> void:
	for voice in voices: voice.stream_paused = suspended or not audio_enabled
	for effect in active:
		var rate = _effect_clock_rate(effect)
		effect.sparks.speed_scale = 0 if suspended else rate
		var particle_rate = rate * float(effect.get("playback_speed", 1))
		if effect.authored: effect.authored.advance(delta * particle_rate, suspended or particle_rate <= 0, particle_rate)
	if suspended: return
	for i in range(telegraphs.size() - 1, -1, -1):
		var entry = telegraphs[i]
		var actor = entry.actor.get_ref()
		if actor and actor.dead: actor.clear_telegraph_aim()
		if not actor or actor.dead or actor.combat._cast_sequence != entry.sequence or float(actor.combat.action_elapsed) >= float(entry.start) + float(entry.duration):
			_remove_telegraph(i)
		else: _place_telegraph(entry, actor)
	for i in range(active.size() - 1, -1, -1):
		var effect = active[i]
		var actor = effect.actor.get_ref()
		if (not actor or actor.dead) and not effect.get("detached", false) or (actor and effect.sequence >= 0 and effect.sequence != actor.combat._cast_sequence):
			_recycle(i)
			continue
		effect.age += delta * _effect_clock_rate(effect)
		if effect.age >= effect.duration and int(effect.get("summon_token", 0)) == 0:
			_recycle(i)
			continue
		if effect.follow:
			var anchor = effect.follow.get_ref()
			if anchor:
				effect.root.global_position = anchor.to_global(effect.offset)
				if effect.follow_rotation: effect.root.global_basis = anchor.global_basis * effect.rotation_offset
				if float(effect.get("detach_after", 0)) > 0 and effect.age >= float(effect.detach_after):
					effect.follow = null
					effect.follow_rotation = false
			else:
				_recycle(i)
				continue
		var fraction = effect.age / effect.duration
		if effect.body_burst: effect.burst_material.set_shader_parameter("phase", fraction)
		var color: Color = effect.color
		color.a = 0.65 if effect.important else (0.8 + sin(effect.age * 18) * 0.2) if effect.loop else 1.0 - fraction
		effect.material.albedo_color = color
		if not effect.authored and not effect.body_burst and not effect.important and not effect.loop: effect.root.scale = Vector3.ONE * (1.0 + fraction * 0.35)
	sound_queue.sort_custom(func(a, b): return not bool(a.get("priority", false)) and bool(b.get("priority", false)))
	for i in range(sound_queue.size() - 1, -1, -1):
		var entry = sound_queue[i]
		var actor = entry.actor.get_ref()
		if (not actor or actor.dead) and not entry.get("priority", false) or not audio_enabled or (actor and entry.sequence >= 0 and actor.combat._cast_sequence != entry.sequence):
			sound_queue.remove_at(i)
			continue
		entry.delay -= delta
		if entry.delay > 0: continue
		var selected: AudioStreamPlayer3D
		for voice in voices:
			if not voice.playing:
				selected = voice
				break
		if not selected and entry.get("priority", false):
			for voice in voices:
				if not voice.get_meta("impact", false):
					selected = voice
					selected.stop()
					break
		if selected and not entry.layer.get("clips", []).is_empty():
			var voice = selected
			var path = str(entry.layer.clips[int(entry.get("clip", 0))])
			if not sound_cache.has(path) and ResourceLoader.exists(path): sound_cache[path] = load(path)
			voice.stream = sound_cache.get(path)
			voice.position = entry.point
			voice.pitch_scale = clampf(float(entry.layer.get("pitch", 1)) * float(entry.get("pitch", 1)), 0.2, 3)
			voice.volume_db = linear_to_db(maxf(0.001, float(entry.layer.get("volume", 1)) * 0.65 * float(entry.get("gain", 1))))
			voice.set_meta("impact", bool(entry.get("priority", false)))
			if voice.stream: voice.play()
		sound_queue.remove_at(i)

func _effect_clock_rate(effect: Dictionary) -> float:
	var actor = effect.actor.get_ref()
	if actor and int(effect.get("clock_sequence", -1)) >= 0 and int(effect.clock_sequence) == actor.combat._cast_sequence and actor.combat.busy > 0 and actor.combat.action_tick_delta > 0:
		return maxf(0.0, actor.combat.action_step / actor.combat.action_tick_delta)
	return 1.0

func _recycle(index: int) -> void:
	var effect = active[index]
	if effect.authored:
		var authored = effect.authored
		authored.stop()
		effect.root.remove_child(authored)
		if _authored_pool_size < FEEL.effect_budget:
			if not authored_pool.has(effect.cache_key): authored_pool[effect.cache_key] = []
			authored_pool[effect.cache_key].append(authored)
			_authored_pool_size += 1
		else: authored.queue_free()
		effect.authored = null
	effect.sparks.emitting = false
	effect.root.hide()
	pool.append(effect)
	active.remove_at(index)

func cancel_actor(actor: DungeonActor, keep_sequence := -2) -> void:
	if actor._telegraph_sequence != keep_sequence: actor.clear_telegraph_aim()
	for i in range(telegraphs.size() - 1, -1, -1):
		if telegraphs[i].actor.get_ref() == actor and telegraphs[i].sequence != keep_sequence: _remove_telegraph(i)
	for i in range(active.size() - 1, -1, -1):
		var entry = active[i]
		if not entry.get("detached", false) and entry.actor.get_ref() == actor and (keep_sequence == -2 or (entry.sequence >= 0 and entry.sequence != keep_sequence)): _recycle(i)

func clear() -> void:
	for entry in telegraphs:
		var actor = entry.actor.get_ref()
		if actor: actor.clear_telegraph_aim()
	while not telegraphs.is_empty(): _remove_telegraph(telegraphs.size() - 1)
	while not active.is_empty(): _recycle(active.size() - 1)
	sound_queue.clear()
	for voice in voices: voice.stop()
	for entries in authored_pool.values():
		for entry in entries: entry.free()
	authored_pool.clear()
	_authored_pool_size = 0

func _exit_tree() -> void:
	clear()
