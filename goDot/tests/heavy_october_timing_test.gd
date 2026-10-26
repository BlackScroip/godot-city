extends SceneTree

const Combat = preload("res://scripts/domain/combat.gd")
const Actor = preload("res://scripts/actor.gd")
var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _initialize() -> void:
	_source_fingerprints()
	_source_rates()
	_boundary_admission()
	_source_data_fixes()
	_buff_effects()
	print("HEAVY_OCTOBER_TIMING ", JSON.stringify({"checks": checks, "failures": failures}))
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _source_fingerprints() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/heavy_october_actions.json"))
	var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/heavy_attacks.json"))
	var combat := Combat.new()
	combat.configure()
	check(fixture.apk_sha256 == "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505" and metadata.apk_sha256 == fixture.apk_sha256, "Heavy data identifies the supplied October APK")
	check(fixture.actions.size() == 30 and fixture.actions.keys() == metadata.actions.keys(), "Exactly the 30 implemented source heavy action records are covered")
	for ident in fixture.actions:
		var expected: Dictionary = fixture.actions[ident]
		var actual: Dictionary = combat._action("ActGroup_playerchara", ident)
		check(actual.duration == expected.duration and actual.speed == expected.speed, "%s keeps authored duration and base speed" % ident)
		check(metadata.actions[ident].can_hit == expected.can_hit and metadata.actions[ident].stable_value == expected.stable_value and metadata.actions[ident].source_sha256 == expected.source_sha256, "%s metadata retains verified source record hash" % ident)
		check(actual.apk_source.bundle_sha256 == "e31037e53f323b93419c79a8f03e934b6e0ad2ca49fc9eb255c0e797071371f7", "%s comes from verified source bundle" % ident)
		for kind in ["events", "hits"]:
			check(actual[kind].size() == expected[kind].size(), "%s %s count matches source" % [ident, kind])
			for index in mini(actual[kind].size(), expected[kind].size()):
				var command: Dictionary = actual[kind][index]
				var source: Dictionary = expected[kind][index]
				for field in ["time", "duration", "enabled", "all"]:
					check(command.get(field) == source[field], "%s %s %d %s matches source" % [ident, kind, index, field])
				if kind == "events": check(command.type == source.type, "%s event %d type matches source" % [ident, index])
				check(str(command.raw).sha256_text() == source.raw_sha256, "%s %s %d raw payload matches source" % [ident, kind, index])
				var condition_hashes: Array = []
				for condition in command.conditions: condition_hashes.append(str(condition.raw).sha256_text())
				check(condition_hashes == source.condition_sha256, "%s %s %d trigger conditions match source" % [ident, kind, index])

func _source_rates() -> void:
	for row in [[1, "sword_satk_normal_ready", 2.0], [5, "bow_satk", 2.0], [3, "axe_satk_end", 2.0], [8, "blade_satk_start", 2.0], [7, "lance_satk_nomal2", 3.0], [7, "lance_satk_special", 3.0]]:
		var combat := Combat.new()
		combat.configure(null, null, row[0])
		combat._start(combat._action("ActGroup_playerchara", row[1]), 4)
		combat.tick(0.05)
		check(is_equal_approx(combat.action_elapsed, 0.05 * float(row[2])), "%s executes its source local speed window" % row[1])
		check(not combat.custom_properties._rhythm_enabled and is_zero_approx(combat._recovery_credit), "%s uses source time without custom windup/impact warping" % row[1])
		combat.drain_events()
	for faith in [0, 20]:
		var combat := Combat.new()
		combat.configure(null, null, 6)
		if faith > 0: combat.add_buff("600100", faith)
		combat._start(combat._action("ActGroup_playerchara", "orb_satk_start"), 4)
		combat.tick(0.1)
		check(is_equal_approx(combat.action_elapsed, 0.2 if faith == 0 else 0.4), "Orb admits the authored faith-dependent rate for %d faith" % faith)
	for row in [["701100", 1.5], ["701200", 2.0], ["701300", 3.0]]:
		var combat := Combat.new()
		combat.configure(null, null, 7)
		combat.add_buff(row[0])
		combat.request_attack(4)
		combat.tick(0.1)
		check(is_equal_approx(combat.action_elapsed, 0.1 * float(row[1])), "Lance %s admits source charge speed" % row[0])

func _fixture(add_at: float, remove_at := -1.0) -> Combat:
	var combat := Combat.new()
	combat.configure()
	var commands: Array = [
		{"type": "EET_AddBuff", "time": add_at, "duration": 0.0, "enabled": true, "buff": "140401", "layers": 1, "raw": "{}"},
		{"type": "EET_ActionSpeedScale", "time": 0.2, "duration": 0.3, "enabled": true, "all": true, "conditions": [{"type": "EECT_CheckBuffExist", "buff": "140401", "exists": true, "layers": 1, "compare": "ECT_GreaterEqual"}], "raw": '{"ScaleSpeed":3}'}]
	if remove_at >= 0:
		commands.append({"type": "EET_AddBuff", "time": remove_at, "duration": 0.0, "enabled": true, "buff": "140401", "layers": -1, "raw": "{}"})
	var hit: Dictionary = combat._action("ActGroup_playerchara", "sword_atk1").hits[0].duplicate(true)
	hit.time = 0.3
	combat._start({"id": "timing_fixture", "duration": 1.0, "speed": 1.0, "events": commands, "hits": [hit]}, 4)
	combat.drain_events()
	return combat

