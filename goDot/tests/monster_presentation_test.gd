extends SceneTree

const Presentation = preload("res://scripts/presentation/combat_presentation.gd")
var checks := 0
var failures: Array[String] = []
var rows: Array[Dictionary] = []
var unresolved: Array[Dictionary] = []
var playback_rows: Array[Dictionary] = []
var presentation: Node3D

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _references(value: Variant, effects: Dictionary, sounds: Dictionary, anchors: Dictionary) -> void:
	if value is Dictionary:
		for key in value:
			var child: Variant = value[key]
			if child is String and not child.is_empty():
				if key in ["EffectName", "Effect", "EntityEndEffect", "mEntityEndEffect_Floor", "BounceEffect"]: effects[presentation._key(child)] = true
				if key in ["SoundName", "VoiceName", "EntityEndSound"]: sounds[presentation._key(child)] = true
			if key == "DummyData" and child is Dictionary and not str(child.get("CustomDummyName", "")).is_empty(): anchors[str(child.CustomDummyName)] = true
			_references(child, effects, sounds, anchors)
	elif value is Array:
		for child in value: _references(child, effects, sounds, anchors)

func _warning_checks(actor: DungeonActor) -> void:
	actor.combat.configure_enemy(52003, 731)
	actor.actor_id = 52003
	actor.position = Vector3.ZERO
	actor.facing = Vector3.BACK
	actor.combat._cast_sequence = 91
	actor.combat.busy = 10
	actor.combat.current_action = "ComboAttack1"
	actor.combat.action_elapsed = 0
	presentation.action_started(actor, {"sequence": 91, "action": "ComboAttack1", "speed": 1})
	check(presentation.telegraphs.is_empty(), "Authored combo warnings wait for their own event")
	var warning = {"EffectName": "fx_other_enemyatkrange360.prefab", "Scale": {"x": 2.7, "y": 2.7, "z": 2.7}, "DummyType": "EEDT_DummyChild", "EffectSpeed": 0.7}
	presentation.trigger(actor, warning, 91)
	actor.combat.action_elapsed = 1.833
	presentation.trigger(actor, warning, 91)
	check(presentation.telegraphs.size() == 2, "A repeated prefab creates the second combo warning independently")
	presentation._process(0.01)
	check(presentation.telegraphs.size() == 1 and is_equal_approx(presentation.telegraphs[0].start, 1.833), "First warning expiry preserves the second beat")
	presentation.clear()
	warning.DummyType = "EEDT_DummyPosition"
	warning.Position = {"x": 0, "y": 0, "z": 6}
	presentation.trigger(actor, warning, 91)
	var position: Vector3 = presentation.telegraphs[0].node.position
	var rotation: Vector3 = presentation.telegraphs[0].node.rotation
	actor.position = Vector3(3, 0, 2)
	actor.facing = Vector3.RIGHT
	presentation._process(0.01)
	check(presentation.telegraphs[0].node.position.is_equal_approx(position) and presentation.telegraphs[0].node.rotation.is_equal_approx(rotation), "World-position warnings retain their placement as the monster moves")
	presentation.clear()
	warning.EffectName = "fx_other_enemyatkrange90_forwardz.prefab"
	warning.Scale = {"x": 8, "y": 1, "z": 8}
	presentation.trigger(actor, warning, 91)
	check(presentation.telegraphs[0].node.dimensions.is_equal_approx(Vector2.ONE * 16.8), "Forward fan includes the recovered prefab's 0.42 hierarchy scale")
	presentation.clear()
	actor.combat.configure_enemy(11005, 731)
	actor.combat._start(actor.combat._action("ActGroup_xiaoshanzhu", "attack"), 0)
	presentation.action_started(actor, {"sequence": actor.combat._cast_sequence, "action": "attack", "speed": 1})
	check(presentation.telegraphs.is_empty(), "Unempowered boar does not borrow its empowered charge warning")
	presentation.clear()
	actor.combat.configure_enemy(42002, 731)
	actor.actor_id = 42002
	actor.combat._cast_sequence = 92
	actor.combat.current_action = "attack4"
	actor.combat.action_elapsed = 0
	actor.combat.busy = 4
	presentation.action_started(actor, {"sequence": 92, "action": "attack4", "speed": 1})
	check(presentation.telegraphs.size() == 4 and not presentation.telegraphs.any(func(entry): return entry.node.visible), "Four-hit fallback warnings stay hidden until their own windup")
	for entry in presentation.telegraphs:
		check(entry.offset.is_equal_approx(Vector3(0, 0, 1.5)), "Scorpion ground strike warning uses its source forward emission position")
	actor.combat.action_elapsed = 1.6
	presentation._process(0.01)
	check(presentation.telegraphs.filter(func(entry): return entry.node.visible).size() == 1, "Scorpion combo displays only its next strike warning")
	presentation.clear()

