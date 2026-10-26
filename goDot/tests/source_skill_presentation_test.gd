extends SceneTree

const Presentation = preload("res://scripts/presentation/combat_presentation.gd")
const SourceImpact = preload("res://scripts/presentation/source_heavy_impact.gd")
var checks := 0
var failures: Array[String] = []
var projectile_cases := 0
var spirit_cases := 0
var delayed_cases := 0
var preload_effects := 0
var preload_sounds := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var presentation := Presentation.new()
	root.add_child(presentation)
	presentation.configure({})
	presentation.set_process(false)
	presentation.audio_enabled = false
	var actor := DungeonActor.new()
	actor.set_physics_process(false)
	actor.combat = DungeonCombat.new()
	actor.combat.configure_enemy(53001)
	root.add_child(actor)
	var visual := Node3D.new()
	root.add_child(visual)
	var boss_groups: Dictionary = {}
	for enemy in actor.combat.catalog.enemies:
		if str(enemy.get("rank", "")) == "Boss": boss_groups[str(enemy.group)] = true
	for action in actor.combat.catalog.actions:
		if not boss_groups.has(str(action.group)): continue
		for hit in action.get("hits", []):
			if not hit.get("enabled", false): continue
			var raw := DungeonWorld._raw_definition(hit)
			if str(raw.get("EntityType", "")) != "EET_Physical": continue
			if str(raw.get("EntityProperty", {}).get("ModlePrefab", "")).is_empty(): continue
			_projectile(presentation, actor, visual, hit, str(action.group) + "/" + str(action.id))
			projectile_cases += 1
	actor.is_player = true
	actor.combat.configure(null, null, 1)
	var target := DungeonActor.new()
	target.set_physics_process(false)
	target.combat = DungeonCombat.new()
	target.combat.configure_enemy(13001)
	root.add_child(target)
	for summon in actor.combat.catalog.summons:
		if str(summon.hit.get("actType", "")) != "Spirit": continue
		var raw: Dictionary = summon.raw_data
		var hit := {"definition": summon.hit, "summon_id": str(summon.id), "impact_position": [3, 0.7, 4]}
		if str(raw.get("EntityType", "")) == "EET_Physical":
			_projectile(presentation, actor, visual, summon.hit, str(summon.id), str(summon.id))
		var plan := SourceImpact.collect(hit, actor.combat)
		presentation.clear()
		presentation.impact(actor, target, hit)
		check(presentation.active.size() == plan.effects.size(), "Spirit %s emits its source impact count without a substitute burst" % summon.id)
		for index in mini(plan.effects.size(), presentation.active.size()):
			var effect: Dictionary = presentation.active[index]
			check(effect.source_only and effect.key == presentation._key(plan.effects[index].name), "Spirit %s keeps the source impact prefab" % summon.id)
			check(effect.authored != null and effect.authored.scale.is_equal_approx(plan.effects[index].scale), "Spirit %s keeps source impact scale" % summon.id)
		spirit_cases += 1
	_delayed_and_buff(presentation, actor)
	_modifier_styles(presentation, actor)
	_source_preload(presentation, actor)
	check(projectile_cases >= 60 and spirit_cases >= 15, "All available Boss projectile and Spirit damage definitions are exercised")
	var report := {"apk_sha256": "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505", "checks": checks, "failures": failures, "boss_projectiles": projectile_cases, "spirit_damage_definitions": spirit_cases, "delayed_entities": delayed_cases, "preloaded_effect_dependencies": preload_effects, "preloaded_sound_dependencies": preload_sounds, "scope": "Recovered source dispatch, projectile/end scaling, creation versus activation effects, nested range Buff styles, impact payloads, attack-ID-scoped style replacements with creation-time snapshots and all 33 spirit ability media closures. Headless checks do not establish Unity shader equivalence or device FPS."}
	FileAccess.open("res://reports/source-skill-presentation-tests.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t") + "\n")
	print("SOURCE_SKILL_PRESENTATION ", JSON.stringify(report))
	# Let particle work finish before the SceneTree destroys its renderer resources.
	presentation.clear()
	await process_frame
	presentation.queue_free()
	actor.queue_free()
	target.queue_free()
	visual.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _projectile(presentation: Node3D, actor: DungeonActor, visual: Node3D, definition: Dictionary, label: String, summon_id := "") -> void:
	presentation.clear()
	var raw := DungeonWorld._raw_definition(definition)
	var state := DungeonProjectile.new()
	state.hit = {"definition": definition, "summon_id": summon_id}
	state.entity = raw.get("EntityProperty", {})
	state.motion_type = str(raw.get("MotionAnimatorType", ""))
	state.position = Vector3(3, 0, 4)
	state.radius = 9.0
	state.lifetime = 2.0
	presentation.attack_emitted(actor, state.hit, state.position)
	presentation.projectile_started(actor, state, visual)
	var name := str(state.entity.get("ModlePrefab", ""))
	if name.is_empty(): name = str(state.entity.get("EffectTriggerDef", {}).get("EffectName", ""))
	if not name.is_empty():
		check(not presentation.active.is_empty(), label + " projectile has its source visual")
		if not presentation.active.is_empty():
			var effect: Dictionary = presentation.active.back()
			var size := DungeonWorld.vector(state.entity.get("ModlePrefabSize", {}))
			if name == str(state.entity.get("EffectTriggerDef", {}).get("EffectName", "")) and str(state.entity.get("ModlePrefab", "")).is_empty(): size = DungeonWorld.vector(state.entity.get("EffectTriggerDef", {}).get("Scale", {}))
			if size.is_zero_approx(): size = Vector3.ONE
			check(effect.authored != null and effect.authored.scale.is_equal_approx(size), label + " uses source model scale independently of collision radius")
			check(effect.source_only and effect.key == presentation._key(name), label + " retains source style and exact prefab")
	presentation.clear()
	presentation.projectile_ended(actor, state)
	var end := str(state.entity.get("EntityEndEffect", ""))
	if end.is_empty():
		check(presentation.active.is_empty(), label + " has no invented ending effect")
	else:
		check(not presentation.active.is_empty(), label + " emits its source ending effect")
		if not presentation.active.is_empty():
			var effect: Dictionary = presentation.active.back()
			var size := DungeonWorld.vector(state.entity.get("EntityEndEffectScale", {}))
			check(effect.source_only and effect.key == presentation._key(end) and effect.authored.scale.is_equal_approx(Vector3.ONE if size.is_zero_approx() else size), label + " ending effect uses its source scale")

