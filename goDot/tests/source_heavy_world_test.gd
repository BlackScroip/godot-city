extends SceneTree

const Combat = preload("res://scripts/domain/combat.gd")
const Profiles = preload("res://scripts/presentation/impact_profiles.gd")
const SourceImpact = preload("res://scripts/presentation/source_heavy_impact.gd")
const Feedback = preload("res://scripts/presentation/hit_feedback.gd")
var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _actor(world: DungeonWorld, key: String, player := false) -> DungeonActor:
	var actor := DungeonActor.new()
	actor.is_player = player
	actor.combat = Combat.new()
	if player: actor.combat.configure(null, null, 3)
	else: actor.combat.configure_enemy(11001)
	actor.combat.actor_key = key
	actor.combat.defense = 0
	actor.combat.max_health = 100000
	actor.combat.health = actor.combat.max_health
	world.add_child(actor)
	actor.set_process(false)
	actor.set_physics_process(false)
	world.actors.append(actor)
	return actor

func _packet(source: DungeonActor, action: String, slot: int, emission: int) -> Dictionary:
	return {"definition": source.combat._action("ActGroup_playerchara", action).hits[0], "damage": 32.0, "uncritical_damage": 32.0, "critical_rate": 0.0, "critical_roll": 1.0, "action": action, "slot": slot, "sequence": source.combat._cast_sequence, "emission": emission, "impact_position": [1.0, 0.75, 2.0]}