func _reverse_playback_checks(actor: DungeonActor) -> void:
	var state_name := "Move_Back" if actor.actor_id == 33001 else "Moveback"
	actor.combat.busy = 1
	actor.play_animation(state_name, true)
	var length := actor.animation.current_animation_length
	var initial := actor.animation.current_animation_position
	check(actor.animation_state_speed == -1.0, "%d retains the recovered negative state rate" % actor.actor_id)
	check(length > 0.1 and is_equal_approx(initial, length), "%d reverse playback begins at the real clip end" % actor.actor_id)
	actor._physics_process(0.08)
	var backwards_position := actor.animation.current_animation_position
	check(is_equal_approx(actor.animation.current_animation_position, initial - 0.08), "%d physics advances the animation cursor backwards" % actor.actor_id)
	actor.animation.seek(0.04, true)
	actor._physics_process(0.1)
	check(is_equal_approx(actor.animation.current_animation_position, length - 0.06), "%d backwards playback wraps across the source looping boundary" % actor.actor_id)
	playback_rows.append({"enemy": actor.actor_id, "state": state_name, "length": length, "initial": initial, "advanced": backwards_position, "wrapped": actor.animation.current_animation_position})

func _run() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/catalog.json"))
	var combat := DungeonCombat.new()
	combat.configure()
	var source_states: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/monster_presentation.json"))
	presentation = Presentation.new()
	root.add_child(presentation)
	presentation.configure(catalog)
	presentation.set_process(false)
	var groups: Dictionary = {}
	var source_actions := 0
	var warning_events := 0
	for enemy in combat.catalog.enemies:
		var actor := DungeonActor.new()
		actor.actor_id = int(enemy.id)
		actor.combat = DungeonCombat.new()
		actor.combat.configure_enemy(actor.actor_id, 731)
		root.add_child(actor)
		var metadata: Dictionary = catalog.enemies[str(actor.actor_id)]
		actor.set_visual(str(metadata.path), metadata)
		check(actor.visual_loaded and actor.animation != null, "Monster %d loads its source model and animation player" % actor.actor_id)
		if actor.actor_id in [33001, 42001]: _reverse_playback_checks(actor)
		if actor.actor_id == 23001:
			check(actor.impact_bounds.size.x > 3 and actor.impact_bounds.size.x < 5 and actor.impact_bounds.size.y < 4, "Griffin skinned bounds use its metre-scale bone envelope")
			var center: Node3D = presentation._anchor(actor, {"DummyData": {"DummyType": "Unit_Center"}})
			check(center != actor and center.global_position.y > 1 and center.global_position.y < 3 and absf(center.global_position.x) < 0.3, "Griffin Unit_Center stays on its torso")
			var contact: Vector3 = actor.impact_anchor()
			check(contact.y > 1 and contact.y < 3 and contact.distance_to(actor.position) < 3, "Griffin body impact stays near the visible model")
		var animations: Dictionary = {}
		var effects: Dictionary = {}
		var sounds: Dictionary = {}
		var anchors: Dictionary = {}
		var action_names: Array[String] = []
		var local_warnings := 0
		var absent_animations: Array[String] = []
		for action in combat.catalog.actions:
			if str(action.group) != str(enemy.group): continue
			action_names.append(str(action.id))
			for event in action.events + action.hits:
				if not event.get("enabled", false): continue
				var raw = DungeonWorld._raw_definition(event)
				if event.get("type", "") == "EET_PlayAnim":
					var name = str(raw.get("AnimName", ""))
					if not name.is_empty():
						animations[name] = true
						var resolved = str(actor.animation_aliases.get(name.to_lower(), name))
						if actor.animation.has_animation(resolved): check(true, "%d/%s resolves exact source animation %s" % [enemy.id, action.id, name])
						else:
							if name not in absent_animations: absent_animations.append(name)
							check(int(enemy.id) == 23001 and name == "Attack2_Part2" and not source_states.enemies[str(int(enemy.id))].states.has(name.to_lower()), "Unresolved animation is the confirmed missing source state rather than a dropped import: %d/%s" % [enemy.id, name])
				if event.get("type", "") == "EET_PlayEffect" and "enemyatkrange" in str(raw.get("EffectTriggerDef", {}).get("EffectName", "")).to_lower(): local_warnings += 1
				_references(raw, effects, sounds, anchors)
		var absent_effects: Array[String] = []
		var absent_sounds: Array[String] = []
		var absent_anchors: Array[String] = []
		for key in effects:
			if not presentation.media.effects.has(key): absent_effects.append(key)
		for key in sounds:
			if not presentation.media.audio.has(key) and not catalog.audio.has(key): absent_sounds.append(key)
		for name in anchors:
			var anchor: Node3D = presentation._anchor(actor, {"DummyData": {"CustomDummyName": name}})
			if anchor == actor: absent_anchors.append(name)
			else:
				check(anchor == presentation._anchor(actor, {"DummyData": {"CustomDummyName": name}}), "%d reuses the exact %s socket" % [enemy.id, name])
		if not absent_effects.is_empty() or not absent_sounds.is_empty() or not absent_anchors.is_empty() or not absent_animations.is_empty():
			var bones: Array[String] = []
			if not absent_anchors.is_empty():
				for skeleton: Skeleton3D in actor.visual.find_children("*", "Skeleton3D", true, false):
					for index in skeleton.get_bone_count(): bones.append(skeleton.get_bone_name(index))
			unresolved.append({"enemy": enemy.id, "effects": absent_effects, "sounds": absent_sounds, "anchors": absent_anchors, "animations": absent_animations, "available_bones": bones})
		rows.append({"enemy": enemy.id, "name": enemy.name, "rank": enemy.rank, "group": enemy.group, "actions": action_names, "animation_clips": animations.size(), "effects": effects.size(), "sounds": sounds.size(), "custom_anchors": anchors.size(), "authored_warning_events": local_warnings})
		if not groups.has(enemy.group):
			groups[enemy.group] = true
			source_actions += action_names.size()
			warning_events += local_warnings
		actor.free()
	var fixture := DungeonActor.new()
	fixture.combat = DungeonCombat.new()
	root.add_child(fixture)
	_warning_checks(fixture)
	fixture.free()
	check(rows.size() == 39, "Every shipped monster entry is audited")
	var report = {"passed": failures.is_empty(), "checks": checks, "failures": failures, "monsters": rows.size(), "action_groups": groups.size(), "source_actions": source_actions, "authored_warning_events": warning_events, "coverage": rows, "reverse_playback": playback_rows, "unresolved_source_references": unresolved, "scope": "All enabled action events and hit definitions in the 39 converted APK monster entries. Exact model animation aliases and custom skeleton anchors are inspected; static reference coverage is separate from runtime parity. Shader warning visuals are a reconstruction; no APK runtime was observed."}
	FileAccess.open("res://reports/monster-presentation-tests.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("MONSTER_PRESENTATION ", JSON.stringify({"passed": report.passed, "checks": checks, "failures": failures, "monsters": rows.size(), "source_actions": source_actions, "unresolved_entries": unresolved.size()}))
	presentation.free()
	quit(0 if failures.is_empty() else 1)
