extends SceneTree

const Presentation = preload("res://scripts/presentation/combat_presentation.gd")
var checks := 0
var failures: Array[String] = []
var actions: Array[Dictionary] = []
var presentation: Node3D
var actor: DungeonActor

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	run.call_deferred()

func _raw_action(name: String) -> Dictionary:
	return actor.combat._action("ActGroup_playerchara", name)

func _effect(name: String, speed: float) -> Dictionary:
	for command in _raw_action(name).get("events", []):
		if command.get("type", "") != "EET_PlayEffect" or not command.get("enabled", false): continue
		var definition: Dictionary = DungeonWorld._raw_definition(command).get("EffectTriggerDef", {})
		if is_equal_approx(float(definition.get("EffectSpeed", 1)), speed): return definition
	return {}

func _clock_check(name: String, source_speed: float, action_rate: float, ignored := false) -> void:
	presentation.clear()
	actor.combat.busy = 5
	actor.combat._cast_sequence = 41
	actor.combat.action_tick_delta = 0.02
	actor.combat.action_step = 0.02 * action_rate
	var definition = _effect(name, source_speed).duplicate(true)
	check(not definition.is_empty(), "%s has a source effect at %.3f speed" % [name, source_speed])
	presentation.trigger(actor, definition, 41, Vector3.INF, not ignored)
	check(presentation.active.size() == 1, "%s emits one authored effect" % name)
	if presentation.active.is_empty(): return
	var entry: Dictionary = presentation.active.back()
	var owner_rate = 1.0 if ignored else action_rate
	var duration = entry.duration
	var expected_duration = float(definition.get("DelayTimeToDestroy", 0)) / 1000.0
	if expected_duration <= 0: expected_duration = minf(entry.authored.lifetime, 4.0)
	check(is_equal_approx(duration, expected_duration / source_speed), "%s lifetime applies source speed once" % name)
	presentation._process(0.02)
	check(is_equal_approx(entry.age, 0.02 * owner_rate), "%s owner clock is independent of source speed" % name)
	check(is_equal_approx(entry.authored.age, 0.02 * owner_rate * source_speed), "%s emission schedule uses composed speed once" % name)
	for emitter in entry.authored.emitters:
		check(is_equal_approx(emitter.node.speed_scale, float(emitter.speed) * owner_rate * source_speed), "%s particle simulation matches its emission clock" % name)
	actor.combat.action_step = 0
	presentation._process(0.02)
	for emitter in entry.authored.emitters:
		check(not is_zero_approx(emitter.node.speed_scale) if ignored else is_zero_approx(emitter.node.speed_scale), "%s respects local pause/ignore clock" % name)
	presentation.suspended = true
	var paused_age: float = entry.authored.age
	presentation._process(0.02)
	check(is_equal_approx(entry.authored.age, paused_age), "%s global suspension stops emission clock" % name)
	for emitter in entry.authored.emitters: check(is_zero_approx(emitter.node.speed_scale), "%s global suspension stops particles" % name)
	presentation.suspended = false
	presentation.clear()
	presentation.emit_effect(actor, str(definition.EffectName), Vector3.ZERO)
	var reused: Dictionary = presentation.active.back()
	check(is_equal_approx(reused.playback_speed, 1.0) and is_zero_approx(reused.detach_after) and reused.clock_sequence == -1, "%s pooled entry clears speed/detach/action-clock state" % name)
	presentation._process(0.02)
	for emitter in reused.authored.emitters: check(is_equal_approx(emitter.node.speed_scale, float(emitter.speed)), "%s pooled authored effect resumes its original speed" % name)
	presentation.clear()

