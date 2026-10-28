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
var simulation_scale := 1.0
var low_quality := false
var audio_enabled := true
var effects_density := 2
var effects_opacity := 1.0
var reduce_player_effects := false
var catalog: Dictionary = {}
var media: Dictionary = {}
var monster_tuning: Dictionary = {}
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
var _authored_pool_limit: int = FEEL.effect_budget
const WOLF_BURST_INSTANCES := {
	"24042901_fx_enemy_senlinlangwang_roar_fireball": 32,
	"24041801_fx_enemy_senlinlangwang_fireball_explosion": 8,
	"24042901_fx_enemy_senlinlangwang_roar_eruption": 4,
	"24042201_fx_enemy_senlinlangwang_attack2_rangepointer": 4,
	"24042501_fx_enemy_senlinlangwang_attack4_flyslash": 4,
}
var _prepared_group_media: Dictionary = {}
var _authored_templates: Dictionary = {}
var _active_particles := 0
var _active_emitters := 0
var _preparation: Array[Dictionary] = []
var _preparation_keys: Dictionary = {}
var _preparation_head := 0
var _warm_viewport: SubViewport
var _warm_particles: Array[Dictionary] = []
var authored_builds := 0
var authored_reuses := 0
var _sound_serial := 0
var _summon_serial := 0
var prewarmed_heavy_sounds: Dictionary = {}
const Telegraph = preload("res://scripts/presentation/attack_telegraph.gd")
const AuthoredEffect = preload("res://scripts/presentation/authored_effect.gd")
const Descriptors = preload("res://scripts/presentation/effect_descriptors.gd")
const WOLF_EMBEDDED_PATH := "res://assets/combat_presentation/wolf_embedded/catalog.json"
static var _wolf_embedded: Dictionary = {}
var telegraphs: Array[Dictionary] = []
var unresolved_anchors: Dictionary = {}
var _buff_styles: Dictionary = {}
var _buff_style_bindings: Dictionary = {}
var _replacement_buff_ids: Array[String] = []

func configure(value: Dictionary) -> void:
	apply_settings(DungeonSettings.read_options())
	catalog = value
	if _wolf_embedded.is_empty():
		var embedded = JSON.parse_string(FileAccess.get_file_as_string(WOLF_EMBEDDED_PATH))
		if embedded is Dictionary: _wolf_embedded = embedded
	media = Descriptors.load_catalog().duplicate()
	media["effects"] = media.get("effects", {}).duplicate()
	media.effects.merge(_wolf_embedded.get("effects", {}))
	var tuning_path = "res://assets/data/monster_presentation_tuning.json"
	if FileAccess.file_exists(tuning_path): monster_tuning = JSON.parse_string(FileAccess.get_file_as_string(tuning_path))
	for index in FEEL.audio_budget:
		var voice = AudioStreamPlayer3D.new()
		voice.bus = &"Effects"
		voice.max_distance = 28
		voice.unit_size = 8
		add_child(voice)
		voices.append(voice)
	for index in FEEL.effect_budget: pool.append(_make_effect())
	# Decode impact clips before the first contact rather than on its display frame.
	for key in media.get("audio", {}):
		if "hit" not in key and "explos" not in key and "shield" not in key: continue
		for layer in media.audio[key]:
			for clip in layer.get("clips", []):
				if ResourceLoader.exists(str(clip)): sound_cache[str(clip)] = load(str(clip))
	_prewarm_heavy_audio()

func apply_settings(settings: Dictionary) -> void:
	DungeonStyle.apply_audio_options(settings)
	effects_density = clampi(int(settings.get("effects_density", 2)), 0, 2)
	effects_opacity = clampf(float(settings.get("effects_opacity", 100)) / 100.0, 0.0, 1.0)
	reduce_player_effects = bool(settings.get("reduce_player_effects", false))
	for effect in active: _apply_effect_opacity(effect)

func _apply_effect_opacity(effect: Dictionary) -> void:
	var actor = effect.actor.get_ref()
	var gain := effects_opacity * (0.35 if reduce_player_effects and actor and actor.is_player and not effect.important else 1.0)
	# Enemy attack warnings retain their source visibility regardless of cosmetic settings.
	if effect.important: gain = 1.0
	effect["settings_opacity"] = gain
	if effect.authored:
		for emitter in effect.authored.emitters:
			var particle: CPUParticles3D = emitter.node
			if not particle.has_meta("settings_base_alpha"): particle.set_meta("settings_base_alpha", particle.color.a)
			particle.color.a = float(particle.get_meta("settings_base_alpha")) * gain
		for model in effect.authored.find_children("*", "MeshInstance3D", true, false): model.transparency = 1.0 - gain
	effect.sparks.color.a = gain

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
	for definition in source.catalog.get("buffs", []):
		if definition.get("type", "") == "EBT_SpecialReplaceEffect": _replacement_buff_ids.append(str(definition.id))
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

func _effect_key(actor: DungeonActor, value: Variant) -> String:
	var key = _key(value)
	for id in _replacement_buff_ids:
		if actor.combat.buff_layers(id) <= 0: continue
		var settings = actor.combat._settings(actor.combat._buff_index.get(id, {}))
		for replacement in settings.get("ReplaceEffectDict", []):
			if _key(replacement.get("DetectionEffectName", "")) == key and not str(replacement.get("ReplaceEffectName", "")).is_empty():
				return _key(replacement.ReplaceEffectName)
	return key

func _source_style(actor: DungeonActor, hit: Dictionary = {}, summon: Dictionary = {}) -> bool:
	if not actor.is_player and str(actor.combat.enemy.get("rank", "")) == "Boss": return true
	if str(hit.get("definition", {}).get("actType", "")) == "Spirit": return true
	if not hit.get("source_attack_effect_replacements", {}).is_empty(): return true
	var id := str(summon.get("ID", hit.get("summon_id", "")))
	return str(actor.combat._summon_index.get(id, {}).get("hit", {}).get("actType", "")) == "Spirit"

func _source_dimensions(value: Variant, fallback := Vector3.ONE) -> Vector3:
	var dimensions := DungeonWorld.vector(value) if value is Dictionary else Vector3.ZERO
	return fallback if dimensions.is_zero_approx() else dimensions

func _attack_effect_replacements(actor: DungeonActor, hit: Dictionary) -> Dictionary:
	var raw := DungeonWorld._raw_definition(hit.get("definition", {}))
	var attack_id := int(raw.get("Id", 0))
	var result: Dictionary = {}
	if attack_id == 0: return result
	for entry in actor.combat.statuses.values():
		var buff: Dictionary = actor.combat._buff_index.get(str(entry.id), {})
		if buff.get("type", "") != "EBT_ModifyAttackDef" or int(entry.get("layers", 0)) <= 0: continue
		var settings: Dictionary = actor.combat._settings(buff, actor.combat._caster_for(str(entry.id)))
		if not settings.get("AttackDefIdList", []).any(func(id): return int(id) == attack_id): continue
		var detection := _key(settings.get("DetectionEffectName", ""))
		var replacement := str(settings.get("ReplaceEffectName", ""))
		if not detection.is_empty() and not replacement.is_empty(): result[detection] = replacement
	return result

func _attack_effect_name(actor: DungeonActor, name: String, hit: Dictionary) -> String:
	var replacements: Dictionary = hit.get("source_attack_effect_replacements", {}) if hit.has("source_attack_effect_replacements") else _attack_effect_replacements(actor, hit)
	return str(replacements.get(_key(name), name))