func _delayed_and_buff(presentation: Node3D, actor: DungeonActor) -> void:
	actor.is_player = false
	actor.combat.configure_enemy(53001)
	for action in actor.combat.catalog.actions:
		if str(action.group) not in ["ActGroup_mojiehua", "ActGroup_dilong", "ActGroup_Chimera"]: continue
		for definition in action.get("hits", []):
			if not definition.get("enabled", false): continue
			var raw := DungeonWorld._raw_definition(definition)
			var entity: Dictionary = raw.get("EntityProperty", {})
			var delayed: Dictionary = entity.get("EffectDelayTriggerDef", {})
			if str(delayed.get("EffectName", "")).is_empty(): continue
			var hit := {"definition": definition, "sequence": -1}
			presentation.clear()
			presentation.attack_emitted(actor, hit, Vector3(3, 0, 4))
			var immediate := str(entity.get("EffectTriggerDef", {}).get("EffectName", ""))
			if immediate != str(delayed.EffectName): check(not presentation.active.any(func(effect): return effect.key == presentation._key(delayed.EffectName)), "%s creation does not play its delayed effect early" % action.id)
			presentation.clear()
			presentation.entity_activated(actor, hit, Vector3(3, 0, 4), Vector3.RIGHT)
			check(presentation.active.any(func(effect): return effect.key == presentation._key(delayed.EffectName)), "%s activation emits its delayed source effect" % action.id)
			if not presentation.active.is_empty():
				var effect: Dictionary = presentation.active.back()
				var expected := Vector3(3, 0, 4) + Basis(Vector3.UP, PI * 0.5) * DungeonWorld.vector(delayed.get("Position", {}))
				check(effect.root.global_position.is_equal_approx(expected), "%s activation retains its frozen entity position and facing" % action.id)
			delayed_cases += 1
	presentation.clear()
	var magnetized: Dictionary = actor.combat._buff_index["50203402"].raw_data
	presentation.buff_effect(actor, {"id": "50203402", "definition": magnetized})
	check(presentation.active.size() == 1 and presentation.active[0].key == "26091701_fx_buff_rockthunderspirit_lightning", "Magnetized range Buff emits nested EffectName1")
	check(presentation.active[0].source_only and presentation.active[0].authored.scale == Vector3.ONE, "Range Buff keeps its zero-scale prefab default")
	check(presentation.active[0].clock_sequence == -1, "A periodic Buff effect is independent of the owner's current action speed")

