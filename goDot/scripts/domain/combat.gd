class_name DungeonCombat
extends RefCounted

signal impact_confirmed(impact: Dictionary)

const FEEL = preload("res://assets/feel_settings.tres")
const EnemyHitReaction = preload("res://scripts/domain/enemy_hit_reaction.gd")
const HIT_REACTION_ATTRIBUTES := ["Weight", "PushForceResist", "PushForceAddRate", "BaseTenacity", "BaseTenacityRecover", "TenacityAccAddRate", "BaseWeakTime"]

const DATA_PATH = "res://assets/data/combat.json"
const SUPPORTED_ATTRIBUTES = ["BaseAtk", "BaseDef", "BaseHp", "MoveSpeedRate", "HpAddFixed", "HpAddRate", "AttackSpeedRate", "Monster_AttackCDRate", "AtkAddFixed", "AtkAddRate", "DefAddFixed", "DefAddRate", "CriticalRate", "CriticalMulti", "NormalAtkDamageRate", "DodgeAtkDamageRate", "SubSkillDamageRate", "MainSkillDamageRate", "SpecialAtkDamageRate", "MonsterPartnerDamageRate", "AllElementDamageRate", "AllElementResist", "HealRate", "ShieldEmpower", "None", "FireDamageRate", "WaterDamageRate", "ThunderDamageRate", "WindDamageRate", "LightDamageRate", "DarkDamageRate", "IceDamageRate", "FireResist", "WaterResist", "ThunderResist", "WindResist", "LightResist", "DarkResist", "IceResist", "SpiritTrigger", "SpiritEnhance", "SpiritRange", "SpiritDuration", "SpiritCount", "SkillActive1ExtraUseCount", "SkillActive1MaxSpAddRate", "SkillActive1CostSpAddRate", "SkillActive2ExtraUseCount", "SkillActive2MaxSpAddRate", "SkillActive2CostSpAddRate"]
static var _shared_catalog: Dictionary = {}
static var _shared_actions: Dictionary = {}
static var _shared_buffs: Dictionary = {}
static var _shared_summons: Dictionary = {}
static var _heavy_catalog: Dictionary = {}
static var _monster_behavior_catalog: Dictionary = {}
const RAW_JSON_CACHE_CAPACITY := 2048
static var _raw_json_cache: Dictionary = {}
static var _raw_json_keys: Array[String] = []
static var _raw_json_cursor := 0

class EnemyInterruptPredicate:
	extends RefCounted
	enum Kind { UNKNOWN, BOOL, STRING, ATTACK_MODE, DEAD, AI, INT, HIT_ACTION }
	var kind: Kind = Kind.UNKNOWN
	var property: String = ""
	var expected_bool := false
	var expected_string: String = ""
	var minimum := 0
	var maximum := 0

class EnemyInterrupt:
	extends RefCounted
	var start := 0.0
	var duration := 0.0
	var target: String = ""
	var conditions: Array = []
	var all_required := true
	var valid := false
	var check_all := true
	var predicates: Array[EnemyInterruptPredicate] = []

var catalog: Dictionary = {}
var fighter: Dictionary = {}
var enemy: Dictionary = {}
var enemy_hit_rules: Dictionary = {}
var enemy_hit_motion_step := -1.0
var character_id: int = 0
var enemy_id: int = 0
var actor_key: String = ""
var difficulty: int = 0
var health: float = 100.0
var attack: float = 85.0
var defense: float = 70.0
var armor: float = 0.0
var shield: float = 0.0
var max_health: float:
	get:
		return maxf(1.0, (_base_max_health + attribute("BaseHp")) * (1.0 + attribute("HpAddRate") / 1000.0) + attribute("HpAddFixed"))
	set(value):
		_base_max_health = maxf(1.0, value)
var hp: float:
	get:
		return health
	set(value):
		health = clampf(value, 0.0, max_health)
var max_hp: float:
	get:
		return max_health
	set(value):
		max_health = value
var move_speed: float:
	get:
		return float(fighter.get("speed", enemy.get("speed", 5.0))) * move_multiplier()
var busy: float = 0.0
var invincible: float = 0.0
var frozen: float = 0.0
var current_action: String = ""
var energy: Array = [0.0, 0.0, 0.0, 0.0, 0.0]
var cooldowns: Array = [0.0, 0.0, 0.0, 0.0, 0.0]
var skill_round_uses: Array = [0, 0, 0, 0, 0]
var statuses: Dictionary = {}
var diagnostics: Array = []
var events: Array = []
var custom_properties: Dictionary = {"InputMove": false, "InputAttack": false, "InputAttack_LongPress": false, "InputSkill": false}
var charging: bool = false
var charge_released: bool = false
var charge_elapsed: float = 0.0
var _base_max_health: float = 100.0
var _clock: float = 0.0
var _slow_time: float = 0.0
var _slow_scale: float = 1.0
var _combo: int = 0
var _combo_expiry: float = 0.0
var _cast_sequence: int = 0
var _collision_events_sequence := -1
var _collision_events: Array = []
var _heavy_events_sequence := -1
var _heavy_events: Array = []
var _current_slot: int = 0
var _random_state: int = 1
var _pending: Array = []
var _external: Dictionary = {}
var _progression_roots: Dictionary = {}
var _progression_owned: Array = []
var _external_numeric_buffs: Array = []
var _action_index: Dictionary = {}
var _buff_index: Dictionary = {}
var _summon_index: Dictionary = {}
var _dead_emitted: bool = false
var _emission_sequence: int = 0
var _condition_depth: int = 0
var _buff_casters: Dictionary = {}
var _dodge_time: float = 0.0
var _dodge_recharge_elapsed: float = 0.0
var _block_time: float = 0.0
var _anti_heal_time: float = 0.0
var _attribute_stack: Dictionary = {}
var action_elapsed := 0.0
var action_step := -1.0
var action_tick_delta := 0.0
var impact_pause := 0.0
var stagger_remaining := 0.0
var _impact_gate := 0.0
var _stagger_grace := 0.0
var _recovery_credit := 0.0
var _compensate_pause := false
var enemy_ai: RefCounted
var enemy_ai_enabled := false
var _enemy_speed_windows: Array = []
var _enemy_interrupts: Array = []
var _enemy_interrupt_program: Array[EnemyInterrupt] = []
var _enemy_timing_cache: Dictionary = {}
var _navigation_cached := false
var _navigation_name := ""
var _navigation_definition: Dictionary = {}
var _navigation_windows := PackedFloat64Array()
var _navigation_fallback := false

func apply_hit_stop(duration: float, compensate := false) -> bool:
	if not FEEL.impact_enabled or health <= 0: return false
	if _impact_gate > 0:
		if impact_pause > 0:
			var elapsed = maxf(0.0, FEEL.hit_stop_interval - _impact_gate)
			impact_pause = maxf(impact_pause, clampf(duration, 0, FEEL.hit_stop_limit) - elapsed)
		return false
	impact_pause = maxf(impact_pause, clampf(duration, 0, FEEL.hit_stop_limit))
	if impact_pause <= 0: return false
	_impact_gate = FEEL.hit_stop_interval
	_compensate_pause = compensate
	return true

func apply_stagger(duration: float, interrupt := false) -> bool:
	if not FEEL.impact_enabled or duration <= 0 or health <= 0: return false
	if not enemy.is_empty(): return false
	if not fighter.is_empty():
		if stagger_remaining > 0 or _stagger_grace > 0 or _current_slot == 1: return false
		duration = minf(duration, FEEL.player_stagger_limit)
		_stagger_grace = duration + FEEL.player_stagger_grace
	stagger_remaining = maxf(stagger_remaining, duration)
	if interrupt:
		_cancel_sequence(_cast_sequence)
		busy = 0
		charging = false
		_clear_charge()
		custom_properties.InputAttack_LongPress = false
		_emit_event("action_cancelled", {"sequence": _cast_sequence})
		if enemy_ai_enabled:
			if enemy_ai != null: enemy_ai.notify_action_ended(current_action)
			current_action = ""
	return true

func clear_impact_state() -> void:
	impact_pause = 0.0
	stagger_remaining = 0.0
	_impact_gate = 0.0
	_stagger_grace = 0.0
	_recovery_credit = 0.0
	_compensate_pause = false

func action_phase() -> String:
	var definition = _action("ActGroup_playerchara" if enemy.is_empty() else str(enemy.get("group", "")), current_action)
	var speed = maxf(0.01, float(custom_properties.get("_feel_action_speed", 1)))
	var first = INF
	var last = 0.0
	for hit in definition.get("hits", []):
		if not bool(hit.get("enabled", false)): continue
		first = minf(first, float(hit.time) / speed)
		last = maxf(last, float(hit.time) / speed)
	for command in definition.get("events", []):
		if not command.get("enabled", false) or command.get("type", "") != "EET_AddSummonUnit": continue
		first = minf(first, float(command.time) / speed)
		last = maxf(last, float(command.time) / speed)
	if action_elapsed < first and first < INF: return "windup"
	return "impact" if action_elapsed < last + 0.06 and first < INF else "recovery"

func _action_event(event: Dictionary) -> bool:
	return int(event.get("sequence", -1)) == _cast_sequence and bool(event.get("action_timeline", event.get("summon_id", "").is_empty() and (event.has("command") or event.has("hit"))))

func _using_heavy_graph() -> bool:
	return enemy.is_empty() and (_current_slot == 4 or bool(custom_properties.get("_heavy_graph", _current_slot == 0 and custom_properties.get("AttackModeStr", "normal") == "satk")))

func configure(catalog_value: Variant = null, _systems: Variant = null, char_id: int = 1, difficulty_value: int = 0, seed_value: int = 1) -> Dictionary:
	_collision_events_sequence = -1
	_heavy_events_sequence = -1
	if not _load_catalog(catalog_value):
		return _result(false, "Combat database missing", char_id)
	_reset()
	for definition in catalog.get("characters", []):
		if int(definition.id) == char_id:
			fighter = definition
			break
	if fighter.is_empty():
		return _result(false, "Unknown character", char_id)
	character_id = char_id
	actor_key = "character:%s" % char_id
	difficulty = clampi(difficulty_value, 0, 10)
	_random_state = seed_value & 0xffffffff
	attack = float(fighter.attack)
	defense = float(fighter.defense)
	max_health = float(fighter.hp)
	health = max_health
	for index in range(mini(5, fighter.skills.size())):
		energy[index] = 0.0 if index == 3 else skill_capacity(index)
	for id in fighter.get("passives", []):
		add_buff(str(id), 1)
	return _result(true, "Character ready", char_id)

func configure_enemy(id: int, seed_value: int = 1, difficulty_value: int = 0, catalog_value: Variant = null, stage_value: int = 1, chaos_value: int = 0) -> Dictionary:
	_collision_events_sequence = -1
	_heavy_events_sequence = -1
	if not _load_catalog(catalog_value):
		return _result(false, "Combat database missing", id)
	_reset()
	for definition in catalog.get("enemies", []):
		if int(definition.id) == id:
			enemy = definition
			break
	if enemy.is_empty():
		return _result(false, "Unknown enemy", id)
	enemy_id = id
	enemy_hit_rules = EnemyHitReaction.rules_for(id)
	actor_key = "enemy:%s" % id
	difficulty = clampi(difficulty_value, 0, 10)
	_random_state = seed_value & 0xffffffff
	attack = float(enemy.attack)
	defense = float(enemy.get("defense", 0.0))
	custom_properties["enemy_stage"] = clampi(stage_value, 1, 5)
	custom_properties["enemy_chaos"] = maxi(0, chaos_value)
	max_health = preload("res://scripts/domain/enemy_stats.gd").hp(float(enemy.hp), str(enemy.get("rank", "Normal")), difficulty, stage_value, chaos_value)
	health = max_health
	enemy_ai = preload("res://scripts/domain/enemy_ai.gd").new()
	enemy_ai.trace_enabled = false
	if not enemy_ai.configure(enemy, catalog.get("ai_graphs", {}).get(str(enemy.get("ai", "")), {}), seed_value):
		_report("Enemy behavior graph unavailable: %s" % enemy_id)
		enemy_ai = null
	return _result(true, "Enemy ready", id)

func apply_enemy_enhancements(enhancements: Array) -> bool:
	if enemy.is_empty() or bool(custom_properties.get("_enemy_enhancements_initialized", false)): return false
	custom_properties["_enemy_enhancements_initialized"] = true
	custom_properties["_enemy_enhancements"] = enhancements.duplicate(true)
	if enhancements.is_empty(): return false
	for enhancement in enhancements:
		add_buff(str(enhancement.get("buff_id", "")), 1)
	add_buff("26012001", 1)
	custom_properties["sIs_MoHua_Enhance_Monster"] = true
	health = max_health
	return true

func is_mohua() -> bool:
	return not enemy.is_empty() and bool(custom_properties.get("sIs_MoHua_Enhance_Monster", false))

func enemy_health_title() -> String:
	var names: PackedStringArray = []
	for enhancement in custom_properties.get("_enemy_enhancements", []):
		var title := str(enhancement.get("name", ""))
		if not title.is_empty(): names.append(DungeonLocale.text(title))
	if names.is_empty(): return ""
	return " ".join(names) + " " + DungeonLocale.text(str(enemy.get("name", "")))

func enemy_health_locked() -> bool:
	# The source indicator starts after a lock activates, and ends on disposal.
	for entry in statuses.values():
		if int(entry.get("lock_count", 0)) > 0 and int(entry.get("layers", 0)) > 0 and _buff_index.get(str(entry.id), {}).get("type") == "EBT_SpecialBuffLockHp":
			return true
	return false

func enemy_attack_cooldown() -> float:
	if enemy.is_empty(): return 0.0
	# AIStatus_BT refreshes BB_AttackCD from this runtime attribute every update.
	return float(enemy.get("cooldown", 0)) * (1.0 + attribute("Monster_AttackCDRate") / 1000.0)

func tick_enemy_ai(delta: float, context: Dictionary) -> Dictionary:
	if enemy_ai == null or health <= 0: return {}
	enemy_ai_enabled = true
	begin_enemy_spawn()
	var input = context.duplicate()
	input["hp_ratio"] = health / max_health
	input["move_speed"] = move_speed
	input["attack_cooldown"] = enemy_attack_cooldown()
	input["self_buffs"] = statuses.keys()
	input["current_action"] = current_action
	var result: Dictionary = enemy_ai.tick(delta, input)
	custom_properties["OP_AIAction"] = result.action
	for property in result.properties: custom_properties[property] = result.properties[property]
	for id in result.buffs: add_buff(str(id), 1)
	for message in result.messages: _emit_event("ai_message", {"message": message})
	# Phase reporting observes the tree; the legacy phase queue must not also run.
	var phase = int(enemy_ai.blackboard.get("BB_HpChecker", enemy_phase()))
	if phase > enemy_phase():
		custom_properties["_enemy_phase"] = phase
		_emit_event("phase_changed", {"phase": phase, "source": enemy.get("ai_source", ""), "rule_basis": "serialized_behavior_tree"})
	if current_action.is_empty():
		var idle = _action(str(enemy.group), "idle")
		if not idle.is_empty(): _start(idle, 0)
	_tick_enemy_interrupts()
	return result

func begin_enemy_spawn() -> bool:
	if enemy.is_empty() or health <= 0 or custom_properties.get("_enemy_spawn_entered", false): return false
	if not current_action.is_empty():
		custom_properties["_enemy_spawn_entered"] = true
		return false
	if _monster_behavior_catalog.is_empty():
		_monster_behavior_catalog = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/monster_behavior.json"))
	var behavior: Dictionary = _monster_behavior_catalog.get("enemies", {}).get(str(enemy_id), {})
	var action_name = str(behavior.get("first_action", "born"))
	var first_action = _action(str(enemy.group), action_name)
	# BattleManager requests BossAct; its AddBuff commands initialize boss phases.
	if enemy.get("rank") == "Boss" and not str(behavior.get("boss_action", "")).is_empty():
		action_name = str(behavior.boss_action)
		if action_name != str(first_action.get("id", "")):
			# FirstAct can install gameplay listeners before the entrance pose replaces it.
			for command in first_action.get("events", []):
				if bool(command.get("enabled", false)) and command.get("type", "") == "EET_AddBuff" and float(command.get("time", 0)) <= 0.000001 and _conditions(command.get("conditions", []), bool(command.get("all", true))):
					add_buff(str(command.get("buff", "")), int(command.get("layers", 1)))
	var initial = _action(str(enemy.group), action_name)
	if initial.is_empty(): initial = _action(str(enemy.group), "idle")
	custom_properties["_enemy_spawn_entered"] = true
	if initial.is_empty(): return false
	_start(initial, 0)
	return true

func enemy_navigation_requested() -> bool:
	if enemy.is_empty() or health <= 0: return false
	var elapsed = action_elapsed * maxf(0.01, float(custom_properties.get("_feel_action_speed", 1)))
	var definition = _action(str(enemy.group), current_action)
	# Cache immutable windows; action time, speed and definition identity stay live.
	if not _navigation_cached or _navigation_name != current_action or not is_same(_navigation_definition, definition):
		_navigation_cached = true
		_navigation_name = current_action
		_navigation_definition = definition
		_navigation_fallback = current_action.to_lower() in ["run", "forward", "dash", "running", "meaninglessrun"]
		_navigation_windows = PackedFloat64Array()
		for command in definition.get("events", []):
			if not command.get("enabled", false) or command.get("type", "") != "EET_Navigation": continue
			var start = float(command.get("time", 0))
			_navigation_windows.append(start)
			_navigation_windows.append(start + float(command.get("duration", 0)))
	if _navigation_fallback: return true
	var index := 0
	while index < _navigation_windows.size():
		if elapsed >= _navigation_windows[index] and elapsed < _navigation_windows[index + 1]: return true
		index += 2
	return false

func begin_enemy_death() -> bool:
	if enemy.is_empty() or health > 0 or custom_properties.get("_enemy_death_started", false): return false
	var definition = _action(str(enemy.group), "dead")
	if definition.is_empty():
		_report("Enemy death action missing: %s" % enemy_id)
		return false
	clear_impact_state()
	_pending.clear()
	custom_properties["_enemy_death_started"] = true
	custom_properties["_enemy_deleted"] = false
	custom_properties["_enemy_visual_hidden"] = false
	_start(definition, 0)
	tick_enemy_death(0.0)
	return true

func tick_enemy_death(delta: float) -> void:
	if not custom_properties.get("_enemy_death_started", false) or custom_properties.get("_enemy_deleted", false): return
	if not is_finite(delta) or delta < 0: return
	action_step = _enemy_action_advance(delta)
	action_tick_delta = delta
	action_elapsed += action_step
	_clock += delta
	var timeline_delay = delta - action_step
	for scheduled in _pending:
		if _action_event(scheduled): scheduled.at += timeline_delay
	busy = maxf(0.0, busy - action_step)
	_pending.sort_custom(_event_before)
	var guard = 0
	# Death keeps its authored effects and movement after HP/AI stop updating.
	while not _pending.is_empty() and float(_pending[0].at) <= _clock + 0.0000001 and guard < 4096:
		guard += 1
		var event: Dictionary = _pending.pop_front()
		if int(event.get("sequence", -1)) != _cast_sequence: continue
		if event.has("hit"):
			_emit_hit(event)
		elif event.has("command"):
			_execute(event)
		if custom_properties.get("_enemy_deleted", false):
			_pending.clear()
			break
		_pending.sort_custom(_event_before)
	if guard >= 4096: _report("Death timeline event budget exceeded")

func _cache_enemy_timing(definition: Dictionary) -> void:
	_enemy_speed_windows = []
	_enemy_interrupts = []
	_enemy_interrupt_program = []
	if enemy.is_empty(): return
	var key := str(definition.get("key", definition.get("id", "")))
	# Catalog definitions are immutable; runtime property values are read each tick.
	var cached: Dictionary = _enemy_timing_cache.get(key, {})
	if not cached.is_empty() and is_same(cached.definition, definition):
		_enemy_speed_windows = cached.speed_windows
		_enemy_interrupts = cached.interrupts
		_enemy_interrupt_program = cached.program
		return
	for command in definition.get("events", []):
		if not command.get("enabled", false): continue
		if command.get("type", "") == "EET_Interrupt":
			_enemy_interrupts.append(command)
			_enemy_interrupt_program.append(_compile_enemy_interrupt(command))
		elif command.get("type", "") == "EET_ActionSpeedScale" and float(command.get("duration", 0)) > 0:
			var raw = _read_raw_json(str(command.get("raw", "{}")))
			if raw is Dictionary:
				_enemy_speed_windows.append({"start": float(command.time), "end": float(command.time) + float(command.duration), "rate": maxf(0.01, float(raw.get("ScaleSpeed", 1)))})
	_enemy_timing_cache[key] = {"definition": definition, "speed_windows": _enemy_speed_windows, "interrupts": _enemy_interrupts, "program": _enemy_interrupt_program}

func _compile_enemy_interrupt(command: Dictionary) -> EnemyInterrupt:
	var compiled := EnemyInterrupt.new()
	compiled.start = float(command.get("time", 0))
	compiled.duration = float(command.get("duration", 0))
	compiled.target = str(command.get("target", ""))
	compiled.conditions = command.get("conditions", [])
	compiled.all_required = bool(command.get("all", true))
	var raw = _read_raw_json(str(command.get("raw", "{}")))
	if not raw is Dictionary: return compiled
	compiled.valid = true
	compiled.check_all = bool(raw.get("CheckAllCondition", true))
	for condition in raw.get("Conditions", []):
		var predicate := EnemyInterruptPredicate.new()
		match str(condition.get("InterruptType", "")):
			"EIT_CheckCustomPropertyBool":
				predicate.kind = EnemyInterruptPredicate.Kind.BOOL
				predicate.property = str(condition.get("Property", ""))
				predicate.expected_bool = bool(condition.get("CompareVal", false))
			"EIT_CheckCustomPropertyString":
				predicate.kind = EnemyInterruptPredicate.Kind.STRING
				predicate.property = str(condition.get("Property", ""))
				predicate.expected_string = str(condition.get("CompareVal", ""))
			"EIT_CheckAttackMode":
				predicate.kind = EnemyInterruptPredicate.Kind.ATTACK_MODE
				predicate.expected_string = "satk" if condition.get("ModeType") == "Special" else "normal"
			"EIT_CheckDead":
				predicate.kind = EnemyInterruptPredicate.Kind.DEAD
			"EIT_CheckAI":
				predicate.kind = EnemyInterruptPredicate.Kind.AI
				predicate.expected_string = str(condition.get("CompareVal", ""))
			"EIT_CheckCustomPropertyInt":
				predicate.kind = EnemyInterruptPredicate.Kind.INT
				predicate.property = str(condition.get("CustomProperty", condition.get("Property", "")))
				predicate.minimum = int(condition.get("MinVal", 0))
				predicate.maximum = int(condition.get("MaxVal", 0))
			"EIT_CheckHitAction":
				predicate.kind = EnemyInterruptPredicate.Kind.HIT_ACTION
				predicate.minimum = EnemyHitReaction.condition_flags(condition)
		compiled.predicates.append(predicate)
	return compiled

func _compiled_enemy_interrupt_conditions(compiled: EnemyInterrupt) -> bool:
	if not compiled.valid: return false
	if compiled.predicates.is_empty(): return true
	var any := false
	for predicate in compiled.predicates:
		var passed := false
		match predicate.kind:
			EnemyInterruptPredicate.Kind.BOOL:
				passed = bool(custom_properties.get(predicate.property, false)) == predicate.expected_bool
			EnemyInterruptPredicate.Kind.STRING:
				var value = custom_properties.get(predicate.property, "satk" if _current_slot == 4 else "normal") if predicate.property == "AttackModeStr" else property_value(predicate.property)
				passed = str(value) == predicate.expected_string
			EnemyInterruptPredicate.Kind.ATTACK_MODE:
				passed = str(custom_properties.get("AttackModeStr", "satk" if _current_slot == 4 else "normal")) == predicate.expected_string
			EnemyInterruptPredicate.Kind.DEAD:
				passed = health <= 0
			EnemyInterruptPredicate.Kind.AI:
				passed = str(custom_properties.get("OP_AIAction", "")) == predicate.expected_string
			EnemyInterruptPredicate.Kind.INT:
				var value := int(custom_properties.get(predicate.property, 0))
				passed = value >= predicate.minimum and value <= predicate.maximum
			EnemyInterruptPredicate.Kind.HIT_ACTION:
				passed = EnemyHitReaction.matches(self, predicate.minimum)
		if compiled.check_all and not passed: return false
		any = any or passed
	return compiled.check_all or any