func _run() -> void:
	var world := DungeonWorld.new()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.presentation.set_process(false)
	var player := _actor(world, "player", true)
	var target := _actor(world, "target")
	target.set_visual("")
	world.player = player
	target.position = Vector3(0, 0, -1)
	var baseline := Combat.new()
	baseline.configure_enemy(11001)
	baseline.defense = target.combat.defense
	baseline.max_health = target.combat.max_health
	baseline.health = target.combat.health
	var hit := _packet(player, "axe_satk_end", 4, 101)
	var independent := hit.duplicate(true)
	independent.source = player.combat
	var expected_damage := baseline.receive(independent, player.combat.effective_attack_power())
	var before_hp: float = target.combat.health
	world._apply_hit(player, target, hit)
	check(is_equal_approx(before_hp - target.combat.health, expected_damage) and expected_damage > 0, "Source-heavy world contact preserves independent damage settlement")
	check(is_zero_approx(player.combat.impact_pause) and is_zero_approx(target.combat.impact_pause), "Source-heavy contact adds no attacker or receiver FEEL pause")
	check(target.knockback_elapsed < 0 and is_zero_approx(target.combat.stagger_remaining) and target.velocity.is_zero_approx(), "Source-heavy contact adds no unconverted push, upper force or stagger")
	check(is_zero_approx(target.hurt_timer), "Source-heavy contact does not invent a material-flash duration")
	var feedback := Feedback.normalize(hit.definition)
	check(target._model_shake_active == feedback.hit_actions.any(func(action): return bool(action.model_shake)), "Source-heavy contact applies exactly the authored model-shake flag")
	check(world._camera_impulses.size() == feedback.camera_shakes.size(), "Heavy contact queues exactly the original hit-camera entries")
	for index in feedback.camera_shakes.size():
		var actual: Dictionary = world._camera_impulses[index]
		var expected: Dictionary = feedback.camera_shakes[index]
		check(actual.duration == expected.duration and actual.intensity == expected.intensity and actual.times == expected.times and actual.raw == expected.raw and not actual.has("amplitude"), "Hit-camera entry keeps source duration, intensity, count and raw payload")
	check(world._seen_blasts.is_empty(), "Source-heavy contact adds no generic explosion")
	var plan := SourceImpact.collect(hit, player.combat)
	check(world.presentation.active.size() == plan.effects.size(), "Source-heavy contact creates only source hit effects")
	for index in world.presentation.active.size():
		var effect: Dictionary = world.presentation.active[index]
		check(not effect.body_burst and effect.root.position.is_equal_approx(Vector3(1, 0.75, 2)), "Original hit effects retain the hit position without a generic burst or camera-facing offset")
		check(effect.key == world.presentation._effect_key(player, plan.effects[index].name), "Actual world presentation uses the original named hit effect")
		check(effect.authored != null and effect.authored.scale.is_equal_approx(plan.effects[index].scale), "Original hit effects retain prefab/default scale")
		_neutral_material(effect, "Original source hit effects retain neutral brightness and source colors")
	check(not world.presentation.sound_queue.is_empty(), "Source-heavy contact retains its nonempty source audio")
	var expected_layers: Array = []
	for name in plan.sounds:
		var layers: Array = world.presentation.media.get("audio", {}).get(world.presentation._key(name), [])
		for layer in layers.slice(0, 3): expected_layers.append(layer)
	check(world.presentation.sound_queue.map(func(sound): return sound.layer) == expected_layers, "Actual world audio queue contains exactly the source sound layers")
	for sound in world.presentation.sound_queue:
		check(is_equal_approx(float(sound.pitch), 1.0) and is_equal_approx(float(sound.gain), 1.0), "Source-heavy audio avoids custom heavy pitch, gain and random variation")
	var first_effects: int = world.presentation.spawned
	var first_sounds: int = world.presentation.sound_queue.size()
	var blank := {"slot": 4, "action": "axe_satk_end", "definition": {}, "resolved_damage": 0.0, "source_key": "player", "emission": 102}
	world._on_impact(blank, target)
	check(world.presentation.spawned == first_effects and world.presentation.sound_queue.size() == first_sounds, "Empty source feedback adds no substitute hit effect or audio")
	world.presentation.clear()
	world._camera_impulses.clear()
	var orb := _packet(player, "orb_satk_loop_1", 4, 103)
	world._apply_hit(player, target, orb)
	check(target.knockback_elapsed < 0 and is_zero_approx(target.combat.stagger_remaining) and is_zero_approx(player.combat.impact_pause), "Source orb loop does not add the former 0.08-unit attraction")
	check(Profiles.resolve(orb, player.combat).source_feedback.hit_actions[0].push_power == -20, "Original orb attraction power remains in its source units")
	_delayed_lineage(world, player)
	_source_styles(world, player)
	_source_projectiles(world, player)
	_source_summons(world, player)
	world.presentation.clear()
	world._camera_impulses.clear()
	player.combat.clear_impact_state()
	target.clear_impact_state()
	player.combat._current_slot = 4
	var normal := _packet(player, "sword_atk1", 0, 104)
	world._apply_hit(player, target, normal)
	check(not Profiles.resolve(normal, player.combat).get("source_only", false) and target.combat.impact_pause > 0, "An earlier normal attack retains its normal presentation despite the owner's later heavy input")
	check(target.knockback_elapsed < 0 and target.combat.stagger_remaining == 0, "Normal presentation cannot bypass source monster hit resistance")
	world.free()
	var result := {"checks": checks, "failures": failures, "scope": "Real world/presentation source-heavy settlement, source-only feedback and delayed/transient lineage."}
	FileAccess.open("res://reports/source-heavy-world-tests.json", FileAccess.WRITE).store_string(JSON.stringify(result, "\t") + "\n")
	print("SOURCE_HEAVY_WORLD ", JSON.stringify(result))
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _delayed_lineage(world: DungeonWorld, player: DungeonActor) -> void:
	player.combat._current_slot = 0
	player.combat.current_action = "sword_atk1"
	var provenance := {"action": "axe_satk_end", "slot": 4, "sequence": player.combat._cast_sequence - 1}
	world._spawn_from_definition(player, {"AddSummonUnitId": "6000111", "AddSummonUnitQuantity": 1}, Vector3(3, 0, 2), provenance)
	var pending: Array = player.combat.drain_events().filter(func(event): return event.type == "summon")
	check(not pending.is_empty(), "Delayed child uses the real source summon path")
	if pending.is_empty(): return
	var event: Dictionary = pending.back()
	check(event.origin.get("_source_heavy", false) and Profiles.is_source_heavy(event, player.combat), "Child emitted during a later normal action retains heavy origin provenance")
	world._consume(player, event)
	check(not world.summon_units.is_empty() and world.summon_units.back().source_heavy, "Runtime summon unit stores its heavy origin")
	var missile := {"action": "sword_atk1", "slot": 0, "sequence": player.combat._cast_sequence - 1, "origin": {"_source_heavy": true}, "summon_id": "4001021", "definition": player.combat._summon_index["4001021"].hit}
	world._projectile(player, missile)
	var data: Dictionary = JSON.parse_string(JSON.stringify(world.transient_snapshot()))
	check(data.summons.back().source_heavy, "Serialized transient summon retains heavy origin")
	check(data.projectiles.back().hit.origin.get("_source_heavy", false), "Serialized delayed projectile retains heavy origin")
	for unit in world.summon_units.duplicate(): world._dispose_summon(unit, false)
	for projectile in world.projectiles: world._recycle_projectile(projectile)
	world.projectiles.clear()
	world.restore_transients({})
	world.restore_transients(data)
	check(not world.summon_units.is_empty() and world.summon_units.back().source_heavy and Profiles.is_source_heavy(world.summon_units.back(), player.combat), "Restored summon remains source-heavy without depending on the player's current slot")
	check(world.projectiles.size() == 1 and Profiles.is_source_heavy(world.projectiles[0].state.hit, player.combat), "Restored projectile retains source-heavy lineage across a later normal action")
	check(world.presentation.active.all(func(effect): return effect.source_only), "Restored heavy summon visuals receive source provenance before creation")