func _attack_effect_definition(actor: DungeonActor, definition: Dictionary, hit: Dictionary) -> Dictionary:
	var name := str(definition.get("EffectName", ""))
	var replacement := _attack_effect_name(actor, name, hit)
	if name == replacement: return definition
	var result := definition.duplicate(true)
	result["EffectName"] = replacement
	result["attack_modifier_style"] = true
	return result

func _collect_media(value: Variant, source: DungeonCombat, effects: Dictionary, sounds: Dictionary, pending: Dictionary) -> void:
	if value is Dictionary:
		for field in value:
			if field == "raw": continue
			var child: Variant = value[field]
			if "buff" in str(field).to_lower() or "summon" in str(field).to_lower():
				var ids: Array = child if child is Array else [child]
				for id in ids:
					if not (id is String or id is int or id is float): continue
					var key = str(int(id)) if id is int or id is float else str(id)
					if source._buff_index.has(key): pending["buff:" + key] = source._buff_index[key]
					if source._summon_index.has(key): pending["summon:" + key] = source._summon_index[key]
			if field == "AddSummonUnitId" and str(child) not in ["", "0"]: pending["summon:" + str(child)] = source._summon_index.get(str(child), {})
			elif field in ["BuffTriggerId", "BuffId", "buff"] and str(child) not in ["", "0"]: pending["buff:" + str(child)] = source._buff_index.get(str(child), {})
			elif field == "CommonBuffEffectId" and str(child) not in ["", "0"]: pending["buff:" + str(child)] = source._buff_index.get(str(child), {})
			elif field == "MonsterId" and int(child) > 0:
				for enemy in source.catalog.get("enemies", []):
					if int(enemy.id) == int(child): pending["enemy:" + str(child)] = {"action_group": str(enemy.group)}
			_collect_media(child, source, effects, sounds, pending)
	elif value is Array:
		for child in value: _collect_media(child, source, effects, sounds, pending)
	elif value is String:
		var key = _key(value)
		if media.get("effects", {}).has(key) and ("enemyatkrange" not in key or source.enemy_id == 13001): effects[key] = true
		if media.get("audio", {}).has(key) or catalog.get("audio", {}).has(key): sounds[key] = true

func prepare_combat(combats: Array) -> void:
	var effects: Dictionary = {}
	var sounds: Dictionary = {}
	var groups: Dictionary = {}
	var wolf_bursts := combats.any(func(source): return source.enemy_id == 13001)
	if wolf_bursts:
		# Keep one ordinary cache slot per asset plus bounded concurrent wolf instances.
		_authored_pool_limit = FEEL.effect_budget
		for count in WOLF_BURST_INSTANCES.values(): _authored_pool_limit += int(count) - 1
	for source: DungeonCombat in combats:
		var group = str(source.enemy.get("group", "ActGroup_playerchara"))
		var prefix = str(source.fighter.get("combo", [""])[0]).get_slice("_", 0) if source.enemy.is_empty() else ""
		var identity = group + ":" + prefix
		var buff_ids: Array = source.fighter.get("passives", []) + source.statuses.keys()
		buff_ids = buff_ids.map(func(id): return str(id))
		buff_ids.sort()
		var media_key = identity + ":" + ",".join(buff_ids)
		if groups.has(media_key): continue
		groups[media_key] = true
		if _prepared_group_media.has(media_key):
			effects.merge(_prepared_group_media[media_key].effects)
			sounds.merge(_prepared_group_media[media_key].sounds)
			continue
		var group_effects: Dictionary = {}
		var group_sounds: Dictionary = {}
		var pending: Dictionary = {}
		var seen: Dictionary = {}
		_collect_action_media(source, group, prefix, group_effects, group_sounds, pending)
		for id in buff_ids: pending["buff:" + str(id)] = source._buff_index.get(str(id), {})
		while not pending.is_empty():
			var id = str(pending.keys()[0])
			var definition: Dictionary = pending[id]
			pending.erase(id)
			if seen.has(id): continue
			seen[id] = true
			if definition.has("action_group"): _collect_action_media(source, str(definition.action_group), "", group_effects, group_sounds, pending)
			else: _collect_media(definition, source, group_effects, group_sounds, pending)
		if _prepared_group_media.size() >= 64: _prepared_group_media.erase(_prepared_group_media.keys()[0])
		_prepared_group_media[media_key] = {"effects": group_effects, "sounds": group_sounds}
		effects.merge(group_effects)
		sounds.merge(group_sounds)
	for key in effects:
		if media.effects[key].get("layers", []).is_empty() and media.effects[key].get("models", []).is_empty(): continue
		for source_only in [false, true] if FEEL.effect_emitter_suppressions.has(key) else [false]:
			var cache_key = _authored_cache_key(key, source_only)
			var template: Node3D = _authored_templates.get(cache_key)
			if template != null:
				_authored_templates.erase(cache_key)
				_authored_templates[cache_key] = template
			var count := int(WOLF_BURST_INSTANCES.get(key, 1)) if wolf_bursts else 1
			if (template != null and authored_pool.get(cache_key, []).size() >= _preparation_count(template, count, low_quality)) or _preparation_keys.has(cache_key): continue
			_preparation.append({"effect": key, "cache_key": cache_key, "low": low_quality, "source_only": source_only, "count": count})
			_preparation_keys[cache_key] = true
	for key in sounds:
		var layers: Array = media.get("audio", {}).get(key, [])
		if layers.is_empty() and catalog.get("audio", {}).has(key): layers = [{"clips": [catalog.audio[key]]}]
		for layer in layers:
			for clip in layer.get("clips", []):
				var path = str(clip)
				if sound_cache.has(path) or _preparation_keys.has(path): continue
				_preparation.append({"audio": path})
				_preparation_keys[path] = true

func _collect_action_media(source: DungeonCombat, group: String, prefix: String, effects: Dictionary, sounds: Dictionary, pending: Dictionary) -> void:
	for action in source.catalog.get("actions", []):
		if str(action.get("group", "")) != group or (not prefix.is_empty() and prefix not in str(action.id)): continue
		for command in action.get("events", []) + action.get("hits", []):
			if command.get("enabled", false):
				_collect_media(DungeonWorld._raw_definition(command), source, effects, sounds, pending)
				if command.has("buff"): pending["buff:" + str(command.buff)] = source._buff_index.get(str(command.buff), {})

func has_pending_preparation() -> bool:
	return _preparation_head < _preparation.size() or not _warm_particles.is_empty()

func _preparation_count(template: Node3D, requested: int, low: bool) -> int:
	var count := mini(requested, FEEL.low_effect_budget if low else FEEL.effect_budget)
	count = mini(count, int((FEEL.low_emitter_budget if low else FEEL.emitter_budget) / maxi(1, template.emitters.size())))
	count = mini(count, int((FEEL.low_particle_budget if low else FEEL.particle_budget) / maxi(1, template.particle_count)))
	return maxi(1, count)