func _modifier_styles(presentation: Node3D, actor: DungeonActor) -> void:
	actor.is_player = true
	actor.combat.configure(null, null, 1)
	var definition: Dictionary = actor.combat._summon_index["119905"].hit
	var source := JSON.stringify(definition)
	var original := "24081201_fx_axe_satk_talent"
	var replacement := "24072901_fx_buff_thunderfirespirit_lightning"
	var before_buff := {"definition": definition}
	presentation.clear()
	presentation.attack_emitted(actor, before_buff, Vector3.ZERO)
	presentation.entity_activated(actor, before_buff, Vector3.ZERO)
	check(presentation.active.size() == 1 and presentation.active[0].key == original, "Unmodified lightning keeps its source effect")
	actor.combat.add_buff("50202801")
	actor.combat.drain_events()
	var emitted := {"definition": definition}
	presentation.clear()
	presentation.attack_emitted(actor, emitted, Vector3.ZERO)
	presentation.entity_activated(actor, emitted, Vector3.ZERO)
	check(presentation.active.size() == 1 and presentation.active[0].key == replacement and presentation.active[0].source_only, "Thunder-fire modifier replaces the matching attack's exact detected effect")
	for attack_id in [1199051, 119904]:
		var raw := DungeonWorld._raw_definition(definition).duplicate(true)
		raw["Id"] = attack_id
		var changed := definition.duplicate(true)
		changed["raw"] = JSON.stringify(raw)
		var hit := {"definition": changed}
		presentation.clear()
		presentation.attack_emitted(actor, hit, Vector3.ZERO)
		presentation.entity_activated(actor, hit, Vector3.ZERO)
		check(presentation.active.size() == 1 and presentation.active[0].key == (replacement if attack_id == 1199051 else original), "Attack modifier honors its complete source ID list and leaves unrelated IDs intact: %d" % attack_id)
	presentation.clear()
	presentation.emit_effect(actor, original + ".prefab", Vector3.ZERO)
	check(presentation.active.size() == 1 and presentation.active[0].key == original, "A source attack modifier does not become a global prefab alias")
	actor.combat.remove_buff("50202801")
	presentation.clear()
	presentation.entity_activated(actor, emitted, Vector3.ZERO)
	check(presentation.active.size() == 1 and presentation.active[0].key == replacement, "An emitted entity retains its creation-time replacement after the Buff ends")
	actor.combat.add_buff("50202801")
	presentation.clear()
	presentation.entity_activated(actor, before_buff, Vector3.ZERO)
	check(presentation.active.size() == 1 and presentation.active[0].key == original, "A later Buff cannot replace an already emitted entity")
	check(JSON.stringify(definition) == source, "Style replacement preserves the imported source attack definition")