func _summon_check() -> void:
	presentation.clear()
	var point = Vector3(3, 0.4, 7)
	var raw: Dictionary = actor.combat._summon_index["115101"].raw_data
	var source_model: Dictionary = actor.combat._summon_index["1194001"].raw_data
	check(not source_model.PrefabIsEffect, "The APK sword soul is a non-effect prefab with source model geometry")
	var model_token: int = presentation.summon_started(actor, source_model, point)
	check(model_token > 0 and presentation.active.size() == 1 and presentation.active.back().authored.find_children("*", "MeshInstance3D", true, false).size() > 0, "Recovered non-effect source prefab renders its actual model")
	presentation.summon_ended(model_token)
	check(presentation.active.is_empty(), "World disposal releases the source model prefab")
	var unavailable: Dictionary = actor.combat._summon_index["11001"].raw_data
	check(presentation.summon_started(actor, unavailable, point) == 0 and presentation.active.is_empty(), "An exact prefab absent from the APK does not create a fabricated lease")
	var ignored = raw.duplicate(true)
	ignored.Prefab = ""
	check(presentation.summon_started(actor, ignored, point) == 0 and presentation.active.is_empty(), "Missing summon prefab does not create a lease")
	var token: int = presentation.summon_started(actor, raw, point, Vector3.RIGHT)
	check(token > 0 and presentation.active.size() == 1, "Sword dimensional slash creates one leased effect")
	var entry: Dictionary = presentation.active.back()
	check(entry.key == "24080201_fx_sword_satk_dimensionalslash" and entry.authored != null, "Summon uses its original authored prefab")
	check(entry.root.global_position.is_equal_approx(point), "Summon position is supplied by world without a second hit offset")
	check(entry.authored.scale.is_equal_approx(Vector3.ONE), "Zero source summon scale uses the original unit scale")
	check(is_equal_approx(entry.root.global_rotation.y, PI / 2), "Summon starts facing its supplied world direction")
	check(entry.sequence == -1 and entry.clock_sequence == -1 and entry.detached, "Emitted summon owns an independent action clock and lifetime")
	actor.combat._cast_sequence += 1
	presentation.cancel_actor(actor)
	check(presentation.active.size() == 1, "Owner action cancellation retains an emitted summon")
	actor.combat.action_step = 0
	var age: float = entry.authored.age
	presentation._process(1.4)
	check(presentation.active.size() == 1 and entry.authored.age > age, "World-owned summon survives source visual duration and owner local hit pause")
	var updated = Vector3(-2, 1.1, 5)
	presentation.summon_updated(token, updated, Vector3.BACK)
	check(entry.root.global_position.is_equal_approx(updated) and is_zero_approx(entry.root.global_rotation.y), "Summon position and facing follow world updates")
	presentation.summon_updated(token, point)
	check(entry.root.global_position.is_equal_approx(point) and is_zero_approx(entry.root.global_rotation.y), "Position-only update retains summon orientation")
	actor.dead = true
	presentation._process(0.02)
	check(presentation.active.size() == 1, "Emitted summon remains until world disposal even after its owner dies")
	actor.dead = false
	presentation.summon_ended(token)
	check(presentation.active.is_empty(), "World disposal returns the summon effect to its pool")
	presentation.emit_effect(actor, "", Vector3.ZERO)
	var reused: Dictionary = presentation.active.back()
	check(reused.root == entry.root and int(reused.summon_token) == 0, "Reused effect root clears the previous summon lease")
	presentation.summon_updated(token, updated)
	presentation.summon_ended(token)
	check(presentation.active.size() == 1 and reused.root.global_position.is_zero_approx(), "Stale summon token cannot move or recycle a reused effect")
	presentation.clear()
	var scaled_raw: Dictionary = actor.combat._summon_index["115201"].raw_data
	actor.facing = Vector3.LEFT
	var next_token: int = presentation.summon_started(actor, scaled_raw, point)
	entry = presentation.active.back()
	check(next_token > token and entry.authored.scale.is_equal_approx(DungeonWorld.vector(scaled_raw.PrefabScale)), "New summon lease preserves strengthened source prefab scale")
	check(is_equal_approx(entry.root.global_rotation.y, -PI / 2), "Omitted direction defaults to the source actor facing")
	presentation.summon_ended(token)
	check(presentation.active.size() == 1, "Previous summon token cannot dispose a later summon")
	presentation.clear()
	presentation.summon_updated(next_token, updated)
	presentation.summon_ended(next_token)
	check(presentation.active.is_empty(), "Scene clear invalidates all remaining summon handles")

