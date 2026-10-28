extends SceneTree

const Interactions = preload("res://scripts/world_interactions.gd")
var checks := 0
var failures: Array[String] = []
var rows: Array = []
var rules: Dictionary
var definitions: Dictionary = {}
var world: ObservedWorld

class ObservedWorld extends DungeonWorld:
	var impacts: Array = []
	func _on_impact(hit: Dictionary, target: DungeonActor) -> void:
		impacts.append({"target": target.combat.actor_key, "source": hit.get("source_key", ""), "damage": hit.get("resolved_damage", 0), "absorbed": hit.get("resolved_absorbed", 0)})

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	rules = JSON.parse_string(FileAccess.get_file_as_string(Interactions.RULES_PATH))
	for definition in rules.Definitions:
		if definition.Type == "EEUT_TriggerTrap": definitions[str(definition.ID)] = definition
	world = ObservedWorld.new()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.presentation.set_process(false)
	world.presentation.audio_enabled = false
	world.low_effects = true
	_all_definitions()
	_defensive_states()
	_persistent_effects()
	_shared_interval()
	_environment_damage()
	_source_volumes()
	_source_attraction()
	_attraction_rules()
	_disabled_traps()
	await _attraction_wall()
	_check(rows.filter(func(row): return row.has("id")).size() == 20, "All damage definition scenarios completed")
	for scenario in ["persistent_effects", "all_source_colliders", "source_attraction", "attraction_rules", "disabled_traps", "attraction_wall"]:
		_check(rows.any(func(row): return row.get("case", "") == scenario), scenario + " completed without an interrupted test function")
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "definitions": definitions.size() + 1, "scenarios": rows, "scope": "All 20 APK trigger trap definitions plus the quicksand attraction trap: actual world-to-combat damage dispatch, camp filters, recipient damage tiers, effects, defensive states, shared timing, environment destruction, JSON recovery and all 357 recovered trap bindings. Attraction includes native force, player weight and all source action-state restrictions, collision and trap-disable messages. Controlled Godot headless execution; no original APK runtime or visual/device-performance equivalence claim."}
	FileAccess.open("res://reports/trap-complete-test.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("TRAP_COMPLETE ", JSON.stringify({"passed": report.passed, "checks": checks, "failures": failures, "definitions": report.definitions}))
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _actor(key: String, friendly: bool, point: Vector3) -> DungeonActor:
	var actor := DungeonActor.new()
	actor.is_player = friendly
	actor.combat = DungeonCombat.new()
	if friendly: actor.combat.configure(null, null, 1, 0, 193)
	else: actor.combat.configure_enemy(11001, 193)
	actor.combat.statuses.clear()
	actor.combat._pending.clear()
	actor.combat.drain_events()
	actor.combat.actor_key = key
	actor.combat.attack = 100
	actor.combat.defense = 0
	actor.combat.max_health = 1000
	actor.combat.health = 1000
	actor.position = point
	world.add_child(actor)
	actor.set_process(false)
	actor.set_physics_process(false)
	world.actors.append(actor)
	world._actor_index[key] = actor
	world._bind_impact(actor)
	return actor

func _reset() -> void:
	world.presentation.clear()
	for actor in world.actors: actor.free()
	world.actors.clear()
	world._actor_index.clear()
	world.impacts.clear()
	world.player = _actor("player", true, Vector3.ZERO)
	_actor("enemy", false, Vector3(4, 0, 0))

func _fixture(definition: Dictionary, disabled_effect := false, with_props := false, shape := 65) -> Dictionary:
	var environment := Node3D.new()
	var marker_list: Array = [_marker("trap", "EEUT_TriggerTrap")]
	var bindings: Array = [{"SceneName": "TrapTest", "SourceGameObjectId": "trap", "ConfigId": str(definition.ID), "SupportsRules": true, "FirstTriggerDelayTime": 0.1, "TriggerIdleTime": 0.2}]
	var configs: Array = [definition]
	var colliders: Array = [_volume("trap", "Container_EnterTrigger"), _volume("trap", "Container_EffectTrigger")]
	colliders[1].properties.m_Enabled = 0 if disabled_effect else 1
	colliders[1].kind = shape
	colliders[1].properties.merge({"m_Radius": 6.0, "m_Height": 14.0, "m_Direction": 0})
	if with_props:
		configs.append({"ID": "jar", "Type": "EEUT_DestoryableItem", "CanBeAttack": true, "CanBeAttackCamp": "101", "Durablity": 50, "BreakDelayTime": 0.1, "DropItemIdList": []})
		for id in ["near", "far"]:
			marker_list.append(_marker(id, "EEUT_DestoryableItem"))
			bindings.append({"SceneName": "TrapTest", "SourceGameObjectId": id, "ConfigId": "jar", "SupportsRules": true})
			var volume := _volume(id, "")
			volume.properties.m_Size = {"x": 1, "y": 1, "z": 1}
			volume.properties.m_IsTrigger = 0
			volume.world_matrix[3] = 2 if id == "near" else 30
			colliders.append(volume)
	for marker in marker_list:
		var visual := Node3D.new()
		visual.name = marker.exported_node_name
		environment.add_child(visual)
	var interactions := Interactions.new()
	var fixture := {"environment": environment, "interactions": interactions, "events": []}
	interactions.trap_triggered.connect(func(event): fixture.events.append(event); world._environment_trap(event))
	interactions.setup(environment, marker_list, {"rules": {"Bindings": bindings, "Definitions": configs}, "colliders": colliders})
	return fixture

func _tick(fixture: Dictionary, delta: float, player_point := Vector3.ZERO, enemy_inside := true) -> void:
	fixture.interactions.tick(delta, player_point, [{"id": "enemy", "position": Vector3(4, 0, 0) if enemy_inside else Vector3(100, 0, 100), "camp": 3}])

func _activate(fixture: Dictionary, player_point := Vector3.ZERO, enemy_inside := true) -> void:
	for frame in 200:
		_tick(fixture, 0.01, player_point, enemy_inside)
		if fixture.interactions.state_for("trap").phase == "active": return
	_check(false, "Trap enters active phase within recovered delay")

func _all_definitions() -> void:
	var player_damage := {"92111022": 5.0, "92111023": 2.0, "92111024": 5.0, "92111025": 2.0, "92111071": 2.0, "92111072": 5.0, "92111074": 2.0}
	var enemy_damage := {"92111022": 250.0, "92111023": 40.0, "92111024": 250.0, "92111025": 40.0, "92111071": 0.0, "92111072": 250.0, "92111074": 40.0}
	var extra_buffs := {"92111023": "92111063", "92111024": "92111063", "92111025": "92111061"}
	_check(definitions.size() == 20, "All twenty recovered trap definitions are exercised")
	for id in definitions:
		_reset()
		var definition: Dictionary = definitions[id]
		var buff := str(definition.AddBuffData.BuffTriggerId)
		var fixture := _fixture(definition, id in ["11127", "11128"])
		_tick(fixture, 0.09)
		_check(fixture.events.is_empty(), id + " waits for original first trigger delay")
		_activate(fixture)
		var hostile_allowed := Interactions.camp_allows(str(definition.TargetCampString), 3)
		_check(fixture.events.size() == (2 if hostile_allowed else 1), id + " applies once to each source-allowed camp at activation")
		var player_loss: float = 1000.0 - world.player.combat.health
		var enemy_loss: float = 1000.0 - world.actors[1].combat.health
		_check(is_equal_approx(player_loss, float(player_damage.get(buff, 0))), id + " uses player damage tier")
		_check(is_equal_approx(enemy_loss, float(enemy_damage.get(buff, 0)) if hostile_allowed else 0.0), id + " uses monster damage tier with native player caster")
		if extra_buffs.has(buff):
			_check(world.player.combat.statuses.has(extra_buffs[buff]) and world.actors[1].combat.statuses.has(extra_buffs[buff]), id + " applies its post-hit slow or armor debuff")
		if buff in ["92111072", "92111074"]: _check(world.actors[1].combat.statuses.has("119903") and not world.player.combat.statuses.has("119903"), id + " applies armor break only to monster tier")
		if buff == "92111071": _check(world.actors[1].combat.statuses.has("119901") and not world.player.combat.statuses.has("119901"), id + " applies burn only to monster tier")
		if buff in ["92111061", "92111063"]: _check(world.player.combat.attribute("MoveSpeedRate") == -200, id + " applies source movement penalty")
		if buff == "92111067": _check(world.player.combat.statuses.has(buff), id + " retains harmless water visual buff")
		if buff == "25060501":
			_check(world.player.combat.skill_capacity(1) == world.player.combat.skill_cost(1), id + " restricts dodge capacity to one use")
			world.player.combat.tick(0.01)
			_check(world.player.combat.energy[1] <= world.player.combat.skill_cost(1), id + " clamps stored dodge energy on the next simulation step")
		var saved: Dictionary = JSON.parse_string(JSON.stringify(fixture.interactions.snapshot()))
		_check(fixture.interactions.restore(saved), id + " active trap JSON state restores")
		var before: int = fixture.events.size()
		_tick(fixture, 0.02)
		_check(fixture.events.size() == before, id + " restore preserves active once or interval hit history")
		_check(world.impacts.all(func(hit): return hit.source == "player"), id + " retains native current-player damage attribution")
		for frame in 600:
			_tick(fixture, 0.01)
			if fixture.interactions.state_for("trap").cycle == 2 and fixture.interactions.state_for("trap").phase == "active": break
		_check(fixture.interactions.state_for("trap").cycle == 2 and fixture.interactions.state_for("trap").phase == "active", id + " finishes the authored active/end/idle durations and rearms")
		_check(fixture.events.size() > before, id + " can affect units again after the full reset cycle")
		rows.append({"id": id, "buff": buff, "player_damage": player_loss, "enemy_damage": enemy_loss, "contacts": before})
		fixture.environment.free()

func _defensive_states() -> void:
	for state in ["invincible", "_dodge_time", "_block_time"]:
		_reset()
		world.player.combat.set(state, 1.0)
		world._environment_trap({"target_id": "player", "buff_id": "92111023", "camp_mask": "111"})
		_check(world.player.combat.health == 1000 and not world.player.combat.statuses.has("92111063"), state + " rejects trap damage and post-hit slowing")
	_reset()
	world.player.combat.shield = 2
	world.player.combat.armor = 2
	world._environment_trap({"target_id": "player", "buff_id": "92111022", "camp_mask": "111"})
	_check(world.player.combat.health == 999 and world.player.combat.shield == 0 and world.player.combat.armor == 0, "Trap damage consumes shield then armor before health")
	_check(world.impacts.size() == 1 and world.impacts[0].absorbed == 4, "Trap hit feedback records absorption once")
	_reset()
	world.player.combat.add_buff("100200201")
	world._environment_trap({"target_id": "player", "buff_id": "92111022", "camp_mask": "111"})
	_check(world.player.combat.health == 992.5, "Original higher-difficulty trap modifier increases environment damage by fifty percent")
	world.player.combat.receive({"damage": 5.0, "attack_collision": false, "definition": {"actType": "NormalAtk", "element": "Physical"}})
	_check(world.player.combat.health == 987.5, "Environment resistance does not modify ordinary attacks")
	world.player.combat.health = 1
	world._environment_trap({"target_id": "player", "buff_id": "92111022", "camp_mask": "111"})
	var death_contacts := world.impacts.size()
	world._environment_trap({"target_id": "player", "buff_id": "92111022", "camp_mask": "111"})
	_check(world.player.dead and world.player.combat.health == 0 and world.impacts.size() == death_contacts, "Lethal trap damage kills once and rejects further contacts")

func _shared_interval() -> void:
	_reset()
	var fixture := _fixture(definitions["11104"])
	_activate(fixture, Vector3.ZERO, false)
	_check(fixture.events.size() == 1, "Periodic trap initially affects only present player")
	_tick(fixture, 0.1)
	_check(fixture.events.size() == 1 and world.actors[1].combat.health == 1000, "Enemy entering mid-interval waits for shared native countdown")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(fixture.interactions.snapshot()))
	saved.objects.trap.hit_cooldowns = {"player": 0.4, "enemy": 0.1}
	_check(fixture.interactions.restore(saved) and fixture.interactions.state_for("trap").hit_cooldowns == {"*": 0.4}, "Legacy target cooldowns migrate to shared maximum without replay")
	_tick(fixture, 0.39)
	_check(fixture.events.size() == 1, "Restored trap waits the remaining shared interval")
	_tick(fixture, 0.011)
	_check(fixture.events.size() == 3, "Shared interval releases one simultaneous batch for both camps")
	var invalid: Dictionary = JSON.parse_string(JSON.stringify(fixture.interactions.snapshot()))
	invalid.objects.trap.hit_cooldowns["*"] = 99
	_check(not fixture.interactions.restore(invalid), "Saved interval exceeding original configured period is rejected")
	fixture.environment.free()
	_reset()
	fixture = _fixture(definitions["11102"])
	_activate(fixture, Vector3(100, 0, 100), true)
	_check(fixture.events.size() == 1 and fixture.events[0].target_id == "enemy", "Source player-enter trap also detects allowed monster units")
	fixture.environment.free()
	fixture = _fixture(definitions["11107"])
	_tick(fixture, 2.0, Vector3(100, 0, 100), true)
	_check(fixture.events.is_empty() and fixture.interactions.state_for("trap").phase == "idle", "Player-only water does not start for an excluded monster")
	fixture.environment.free()