func _enemy_action_advance(delta: float) -> float:
	if _enemy_speed_windows.is_empty(): return delta
	var speed = maxf(0.01, float(custom_properties.get("_feel_action_speed", 1)))
	var cursor = action_elapsed * speed
	var remaining = delta * speed
	var begin = cursor
	# Integrate exactly through authored rate boundaries, independent of physics Hz.
	for iteration in range(_enemy_speed_windows.size() * 2 + 2):
		if remaining <= 0.0000001: break
		var rate = 1.0
		var boundary = INF
		for window in _enemy_speed_windows:
			if cursor >= float(window.start) - 0.0000001 and cursor < float(window.end) - 0.0000001: rate = float(window.rate)
			for point in [float(window.start), float(window.end)]:
				if point > cursor + 0.0000001: boundary = minf(boundary, point)
		var used = minf(remaining, (boundary - cursor) / rate)
		cursor += used * rate
		remaining -= used
	return (cursor - begin) / speed

func _tick_enemy_interrupts() -> void:
	if not enemy_ai_enabled or frozen > 0 or impact_pause > 0 or stagger_remaining > 0: return
	if _enemy_due_payloads_pending(): return
	var visited: Dictionary = {current_action: true}
	for transition in range(12):
		var changed = false
		var elapsed = action_elapsed * maxf(0.01, float(custom_properties.get("_feel_action_speed", 1)))
		for command in _enemy_interrupt_program:
			if elapsed + 0.000001 < command.start or (command.duration > 0 and elapsed > command.start + command.duration): continue
			if not _conditions(command.conditions, command.all_required): continue
			if not _compiled_enemy_interrupt_conditions(command): continue
			var next = _action(str(enemy.group), command.target)
			if next.is_empty(): continue
			_start(next, 0)
			if _enemy_due_payloads_pending(): return
			# Source helper fallbacks can return to an already checked action at t=0.
			# Keep the authored transition, then yield until the next AI update.
			if visited.has(current_action): return
			visited[current_action] = true
			changed = true
			break
		if not changed: return
	_report("Enemy action transition budget exceeded: %s" % enemy_id)

func _enemy_due_payloads_pending() -> bool:
	# Source event payloads execute before an interrupt at the same action time.
	return _pending.any(func(event): return _action_event(event) and float(event.get("at", INF)) <= _clock + 0.000001)

func input_block_reason(slot: int) -> String:
	if fighter.is_empty() or slot < 0 or slot >= fighter.get("skills", []).size(): return "Unknown skill"
	if health <= 0: return "Defeated"
	if frozen > 0: return "Frozen"
	if minf(float(energy[slot]), skill_capacity(slot)) + 0.001 < skill_cost(slot): return "Insufficient energy"
	if slot == 4 and character_id == 3 and special_resource() < 1: return "Requires rage"
	if slot == 4 and character_id == 4 and special_resource() < 25: return "Requires 25 water energy"
	return ""

func skill_capacity(slot: int) -> float:
	if fighter.is_empty() or slot < 0 or slot >= fighter.skills.size(): return 0.0
	var skill: Dictionary = fighter.skills[slot]
	if slot == 1:
		var maximum := maxf(0.0, float(skill.maxSp) + float(skill.sp) * (FEEL.dodge_base_extra_uses + attribute("SkillDodgeExtraUseCount")))
		var limit := int(attribute("SkillDodgeLimitMaxUseCount"))
		return minf(maximum, float(skill.sp) * limit) if limit > 0 else maximum
	if slot not in [2, 3]: return float(skill.maxSp)
	var prefix = "SkillActive1" if slot == 2 else "SkillActive2"
	var maximum = float(skill.maxSp) * (1.0 + attribute(prefix + "MaxSpAddRate") / 1000.0)
	maximum += skill_cost(slot) * int(attribute(prefix + "ExtraUseCount"))
	return clampf(maximum, 0.0, 2147483647.0 * skill_cost(slot))

func skill_cost(slot: int) -> float:
	if fighter.is_empty() or slot < 0 or slot >= fighter.skills.size(): return 0.0
	var rate = 0.0
	if slot in [2, 3]: rate = attribute(("SkillActive1" if slot == 2 else "SkillActive2") + "CostSpAddRate")
	return maxf(0.0, float(fighter.skills[slot].sp) * (1.0 + rate / 1000.0))

func skill_charge_fraction(slot: int, use_cost := false) -> float:
	var maximum = skill_cost(slot) if use_cost else skill_capacity(slot)
	if maximum <= 0: return 1.0 if use_cost else 0.0
	return clampf(float(energy[slot]) / maximum, 0.0, 1.0)

func skill_resource_snapshot() -> Dictionary:
	return {"character_id": character_id, "energy": energy.duplicate(), "cooldowns": cooldowns.duplicate(), "round_uses": skill_round_uses.duplicate()}

func restore_skill_resources(saved: Dictionary) -> bool:
	if int(saved.get("character_id", 0)) != character_id: return false
	for field in ["energy", "cooldowns", "round_uses"]:
		if not saved.get(field) is Array or saved[field].size() != 5: return false
		for value in saved[field]:
			if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0: return false
	for slot in range(5):
		energy[slot] = minf(skill_capacity(slot), float(saved.energy[slot]))
		cooldowns[slot] = float(saved.cooldowns[slot])
		skill_round_uses[slot] = int(saved.round_uses[slot])
	return true

func add_skill_charge(slot: int, amount: float) -> float:
	if fighter.is_empty() or slot < 0 or slot >= energy.size() or amount <= 0: return 0.0
	if slot == 3:
		var speed = maxf(0.0, attribute("SkillActive2ChargeSpeed"))
		amount *= 1.0 + 4.0 * speed / (3.0 * speed + 5000.0)
	var previous = minf(float(energy[slot]), skill_capacity(slot))
	energy[slot] = minf(skill_capacity(slot), previous + amount)
	return float(energy[slot]) - previous

func skill_available_uses(slot: int) -> int:
	# GetCurRealCanUseCount includes stored casts remaining in the current cooldown round.
	var cost = skill_cost(slot)
	if cost <= 0: return 0
	var charge = minf(float(energy[slot]), skill_capacity(slot))
	if charge < cost: return 0
	var count = int((charge + 0.0001) / cost)
	if float(fighter.skills[slot].cooldown) <= 0 or float(cooldowns[slot]) <= 0: return count
	var maximum = int((skill_capacity(slot) + 0.0001) / cost)
	return 0 if maximum < 2 else mini(count, maximum - int(skill_round_uses[slot]))

func _skill_cooldown_ready(slot: int) -> bool:
	if float(fighter.skills[slot].cooldown) <= 0 or float(cooldowns[slot]) <= 0: return true
	var cost = skill_cost(slot)
	if cost <= 0: return false
	var maximum = int((skill_capacity(slot) + 0.0001) / cost)
	return maximum >= 2 and int(skill_round_uses[slot]) < maximum

func dodge_recharge_duration() -> float:
	return maxf(0.0, 1.0 + attribute("SkillDodgeChargeTimeAdd") / 1000.0)

func dodge_recharge_remaining() -> float:
	if fighter.is_empty() or float(energy[1]) >= skill_capacity(1): return 0.0
	return maxf(0.0, dodge_recharge_duration() - _dodge_recharge_elapsed)

func cancel_held_input() -> void:
	custom_properties.InputSkill = false
	custom_properties["InputSkill1_LongPress"] = false
	cancel_held_attack()

func cancel_held_attack() -> void:
	custom_properties.InputAttack_LongPress = false
	custom_properties.InputAttack = false
	if charging or (_using_heavy_graph() and busy > 0):
		_cancel_sequence(_cast_sequence)
		busy = 0.0
		charging = false
		charge_released = false
		_clear_charge()
		_emit_event("action_cancelled", {"sequence": _cast_sequence})

func input_action_delay(slot: int) -> float:
	if slot == 1: return 0.0
	if stagger_remaining > 0: return maxf(stagger_remaining, busy)
	if _current_slot in [2, 3] and int(custom_properties.get("_movement_sequence", -1)) == _cast_sequence:
		var definition = _action("ActGroup_playerchara", current_action)
		var speed = maxf(0.01, float(custom_properties.get("_feel_action_speed", 1)))
		var elapsed = action_elapsed * speed
		var delay = maxf(0.0, float(definition.get("duration", 0)) - elapsed) / speed
		for command in definition.get("events", []):
			var target = str(command.get("target", ""))
			var eligible = target == "sys_checkskill" if slot in [2, 3] else target == "sys_checkatk_1" or fighter.get("combo", []).has(target)
			if not command.get("enabled", false) or not eligible: continue
			if not _conditions(command.get("conditions", []), bool(command.get("all", true))): continue
			var start = float(command.get("time", 0))
			var duration = float(command.get("duration", 0))
			if duration > 0 and elapsed > start + duration: continue
			delay = minf(delay, maxf(0.0, start - elapsed) / speed)
		return delay
	if _using_heavy_graph() and busy > 0:
		var definition = _action("ActGroup_playerchara", current_action)
		var speed = maxf(0.01, float(custom_properties.get("_feel_action_speed", 1)))
		for command in definition.get("events", []):
			if not command.get("enabled", false) or command.get("type", "") != "EET_Interrupt": continue
			var target = str(command.get("target", ""))
			var skill_window = slot in [2, 3] and target == "sys_checkskill"
			var attack_window = slot in [0, 4] and (target == "sys_checkatk_1" or fighter.get("combo", []).has(target))
			if not skill_window and not attack_window: continue
			if not _conditions(command.get("conditions", []), bool(command.get("all", true))): continue
			var raw = _read_raw_json(str(command.get("raw", "{}")))
			if not raw is Dictionary: continue
			var eligible = false
			for condition in raw.get("Conditions", []):
				if condition.get("InterruptType", "") == "EIT_CheckCustomPropertyBool" and condition.get("Property", "") == ("InputSkill" if skill_window else "InputAttack") and condition.get("CompareVal", false): eligible = true
				if condition.get("InterruptType", "") == "EIT_CheckAttackMode" and (condition.get("ModeType", "") == "Special") != (slot == 4): eligible = false; break
			if not eligible: continue
			var start = float(command.get("time", 0)) / speed
			var duration = float(command.get("duration", 0)) / speed
			if duration > 0 and action_elapsed > start + duration: continue
			return minf(busy, maxf(0.0, start - action_elapsed))
	# Normal attacks explicitly expose InputSkill interrupts in the source timeline.
	if enemy.is_empty() and _current_slot == 0 and slot in [2, 3]:
		var definition = _action("ActGroup_playerchara", current_action)
		var elapsed = action_elapsed
		var speed = maxf(0.01, float(custom_properties.get("_feel_action_speed", 1)))
		for command in definition.get("events", []):
			if not command.get("enabled", false) or command.get("target", "") != "sys_checkskill": continue
			var raw = _read_raw_json(str(command.get("raw", "{}")))
			var conditions: Array = raw.get("Conditions", []) if raw is Dictionary else []
			if conditions.size() != 1: continue
			var condition: Dictionary = conditions[0]
			if condition.get("InterruptType", "") == "EIT_CheckCustomPropertyBool" and condition.get("Property", "") == "InputSkill" and condition.get("CompareVal", false):
				return minf(busy, maxf(0, float(command.get("time", 0)) / speed - elapsed))
	return busy

func cancel_normal_attack() -> void:
	if not enemy.is_empty() or _current_slot != 0: return
	_cancel_sequence(_cast_sequence)
	busy = 0.0
	_emit_event("action_cancelled", {"sequence": _cast_sequence})

func request_attack(slot: int, pressed: bool = true) -> Dictionary:
	record_input(slot, pressed)
	if slot == 4:
		if not pressed:
			custom_properties.InputAttack_LongPress = false
			custom_properties.InputAttack = false
			charge_released = charging
			return _result(true, "Heavy attack released")
	if not pressed:
		if slot == 0 and custom_properties.get("AttackModeStr", "normal") == "normal": custom_properties.InputAttack = false
		return _result(true, "Input released")
	if not enemy.is_empty():
		return request_enemy_attack()
	if fighter.is_empty() or slot < 0 or slot >= fighter.get("skills", []).size():
		return _result(false, "Unknown skill", slot)
	if health <= 0:
		return _result(false, "Defeated", slot)
	if frozen > 0:
		return _result(false, "Frozen", slot)
	if slot == 4 and _current_slot == 4 and busy > 0:
		custom_properties.InputAttack_LongPress = true
		custom_properties.InputAttack = true
		custom_properties.AttackModeStr = "satk"
		charge_released = false
		return _result(true, "Heavy input held")
	if input_action_delay(slot) > 0:
		return _result(false, "Action in progress", slot)
	var skill: Dictionary = fighter.skills[slot]
	if not _skill_cooldown_ready(slot):
		return _result(false, "Cooling down", slot)
	if minf(float(energy[slot]), skill_capacity(slot)) + 0.001 < skill_cost(slot):
		return _result(false, "Insufficient energy", slot)
	if slot == 4 and character_id == 4 and special_resource() < 25:
		return _result(false, "Requires 25 water energy", slot)
	if slot == 4 and character_id == 3 and special_resource() < 1:
		return _result(false, "Requires rage", slot)
	if slot == 4 and character_id == 8 and buff_layers("800232") < 1:
		return _result(false, "Requires sufficient soul resource", slot)
	var action_name = str(skill.action)
	if slot == 0:
		if _clock > _combo_expiry:
			_combo = 0
		action_name = str(fighter.combo[_combo % fighter.combo.size()])
		var authored_next = str(custom_properties.get("_feel_next_combo", ""))
		if _clock <= _combo_expiry and not _action("ActGroup_playerchara", authored_next).is_empty(): action_name = authored_next
		_combo = (_combo + 1) % fighter.combo.size()
	if slot == 4:
		action_name = str(_heavy_catalog.get("entries", {}).get(str(character_id), action_name))
	for entry in statuses.values():
		var definition: Dictionary = _buff_index.get(entry.id, {})
		if definition.get("type") == "EBT_SpecialChangeAction":
			var raw = definition.get("raw_data", {})
			if (raw.get("Type") == "NorAtk" and slot == 0) or (raw.get("Type") == "SpecialAtk" and slot == 4):
				action_name = str(raw.get("ModifyId", action_name))
	var action_def = _action("ActGroup_playerchara", action_name)
	if action_def.is_empty():
		_report("Missing original action " + action_name)
		return _result(false, "Missing original action " + action_name, slot)
	if slot == 1:
		clear_impact_state()
		_dodge_recharge_elapsed = 0.0
		_cancel_sequence(_cast_sequence)
		custom_properties.InputAttack_LongPress = false
		custom_properties.InputAttack = false
		charging = false
		_clear_charge()
		invincible = maxf(invincible, 0.38)
	energy[slot] = minf(float(energy[slot]), skill_capacity(slot)) - skill_cost(slot)
	if slot == 4:
		custom_properties.InputAttack_LongPress = true
		custom_properties.InputAttack = true
		custom_properties.AttackModeStr = "satk"
	elif slot == 0:
		custom_properties.AttackModeStr = "normal"
	if float(skill.cooldown) <= 0 or float(cooldowns[slot]) <= 0: skill_round_uses[slot] = 0
	skill_round_uses[slot] = int(skill_round_uses[slot]) + 1
	cooldowns[slot] = float(skill.cooldown)
	_start(action_def, slot)
	_combo_expiry = _clock + busy + 1.3
	return _result(true, "Action started", int(skill.id))

func request_enemy_attack() -> Dictionary:
	if enemy.is_empty() or busy > 0 or health <= 0 or frozen > 0 or stagger_remaining > 0 or impact_pause > 0:
		return _result(false, "Enemy cannot act", enemy_id)
	_queue_enemy_phases()
	var queued: Array = custom_properties.get("_enemy_phase_actions", [])
	var phase_action = str(queued.pop_front()) if not queued.is_empty() else ""
	custom_properties["_enemy_phase_actions"] = queued
	var actions: Array = _enemy_action_pool()
	if enemy.get("behavior") == "flee":
		phase_action = "runaway"
	if actions.is_empty():
		if phase_action.is_empty():
			_report("No recovered attacks: %s" % enemy_id)
			return _result(false, "No recovered attacks", enemy_id)
	var action_name = phase_action
	if action_name.is_empty():
		action_name = str(actions[_combo % actions.size()])
		_combo += 1
	var action_def = _action(str(enemy.group), action_name)
	if action_def.is_empty():
		_report("Missing enemy action: " + action_name)
		return _result(false, "Missing enemy action", enemy_id)
	# Attack selection is a declared offline reconstruction, not the recovered behavior tree.
	_cancel_sequence(_cast_sequence)
	_start(action_def, 0)
	busy = maxf(busy, float(custom_properties.get("BB_AttackCD", enemy_attack_cooldown())))
	return _result(true, "Enemy attack started", enemy_id)

func enemy_phase() -> int:
	return int(custom_properties.get("_enemy_phase", 0))

func _queue_enemy_phases() -> void:
	var triggered: Array = custom_properties.get("_enemy_phase_triggered", [])
	var queued: Array = custom_properties.get("_enemy_phase_actions", [])
	for rule in enemy.get("phase_rules", []):
		var phase_id = int(rule.phase)
		if triggered.has(phase_id) or triggered.has(float(phase_id)):
			continue
		var ratio = health / max_health * 1000.0
		var threshold = float(rule.hp_per_mille)
		if not (ratio < threshold if rule.get("compare") == "less" else ratio <= threshold):
			continue
		triggered.append(phase_id)
		custom_properties["_enemy_phase"] = maxi(enemy_phase(), phase_id)
		for property in rule.get("properties", {}):
			custom_properties[property] = rule.properties[property]
		if rule.has("attack_cooldown"):
			custom_properties["BB_AttackCD"] = float(rule.attack_cooldown)
		for action in rule.get("actions", []):
			if not _action(str(enemy.group), str(action)).is_empty():
				queued.append(str(action))
			else:
				_report("Phase action missing: %s %s" % [enemy_id, action])
		_emit_event("phase_changed", {"phase": phase_id, "threshold": threshold, "source": enemy.get("ai_source", ""), "rule_basis": "serialized_configuration_with_reconstructed_scheduler"})
	custom_properties["_enemy_phase_triggered"] = triggered
	custom_properties["_enemy_phase_actions"] = queued

func _enemy_action_pool() -> Array:
	var candidates: Array = enemy.get("ai_action_ids", enemy.get("actions", [])).duplicate()
	var actions: Array = []
	for candidate in candidates:
		var action = str(candidate)
		if not action.to_lower().contains("attack") and not action.to_lower().contains("combo"):
			continue
		if action.to_lower().contains("wait") or _action(str(enemy.group), action).is_empty():
			continue
		if enemy_id == 23001:
			if bool(custom_properties.get("BB_IsFlyState", false)) != ["attack4", "attack5", "attack7"].has(action):
				continue
			if action == "attack3" or action == "attack6":
				continue
		if enemy_id == 43001 and action.begins_with("EX_") and buff_layers("45400004") <= 0:
			continue
		if enemy_id == 52001 and action == "attack6" and enemy_phase() == 0:
			continue
		if not actions.has(action):
			actions.append(action)
	return actions

func tick(delta: float) -> void:
	if not is_finite(delta) or delta < 0:
		_report("Invalid combat delta")
		return
	if delta > 0: _tick_health_lock_triggers()
	if not _using_heavy_graph() or busy <= 0:
		_tick_segment(delta)
		return
	var remaining = delta
	var advanced = 0.0
	# Admit commands at their authored boundaries before advancing the next span.
	# A condition belongs to entry, so losing its buff cannot change an active rate.
	_tick_segment(0.0)
	for iteration in 4096:
		var step = _heavy_tick_slice(remaining) if _using_heavy_graph() and busy > 0 else remaining
		if step <= 0 and not _pending.any(func(event): return _action_event(event) and float(event.at) <= _clock + 0.0000001): break
		_tick_segment(step)
		advanced += action_step
		remaining = maxf(0.0, remaining - step)
		if remaining <= 0.0000001 and not _pending.any(func(event): return _action_event(event) and float(event.at) <= _clock + 0.0000001): break
		if iteration == 4095: _report("Heavy action boundary budget exceeded")
	action_step = advanced
	action_tick_delta = delta

func _player_action_rate() -> float:
	var elapsed = action_elapsed * maxf(0.01, float(custom_properties.get("_feel_action_speed", 1)))
	var rate = 1.0
	for window in custom_properties.get("_action_speed_windows", []):
		if elapsed < float(window.end) - 0.0000001: rate = float(window.rate)
	return rate

func _heavy_tick_slice(remaining: float) -> float:
	for event in _pending:
		if _action_event(event) and float(event.at) <= _clock + 0.0000001: return 0.0
	if remaining <= 0: return 0.0
	if frozen > 0: return minf(remaining, frozen)
	var pause = maxf(impact_pause, stagger_remaining)
	if pause > 0: return minf(remaining, pause)
	var rate = _player_action_rate()
	var speed = maxf(0.01, float(custom_properties.get("_feel_action_speed", 1)))
	var elapsed = action_elapsed * speed
	var step = remaining
	for event in _pending:
		if _action_event(event): step = minf(step, maxf(0, float(event.at) - _clock) / rate)
	for window in custom_properties.get("_action_speed_windows", []):
		if float(window.end) > elapsed + 0.0000001: step = minf(step, (float(window.end) - elapsed) / (speed * rate))
	for window in custom_properties.get("_battle_time_scale_windows", {}).values():
		if int(window.sequence) == _cast_sequence and float(window.end) > elapsed + 0.0000001:
			step = minf(step, (float(window.end) - elapsed) / (speed * rate))
	for command in _heavy_events:
		for boundary in [float(command.time), float(command.time) + float(command.get("duration", 0))]:
			if boundary > elapsed + 0.0000001: step = minf(step, (boundary - elapsed) / (speed * rate))
	return step