func prepare_step() -> void:
	for i in range(_warm_particles.size() - 1, -1, -1):
		if Engine.get_process_frames() > int(_warm_particles[i].frame):
			_warm_particles[i].node.free()
			_warm_particles.remove_at(i)
	var started = Time.get_ticks_usec()
	while _preparation_head < _preparation.size():
		var entry = _preparation[_preparation_head]
		_preparation_head += 1
		if entry.has("audio"):
			if not sound_cache.has(entry.audio) and ResourceLoader.exists(entry.audio): sound_cache[entry.audio] = load(entry.audio)
		else:
			# A pooled instance can outlive its template; concurrent casts still need it.
			var template := _authored_template(entry.effect, entry.cache_key, entry.low, bool(entry.get("source_only", false)))
			var count := _preparation_count(template, int(entry.get("count", 1)), entry.low)
			if authored_pool.get(entry.cache_key, []).size() < count:
				var authored: Node3D = template.instantiate_effect()
				if authored_pool.get(entry.cache_key, []).is_empty(): _warm_rendering(authored)
				_store_authored(entry.cache_key, authored)
				if authored_pool.get(entry.cache_key, []).size() < count: _preparation_head -= 1
		if Time.get_ticks_usec() - started >= FEEL.combat_prepare_usec: break
	if not has_pending_preparation():
		_preparation.clear()
		_preparation_keys.clear()
		_preparation_head = 0

func _warm_rendering(authored: Node3D) -> void:
	if DisplayServer.get_name() == "headless": return
	if _warm_viewport == null:
		_warm_viewport = SubViewport.new()
		_warm_viewport.size = Vector2i(32, 32)
		_warm_viewport.own_world_3d = true
		add_child(_warm_viewport)
		var camera = Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 4
		camera.position.z = 4
		_warm_viewport.add_child(camera)
		var warning = Telegraph.new()
		warning.configure(Vector2.ONE)
		warning.rotation.x = PI / 2
		_warm_viewport.add_child(warning)
	# Draw the actual particle shader variants offscreen before gameplay resumes.
	for emitter in authored.emitters:
		var particle: CPUParticles3D = emitter.node.duplicate(0)
		particle.transform = Transform3D.IDENTITY
		particle.amount = 1
		particle.lifetime = 1
		particle.one_shot = true
		particle.explosiveness = 1
		particle.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINT
		particle.initial_velocity_min = 0
		particle.initial_velocity_max = 0
		particle.gravity = Vector3.ZERO
		particle.scale_amount_min = 0.1
		particle.scale_amount_max = 0.1
		_warm_viewport.add_child(particle)
		particle.restart()
		particle.request_particles_process(1.0 / 60.0)
		_warm_particles.append({"node": particle, "frame": Engine.get_process_frames()})
	_warm_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _authored_cache_key(key: String, source_only: bool) -> String:
	return key + (":source" if source_only and FEEL.effect_emitter_suppressions.has(key) else "") + (":low" if low_quality else ":full")

func _take_authored(key: String, cache_key: String, low: bool, source_only := false) -> Node3D:
	if not authored_pool.get(cache_key, []).is_empty():
		_authored_pool_size -= 1
		authored_reuses += 1
		var authored: Node3D = authored_pool[cache_key].pop_back()
		if authored_pool[cache_key].is_empty(): authored_pool.erase(cache_key)
		return authored
	return _authored_template(key, cache_key, low, source_only).instantiate_effect()

func _authored_template(key: String, cache_key: String, low: bool, source_only: bool) -> Node3D:
	var template: Node3D = _authored_templates.get(cache_key)
	if template == null:
		var definition = effect_definition(key)
		_prepare_effect_textures(definition)
		template = AuthoredEffect.new()
		template.configure(definition, low, texture_cache, [] if source_only else FEEL.effect_emitter_suppressions.get(key, []))
		authored_builds += 1
	_authored_templates.erase(cache_key)
	_authored_templates[cache_key] = template
	while _authored_templates.size() > FEEL.effect_template_budget:
		var oldest = _authored_templates.keys()[0]
		_authored_templates[oldest].free()
		_authored_templates.erase(oldest)
	return template

func effect_definition(name: String) -> Dictionary:
	return Descriptors.resolve(media.get("effects", {}).get(_key(name), {}))

func _prepare_effect_textures(definition: Dictionary) -> void:
	for path in definition.get("textures", []):
		if not texture_cache.has(path) and ResourceLoader.exists(str(path)):
			texture_cache[path] = load(str(path))

func _store_authored(cache_key: String, authored: Node3D) -> void:
	while _authored_pool_size >= _authored_pool_limit:
		var oldest = authored_pool.keys()[0]
		var entries: Array = authored_pool[oldest]
		entries.pop_front().free()
		_authored_pool_size -= 1
		if entries.is_empty(): authored_pool.erase(oldest)
	var entries: Array = authored_pool.get(cache_key, [])
	entries.append(authored)
	# Insertion order provides a bounded cache that also admits effects from later rooms.
	authored_pool.erase(cache_key)
	authored_pool[cache_key] = entries
	_authored_pool_size += 1

func _reserve_effect(particles: int, emitters: int, important: bool, priority: bool) -> bool:
	var budget = FEEL.low_effect_budget if low_quality else FEEL.effect_budget
	var particle_limit = FEEL.low_particle_budget if low_quality else FEEL.particle_budget
	var emitter_limit = FEEL.low_emitter_budget if low_quality else FEEL.emitter_budget
	if not important:
		var multiplier: float = [0.35, 0.65, 1.0][effects_density]
		budget = maxi(4, int(budget * multiplier))
		particle_limit = maxi(128, int(particle_limit * multiplier))
		emitter_limit = maxi(8, int(emitter_limit * multiplier))
	while active.size() >= budget or pool.is_empty() or _active_particles + particles > particle_limit or _active_emitters + emitters > emitter_limit:
		var victim := -1
		for i in active.size():
			if not active[i].important and (important or not active[i].get("priority", false)) and (important or priority or int(active[i].get("summon_token", 0)) == 0):
				victim = i
				break
		if victim < 0: return false
		_recycle(victim)
	return true

