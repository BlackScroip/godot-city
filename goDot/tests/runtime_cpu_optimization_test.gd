extends SceneTree

const Combat = preload("res://scripts/domain/combat.gd")
const EnemyAI = preload("res://scripts/domain/enemy_ai.gd")
var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _initialize() -> void:
	_raw_cache_cases()
	_attack_mutation_cases()
	_ai_trace_cases()
	print("RUNTIME_CPU_OPTIMIZATION ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func _raw_cache_cases() -> void:
	var encoded := '{"Conditions":[{"Property":"InputMove","CompareVal":true}],"Value":3}'
	var original: Variant = Combat._read_raw_json(encoded)
	check(original == JSON.parse_string(encoded), "Cached commands retain their JSON structure")
	check(is_same(original, Combat._read_raw_json(encoded)), "Repeated command reads reuse the parsed object")
	check(Combat._read_raw_json("null") == null and Combat._raw_json_cache.has("null"), "Null JSON is cached without being confused with a miss")
	for index in Combat.RAW_JSON_CACHE_CAPACITY:
		Combat._read_raw_json('{"cache_fixture":%d}' % index)
	check(Combat._raw_json_cache.size() == Combat.RAW_JSON_CACHE_CAPACITY, "Shared parsed-command cache has a fixed capacity")
	check(Combat._raw_json_keys.size() == Combat.RAW_JSON_CACHE_CAPACITY, "Cache eviction metadata stays bounded")
	check(not Combat._raw_json_cache.has(encoded), "Old commands are evicted after a full cache turnover")
	check(Combat._read_raw_json(encoded) == original, "Evicted commands parse to the same data on reuse")
	check(original.Conditions[0].Property == "InputMove", "Eviction leaves in-use parsed commands intact")

func _attack_mutation_cases() -> void:
	var actor = Combat.new()
	actor._buff_index = {"fixture": {"type": "EBT_ModifyAttackDef", "raw_data": {"BuffSettingDataList": [{"AttackDefIdList": [7], "ModifyEntity_PhysicEntitySizeAddPercent": 1000, "ModifyEntity_PhysicEntityIntervalAddSummonUnitList": [{"SummonUnitId": "fixture"}]}]}}}
	actor.statuses.fixture = {"id": "fixture", "layers": 1}
	var encoded := '{"Id":7,"EntityType":"EET_Physical","EntityProperty":{"ModelBoxColliderSize":{"x":1,"y":2,"z":3}}}'
	var definition := {"damageId": 7, "width": 2.0, "length": 3.0, "raw": encoded}
	var cached: Dictionary = Combat._read_raw_json(encoded)
	var first: Dictionary = actor._modified_attack_definition(definition)
	var second: Dictionary = actor._modified_attack_definition(definition)
	var changed: Dictionary = JSON.parse_string(first.raw)
	check(first == second, "Repeated modified attacks do not accumulate earlier size or summon edits")
	check(first.width == 4.0 and changed.EntityProperty.ModelBoxColliderSize.x == 2.0, "Attack modifiers still change their private parsed payload")
	check(changed.EntityProperty.IntervalCreateSummonUnitDefList.size() == 1, "Modified attack retains its authored additional summon")
	check(definition.raw == encoded and definition.width == 2.0, "Original attack definitions remain unchanged")
	check(cached.EntityProperty.ModelBoxColliderSize.x == 1.0 and not cached.EntityProperty.has("IntervalCreateSummonUnitDefList"), "Attack modifications cannot mutate the shared command cache")
	actor._execute({"command": {"type": "EET_SendMessage", "raw": encoded}, "action": "fixture", "slot": 0, "sequence": 0})
	var events: Array = actor.drain_events()
	events[0].definition.EntityProperty.ModelBoxColliderSize.x = 9.0
	check(cached.EntityProperty.ModelBoxColliderSize.x == 1.0, "Mutable emitted event payloads do not alias cached commands")

func _ai_trace_cases() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/combat.json"))
	for enemy_id in [11001, 21002, 52002, 90001]:
		var definition: Dictionary = {}
		for row in catalog.enemies:
			if int(row.id) == enemy_id:
				definition = row
		var observed = EnemyAI.new()
		var quiet = EnemyAI.new()
		quiet.trace_enabled = false
		check(observed.configure(definition, catalog.ai_graphs[definition.ai], 731), "Traced AI fixture loads %d" % enemy_id)
		check(quiet.configure(definition, catalog.ai_graphs[definition.ai], 731), "Quiet AI fixture loads %d" % enemy_id)
		var saw_trace := false
		for frame in 360:
			var context := {"target_available": true, "distance": [2.0, 6.0, 3.5][(frame / 60) % 3], "line_blocked": frame % 90 > 60, "hp_ratio": 1.0 - frame / 400.0, "move_speed": 5.0, "attack_cooldown": 3.0, "self_buffs": [], "target_buffs": [], "battle_time": frame / 60.0, "monster_index": frame % 3}
			if frame % 60 == 0:
				observed.notify_action_started("idle")
				quiet.notify_action_started("idle")
			var expected: Dictionary = observed.tick(1.0 / 60.0, context)
			var actual: Dictionary = quiet.tick(1.0 / 60.0, context)
			for key in ["action", "properties", "buffs", "messages", "status"]:
				check(actual[key] == expected[key], "Trace option preserves %s for enemy %d at frame %d" % [key, enemy_id, frame])
			check(observed.snapshot() == quiet.snapshot(), "Trace option preserves AI state and random draws %d/%d" % [enemy_id, frame])
			check(actual.trace.is_empty() and actual.visited.is_empty(), "Quiet AI omits only tracing output %d/%d" % [enemy_id, frame])
			saw_trace = saw_trace or not expected.trace.is_empty()
		check(saw_trace, "Standalone AI still collects assignments by default %d" % enemy_id)
		observed.trace_enabled = false
		var disabled: Dictionary = observed.tick(0.0, {})
		check(disabled.trace.is_empty() and disabled.visited.is_empty(), "Disabling traces clears old diagnostic data %d" % enemy_id)
		quiet.trace_enabled = true
		var enabled: Dictionary = quiet.tick(0.0, {})
		check(not enabled.visited.is_empty(), "Trace collection can be enabled again %d" % enemy_id)
	var actor = Combat.new()
	check(actor.configure_enemy(11001).success and not actor.enemy_ai.trace_enabled, "Gameplay enemy AI skips diagnostic trace collection")