func _tick_segment(delta: float) -> void:
	action_tick_delta = delta
	if health <= 0:
		_emit_death()
		return
	var action_delta = maxf(0.0, delta - frozen)
	if not enemy.is_empty(): EnemyHitReaction.tick(self, delta)
	var held = minf(action_delta, maxf(impact_pause, stagger_remaining))
	action_step = maxf(0.0, action_delta - held)
	if not enemy.is_empty(): enemy_hit_motion_step = EnemyHitReaction.motion_delta(self, action_step, true)
	if FEEL.impact_enabled and not _using_heavy_graph() and bool(custom_properties.get("_rhythm_enabled", false)) and busy > 0:
		var phase = action_phase()
		var rate = 0.92 if phase == "windup" else 1.08 if phase == "impact" else 1.0
		var before = action_step
		action_step *= rate
		_recovery_credit += before - action_step
	if _compensate_pause and stagger_remaining <= 0 and not _using_heavy_graph(): _recovery_credit += minf(action_delta, impact_pause)
	if _using_heavy_graph() and busy > 0: action_step *= _player_action_rate()
	if not enemy.is_empty(): action_step = _enemy_action_advance(action_step)
	impact_pause = maxf(0.0, impact_pause - delta)
	stagger_remaining = maxf(0.0, stagger_remaining - delta)
	_impact_gate = maxf(0.0, _impact_gate - delta)
	_stagger_grace = maxf(0.0, _stagger_grace - delta)
	action_elapsed += action_step
	# Shift only the current action. Spawned payloads and status clocks stay live.
	var timeline_delay = action_delta - action_step
	if not is_zero_approx(timeline_delay):
		for scheduled in _pending:
			if _action_event(scheduled): scheduled.at += timeline_delay
	var was_busy = busy > 0
	frozen = maxf(0.0, frozen - delta)
	_slow_time = maxf(0.0, _slow_time - delta)
	_clock += action_delta
	if enemy_id == 23001 and enemy_phase() > 0 and not enemy_ai_enabled:
		var flight_timer = float(custom_properties.get("_flight_timer", 0)) + action_delta
		if flight_timer >= 60.0:
			flight_timer -= 60.0
			custom_properties["BB_IsFlyState"] = not bool(custom_properties.get("BB_IsFlyState", false))
			var phase_actions: Array = custom_properties.get("_enemy_phase_actions", [])
			phase_actions.append("attack3" if bool(custom_properties.BB_IsFlyState) else "attack6")
			custom_properties["_enemy_phase_actions"] = phase_actions
		custom_properties["_flight_timer"] = flight_timer
	busy = maxf(0.0, busy - action_step)
	var remaining_hit = false
	for scheduled in _pending:
		if _action_event(scheduled) and scheduled.has("hit") and float(scheduled.at) > _clock:
			remaining_hit = true
			break
	if not _using_heavy_graph() and not remaining_hit and not is_zero_approx(_recovery_credit):
		var compensation = minf(_recovery_credit, busy)
		busy -= compensation
		_recovery_credit -= compensation
	if was_busy and busy <= 0:
		notify_gameplay("action_end", {"slot": _current_slot, "action": current_action})
		if enemy_ai != null:
			enemy_ai.notify_action_ended(current_action)
			custom_properties["_enemy_ended_sequence"] = _cast_sequence
	invincible = maxf(0.0, invincible - delta)
	_dodge_time = maxf(0.0, _dodge_time - delta)
	_block_time = maxf(0.0, _block_time - delta)
	_anti_heal_time = maxf(0.0, _anti_heal_time - delta)
	if not fighter.is_empty():
		_dodge_recharge_elapsed += delta
		for slot in range(mini(5, fighter.skills.size())):
			cooldowns[slot] = maxf(0.0, float(cooldowns[slot]) - delta)
			var recovered = delta * 2.0 if slot == 2 else 0.0
			# APK grants the original max_sp per update after the last-use delay.
			if slot == 1 and delta > 0 and _dodge_recharge_elapsed + 0.000001 >= dodge_recharge_duration():
				recovered = float(fighter.skills[slot].maxSp)
			energy[slot] = minf(skill_capacity(slot), float(energy[slot]) + recovered)
	if delta > 0.000001 and statuses.is_empty() and _condition_depth <= 16:
		# Empty status substeps have no listeners or clocks; only clamp health.
		health = minf(health, max_health)
	else:
		var remaining = delta
		while remaining > 0.000001:
			var step = minf(0.01, remaining)
			_tick_statuses(step)
			remaining -= step
	if charging:
		charge_elapsed += action_step
	_pending.sort_custom(_event_before)
	var guard = 0
	while not _pending.is_empty() and float(_pending[0].at) <= _clock + 0.0000001 and guard < 4096:
		guard += 1
		var event: Dictionary = _pending.pop_front()
		if health <= 0:
			continue
		if event.has("condition_effect"):
			_apply_condition_effect(event.condition_effect)
		elif event.has("funnel_trigger"):
			_trigger_funnel(event)
		elif event.has("funnel_emit"):
			_emit_funnel(event)
		elif event.has("emitter_start"):
			for pending in _pending:
				if pending.get("emitter_id", -1) == event.emitter_start: pending.action_timeline = false
		elif event.has("hit"):
			_emit_hit(event)
		else:
			_execute(event)
		_pending.sort_custom(_event_before)
	if guard >= 4096:
		_report("Timeline event budget exceeded")
	_tick_attack_collision_gate()
	_expire_battle_time_scale_windows()
	if was_busy and _using_heavy_graph():
		_tick_heavy_interrupts()
	elif enemy.is_empty():
		_tick_movement_interrupts()
	if health <= 0:
		_emit_death()

func confirm_hit(hit: Dictionary) -> void:
	if not fighter.is_empty():
		var definition: Dictionary = hit.get("definition", {})
		_recover_ultimate_from_hit(hit)
		for application in definition.get("ownerBuffs", []):
			add_buff(str(application.id), int(application.layers))
	_confirm_status_hit(hit)

func _recover_ultimate_from_hit(hit: Dictionary) -> void:
	if not bool(hit.get("resolved_accepted", false)) or bool(hit.get("skill_charge_attempted", false)): return
	# The APK latches the AttackHit instance before damage, chance and full-SP checks.
	hit["skill_charge_attempted"] = true
	var definition: Dictionary = hit.get("definition", {})
	var raw: Variant = definition.get("raw", {})
	if raw is String: raw = _read_raw_json(raw)
	if not raw is Dictionary: raw = {}
	var amount = float(raw.get("RecoverSkillCharge", definition.get("charge", 0)))
	if float(hit.get("resolved_calculated_damage", 0)) < 1.0 or amount <= 0 or health <= 0 or skill_charge_fraction(3) >= 1.0: return
	var chance = int(raw.get("RecoverSkillChargeChance", definition.get("chargeChance", 0)))
	if int(_random() * 1001.0) > chance: return
	add_skill_charge(3, amount)

func receive(hit: Dictionary, caster_attack: float = 0.0) -> float:
	hit["receiver_key"] = actor_key
	var hit_source = hit.get("source")
	hit["source_key"] = hit_source.actor_key if hit_source is DungeonCombat else str(hit.get("source_key", ""))
	hit["resolved_damage"] = 0.0
	hit["resolved_calculated_damage"] = 0.0
	hit["resolved_absorbed"] = 0.0
	hit["resolved_critical"] = false
	hit["resolved_accepted"] = false
	if bool(hit.get("definition", {}).get("carrier_only", false)):
		return 0.0
	if invincible > 0 or _dodge_time > 0 or _block_time > 0 or health <= 0 or (bool(hit.get("attack_collision", true)) and not can_receive_attack()):
		if health > 0 and (_dodge_time > 0 or _block_time > 0 or _current_slot == 1):
			_emit_event("evaded_hit", {"dodge_type": "Block" if _block_time > 0 else "BeHiterAutoDodge" if _dodge_time > 0 else "Dodge"})
			notify_gameplay("dodge", {"definition": hit.get("definition", {}), "attacker": hit.get("source"), "dodge_type": "Block" if _block_time > 0 else "BeHiterAutoDodge" if _dodge_time > 0 else "Dodge"})
		return 0.0
	var definition: Dictionary = hit.get("definition", {}).duplicate()
	var source = hit.get("source")
	var context = {"hit": hit, "damage_rate": 0.0, "fixed_add": 0.0, "final_add": 0.0, "defense_penetration": 0.0, "critical_rate": float(hit.get("critical_rate", 0)), "critical_multi": float(hit.get("critical_multi", 1.5)), "min_damage": 0.0, "max_damage": INF, "can_critical": bool(definition.get("critical", false))}
	if source is DungeonCombat:
		source._apply_combat_modifiers(context, self, source, false)
	_apply_combat_modifiers(context, self, source if source is DungeonCombat else null, true)
	var critical = bool(hit.get("critical", false))
	if bool(context.can_critical) and hit.has("critical_roll"):
		critical = float(hit.critical_roll) < float(context.critical_rate)
	var value = maxf(0.0, float(hit.get("uncritical_damage", hit.get("damage", 0))))
	if not hit.has("uncritical_damage") and bool(hit.get("critical", false)):
		value /= maxf(0.01, float(hit.get("critical_multi", 1.5)))
	value = value * (float(context.critical_multi) if critical else 1.0) * maxf(0.0, 1.0 + float(context.damage_rate)) + float(context.fixed_add)
	var effective_defense = (defense + attribute("BaseDef") + attribute("DefAddFixed")) * (1.0 + attribute("DefAddRate") / 1000.0)
	effective_defense *= maxf(0.0, 1.0 - float(context.defense_penetration))
	# The APK coefficients are recovered; this defense curve is explicitly reconstructed.
	value *= 100.0 / (100.0 + maxf(0.0, effective_defense)) * maxf(0.0, 1.0 - attribute("AllElementResist") / 1000.0)
	var element = str(context.get("element", definition.get("element", "")))
	definition["element"] = element
	definition["actType"] = context.get("act_type", definition.get("actType", ""))
	value *= maxf(0.0, 1.0 - attribute(element + "Resist") / 1000.0)
	if str(definition.get("actType", "")) == "EnvUnit": value *= maxf(0.0, 1.0 - attribute("EnvUnitDamageResist") / 1000.0)
	value = clampf(value + float(context.final_add), float(context.min_damage), float(context.max_damage))
	value = maxf(0.0, value)
	hit["resolved_calculated_damage"] = value
	var absorbed = minf(shield, value)
	var total_absorbed = absorbed
	shield -= absorbed
	value -= absorbed
	absorbed = minf(armor, value)
	total_absorbed += absorbed
	armor -= absorbed
	value -= absorbed
	var previous = health
	health = maxf(0.0, health - value)
	_apply_health_locks(previous)
	for application in definition.get("targetBuffs", []):
		if source is DungeonCombat and source != self:
			_buff_casters[str(application.id)] = weakref(source)
		add_buff(str(application.id), int(application.layers), caster_attack)
	_emit_event("received_hit", {"damage": previous - health, "absorbed": total_absorbed, "damage_id": int(definition.get("damageId", 0)), "element": element, "critical": critical})
	hit["resolved_damage"] = previous - health
	hit["resolved_absorbed"] = total_absorbed
	hit["resolved_critical"] = critical
	hit["resolved_accepted"] = true
	if not enemy.is_empty(): EnemyHitReaction.apply(self, hit)
	if previous > health or total_absorbed > 0:
		var impact = hit.duplicate(true)
		impact.erase("source")
		impact_confirmed.emit(impact)
		_emit_event("impact_confirmed", impact)
	if previous > health:
		var history: Array = custom_properties.get("_recent_damage", [])
		history = history.filter(func(item): return float(item.at) >= _clock - 1.0)
		history.append({"at": _clock, "damage": previous - health})
		custom_properties["_recent_damage"] = history
		notify_gameplay("injured", {"damage": previous - health, "definition": definition, "attacker": source})
		if source is DungeonCombat:
			source.notify_gameplay("cause_damage", {"damage": previous - health, "definition": definition, "critical": critical, "target": self})
	if health <= 0:
		if source is DungeonCombat:
			source.notify_gameplay("kill", {"target": self, "enemy_id": enemy_id, "rank": enemy.get("rank", "Normal")})
		_emit_death()
	return previous - health

func apply_area(event: Dictionary, same_camp: bool, squared_distance: float, is_host: bool = false) -> bool:
	var definition: Dictionary = event.get("definition", {})
	if health <= 0 or not is_finite(squared_distance) or squared_distance < 0 or squared_distance > pow(float(definition.get("radius", 0)), 2):
		return false
	if is_host and not bool(definition.get("includeSelf", false)):
		return false
	if not is_host and same_camp != bool(definition.get("sameCamp", false)):
		return false
	if not bool(definition.get("addAfterHit", false)):
		for application in definition.get("targetBuffs", []):
			if event.get("source") is DungeonCombat:
				bind_buff_caster(str(application.id), event.source)
			add_buff(str(application.id), int(application.layers), float(event.get("caster_attack", 0)))
	var hit_def = {"damageId": int(definition.get("damageId", 0)), "attribute": definition.get("attribute", "None"), "element": definition.get("element", "None"), "actType": definition.get("actType", "None"), "critical": bool(definition.get("critical", false)), "targetBuffs": definition.get("targetBuffs", []) if bool(definition.get("addAfterHit", false)) else []}
	var area_hit = event.duplicate()
	area_hit.merge({"definition": hit_def, "damage": float(event.get("damage", 0)) if bool(definition.get("enableDamage", true)) else 0.0, "distance": sqrt(squared_distance), "attack_collision": false}, true)
	receive(area_hit, float(event.get("caster_attack", 0)))
	var summon: Dictionary = definition.get("summon", {})
	var source = event.get("source")
	if source is DungeonCombat and not str(summon.get("AddSummonUnitId", "")).is_empty():
		var origin = summon.duplicate(true)
		origin["OriginType"] = "targetPosAndSelfDir"
		for index in range(clampi(int(origin.get("AddSummonUnitQuantity", 1)), 1, 30)):
			source._spawn_summon(str(origin.AddSummonUnitId), source._clock, source.current_action, source._current_slot, float(origin.get("InitPosOffset", {}).get("z", 0)), 0, origin, actor_key)
	return true

func _status_area(definition: Dictionary, caster: DungeonCombat) -> Dictionary:
	var raw: Dictionary = definition.get("raw_data", {})
	var settings = _settings(definition, caster)
	if settings.is_empty():
		return definition.get("area", {})
	var damage_owner: DungeonCombat = caster if bool(raw.get("DamageAttriOwnerIsCaster", true)) and caster != null else self
	var damage = damage_owner._damage_data(int(settings.get("DamageDefId", 0)))
	var applications: Array = []
	var application: Dictionary = settings.get("BuffTrigger_AddToAttackee", {})
	if not str(application.get("BuffTriggerId", "")).is_empty():
		applications.append({"id": str(application.BuffTriggerId), "layers": int(application.get("BuffAddLayer", 1))})
	var maximum = int(settings.get("MaxEffectObject", -1))
	var layer_source = str(settings.get("MaxEffectObjectFollowBuffLayer", ""))
	if not layer_source.is_empty(): maximum = buff_layers(layer_source)
	return {"radius": float(settings.get("EffectRadius", 0)), "sameCamp": bool(raw.get("TargetIsSelfCamp", false)), "includeSelf": bool(raw.get("EffectToSelf", false)), "enableDamage": bool(raw.get("EnableDamage", true)), "addAfterHit": bool(raw.get("IsAddBuffAfterHit", false)), "damageId": int(settings.get("DamageDefId", 0)), "attribute": str(damage.get("DamageAttribType", "None")), "element": str(damage.get("DamageType", "None")), "actType": str(damage.get("DamageActType", "Other")), "critical": bool(damage.get("EnableCriticle", false)), "targetBuffs": applications, "randomTargets": bool(settings.get("RandomEffectObject", false)), "maxTargets": maximum, "summon": settings.get("SummonUnitDefProperty", {}).duplicate(true), "damage": damage_owner._damage_value(damage, damage_owner.effective_attack_power())}

func _status_range_visual(definition: Dictionary, caster: DungeonCombat) -> void:
	var raw: Dictionary = definition.get("raw_data", {})
	if str(raw.get("EffectName", "")).is_empty() and str(raw.get("EffectName1", {}).get("EffectName", "")).is_empty(): return
	_emit_event("buff_effect", {"id": str(definition.id), "phase": "pulse", "definition": raw, "effect_radius": float(_status_area(definition, caster).get("radius", 0))})

func recover_health(amount: float, apply_heal_rate := false) -> float:
	if not is_finite(amount) or amount <= 0 or health <= 0 or _anti_heal_time > 0: return 0.0
	var previous := health
	var recovery := amount * (1.0 + attribute("HealRate") / 1000.0) if apply_heal_rate else amount
	health = clampf(health + recovery, 0.0, max_health)
	_apply_health_locks(previous)
	var restored := maxf(0.0, health - previous)
	_emit_event("heal", {"id": "spring", "amount": restored})
	notify_gameplay("heal", {"amount": restored})
	return restored

func confirm_direct_damage(previous_health: float, context: Dictionary) -> void:
	if not is_finite(previous_health) or previous_health <= health or invincible > 0 or _dodge_time > 0 or _block_time > 0: return
	_emission_sequence += 1
	var impact = context.duplicate(true)
	impact.erase("source")
	impact.merge({"receiver_key": actor_key, "resolved_damage": previous_health - health, "resolved_absorbed": 0.0, "resolved_critical": false, "resolved_accepted": true}, true)
	if not impact.has("emission"): impact["emission"] = _emission_sequence
	impact_confirmed.emit(impact)
	_emit_event("impact_confirmed", impact)

func add_buff(id: String, layers: int = 1, caster_attack: float = -1.0, depth: int = 0) -> bool:
	if id.is_empty() or layers == 0:
		return false
	if depth > 16:
		_report("Buff initialization recursion exceeds 16: " + id)
		return false
	var definition: Dictionary = _buff_index.get(id, {})
	if definition.is_empty():
		_report("Missing buff " + id)
		return false
	if caster_attack < 0:
		caster_attack = effective_attack_power()
	var raw_add: Dictionary = definition.get("raw_data", {})
	if layers > 0:
		var add_cooldowns: Dictionary = custom_properties.get("_buff_add_cooldowns", {})
		if bool(raw_add.get("EnableAddCd", false)) and not bool(raw_add.get("EnableAddCd_CanAddLayer", false)):
			if _clock + 0.000001 < float(add_cooldowns.get(id, 0)):
				return false
			add_cooldowns[id] = _clock + maxf(0.0, float(raw_add.get("EnableAddCd_CdTime", 0)) / 1000.0)
			custom_properties["_buff_add_cooldowns"] = add_cooldowns
		# Instant applications remain visible until the next status tick, but each
		# subsequent application must execute its initialization again.
		if float(definition.get("duration", -1)) == 0 and statuses.has(id) and float(statuses[id].time) <= 0:
			statuses.erase(id)
	if layers > 0:
		for old in definition.get("clear", []):
			statuses.erase(str(old))
	var type = str(definition.get("type", "Unknown"))
	var visual_definition: Dictionary = definition.get("raw_data", {})
	if layers > 0 and type != "EBT_PlayEffect" and not str(visual_definition.get("StartEffect", "")).is_empty():
		_emit_event("buff_effect", {"id": id, "phase": "start", "definition": visual_definition})
	if type == "EBT_SpecialBuffAddByOwnerBuffLayer":
		_apply_buff_layer_mapping(definition, caster_attack, depth)
		return true
	if type == "EBT_SpecialSheild":
		if layers <= 0: return false
		_apply_shield_buff(definition)
		return true
	if type == "EBT_SpecialBuffHP":
		var settings = _settings(definition)
		var amount = max_health * float(settings.get("MaxHpPercentChange", definition.get("healPercent", 0))) / 1000.0 + float(settings.get("MaxHpValueChange", settings.get("FixValueChange", 0)))
		if definition.get("raw_data", {}).get("ChangeMode") == "DamageDef":
			var damage = _damage_data(int(settings.get("DamageDefId", 0)))
			if damage.is_empty():
				_report("Healing damage definition missing: %s %s" % [id, settings.get("DamageDefId", 0)])
			else:
				amount = _damage_value(damage, caster_attack)
		var multiplier_buff = str(settings.get("BeMutiplyBuffId", ""))
		if not multiplier_buff.is_empty():
			amount *= buff_layers(multiplier_buff)
		if _anti_heal_time > 0:
			amount = 0.0
		var previous = health
		health = clampf(health + amount * (1.0 + attribute("HealRate") / 1000.0), 0.0, max_health)
		_apply_health_locks(previous)
		_emit_event("heal", {"id": id, "amount": amount})
		notify_gameplay("heal", {"amount": amount})
		return true
	if bool(definition.get("setState", false)):
		frozen = maxf(frozen, float(definition.get("freezeTime", 0)))
		invincible = maxf(invincible, float(definition.get("godTime", 0)))
		if float(definition.get("slowTime", 0)) > 0:
			_slow_time = maxf(_slow_time, float(definition.slowTime))
			_slow_scale = maxf(0.0, float(definition.get("slowScale", 1)))
		var settings = _settings(definition)
		_dodge_time = maxf(_dodge_time, float(settings.get("DodgeTime", 0)) / 1000.0)
		_block_time = maxf(_block_time, float(settings.get("BlockTime", 0)) / 1000.0)
		_anti_heal_time = maxf(_anti_heal_time, float(settings.get("AntiHealTime", 0)) / 1000.0)
	if type == "EBT_ModifyTargetBuffValue" and not str(definition.get("modify", "")).is_empty() and str(definition.get("syncSource", "")).is_empty():
		add_buff(str(definition.modify), int(definition.get("modifyLayers", 0)), caster_attack, depth + 1)
		return true
	var created = not statuses.has(id)
	if created and layers < 0:
		return false
	if created:
		var timers: Array = []
		var delays: Array = []
		var initial_cooldown = 0.0
		for condition in _spirit_conditions(definition.get("raw_data", {}).get("Conditions", []), _caster_for(id)):
			if condition.get("ConditionType") == "ECT_CheckBuffCD" and bool(condition.get("InitResetCD", false)):
				initial_cooldown = maxf(initial_cooldown, float(condition.get("ColdTime", 0)) / 1000.0)
		for trigger in definition.get("triggers", []):
			timers.append(maxf(initial_cooldown, float(trigger.get("initialDelay", 0))))
			delays.append(-1.0)
		statuses[id] = {"id": id, "layers": 0, "time": float(definition.get("duration", -1)), "tick": maxf(0.0, float(definition.get("firstDelay", 1))), "attack": caster_attack, "modifier_cooldown": 0.0, "trigger_cooldowns": timers, "trigger_delays": delays, "lock_count": 0}
	var entry: Dictionary = statuses[id]
	var caster = _caster_for(id)
	if type == "EBT_NBuffAddCasterUnitAttribToReceiverProperty" and bool(definition.get("raw_data", {}).get("IsSnapShootMode", false)):
		var settings = _settings(definition, caster)
		entry.attribute_basis = (caster if caster != null else self).stat_value(str(settings.get("Attr_CasterUnit", "None")))
	if caster != null:
		entry.caster_actor = caster.character_id if caster.character_id > 0 else caster.enemy_id
		entry.caster_key = caster.actor_key
	else:
		entry.caster_actor = character_id if character_id > 0 else enemy_id
		entry.caster_key = actor_key
	var level_settings = _settings(definition, caster)
	var context_owner = caster if caster != null else self
	var raw_context: Dictionary = definition.get("raw_data", {})
	var maximum_layers = maxi(1, int(definition.get("maxLayers", 1)) + int(level_settings.get("MaxLayerAdd", 0)) + int(context_owner._property_context_total(str(raw_context.get("PropertyContext_AddMaxLayer", "")))))
	var duration = float(definition.get("duration", -1))
	if duration >= 0:
		duration = maxf(0.0, duration + (float(level_settings.get("InitLifeTimeAdd", 0)) + context_owner._property_context_total(str(raw_context.get("PropertyContext_AddDuration", "")))) / 1000.0)
	var old_layers = int(entry.layers)
	entry.layers = clampi(int(entry.layers) + layers, 0, maximum_layers)
	if created or not bool(definition.get("keepDuration", false)):
		entry.time = duration
	entry.attack = caster_attack
	if int(entry.layers) == 0:
		if type != "EBT_SpecialCustomStateBar":
			statuses.erase(id)
			_dispose_status(definition, entry, depth + 1)
		return true
	if created:
		for condition in _spirit_conditions(definition.get("raw_data", {}).get("Conditions", []), _caster_for(id)):
			if condition.get("ConditionType") == "ECT_CheckBuffCD" and bool(condition.get("InitResetCD", false)):
				entry.raw_cooldown = maxf(float(entry.get("raw_cooldown", 0)), float(condition.get("ColdTime", 0)) / 1000.0)
		for child in definition.get("initial", []):
			if _buff_casters.has(id):
				_buff_casters[str(child)] = _buff_casters[id]
			add_buff(str(child), 1, caster_attack, depth + 1)
		_apply_extra_buff(definition, entry, caster_attack, depth)
	if float(definition.get("duration", -1)) == 0:
		for index in range(definition.get("triggers", []).size()):
			var rule: Dictionary = definition.triggers[index]
			if not bool(rule.get("onHit", false)) and rule.get("addedBuffs", []).is_empty() and float(entry.trigger_cooldowns[index]) <= 0 and _requirements(rule):
				_fire(entry, index, caster_attack, depth + 1)
	if layers > 0:
		for listener in statuses.values().duplicate():
			var listener_def: Dictionary = _buff_index.get(listener.id, {})
			for index in range(listener_def.get("triggers", []).size()):
				var rule: Dictionary = listener_def.triggers[index]
				if rule.get("addedBuffs", []).has(id) and float(listener.trigger_cooldowns[index]) <= 0 and _requirements(rule):
					_fire(listener, index, caster_attack, depth + 1)
	if type == "EBT_SpecialCounterTrigger" and int(entry.layers) >= int(definition.get("maxLayers", 1)):
		var raw: Dictionary = definition.get("raw_data", {})
		if not str(raw.get("PlayEffectWhenLayerMax", "")).is_empty():
			_emit_event("buff_effect", {"id": id, "phase": "counter_max", "definition": raw})
		_apply_raw_buff(raw.get("AddBuffWhenLayerMax", {}), caster_attack, depth + 1)
		entry.layers = maxi(0, int(entry.layers) - int(raw.get("ReduceLayerWhenLayerMax", 0)))
	if type == "EBT_NumericalBuff":
		for stat in definition.get("stats", []):
			if not SUPPORTED_ATTRIBUTES.has(str(stat.attribute)) and not HIT_REACTION_ATTRIBUTES.has(str(stat.attribute)) and str(stat.attribute) not in ["SkillActive2ChargeSpeed", "EnvUnitDamageResist", "SkillDodgeLimitMaxUseCount"]:
				_report("Attribute needs system adapter: %s buff %s" % [stat.attribute, id])
	elif type == "Unknown" or (type != "EBT_ConditionBuff" and not str(definition.get("unsupported", "")).is_empty()):
		_report("Buff rule requires review: %s %s %s" % [id, type, definition.get("unsupported", "")])
	if type == "EBT_SpecialTriggerRangeDamage" and not bool(definition.get("selfOnlyDamage", false)) and _status_area(definition, _caster_for(id)).is_empty():
		_report("Unsupported area effect: %s %s" % [id, definition.get("areaUnsupported", "")])
	notify_gameplay("buff_add", {"id": id, "layers": int(entry.layers) - old_layers, "before": old_layers, "after": int(entry.layers)})
	return true