func _persistent_effects() -> void:
	for buff in ["92111061", "92111063", "92111067"]:
		_reset()
		world._environment_trap({"target_id": "player", "buff_id": buff, "camp_mask": "100"})
		var lifetime := 0.3 if buff == "92111067" else 0.5
		world.player.combat.tick(lifetime - 0.01)
		_check(world.player.combat.statuses.has(buff), buff + " persists for its authored duration after leaving the trap")
		world.player.combat.tick(0.02)
		_check(not world.player.combat.statuses.has(buff) and world.player.combat.move_multiplier() == 1.0, buff + " expires and restores player movement")
	_reset()
	var capacity: float = world.player.combat.skill_capacity(1)
	world._environment_trap({"target_id": "player", "buff_id": "25060501", "camp_mask": "100"})
	world.player.combat.remove_buff("25060501")
	_check(world.player.combat.skill_capacity(1) == capacity, "Removing the trap-room modifier restores original dodge capacity")
	_reset()
	var enemy := world.actors[1]
	world._environment_trap({"target_id": "enemy", "buff_id": "92111071", "camp_mask": "111"})
	world.impacts.clear()
	for step in [0.04, 0.02, 5.1]:
		enemy.combat.tick(step)
		for event in enemy.combat.drain_events(): world._consume(enemy, event)
		if step == 0.04: _check(enemy.combat.health == 1000, "Trap-applied burn waits for the source 50 ms first delay")
		elif step == 0.02: _check(enemy.combat.health == 975, "Trap burn uses the original fire damage definition at the first tick")
	_check(enemy.combat.health == 850 and not enemy.combat.statuses.has("119901"), "Trap burn applies six authored damage ticks and expires after 5.1 seconds")
	_check(world.impacts.size() == 6 and world.impacts.all(func(hit): return hit.source == "player"), "Every burn tick uses normal feedback and retains current-player attribution")
	_check(world.player.combat.health == 1000, "Monster burn cannot leak to nearby player")
	_reset()
	enemy = world.actors[1]
	world._environment_trap({"target_id": "enemy", "buff_id": "92111072", "camp_mask": "111"})
	_check(enemy.combat.attribute("AllElementResist") == -150, "Trap armor-break status reduces elemental resistance by the source amount")
	enemy.combat.receive({"damage": 100.0, "attack_collision": false, "definition": {"actType": "NormalAtk", "element": "Physical"}})
	_check(enemy.combat.health == 635, "Trap armor break affects subsequent ordinary damage through shared combat rules")
	enemy.combat.tick(5.01)
	_check(not enemy.combat.statuses.has("119903") and enemy.combat.attribute("AllElementResist") == 0, "Trap armor break expires and restores resistance")
	rows.append({"case": "persistent_effects", "burn_ticks": 6, "burn_damage": 150})

