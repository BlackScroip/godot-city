extends SceneTree

const Combat = preload("res://scripts/domain/combat.gd")

var checks := 0
var failures: Array[String] = []
var cases: Array = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var audit_path = "res://reports/boss-ability-source.json"
	if not FileAccess.file_exists(audit_path):
		_check(false, "Run tools/audit_boss_abilities.py before the dependency smoke test")
	else:
		var audit: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(audit_path))
		_check(bool(audit.get("passed", false)), "Fresh source parity audit passes")
		var ids: Dictionary = audit.get("fresh_source_parity", {}).get("closure_ids", {})
		_check(ids.get("buff", []).size() == 82, "All 82 fresh-source Boss buffs are enumerated")
		_check(ids.get("summon", []).size() == 134, "All 134 fresh-source Boss summons are enumerated")
		_check(ids.get("damage", []).size() == 74, "All 74 fresh-source Boss damage definitions are enumerated")
		for id in ids.get("buff", []): _buff_case(str(id))
		for id in ids.get("summon", []): _summon_case(str(id))
	var report = {"passed": failures.is_empty(), "checks": checks, "failures": failures, "cases": cases,
		"scope": "Each of the complete fresh-source Boss closure's 82 buffs and 134 summons is individually initialized in the Godot domain and advanced two seconds. Buff cases also receive representative injured/action/message notifications. Hit payloads are checked for finite nonnegative damage. Static-range world-adapter dispatch is retained explicitly. This is initialization/dispatch smoke coverage, not every condition branch, full-lifetime behavior, collision, world entity or rendered-effect coverage."}
	FileAccess.open("res://reports/boss-dependency-test.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("BOSS_DEPENDENCY ", JSON.stringify({"passed": failures.is_empty(), "checks": checks, "cases": cases.size(), "failure_count": failures.size(), "failures": failures.slice(0, 15)}))
	quit(0 if failures.is_empty() else 1)

func _unit() -> DungeonCombat:
	var unit = Combat.new()
	_check(unit.configure_enemy(13001, 731).success, "Boss smoke fixture configures")
	unit.enemy_ai_enabled = true
	unit.custom_properties["EnemyDistances"] = [2.0]
	return unit

func _buff_case(id: String) -> void:
	var unit = _unit()
	var definition: Dictionary = unit._buff_index.get(id, {})
	_check(not definition.is_empty(), "Buff %s has a runtime definition" % id)
	_check(unit.add_buff(id), "Buff %s initializes" % id)
	unit.notify_gameplay("injured", {"damage": 1.0, "attacker": null})
	unit.notify_gameplay("action_start", {"action": "attack", "slot": 0})
	unit.notify_gameplay("action_end", {"action": "attack", "slot": 0})
	for condition in definition.get("raw_data", {}).get("Conditions", []):
		if condition.get("ConditionType") == "ECT_CheckBuffReceiveMsg":
			unit.notify_gameplay("message", {"name": condition.get("CustomMsgName", ""), "event_type": condition.get("RogueTrigger", {}).get("RogueEventTriggerData", {}).get("EventType", "")})
	_advance(unit)
	_record(unit, "buff", id, str(definition.get("type", "")))

func _summon_case(id: String) -> void:
	var unit = _unit()
	var definition: Dictionary = unit._summon_index.get(id, {})
	_check(not definition.is_empty(), "Summon %s has a runtime definition" % id)
	unit._spawn_summon(id, 0.0, "dependency_smoke", 0)
	_advance(unit)
	_record(unit, "summon", id, str(definition.get("type", "")))

func _advance(unit: DungeonCombat) -> void:
	for frame in 60: unit.tick(1.0 / 30.0)

func _record(unit: DungeonCombat, kind: String, id: String, type: String) -> void:
	var hit_count := 0
	var summon_count := 0
	var adapters: Array = []
	for message in unit.diagnostics:
		if str(message).begins_with("Summon behavior requires world adapter:"):
			adapters.append(message)
	var unsupported = unit.diagnostics.filter(func(message): return not str(message).begins_with("Summon behavior requires world adapter:"))
	_check(unsupported.is_empty(), "%s %s has no unsupported domain operation: %s" % [kind, id, unsupported])
	for event in unit.drain_events():
		if event.type == "hit":
			hit_count += 1
			_check(is_finite(float(event.damage)) and float(event.damage) >= 0, "%s %s emits finite nonnegative damage" % [kind, id])
		elif event.type == "summon": summon_count += 1
	if kind == "summon": _check(summon_count >= 1, "Summon %s reaches its world-adapter event" % id)
	cases.append({"kind": kind, "id": id, "type": type, "hit_payloads": hit_count, "summon_events": summon_count, "world_adapters": adapters, "diagnostics": unsupported})

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)