func buff_layers(id: String) -> int:
	return int(statuses[id].layers) if statuses.has(id) else 0

func remove_buff(id: String) -> void:
	statuses.erase(id)

func _dispose_status(definition: Dictionary, entry: Dictionary, depth: int = 0) -> void:
	var disposal: Dictionary = definition.get("raw_data", {}).get("DisposeTriggerBuff", {})
	var id = str(definition.get("disposeBuff", disposal.get("BuffTriggerId", "")))
	if id.is_empty(): return
	bind_buff_caster(id, _caster_for(str(entry.id)))
	add_buff(id, int(definition.get("disposeLayers", disposal.get("BuffAddLayer", 1))), float(entry.attack), depth)

func special_resource() -> int:
	return buff_layers(str(fighter.get("jp", "")))

func special_resource_fraction() -> float:
	var maximum := maxi(1, int(_buff_index.get(str(fighter.get("jp", "")), {}).get("maxLayers", 1)))
	return clampf(float(special_resource()) / maximum, 0, 1)

func charge_stage() -> int:
	return 3 if buff_layers("700003") > 0 else 2 if buff_layers("700002") > 0 else 1 if buff_layers("700001") > 0 else 0

func is_transformed() -> bool:
	return buff_layers("700200") > 0 or buff_layers("200202") > 0 or buff_layers("200400") > 0

func can_be_attracted() -> bool:
	if health <= 0: return false
	if enemy.is_empty():
		EnemyHitReaction.rules_for(0)
		var state := int(EnemyHitReaction._action_states.get("ActGroup_playerchara/" + current_action, -1))
		if state in [6, 31, 32] or stagger_remaining > 0: return false
	return true

func attraction_weight() -> float:
	EnemyHitReaction.rules_for(enemy_id)
	var group := "ActGroup_playerchara" if enemy.is_empty() else str(enemy.get("group", ""))
	var action_rules: Dictionary = EnemyHitReaction._action_hit_rules.get(group + "/" + current_action, {})
	# UnitRuntimeStatus initializes BaseWeight to 100; enemy configs override it.
	var value := (100.0 if enemy.is_empty() else float(enemy_hit_rules.get("Weight", 100))) + float(action_rules.get("WeightAddValue", 0)) + attribute("Weight")
	return value if is_finite(value) and value > 0 else 100.0

func can_receive_attack() -> bool:
	if not enemy.is_empty(): return bool(custom_properties.get("_action_can_hit", true))
	return busy <= 0 or bool(custom_properties.get("_action_can_hit", true))

func _tick_attack_collision_gate() -> void:
	if busy <= 0 and enemy.is_empty(): return
	var definition = _action("ActGroup_playerchara" if enemy.is_empty() else str(enemy.get("group", "")), current_action)
	var elapsed = action_elapsed * maxf(0.01, float(custom_properties.get("_feel_action_speed", 1)))
	var previous = float(custom_properties.get("_can_hit_evaluated", -1.0))
	var active: Dictionary = custom_properties.get("_can_hit_windows", {})
	if _collision_events_sequence != _cast_sequence:
		_collision_events_sequence = _cast_sequence
		_collision_events = definition.get("events", []).filter(func(command): return command.get("enabled", false) and command.get("type", "") == "EET_CanBeHit")
		_collision_events.sort_custom(func(a, b): return float(a.time) < float(b.time))
	var commands: Array = _collision_events
	for index in commands.size():
		var command: Dictionary = commands[index]
		var start = float(command.get("time", 0))
		var duration = float(command.get("duration", 0))
		if elapsed + 0.000001 < start: continue
		var triggered = previous < start and elapsed + 0.000001 >= start
		var key = str(index)
		if triggered:
			if not _conditions(command.get("conditions", []), bool(command.get("all", true))): continue
			if duration > 0: active[key] = true
		elif not active.has(key) or elapsed > start + duration + 0.000001:
			continue
		var raw = _read_raw_json(str(command.get("raw", "{}")))
		if raw is Dictionary and raw.has("IsCanBeHit"):
			custom_properties["_action_can_hit"] = bool(raw.IsCanBeHit)
	# Native Exit is a no-op: the last write survives until this action is reset.
	custom_properties["_can_hit_evaluated"] = elapsed
	custom_properties["_can_hit_windows"] = active

func is_busy() -> bool:
	return busy > 0

func effective_attack_power() -> float:
	return (attack + attribute("BaseAtk") + attribute("AtkAddFixed")) * (1.0 + attribute("AtkAddRate") / 1000.0)

func move_multiplier() -> float:
	return (0.0 if frozen > 0 else _slow_scale if _slow_time > 0 else 1.0) * maxf(0.1, 1.0 + attribute("MoveSpeedRate") / 1000.0)

func attribute(name: String) -> float:
	var value = float(_external.get(name, 0.0))
	if statuses.is_empty(): return value
	if _attribute_stack.has(name):
		return value
	_attribute_stack[name] = true
	for entry in statuses.values():
		var definition: Dictionary = _buff_index.get(entry.id, {})
		if definition.get("type") == "EBT_NumericalBuff" and not _external_numeric_buffs.has(entry.id):
			var settings = _settings(definition, _caster_for(str(entry.id)))
			var stats: Array = settings.get("BuffDataList", [])
			if stats.is_empty() and definition.get("raw_data", {}).get("BuffSettingDataList", []).is_empty():
				stats = definition.get("stats", [])
			for stat in stats:
				var stat_name = str(stat.get("Attr", stat.get("attribute", "")))
				if stat_name == name:
					value += float(stat.get("AddValue", stat.get("value", 0))) * int(entry.layers)
		elif definition.get("type") == "EBT_NBuffAddCasterUnitAttribToReceiverProperty":
			var settings = _settings(definition, _caster_for(str(entry.id)))
			if settings.get("Attr_Receiver") != name:
				continue
			var caster = _caster_for(str(entry.id))
			var basis = float(entry.attribute_basis) if entry.has("attribute_basis") else (caster if caster != null else self).stat_value(str(settings.get("Attr_CasterUnit", "None")))
			var addition = 0.0
			if basis >= float(settings.get("StartThresholdValue", 0)):
				if settings.get("AddModeType") == "PerNumAddMode":
					addition = floor((basis - float(settings.get("StartThresholdValue", 0))) / maxf(0.001, float(settings.get("PerNumValue", 1)))) * float(settings.get("PerAddValue", 0))
				else:
					addition = float(settings.get("AddValue", 0)) + basis * float(settings.get("MulValue", 0)) / 1000.0
			if float(settings.get("FinalMaxAddValue", -1)) >= 0:
				addition = minf(addition, float(settings.FinalMaxAddValue))
			value += addition * int(entry.layers)
	_attribute_stack.erase(name)
	return value

func set_external_attributes(attributes: Dictionary) -> void:
	_external = attributes.duplicate()
	health = minf(health, max_health)

func set_stats(attack_value: float, defense_value: float, max_hp_value: float) -> void:
	attack = attack_value
	defense = defense_value
	max_health = max_hp_value
	health = minf(health, max_health)

func set_progression_buffs(roots: Array, externally_counted_numeric_ids: Array = []) -> void:
	var next: Dictionary = {}
	for root in roots:
		if root is Dictionary and not str(root.get("id", "")).is_empty() and int(root.get("layers", 0)) > 0:
			next[str(root.id)] = int(next.get(str(root.id), 0)) + int(root.layers)
	_external_numeric_buffs = externally_counted_numeric_ids.duplicate()
	if next != _progression_roots:
		var retired: Dictionary = {}
		var retained: Dictionary = {}
		for id in _progression_roots:
			if not next.has(id): _collect_progression_effects(str(id), retired)
		for id in next: _collect_progression_effects(str(id), retained)
		for id in retired:
			if retained.has(id) or _buff_index.get(id, {}).get("type") == "EBT_SpecialCustomStateBar": continue
			# Removal must not run disposal transitions that can revive an old form.
			statuses.erase(id)
		_pending = _pending.filter(func(event):
			var id := str(event.get("condition_effect", {}).get("id", ""))
			return not retired.has(id) or retained.has(id))
	var required: Dictionary = {}
	for id in next:
		_collect_initial(str(id), required)
	for id in _progression_owned.duplicate():
		if not required.has(id):
			if _buff_index.get(id, {}).get("type") != "EBT_SpecialCustomStateBar":
				statuses.erase(id)
			_progression_owned.erase(id)
	for id in next:
		var before = int(_progression_roots.get(id, 0))
		if before == int(next[id]) or (statuses.has(id) and not _progression_owned.has(id)):
			continue
		var existing = statuses.keys()
		add_buff(id, int(next[id]) - before)
		for added in statuses:
			if not existing.has(added) and required.has(added):
				_progression_owned.append(added)
	_progression_roots = next
	health = minf(health, max_health)

func cancel() -> void:
	for window in battle_time_scale_windows():
		_expire_battle_time_scale_windows(int(window.sequence))
	_pending = _pending.filter(func(event): return event.has("condition_effect"))
	busy = 0.0
	charging = false
	_clear_charge()

func revive(health_value: float, protection: float = 2.0) -> bool:
	if health > 0 or health_value <= 0 or not is_finite(health_value) or not is_finite(protection):
		return false
	cancel()
	current_action = ""
	health = minf(max_health, health_value)
	invincible = maxf(0.0, protection)
	_dead_emitted = false
	_emit_event("revived", {"health": health})
	return true

func enemy_preferred_range() -> float:
	for action_name in enemy.get("actions", []):
		for hit in _action(str(enemy.get("group", "")), str(action_name)).get("hits", []):
			if bool(hit.get("projectile", false)):
				return 7.0
	return 3.2 if enemy.get("rank") == "Boss" else 1.7

func snapshot() -> Dictionary:
	custom_properties["_emission_sequence"] = _emission_sequence
	custom_properties["_actor_key"] = actor_key
	custom_properties["_defensive_timers"] = {"dodge": _dodge_time, "dodge_recharge": _dodge_recharge_elapsed, "block": _block_time, "anti_heal": _anti_heal_time}
	custom_properties["_local_action_elapsed"] = action_elapsed
	custom_properties["_recovery_credit"] = _recovery_credit
	if enemy_ai != null:
		custom_properties["_enemy_ai"] = enemy_ai.snapshot()
		custom_properties["_enemy_ai_enabled"] = enemy_ai_enabled
	return {"version": 1, "character_id": character_id, "enemy_id": enemy_id, "difficulty": difficulty, "attack": attack, "defense": defense, "max_health": _base_max_health, "health": health, "armor": armor, "shield": shield, "invincible": invincible, "frozen": frozen, "slow_time": _slow_time, "slow_scale": _slow_scale, "clock": _clock, "busy": busy, "combo": _combo, "combo_expiry": _combo_expiry, "cast_sequence": _cast_sequence, "current_slot": _current_slot, "current_action": current_action, "random_state": _random_state, "energy": energy.duplicate(), "cooldowns": cooldowns.duplicate(), "skill_round_uses": skill_round_uses.duplicate(), "pending": _pending.duplicate(true), "statuses": statuses.duplicate(true), "external": _external.duplicate(), "progression_roots": _progression_roots.duplicate(), "progression_owned": _progression_owned.duplicate(), "external_numeric_buffs": _external_numeric_buffs.duplicate(), "charging": charging, "charge_released": charge_released, "charge_elapsed": charge_elapsed, "custom_properties": custom_properties.duplicate(true), "diagnostics": diagnostics.duplicate()}

func restore(saved: Dictionary) -> bool:
	_collision_events_sequence = -1
	_heavy_events_sequence = -1
	if int(saved.get("version", 0)) != 1 or int(saved.get("character_id", -1)) != character_id or int(saved.get("enemy_id", -1)) != enemy_id:
		return false
	for key in ["health", "max_health", "attack", "defense", "clock", "busy", "invincible", "frozen"]:
		if not is_finite(float(saved.get(key, NAN))):
			return false
	if not saved.get("energy") is Array or saved.energy.size() != 5 or not saved.get("cooldowns") is Array or saved.cooldowns.size() != 5 or not saved.get("statuses") is Dictionary or not saved.get("pending") is Array:
		return false
	if saved.has("skill_round_uses") and (not saved.skill_round_uses is Array or saved.skill_round_uses.size() != 5): return false
	difficulty = clampi(int(saved.get("difficulty", difficulty)), 0, 10)
	_base_max_health = maxf(1.0, float(saved.max_health))
	attack = float(saved.attack)
	defense = float(saved.defense)
	armor = maxf(0.0, float(saved.get("armor", 0)))
	shield = maxf(0.0, float(saved.get("shield", 0)))
	_external = saved.get("external", {}).duplicate()
	statuses = saved.statuses.duplicate(true)
	for id in statuses.keys():
		if not _buff_index.has(id):
			statuses.erase(id)
			_report("Saved buff missing " + str(id))
		else:
			var count = _buff_index[id].get("triggers", []).size()
			if statuses[id].get("trigger_cooldowns", []).size() != count or statuses[id].get("trigger_delays", []).size() != count:
				return false
	health = clampf(float(saved.health), 0.0, max_health)
	invincible = maxf(0.0, float(saved.invincible))
	frozen = maxf(0.0, float(saved.frozen))
	_slow_time = maxf(0.0, float(saved.get("slow_time", 0)))
	_slow_scale = maxf(0.0, float(saved.get("slow_scale", 1)))
	_clock = float(saved.clock)
	busy = maxf(0.0, float(saved.busy))
	_combo = int(saved.get("combo", 0))
	_combo_expiry = float(saved.get("combo_expiry", 0))
	_cast_sequence = int(saved.get("cast_sequence", 0))
	_current_slot = int(saved.get("current_slot", 0))
	current_action = str(saved.get("current_action", ""))
	_random_state = int(saved.get("random_state", 1)) & 0xffffffff
	energy = saved.energy.duplicate()
	cooldowns = saved.cooldowns.duplicate()
	skill_round_uses = saved.get("skill_round_uses", cooldowns.map(func(value): return 1 if float(value) > 0 else 0)).duplicate()
	_pending = saved.pending.duplicate(true)
	if enemy.is_empty() and _current_slot == 4:
		_pending = _pending.filter(func(event): return not (_action_event(event) and event.get("command", {}).get("type", "") == "EET_Interrupt"))
	_progression_roots = saved.get("progression_roots", {}).duplicate()
	_progression_owned = saved.get("progression_owned", []).duplicate()
	_external_numeric_buffs = saved.get("external_numeric_buffs", []).duplicate()
	charging = bool(saved.get("charging", false))
	charge_released = bool(saved.get("charge_released", false))
	charge_elapsed = float(saved.get("charge_elapsed", 0))
	custom_properties = saved.get("custom_properties", {}).duplicate(true)
	enemy_hit_motion_step = -1.0
	if not enemy.is_empty(): EnemyHitReaction.restore_state(self)
	if not enemy.is_empty() and not current_action.is_empty(): custom_properties["_enemy_spawn_entered"] = true
	enemy_ai_enabled = bool(custom_properties.get("_enemy_ai_enabled", false)) and enemy_ai != null
	if enemy_ai != null and custom_properties.has("_enemy_ai"): enemy_ai.restore(custom_properties._enemy_ai)
	_cache_enemy_timing(_action(str(enemy.get("group", "")), current_action))
	clear_impact_state()
	action_elapsed = maxf(0, float(custom_properties.get("_local_action_elapsed", _clock - float(custom_properties.get("_feel_action_started", _clock)))))
	if not custom_properties.has("_action_can_hit"):
		custom_properties["_action_can_hit"] = bool(_heavy_catalog.get("actions", {}).get(current_action, {}).get("can_hit", true))
		if not enemy.is_empty(): custom_properties["_action_can_hit"] = bool(EnemyHitReaction.action_rules_for(self).get("CanHit", true))
		_tick_attack_collision_gate()
	var saved_credit = float(custom_properties.get("_recovery_credit", 0))
	_recovery_credit = saved_credit if is_finite(saved_credit) else 0.0
	_emission_sequence = int(custom_properties.get("_emission_sequence", 0))
	actor_key = str(custom_properties.get("_actor_key", actor_key))
	var timers: Dictionary = custom_properties.get("_defensive_timers", {})
	_dodge_time = maxf(0.0, float(timers.get("dodge", 0)))
	_dodge_recharge_elapsed = maxf(0.0, float(timers.get("dodge_recharge", 0)))
	_block_time = maxf(0.0, float(timers.get("block", 0)))
	_anti_heal_time = maxf(0.0, float(timers.get("anti_heal", 0)))
	diagnostics = saved.get("diagnostics", []).duplicate()
	_buff_casters.clear()
	events.clear()
	_dead_emitted = health <= 0
	return true

func drain_events() -> Array:
	var result = events
	events = []
	return result

func _start(definition: Dictionary, slot: int) -> void:
	if enemy_ai != null and not current_action.is_empty() and int(custom_properties.get("_enemy_ended_sequence", -1)) != _cast_sequence:
		enemy_ai.notify_action_ended(current_action)
	_cancel_sequence(_cast_sequence, true)
	if enemy.is_empty(): custom_properties.InputSkill = false
	_current_slot = slot
	current_action = str(definition.id)
	if not enemy.is_empty(): EnemyHitReaction.action_started(self, definition)
	_cache_enemy_timing(definition)
	custom_properties["_action_can_hit"] = bool(_heavy_catalog.get("actions", {}).get(current_action, {}).get("can_hit", true))
	if not enemy.is_empty(): custom_properties["_action_can_hit"] = bool(EnemyHitReaction.action_rules_for(self).get("CanHit", true))
	custom_properties["_can_hit_evaluated"] = -1.0
	custom_properties["_can_hit_windows"] = {}
	custom_properties["_movement_windows"] = []
	custom_properties["_action_speed_windows"] = []
	custom_properties["_heavy_interrupt_admission"] = {}
	custom_properties["_heavy_graph"] = enemy.is_empty() and (slot == 4 or (slot == 0 and custom_properties.get("AttackModeStr", "normal") == "satk"))
	if slot == 4 and current_action == "lance_satk":
		charging = true
		charge_released = false
		charge_elapsed = 0.0
	_cast_sequence += 1
	action_elapsed = 0.0
	_recovery_credit = 0.0
	_compensate_pause = false
	var speed = maxf(0.01, float(definition.get("speed", 1))) * maxf(0.1, 1.0 + attribute("AttackSpeedRate") / 1000.0)
	custom_properties["_feel_action_started"] = _clock
	custom_properties["_feel_action_speed"] = speed
	custom_properties["_rhythm_enabled"] = enemy.is_empty() and not _using_heavy_graph() and slot != 1 and definition.get("hits", []).any(func(hit): return hit.get("enabled", false) and not preload("res://scripts/presentation/impact_profiles.gd").ranged({"definition": hit}))
	var last_hit = 0.0
	for hit in definition.get("hits", []):
		if bool(hit.get("enabled", false)):
			last_hit = maxf(last_hit, float(hit.time) / speed)
	busy = maxf(0.18, minf(float(definition.duration) / speed, maxf(last_hit + 0.18, 0.45)))
	var heavy_graph = _using_heavy_graph()
	if heavy_graph:
		busy = maxf(0.18, float(definition.duration) / speed)
	if enemy.is_empty() and slot == 0 and not heavy_graph:
		custom_properties["_feel_next_combo"] = ""
		var first_window := INF
		for command in definition.get("events", []):
			if not command.get("enabled", false) or command.get("type", "") != "EET_Interrupt": continue
			var target = str(command.get("target", ""))
			if not fighter.get("combo", []).has(target): continue
			var raw = _read_raw_json(str(command.get("raw", "{}")))
			var conditions: Array = raw.get("Conditions", []) if raw is Dictionary else []
			if conditions.size() != 1: continue
			var condition: Dictionary = conditions[0]
			if condition.get("InterruptType", "") != "EIT_CheckCustomPropertyBool" or condition.get("Property", "") != "InputAttack" or not condition.get("CompareVal", false): continue
			var start = float(command.get("time", 0)) / speed
			if start > 0 and start < first_window:
				first_window = start
				custom_properties["_feel_next_combo"] = target
		if first_window < INF: busy = first_window
	if not enemy.is_empty():
		busy = 0.0 if current_action.begins_with("idle") else maxf(0.18, float(definition.duration) / speed)
	custom_properties["_movement_sequence"] = _cast_sequence
	_emit_event("action_started", {"action": current_action, "slot": slot, "sequence": _cast_sequence, "duration": busy, "timeline_duration": float(definition.duration), "speed": speed})
	if enemy_ai != null: enemy_ai.notify_action_started(current_action)
	notify_gameplay("action_start", {"slot": slot, "action": current_action})
	for hit in definition.get("hits", []):
		if bool(hit.get("enabled", false)):
			_schedule(hit, _clock + float(hit.time) / speed, current_action, slot, 0.0)
	for command_index in definition.get("events", []).size():
		var command: Dictionary = definition.events[command_index]
		if bool(command.get("enabled", false)):
			if enemy_ai_enabled and command.get("type", "") == "EET_Interrupt": continue
			if heavy_graph and command.get("type", "") == "EET_Interrupt": continue
			_pending.append({"at": _clock + float(command.time) / speed, "sequence": _cast_sequence, "action": current_action, "slot": slot, "command": command, "command_index": command_index, "action_timeline": true})