func _environment_damage() -> void:
	for shape in [65, 135, 136]:
		_reset()
		var fixture := _fixture(definitions["11102"], true, true, shape)
		_activate(fixture)
		_check(fixture.interactions.state_for("near").breaking and fixture.interactions.state_for("near").hp == 0, "Trap shape %d damages intersecting environment with native 9999 tenacity" % shape)
		_check(not fixture.interactions.state_for("far").breaking and fixture.interactions.state_for("far").hp == 50, "Trap shape %d excludes distant props" % shape)
		_tick(fixture, 0.11)
		_check(fixture.interactions.state_for("near").broken, "Trap shape %d respects configured prop break delay" % shape)
		fixture.environment.free()
	var fixture := _fixture(definitions["11104"], false, true)
	_activate(fixture)
	_check(fixture.interactions.state_for("near").hp == 50, "AttackEnvUnit false preserves intersecting scenery")
	fixture.environment.free()

func _source_volumes() -> void:
	var traps := 0
	var volumes := 0
	var initially_disabled := 0
	var scenes := 0
	for filename in DirAccess.open("res://assets/environments").get_files():
		if not filename.ends_with(".markers.json"): continue
		var sidecar: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/environments/" + filename))
		var selected: Array = sidecar.get("semantic_markers", []).filter(func(marker): return marker.Type == "EEUT_TriggerTrap")
		if selected.is_empty(): continue
		var environment := Node3D.new()
		for marker in selected:
			var visual := Node3D.new()
			visual.name = marker.exported_node_name
			environment.add_child(visual)
		var interactions := Interactions.new()
		interactions.setup(environment, selected, {"rules": rules, "colliders": sidecar.markers})
		_check(interactions.diagnostics.is_empty(), filename + " has complete trap configuration and volumes")
		for item in interactions._items.values():
			traps += 1
			item.state.phase = "active"
			item.state.cycle = 1
			var colliders: Array = interactions._volumes(item, "Container_EffectTrigger")
			_check(not colliders.is_empty(), filename + ":" + str(item.id) + " has a source effect trigger")
			for collider in colliders:
				volumes += 1
				if not collider.properties.get("m_Enabled", 1): initially_disabled += 1
				var center: Vector3 = interactions._matrix(collider.world_matrix) * interactions._vector(collider.properties.get("m_Center", {}))
				_check(interactions._contains(item, center, 0, "Container_EffectTrigger"), filename + ":" + str(item.id) + " activates its real source collider center")
		scenes += 1
		environment.free()
	_check(traps == 354 and volumes == 357, "All 354 source trap bindings and 357 effect trigger volumes are covered")
	_check(initially_disabled == 7, "Seven source-disabled ice effect colliders become active during trap firing")
	rows.append({"case": "all_source_colliders", "scenes": scenes, "traps": traps, "effect_volumes": volumes, "initially_disabled": initially_disabled})