func _neutral_material(effect: Dictionary, message: String) -> void:
	check(effect.authored != null and effect.authored.emitters.all(func(emitter): return not emitter.node.material_override is ShaderMaterial or (is_equal_approx(float(emitter.node.material_override.get_shader_parameter("visual_gain")), 1.0) and not emitter.node.material_override.get_shader_parameter("crimson_blade"))), message)

func _source_styles(world: DungeonWorld, player: DungeonActor) -> void:
	var presentation: Node3D = world.presentation
	var metadata: Dictionary = player.combat._heavy_catalog
	player.combat._current_slot = 0
	player.combat.current_action = "sword_atk1"
	var effects := 0
	for action in metadata.actions:
		for command in player.combat._action("ActGroup_playerchara", action).events:
			if not command.get("enabled", false) or command.type != "EET_PlayEffect": continue
			presentation.clear()
			var definition: Dictionary = DungeonWorld._raw_definition(command).get("EffectTriggerDef", {})
			var name := str(definition.get("EffectName", ""))
			var key: String = presentation._effect_key(player, name)
			var media: Dictionary = presentation.media.effects.get(key, {})
			presentation.command(player, {"action": action, "slot": 0, "sequence": player.combat._cast_sequence - 1, "command": command})
			if media.get("layers", []).is_empty() and media.get("models", []).is_empty():
				check(presentation.active.is_empty(), "%s missing source command does not create a substitute quad" % action)
				continue
			effects += 1
			check(presentation.active.size() == 1 and presentation.active.back().source_only, "%s delayed source action creates its exact source effect" % action)
			if presentation.active.is_empty(): continue
			var effect: Dictionary = presentation.active.back()
			var anchor: Node3D = presentation._anchor(player, definition)
			var expected := anchor.global_position + Basis(Vector3.UP, atan2(player.facing.x, player.facing.z)) * DungeonWorld.vector(definition.get("Position", {}))
			check(effect.root.global_position.is_equal_approx(expected), "%s source effect has no extra vertical or sword offset" % action)
			var euler := Vector3(0, atan2(player.facing.x, player.facing.z), 0) + DungeonWorld.vector(definition.get("Euler", {})) * PI / 180.0
			check(effect.root.rotation.is_equal_approx(euler), "%s source effect keeps its source rotation without an added half turn" % action)
			var dimensions := DungeonWorld.vector(definition.get("Scale", {}))
			if dimensions.is_zero_approx(): dimensions = Vector3.ONE
			check(effect.authored != null and effect.authored.scale.is_equal_approx(dimensions), "%s source effect retains its complete explicit scale" % action)
			_neutral_material(effect, "%s source material keeps neutral brightness and original colors" % action)
	check(effects > 0, "Source transform regression exercises enabled APK heavy effect commands")
	presentation.clear()
	var slash: Dictionary = player.combat._action("ActGroup_playerchara", "sword_atk1").hits[0]
	check(presentation._sword_slash(presentation._key(DungeonWorld._raw_definition(slash).get("EntityProperty", {}).get("EffectTriggerDef", {}).get("EffectName", ""))), "Sword offset regression uses an actual APK slash trigger")
	if not slash.is_empty():
		var definition: Dictionary = DungeonWorld._raw_definition(slash).EntityProperty.EffectTriggerDef
		var event := {"action": "sword_atk1", "slot": 0, "sequence": player.combat._cast_sequence - 1, "origin": {"_source_heavy": true}, "definition": slash}
		presentation.attack_emitted(player, event, player.position)
		var effect: Dictionary = presentation.active.back()
		var offset := DungeonWorld.vector(definition.get("Position", {}))
		var anchor: Node3D = presentation._anchor(player, definition)
		var expected := anchor.global_position + Basis(Vector3.UP, atan2(player.facing.x, player.facing.z)) * offset
		check(effect.source_only and effect.root.global_position.is_equal_approx(expected), "A delayed source-derived sword slash omits the custom 0.55 forward and 0.08 vertical offsets")
		var euler := Vector3(0, atan2(player.facing.x, player.facing.z), 0) + DungeonWorld.vector(definition.get("Euler", {})) * PI / 180.0
		check(effect.root.rotation.is_equal_approx(euler), "A delayed source-derived sword slash omits the custom PI rotation")
		_neutral_material(effect, "A source-derived sword slash does not turn crimson or dim")
		presentation.clear()
		player.combat._current_slot = 4
		player.combat.current_action = "sword_satk_normal_ready"
		event.erase("origin")
		presentation.attack_emitted(player, event, player.position)
		effect = presentation.active.back()
		offset.z += 0.55
		expected = player.position + offset + Vector3.UP * 0.08
		check(not effect.source_only and effect.root.global_position.is_equal_approx(expected), "An earlier normal sword hit trigger retains its own presentation while the owner starts a heavy action")
	presentation.clear()
	var name := "24080201_fx_sword_satk_drawknife"
	presentation._summon_style(player, name, Vector3.ZERO, Vector3.ONE, true)
	check(presentation.active.back().authored.get_children().any(func(node): return node.get_meta("source_layer", "") == "24080201_drawknife_ring"), "Source drawknife restores its authored ring emitter")
	presentation.clear()
	presentation._summon_style(player, name, Vector3.ZERO)
	check(not presentation.active.back().authored.get_children().any(func(node): return node.get_meta("source_layer", "") == "24080201_drawknife_ring"), "Normal presentation keeps its separate emitter suppression template")
	presentation.clear()
	presentation.media.effects["source_texture_only_fixture"] = {"textures": presentation.media.effects["23101901_fx_axe_atk_hit"].get("textures", []), "layers": [], "models": []}
	presentation._summon_style(player, "source_texture_only_fixture", Vector3.ZERO, Vector3.ONE, true)
	check(presentation.active.is_empty(), "A texture list without authored geometry does not become a source effect quad")
	presentation.media.effects.erase("source_texture_only_fixture")

