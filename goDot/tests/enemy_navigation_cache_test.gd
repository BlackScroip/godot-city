extends SceneTree

const Combat = preload("res://scripts/domain/combat.gd")
const Reference = preload("res://tests/fixtures/navigation_reference.gd")
const Candidate = preload("res://scripts/domain/combat.gd")
var checks := 0
var failures: Array[String] = []
var source_pairs := 0
var source_windows := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok and failures.size() < 30: failures.append(message)

func _pair(id: int, data: Variant = null) -> Array:
	var pair := [Reference.new(), Candidate.new()]
	for actor in pair: check(actor.configure_enemy(id, 731, 0, data).success, "configure %d" % id)
	return pair

func _probe(pair: Array, elapsed: float, speed: Variant, label: String) -> void:
	var result: Array = []
	for actor in pair:
		actor.action_elapsed = elapsed
		if speed == null: actor.custom_properties.erase("_feel_action_speed")
		else: actor.custom_properties["_feel_action_speed"] = speed
		result.append(actor.enemy_navigation_requested())
	check(result[0] == result[1], "navigation differs " + label)

func _boundaries(pair: Array, action: Dictionary, label: String) -> void:
	for actor in pair: actor.current_action = str(action.id)
	var probes: Array = [-1.0, 0.0, 1.0 / 120, 1.0 / 60, 1.0 / 30, float(action.get("duration", 0)), NAN, INF, -INF]
	for command in action.get("events", []):
		if not command.get("enabled", false) or command.get("type", "") != "EET_Navigation": continue
		source_windows += 1
		for boundary in [float(command.get("time", 0)), float(command.get("time", 0)) + float(command.get("duration", 0))]:
			for epsilon in [-0.000002, -0.0000005, -0.000000000001, 0.0, 0.000000000001, 0.0000005, 0.000002]: probes.append(boundary + epsilon)
	for speed in [null, -2.0, 0.0, 0.009, 0.01, 0.75, 1.0, 1.5, 2.0, "1.25"]:
		var divisor := maxf(0.01, float(speed if speed != null else 1.0))
		for elapsed in probes:
			_probe(pair, float(elapsed) / divisor, speed, label)
	_probe(pair, 0.25, 1.0, label + " finite snapshot state")
	check(pair[0].snapshot() == pair[1].snapshot(), "query preserves snapshots " + label)

func _source(catalog: Dictionary) -> void:
	for enemy in catalog.enemies:
		var pair := _pair(int(enemy.id))
		for action in catalog.actions:
			if action.group != enemy.group: continue
			source_pairs += 1
			_boundaries(pair, action, "%d/%s" % [int(enemy.id), str(action.id)])
		for actor in pair: actor.current_action = "run"
		for health in [-1.0, 0.0, 0.000001, 5.0]:
			for actor in pair: actor.health = health
			_probe(pair, 0.1, 1.0, "health %d/%s" % [int(enemy.id), str(health)])