func _attraction_fixture(source_marker: Dictionary = {}, source_colliders: Array = []) -> Dictionary:
	var definition: Dictionary = rules.Definitions.filter(func(row): return str(row.ID) == "11101")[0].duplicate(true)
	var marker: Dictionary = source_marker if not source_marker.is_empty() else _marker("quicksand", "EEUT_AttractTrap")
	var colliders: Array = source_colliders if not source_colliders.is_empty() else [_volume("quicksand", "Container_EffectTrigger")]
	var source_rules := rules if not source_marker.is_empty() else {"Definitions": [definition], "Bindings": [{"SceneName": "TrapTest", "SourceGameObjectId": "quicksand", "ConfigId": "11101", "SupportsRules": true, "AttractTargetPosition": [0, 0, 0], "AttractTargetForward": [0, 0, 1]}]}
	var environment := Node3D.new()
	var visual := Node3D.new()
	visual.name = marker.exported_node_name
	environment.add_child(visual)
	var interactions := Interactions.new()
	var fixture := {"environment": environment, "interactions": interactions, "events": []}
	interactions.attraction_requested.connect(func(event): fixture.events.append(event); world._environment_attract(event))
	interactions.setup(environment, [marker], {"rules": source_rules, "colliders": colliders})
	return fixture

func _source_attraction() -> void:
	var count := 0
	for scene in ["LevelMap_1020601", "LevelMap_1020701"]:
		var sidecar: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/environments/" + scene + ".markers.json"))
		for marker in sidecar.semantic_markers:
			if marker.Type != "EEUT_AttractTrap": continue
			_reset()
			var fixture := _attraction_fixture(marker, sidecar.markers)
			var item: Dictionary = fixture.interactions._items[str(marker.SourceGameObjectId)]
			var center := Interactions._vector(item.binding.AttractTargetPosition)
			world.player.position = center + Vector3.RIGHT
			world.actors[1].position = center - Vector3.RIGHT
			fixture.interactions.tick(0.02, world.player.position, [{"id": "enemy", "position": world.actors[1].position, "camp": 3}])
			_check(fixture.interactions.diagnostics.is_empty(), scene + " quicksand has exact config and target binding")
			_check(world.player.position.is_equal_approx(center + Vector3.RIGHT * 0.96), scene + " quicksand applies force 200 divided by native weight 100")
			_check(world.actors[1].position.is_equal_approx(center - Vector3.RIGHT) and fixture.events.size() == 1, scene + " quicksand excludes monsters using EffectCamp 100")
			_check(world.player.combat.health == 1000 and world.impacts.is_empty(), scene + " quicksand moves without inventing damage")
			_check(fixture.interactions.restore(JSON.parse_string(JSON.stringify(fixture.interactions.snapshot()))), scene + " quicksand state restores")
			var legacy: Dictionary = JSON.parse_string(JSON.stringify(fixture.interactions.snapshot()))
			legacy.fingerprint = JSON.stringify([scene, [[str(marker.SourceGameObjectId), "EEUT_AttractTrap", JSON.parse_string(marker.DataJson), ""]]]).sha256_text()
			_check(fixture.interactions.restore(legacy), scene + " accepts the exact previous scene fingerprint without the formerly unsupported attraction binding")
			_check(fixture.interactions.snapshot().fingerprint != legacy.fingerprint, scene + " upgraded save records the complete attraction binding")
			legacy.fingerprint = "unrelated_scene_fingerprint"
			_check(not fixture.interactions.restore(legacy), scene + " still rejects unrelated scene revisions")
			fixture.environment.free()
			count += 1
	_check(count == 3, "All three APK quicksand instances run through actual source effect volumes")
	rows.append({"case": "source_attraction", "traps": count, "source_force": 200, "player_base_weight": 100})