func _source_projectiles(world: DungeonWorld, player: DungeonActor) -> void:
	var presentation: Node3D = world.presentation
	for projectile in world.projectiles: world._recycle_projectile(projectile)
	world.projectiles.clear()
	var count := 0
	for action in player.combat._heavy_catalog.actions:
		for definition in player.combat._action("ActGroup_playerchara", action).hits:
			if not definition.get("enabled", false) or DungeonWorld._raw_definition(definition).get("EntityType", "") != "EET_Physical": continue
			presentation.clear()
			world._projectile(player, {"definition": definition, "action": action, "slot": 4, "sequence": player.combat._cast_sequence - 1})
			var projectile: Dictionary = world.projectiles.back()
			var state: DungeonProjectile = projectile.state
			check(not projectile.visual.visible, "%s heavy projectile hides the fallback sphere anchor" % action)
			for effect in presentation.active:
				count += 1
				var prefab := str(state.entity.get("ModlePrefab", ""))
				var trigger: Dictionary = state.entity.get("EffectTriggerDef", {})
				var name := prefab if not prefab.is_empty() else str(trigger.get("EffectName", ""))
				check(effect.key == presentation._effect_key(player, name) and effect.source_only and effect.authored != null and effect.root.is_visible_in_tree(), "%s projectile shows the named APK visual independently of its hidden sphere" % action)
				check(effect.follow != null and effect.follow.get_ref() == projectile.visual, "%s source projectile visual retains its motion anchor" % action)
				var dimensions := DungeonWorld.vector(state.entity.get("ModlePrefabSize", {})) if not prefab.is_empty() else DungeonWorld.vector(trigger.get("Scale", {}))
				if dimensions.is_zero_approx(): dimensions = Vector3.ONE
				check(effect.authored.scale.is_equal_approx(dimensions), "%s source projectile scale does not derive from collision radius" % action)
				_neutral_material(effect, "%s source projectile has neutral material gain" % action)
			presentation.clear()
			presentation.projectile_ended(player, state)
			for effect in presentation.active:
				check(effect.source_only and effect.key == presentation._effect_key(player, str(state.entity.get("EntityEndEffect", ""))), "%s projectile ending uses only its exact named source effect" % action)
				var dimensions := DungeonWorld.vector(state.entity.get("EntityEndEffectScale", {}))
				if dimensions.is_zero_approx(): dimensions = Vector3.ONE
				check(effect.authored.scale.is_equal_approx(dimensions), "%s projectile ending keeps its serialized scale independently of collision radius" % action)
				_neutral_material(effect, "%s projectile ending keeps original colors and brightness" % action)
			presentation.clear()
			world._recycle_projectile(projectile)
			world.projectiles.clear()
	check(count > 0, "Projectile style regression exercises named APK heavy projectile visuals")
	var state := DungeonProjectile.new()
	state.hit = {"action": "sword_atk1", "slot": 0, "origin": {"_source_heavy": true}}
	state.position = Vector3(2, 1, 4)
	state.entity = {"ModlePrefab": "missing_source_projectile.prefab", "EntityEndEffect": "missing_source_ending.prefab"}
	world._add_projectile_visual(state, player)
	check(not world.projectiles.back().visual.visible and presentation.active.is_empty(), "An unavailable exact source projectile creates no sphere or substitute effect")
	presentation.projectile_ended(player, state)
	check(presentation.active.is_empty(), "An unavailable exact source ending creates no substitute effect")
	world._recycle_projectile(world.projectiles.back())
	world.projectiles.clear()
	state = DungeonProjectile.new()
	state.hit = {"action": "sword_atk1", "slot": 0, "origin": {"_source_heavy": true}}
	state.entity = {}
	world._add_projectile_visual(state, player)
	presentation.projectile_ended(player, state)
	check(not world.projectiles.back().visual.visible and presentation.active.is_empty(), "Empty source projectile and ending definitions create no substitute graphics")
	state.entity = {"EntityEndEffect": "23101901_fx_axe_atk_hit.prefab"}
	state.radius = 4.0
	presentation.projectile_ended(player, state)
	var effect: Dictionary = presentation.active.back()
	check(effect.authored.scale.is_equal_approx(Vector3.ONE), "A named source ending uses its prefab scale even with a large collision radius")
	_neutral_material(effect, "Source projectile endings retain original material brightness")
	world._recycle_projectile(world.projectiles.back())
	world.projectiles.clear()
	presentation.clear()
	state = DungeonProjectile.new()
	state.hit = {"action": "sword_atk1", "slot": 0}
	state.entity = {}
	world._add_projectile_visual(state, player)
	check(world.projectiles.back().visual.visible and not presentation.active.back().source_only, "Normal projectiles retain their existing presentation regardless of the owner's current heavy slot")
	world._recycle_projectile(world.projectiles.back())
	world.projectiles.clear()
	presentation.clear()