func _synthetic() -> void:
	var actions: Array = []
	for name in ["run", "RuN", "forward", "FORWARD", "dash", "running", "meaninglessrun", "idle", "unknown", "", "custom"]:
		actions.append({"id": name, "group": "Fixture", "key": "Fixture/" + name, "duration": 3.0, "events": []})
	var commands: Array = [
		{}, {"enabled": false, "type": "EET_Navigation", "time": 0.0, "duration": 10.0},
		{"enabled": true, "type": "other", "time": 0.0, "duration": 10.0},
		{"enabled": true, "type": "EET_Navigation"},
		{"enabled": 1, "type": "EET_Navigation", "time": -1.0, "duration": 0.25},
		{"enabled": true, "type": "EET_Navigation", "time": 1.0, "duration": 0.0},
		{"enabled": true, "type": "EET_Navigation", "time": 2.0, "duration": -0.5},
		{"enabled": true, "type": "EET_Navigation", "time": 0.1000000001, "duration": 0.0000000001},
		{"enabled": true, "type": "EET_Navigation", "time": 16777217.0, "duration": 0.000001},
		{"enabled": true, "type": "EET_Navigation", "time": "0.3", "duration": "0.2"},
		{"enabled": true, "type": "EET_Navigation", "time": INF, "duration": 1.0},
		{"enabled": true, "type": "EET_Navigation", "time": NAN, "duration": 1.0}
	]
	var custom: Dictionary = actions.back()
	custom.events = commands
	var data := {"actions": actions, "enemies": [{"id": 1, "group": "Fixture", "attack": 1, "hp": 100, "ai": "none"}], "buffs": [], "summons": []}
	var pair := _pair(1, data)
	for action in actions: _boundaries(pair, action, "synthetic " + str(action.id))
	for actor in pair:
		actor.current_action = "custom"
		actor._action_index = actor._action_index.duplicate()
	_probe(pair, 0.4, 1.0, "before dictionary replacement")
	var replacement: Dictionary = custom.duplicate(true)
	replacement.events = [{"enabled": true, "type": "EET_Navigation", "time": 2.0, "duration": 0.5}]
	for actor in pair: actor._action_index["Fixture/custom"] = replacement
	_probe(pair, 0.4, 1.0, "replaced definition removes window")
	_probe(pair, 2.25, 1.0, "replaced definition adds window")
	for actor in pair: actor._action_index["Fixture/custom"] = replacement.duplicate(true)
	_probe(pair, 2.25, 1.0, "equal value new identity")
	for actor in pair: actor._action_index.erase("Fixture/custom")
	_probe(pair, 2.25, 1.0, "definition erased")
	for actor in pair: actor._action_index["Fixture/custom"] = custom
	_probe(pair, 0.4, 1.0, "definition reintroduced")
	for actor in pair: actor.enemy = {}
	_probe(pair, 0.4, 1.0, "empty enemy")
	for actor in pair:
		check(actor.configure_enemy(11001, 129).success, "reconfigure enemy")
		actor.current_action = "run"
	_probe(pair, 0.4, 1.0, "reconfigured enemy")
	for actor in pair: check(actor.configure(null, null, 1).success, "reconfigure player")
	_probe(pair, 0.4, 1.0, "reconfigured player")

func _events(actor: DungeonCombat) -> Array:
	var events: Array = actor.drain_events().duplicate(true)
	for event in events:
		if event.get("source") is DungeonCombat:
			check(is_same(event.source, actor), "event source retained")
			event.source = actor.actor_key
	return events

func _runtime(catalog: Dictionary) -> void:
	for enemy in catalog.enemies:
		var pair := _pair(int(enemy.id))
		for frame in 120:
			var delta: float = [1.0 / 30, 1.0 / 60, 1.0 / 120][frame % 3]
			var context := {"target_available": frame % 43 < 37, "distance": [1.0, 3.5, 9.0][(frame / 20) % 3], "line_blocked": frame % 50 > 40, "battle_time": frame / 60.0, "monster_index": frame % 3, "target_buffs": []}
			var decisions: Array = []
			var requested: Array = []
			for actor in pair:
				actor.health = actor.max_health * (1.0 if frame < 60 else 0.25)
				decisions.append(actor.tick_enemy_ai(delta, context))
				requested.append(actor.enemy_navigation_requested())
				actor.tick(delta)
			check(decisions[0] == decisions[1] and requested[0] == requested[1], "runtime decision %d/%d" % [int(enemy.id), frame])
			check(pair[0].snapshot() == pair[1].snapshot(), "runtime snapshot %d/%d" % [int(enemy.id), frame])
			check(_events(pair[0]) == _events(pair[1]), "runtime events %d/%d" % [int(enemy.id), frame])
			if frame in [39, 79]:
				for actor in pair: check(actor.restore(JSON.parse_string(JSON.stringify(actor.snapshot()))), "JSON restore")
				_probe(pair, pair[0].action_elapsed, null, "restored %d/%d" % [int(enemy.id), frame])

func _run() -> void:
	var tested_source := {"started_utc": Time.get_datetime_string_from_system(true) + "Z", "before_sha256": FileAccess.get_sha256("res://scripts/domain/combat.gd")}
	var actor := Combat.new()
	actor.configure()
	var original: Dictionary = actor.catalog.duplicate(true)
	_source(actor.catalog)
	var authored_windows := source_windows
	_synthetic()
	_runtime(actor.catalog)
	check(original == actor.catalog, "catalog remains unchanged")
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "enemies": actor.catalog.enemies.size(), "source_action_pairs": source_pairs, "source_navigation_windows": authored_windows, "scope": "Isolated cached float64 navigation windows versus exact original method. All source actions, direct action assignment, epsilon/negative/zero durations, dynamic speed, health, empty enemy, dictionary identity replacement/erasure, reconfiguration, mixed 30/60/120Hz runtime, snapshots and emitted events."}
	tested_source["after_sha256"] = FileAccess.get_sha256("res://scripts/domain/combat.gd")
	report["tested_source"] = tested_source
	FileAccess.open("res://reports/enemy-navigation-cache.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("NAVIGATION_TEST ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
