extends SceneTree

const Combat = preload("res://scripts/domain/combat.gd")
const STEP := 1.0 / 60.0
var _tick_seconds := STEP
var _behavior: Dictionary = {}
var checks := 0
var failures: Array[String] = []
var rows: Array = []
var skills: Array = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_behavior = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/monster_behavior.json"))
	for config in [
		{"id": 13001, "lock": "41300103", "ratio": 0.499, "action": "roar"},
		{"id": 23001, "lock": "42300104", "ratio": 0.599, "action": "attack3"},
		{"id": 33001, "lock": "43300104", "ratio": 0.499, "action": "RoarAttack"},
		{"id": 43001, "lock": "44300130", "ratio": 0.499, "action": "P2action"},
	]:
		_single_phase(config)
	for hz in [30, 60, 120]:
		_tick_seconds = 1.0 / hz
		_dragon_phases(hz)
	_tick_seconds = STEP
	_boss_skill_outputs()
	var report = {"passed": failures.is_empty(), "checks": checks, "failures": failures, "phases": rows, "skills": skills, "scope": "Bosses enter through begin_enemy_spawn and the serialized AI. Real receive damage crosses HP gates; HP is never assigned to phase thresholds. Four one-time boss transitions, the dragon's three HP gates and recovery at 30/60/120Hz, plus attack output from all ten Boss definitions. Headless domain simulation, not original APK execution or rendered/mobile validation."}
	FileAccess.open("res://reports/boss-phase-test.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("BOSS_PHASE ", JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures, "phases": rows.size(), "boss_skills": skills.size()}))
	quit(0 if failures.is_empty() else 1)

func _new_enemy(id: int) -> DungeonCombat:
	var enemy = Combat.new()
	_check(enemy.configure_enemy(id, 731).success, "%d configures" % id)
	_check(enemy.begin_enemy_spawn(), "%d begins authored spawn" % id)
	var startup: Dictionary = _behavior.get("enemies", {}).get(str(id), {})
	var expected = str(startup.get("boss_action", ""))
	if expected.is_empty(): expected = str(startup.get("first_action", "born"))
	_check(enemy.current_action == expected, "%d begins source BossAct or FirstAct %s" % [id, expected])
	return enemy

func _record(enemy: DungeonCombat, ledger: Dictionary) -> void:
	for event in enemy.drain_events():
		if event.type == "action_started": ledger.actions.append(str(event.action))
		if event.type in ["hit", "projectile", "summon_spawned"]: ledger.outputs += 1

func _step(enemy: DungeonCombat, ledger: Dictionary, distance: float = 2.0) -> void:
	enemy.custom_properties["EnemyDistances"] = [distance]
	enemy.tick_enemy_ai(_tick_seconds, {"target_available": true, "distance": distance, "line_blocked": false, "battle_time": enemy._clock, "monster_index": 0, "target_buffs": []})
	enemy.tick(_tick_seconds)
	_record(enemy, ledger)

func _advance(enemy: DungeonCombat, ledger: Dictionary, seconds: float) -> void:
	for frame in int(ceil(seconds / _tick_seconds)):
		_step(enemy, ledger)

func _wait_buff(enemy: DungeonCombat, ledger: Dictionary, buff: String, present: bool, seconds: float) -> bool:
	for frame in int(ceil(seconds / _tick_seconds)):
		if enemy.statuses.has(buff) == present: return true
		_step(enemy, ledger)
	return enemy.statuses.has(buff) == present

func _damage(enemy: DungeonCombat) -> void:
	enemy.receive({"damage": enemy.max_health * 1000.0, "attack_collision": false, "definition": {}}, enemy.attack)

func _single_phase(config: Dictionary) -> void:
	var enemy = _new_enemy(int(config.id))
	var ledger := {"actions": [], "outputs": 0}
	var installed = _wait_buff(enemy, ledger, str(config.lock), true, 15.0)
	_check(installed, "%d authored entrance installs HP lock %s" % [config.id, config.lock])
	if not installed:
		rows.append({"enemy": config.id, "spawn_actions": ledger.actions, "lock_installed": false})
		return
	_damage(enemy)
	var stopped = is_equal_approx(enemy.health / enemy.max_health, float(config.ratio))
	_check(stopped, "%d lethal damage stops at authored HP gate %.3f" % [config.id, config.ratio])
	if not stopped:
		rows.append({"enemy": config.id, "lock_installed": true, "health_ratio": enemy.health / enemy.max_health, "actions": ledger.actions})
		return
	_damage(enemy)
	_check(is_equal_approx(enemy.health / enemy.max_health, float(config.ratio)), "%d remains locked through repeated damage before transition" % config.id)
	var released = _wait_buff(enemy, ledger, str(config.lock), false, 40.0)
	_check(ledger.actions.has(config.action), "%d source AI reaches phase action %s" % [config.id, config.action])
	_check(released, "%d authored phase releases HP lock %s" % [config.id, config.lock])
	if released:
		_damage(enemy)
		_check(enemy.health <= 0, "%d can die after phase lock is released" % config.id)
	_check(enemy.diagnostics.is_empty() and enemy.enemy_ai.diagnostics.is_empty(), "%d phase has no unsupported runtime operations" % config.id)
	rows.append({"enemy": config.id, "lock_installed": installed, "released": released, "actions": ledger.actions, "health_ratio": enemy.health / enemy.max_health})

func _dragon_phases(hz: int) -> void:
	var enemy = _new_enemy(53001)
	var ledger := {"actions": [], "outputs": 0}
	var installed = _wait_buff(enemy, ledger, "45300130", true, 15.0)
	_check(installed, "Dragon authored entrance installs eighty-percent HP lock at %dHz" % hz)
	if not installed: return
	for gate in [
		{"lock": "45300130", "ratio": 0.799, "next": "45300131", "action": "roar1"},
		{"lock": "45300131", "ratio": 0.499, "next": "45300120", "action": "roar2"},
		{"lock": "45300120", "ratio": 0.001, "next": "45300104", "action": "roar3"},
	]:
		_damage(enemy)
		var stopped = is_equal_approx(enemy.health / enemy.max_health, float(gate.ratio))
		_check(stopped, "Dragon lethal hit stops at %.3f HP gate at %dHz" % [gate.ratio, hz])
		if not stopped:
			rows.append({"enemy": 53001, "hz": hz, "failed_gate": gate.lock, "health_ratio": enemy.health / enemy.max_health, "actions": ledger.actions})
			return
		_damage(enemy)
		_check(is_equal_approx(enemy.health / enemy.max_health, float(gate.ratio)), "Dragon gate %s survives repeated damage" % gate.lock)
		var advanced = _wait_buff(enemy, ledger, str(gate.next), true, 45.0)
		_check(advanced and ledger.actions.has(gate.action), "Dragon source AI reaches %s and installs %s" % [gate.action, gate.next])
		_check(not enemy.statuses.has(str(gate.lock)), "Dragon phase %s clears old HP lock" % gate.action)
		if not advanced: return
	_advance(enemy, ledger, 8.0)
	var recovery_ratio = enemy.health / enemy.max_health
	_check(enemy.health / enemy.max_health >= 0.49 and enemy.health / enemy.max_health <= 0.51, "Dragon near-death source healing restores about fifty percent HP at %dHz" % hz)
	_check(not enemy.statuses.has("45300120"), "Dragon final form releases near-death lock")
	_damage(enemy)
	_check(enemy.health <= 0, "Dragon final form can die after recovery and temporary lock expiry")
	var unsupported = enemy.diagnostics.filter(func(message): return message != "Summon behavior requires world adapter: 45300105 ESUT_StaticRangeTrigger")
	_check(unsupported.is_empty() and enemy.enemy_ai.diagnostics.is_empty(), "Dragon full phase sequence has no unsupported runtime operations")
	rows.append({"enemy": 53001, "hz": hz, "actions": ledger.actions, "health_ratio": enemy.health / enemy.max_health, "recovery_ratio": recovery_ratio, "diagnostics": enemy.diagnostics, "final_gate_released": not enemy.statuses.has("45300120")})

func _boss_skill_outputs() -> void:
	var fixture = Combat.new()
	fixture.configure()
	for definition in fixture.catalog.enemies:
		if str(definition.get("rank", "")) != "Boss": continue
		var enemy = _new_enemy(int(definition.id))
		var ledger := {"actions": [], "outputs": 0}
		for frame in 3600:
			_step(enemy, ledger, [12.0, 2.0, 6.0, 1.0][mini(3, frame / 900)])
		_check(int(ledger.outputs) > 0, "%d Boss produces actual source skill payloads" % int(definition.id))
		_check(enemy.diagnostics.is_empty() and enemy.enemy_ai.diagnostics.is_empty(), "%d Boss skills have no unsupported operations" % int(definition.id))
		skills.append({"enemy": definition.id, "actions": ledger.actions, "attack_outputs": ledger.outputs})
	_check(skills.size() == 10, "All ten packaged Boss definitions are exercised")

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)