func _source_summons(world: DungeonWorld, player: DungeonActor) -> void:
	var presentation: Node3D = world.presentation
	for unit in world.summon_units.duplicate(): world._dispose_summon(unit, false)
	presentation.clear()
	var definition: Dictionary = player.combat._summon_index["115101"]
	world._create_summon(player, {"id": "115101", "definition": definition, "lifetime": 1.0, "source_heavy": true, "action": "sword_atk1", "slot": 0})
	check(not presentation.active.is_empty() and presentation.active.all(func(effect): return effect.source_only), "Heavy-derived summon prefab and creation styles receive source-only presentation")
	for effect in presentation.active: _neutral_material(effect, "Heavy-derived summon keeps original colors and brightness")
	for unit in world.summon_units.duplicate(): world._dispose_summon(unit, false)
	presentation.clear()
	var pickup: Dictionary = player.combat._summon_index["240700"].duplicate(true)
	pickup.raw_data.Prefab = "missing_source_pickup.prefab"
	pickup.raw_data.InitEffect = ""
	world._create_summon(player, {"id": "240700", "definition": pickup, "lifetime": 1.0, "source_heavy": true, "action": "sword_atk1", "slot": 0})
	check(not world.summon_units.back().has("visual") and presentation.active.is_empty(), "A missing source-heavy pickup prefab does not create a replacement sprite")
	for unit in world.summon_units.duplicate(): world._dispose_summon(unit, false)
	presentation.clear()