func emit_effect(actor: DungeonActor, name: String, point: Vector3, dimensions := Vector3(2, 1, 2), duration := 0.35, follow: Node3D = null, important := false, sequence := -1, loop := false, priority := false, source_only := false) -> void:
	source_only = source_only or (not actor.is_player and actor.combat.enemy_id == 13001)
	if not important and get_viewport().get_camera_3d() and point.distance_to(get_viewport().get_camera_3d().global_position) > 48: return
	var key = _effect_key(actor, name)
	var definition: Dictionary = media.get("effects", {}).get(key, {})
	if source_only and definition.get("layers", []).is_empty() and definition.get("models", []).is_empty():
		if not key.is_empty(): missing[key] = true
		return
	var cache_key = _authored_cache_key(key, source_only)
	var authored: Node3D
	var has_authored: bool = not definition.get("layers", []).is_empty() or not definition.get("models", []).is_empty()
	if has_authored:
		# Reserve first: eviction can return the exact instance this cast needs.
		var retained: Array = authored_pool.get(cache_key, [])
		var prototype: Node3D = retained.back() if not retained.is_empty() else _authored_template(key, cache_key, low_quality, source_only)
		if not _reserve_effect(prototype.particle_count, prototype.emitters.size(), important, priority): return
		authored = _take_authored(key, cache_key, low_quality, source_only)
	elif not _reserve_effect(0, 0, important, priority): return
	var entry: Dictionary = pool.pop_back()
	entry.erase("buff_style")
	entry.erase("embedded_effect")
	entry["source_warning"] = false
	var textures: Array = media.get("effects", {}).get(key, {}).get("textures", [])
	if not key.is_empty() and not media.get("effects", {}).has(key): missing[key] = true
	var mat: StandardMaterial3D = entry.material
	if not textures.is_empty(): _prepare_effect_textures({"textures": [textures[0]]})
	mat.albedo_texture = texture_cache.get(textures[0]) if not textures.is_empty() else null
	mat.albedo_color = color_for(actor)
	entry.mesh.visible = mat.albedo_texture != null
	entry.burst.hide()
	entry.root.position = point
	entry.root.rotation = Vector3(0, atan2(actor.facing.x, actor.facing.z), 0)
	entry.root.scale = Vector3.ONE
	entry.mesh.scale = Vector3(maxf(0.2, dimensions.x), maxf(0.2, dimensions.z), 1)
	entry.root.show()
	entry.merge({"actor": weakref(actor), "sequence": sequence, "clock_sequence": -1, "playback_speed": 1.0, "detach_after": 0.0, "summon_token": 0, "age": 0.0, "duration": maxf(0.05, duration), "follow": weakref(follow) if follow else null, "offset": follow.to_local(point) if follow else Vector3.ZERO, "world_offset": point - follow.global_position if follow else Vector3.ZERO, "position_without_rotate": false, "follow_rotation": false, "rotation_offset": Basis.IDENTITY, "important": important, "priority": priority, "detached": priority, "loop": loop, "key": key, "color": color_for(actor), "body_burst": false, "source_only": source_only}, true)
	entry.sparks.emitting = false
	entry.sparks.direction = Vector3.UP
	entry.sparks.spread = 75
	entry.sparks.color = color_for(actor)
	if authored:
		entry.root.add_child(authored)
		authored.transform = Transform3D.IDENTITY
		authored.set_visual_gain(1.0 if source_only else FEEL.sword_light_gain if _sword_slash(key) else FEEL.skill_light_gain, not source_only and _sword_slash(key))
		authored.restart()
		entry.authored = authored
		_active_particles += authored.particle_count
		_active_emitters += authored.emitters.size()
		entry["cache_key"] = cache_key
		entry.mesh.hide()
		if not loop and follow == null: entry.duration = maxf(float(entry.duration), minf(authored.lifetime, 4.0))
	_apply_effect_opacity(entry)
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
	if actor.visual:
		if not actor.is_player: name = str(monster_tuning.get("enemies", {}).get(str(actor.actor_id), {}).get("anchor_aliases", {}).get(name, name))
		var node = actor.visual.find_child(name, true, false)
		if node is Node3D: return node
		if not name.is_empty():
			for skeleton: Skeleton3D in actor.visual.find_children("*", "Skeleton3D", true, false):
				var bone = skeleton.find_bone(name)
				if bone < 0: continue
				var socket = BoneAttachment3D.new()
				socket.name = name
				socket.bone_name = skeleton.get_bone_name(bone)
				skeleton.add_child(socket)
				socket.transform = skeleton.get_bone_global_pose(bone)
				return socket
		if name == "Unit_Center":
			var center = Node3D.new()
			center.name = name
			actor.visual.add_child(center)
			center.global_position = actor.to_global(actor.impact_bounds.get_center())
			return center
	if "hand" in name.to_lower() or "weapon" in name.to_lower():
		if is_instance_valid(actor.weapon): return actor.weapon
	if not actor.is_player and not str(dummy.get("CustomDummyName", "")).is_empty(): unresolved_anchors[str(actor.actor_id) + ":" + name] = true
	return actor

func trigger(actor: DungeonActor, definition: Dictionary, sequence := -1, point := Vector3.INF, use_action_clock := true, source_only := false, facing := Vector3.ZERO) -> void:
	source_only = source_only or _source_style(actor) or bool(definition.get("attack_modifier_style", false))
	var name = str(definition.get("EffectName", ""))
	if name.is_empty(): return
	var source_wolf: bool = not actor.is_player and actor.combat.enemy_id == 13001
	var source_warning: bool = source_wolf and ("enemyatkrange" in name.to_lower() or "attackrange" in name.to_lower() or "attackprompt" in name.to_lower() or "rangepointer" in name.to_lower())
	if not actor.is_player and "enemyatkrange" in name.to_lower() and not source_wolf:
		_authored_telegraph(actor, definition, sequence, point, -1.0, facing)
		return
	var anchor = _anchor(actor, definition)
	var follows = str(definition.get("DummyType", "")) in ["EEDT_DummyChild", "EEDT_DummyPosFollow_WithoutRotate"]
	var offset = DungeonWorld.vector(definition.get("Position", {}))
	if not source_only and _sword_slash(_key(name)): offset.z += 0.55
	var direction := actor.facing if facing.is_zero_approx() else facing
	var yaw := atan2(direction.x, direction.z)
	var bone_bound = not actor.is_player and anchor != actor and not str(definition.get("DummyData", {}).get("CustomDummyName", "")).is_empty()
	var location = anchor.to_global(offset) if bone_bound else anchor.global_position + Basis(Vector3.UP, yaw) * offset
	if point != Vector3.INF: location = point + (Basis(Vector3.UP, yaw) * offset if source_only else offset)
	if not source_only: location.y += 0.08
	var dimensions = DungeonWorld.vector(definition.get("Scale", {}))
	if dimensions.is_zero_approx() if source_only else dimensions.length_squared() < 0.01: dimensions = Vector3.ONE
	var duration = float(definition.get("DelayTimeToDestroy", 0)) / 1000.0
	var loop = bool(definition.get("IsLoop", false))
	if duration <= 0: duration = maxf(actor.action_time, 0.3) if loop else 0.45
	var playback_speed = maxf(0.1, float(definition.get("EffectSpeed", 1)))
	duration /= playback_speed
	var owned = sequence if definition.get("DestoryWhenActionSwitch", false) or (loop and not source_wolf) else -1
	var emitted_before = spawned
	emit_effect(actor, name, location, dimensions, duration, anchor if follows else null, source_warning, owned, loop, false, source_only)
	if spawned > emitted_before:
		if source_warning or (not actor.is_player and "attackprompt" in _key(name)): actor.lock_telegraph_aim(sequence)
		active.back()["source_warning"] = source_warning
		active.back().clock_sequence = sequence if use_action_clock and definition.get("SpeedScaleByOwnerActionSpeed", true) else -1
		active.back().playback_speed = playback_speed
		active.back().detach_after = maxf(0, float(definition.get("DelayTimeToWorldPos", 0))) / 1000.0
		if (not loop or source_wolf) and float(definition.get("DelayTimeToDestroy", 0)) <= 0 and active.back().authored:
			var source_lifetime: float = active.back().authored.lifetime
			active.back().duration = maxf(0.05, (source_lifetime if source_wolf else minf(source_lifetime, 4.0)) / playback_speed)
		active.back().root.rotation = Vector3(0, yaw, 0) + DungeonWorld.vector(definition.get("Euler", {})) * PI / 180.0
		if bone_bound: active.back().root.global_basis = anchor.global_basis.orthonormalized() * Basis.from_euler(DungeonWorld.vector(definition.get("Euler", {})) * PI / 180.0)
		if not source_only and _sword_slash(_key(name)): active.back().root.rotate_y(PI)
		active.back().position_without_rotate = str(definition.get("DummyType", "")) == "EEDT_DummyPosFollow_WithoutRotate"
		if str(definition.get("DummyType", "")) == "EEDT_DummyChild":
			active.back().follow_rotation = true
			active.back().rotation_offset = anchor.global_basis.inverse() * active.back().root.global_basis
		if active.back().authored: active.back().authored.scale = dimensions
	play_sound(str(definition.get("InitSoundDef", {}).get("SoundName", "")), location, actor, sequence)