func _boundary_admission() -> void:
	for hz in [30, 60, 120]:
		var combat := _fixture(0.1, 0.25)
		var hits: Array = []
		for frame in range(int(hz * 0.6)):
			combat.tick(1.0 / hz)
			for emitted in combat.drain_events():
				if emitted.type == "hit": hits.append(emitted)
		check(is_equal_approx(combat.action_elapsed, 0.8), "Rate boundary integration is independent of %dHz ticks" % hz)
		check(hits.size() == 1 and absf(float(hits[0].clock) - (0.2 + 0.1 / 3)) < 0.00001, "Hit crosses its source boundary exactly at %dHz" % hz)
		check(combat.buff_layers("140401") == 0, "Removing entry condition buff does not cancel an admitted rate at %dHz" % hz)
	var coarse := _fixture(0.1, 0.25)
	coarse.tick(0.6)
	check(is_equal_approx(coarse.action_elapsed, 0.8), "One coarse update executes preceding commands before conditional rate admission")
	var failed := _fixture(0.25)
	failed.tick(0.6)
	check(is_equal_approx(failed.action_elapsed, 0.6), "A failed entry condition cannot become eligible later in its duration")
	var original := _fixture(0.1, 0.25)
	original.tick(0.22)
	original.drain_events()
	var restored := Combat.new()
	restored.configure()
	check(restored.restore(JSON.parse_string(JSON.stringify(original.snapshot()))), "Admitted windows survive serialization after their condition buff is removed")
	original.tick(0.1)
	restored.tick(0.1)
	check(is_equal_approx(original.action_elapsed, restored.action_elapsed), "Restored local clock retains its admitted speed")
	check(original.drain_events().filter(func(event): return event.type == "hit").size() == restored.drain_events().filter(func(event): return event.type == "hit").size(), "Restore does not repeat or drop a pending hit")
	var paused := _fixture(0.1)
	paused.tick(0.2)
	paused.apply_hit_stop(0.05, true)
	paused.tick(0.1)
	check(is_equal_approx(paused.action_elapsed, 0.35) and is_zero_approx(paused._recovery_credit), "Hit pause holds the source clock without inventing a heavy recovery speedup")
	var actor := Actor.new()
	actor.combat = coarse
	actor.begin_action({"duration": 1.0, "speed": 1.0, "timeline_duration": 1.0})
	actor._action_displacement()
	check(is_equal_approx(actor.action_cursor, coarse.action_elapsed), "Actor pose and root motion consume the same accelerated action cursor")
	actor.free()
	check(coarse.diagnostics.is_empty() and failed.diagnostics.is_empty() and paused.diagnostics.is_empty(), "Boundary integration completes without timeline diagnostics")
	coarse.drain_events()
	failed.drain_events()
	paused.drain_events()

func _source_data_fixes() -> void:
	var combat := Combat.new()
	combat.configure()
	var repeat := false
	for command in combat._action("ActGroup_playerchara", "sword_satk_normal_attack").events:
		if command.type == "EET_Interrupt" and command.target == "sword_satk_normal_attack" and command.conditions.any(func(condition): return condition.buff == "140401"):
			repeat = true
			check(not command.enabled, "October sword weapon-specific repeat stays disabled")
	check(repeat, "Disabled original sword repeat remains in the source catalog")
	for command in combat._action("ActGroup_playerchara", "axe_satk_loop").events:
		if command.type == "EET_AddBuff" and command.buff == "393201": check(not command.enabled, "October axe does not enable the old extra buff")
	var sickle := Combat.new()
	sickle.configure(null, null, 2)
	sickle.add_buff("241200")
	sickle.add_buff("200200", 20)
	sickle.request_attack(4)
	sickle.tick(0.11)
	check(sickle.buff_layers("200202") > 0, "October sickle weapon transformation executes its added 200ms source event")

func _buff_effects() -> void:
	var combat := Combat.new()
	combat.configure()
	combat.health -= 10
	combat.drain_events()
	var healing := ""
	var counter := ""
	for id in combat._buff_index:
		var definition: Dictionary = combat._buff_index[id]
		var raw: Dictionary = definition.get("raw_data", {})
		if definition.type == "EBT_SpecialBuffHP" and not str(raw.get("StartEffect", "")).is_empty(): healing = id
		if definition.type == "EBT_SpecialCounterTrigger" and not str(raw.get("PlayEffectWhenLayerMax", "")).is_empty(): counter = id
	check(not healing.is_empty() and not counter.is_empty(), "Visual event checks use authored healing and counter buffs")
	if not healing.is_empty():
		combat.add_buff(healing)
		check(combat.drain_events().any(func(event): return event.type == "buff_effect" and event.id == healing and event.phase == "start" and event.definition == combat._buff_index[healing].raw_data), "Instant healing exposes its exact source StartEffect payload")
	if not counter.is_empty():
		combat.add_buff(counter, int(combat._buff_index[counter].maxLayers))
		check(combat.drain_events().any(func(event): return event.type == "buff_effect" and event.id == counter and event.phase == "counter_max" and event.definition == combat._buff_index[counter].raw_data), "Counter threshold exposes its exact source effect before layer reduction")