func _tick_heavy_interrupts() -> void:
	var definition = _action("ActGroup_playerchara", current_action)
	if _heavy_events_sequence != _cast_sequence:
		_heavy_events_sequence = _cast_sequence
		_heavy_events = definition.get("events", []).filter(func(command): return command.get("enabled", false) and command.get("type", "") == "EET_Interrupt")
		_heavy_events.sort_custom(func(a, b): return float(a.time) < float(b.time))
	var interrupts: Array = _heavy_events
	var speed = maxf(0.01, float(custom_properties.get("_feel_action_speed", 1)))
	var elapsed = action_elapsed * speed
	var admitted: Dictionary = custom_properties.get("_heavy_interrupt_admission", {})
	for index in interrupts.size():
		var command: Dictionary = interrupts[index]
		var start = float(command.get("time", 0))
		var duration = float(command.get("duration", 0))
		if elapsed + 0.000001 < start: continue
		if duration > 0 and elapsed > start + duration + 0.000001: continue
		var key = str(index)
		if not admitted.has(key): admitted[key] = _conditions(command.get("conditions", []), bool(command.get("all", true)))
		custom_properties["_heavy_interrupt_admission"] = admitted
		if not admitted[key]: continue
		var raw = _read_raw_json(str(command.get("raw", "{}")))
		if not raw is Dictionary or not _interrupt_conditions(raw): continue
		var target = str(command.get("target", ""))
		# Keep heavy action branches local; skill, movement and normal input use the input buffer.
		if "satk" in target or "SmiteDerivative" in target or target == "orb_smite_0jp":
			var next = _action("ActGroup_playerchara", target)
			if next.is_empty(): continue
			if charging and current_action == "lance_satk": _release_charge(target)
			else: _start(next, 4)
			return
		if fighter.get("combo", []).has(target) or target == "sys_checkatk_1":
			if custom_properties.get("_auto_heavy_only", false): continue
			if custom_properties.get("AttackModeStr", "satk") != "satk": continue
			if target == "sys_checkatk_1": target = str(fighter.combo[0])
			var next = _action("ActGroup_playerchara", target)
			if not next.is_empty():
				_start(next, 0)
				return
		if target == "sys_idle" or target.begins_with("idle_"):
			_cancel_sequence(_cast_sequence, true)
			busy = 0.0
			charging = false
			_emit_event("action_cancelled", {"sequence": _cast_sequence})
			return
		if target == "sys_run" or target.begins_with("run_"):
			_cancel_sequence(_cast_sequence, true)
			busy = 0.0
			charging = false
			_clear_charge()
			_emit_event("action_cancelled", {"sequence": _cast_sequence})
			return

func _tick_movement_interrupts() -> void:
	if int(custom_properties.get("_movement_sequence", -1)) != _cast_sequence: return
	var elapsed = action_elapsed * maxf(0.01, float(custom_properties.get("_feel_action_speed", 1)))
	for command in custom_properties.get("_movement_windows", []):
		var target = str(command.get("target", ""))
		var start = float(command.get("time", 0))
		var duration = float(command.get("duration", 0))
		if elapsed + 0.000001 < start or (duration > 0 and elapsed > start + duration + 0.000001): continue
		var raw = _read_raw_json(str(command.get("raw", "{}")))
		if not raw is Dictionary: continue
		if target == "sys_checkdodgeatk":
			if _try_dodge_attack_interrupt(raw): return
			continue
		if not _interrupt_conditions(raw): continue
		if not target.begins_with("sys_") and not target.begins_with("run_") and not target.begins_with("idle_"):
			if fighter.get("combo", []).has(target): continue
			var next = _action("ActGroup_playerchara", target)
			if not next.is_empty():
				_start(next, _current_slot)
				return
			continue
		if target != "sys_run" and target != "sys_idle" and not target.begins_with("run_") and not target.begins_with("idle_"): continue
		_cancel_sequence(_cast_sequence, true)
		custom_properties["_movement_sequence"] = -1
		busy = 0.0
		_emit_event("action_cancelled", {"sequence": _cast_sequence})
		return

func _try_dodge_attack_interrupt(raw: Dictionary) -> bool:
	if statuses.has("26080801"): return false
	var manual := bool(custom_properties.get("InputAttack", false))
	if statuses.has("26081001"): custom_properties.InputAttack = true
	var admitted := _interrupt_conditions(raw)
	custom_properties.InputAttack = manual
	if not admitted: return false
	var dispatcher := _action("ActGroup_playerchara", "sys_checkdodgeatk")
	for branch in dispatcher.get("events", []):
		if not branch.get("enabled", false): continue
		var condition: Dictionary = _read_raw_json(str(branch.get("raw", "{}")))
		if condition.get("Conditions", []).is_empty() or not _interrupt_conditions(condition): continue
		var dodge_attack := _action("ActGroup_playerchara", str(branch.get("target", "")))
		if not dodge_attack.is_empty():
			_start(dodge_attack, 0)
			return true
	return false

func _schedule(hit: Dictionary, at: float, action_name: String, slot: int, offset: float, summon_id: String = "", origin: Dictionary = {}, target_key: String = "") -> void:
	hit = _modified_attack_definition(hit)
	var raw: Dictionary = _read_raw_json(str(hit.get("raw", "{}")))
	var emit: Dictionary = raw.get("EmitProperty", {})
	var emissions: Array = []
	if raw.get("EmitType", "") == "EET_MultiPoint":
		var points: Array = emit.get("PointData", [])
		for index in points.size(): emissions.append({"index": index, "delay": maxf(0, float(points[index].get("Delay", 0)))})
		emissions.sort_custom(func(a, b): return int(a.index) < int(b.index) if is_equal_approx(float(a.delay), float(b.delay)) else float(a.delay) < float(b.delay))
		emissions.resize(mini(emissions.size(), clampi(int(hit.get("count", 1)), 0, 100)))
	else:
		for index in range(clampi(int(hit.get("count", 1)), 1, 100)):
			emissions.append({"index": index, "delay": index * float(hit.get("interval", 0))})
	var emitter_id := int(custom_properties.get("_emitter_sequence", 0)) + 1
	custom_properties["_emitter_sequence"] = emitter_id
	if summon_id.is_empty() and emit.has("EndEmitWhenActionChange") and not bool(emit.EndEmitWhenActionChange) and not emissions.is_empty():
		# An emitter becomes independent when its source event starts, including delayed points.
		_pending.append({"at": at, "sequence": _cast_sequence, "emitter_start": emitter_id, "action_timeline": true})
	for emission in emissions:
		_pending.append({"at": at + float(emission.delay), "sequence": _cast_sequence, "action": action_name, "slot": slot, "hit": hit, "emit_index": int(emission.index), "emitter_id": emitter_id, "offset": offset, "summon_id": summon_id, "origin": origin.duplicate(true), "target_key": target_key, "action_timeline": summon_id.is_empty()})

func source_stop_frame_modifier(definition: Dictionary) -> float:
	if statuses.is_empty(): return 0.0
	var raw: Variant = definition.get("raw", definition)
	if raw is String: raw = JSON.parse_string(raw)
	if not raw is Dictionary: return 0.0
	var attack_id := int(raw.get("Id", definition.get("damageId", 0)))
	if attack_id == 0: return 0.0
	var value := 0.0
	for entry in statuses.values():
		var buff: Dictionary = _buff_index.get(entry.id, {})
		if buff.get("type") != "EBT_ModifyAttackDef": continue
		var settings := _settings(buff, _caster_for(str(entry.id)))
		if settings.get("AttackDefIdList", []).any(func(id): return int(id) == attack_id):
			# APK type11 reads this float directly, without multiplying layers.
			value += float(settings.get("HitFeedBack_StopFrameAdd", 0))
	return value

func _modified_attack_definition(definition: Dictionary) -> Dictionary:
	if bool(definition.get("_entity_modifiers_resolved", false)): return definition
	var modifiers: Array = []
	for entry in statuses.values():
		if _buff_index.get(entry.id, {}).get("type") == "EBT_ModifyAttackDef": modifiers.append(entry)
	var raw = _read_raw_json(str(definition.get("raw", "{}")))
	if not raw is Dictionary: return definition
	var attack_id = int(raw.get("Id", definition.get("damageId", 0)))
	var entity: Dictionary = raw.get("EntityProperty", {})
	var physical: bool = raw.get("EntityType", "") == "EET_Physical"
	var size_add := 0.0
	var count_add := 0
	var interval_summons: Array = []
	for entry in modifiers:
		var buff: Dictionary = _buff_index.get(entry.id, {})
		var settings = _settings(buff, _caster_for(str(entry.id)))
		if attack_id == 0 or not settings.get("AttackDefIdList", []).any(func(id): return int(id) == attack_id): continue
		size_add += float(settings.get("ModifyEntity_PhysicEntitySizeAddPercent" if physical else "ModifyEntity_RangePercent", 0)) * int(entry.layers) / 1000.0
		count_add += int(settings.get("ModifyEmit_Num", 0)) * int(entry.layers)
		if physical: interval_summons.append_array(settings.get("ModifyEntity_PhysicEntityIntervalAddSummonUnitList", []))
	size_add += _property_context_total(str(entity.get("ScaleModifyPropertyName", ""))) / 1000.0
	var factor := maxf(0.0, _spirit_apply(1.0 + size_add, entity.get("ScaleSpiritModifier", {}), self))
	if is_equal_approx(factor, 1.0) and count_add == 0 and interval_summons.is_empty(): return definition
	definition = definition.duplicate(true)
	raw = raw.duplicate(true)
	entity = raw.get("EntityProperty", {})
	for key in ["ModelBoxColliderSize", "ModlePrefabSize"]:
		if entity.get(key) is Dictionary: _scale_components(entity[key], factor)
	for key in ["Radius", "Width", "Length", "Height"]:
		if entity.has(key): entity[key] = float(entity[key]) * factor
	for key in ["EffectTriggerDef", "EffectDelayTriggerDef"]:
		var effect: Dictionary = entity.get(key, {})
		if effect.get("Scale") is Dictionary: _scale_components(effect.Scale, factor)
	definition.width = float(definition.get("width", 1)) * factor
	definition.length = float(definition.get("length", 1)) * factor
	if count_add != 0:
		definition.count = maxi(1, int(definition.get("count", 1)) + count_add)
		if raw.get("EmitProperty") is Dictionary: raw.EmitProperty.Num = definition.count
	if not interval_summons.is_empty():
		var intervals: Array = entity.get("IntervalCreateSummonUnitDefList", [])
		intervals.append_array(interval_summons.duplicate(true))
		entity["IntervalCreateSummonUnitDefList"] = intervals
	raw["EntityProperty"] = entity
	definition.raw = JSON.stringify(raw)
	definition["_entity_modifiers_resolved"] = true
	return definition

func _scale_components(value: Dictionary, factor: float) -> void:
	for axis in ["x", "y", "z"]:
		if value.has(axis): value[axis] = float(value[axis]) * factor

func _effective_summon_definition(definition: Dictionary) -> Dictionary:
	var raw: Dictionary = definition.get("raw_data", {})
	var duration := _spirit_apply(float(raw.get("Duration", definition.get("lifetime", 0))), raw.get("DurationSpiritModifier", {}), self)
	var scale := maxf(0.0, _spirit_apply(1.0, raw.get("PrefabScaleModifySpiritModifier", {}), self))
	var hit := _modified_attack_definition(definition.get("hit", {}))
	if is_equal_approx(duration, float(definition.get("lifetime", 0))) and is_equal_approx(scale, 1.0) and hit == definition.get("hit", {}): return definition
	definition = definition.duplicate(true)
	raw = definition.get("raw_data", {})
	raw["Duration"] = duration
	if raw.get("PrefabScale") is Dictionary: _scale_components(raw.PrefabScale, scale)
	var effective_hit = _read_raw_json(str(hit.get("raw", "{}")))
	if effective_hit is Dictionary: raw["EntityProperty"] = effective_hit.get("EntityProperty", {}).duplicate(true)
	definition.hit = hit
	definition.lifetime = duration
	definition.raw = JSON.stringify({"SummonUnitType": definition.get("type", ""), "SummonUnitData": raw})
	return definition

func _execute(event: Dictionary) -> void:
	var command: Dictionary = event.command
	if not _conditions(command.get("conditions", []), bool(command.get("all", true))):
		return
	var raw = JSON.parse_string(str(command.get("raw", "{}")))
	if not raw is Dictionary:
		raw = {}
	match str(command.type):
		"EET_BattleTimeScaleModify":
			var windows: Dictionary = custom_properties.get("_battle_time_scale_windows", {})
			var key = "%d:%d" % [int(event.sequence), int(event.get("command_index", -1))]
			var window = {"key": key, "sequence": int(event.sequence), "index": int(event.get("command_index", -1)), "action": str(event.action), "start": float(command.time), "end": float(command.time) + float(command.get("duration", 0)), "scale": float(raw.get("ModifyBattleTimeScale", 1)), "duration": float(command.get("duration", 0)), "definition": raw.duplicate(true)}
			windows[key] = window
			custom_properties["_battle_time_scale_windows"] = windows
			_emit_event("battle_time_scale", {"phase": "Enter", "window": window.duplicate(true)})
		"EET_ActionSpeedScale":
			if _using_heavy_graph() and float(command.get("duration", 0)) > 0:
				var windows: Array = custom_properties.get("_action_speed_windows", [])
				windows.append({"end": float(command.time) + float(command.duration), "rate": maxf(0.01, float(raw.get("ScaleSpeed", 1)))})
				custom_properties["_action_speed_windows"] = windows
		"EET_AddBuff":
			add_buff(str(command.buff), int(command.layers))
		"EET_AddSummonUnit":
			_spawn_summon(str(command.summon), float(event.at), str(event.action), int(event.slot), float(command.get("offset", 0)), 0, raw.get("AddSummonUnitDef", {}))
		"EET_Interrupt":
			var target = str(command.get("target", ""))
			if enemy.is_empty() and not _using_heavy_graph():
				var windows: Array = custom_properties.get("_movement_windows", [])
				windows.append(command)
				custom_properties["_movement_windows"] = windows
			if str(event.action).begins_with("lance_satk") and bool(command.get("unconditionalInterrupt", false)) and target.begins_with("lance_satk"):
				_release_charge(target)
			elif _current_slot == 4 and character_id == 3 and target.begins_with("axe_satk") and _interrupt_conditions(raw):
				if target == "axe_satk_loop" and special_resource() <= 0:
					target = "axe_satk_end"
				var next = _action("ActGroup_playerchara", target)
				if not next.is_empty():
					_cancel_sequence(_cast_sequence)
					_start(next, 4)
			elif not enemy.is_empty() and bool(command.get("unconditionalInterrupt", false)) and not target.begins_with("sys_"):
				var next = _action(str(enemy.group), target)
				if not next.is_empty():
					_cancel_sequence(_cast_sequence)
					_start(next, 0)
		"EET_SetCustomPropertyInt32":
			var property = str(raw.get("CustomProperty", ""))
			if property.is_empty(): property = str(raw.get("Property", ""))
			var value = int(raw.get("Value", raw.get("Val", raw.get("SetValue", 0))))
			if str(raw.get("OperationMethod", "Set")) == "Add": value += int(custom_properties.get(property, 0))
			custom_properties[property] = value
		"EET_CanBeHit":
			pass # Evaluated in action-time order, including active duration windows.
		"EET_MonsterGeneration":
			_emit_event("spawn_monster", {"definition": raw})
		"EET_DelUnit":
			if custom_properties.get("_enemy_death_started", false):
				custom_properties["_enemy_deleted" if raw.get("Delete", true) else "_enemy_visual_hidden"] = true
			_emit_event("delete_unit", {"definition": raw})
		"EET_SendMessage":
			_emit_event("message", {"definition": raw})
	_emit_event("command", {"command": command, "action": event.action, "slot": event.slot, "sequence": event.sequence, "speed": float(custom_properties.get("_feel_action_speed", 1.0))})

func _emit_hit(event: Dictionary) -> void:
	var definition: Dictionary = _modified_attack_definition(event.hit).duplicate()
	var damage_data = _damage_data(int(definition.get("damageId", 0)))
	if not damage_data.is_empty():
		definition.attribute = str(damage_data.get("DamageAttribType", definition.get("attribute", "None")))
		definition.element = str(damage_data.get("DamageType", definition.get("element", "None")))
		definition.actType = str(damage_data.get("DamageActType", definition.get("actType", "Other")))
		definition.critical = bool(damage_data.get("EnableCriticle", definition.get("critical", false)))
	if not _conditions(definition.get("conditions", []), bool(definition.get("all", true))):
		return
	if str(definition.get("summon", "")) not in ["", "0"]:
		var nested: Dictionary = _summon_index.get(str(definition.summon), {})
		if nested.is_empty():
			_report("Missing nested summon " + str(definition.summon))
		else:
			_schedule(nested.hit, float(event.at), str(event.action), int(event.slot), float(event.get("offset", 0)), str(definition.summon), event.get("origin", {}), str(event.get("target_key", "")))
	if int(definition.get("damageId", 0)) <= 0:
		var payload = JSON.parse_string(str(definition.get("raw", "{}")))
		if not payload is Dictionary: return
		var entity: Dictionary = payload.get("EntityProperty", {})
		var ending: Dictionary = entity.get("AddSummonUnitDefOnEnd", {})
		var end_summon := str(ending.get("AddSummonUnitId", ""))
		var has_end_summon := end_summon not in ["", "0", "-1"]
		var has_visual := _entity_has_presentation(entity)
		if payload.get("EntityType", "") != "EET_Physical" and not has_end_summon and not has_visual: return
		# Visual and ending-summon carriers must not create damage or contact callbacks.
		definition["carrier_only"] = (has_end_summon or has_visual) and definition.get("targetBuffs", []).is_empty() and definition.get("ownerBuffs", []).is_empty()
		definition.attribute = "None"
		definition.element = "None"
		definition.multiplier = 0.0
		definition.fixedDamage = 0.0
		definition.critical = false
	if definition.get("attribute") == "Unknown":
		_report("Missing damage " + str(int(definition.damageId)))
		return
	var basis = max_health if definition.get("attribute") == "MaxHp" else effective_attack_power()
	if not ["FinalAtk", "None", "Atk", "MaxHp", "FinalDef", "CurHp", "LostHpValue", "LastSecTotalBeDamage"].has(definition.get("attribute")):
		_report("Damage attribute reconstructed as attack: " + str(definition.get("attribute")))
	var critical_rate = float(fighter.get("critRate", 0)) + attribute("CriticalRate") / 1000.0
	var critical_roll = _random() if bool(definition.get("critical", false)) and not fighter.is_empty() else 1.0
	var critical = bool(definition.get("critical", false)) and not fighter.is_empty() and critical_roll < critical_rate
	var rate_keys = ["NormalAtkDamageRate", "DodgeAtkDamageRate", "SubSkillDamageRate", "MainSkillDamageRate", "SpecialAtkDamageRate"]
	var value = maxf(0.0, basis * float(definition.get("multiplier", 0)) + float(definition.get("fixedDamage", 0)))
	if not damage_data.is_empty():
		value = maxf(0.0, _damage_value(damage_data, effective_attack_power()))
	var critical_multi = float(fighter.get("critMultiplier", 1.5)) + attribute("CriticalMulti") / 1000.0
	var damage_rate_key: String = "MonsterPartnerDamageRate" if int(event.slot) in [5, 6] else rate_keys[clampi(int(event.slot), 0, 4)]
	value *= 1.0 + (attribute(damage_rate_key) + attribute("AllElementDamageRate") + attribute(str(definition.get("element", "")) + "DamageRate")) / 1000.0
	value *= _damage_multiplier(str(definition.get("actType", "")))
	_emission_sequence += 1
	var emitted := {"definition": definition, "action": event.action, "slot": event.slot, "sequence": event.sequence, "emission": _emission_sequence, "emit_index": int(event.get("emit_index", 0)), "damage": value * (critical_multi if critical else 1.0), "uncritical_damage": value, "critical_rate": critical_rate, "critical_multi": critical_multi, "critical_roll": critical_roll, "critical": critical, "forward_offset": float(event.get("offset", 0)), "projectile": bool(definition.get("projectile", false)), "summon_id": event.get("summon_id", ""), "origin": event.get("origin", {}), "target_key": event.get("target_key", ""), "source": self}
	var raw: Dictionary = _read_raw_json(str(definition.get("raw", "{}")))
	if raw.get("EmitType", "") == "EET_MultiPoint":
		var points: Array = raw.get("EmitProperty", {}).get("PointData", [])
		var index := int(event.get("emit_index", 0))
		if index >= 0 and index < points.size():
			var random_offset: Dictionary = points[index].get("RandomOffset", {})
			if random_offset.values().any(func(component): return not is_zero_approx(float(component))):
				# Native CalcStartPosition scales Random.onUnitSphere in world axes.
				var y := _random() * 2.0 - 1.0
				var angle := _random() * TAU
				var radius := sqrt(maxf(0.0, 1.0 - y * y))
				emitted["emit_random_offset"] = [cos(angle) * radius * float(random_offset.get("x", 0)), y * float(random_offset.get("y", 0)), sin(angle) * radius * float(random_offset.get("z", 0))]
	_emit_event("hit", emitted)

func _entity_has_presentation(entity: Dictionary) -> bool:
	for key in ["EffectTriggerDef", "EffectDelayTriggerDef"]:
		var effect: Dictionary = entity.get(key, {})
		if not str(effect.get("EffectName", "")).is_empty() or not str(effect.get("InitSound", "")).is_empty(): return true
	return not str(entity.get("ModlePrefab", "")).is_empty() or not str(entity.get("CreateSound", "")).is_empty()

func _spawn_summon(id: String, at: float, action_name: String, slot: int, offset: float = 0.0, depth: int = 0, origin: Dictionary = {}, target_key: String = "") -> void:
	if depth > 8:
		_report("Summon recursion exceeds 8: " + id)
		return
	for entry in statuses.values():
		var definition: Dictionary = _buff_index.get(entry.id, {})
		if definition.get("type") == "EBT_SummonUnitModify" and definition.get("raw_data", {}).get("SummonUnitIdList", []).has(id):
			id = str(_settings(definition).get("ModifyTargetSummonUnitToOtherSummonUnitId", id))
	var summon: Dictionary = _summon_index.get(id, {})
	if summon.is_empty():
		_report("Missing summon " + id)
		return
	summon = _effective_summon_definition(summon)
	var motion: Dictionary = summon.get("raw_data", {}).get("MotionAnimatorProperty", {})
	var lifetime_key = "LastingTime" if str(summon.get("raw_data", {}).get("MotionAnimatorType", "")) == "EMAT_RotateOwner" else "MaxLifetime"
	var context_key = "LastingTimePropertyContextAdd" if lifetime_key == "LastingTime" else "PropertyContextAdd"
	var lifetime_add = _property_context_total(str(motion.get(context_key, "")))
	if not is_zero_approx(lifetime_add) and motion.has(lifetime_key):
		# Context values are milliseconds, while line-motion MaxLifetime is seconds.
		summon = summon.duplicate(true)
		motion = summon.raw_data.MotionAnimatorProperty
		motion[lifetime_key] = maxf(0.0, float(motion[lifetime_key]) + lifetime_add / (1000.0 if lifetime_key == "MaxLifetime" else 1.0))
		summon.hit.lifetime = float(motion[lifetime_key]) / (1000.0 if lifetime_key == "LastingTime" else 1.0)
		var hit_raw = JSON.parse_string(str(summon.hit.get("raw", "{}")))
		if hit_raw is Dictionary:
			hit_raw["MotionAnimatorProperty"] = motion.duplicate(true)
			summon.hit.raw = JSON.stringify(hit_raw)
	origin = origin.duplicate(true)
	_emission_sequence += 1
	origin["_summon_token"] = "%s:%d" % [actor_key, _emission_sequence]
	_emit_event("summon", {"id": id, "definition": summon, "lifetime": float(summon.get("lifetime", 0)), "forward_offset": offset, "origin": origin, "target_key": target_key, "action": action_name, "slot": slot, "sequence": _cast_sequence})
	notify_gameplay("summon", {"id": id})
	var raw: Dictionary = summon.get("raw_data", {})
	_apply_raw_buff(raw.get("BuffTrigger_Caster", {}), effective_attack_power(), depth + 1)
	var phased_funnel = summon.get("type", "") == "ESUT_Funnel" and raw.get("TriggerBulletType", "") == "OnDurationTimeAuto" and (float(raw.get("FirstTriggerDelayTime", 0)) > 0 or float(raw.get("TriggerDelayTime", 0)) > 0 or not str(raw.get("TriggerEffectName_NoDelay", "")).is_empty() or not str(raw.get("TriggerEffectName_Delay", "")).is_empty())
	var ending_id := str(raw.get("EntityProperty", {}).get("AddSummonUnitDefOnEnd", {}).get("AddSummonUnitId", ""))
	var ending_carrier := ending_id not in ["", "0", "-1"]
	if int(summon.get("hit", {}).get("damageId", 0)) > 0 or phased_funnel or ending_carrier or (summon.get("type", "") == "ESUT_Funnel" and raw.get("EntityType", "") == "EET_Physical"):
		var summon_hit: Dictionary = summon.hit
		if summon.get("type", "") == "ESUT_Funnel":
			# Funnel emit intervals in the APK are already seconds; the legacy import divided them again.
			summon_hit = summon_hit.duplicate()
			summon_hit.interval = float(raw.get("EmitProperty", {}).get("Interval", summon_hit.get("interval", 0)))
		var interval = maxf(0.05, float(summon.get("interval", 1)))
		var repeats = clampi(int(ceil(float(summon.get("lifetime", interval)) / interval)), 1, 100)
		for index in range(repeats):
			var emission_at = at + index * interval
			var emission_offset = 0.0 if origin.has("InitPosOffset") else offset
			if phased_funnel:
				_pending.append({"at": emission_at + maxf(0, float(raw.get("FirstTriggerDelayTime", 0))), "sequence": _cast_sequence, "action": action_name, "slot": slot, "funnel_trigger": {"id": id, "definition": raw, "hit": summon_hit}, "origin": origin.duplicate(true), "target_key": target_key, "offset": emission_offset, "action_timeline": false})
			else:
				_schedule(summon_hit, emission_at, action_name, slot, emission_offset, id, origin, target_key)
	elif str(summon.get("type", "")) == "ESUT_PickupableItem":
		_emit_event("pickup_spawn", {"id": id, "buff": raw.get("BuffTrigger_Picker", {}), "radius": raw.get("PickUpRange", 2), "lifetime": summon.get("lifetime", 20), "origin": origin, "target_key": target_key})
	elif str(summon.get("type", "")) != "ESUT_Funnel":
		_report("Summon behavior requires world adapter: %s %s" % [id, summon.get("type", "")])

