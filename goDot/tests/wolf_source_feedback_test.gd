extends SceneTree

const Profiles = preload("res://scripts/presentation/impact_profiles.gd")
const Feedback = preload("res://scripts/presentation/hit_feedback.gd")
const SourceImpact = preload("res://scripts/presentation/source_heavy_impact.gd")
var checks := 0
var failures: Array[String] = []
var hit_cases := 0
var projectile_cases := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _actor(world: DungeonWorld, id: int, key: String) -> DungeonActor:
	var actor := DungeonActor.new()
	actor.actor_id = id
	actor.is_player = id == 0
	actor.combat = DungeonCombat.new()
	if actor.is_player: actor.combat.configure()
	else: actor.combat.configure_enemy(id)
	actor.combat.actor_key = key
	actor.combat.defense = 0
	actor.combat.max_health = 1000000
	actor.combat.health = actor.combat.max_health
	world.add_child(actor)
	actor.set_process(false)
	actor.set_physics_process(false)
	actor.set_visual("")
	world.actors.append(actor)
	return actor

func _run() -> void:
	var world := DungeonWorld.new()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.presentation.set_process(false)
	var wolf := _actor(world, 13001, "wolf")
	var target := _actor(world, 0, "player")
	world.player = target
	target.position = Vector3(0, 0, 4)
	check(Profiles.is_source_wolf({}, wolf.combat), "First wolf boss uses its APK feedback")
	check(not Profiles.is_source_heavy({}, wolf.combat), "Wolf source policy does not classify it as a player heavy attack")
	var other := DungeonCombat.new()
	other.configure_enemy(11001)
	check(not Profiles.is_source_wolf({}, other), "Ordinary wolves keep their existing presentation policy")
	other.configure_enemy(13002)
	check(not Profiles.is_source_wolf({}, other), "The separate second wolf variant is outside this focused change")
	for action in wolf.combat.catalog.actions:
		if not str(action.key).begins_with("ActGroup_senlinlangwang/"): continue
		for definition in action.get("hits", []):
			if not definition.get("enabled", false): continue
			_test_hit(world, wolf, target, definition, str(action.key).get_file())
			if definition.get("projectile", false): _test_projectile(world, wolf, definition, str(action.key).get_file())
	check(hit_cases == 29, "All 29 enabled source wolf hit definitions receive real world feedback coverage")
	check(projectile_cases == 11, "All 11 enabled source wolf physical projectiles receive visual coverage")
	world.presentation.clear()
	var no_style := DungeonProjectile.new()
	no_style.hit = {"action": "attack", "emission": "empty-style"}
	no_style.entity = {}
	no_style.source_key = wolf.combat.actor_key
	world._add_projectile_visual(no_style, wolf)
	check(not world.projectiles.back().visual.visible and world.presentation.active.is_empty(), "Empty wolf projectile style creates no substitute sphere or effect")
	world._recycle_projectile(world.projectiles.back())
	world.projectiles.clear()
	check(world._source_stop_projectiles.is_empty(), "Source projectile reference counts release after every case")
	var result := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "hit_cases": hit_cases, "projectile_cases": projectile_cases, "scope": "First wolf source impact assets, audio, camera and hit-stop feedback; all enabled direct hit definitions and projectile styles. Existing damage and player knockback remain unchanged. Headless Godot, not APK runtime or pixel equivalence."}
	FileAccess.open("res://reports/wolf-source-feedback-test.json", FileAccess.WRITE).store_string(JSON.stringify(result, "\t"))
	print("WOLF_SOURCE_FEEDBACK ", JSON.stringify(result))
	world.free()
	quit(0 if failures.is_empty() else 1)