func _attraction_rules() -> void:
	_reset()
	var fixture := _attraction_fixture()
	var item: Dictionary = fixture.interactions._items.quicksand
	var combat := world.player.combat
	world.player.position = Vector3.RIGHT
	fixture.interactions.tick(0.2, world.player.position)
	_check(world.player.position.is_equal_approx(Vector3.RIGHT * 0.6), "Quicksand movement is applied throughout the simulation interval: " + str(world.player.position))
	var before: int = fixture.events.size()
	world.player.position = Vector3.ZERO
	fixture.interactions.tick(0.02, world.player.position)
	_check(world.player.position == Vector3.ZERO and fixture.events.size() == before, "Quicksand center produces no invalid normalized force")
	world.player.position = Vector3.RIGHT * 30
	fixture.interactions.tick(0.02, world.player.position)
	_check(world.player.position == Vector3.RIGHT * 30, "Outside the trigger there is no attraction")
	for state in ["dead", "health", "suspended", "behit_1_sword", "skill_axe_liedichongjibo", "skill_axe_sanlianzhan"]:
		world.player.position = Vector3.RIGHT
		world.player.dead = state == "dead"
		world.player.suspended = state == "suspended"
		combat.health = 0 if state == "health" else 1000
		combat.current_action = state if state.begins_with("behit") or state.begins_with("skill") else ""
		fixture.interactions.tick(0.02, world.player.position)
		_check(world.player.position == Vector3.RIGHT, "Quicksand rejects " + state)
	world.player.dead = false
	world.player.suspended = false
	combat.health = 1000
	combat.current_action = ""
	for state in ["normal", "dodge", "invincible"]:
		world.player.position = Vector3.RIGHT
		combat._dodge_time = 1 if state == "dodge" else 0
		combat.invincible = 1 if state == "invincible" else 0
		fixture.interactions.tick(0.02, world.player.position)
		_check(world.player.position.is_equal_approx(Vector3.RIGHT * 0.96), "Quicksand allows native attraction during " + state)
	combat._dodge_time = 0
	combat.invincible = 0
	var source_actions := 0
	for action in DungeonCombat.EnemyHitReaction._action_states:
		if not str(action).begins_with("ActGroup_playerchara/"): continue
		combat.current_action = str(action).trim_prefix("ActGroup_playerchara/")
		var state := int(DungeonCombat.EnemyHitReaction._action_states[action])
		_check(combat.can_be_attracted() == (state not in [6, 31, 32]), "Native attraction action-state restriction " + str(action))
		source_actions += 1
	combat.current_action = ""
	combat.stagger_remaining = 0.1
	_check(not combat.can_be_attracted(), "Active player hit reaction suppresses attraction")
	combat.stagger_remaining = 0
	combat._external.Weight = 100
	world.player.position = Vector3.RIGHT
	fixture.interactions.tick(0.02, world.player.position)
	_check(world.player.position.is_equal_approx(Vector3.RIGHT * 0.98) and combat.attraction_weight() == 200, "Weight attributes reduce the actual pull displacement")
	combat._external.Weight = -100
	_check(combat.attraction_weight() == 100, "Invalid zero weight cannot produce non-finite movement")
	combat._external.erase("Weight")
	item.definition.AttractDistancePercent = 25
	world.player.position = Vector3.RIGHT * 2
	fixture.interactions.tick(0.02, world.player.position)
	_check(world.player.position.is_equal_approx(Vector3.RIGHT * 1.98), "Native attraction percentage decreases force with point distance")
	item.definition.DirType = "Dir"
	item.binding.AttractTargetForward = [2, 0, 0]
	world.player.position = Vector3.ZERO
	fixture.interactions.tick(0.02, world.player.position)
	_check(world.player.position.is_equal_approx(Vector3.RIGHT * 0.03), "Directional attraction uses normalized source forward and native distance factor: " + str(world.player.position))
	item.definition.DirType = "Point"
	item.definition.AttractDistancePercent = 0
	item.definition.EffectActiveInterval = 0.1
	world.player.position = Vector3.RIGHT
	fixture.interactions.tick(0.08, world.player.position)
	_check(world.player.position == Vector3.RIGHT, "Attraction interval waits before activation")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(fixture.interactions.snapshot()))
	fixture.interactions.tick(0.02, world.player.position)
	_check(world.player.position.is_equal_approx(Vector3.RIGHT * 0.96), "Attraction interval applies the triggering tick force")
	_check(fixture.interactions.restore(saved), "Attraction restores an unfinished interval")
	world.player.position = Vector3.RIGHT
	fixture.interactions.tick(0.02, world.player.position)
	_check(world.player.position.is_equal_approx(Vector3.RIGHT * 0.96), "Attraction interval timing survives JSON restoration")
	fixture.environment.free()
	rows.append({"case": "attraction_rules", "source_player_actions": source_actions})