func _trigger_funnel(event: Dictionary) -> void:
	var funnel: Dictionary = event.funnel_trigger
	var raw: Dictionary = funnel.definition
	_emit_summon_trigger_phase(event, funnel, "NoDelay")
	var emission = event.duplicate()
	emission.erase("funnel_trigger")
	emission["funnel_emit"] = funnel
	emission.at = float(event.at) + maxf(0, float(raw.get("TriggerDelayTime", 0)))
	if float(emission.at) <= _clock + 0.0000001:
		_emit_funnel(emission)
	else:
		_pending.append(emission)

func _emit_funnel(event: Dictionary) -> void:
	var funnel: Dictionary = event.funnel_emit
	_emit_summon_trigger_phase(event, funnel, "Delay")
	_schedule(funnel.hit, float(event.at), str(event.action), int(event.slot), float(event.get("offset", 0)), str(funnel.id), event.get("origin", {}), str(event.get("target_key", "")))

func _emit_summon_trigger_phase(event: Dictionary, funnel: Dictionary, phase: String) -> void:
	var raw: Dictionary = funnel.definition
	if str(raw.get("TriggerEffectName_" + phase, "")).is_empty(): return
	_emit_event("summon_trigger_effect", {"id": str(funnel.id), "definition": raw.duplicate(true), "phase": phase, "origin": event.get("origin", {}).duplicate(true), "target_key": str(event.get("target_key", "")), "forward_offset": float(event.get("offset", 0)), "action": str(event.action), "sequence": int(event.sequence), "slot": int(event.slot)})

func _tick_statuses(delta: float) -> void:
	for entry in statuses.values().duplicate():
		var definition: Dictionary = _buff_index.get(entry.id, {})
		var source_id = str(definition.get("syncSource", ""))
		if not source_id.is_empty():
			var source: Dictionary = statuses.get(source_id, {})
			var total = float(source.get("time", 0)) + maxi(0, int(source.get("layers", 0)) - 1) * float(_buff_index.get(source_id, {}).get("duration", 0)) if not source.is_empty() else 0.0
			for id in definition.get("syncTargets", []):
				if statuses.has(str(id)):
					statuses[str(id)].time = maxf(0.0, total)
	var expired: Array = []
	for id in statuses.keys():
		if not statuses.has(id):
			continue
		var entry: Dictionary = statuses[id]
		var definition: Dictionary = _buff_index.get(id, {})
		var expiry_layers = int(definition.get("expiryLayers", definition.get("raw_data", {}).get("OnceReduceNumCount", 0)))
		var active = delta if float(entry.time) < 0 or expiry_layers > 0 else minf(delta, float(entry.time))
		entry.modifier_cooldown = maxf(0.0, float(entry.modifier_cooldown) - active)
		entry.raw_cooldown = maxf(0.0, float(entry.get("raw_cooldown", 0)) - active)
		if float(entry.raw_cooldown) <= 0.000001: entry.raw_cooldown = 0.0
		for index in range(definition.get("triggers", []).size()):
			if float(entry.trigger_delays[index]) >= 0:
				entry.trigger_delays[index] = float(entry.trigger_delays[index]) - active
				if float(entry.trigger_delays[index]) <= 0:
					entry.trigger_delays[index] = -1.0
					_fire(entry, index, float(entry.attack), 0, true)
			var rule: Dictionary = definition.triggers[index]
			var periodic = not bool(rule.get("onHit", false)) and rule.get("addedBuffs", []).is_empty()
			var cooldown = float(entry.trigger_cooldowns[index]) - active
			entry.trigger_cooldowns[index] = maxf(0.0, cooldown)
			if float(entry.trigger_cooldowns[index]) <= 0.000001: entry.trigger_cooldowns[index] = 0.0
			if int(entry.layers) > 0 and periodic and float(entry.trigger_cooldowns[index]) <= 0 and _requirements(rule):
				_fire(entry, index, float(entry.attack), 0)
				# Preserve substep overshoot so periodic boss recovery does not drift by FPS.
				entry.trigger_cooldowns[index] = maxf(0.0, float(entry.trigger_cooldowns[index]) + minf(0.0, cooldown))
		if definition.get("type") == "EBT_SpecialTriggerRangeDamage" and bool(definition.get("selfOnlyDamage", false)):
			entry.tick = float(entry.tick) - active
			while float(entry.tick) <= 0:
				var value = (float(entry.attack) * float(definition.get("multiplier", 0)) + float(definition.get("fixedDamage", 0))) * int(entry.layers)
				var previous = health
				var caster = _caster_for(str(id))
				_status_range_visual(definition, caster)
				if caster != null and caster != self:
					var area = _status_area(definition, caster)
					_emission_sequence += 1
					var status_hit = {"source": caster, "sequence": -1, "emission": "%s:%s:%d" % [actor_key, id, _emission_sequence], "damage": float(area.get("damage", value)) * int(entry.layers), "definition": {"damageId": area.get("damageId", 0), "actType": area.get("actType", "Buff"), "element": area.get("element", "None"), "critical": area.get("critical", false), "targetBuffs": area.get("targetBuffs", [])}, "continuous": true, "attack_collision": false}
					receive(status_hit, float(entry.attack))
				else:
					health = maxf(0.0, health - value)
					_apply_health_locks(previous)
				var settled = maxf(0.0, previous - health)
				_emit_event("status_damage", {"id": id, "damage": settled, "definition": definition.get("raw_data", {})})
				if settled > 0 and (caster == null or caster == self): _emission_sequence += 1
				var caster_key = caster.actor_key if caster != null else str(entry.get("caster_key", actor_key))
				var status_impact = {"source_key": caster_key, "receiver_key": actor_key, "id": id, "emission": _emission_sequence, "continuous": true, "resolved_damage": settled, "resolved_absorbed": 0.0, "resolved_accepted": true}
				if settled > 0 and (caster == null or caster == self):
					impact_confirmed.emit(status_impact)
					_emit_event("impact_confirmed", status_impact)
				entry.tick = float(entry.tick) + maxf(0.05, float(definition.get("interval", 1)))
		elif definition.get("type") == "EBT_SpecialTriggerRangeDamage" and not _status_area(definition, _caster_for(str(id))).is_empty():
			entry.tick = float(entry.tick) - active
			while float(entry.tick) <= 0.000001:
				var caster = _caster_for(str(id))
				var area = _status_area(definition, caster)
				_status_range_visual(definition, caster)
				var value = maxf(0.0, float(area.get("damage", (float(entry.attack) if area.get("attribute") == "FinalAtk" else 0.0) * float(area.get("multiplier", 0)) + float(area.get("fixedDamage", 0))))) * int(entry.layers)
				_emission_sequence += 1
				_emit_event("area", {"id": id, "host_key": actor_key, "definition": area, "layers": entry.layers, "caster_attack": entry.attack, "damage": value, "emission": _emission_sequence, "source": caster if caster != null else self, "continuous": float(definition.get("interval", 0)) > 0, "action": current_action, "slot": _current_slot})
				entry.tick = float(entry.tick) + (float(definition.interval) if float(definition.get("interval", 0)) > 0 else 1.0e20)
				if not statuses.has(id):
					break
		if float(entry.time) >= 0:
			entry.time = float(entry.time) - delta
			if expiry_layers > 0 and float(definition.get("duration", 0)) > 0:
				while float(entry.time) <= 0.000001 and int(entry.layers) > 0:
					entry.layers = maxi(0, int(entry.layers) - expiry_layers)
					if int(entry.layers) > 0:
						entry.time = float(entry.time) + float(definition.duration)
			if float(entry.time) <= 0.000001:
				expired.append(id)
	# Raw conditions must see their final active tick before expiry disposes them.
	notify_gameplay("tick", {"delta": delta})
	for id in expired:
		if not statuses.has(id) or float(statuses[id].time) > 0.000001:
			continue
		var entry: Dictionary = statuses[id]
		var definition: Dictionary = _buff_index.get(id, {})
		statuses.erase(id)
		_dispose_status(definition, entry)
	health = minf(health, max_health)

func _fire(entry: Dictionary, index: int, caster_attack: float, depth: int, delayed: bool = false) -> void:
	if depth > 16:
		_report("Resource trigger recursion limit: " + str(entry.id))
		return
	var definition: Dictionary = _buff_index.get(entry.id, {})
	var rule: Dictionary = definition.get("triggers", [])[index]
	entry.trigger_cooldowns[index] = maxf(0.001, float(rule.get("cooldown", 0)))
	if float(rule.get("delay", 0)) > 0 and not delayed:
		if float(entry.trigger_delays[index]) < 0:
			entry.trigger_delays[index] = float(rule.delay)
		return
	var source_layers = buff_layers(str(rule.get("sourceBuff", "")))
	for old in rule.get("remove", []):
		statuses.erase(str(old))
	for addition in rule.get("add", []):
		var layers = source_layers if not str(rule.get("sourceBuff", "")).is_empty() else int(addition.layers) * (int(entry.layers) if bool(rule.get("multiplySelfLayers", false)) else 1)
		bind_buff_caster(str(addition.id), _caster_for(str(entry.id)))
		add_buff(str(addition.id), layers, caster_attack, depth + 1)
	if int(rule.get("reduceSelf", 0)) > 0:
		entry.layers = maxi(0, int(entry.layers) - int(rule.reduceSelf))
		if int(entry.layers) == 0:
			statuses.erase(str(entry.id))
			_dispose_status(definition, entry, depth + 1)

func _confirm_status_hit(hit: Dictionary) -> void:
	var hit_def: Dictionary = hit.get("definition", {})
	for entry in statuses.values().duplicate():
		var definition: Dictionary = _buff_index.get(entry.id, {})
		if int(entry.layers) <= 0:
			continue
		for index in range(definition.get("triggers", []).size()):
			var rule: Dictionary = definition.triggers[index]
			if not bool(rule.get("onHit", false)) or float(entry.trigger_cooldowns[index]) > 0 or not _requirements(rule):
				continue
			if not _rule_hit_matches(rule, hit_def):
				continue
			_fire(entry, index, effective_attack_power(), 0)

func _target_hit(hit: Dictionary, target: DungeonCombat, caster_attack: float) -> float:
	var rate = 0.0
	for entry in statuses.values().duplicate():
		var definition: Dictionary = _buff_index.get(entry.id, {})
		var modifier = definition.get("targetModifier")
		if not modifier is Dictionary or int(entry.layers) <= 0 or float(entry.modifier_cooldown) > 0:
			continue
		if not _rule_hit_matches(modifier, hit.get("definition", {})):
			continue
		if not str(modifier.get("ownerBuff", "")).is_empty() and buff_layers(str(modifier.ownerBuff)) < int(modifier.get("ownerLayers", 1)):
			continue
		if not str(modifier.get("targetBuff", "")).is_empty() and target.buff_layers(str(modifier.targetBuff)) < int(modifier.get("targetLayers", 1)):
			continue
		rate += float(modifier.get("damageRate", 0))
		entry.modifier_cooldown = float(modifier.get("cooldown", 0))
		if not str(modifier.get("addTarget", "")).is_empty():
			target.add_buff(str(modifier.addTarget), int(modifier.get("addLayers", 1)), caster_attack)
	return 1.0 + rate

func _apply_combat_modifiers(context: Dictionary, target: DungeonCombat, source: DungeonCombat, receiver_side: bool) -> void:
	var hit: Dictionary = context.hit
	var hit_def: Dictionary = hit.get("definition", {})
	for entry in statuses.values().duplicate():
		var definition: Dictionary = _buff_index.get(entry.id, {})
		if definition.get("type") != "EBT_ModifyCombatResult" or int(entry.layers) <= 0 or float(entry.modifier_cooldown) > 0:
			continue
		# These seven definitions already have their exact recovered trigger representation.
		if not definition.get("triggers", []).is_empty() or float(definition.get("damageRate", 0)) != 0:
			continue
		var settings = _settings(definition, source)
		if settings.is_empty():
			continue
		if receiver_side and not bool(settings.get("EnableAttackeeSelfCheck", false)):
			continue
		if not receiver_side and not bool(settings.get("EnableAttackerSelfCheck", true)):
			continue
		if not _modifier_matches(settings, context, target, source):
			continue
		var key = str(hit.get("sequence", 0))
		match str(settings.get("MaxModifyCounterType", "DamageInstance")):
			"AttackDef":
				var token = str(hit.get("origin", {}).get("_summon_token", ""))
				if not token.is_empty(): key = token
				key += ":" + str(hit_def.get("damageId", 0))
			"DamageInstance": key += ":" + str(hit.get("emission", 0))
		if str(entry.get("modifier_key", "")) != key:
			entry.modifier_key = key
			entry.modifier_count = 0
		var limit = int(settings.get("MaxModifyCount", -1))
		if limit >= 0 and int(entry.get("modifier_count", 0)) >= limit:
			continue
		if float(settings.get("TriggerRandom", 100)) < 100 and _random() * 100.0 >= float(settings.get("TriggerRandom", 100)):
			continue
		entry.modifier_count = int(entry.get("modifier_count", 0)) + 1
		entry.modifier_cooldown = maxf(0.0, float(settings.get("ModifyCd", 0)) / 1000.0)
		var cooldown_property = str(settings.get("ModifyCdPropertyContext", ""))
		if not cooldown_property.is_empty():
			if custom_properties.has(cooldown_property):
				entry.modifier_cooldown = maxf(0.0, float(entry.modifier_cooldown) + float(custom_properties[cooldown_property]) / 1000.0)
			else:
				_report("Modifier cooldown context unbound: %s %s" % [entry.id, cooldown_property])
		var layers = int(entry.layers)
		var owner_multiplier = str(settings.get("ModifyDamageMultiLayer_AttackerBuffId", ""))
		var target_multiplier = str(settings.get("ModifyDamageMultiLayer_AttackeeBuffId", ""))
		if not owner_multiplier.is_empty():
			layers *= source.buff_layers(owner_multiplier) if source != null else 0
		if not target_multiplier.is_empty():
			layers *= target.buff_layers(target_multiplier)
		if bool(settings.get("EnableDamageCaculateModify", false)):
			_modifier_value(context, str(settings.get("ModifyDamageCaculateType", "None")), float(settings.get("ModifyDamageCaculateValue", 0)) * layers, target)
			_modifier_value(context, str(settings.get("ModifyDamageCaculateType2", "None")), float(settings.get("ModifyDamageCaculateValue2", 0)) * layers, target)
		if bool(settings.get("EnableDamageExtraCaculateModify", false)):
			var basis_owner = target if bool(settings.get("EnableDamageExtraAttackee", false)) else source
			var basis = basis_owner.stat_value(str(settings.get("ModifyDamageAddExtraType", "None"))) if basis_owner != null else 0.0
			var extra = basis * float(settings.get("ModifyDamageAddExtraValue", 0)) / 1000.0 * layers
			_modifier_value(context, str(settings.get("ModifyDamageAddExtraCaculateType", "None")), extra, target)
		if bool(settings.get("EnableDamageActModify", false)):
			context["act_type"] = str(settings.get("ModifyDamageActType", hit_def.get("actType", "")))
		if bool(settings.get("EnableDamageTypeModify", false)):
			context["element"] = str(settings.get("ModifyDamageType", hit_def.get("element", "")))
		if int(settings.get("IsReplaceDamageCanCritiProperty", 0)) != 0:
			context.can_critical = int(settings.IsReplaceDamageCanCritiProperty) > 0
		if bool(settings.get("EnableDamageDefReplace", false)):
			_report("Damage definition replacement needs original definition map: " + str(entry.id))
		var caster_attack = source.effective_attack_power() if source != null else float(entry.attack)
		if source != null:
			source._apply_raw_buff(settings.get("AddBuff_ToAttacker", {}), caster_attack, 0)
		target._apply_raw_buff(settings.get("AddBuff_ToAttackee", {}), caster_attack, 0, source)
		var summon: Dictionary = settings.get("AddSummonUnitDef_OnAttackeePos", {})
		if not str(summon.get("AddSummonUnitId", "")).is_empty():
			summon = summon.duplicate(true)
			summon["OriginType"] = "targetPosAndSelfDir"
			var summoner = source if source != null else self
			for index in range(clampi(int(summon.get("AddSummonUnitQuantity", 1)), 1, 30)):
				summoner._spawn_summon(str(summon.AddSummonUnitId), summoner._clock, str(hit.get("action", "")), int(hit.get("slot", 0)), float(summon.get("InitPosOffset", {}).get("z", 0)), 0, summon, target.actor_key)
		var message: Dictionary = settings.get("OnTriggerSendMsg", {})
		if not str(message.get("MsgName", "")).is_empty():
			_emit_event("message", {"definition": message})
		var effect: Dictionary = settings.get("TriggerShowEffectData", {})
		if not effect.is_empty():
			_emit_event("buff_effect", {"id": entry.id, "definition": effect})
		var reduce = int(settings.get("ModifyCDReduceLayer", 0))
		if reduce > 0:
			entry.layers = maxi(0, int(entry.layers) - reduce)
			if int(entry.layers) == 0:
				statuses.erase(str(entry.id))
		if float(settings.get("ModifySuccessDisposeTime", -1)) >= 0:
			entry.time = float(settings.ModifySuccessDisposeTime) / 1000.0

func _modifier_matches(settings: Dictionary, context: Dictionary, target: DungeonCombat, source: DungeonCombat) -> bool:
	var hit: Dictionary = context.hit
	var definition: Dictionary = hit.get("definition", {})
	if bool(settings.get("EnableCheckDamageDefId", false)):
		var ids: Array = []
		for field in ["CheckDamageDefId", "CheckDamageDefId2"]:
			if int(settings.get(field, 0)) > 0: ids.append(int(settings[field]))
		for id in str(settings.get("CheckDamageDefId3", "")).split("|", false):
			if int(id) > 0: ids.append(int(id))
		if not ids.has(int(definition.get("damageId", 0))):
			return false
	if bool(settings.get("EnableCheckDamageActType", false)):
		var types: Array = []
		for index in range(1, 6):
			types.append(str(settings.get("CheckDamageActType" + str(index), "")))
		if not types.has(str(definition.get("actType", ""))):
			return false
	if bool(settings.get("EnableCheckDamageType", false)) and settings.get("CheckDamageType") != definition.get("element"):
		return false
	if bool(settings.get("EnableCheckAttackeeHpRatio", false)) and not _compare(target.health / target.max_health * 1000.0, float(settings.get("CheckAttackeeHpRatio", 0)), str(settings.get("AttackeeHpRatioCompareCondition", "ECT_LessEqual"))):
		return false
	if bool(settings.get("EnableCheckMonsterAttackeeType", false)) and target.enemy.get("rank", "") != settings.get("MonsterAttackeeTypeCompareCondition", "Normal"):
		return false
	if bool(settings.get("EnableCheckAttackeeSheildValue", false)) and not _compare(target.shield, float(settings.get("CheckSheildValue", 0)), str(settings.get("AttackeeSheildValueCompareCondition", "ECT_Equal"))):
		return false
	if bool(settings.get("EnableCheckAttackerBuff", false)):
		var count = source.buff_layers(str(settings.get("CheckAttackerBuffId", ""))) if source != null else 0
		var passed = _compare(float(count), float(settings.get("CheckAttackerBuffLayer", 1)), str(settings.get("CheckAttackerBuffLayerCompareCondition", "ECT_GreaterEqual"))) if settings.has("CheckAttackerBuffLayerCompareCondition") else count > 0
		if passed != bool(settings.get("CheckAttackerBuffHave", true)):
			return false
	if bool(settings.get("EnableCheckAttackeeBuff", false)):
		var count = target.buff_layers(str(settings.get("CheckAttackeeBuffId", "")))
		var passed = _compare(float(count), float(settings.get("CheckAttackeeBuffLayer", 1)), str(settings.get("CheckAttackeeBuffLayerCompareCondition", "ECT_GreaterEqual"))) if settings.has("CheckAttackeeBuffLayerCompareCondition") else count > 0
		if passed != bool(settings.get("CheckAttackeeBuffHave", true)):
			return false
	if bool(settings.get("EnableCheckAttackeeDistance", false)):
		if not hit.has("distance"):
			_report("Hit distance requires world adapter")
			return false
		if not _compare(float(hit.distance), float(settings.get("CheckAttackeeDistanceValue", 0)), str(settings.get("CheckAttackeeDistanceCompareType", "ECT_Equal"))):
			return false
	if bool(settings.get("EnableCheckAttackerAttribute", false)):
		if source == null or not _compare(source.stat_value(str(settings.get("AttackerAttributeType", "None"))), float(settings.get("CheckAttackerAttributeValue", 0)), str(settings.get("AttackerAttributeCompareCondition", "ECT_Equal"))):
			return false
	if bool(settings.get("EnableCheckAttackeeAttribute", false)) and not _compare(target.stat_value(str(settings.get("AttackeeAttributeType", "None"))), float(settings.get("CheckAttackeeAttributeValue", 0)), str(settings.get("AttackeeAttributeCompareCondition", "ECT_Equal"))):
		return false
	return int(settings.get("IsCritical", 0)) != 1 or bool(hit.get("critical", false))

func _modifier_value(context: Dictionary, type: String, value: float, target: DungeonCombat) -> void:
	match type:
		"None": pass
		"DamageRateAdd", "FinalDamageRateAdd", "DamageDefAddRate": context.damage_rate = float(context.damage_rate) + value / 1000.0
		"DefensePenetration": context.defense_penetration = float(context.defense_penetration) + value / 1000.0
		"CtriticalRate", "CriticalRate": context.critical_rate = float(context.critical_rate) + value / 1000.0
		"CriticalMulti": context.critical_multi = float(context.critical_multi) + value / 1000.0
		"DamageFixAdd", "ExtraDamageFixAdd": context.fixed_add = float(context.fixed_add) + value
		"FinalDamageFixAdd": context.final_add = float(context.final_add) + value
		"FinalDamageMaxLimitInAtkeeMaxHP": context.max_damage = minf(float(context.max_damage), target.max_health * value / 1000.0)
		"FinalDamageMinLimitInAtkeeMaxHP": context.min_damage = maxf(float(context.min_damage), target.max_health * value / 1000.0)
		_: _report("Unsupported damage calculation: " + type)