func _test_hit(world: DungeonWorld, wolf: DungeonActor, target: DungeonActor, definition: Dictionary, action: String) -> void:
	hit_cases += 1
	world.presentation.clear()
	world._camera_impulses.clear()
	wolf.clear_impact_state()
	target.clear_impact_state()
	var hit := {"definition": definition, "damage": 32.0, "uncritical_damage": 32.0, "critical_rate": 0.0, "critical_roll": 1.0, "action": action, "slot": 0, "sequence": 1, "emission": hit_cases, "impact_position": [0.0, 0.75, 4.0]}
	var source := Feedback.read(definition)
	var profile := Profiles.resolve(hit, wolf.combat)
	check(profile.get("source_only", false) and profile.source_feedback == source, "%s retains exact source feedback" % action)
	var hp_before: float = target.combat.health
	world._apply_hit(wolf, target, hit)
	check(is_equal_approx(hp_before - target.combat.health, 32.0), "%s preserves settled damage" % action)
	check(is_zero_approx(target.hurt_timer) and is_zero_approx(target.combat.impact_pause) and is_zero_approx(wolf.combat.impact_pause), "%s adds no generic material flash or local hit pause" % action)
	check(world._camera_impulses.size() == source.camera_shakes.size(), "%s keeps exactly the APK hit camera shake count" % action)
	for index in source.camera_shakes.size():
		check(world._camera_impulses[index].raw == source.camera_shakes[index].raw and not world._camera_impulses[index].has("amplitude"), "%s keeps the raw source camera shake values" % action)
	check(world._seen_blasts.is_empty(), "%s adds no generic explosion" % action)
	var plan := SourceImpact.collect(hit, wolf.combat)
	check(world.presentation.active.size() == plan.effects.size(), "%s creates exactly its source contact effects" % action)
	for effect in world.presentation.active:
		check(effect.source_only and not effect.body_burst and effect.authored != null, "%s contact uses authored source geometry without a generic burst" % action)
	var layers: Array = []
	for name in plan.sounds:
		layers.append_array(world.presentation.media.get("audio", {}).get(world.presentation._key(name), []).slice(0, 3))
	check(world.presentation.sound_queue.map(func(sound): return sound.layer) == layers, "%s keeps exactly its source sound layers" % action)
	check(is_equal_approx(target.knockback_distance, float(profile.distance) * 0.35), "%s preserves its existing player knockback distance" % action)
	check(target._model_shake_active == source.hit_actions.any(func(entry): return bool(entry.model_shake)), "%s keeps its source model-shake flag" % action)
	check(source.hit_stops.is_empty() == not world._battle_scales.has("UnitStopFrame"), "%s has no invented source hit stop" % action)

func _test_projectile(world: DungeonWorld, wolf: DungeonActor, definition: Dictionary, action: String) -> void:
	projectile_cases += 1
	world.presentation.clear()
	var state := world._projectile(wolf, {"definition": definition, "action": action, "slot": 0, "sequence": 1, "emission": "projectile:%d" % projectile_cases})
	var projectile: Dictionary = world.projectiles.back()
	check(not projectile.visual.visible, "%s hides the fallback projectile sphere" % action)
	var prefab := str(state.entity.get("ModlePrefab", ""))
	var trigger: Dictionary = state.entity.get("EffectTriggerDef", {})
	var name := prefab if not prefab.is_empty() else str(trigger.get("EffectName", ""))
	if not name.is_empty() and state.motion_type not in ["EMAT_FollowOwner", "EMAT_RotateOwner"]:
		check(not world.presentation.active.is_empty(), "%s displays its named source projectile" % action)
	for effect in world.presentation.active:
		check(effect.source_only and effect.key == world.presentation._key(name) and effect.authored != null, "%s retains exact APK projectile style" % action)
		check(effect.follow != null and effect.follow.get_ref() == projectile.visual, "%s retains its projectile motion anchor" % action)
		var dimensions := DungeonWorld.vector(state.entity.get("ModlePrefabSize", {})) if not prefab.is_empty() else DungeonWorld.vector(trigger.get("Scale", {}))
		if dimensions.is_zero_approx(): dimensions = Vector3.ONE
		check(effect.authored.scale.is_equal_approx(dimensions), "%s retains serialized projectile scale" % action)
	var key := Profiles.instance_id(state.hit)
	check(world._source_stop_projectiles.get(key, 0) == 1, "%s retains source hit-stop identity through its projectile lifetime" % action)
	world._recycle_projectile(projectile)
	world.projectiles.clear()