func run() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/catalog.json"))
	actor = DungeonActor.new()
	actor.actor_id = 6
	actor.is_player = true
	actor.combat = DungeonCombat.new()
	actor.combat.configure(null, null, 6)
	root.add_child(actor)
	presentation = Presentation.new()
	root.add_child(presentation)
	presentation.configure(catalog)
	presentation.set_process(false)
	for character in actor.combat.catalog.characters:
		var metadata: Dictionary = catalog.characters[str(int(character.id))]
		var model: Node3D = load(str(metadata.path)).instantiate()
		root.add_child(model)
		var animators = model.find_children("*", "AnimationPlayer", true, false)
		check(not animators.is_empty(), "Character %d has an animation player" % character.id)
		var animator: AnimationPlayer = animators[0]
		for action in actor.combat.catalog.actions:
			var name = str(action.key).get_file()
			if not name.begins_with(str(character.prefix) + "_") or name not in Presentation.HEAVY_ACTIONS: continue
			var clips: Array[String] = []
			for event in action.events:
				if not event.get("enabled", false) or event.type != "EET_PlayAnim": continue
				var source_name = str(DungeonWorld._raw_definition(event).get("AnimName", ""))
				var converted: Array = metadata.animations.filter(func(clip): return str(clip.get("source_name", "")) == source_name)
				check(not converted.is_empty() and animator.has_animation(str(converted[0].name)), "%s resolves exact source animation %s" % [name, source_name])
				if source_name not in clips: clips.append(source_name)
			actions.append({"character": character.id, "action": name, "clips": clips})
		model.free()
	check(actions.size() == 26, "All 26 original heavy and derivative action variants retain animation coverage")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://reports/APK_HEAVY_ATTACK_DATA.json"))
	var manifest_names: Array = manifest.actions.keys()
	var runtime_names: Array = Presentation.HEAVY_ACTIONS.duplicate()
	manifest_names.sort()
	runtime_names.sort()
	check(manifest_names == runtime_names, "Heavy audio prewarm covers exactly the APK heavy action manifest")
	for name in ["audio_sound_sword_satk_02", "audio_sound_scythe_heavy_atk_02_2", "audio_sound_axe_heavy_atk_01", "audio_sound_sword_nezimi_satk_03_03", "audio_sound_bow_heavy_atk_02", "audio_sound_sword_oba_satk_01", "audio_sound_knight_heavy_freeze", "audio_sound_wolf_attack1_02", "audio_voice_jiannan_nattack05", "audio_sound_sword_oba_swing", "audio_sound_sword_oba_satk_01_01"]:
		check(presentation.prewarmed_heavy_sounds.has(name), "%s is decoded before first heavy contact" % name)
	_clock_check("orb_satk_start", 0.5, 1.0)
	_clock_check("bow_fullsatk_weapon4_combine", 2.0, 1.5)
	_clock_check("lance_satk_nomal2", 0.600000023841858, 0.5)
	_clock_check("orb_satk_start", 0.5, 0.5, true)
	# A source-enabled fixed clock remains independent of the local hit pause.
	var definition = _effect("orb_satk_start", 0.5).duplicate(true)
	definition.SpeedScaleByOwnerActionSpeed = false
	actor.combat.action_step = 0
	presentation.trigger(actor, definition, 41)
	presentation._process(0.02)
	check(presentation.active.back().clock_sequence == -1 and presentation.active.back().authored.age > 0, "Explicit source-independent effect continues through local hit pause")
	presentation.clear()
	definition = _effect("bow_fullsatk", 1.0)
	actor.combat.action_step = 0.02
	actor.combat.busy = 5
	actor.position = Vector3.ZERO
	presentation.trigger(actor, definition, 41)
	check(presentation.active.back().follow != null, "Bow jump initially follows the actor")
	actor.position.x = 1
	presentation._process(0.29)
	check(presentation.active.back().follow != null, "Bow jump retains source following before 300 ms")
	actor.position.x = 2
	presentation._process(0.02)
	var detached: Dictionary = presentation.active.back()
	var world_position: Vector3 = detached.root.global_position
	check(detached.follow == null, "Bow jump detaches to world position at its source deadline")
	actor.position.x = 3
	presentation._process(0.02)
	check(detached.root.global_position.is_equal_approx(world_position), "Detached effect retains world position while the actor moves")
	_summon_check()
	var report = {"checks": checks, "failures": failures, "characters": 7, "actions": actions, "prewarmed_sound_keys": presentation.prewarmed_heavy_sounds.size()}
	FileAccess.open("res://reports/heavy-presentation-tests.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("HEAVY_PRESENTATION ", JSON.stringify({"checks": checks, "failures": failures, "characters": 7, "actions": actions.size(), "prewarmed_sound_keys": presentation.prewarmed_heavy_sounds.size()}))
	presentation.free()
	actor.free()
	quit(0 if failures.is_empty() else 1)