func action_started(actor: DungeonActor, event: Dictionary) -> void:
	cancel_actor(actor, int(event.sequence))
	if not actor.is_player and actor.combat.enemy_id != 13001:
		var definition = actor.combat._action(str(actor.combat.enemy.group), str(event.action))
		var authored: Array = (definition.get("events", []) + definition.get("hits", [])).filter(func(command): return command.get("enabled", false) and "enemyatkrange" in str(command.get("raw", "")).to_lower())
		# Authored warnings dispatch on their actual event, with live source conditions.
		# Precreating them suppresses later same-prefab beats and freezes target positions early.
		if authored.is_empty():
			var hits: Array = definition.get("hits", []).duplicate()
			hits.sort_custom(func(first, second): return float(first.get("time", 0)) < float(second.get("time", 0)))
			var previous_impact := 0.0
			var seen: Dictionary = {}
			for hit in hits:
				if not hit.get("enabled", false) or float(hit.get("time", 0)) <= 0.08: continue
				if not actor.combat._conditions(hit.get("conditions", []), bool(hit.get("all", true))): continue
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
				var emit: Dictionary = raw.get("EmitProperty", {})
				var yaw = deg_to_rad(float(emit.get("EmitRotation", {}).get("y", 0)))
				# Imported hit.offset already mirrors EmitOffset.z when raw emission exists.
				var local_offset = float(hit.get("forward_offset", 0)) + (0.0 if emit.has("EmitOffset") else float(hit.get("offset", 0)))
				var offset = DungeonWorld.vector(emit.get("EmitOffset", {})) + Basis(Vector3.UP, yaw) * (DungeonWorld.vector(emit.get("AfterRotateEmitOffset", {})) + Vector3(0, 0, local_offset))
				offset.y = 0
				var at = float(hit.time)
				var identity = str([at, size, shape, degrees, offset, yaw])
				if seen.has(identity): continue
				seen[identity] = true
				# A reconstructed warning belongs to its own beat, not every later combo hit.
				var first = maxf(previous_impact, maxf(0, at - 0.7))
				var speed = maxf(0.01, float(event.get("speed", 1)))
				_add_telegraph(actor, int(event.sequence), size, shape, degrees, offset, yaw, maxf(0.01, at - first) / speed, Vector3.INF, first / speed)
				previous_impact = at
	for effect in active:
		if effect.actor.get_ref() == actor and effect.sequence == int(event.sequence): effect.clock_sequence = int(event.sequence)

func _authored_telegraph(actor: DungeonActor, definition: Dictionary, sequence: int, point: Vector3, start := -1.0, facing := Vector3.ZERO) -> void:
	var key = _key(str(definition.EffectName))
	var scale_value = DungeonWorld.vector(definition.get("Scale", {})).abs()
	if scale_value.is_zero_approx(): scale_value = Vector3.ONE
	var rectangle = "rectangle" in key
	var forward_z = "forwardz" in key or "fowardz" in key
	var base_size = 1.0 if rectangle and forward_z else 2.1 if "90_forwardz" in key else 5.0
	# APK forward sector has an additional 0.42 prefab scale; rectangles use 0.2.
	var size = Vector2(scale_value.x, scale_value.z) * base_size
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
	telegraphs.back()["follow_position"] = str(definition.get("DummyType", "EEDT_DummyChild")) in ["EEDT_DummyChild", "EEDT_DummyPosFollow_WithoutRotate"]
	telegraphs.back()["follow_rotation"] = str(definition.get("DummyType", "EEDT_DummyChild")) == "EEDT_DummyChild"
	telegraphs.back()["detach_after"] = maxf(0, float(definition.get("DelayTimeToWorldPos", 0))) / 1000.0
	if not facing.is_zero_approx():
		telegraphs.back()["facing"] = facing
		telegraphs.back()["facing_offset"] = atan2(facing.x, facing.z) - atan2(actor.facing.x, actor.facing.z)
	_place_telegraph(telegraphs.back(), actor)

func _add_telegraph(actor: DungeonActor, sequence: int, size: Vector2, shape: int, degrees: float, offset: Vector3, yaw: float, duration: float, point := Vector3.INF, start := -1.0) -> void:
	var node = Telegraph.new()
	node.configure(size, shape, degrees)
	add_child(node)
	var entry = {"node": node, "actor": weakref(actor), "sequence": sequence, "start": float(actor.combat.action_elapsed) if start < 0 else start, "duration": maxf(0.01, duration), "offset": offset, "yaw": yaw, "point": point, "follow_position": true, "follow_rotation": true, "origin": actor.position if point == Vector3.INF else point, "facing": actor.facing, "detach_after": 0.0}
	telegraphs.append(entry)
	_place_telegraph(entry, actor)

func _place_telegraph(entry: Dictionary, actor: DungeonActor) -> void:
	entry.node.visible = float(actor.combat.action_elapsed) >= float(entry.start)
	if entry.node.visible: actor.lock_telegraph_aim(int(entry.sequence))
	if float(entry.get("detach_after", 0)) > 0 and float(actor.combat.action_elapsed) - float(entry.start) >= float(entry.detach_after):
		entry.follow_position = false
		entry.follow_rotation = false
	if entry.get("follow_position", true): entry.origin = actor.position if entry.point == Vector3.INF else entry.point
	if entry.get("follow_rotation", true): entry.facing = Basis(Vector3.UP, float(entry.get("facing_offset", 0))) * actor.facing
	var facing = Basis(Vector3.UP, atan2(entry.facing.x, entry.facing.z))
	entry.node.position = entry.origin + facing * entry.offset + Vector3.UP * 0.12
	entry.node.rotation.y = atan2(entry.facing.x, entry.facing.z) + float(entry.yaw)
	entry.node.set_progress((float(actor.combat.action_elapsed) - float(entry.start)) / float(entry.duration))

func _remove_telegraph(index: int) -> void:
	telegraphs[index].node.hide()
	telegraphs[index].node.queue_free()
	telegraphs.remove_at(index)

func command(actor: DungeonActor, event: Dictionary) -> void:
	var command_data: Dictionary = event.command
	var raw = DungeonWorld._raw_definition(command_data)
	match str(command_data.get("type", "")):
		"EET_PlayEffect":
			var effect: Dictionary = raw.get("EffectTriggerDef", raw)
			if not actor.is_player and actor.combat.enemy_id == 13001:
				# EventPlayEffect reads literal custom-property names, including "kuangbao-100".
				var factor: float = 1.0 + actor.combat._property_context_total(str(raw.get("ScaleModifyPropertyName", ""))) / 1000.0
				if not is_equal_approx(factor, 1.0):
					effect = effect.duplicate(true)
					var size: Vector3 = _source_dimensions(effect.get("Scale", {})) * factor
					effect["Scale"] = {"x": size.x, "y": size.y, "z": size.z}
			trigger(actor, effect, int(event.sequence), Vector3.INF, not raw.get("IgnoreActionSpeed", false), preload("res://scripts/presentation/impact_profiles.gd").is_source_heavy(event, actor.combat))
		"EET_StopEffect":
			var key = _key(raw.get("EffectName", raw.get("EffectId", "")))
			for i in range(active.size() - 1, -1, -1):
				if active[i].actor.get_ref() == actor and (key.is_empty() or active[i].key == key): _recycle(i)
		"EET_PlaySound": play_sound(str(raw.get("SoundName", "")), actor.position, actor, int(event.sequence))
		"EET_PlayVoice": play_sound(str(raw.get("VoiceName", "")), actor.position, actor, int(event.sequence), 1.0, 1.0, false, "voice")
		"EET_SetGameObjectActive":
			if not actor.is_player and actor.combat.enemy_id == 13001:
				for name in raw.get("gameobjectNames", []): _set_embedded_effect(actor, str(name), bool(raw.get("booleanToSet", false)))

