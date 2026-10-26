extends SceneTree

const Combat = preload("res://scripts/domain/combat.gd")
const Reference = preload("res://tests/fixtures/status_substeps_reference.gd")
const Boundaries = preload("res://tests/fixtures/empty_status_cases.gd")
var checks := 0
var boundary_checks := 0
var action_pairs := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok and failures.size() < 40: failures.append(label)

func _events(actor: DungeonCombat) -> Array:
	var result := actor.drain_events().duplicate(true)
	for event in result:
		if event.get("source") is DungeonCombat:
			check(is_same(event.source, actor), "Event source points to its own combat instance")
			event.source = actor.actor_key
	return result

func _equal(pair: Array, label: String) -> void:
	check(pair[0].snapshot() == pair[1].snapshot(), "Snapshot differs: " + label)
	check(pair[0].impact_pause == pair[1].impact_pause and pair[0].stagger_remaining == pair[1].stagger_remaining and pair[0].action_step == pair[1].action_step and pair[0].action_tick_delta == pair[1].action_tick_delta and pair[0]._condition_depth == pair[1]._condition_depth, "Timers/depth differ: " + label)
	check(_events(pair[0]) == _events(pair[1]), "Events differ: " + label)

func _enemies(catalog: Dictionary) -> void:
	for enemy in catalog.enemies:
		var pair := [Combat.new(), Reference.new()]
		for actor in pair:
			check(actor.configure_enemy(int(enemy.id), 731).success, "Enemy configures: %d" % int(enemy.id))
			actor.enemy_ai_enabled = true
		for action in catalog.actions:
			if action.group != enemy.group: continue
			action_pairs += 1
			for actor in pair:
				actor.health = actor.max_health
				actor._start(action, 0)
			for delta in [0.0, 0.000001, 0.0000010001, 1.0 / 120, 1.0 / 60, 1.0 / 30, 0.1]:
				for actor in pair: actor.tick(delta)
				_equal(pair, "%d/%s/%.10f" % [int(enemy.id), action.id, delta])
		for actor in pair: actor.configure_enemy(int(enemy.id), 731)
		for frame in 240:
			var delta: float = [1.0 / 30, 1.0 / 60, 1.0 / 120][frame % 3]
			var context := {"target_available": frame % 43 < 37, "distance": [1.0, 3.5, 9.0][(frame / 20) % 3], "line_blocked": frame % 50 > 40, "battle_time": frame / 60.0, "monster_index": frame % 3, "target_buffs": []}
			var decisions: Array = []
			for actor in pair:
				actor.health = actor.max_health * (1.0 if frame < 120 else 0.25)
				actor.custom_properties["EnemyDistances"] = [context.distance]
				if frame == 35: actor.frozen = 0.05
				if frame == 65: actor.apply_hit_stop(0.04)
				if frame == 95: actor.apply_stagger(0.05)
				decisions.append(actor.tick_enemy_ai(delta, context))
				actor.tick(delta)
			check(decisions[0] == decisions[1], "AI decisions differ: %d/%d" % [int(enemy.id), frame])
			_equal(pair, "enemy runtime %d/%d" % [int(enemy.id), frame])
			if frame in [79, 159]:
				for actor in pair: check(actor.restore(JSON.parse_string(JSON.stringify(actor.snapshot()))), "Enemy JSON snapshot restores")
				_equal(pair, "enemy restored %d/%d" % [int(enemy.id), frame])

func _players(catalog: Dictionary) -> void:
	for character in catalog.characters:
		var pair := [Combat.new(), Reference.new()]
		for actor in pair: check(actor.configure(null, null, int(character.id), 0, 731).success, "Character configures: %d" % int(character.id))
		for frame in 600:
			var delta: float = [1.0 / 30, 1.0 / 60, 1.0 / 120][frame % 3]
			for actor in pair:
				actor.health = maxf(1, actor.health)
				if frame % 60 == 0:
					var slot: int = (frame / 60) % 5
					actor._start(actor._action("ActGroup_playerchara", str(character.skills[slot].action)), slot)
				if frame == 130: actor.apply_hit_stop(0.04)
				if frame == 260: actor.apply_stagger(0.05)
				if frame == 300: actor.statuses.clear()
				if frame == 360: actor.add_buff("41300104", 1)
				if frame == 420: actor.add_buff(str(character.passives[0]), 1)
				actor.tick(delta)
			_equal(pair, "character %d/%d" % [int(character.id), frame])
			if frame in [199, 399]:
				for actor in pair: check(actor.restore(JSON.parse_string(JSON.stringify(actor.snapshot()))), "Character JSON snapshot restores")
				_equal(pair, "character restored %d/%d" % [int(character.id), frame])

func _run() -> void:
	Boundaries.run(func(ok, label):
		boundary_checks += 1
		check(ok, label))
	check(boundary_checks == 338, "All 338 boundary assertions execute")
	var fixture := Combat.new()
	fixture.configure()
	var original := fixture.catalog.duplicate(true)
	_enemies(fixture.catalog)
	_players(fixture.catalog)
	check(fixture.catalog == original, "Status optimization preserves source catalog")
	var report := {"checks": checks, "boundary_checks": boundary_checks, "enemies": fixture.catalog.enemies.size(), "characters": fixture.catalog.characters.size(), "source_action_pairs": action_pairs, "failures": failures, "passed": failures.is_empty(), "scope": "Original 0.01-second segment interpreter versus empty-status fast path. Full snapshots, pending timeline, emitted events/source identity, AI/RNG, timers, skill energy/cooldowns, JSON replay, 338 delta/recursion/health/empty-state boundaries, all source enemies/actions and eight player characters at mixed 30/60/120Hz. Desktop logic validation, not APK runtime or Android FPS."}
	FileAccess.open("res://reports/empty-status-optimization.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("EMPTY_STATUS_OPTIMIZATION ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