func stat_value(name: String) -> float:
	match name:
		"None": return 0.0
		"FinalAtk", "Atk": return effective_attack_power()
		"FinalDef", "Def": return (defense + attribute("BaseDef") + attribute("DefAddFixed")) * (1.0 + attribute("DefAddRate") / 1000.0)
		"MaxHp": return max_health
		"CurHp", "Hp": return health
		"LostHpValue": return maxf(0.0, max_health - health)
		"LastSecTotalBeDamage":
			var total = 0.0
			for item in custom_properties.get("_recent_damage", []):
				if float(item.at) >= _clock - 1.0:
					total += float(item.damage)
			return total
		"CurSheild", "Shield", "CurShield": return shield
		"CurArmor", "Armor": return armor
		"SkillActive1CurChargeValue": return minf(float(energy[2]), skill_capacity(2))
		"SkillActive2CurChargeValue": return minf(float(energy[3]), skill_capacity(3))
		"SkillActive1CostSp": return skill_cost(2)
		"SkillActive2CostSp": return skill_cost(3)
		"SkillActive1MaxSp": return skill_capacity(2)
		"SkillActive2MaxSp": return skill_capacity(3)
		"SkillActive1CurCanUseTimes", "SkillActive2CurCanUseTimes":
			return skill_available_uses(2 if name == "SkillActive1CurCanUseTimes" else 3)
	return attribute(name)

func notify_gameplay(kind: String, payload: Dictionary = {}) -> void:
	if _condition_depth > 16:
		_report("Condition event recursion exceeds 16")
		return
	_condition_depth += 1
	if kind == "cause_damage":
		custom_properties["ComboCount"] = int(custom_properties.get("ComboCount", 0)) + 1
	for entry in statuses.values().duplicate():
		var definition: Dictionary = _buff_index.get(entry.id, {})
		if definition.get("type") != "EBT_ConditionBuff" or not definition.get("triggers", []).is_empty() or int(entry.layers) <= 0 or float(entry.get("raw_cooldown", 0)) > 0 or bool(entry.get("raw_triggering", false)) or bool(entry.get("raw_instant_completed", false)):
			continue
		var raw: Dictionary = definition.get("raw_data", {})
		var conditions: Array = _spirit_conditions(raw.get("Conditions", []), _caster_for(str(entry.id)))
		var passed = true
		if not entry.has("condition_counters"):
			entry.condition_counters = {}
		for index in range(conditions.size()):
			if not _raw_condition(entry, conditions[index], kind, payload, str(index)):
				passed = false
		if not passed:
			continue
		var settings = _settings(definition, _caster_for(str(entry.id)))
		if settings.is_empty():
			continue
		var cooldown = 0.0
		for condition in conditions:
			if condition.get("ConditionType") == "ECT_CheckBuffCD":
				cooldown = maxf(cooldown, float(condition.get("ColdTime", 0)) / 1000.0)
			elif condition.get("ConditionType") == "ECT_CheckBuffCauseDamage":
				cooldown = maxf(cooldown, float(condition.get("CheckSuccessIntervalTime", 0)) / 1000.0)
		entry.raw_cooldown = cooldown
		entry.condition_counters = {}
		entry.raw_triggering = true
		if float(raw.get("TriggerRandom", 100)) < 100 and _random() * 100.0 >= float(raw.get("TriggerRandom", 100)):
			var failed = str(raw.get("FailedTriggerBuffId", ""))
			if not failed.is_empty():
				add_buff(failed, 1, float(entry.attack), _condition_depth)
			entry.raw_triggering = false
			continue
		var effect = {"id": entry.id, "layers": int(entry.layers), "attack": float(entry.attack), "caster_actor": entry.get("caster_actor", character_id if character_id > 0 else enemy_id), "caster_key": entry.get("caster_key", actor_key), "settings": settings.duplicate(true)}
		if float(definition.get("duration", -1)) == 0: entry.raw_instant_completed = true
		var delay = float(raw.get("AddTimeDelay", 0)) / 1000.0
		if delay > 0:
			_pending.append({"at": _clock + delay, "sequence": -1, "condition_effect": effect})
		else:
			_apply_condition_effect(effect)
		var reduce = int(raw.get("TriggerSuccessReduceLayerCount", 0))
		if reduce > 0:
			entry.layers = maxi(0, int(entry.layers) - reduce)
			if int(entry.layers) == 0:
				statuses.erase(str(entry.id))
				_dispose_status(definition, entry, _condition_depth)
		entry.raw_triggering = false
	_condition_depth -= 1

func _raw_condition(entry: Dictionary, condition: Dictionary, kind: String, payload: Dictionary, key: String) -> bool:
	var type = str(condition.get("ConditionType", ""))
	var counter = float(entry.condition_counters.get(key, 0))
	match type:
		"ECT_None", "ECT_CheckBuffCD":
			return true
		"ECT_CheckBuffExist":
			var buff_id = str(condition.get("BuffId", ""))
			if not bool(condition.get("CheckExist", true)): return not statuses.has(buff_id)
			return statuses.has(buff_id) and _compare(float(buff_layers(buff_id)), float(condition.get("CheckLayerCount", 1)), str(condition.get("CompareType", "ECT_GreaterEqual")))
		"ECT_CheckBuffHP":
			return _compare(health / max_health * 1000.0, float(condition.get("CompareVal", 0)), str(condition.get("CompareType", "ECT_GreaterEqual")))
		"ECT_CheckBuffArmor":
			return _compare(armor, float(condition.get("CompareVal", 0)), str(condition.get("CompareType", "ECT_GreaterEqual")))
		"ECT_CheckHaveSheild":
			return (shield > 0) == bool(condition.get("CheckHave", true))
		"ECT_CheckBuffEnemyType":
			return (enemy.get("rank", "") == condition.get("EnemyType")) == bool(condition.get("MatchEqual", true))
		"ECT_CheckActionType":
			var when = str(condition.get("CheckTime", "Start"))
			if when == "Duration":
				if kind != "tick" or busy <= 0:
					return false
			elif kind != ("action_end" if when == "End" else "action_start"):
				return false
			var states: Array = condition.get("ActionStates", [])
			if states.is_empty():
				states = [condition.get("ActionState", "NorAtk")]
				if bool(condition.get("CheckMoreType", false)):
					states.append(condition.get("ActionState2", ""))
					states.append(condition.get("ActionState3", ""))
			var slot = int(payload.get("slot", _current_slot))
			var action_state = ["NorAtk", "Dodge", "SubSkill", "MainSkill", "SAtk"][clampi(slot, 0, 4)]
			if bool(condition.get("UseActionTypeCheck", true)) and not states.has(action_state) and not (slot == 1 and states.has("DodgeAtk")):
				return false
			if bool(condition.get("UseActionIdCheck", false)) and not condition.get("ActionIds", []).has(payload.get("action", current_action)):
				return false
			counter += 1
			entry.condition_counters[key] = counter
			return counter >= maxi(1, int(condition.get("ActionCount", 1)))
		"ECT_CheckBuffChangeLayer":
			if kind != "buff_add" or payload.get("id") != condition.get("BuffId"):
				return false
			counter += absf(float(payload.get("layers", 0)))
			entry.condition_counters[key] = counter
			return counter >= int(condition.get("CheckChangeLayerCount", 1))
		"ECT_CheckBuffAddBuff":
			if kind != "buff_add" or not condition.get("BuffIdList", []).has(payload.get("id")):
				return false
			counter += maxf(0.0, float(payload.get("layers", 0)))
			entry.condition_counters[key] = counter
			return counter >= int(condition.get("CheckChangeLayerCount", 1))
		"ECT_CheckBuffAddSummonUnit":
			if kind != "summon" or not condition.get("SummonIdList", []).has(payload.get("id")):
				return false
			counter += 1
			entry.condition_counters[key] = counter
			return counter >= int(condition.get("CheckCount", 1))
		"ECT_CheckBuffCauseDamage":
			if kind != "cause_damage" or not _raw_damage_condition(condition, payload):
				return false
			counter += float(payload.get("damage", 0)) if bool(condition.get("IsCheckTotalDamage", false)) else 1.0
			entry.condition_counters[key] = counter
			return counter >= float(condition.get("CheckSuccessTotalDamage", 0)) if bool(condition.get("IsCheckTotalDamage", false)) else counter >= maxi(1, int(condition.get("CheckSuccessCount", 1)))
		"ECT_CheckBeInjured":
			if kind != "injured" or not _raw_attacker_condition(condition, payload.get("attacker")):
				return false
			var mode = str(condition.get("CalculateBeDamageType", "SingleDamage"))
			var amount = float(payload.get("damage", 0))
			counter = amount if mode == "SingleDamage" else counter + (1.0 if mode == "TotalBeHitCount" else amount)
			entry.condition_counters[key] = counter
			var threshold = float(condition.get("CompareVal", 0)) if bool(condition.get("EnableCheckWithFixedValue", true)) else stat_value(str(condition.get("CompareType_Attribute", "MaxHp"))) * float(condition.get("CompareVal_Attribute", 0)) / 1000.0
			return _compare(counter, threshold, str(condition.get("CompareType", "ECT_GreaterEqual")))
		"ECT_CheckBuffKillMonster":
			if kind != "kill":
				return false
			var ranks: Array = [condition.get("CheckEnemyRateType1", "Normal"), condition.get("CheckEnemyRateType2", "Elite"), condition.get("CheckEnemyRateType3", "Boss")]
			if not ranks.has(payload.get("rank", "Normal")):
				return false
			if bool(condition.get("EnableCheckEnemyHaveBuff", false)):
				var target = payload.get("target")
				if not target is DungeonCombat:
					return false
				var passed = _compare(float(target.buff_layers(str(condition.get("CheckEnemyBuffId", "")))), float(condition.get("CheckEnemyBuffLayerCount", 1)), str(condition.get("CheckBuffLayerCondition", "ECT_GreaterEqual")))
				if passed != bool(condition.get("CheckEnemyBuffExist", true)):
					return false
			counter += 1
			entry.condition_counters[key] = counter
			return _compare(counter, float(condition.get("CompareVal", 1)), str(condition.get("CompareType", "ECT_GreaterEqual")))
		"ECT_CheckBuffDodgeSuccess":
			if kind != "dodge" or not _raw_attacker_condition(condition, payload.get("attacker")):
				return false
			if bool(condition.get("EnableCheckDodgeActionType", false)) and condition.get("CheckCanBeHurtType", "Dodge") != payload.get("dodge_type", "Dodge"):
				return false
			counter += 1
			entry.condition_counters[key] = counter
			return counter >= int(condition.get("CheckSuccessCount", 1))
		"ECT_CheckEnemyAround":
			if not custom_properties.get("EnemyDistances") is Array:
				_report("Enemy distance list requires world adapter: " + str(entry.id))
				return false
			var count = 0
			for distance in custom_properties.EnemyDistances:
				if float(distance) <= float(condition.get("CompareRange", 0)):
					count += 1
			return _compare(float(count), float(condition.get("CompareVal", 1)), str(condition.get("CompareType", "ECT_GreaterEqual")))
		"ECT_CheckPlayerMove":
			if kind != "move":
				return false
			if bool(condition.get("CheckMoveDistance", false)):
				counter += maxf(0.0, float(payload.get("distance", 0)))
				entry.condition_counters[key] = counter
				return counter >= float(condition.get("mCompareDistance", 0))
			if bool(payload.get("moving", false)) != bool(condition.get("CheckMove", true)):
				entry.condition_counters[key] = 0.0
				return false
			counter += float(payload.get("delta", 0)) * 1000.0
			entry.condition_counters[key] = counter
			return _compare(counter, float(condition.get("CompareVal", 0)), str(condition.get("CompareType", "ECT_GreaterEqual")))
		"ECT_CheckBuffRoleUnitAttribute":
			return _compare(stat_value(str(condition.get("AttributeType", "None"))), float(condition.get("CompareVal", 0)) + stat_value(str(condition.get("CompareTargetAttributeType", "None"))) * float(condition.get("CompareTargetAttributeRateVal", 0)) / 1000.0, str(condition.get("CompareType", "ECT_GreaterEqual")))
		"ECT_CheckBuffCombos":
			return _compare(float(custom_properties.get("ComboCount", 0)), float(condition.get("CompareVal", 0)), str(condition.get("CompareType", "ECT_GreaterEqual")))
		"ECT_CheckBuffRogueAttribute":
			if not custom_properties.get("RogueAttributes") is Dictionary:
				_report("Rogue attributes require system adapter: " + str(entry.id))
				return false
			return _compare(float(custom_properties.RogueAttributes.get(str(condition.get("AttributeType", "")), 0)), float(condition.get("CompareVal", 0)), str(condition.get("CompareType", "ECT_GreaterEqual")))
		"ECT_CheckBuffReceiveMsg":
			if kind != "message":
				return false
			if bool(condition.get("EnableCustomMsgCheck", false)):
				return payload.get("name", "") == condition.get("CustomMsgName", "")
			return payload.get("event_type", "") == condition.get("RogueTrigger", {}).get("RogueEventTriggerData", {}).get("EventType", "")
		"ECT_CheckBuffBePushCollision":
			return kind == "push_collision"
		"ECT_CheckBuffCauseHeal", "ECT_CheckBeHeal":
			return kind == "heal" and _compare(float(payload.get("amount", 0)), float(condition.get("CompareVal", 0)), str(condition.get("CompareType", "ECT_GreaterEqual")))
	_report("Unsupported raw condition: %s %s" % [entry.id, type])
	return false

func _raw_damage_condition(condition: Dictionary, payload: Dictionary) -> bool:
	var definition: Dictionary = payload.get("definition", {})
	if bool(condition.get("CheckDamageActType", false)):
		var types: Array = []
		for index in range(1, 6):
			types.append(condition.get("DamageActType" + str(index), ""))
		if not types.has(definition.get("actType", "")):
			return false
	if bool(condition.get("CheckDamageType", false)) and condition.get("DamageType") != definition.get("element"):
		return false
	if bool(condition.get("CheckDamageDefId", false)) and not str(condition.get("DamageDefId", "")).split("|", false).has(str(int(definition.get("damageId", 0)))):
		return false
	return int(condition.get("IsCritical", 0)) != 1 or bool(payload.get("critical", false))

func _raw_attacker_condition(condition: Dictionary, attacker: Variant) -> bool:
	if not bool(condition.get("CheckDamageAttackerType", false)):
		return true
	if not attacker is DungeonCombat:
		return false
	var is_match = (not attacker.enemy.is_empty()) if condition.get("DamageAttackerType") == "EUT_Monster" else not attacker.fighter.is_empty()
	return is_match == bool(condition.get("CheckIsOrNot", true))

func _apply_condition_effect(effect: Dictionary) -> void:
	var definition: Dictionary = _buff_index.get(effect.id, {})
	var settings: Dictionary = effect.settings
	var recipient: DungeonCombat = self
	if definition.get("raw_data", {}).get("EBuffAddTargetType") == "Caster":
		var caster = _caster_for(str(effect.id))
		if caster != null:
			recipient = caster
		elif str(effect.get("caster_key", actor_key)) != actor_key:
			_report("Transferred condition caster requires world binding: " + str(effect.id))
			return
	var layers = int(settings.get("BuffAddLayer", 1))
	if not str(settings.get("BuffScoureId", "")).is_empty():
		layers = buff_layers(str(settings.BuffScoureId))
	elif bool(settings.get("EnableAddBuffLayerMultiCBuffCurLayer", false)):
		layers *= int(effect.layers)
	for id in settings.get("DelBuffIDList", []):
		recipient.remove_buff(str(id))
	for id in settings.get("AddBuffIDList", []):
		if float(settings.get("BuffAddRandom", 100)) >= 100 or _random() * 100.0 < float(settings.get("BuffAddRandom", 100)):
			recipient.bind_buff_caster(str(id), _caster_for(str(effect.id)))
			recipient.add_buff(str(id), layers, float(effect.attack), _condition_depth)

func _rule_hit_matches(rule: Dictionary, hit_def: Dictionary) -> bool:
	if not rule.get("damageIds", []).is_empty() and not rule.damageIds.has(hit_def.get("damageId", 0)):
		return false
	if not rule.get("actTypes", []).is_empty() and not rule.actTypes.has(hit_def.get("actType", "")):
		return false
	if not rule.get("elements", []).is_empty() and not rule.elements.has(hit_def.get("element", "")):
		return false
	return true

func _damage_multiplier(act_type: String) -> float:
	var rate = 0.0
	for entry in statuses.values():
		var definition: Dictionary = _buff_index.get(entry.id, {})
		if definition.get("damageActType") == act_type and buff_layers(str(definition.get("damageRequiredBuff", ""))) > 0:
			rate += float(definition.get("damageRate", 0))
	return 1.0 + rate

func _conditions(conditions: Array, all_required: bool) -> bool:
	if conditions.is_empty():
		return true
	var any = false
	for condition in conditions:
		var passed = _condition(condition)
		if all_required and not passed:
			return false
		any = any or passed
	return all_required or any

func _condition(condition: Dictionary) -> bool:
	var type = str(condition.get("type", ""))
	var raw = _read_raw_json(str(condition.get("raw", "{}")))
	if not raw is Dictionary:
		raw = {}
	if type in ["EECT_CheckBuffExist", "ECT_CheckBuffExist"] or type.is_empty():
		var buff_id = str(condition.get("buff", ""))
		if not bool(condition.get("exists", true)): return not statuses.has(buff_id)
		return statuses.has(buff_id) and _compare(float(buff_layers(buff_id)), float(condition.get("layers", 1)), str(condition.get("compare", "ECT_GreaterEqual")))
	if type == "EECT_CheckHP":
		return _compare(health / max_health * 1000.0, float(raw.get("CompareVal", condition.get("value", 0))), str(raw.get("CompareType", condition.get("compare", "ECT_LessEqual"))))
	var property = str(raw.get("CustomProperty", ""))
	if property.is_empty():
		property = str(condition.get("property", ""))
	if property.is_empty(): property = str(raw.get("Property", ""))
	var current = property_value(property)
	if property == "AttackModeStr":
		current = custom_properties.get("AttackModeStr", "satk" if _current_slot == 4 else "normal")
	if type == "EECT_CheckCustomPropertyBool":
		if current == null:
			_report("Unbound bool property: " + property)
			return false
		return bool(current) == (str(raw.get("CompareVal", condition.get("value", false))).to_lower() == "true")
	if type == "EECT_CheckCustomPropertyString":
		return str(current) == str(raw.get("CompareVal", condition.get("value", "")))
	if type == "EECT_CheckCustomPropertyFloat" or type == "EECT_CheckCustomPropertyInt":
		if current == null:
			_report("Unbound numeric property: " + property)
			return false
		return float(current) >= float(raw.get("MinVal", 0)) and float(current) <= float(raw.get("MaxVal", 0))
	if type == "EECT_CheckSkillCanUse":
		return not fighter.is_empty() and _skill_cooldown_ready(2) and minf(float(energy[2]), skill_capacity(2)) >= skill_cost(2)
	_report("Unsupported condition " + type + ": " + str(condition.get("raw", "")))
	return false

func _requirements(rule: Dictionary) -> bool:
	if not str(rule.get("sourceState", "")).is_empty() and not statuses.has(str(rule.sourceState)):
		return false
	return _conditions(rule.get("requirements", []), true)

func _interrupt_conditions(raw: Dictionary) -> bool:
	var conditions: Array = raw.get("Conditions", [])
	if conditions.is_empty():
		return true
	var any = false
	for condition in conditions:
		var type = str(condition.get("InterruptType", ""))
		var passed = false
		if type == "EIT_CheckCustomPropertyBool":
			passed = bool(custom_properties.get(str(condition.get("Property", "")), false)) == bool(condition.get("CompareVal", false))
		elif type == "EIT_CheckCustomPropertyString":
			var property = str(condition.get("Property", ""))
			var value = custom_properties.get(property, "satk" if _current_slot == 4 else "normal") if property == "AttackModeStr" else property_value(property)
			passed = str(value) == str(condition.get("CompareVal", ""))
		elif type == "EIT_CheckAttackMode":
			var mode = str(custom_properties.get("AttackModeStr", "satk" if _current_slot == 4 else "normal"))
			passed = mode == ("satk" if condition.get("ModeType") == "Special" else "normal")
		elif type == "EIT_CheckBuffExist":
			var present := buff_layers(str(condition.get("BuffId", ""))) >= int(condition.get("CheckLayerCount", 1))
			passed = present == bool(condition.get("IsExist", true))
		elif type == "EIT_CheckWeaponType":
			var weapons := {"EWT_Sword": 1, "EWT_Sickle": 2, "EWT_Axe": 3, "EWT_Wand": 4, "EWT_Bow": 5, "EWT_Orb": 6, "EWT_Lance": 7, "EWT_DualBlades": 8}
			passed = character_id == int(weapons.get(str(condition.get("WeaponType", "")), -1))
		elif type == "EIT_CheckDead":
			passed = health <= 0
		elif type == "EIT_CheckAI":
			passed = str(custom_properties.get("OP_AIAction", "")) == str(condition.get("CompareVal", ""))
		elif type == "EIT_CheckCustomPropertyInt":
			var value = int(custom_properties.get(str(condition.get("CustomProperty", condition.get("Property", ""))), 0))
			passed = value >= int(condition.get("MinVal", 0)) and value <= int(condition.get("MaxVal", 0))
		elif type == "EIT_CheckHitAction":
			passed = EnemyHitReaction.matches(self, EnemyHitReaction.condition_flags(condition))
		if bool(raw.get("CheckAllCondition", true)) and not passed:
			return false
		any = any or passed
	return bool(raw.get("CheckAllCondition", true)) or any

func _apply_buff_layer_mapping(definition: Dictionary, caster_attack: float, depth: int) -> void:
	var raw: Dictionary = definition.get("raw_data", {})
	for group in raw.get("GroupList", []):
		var conditions: Array = group.get("Conditions", [])
		if conditions.is_empty(): continue
		var all_required = int(group.get("Logic", 0)) == 0
		var matched = all_required
		for condition in conditions:
			var buff_id = str(condition.get("CheckBuffId", ""))
			if buff_id.is_empty(): buff_id = str(raw.get("CheckBuffId", ""))
			if buff_id.is_empty(): continue
			var layers = buff_layers(buff_id)
			var passed = statuses.has(buff_id) and layers >= int(condition.get("MinLayer", 0)) and layers <= int(condition.get("MaxLayer", 0))
			matched = matched and passed if all_required else matched or passed
			if (all_required and not matched) or (not all_required and matched): break
		if matched:
			for addition in group.get("AddBuffList", []):
				add_buff(str(addition.get("BuffId", "")), int(addition.get("BuffLayer", 1)), caster_attack, depth + 1)

func _apply_shield_buff(definition: Dictionary) -> void:
	var raw: Dictionary = definition.get("raw_data", {})
	var caster = _caster_for(str(definition.id))
	var settings = _settings(definition, caster)
	var owner: DungeonCombat = self
	if raw.get("AttribSourceType", "Self") == "CasterUnit":
		owner = caster if caster != null else self
	elif settings.is_empty() and not raw.get("BuffSettingDataList", []).is_empty():
		settings = raw.BuffSettingDataList[0]
	if settings.is_empty(): return
	var reducing = str(settings.get("Mode", "Add")) == "Reduce"
	var value = (owner.stat_value(str(settings.get("Attr", "None"))) * float(settings.get("MulValue", 0)) + float(settings.get("AddValue", 0))) / 1000.0
	if not reducing: value *= 1.0 + (caster if caster != null else self).attribute("ShieldEmpower") / 1000.0
	value = absf(float(int(value))) if reducing else float(int(value))
	if int(settings.get("MinShieldValue", 0)) > 0: value = maxf(value, float(settings.MinShieldValue))
	if int(settings.get("MaxShieldValue", 0)) > 0: value = minf(value, float(settings.MaxShieldValue))
	owner.shield = maxf(0.0, owner.shield + (-value if reducing else value))