func _disabled_traps() -> void:
	for kind in ["damage", "attraction"]:
		_reset()
		var fixture := _fixture(definitions["11102"]) if kind == "damage" else _attraction_fixture()
		var id := "trap" if kind == "damage" else "quicksand"
		world.interactions = fixture.interactions
		if kind == "damage": _activate(fixture)
		world._consume(world.player, {"type": "message", "definition": {"MessageName": "EnvUnit_DisableAllTraps"}})
		var state: Dictionary = fixture.interactions.state_for(id)
		_check(not state.enabled and state.phase == "idle" and state.hits_once.is_empty() and state.hit_cooldowns.is_empty(), kind + " trap disable message clears behavior and target history")
		_check(fixture.environment.get_child(0).visible, kind + " trap disable preserves scene geometry")
		var saved: Dictionary = JSON.parse_string(JSON.stringify(fixture.interactions.snapshot()))
		fixture.interactions._items[id].state.enabled = true
		_check(fixture.interactions.restore(saved) and not fixture.interactions.state_for(id).enabled, kind + " trap disabled state survives JSON restoration")
		var before: int = fixture.events.size()
		world.player.position = Vector3.RIGHT
		fixture.interactions.tick(2, world.player.position)
		_check(fixture.events.size() == before and world.player.position == Vector3.RIGHT, kind + " disabled trap remains inert")
		_check(fixture.interactions.disable_traps() == 0, kind + " repeated disable message is idempotent")
		fixture.environment.free()
	rows.append({"case": "disabled_traps", "types": 2})