func _source_preload(presentation: Node3D, actor: DungeonActor) -> void:
	var followers: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/spirit_followers/catalog.json"))
	var effects: Dictionary = {}
	var sounds: Dictionary = {}
	var pending: Dictionary = {}
	var expected_buffs: Dictionary = {}
	var expected_effects: Dictionary = {}
	for binding in followers.ability_bindings.values():
		presentation._collect_media(binding.raw, actor.combat, effects, sounds, pending)
		_source_effect_references(binding.raw, expected_effects)
		for source in binding.get("source_chain", []):
			var address := str(source.get("address", ""))
			if address.begins_with("BuffCfg_["):
				expected_buffs["buff:" + address.trim_prefix("BuffCfg_[").trim_suffix("]")] = true
	var seen: Dictionary = {}
	while not pending.is_empty():
		var id := str(pending.keys()[0])
		var definition: Dictionary = pending[id]
		pending.erase(id)
		if seen.has(id): continue
		seen[id] = true
		check(not definition.is_empty(), "Spirit preload dependency exists in the source combat catalog: " + id)
		presentation._collect_media(definition, actor.combat, effects, sounds, pending)
		_source_effect_references(definition, expected_effects)
	for id in expected_buffs:
		check(seen.has(id), "Preloading follows the source ability's complete Buff chain: " + str(id))
	for key in expected_effects:
		var follower_owned: bool = followers.effects.has(key) and followers.followers.values().any(func(follower): return str(follower.prefab) == key)
		check(presentation.media.effects.has(key) or follower_owned, "Each named source spirit effect has an imported descriptor: " + str(key))
		if follower_owned: check(not followers.effects[key].get("layers", []).is_empty(), "Persistent companions retain their own prepared particle geometry: " + str(key))
		elif "enemyatkrange" not in key: check(effects.has(key), "Media preparation includes each source spirit effect reference: " + str(key))
	for key in effects:
		var definition: Dictionary = presentation.effect_definition(key)
		check(not definition.get("layers", []).is_empty() or not definition.get("models", []).is_empty(), "Spirit effect dependency retains source geometry: " + str(key))
	preload_effects = effects.size()
	preload_sounds = sounds.size()
	check(followers.ability_bindings.size() == 33 and preload_effects > 30 and preload_sounds > 5, "All 33 source abilities resolve their effect and sound preload graph")

func _source_effect_references(value: Variant, references: Dictionary) -> void:
	if value is Dictionary:
		for field in value:
			if field == "raw": continue
			var child: Variant = value[field]
			if child is String and child.ends_with(".prefab") and ("effect" in str(field).to_lower() or field in ["Prefab", "ModlePrefab"]): references[child.get_file().trim_suffix(".prefab").to_lower()] = true
			_source_effect_references(child, references)
	elif value is Array:
		for child in value: _source_effect_references(child, references)

func _effective_summon_scale(presentation: Node3D, actor: DungeonActor) -> void:
	actor.is_player = true
	actor.combat.configure(null, null, 1)
	for id in ["502032510", "502035510"]:
		var source: Dictionary = actor.combat._summon_index[id]
		var original := JSON.stringify(source)
		var sizes: Array[Vector3] = []
		for spirit_range in [0.0, 1000.0]:
			actor.combat.set_external_attributes({"SpiritRange": spirit_range})
			actor.combat._spawn_summon(id, actor.combat._clock, "summon_attack", 0, 0.0)
			var events: Array = actor.combat.drain_events().filter(func(event): return str(event.get("type", "")) == "summon" and str(event.get("id", "")) == id)
			check(events.size() == 1, "A source ground summon supplies one effective presentation definition: " + id)
			if events.is_empty(): continue
			var raw: Dictionary = events[0].definition.raw_data
			var size := DungeonWorld.vector(raw.get("PrefabScale", {}))
			sizes.append(size)
			presentation.clear()
			var token: int = presentation.summon_started(actor, raw, Vector3(3, 0, 4))
			check(token > 0 and not presentation.active.is_empty(), "The effective ground summon retains its source particle geometry: " + id)
			if not presentation.active.is_empty(): check(presentation.active.back().authored.scale.is_equal_approx(size), "Presentation applies the resolved source scale exactly once: " + id)
		check(sizes.size() == 2 and not sizes[0].is_equal_approx(sizes[1]), "SpiritRange changes the effective source ground scale at creation: " + id)
		check(JSON.stringify(source) == original, "Dynamic presentation scaling preserves the imported summon parameters: " + id)
	actor.combat.set_external_attributes({})