func _apply_extra_buff(definition: Dictionary, entry: Dictionary, caster_attack: float, depth: int) -> void:
	var type = str(definition.get("type", ""))
	var raw: Dictionary = definition.get("raw_data", {})
	var caster = _caster_for(str(entry.id))
	var settings = _settings(definition, caster)
	match type:
		"EBT_SpecialBuffArmor":
			armor += maxf(0.0, max_health * float(settings.get("MaxHpPercentChange", 0)) / 1000.0 + float(settings.get("FixValueChange", 0))) * int(entry.layers)
		"EBT_SpecialBuffLockHp":
			_refresh_health_lock(entry, settings)
		"EBT_SpecialBuffChargeSkillSp":
			var slot := int({"MainSkill": 3, "SubSkill": 2, "Dodge": 1}.get(str(raw.get("AttackType", "")), -1))
			if str(raw.get("AttackType", "")) == "MonsterPartnerSkill":
				_emit_event("partner_charge", {"settings": settings.duplicate(true)})
			elif slot < 0:
				_report("Skill charge requires system adapter: %s %s" % [entry.id, raw.get("AttackType", "")])
			elif not fighter.is_empty():
				var amount := float(settings.get("ChargeCount", 0)) / 1000.0 + skill_cost(slot) * float(settings.get("ChargePercent", 0)) / 1000.0
				add_skill_charge(slot, amount)
				var reduction := float(settings.get("ReduceCooldown", 0)) / 1000.0 + float(fighter.skills[slot].cooldown) * float(settings.get("ReduceCooldownPercent", 0)) / 1000.0
				cooldowns[slot] = maxf(0, float(cooldowns[slot]) - reduction)
		"EBT_SpecialRandomBuffTrigger":
			var rows: Array = raw.get("RandomDataList", [])
			var total = 0.0
			for row in rows:
				total += float(row.get("RandomWeight", 0))
			var value = _random() * total
			for row in rows:
				value -= float(row.get("RandomWeight", 0))
				if value <= 0:
					_apply_raw_buff(row.get("AddBuffData", {}), caster_attack, depth + 1)
					break
		"EBT_SpecialAddSummonUnit":
			var summon: Dictionary = settings.get("AddSummonUnitDef", {}).duplicate(true)
			var summoner: DungeonCombat = self
			var target_key := ""
			# A transferred hit effect retains the caster's team and target origin.
			if caster != null and caster != self:
				summoner = caster
				target_key = actor_key
				summon["OriginType"] = "targetPosAndSelfDir"
			for index in range(clampi(int(summon.get("AddSummonUnitQuantity", 1)), 1, 30)):
				summoner._spawn_summon(str(summon.get("AddSummonUnitId", "")), summoner._clock, summoner.current_action, summoner._current_slot, float(summon.get("InitPosOffset", {}).get("z", 0)), depth + 1, summon, target_key)
		"EBT_PlayEffect":
			_emit_event("buff_effect", {"id": entry.id, "definition": raw})
		"EBT_SpecialSendMsg":
			_emit_event("message", {"name": raw.get("MsgName", ""), "argument": raw.get("MsgArg1", "")})
			notify_gameplay("message", {"name": raw.get("MsgName", ""), "argument": raw.get("MsgArg1", "")})
		"EBT_EditorPropertyContext":
			_emit_event("property_context", {"id": entry.id, "definition": settings})
		"EBT_SpecialBuffGenerationMonster":
			var points: Array = settings.get("SpawnPoints", [])
			var count := (points.size() if int(settings.get("GenerationMode", 0)) == 1 else 1) * int(entry.layers)
			_emit_event("spawn_monster", {"enemy_id": int(settings.get("MonsterId", 0)), "spawn_points": points, "generation_count": count, "definition": settings})
		"EBT_SpecialRevive":
			if health <= 0:
				revive(max_health)
		"EBT_SBuffChangeSpecAttributeToOther":
			if settings.get("SourceType") == "Hp" and settings.get("TargetType") == "Shield":
				var available = maxf(0.0, health - float(settings.get("ThresholdFixed", 0)) - max_health * float(settings.get("ThresholdPercent", 0)) / 1000.0)
				var converted = minf(available, health * float(settings.get("ThresholdCurrentPercent", 1000)) / 1000.0)
				var previous = health
				health -= converted
				_apply_health_locks(previous)
				shield += maxf(0.0, previous - health) * float(settings.get("TargetGain", 1)) / maxf(0.001, float(settings.get("SourceCost", 1)))
			else:
				_report("Resource conversion needs system adapter: " + str(entry.id))
		"EBT_ModifyAttackDef":
			for key in settings:
				if key in ["Level", "AttackDefIdList", "HitFeedBack_StopFrameAdd", "ModifyEmit_Num", "ModifyEntity_RangePercent", "ModifyEntity_PhysicEntitySizeAddPercent", "ModifyEntity_PhysicEntityIntervalAddSummonUnitList", "DetectionEffectName", "ReplaceEffectName"]: continue
				var value: Variant = settings[key]
				if (value is int or value is float) and not is_zero_approx(float(value)) or value is String and not value.is_empty() or value is Array and not value.is_empty():
					_report("Attack definition modifier requires adapter: %s %s" % [entry.id, key])
		"EBT_SpecialAddRogueAttribute":
			_report("Dynamic rule needs adapter: %s %s" % [entry.id, type])

func _apply_health_locks(previous: float) -> void:
	var locks: Array = []
	for entry in statuses.values():
		var definition: Dictionary = _buff_index.get(entry.id, {})
		if definition.get("type") != "EBT_SpecialBuffLockHp" or int(entry.layers) <= 0:
			continue
		var settings = _settings(definition, _caster_for(str(entry.id)))
		if settings.is_empty(): continue
		_refresh_health_lock(entry, settings)
		locks.append({"entry": entry, "settings": settings})
	for lock in locks:
		var entry: Dictionary = lock.entry
		var settings: Dictionary = lock.settings
		var minimum_percent = float(settings.get("MinPrecent", 1))
		# Native SBuffLockHp admits only locks with the highest live lower bound.
		if locks.any(func(other): return other.entry != entry and int(other.entry.lock_remaining) != 0 and float(other.settings.get("MinPrecent", 1)) > minimum_percent): continue
		var candidate = health
		var minimum = maxf(1.0, max_health * minimum_percent / 1000.0)
		var maximum = minf(max_health, max_health * float(settings.get("MaxPrecent", 1000)) / 1000.0)
		var remaining = int(entry.lock_remaining)
		health = minf(candidate, maximum)
		if remaining != 0 and candidate < minimum: health = minimum
		var activated = health != candidate if remaining < 0 else remaining > 0 and candidate < previous and candidate < minimum and health <= minimum
		if activated:
			if remaining > 0: entry.lock_remaining = remaining - 1
			entry.lock_count = int(entry.get("lock_count", 0)) + 1
			var queued: Array = custom_properties.get("_health_lock_triggers", [])
			queued.append({"id": str(entry.id), "serial": int(entry.lock_serial)})
			custom_properties["_health_lock_triggers"] = queued
	if health < 1.0 and health < previous:
		for lock in locks:
			var entry: Dictionary = lock.entry
			statuses.erase(str(entry.id))
			var definition: Dictionary = _buff_index.get(entry.id, {})
			if not str(definition.get("disposeBuff", "")).is_empty():
				add_buff(str(definition.disposeBuff), int(definition.get("disposeLayers", 1)), float(entry.attack))
		custom_properties["_health_lock_triggers"] = []

func _refresh_health_lock(entry: Dictionary, settings: Dictionary) -> void:
	var limit = int(settings.get("MaxLockCount", -1))
	if not entry.has("lock_remaining"):
		entry.lock_remaining = -1 if limit < 0 else maxi(0, limit - int(entry.get("lock_count", 0)))
	elif limit < 0:
		entry.lock_remaining = -1
	elif int(entry.get("lock_limit", limit)) < 0:
		entry.lock_remaining = limit
	else:
		entry.lock_remaining = clampi(int(entry.lock_remaining), 0, limit)
	entry.lock_limit = limit
	if not entry.has("lock_serial"):
		var serial = int(custom_properties.get("_health_lock_serial", 0)) + 1
		custom_properties["_health_lock_serial"] = serial
		entry.lock_serial = serial

func _tick_health_lock_triggers() -> void:
	# The APK yields one frame before adding the trigger buff and removing spent locks.
	var queued: Array = custom_properties.get("_health_lock_triggers", [])
	if queued.is_empty(): return
	custom_properties["_health_lock_triggers"] = []
	for trigger in queued:
		var id = str(trigger.id)
		var entry: Dictionary = statuses.get(id, {})
		if health <= 0 or entry.is_empty() or int(entry.get("lock_serial", -1)) != int(trigger.serial): continue
		var definition: Dictionary = _buff_index.get(id, {})
		var settings = _settings(definition, _caster_for(id))
		if settings.is_empty(): continue
		_refresh_health_lock(entry, settings)
		_apply_raw_buff(settings.get("ActiveTriggerBuff", {}), float(entry.attack), 0, _caster_for(id))
		if int(entry.lock_remaining) == 0 and statuses.get(id) == entry:
			statuses.erase(id)
			if not str(definition.get("disposeBuff", "")).is_empty():
				add_buff(str(definition.disposeBuff), int(definition.get("disposeLayers", 1)), float(entry.attack))

func _apply_raw_buff(raw: Dictionary, caster_attack: float, depth: int, caster: DungeonCombat = null) -> void:
	var id = str(raw.get("BuffTriggerId", ""))
	if not id.is_empty():
		if caster != null and caster != self:
			_buff_casters[id] = weakref(caster)
		add_buff(id, int(raw.get("BuffAddLayer", 1)), caster_attack, depth)

func _caster_for(id: String) -> DungeonCombat:
	var reference = _buff_casters.get(id)
	return reference.get_ref() if reference is WeakRef else null

func bind_buff_caster(id: String, caster: DungeonCombat) -> void:
	if caster != null and caster != self:
		_buff_casters[id] = weakref(caster)

func rebind_buff_casters(actors: Dictionary) -> Array:
	var unresolved: Array = []
	var records: Array = statuses.values().duplicate()
	for event in _pending:
		if event.has("condition_effect"):
			records.append(event.condition_effect)
	for entry in records:
		var key = str(entry.get("caster_key", actor_key))
		if key == actor_key:
			continue
		var caster = actors.get(key)
		if caster is DungeonCombat:
			bind_buff_caster(str(entry.id), caster)
		elif not unresolved.has(key):
			unresolved.append(key)
	return unresolved

func spawn_summon(id: String, origin: Dictionary = {}, target_key: String = "", provenance: Dictionary = {}) -> bool:
	if not _summon_index.has(id):
		_report("Missing summon " + id)
		return false
	_spawn_summon(id, _clock, str(provenance.get("action", current_action)), int(provenance.get("slot", _current_slot)), float(origin.get("InitPosOffset", {}).get("z", 0)), 0, origin, target_key)
	return true

func property_value(name: String) -> Variant:
	var value = custom_properties.get(name)
	for entry in statuses.values():
		var definition: Dictionary = _buff_index.get(entry.id, {})
		if definition.get("type") != "EBT_EditorPropertyContext":
			continue
		var settings = _settings(definition, _caster_for(str(entry.id)))
		for suffix in ["", "2", "3"]:
			if settings.get("Name" + suffix, "") == name:
				value = (float(value) if value != null else 0.0) + float(settings.get("Value" + suffix, 0)) * int(entry.layers)
	return value

func _property_context_total(names: String) -> float:
	var value = 0.0
	for name in names.replace(",", "|").split("|", false):
		var part = property_value(name.strip_edges())
		if part != null: value += float(part)
	return value

func _damage_data(id: int) -> Dictionary:
	var rows: Array = catalog.get("damage_definitions", {}).get(str(id), [])
	var fallback: Dictionary = {}
	for row in rows:
		if int(row.get("Level", 1)) <= 1:
			fallback = row
		elif buff_layers(str(int(row.get("Level", 0)))) > 0:
			return row
	return fallback if not fallback.is_empty() else rows[0] if not rows.is_empty() else {}

func _damage_value(definition: Dictionary, caster_attack: float) -> float:
	var basis = caster_attack if definition.get("DamageAttribType") == "FinalAtk" else stat_value(str(definition.get("DamageAttribType", "None")))
	var second = caster_attack if definition.get("DamageAttribType2") == "FinalAtk" else stat_value(str(definition.get("DamageAttribType2", "None")))
	return basis * float(definition.get("DamageMulValue", 0)) / 1000.0 + second * float(definition.get("DamageMulValue2", 0)) / 1000.0 + float(definition.get("DamageFixValue", 0))

func _spirit_apply(base: float, modifier: Dictionary, source: DungeonCombat = null) -> float:
	if not bool(modifier.get("Enabled", false)): return base
	var owner: DungeonCombat = source if source != null else self
	var influences: Array = modifier.get("Influences", [])
	if not modifier.has("Influences"):
		var legacy := modifier.duplicate()
		legacy["Attribute"] = "Spirit" + str(modifier.get("Parameter", "Trigger"))
		influences = [legacy]
	var value := base
	for influence in influences:
		if not influence is Dictionary or not bool(influence.get("Enabled", false)): continue
		var name := str(influence.get("Attribute", "None"))
		var weight := float(influence.get("PerMille", 0))
		if name == "None" or not is_finite(weight) or is_zero_approx(weight): continue
		var attribute_value := owner.attribute(name)
		if not is_finite(attribute_value): continue
		var spirit := name in ["SpiritTrigger", "SpiritEnhance", "SpiritRange", "SpiritDuration", "SpiritCount"]
		var lower := float(influence.get("MinMultiplier", 0)) if spirit or bool(influence.get("UseMinMultiplier", false)) else -INF
		var upper := float(influence.get("MaxMultiplier", 5)) if spirit or bool(influence.get("UseMaxMultiplier", false)) else INF
		if is_nan(lower): lower = 0.0
		if is_nan(upper): upper = 5.0
		# Native Apply adds each weighted, bounded attribute to the supplied base.
		value += weight * clampf(attribute_value / 1000.0, minf(lower, upper), maxf(lower, upper))
	return value

func _spirit_settings(settings: Dictionary, source: DungeonCombat = null) -> Dictionary:
	var output := settings
	for key in settings:
		if not str(key).ends_with("SpiritModifier") or not settings[key] is Dictionary or not bool(settings[key].get("Enabled", false)): continue
		var target := str(key).trim_suffix("SpiritModifier")
		if not settings.get(target) is float and not settings.get(target) is int: continue
		if output == settings: output = settings.duplicate(true)
		output[target] = _spirit_apply(float(settings[target]), settings[key], source)
	return output

func _spirit_conditions(conditions: Array, source: DungeonCombat = null) -> Array:
	var output: Array = []
	for condition in conditions: output.append(_spirit_settings(condition, source))
	return output

func _settings(definition: Dictionary, source: DungeonCombat = null) -> Dictionary:
	var settings: Array = definition.get("raw_data", {}).get("BuffSettingDataList", [])
	var mode = str(definition.get("raw_data", {}).get("LevelSourceType", "Single"))
	if mode == "BuffExist" or mode == "BuffExist_Caster":
		var owner = source if mode == "BuffExist_Caster" and source != null else self
		var fallback: Dictionary = {}
		for row in settings:
			if int(row.get("Level", 0)) <= 1:
				fallback = row
			elif owner.buff_layers(str(int(row.get("Level", 0)))) > 0:
				return _spirit_settings(row, source)
		return _spirit_settings(fallback, source)
	if mode == "RoleUnitType_1P2M":
		for row in settings:
			if int(row.get("Level", 0)) == (1 if not fighter.is_empty() else 2):
				return _spirit_settings(row, source)
	return _spirit_settings(settings[0], source) if not settings.is_empty() and settings[0] is Dictionary else {}

func _collect_initial(id: String, result: Dictionary) -> void:
	if result.has(id):
		return
	result[id] = true
	for child in _buff_index.get(id, {}).get("initial", []):
		_collect_initial(str(child), result)

func _collect_progression_effects(id: String, result: Dictionary) -> void:
	if result.has(id) or not _buff_index.has(id): return
	result[id] = true
	var definition: Dictionary = _buff_index[id]
	var raw: Dictionary = definition.get("raw_data", {})
	for child in definition.get("initial", []): _collect_progression_effects(str(child), result)
	_collect_progression_effects(str(definition.get("disposeBuff", raw.get("DisposeTriggerBuff", {}).get("BuffTriggerId", ""))), result)
	_collect_progression_effects(str(definition.get("modify", "")), result)
	_collect_progression_effects(str(raw.get("FailedTriggerBuffId", "")), result)
	for rule in definition.get("triggers", []):
		for child in rule.get("add", []): _collect_progression_effects(str(child.id), result)
	for settings in raw.get("BuffSettingDataList", []):
		_collect_progression_effects(str(settings.get("AddBuff_ToAttacker", {}).get("BuffTriggerId", "")), result)
	if str(raw.get("EBuffAddTargetType", "Self")) in ["Self", "Caster"]:
		for settings in raw.get("BuffSettingDataList", []):
			for child in settings.get("AddBuffIDList", []): _collect_progression_effects(str(child), result)

func _clear_charge() -> void:
	for id in ["700004", "700005", "700001", "700002", "700003"]:
		statuses.erase(id)

func _release_charge(action_name: String) -> void:
	var next = _action("ActGroup_playerchara", action_name)
	if next.is_empty():
		_report("Missing charge release " + action_name)
		return
	charging = false
	statuses.erase("700004")
	statuses.erase("700005")
	_start(next, 4)

func _cancel_sequence(sequence: int, keep_spawned := true) -> void:
	_expire_battle_time_scale_windows(sequence)
	_pending = _pending.filter(func(event): return int(event.sequence) != sequence or (keep_spawned and not bool(event.get("action_timeline", true))))
	if int(custom_properties.get("_movement_sequence", -1)) == sequence: custom_properties["_movement_sequence"] = -1

func battle_time_scale_windows() -> Array:
	return custom_properties.get("_battle_time_scale_windows", {}).values().duplicate(true)

func _expire_battle_time_scale_windows(cancelled_sequence: int = -1) -> void:
	var windows: Dictionary = custom_properties.get("_battle_time_scale_windows", {})
	if windows.is_empty(): return
	var elapsed = action_elapsed * maxf(0.01, float(custom_properties.get("_feel_action_speed", 1)))
	for key in windows.keys():
		var window: Dictionary = windows[key]
		if int(window.sequence) == cancelled_sequence or (int(window.sequence) == _cast_sequence and elapsed + 0.0000001 >= float(window.end)):
			_emit_event("battle_time_scale", {"phase": "Exit", "window": window.duplicate(true)})
			windows.erase(key)
	custom_properties["_battle_time_scale_windows"] = windows

func record_input(slot: int, pressed: bool) -> void:
	if slot in [2, 3]:
		if pressed:
			custom_properties.InputSkill = true
			custom_properties["LastInputAttackKeyName"] = "skill_%d" % (slot - 1)
		elif slot == 2:
			custom_properties["InputSkill1_LongPress"] = false

func _action(group: String, id: String) -> Dictionary:
	return _action_index.get(group + "/" + id, {})

# Returned command and condition data is shared; mutating payloads parse separately.
static func _read_raw_json(encoded: String) -> Variant:
	if _raw_json_cache.has(encoded): return _raw_json_cache[encoded]
	var parsed: Variant = JSON.parse_string(encoded)
	if _raw_json_keys.size() < RAW_JSON_CACHE_CAPACITY:
		_raw_json_keys.append(encoded)
	else:
		_raw_json_cache.erase(_raw_json_keys[_raw_json_cursor])
		_raw_json_keys[_raw_json_cursor] = encoded
		_raw_json_cursor = (_raw_json_cursor + 1) % RAW_JSON_CACHE_CAPACITY
	_raw_json_cache[encoded] = parsed
	return parsed

func _load_catalog(value: Variant) -> bool:
	if _heavy_catalog.is_empty():
		var parsed_heavy = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/heavy_attacks.json"))
		if parsed_heavy is Dictionary: _heavy_catalog = parsed_heavy
	if value is Dictionary and value.has("actions"):
		catalog = value
		_action_index = {}
		_buff_index = {}
		_summon_index = {}
		for item in catalog.get("actions", []):
			_action_index[str(item.key)] = item
		for item in catalog.get("buffs", []):
			_buff_index[str(item.id)] = _assemble_heavy_buff(item)
		for item in catalog.get("summons", []):
			_summon_index[str(item.id)] = item
		return true
	if _shared_catalog.is_empty():
		if not FileAccess.file_exists(DATA_PATH):
			return false
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if not parsed is Dictionary:
			return false
		_shared_catalog = parsed
		for item in parsed.get("actions", []):
			_shared_actions[str(item.key)] = item
		for item in parsed.get("buffs", []):
			_shared_buffs[str(item.id)] = _assemble_heavy_buff(item)
		for item in parsed.get("summons", []):
			_shared_summons[str(item.id)] = item
	catalog = _shared_catalog
	_action_index = _shared_actions
	_buff_index = _shared_buffs
	_summon_index = _shared_summons
	return not catalog.is_empty()

func _assemble_heavy_buff(definition: Dictionary) -> Dictionary:
	var assembly: Dictionary = _heavy_catalog.get("buffs", {}).get(str(definition.id), {})
	if assembly.is_empty(): return definition
	var result = definition.duplicate()
	result.merge(assembly, true)
	return result

func _reset() -> void:
	clear_impact_state()
	enemy_hit_motion_step = -1.0
	enemy_ai = null
	enemy_ai_enabled = false
	_enemy_speed_windows = []
	_enemy_interrupts = []
	_enemy_interrupt_program = []
	_enemy_timing_cache.clear()
	_navigation_cached = false
	_navigation_name = ""
	_navigation_definition = {}
	_navigation_windows = PackedFloat64Array()
	_navigation_fallback = false
	action_elapsed = 0.0
	action_step = -1.0
	fighter = {}
	enemy = {}
	enemy_hit_rules = {}
	character_id = 0
	enemy_id = 0
	actor_key = ""
	energy = [0.0, 0.0, 0.0, 0.0, 0.0]
	cooldowns = [0.0, 0.0, 0.0, 0.0, 0.0]
	skill_round_uses = [0, 0, 0, 0, 0]
	statuses = {}
	diagnostics = []
	events = []
	_pending = []
	_external = {}
	_progression_roots = {}
	_progression_owned = []
	_external_numeric_buffs = []
	_clock = 0.0
	busy = 0.0
	invincible = 0.0
	frozen = 0.0
	_slow_time = 0.0
	_slow_scale = 1.0
	_combo = 0
	_combo_expiry = 0.0
	_cast_sequence = 0
	_current_slot = 0
	charging = false
	charge_released = false
	charge_elapsed = 0.0
	current_action = ""
	armor = 0.0
	shield = 0.0
	_dead_emitted = false
	_emission_sequence = 0
	_condition_depth = 0
	_buff_casters = {}
	_dodge_time = 0.0
	_dodge_recharge_elapsed = 0.0
	_block_time = 0.0
	_anti_heal_time = 0.0
	_attribute_stack = {}
	custom_properties = {"InputMove": false, "InputAttack": false, "InputAttack_LongPress": false, "InputSkill": false}

func _emit_event(type: String, content: Dictionary = {}) -> void:
	content["type"] = type
	content["kind"] = type
	content["actor"] = character_id if character_id > 0 else enemy_id
	content["actor_key"] = actor_key
	content["clock"] = _clock
	events.append(content)

func _emit_death() -> void:
	if not _dead_emitted:
		_dead_emitted = true
		EnemyHitReaction.clear_motion(self)
		for window in battle_time_scale_windows():
			_expire_battle_time_scale_windows(int(window.sequence))
		_emit_event("died")

func _report(message: String) -> void:
	if not diagnostics.has(message):
		diagnostics.append(message)
		_emit_event("diagnostic", {"message": message})

func _random() -> float:
	_random_state = (_random_state * 1664525 + 1013904223) & 0xffffffff
	return float(_random_state) / 4294967295.0

func _compare(a: float, b: float, comparison: String) -> bool:
	match comparison:
		"ECT_Equal": return is_equal_approx(a, b)
		"ECT_Less": return a < b
		"ECT_Greater": return a > b
		"ECT_LessEqual": return a <= b
		_: return a >= b

func _event_before(a: Dictionary, b: Dictionary) -> bool:
	if float(a.at) == float(b.at) and a.has("emitter_start") != b.has("emitter_start"): return a.has("emitter_start")
	return float(a.at) < float(b.at)

func _result(success: bool, message: String, id: int = 0) -> Dictionary:
	return {"success": success, "message": message, "id": id}