func _attraction_wall() -> void:
	_reset()
	var fixture := _attraction_fixture()
	world.player.collision_layer = 2
	world.player.collision_mask = 1
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.1, 3, 4)
	wall_shape.shape = box
	wall.add_child(wall_shape)
	world.add_child(wall)
	wall.position = Vector3(0.5, 1, 0)
	world.player.position = Vector3.RIGHT
	await physics_frame
	await physics_frame
	fixture.interactions.tick(0.3, world.player.position)
	_check(world.player.position.x >= 0.899 and world.player.position.x < 1.0, "Actual CharacterBody collision prevents quicksand from pulling through a wall")
	wall.free()
	fixture.environment.free()
	rows.append({"case": "attraction_wall"})

func _marker(id: String, type: String) -> Dictionary:
	return {"SceneName": "TrapTest", "SourceGameObjectId": id, "Type": type, "Path": [id], "DataJson": "{}", "exported_node_name": id, "world_position": [0, 0, 0]}

func _volume(id: String, role: String) -> Dictionary:
	return {"fileID": id + role, "path": "TrapTest/" + id + ("/" + role if not role.is_empty() else ""), "kind": 65, "active": true, "world_matrix": [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1], "properties": {"m_Size": {"x": 12, "y": 2, "z": 12}, "m_Center": {"x": 0, "y": 1, "z": 0}, "m_IsTrigger": 1, "m_Enabled": 1}}

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)