func attack_emitted(actor: DungeonActor, hit: Dictionary, origin: Vector3, facing := Vector3.ZERO) -> void:
	# Entity styles retain the modifiers active at creation across their delay/lifetime.
	if not hit.has("source_attack_effect_replacements"): hit["source_attack_effect_replacements"] = _attack_effect_replacements(actor, hit)
	var definition: Dictionary = hit.get("definition", {})
	var raw = DungeonWorld._raw_definition(definition)
	var entity: Dictionary = raw.get("EntityProperty", {})
	var effect := _attack_effect_definition(actor, entity.get("EffectTriggerDef", {}), hit)
	var emitted_before = spawned
	var attached = str(raw.get("MotionAnimatorType", "")) in ["EMAT_FollowOwner", "EMAT_RotateOwner"]
	if not str(effect.get("EffectName", "")).is_empty() and (raw.get("EntityType", "") != "EET_Physical" or attached): trigger(actor, effect, int(hit.get("sequence", -1)), origin, true, _source_style(actor, hit) or preload("res://scripts/presentation/impact_profiles.gd").is_source_heavy(hit, actor.combat), facing)
	if spawned > emitted_before:
		if preload("res://scripts/presentation/impact_profiles.gd").ranged(hit): active.back().clock_sequence = -1
	play_sound(str(entity.get("CreateSound", {}).get("SoundName", "")), origin, actor, int(hit.get("sequence", -1)))

func entity_activated(actor: DungeonActor, hit: Dictionary, origin: Vector3, facing := Vector3.ZERO) -> void:
	var raw := DungeonWorld._raw_definition(hit.get("definition", {}))
	var entity: Dictionary = raw.get("EntityProperty", {})
	var source_only := _source_style(actor, hit) or preload("res://scripts/presentation/impact_profiles.gd").is_source_heavy(hit, actor.combat)
	trigger(actor, _attack_effect_definition(actor, entity.get("EffectDelayTriggerDef", {}), hit), int(hit.get("sequence", -1)), origin, true, source_only, facing)
	var sound: Variant = entity.get("Sound", entity.get("SoundTriggerDef", ""))
	if sound is Dictionary: sound = sound.get("SoundName", "")
	play_sound(str(sound), origin, actor, int(hit.get("sequence", -1)))

func impact(source: DungeonActor, target: DungeonActor, hit: Dictionary) -> void:
	impacts += 1
	var profile: Dictionary = hit.profile if hit.has("profile") else preload("res://scripts/presentation/impact_profiles.gd").resolve(hit, source.combat)
	if bool(profile.get("source_only", false)) or _source_style(source, hit):
		var point := DungeonWorld.vector(hit.get("impact_position", DungeonProjectile._array(target.position + Vector3.UP * 0.65)))
		preload("res://scripts/presentation/source_heavy_impact.gd").present(self, source, target, hit, point)
		return
	var position = target.impact_anchor(DungeonWorld.vector(hit.get("impact_position", DungeonProjectile._array(target.position + Vector3.UP * 0.65))))
	var camera = get_viewport().get_camera_3d()
	if camera: position += (camera.global_position - position).normalized() * clampf(target.impact_bounds.size.z * 0.25, 0.22, 0.6)
	var category = str(profile.category)
	if category == "continuous" and target.hurt_timer > 0: return
	_contact_burst(source, position, profile, target, float(impacts % 11))
	if category == "shield":
		play_sound("audio_fx_swordhit_body_02", position, source, -1, 0.55, 1.15, true)
		return
	var sounded := false
	var summon_id = str(hit.get("summon_id", ""))
	if not summon_id.is_empty():
		var summon: Dictionary = source.combat._summon_index.get(summon_id, {}).get("raw_data", {})
		_summon_style(source, str(summon.get("HitEffect", "")), position)
		_summon_style(source, str(summon.get("HitEffect_UnitCenter", "")), target.impact_anchor(target.position + Vector3.UP * 0.65))
		var sound = str(summon.get("HitSound", ""))
		if not sound.is_empty():
			play_sound(sound, position, source)
			sounded = true
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
	var definition := _attack_effect_definition(actor, state.entity.get("EffectTriggerDef", {}), state.hit)
	var name = str(state.entity.get("ModlePrefab", definition.get("EffectName", "")))
	if name.is_empty(): name = str(definition.get("EffectName", ""))
	var original_name: String = name
	name = _attack_effect_name(actor, name, state.hit)
	# Attached hitboxes already emitted their action-owned slash at the actor anchor.
	if state.motion_type in ["EMAT_FollowOwner", "EMAT_RotateOwner"] and str(state.entity.get("ModlePrefab", "")).is_empty(): return
	var source_only := _source_style(actor, state.hit) or original_name != name or bool(definition.get("attack_modifier_style", false)) or preload("res://scripts/presentation/impact_profiles.gd").is_source_heavy(state.hit, actor.combat)
	if source_only and str(state.entity.get("ModlePrefab", "")).is_empty():
		var before := spawned
		trigger(actor, definition, -1, state.position, false, true)
		if spawned > before:
			var entry: Dictionary = active.back()
			entry.follow = weakref(visual)
			entry.offset = visual.to_local(entry.root.global_position)
			entry.world_offset = entry.root.global_position - visual.global_position
		return
	var before := spawned
	var dimensions := _source_dimensions(state.entity.get("ModlePrefabSize", {}), Vector3.ONE if source_only else Vector3.ONE * clampf(state.radius * 2, 0.6, 3))
	emit_effect(actor, name, state.position, dimensions, state.lifetime, visual, false, -1, true, false, source_only)
	if spawned > before and active.back().authored: active.back().authored.scale = dimensions

func projectile_ended(actor: DungeonActor, state: DungeonProjectile) -> void:
	var original_name := str(state.entity.get("EntityEndEffect", ""))
	var name := _attack_effect_name(actor, original_name, state.hit)
	var source_only := _source_style(actor, state.hit) or original_name != name or preload("res://scripts/presentation/impact_profiles.gd").is_source_heavy(state.hit, actor.combat)
	if not name.is_empty(): _summon_style(actor, name, state.position, _source_dimensions(state.entity.get("EntityEndEffectScale", {}), Vector3.ONE if source_only else Vector3.ONE * clampf(state.radius * 2, 0.8, 4)), source_only)
	play_sound(str(state.entity.get("EntityEndSoundDef", {}).get("SoundName", state.entity.get("EntityEndSound", ""))), state.position, actor)

func release_anchor(anchor: Node3D) -> void:
	# Pool reuse must not move an old trail onto the next projectile.
	for index in range(active.size() - 1, -1, -1):
		var follow = active[index].get("follow")
		if follow and follow.get_ref() == anchor: _recycle(index)

func summon_started(actor: DungeonActor, raw: Dictionary, point: Vector3, facing := Vector3.ZERO, source_only := false) -> int:
	source_only = source_only or _source_style(actor, {}, raw)
	var prefab = str(raw.get("Prefab", ""))
	if prefab.is_empty(): return 0
	var definition: Dictionary = media.get("effects", {}).get(_key(prefab), {})
	if definition.get("layers", []).is_empty() and definition.get("models", []).is_empty(): return 0
	var dimensions = DungeonWorld.vector(raw.get("PrefabScale", {}))
	if dimensions.is_zero_approx(): dimensions = Vector3.ONE
	var before = spawned
	emit_effect(actor, str(raw.Prefab), point, dimensions, 1.0, null, false, -1, true, true, source_only)
	if spawned == before: return 0
	_summon_serial += 1
	var entry: Dictionary = active.back()
	entry.summon_token = _summon_serial
	entry.detached = true
	entry.duration = INF
	if entry.authored: entry.authored.scale = dimensions
	if entry.authored and not str(raw.get("InitAnimName", "")).is_empty(): entry.authored.play_model_animation(str(raw.InitAnimName))
	summon_updated(_summon_serial, point, actor.facing if facing.is_zero_approx() else facing)
	return _summon_serial

func _summon_style(actor: DungeonActor, name: String, point: Vector3, dimensions := Vector3.ONE, source_only := false) -> void:
	if name.is_empty(): return
	if dimensions.is_zero_approx(): dimensions = Vector3.ONE
	var before = spawned
	emit_effect(actor, name, point, dimensions, 0.45, null, false, -1, false, true, source_only)
	if spawned > before and active.back().authored:
		active.back().authored.scale = dimensions
		active.back().duration = maxf(0.05, minf(active.back().authored.lifetime, 8.0))

func summon_created(actor: DungeonActor, raw: Dictionary, point: Vector3, source_only := false) -> void:
	source_only = source_only or _source_style(actor, {}, raw)
	_summon_style(actor, str(raw.get("InitEffect", "")), point, Vector3.ONE, source_only)
	play_sound(str(raw.get("InitSoundTriggerDef", {}).get("SoundName", "")), point, actor)

func summon_phase(actor: DungeonActor, raw: Dictionary, point: Vector3, phase: String, source_only := false) -> void:
	source_only = source_only or _source_style(actor, {}, raw)
	_summon_style(actor, str(raw.get("EffectName_" + phase, "")), point, DungeonWorld.vector(raw.get("EffectScale_" + phase, {})), source_only)
	play_sound(str(raw.get("SoundTrigger_" + phase, {}).get("SoundName", "")), point, actor)

func summon_trigger(actor: DungeonActor, raw: Dictionary, point: Vector3, phase: String, source_only := false) -> void:
	source_only = source_only or _source_style(actor, {}, raw)
	_summon_style(actor, str(raw.get("TriggerEffectName_" + phase, "")), point, Vector3.ONE, source_only)

func summon_pickup(actor: DungeonActor, raw: Dictionary, point: Vector3, source_only := false) -> void:
	source_only = source_only or _source_style(actor, {}, raw)
	_summon_style(actor, str(raw.get("PickUpEffect", "")), point, Vector3.ONE, source_only)

func summon_disposed(actor: DungeonActor, raw: Dictionary, point: Vector3, source_only := false) -> void:
	source_only = source_only or _source_style(actor, {}, raw)
	_summon_style(actor, str(raw.get("DestoryEffect", "")), point, Vector3.ONE, source_only)
	play_sound(str(raw.get("DestroySoundTriggerDef", {}).get("SoundName", "")), point, actor)

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
	var phase = str(event.get("phase", ""))
	if phase == "start":
		_emit_buff_style(actor, raw, str(raw.get("StartEffect", "")))
		play_sound(str(raw.get("StartSound", {}).get("SoundName", "")), actor.position, actor)
		return
	if phase == "counter_max":
		_emit_buff_style(actor, raw, str(raw.get("PlayEffectWhenLayerMax", "")))
		return
	if raw.has("KeepEffect") or raw.has("CounterFx"):
		sync_actor_buffs(actor)
		return
	var emitted_before = spawned
	var definition: Variant = raw.get("EffectName1", raw.get("EffectTriggerDef", raw))
	if definition is String: definition = {"EffectName": definition}
	if definition is Dictionary:
		trigger(actor, definition, actor.combat._cast_sequence, Vector3.INF, false, raw.has("EffectName1"))
	if spawned > emitted_before: active.back().clock_sequence = -1
	play_sound(str(raw.get("SoundTriggerDef", {}).get("SoundName", "")), actor.position, actor)

func _buff_style_definitions(actor: DungeonActor, owner_id: String) -> Dictionary:
	if _buff_style_bindings.has(owner_id): return _buff_style_bindings[owner_id]
	var result: Dictionary = {}
	var seen: Dictionary = {}
	var pending: Array[String] = [owner_id]
	while not pending.is_empty():
		var id: String = pending.pop_back()
		if seen.has(id): continue
		seen[id] = true
		var raw: Dictionary = actor.combat._buff_index.get(id, {}).get("raw_data", {})
		if not str(raw.get("KeepEffect", raw.get("CounterFx", ""))).is_empty() or not str(raw.get("StartEffect", "")).is_empty() or not raw.get("ActiveExistEffectList", []).is_empty(): result[id] = raw
		var common = str(raw.get("CommonBuffEffectId", ""))
		if not common.is_empty() and not seen.has(common): pending.append(common)
	_buff_style_bindings[owner_id] = result
	return result

func _buff_style_enabled(actor: DungeonActor, raw: Dictionary) -> bool:
	if str(raw.get("EffectPlayType", "")) != "Attribute": return true
	var attribute = str(raw.get("CheckAttributeType", "None"))
	var value: Variant = actor.combat.property_value(attribute)
	if attribute == "ForzenRemainTime": value = actor.combat.frozen
	elif attribute == "GodRemainTime": value = actor.combat.invincible
	if value == null: return false
	return actor.combat._compare(float(value), float(raw.get("CheckAttributeCompareVal", 0)), str(raw.get("CheckAttributeCompareType", "ECT_Equal")))

func _emit_buff_style(actor: DungeonActor, raw: Dictionary, name: String, loop := false) -> void:
	if name.is_empty(): return
	var follows_rotation = bool(raw.get("DummyData", {}).get("FollowRotation", false))
	var before = spawned
	trigger(actor, {"EffectName": name, "DummyData": raw.get("DummyData", {}), "DummyType": "EEDT_DummyChild" if follows_rotation else "EEDT_DummyPosFollow_WithoutRotate", "IsLoop": loop, "SpeedScaleByOwnerActionSpeed": false}, -1, Vector3.INF, false)
	if spawned > before and loop:
		active.back().duration = INF
		active.back().clock_sequence = -1

func _set_embedded_effect(actor: DungeonActor, name: String, enabled: bool) -> void:
	var binding: Dictionary = _wolf_embedded.get("bindings", {}).get(name, {})
	if binding.is_empty(): return
	var existing := -1
	for index in active.size():
		if active[index].actor.get_ref() == actor and active[index].get("embedded_effect", "") == name:
			existing = index
			break
	if not enabled:
		if existing >= 0: _recycle(existing)
		return
	if existing >= 0: return
	var anchor := _anchor(actor, {"DummyData": {"CustomDummyName": str(binding.bone)}})
	if anchor == actor: return
	var parent_transform := Transform3D.IDENTITY
	for item in binding.get("parent_transform_chain", []):
		var q: Dictionary = item.get("rotation", {})
		var rotation_value := Quaternion(float(q.get("x", 0)), float(q.get("y", 0)), float(q.get("z", 0)), float(q.get("w", 1))).normalized()
		parent_transform *= Transform3D(Basis(rotation_value).scaled(_source_dimensions(item.get("scale", {}))), DungeonWorld.vector(item.get("position", {})))
	var before := spawned
	emit_effect(actor, name, anchor.to_global(parent_transform.origin), Vector3.ONE, INF, anchor, false, -1, true, false, true)
	if spawned == before: return
	var effect: Dictionary = active.back()
	# The descriptor includes the disabled effect root's original TRS; only its parent is attached here.
	effect.root.global_transform = anchor.global_transform * parent_transform
	effect.offset = parent_transform.origin
	effect.follow_rotation = true
	effect.rotation_offset = parent_transform.basis
	effect.duration = INF
	effect.clock_sequence = -1
	effect["embedded_effect"] = name
	effect["buff_style"] = "embedded:" + name

func sync_buffs(actors: Array) -> void:
	for actor in actors:
		if is_instance_valid(actor) and not actor.dead: sync_actor_buffs(actor)
	for id in _buff_styles.keys():
		var actor = _buff_styles[id].actor.get_ref()
		if not is_instance_valid(actor) or actor.dead: _buff_styles.erase(id)

func sync_actor_buffs(actor: DungeonActor) -> void:
	# A source common-effect buff shares its owner's lifetime without modifying combat.
	var actor_id = actor.get_instance_id()
	var previous: Dictionary = _buff_styles.get(actor_id, {}).get("styles", {})
	if actor.combat.statuses.is_empty() and previous.is_empty(): return
	var current: Dictionary = {}
	var live: Dictionary = {}
	for effect in active:
		if effect.actor.get_ref() == actor and effect.has("buff_style"): live[effect.buff_style] = true
	for owner_id in actor.combat.statuses:
		if actor.combat.buff_layers(str(owner_id)) <= 0: continue
		var styles = _buff_style_definitions(actor, str(owner_id))
		for style_id in styles:
			var raw: Dictionary = styles[style_id]
			if not _buff_style_enabled(actor, raw): continue
			if not actor.is_player and actor.combat.enemy_id == 13001:
				for name in raw.get("ActiveExistEffectList", []):
					var embedded_identity := "embedded:" + str(name)
					current[embedded_identity] = {"embedded_effect": name}
					if not live.has(embedded_identity): _set_embedded_effect(actor, str(name), true)
			var keep = str(raw.get("KeepEffect", raw.get("CounterFx", "")))
			var start = str(raw.get("StartEffect", ""))
			if keep.is_empty() and start.is_empty(): continue
			var identity = str(style_id)
			if current.has(identity): continue
			current[identity] = raw
			if not previous.has(identity):
				_emit_buff_style(actor, raw, start)
				play_sound(str(raw.get("StartSound", {}).get("SoundName", "")), actor.position, actor)
			if live.has(identity): continue
			var before = spawned
			_emit_buff_style(actor, raw, keep, true)
			if spawned > before: active.back()["buff_style"] = identity
	for identity in previous:
		if current.has(identity): continue
		for index in range(active.size() - 1, -1, -1):
			if active[index].actor.get_ref() == actor and active[index].get("buff_style", "") == identity: _recycle(index)
		_emit_buff_style(actor, previous[identity], str(previous[identity].get("EndEffect", "")))
		play_sound(str(previous[identity].get("EndSound", {}).get("SoundName", "")), actor.position, actor)
	_buff_styles[actor_id] = {"actor": weakref(actor), "styles": current}

func play_sound(name: String, point: Vector3, actor: DungeonActor, sequence := -1, gain := 1.0, pitch := 1.0, priority := false, category := "") -> void:
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
		sound_queue.append({"delay": float(layer.get("delay", 0)), "layer": layer, "bus": DungeonStyle.audio_bus(key, layer, category), "point": point, "actor": weakref(actor), "sequence": sequence, "gain": gain, "pitch": pitch * variation, "priority": priority, "clip": _sound_serial % maxi(1, layer.get("clips", []).size())})

func _process(delta: float) -> void:
	delta *= simulation_scale
	if not suspended and has_pending_preparation(): prepare_step()
	for voice in voices: voice.stream_paused = suspended or not audio_enabled
	for effect in active:
		var rate = _effect_clock_rate(effect)
		effect.sparks.speed_scale = 0 if suspended else rate * simulation_scale
		var particle_rate = rate * float(effect.get("playback_speed", 1))
		if effect.authored: effect.authored.advance(delta * particle_rate, suspended or particle_rate <= 0, particle_rate * simulation_scale)
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
				effect.root.global_position = anchor.global_position + effect.world_offset if effect.get("position_without_rotate", false) else anchor.to_global(effect.offset)
				if effect.follow_rotation: effect.root.global_basis = anchor.global_basis * effect.rotation_offset
				if float(effect.get("detach_after", 0)) > 0 and effect.age >= float(effect.detach_after):
					effect.follow = null
					effect.follow_rotation = false
			else:
				_recycle(i)
				continue
		var fraction = effect.age / effect.duration
		if effect.body_burst: effect.burst_material.set_shader_parameter("phase", fraction)
		if effect.mesh.visible:
			var color: Color = effect.color
			color.a = 0.65 if effect.important else (0.8 + sin(effect.age * 18) * 0.2) if effect.loop else 1.0 - fraction
			color.a *= float(effect.get("settings_opacity", 1.0))
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
			voice.bus = StringName(entry.get("bus", &"Effects"))
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
		_active_particles -= authored.particle_count
		_active_emitters -= authored.emitters.size()
		authored.stop()
		effect.root.remove_child(authored)
		_store_authored(effect.cache_key, authored)
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
		if not entry.has("buff_style") and not entry.get("detached", false) and entry.actor.get_ref() == actor and (keep_sequence == -2 or (entry.sequence >= 0 and entry.sequence != keep_sequence)): _recycle(i)

func clear() -> void:
	_buff_styles.clear()
	_preparation.clear()
	_preparation_keys.clear()
	_preparation_head = 0
	for entry in _warm_particles: entry.node.free()
	_warm_particles.clear()
	if _warm_viewport: _warm_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	for entry in telegraphs:
		var actor = entry.actor.get_ref()
		if actor: actor.clear_telegraph_aim()
	while not telegraphs.is_empty(): _remove_telegraph(telegraphs.size() - 1)
	while not active.is_empty(): _recycle(active.size() - 1)
	sound_queue.clear()
	for voice in voices: voice.stop()

func release_room_resources() -> void:
	clear()
	for entries in authored_pool.values():
		for entry in entries: entry.free()
	authored_pool.clear()
	_authored_pool_size = 0
	_authored_pool_limit = FEEL.effect_budget
	for template in _authored_templates.values(): template.free()
	_authored_templates.clear()
	texture_cache.clear()
	sound_cache.clear()
	for voice in voices: voice.stream = null
	for entry in pool:
		var mesh: MeshInstance3D = entry.mesh
		if mesh.material_override is StandardMaterial3D:
			mesh.material_override.albedo_texture = null

func _exit_tree() -> void:
	release_room_resources()
