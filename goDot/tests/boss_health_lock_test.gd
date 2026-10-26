extends SceneTree

const Combat = preload("res://scripts/domain/combat.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_unlimited_and_priority()
	_finite_and_deferred()
	_all_health_paths()
	_restore_and_refresh()
	_shields()
	var report = {"checks": checks, "failures": failures, "passed": failures.is_empty(), "scope": "Native-derived lock and shield contracts with synthetic boundary fixtures plus real lava-dragon shield buffs; Godot domain execution, not APK runtime observation."}
	FileAccess.open("res://reports/boss-health-lock-test.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("BOSS_HEALTH_LOCK ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func _unit() -> DungeonCombat:
	var unit = Combat.new()
	unit.configure_enemy(11001, 73)
	unit._buff_index = unit._buff_index.duplicate(true)
	unit.max_health = 1000
	unit.health = 1000
	unit.defense = 0
	return unit

func _buff(unit: DungeonCombat, id: String, type: String, settings: Dictionary = {}) -> Dictionary:
	var definition = {"id": id, "type": type, "duration": -1, "maxLayers": 99, "triggers": [], "raw_data": {"LevelSourceType": "Single", "BuffSettingDataList": [settings]}}
	unit._buff_index[id] = definition
	return definition

func _lock(unit: DungeonCombat, id: String, floor_value: int, count: int = -1, ceiling: int = 1000, trigger: String = "") -> Dictionary:
	return _buff(unit, id, "EBT_SpecialBuffLockHp", {"MinPrecent": floor_value, "MaxPrecent": ceiling, "MaxLockCount": count, "ActiveTriggerBuff": {"BuffTriggerId": trigger, "BuffAddLayer": 1}})

func _damage(unit: DungeonCombat, amount: float = 10000) -> void:
	unit.receive({"damage": amount, "attack_collision": false, "definition": {}})

func _unlimited_and_priority() -> void:
	var unit = _unit()
	_buff(unit, "marker", "EBT_NumericalBuff")
	_lock(unit, "lock", 499, -2, 1000, "marker")
	unit.add_buff("lock")
	for hit in 3:
		_damage(unit)
		_check(is_equal_approx(unit.health, 499), "Every negative count protects repeated lethal hits")
	_check(unit.buff_layers("marker") == 0, "Lock trigger waits for the next frame")
	unit.tick(0)
	_check(unit.buff_layers("marker") == 0, "Zero time does not resume deferred triggers")
	unit.tick(0.01)
	_check(unit.buff_layers("marker") == 3 and unit.statuses.has("lock"), "Unlimited lock triggers each clamp and remains installed")
	unit.remove_buff("lock")
	_damage(unit)
	_check(unit.health <= 0, "Explicit lock removal permits death")
	for order in [["low", "high"], ["high", "low"]]:
		unit = _unit()
		_lock(unit, "low", 100, -1, 200)
		_lock(unit, "high", 600)
		for id in order: unit.add_buff(id)
		_damage(unit)
		_check(is_equal_approx(unit.health, 600), "Highest active floor suppresses a lower lock's upper cap regardless of insertion order")
	unit = _unit()
	_lock(unit, "one_hp", 0)
	unit.add_buff("one_hp")
	_damage(unit)
	_check(unit.health == 1, "Native lower bound retains at least one HP")
	unit = _unit()
	var caster = _unit()
	_buff(caster, "900000", "EBT_NumericalBuff")
	caster.add_buff("900000")
	var definition = _lock(unit, "caster_lock", 200)
	definition.raw_data.LevelSourceType = "BuffExist_Caster"
	definition.raw_data.BuffSettingDataList = [{"Level": 1, "MinPrecent": 200}, {"Level": 900000, "MinPrecent": 700}]
	unit.bind_buff_caster("caster_lock", caster)
	unit.add_buff("caster_lock")
	_damage(unit)
	_check(unit.health == 700, "HP changes select lock settings from the bound caster's buff tier")

func _finite_and_deferred() -> void:
	var unit = _unit()
	_buff(unit, "marker", "EBT_NumericalBuff")
	_lock(unit, "lock", 500, 1, 1000, "marker")
	unit.add_buff("lock")
	_damage(unit)
	_check(unit.health == 500 and int(unit.statuses.lock.lock_remaining) == 0, "Finite lock consumes its remaining use on a damage floor crossing")
	_damage(unit)
	_check(unit.health <= 0, "A second hit in the same frame has no invented invincibility")
	_check(not unit.statuses.has("lock") and unit.custom_properties.get("_health_lock_triggers", []).is_empty(), "Lethal HP change removes all health locks and stale triggers")
	unit = _unit()
	_buff(unit, "marker", "EBT_NumericalBuff")
	_lock(unit, "lock", 500, 1, 1000, "marker")
	unit.add_buff("lock")
	_damage(unit)
	unit.tick(0.01)
	_check(unit.buff_layers("marker") == 1 and not unit.statuses.has("lock"), "Next frame applies the trigger once and removes an exhausted lock")
	unit = _unit()
	_lock(unit, "a", 500, 1)
	_lock(unit, "b", 500, 1)
	unit.add_buff("a")
	unit.add_buff("b")
	_damage(unit)
	_check(unit.statuses.a.lock_remaining == 0 and unit.statuses.b.lock_remaining == 1, "Equal floors do not consume the second lock after the first already clamps")
	_damage(unit)
	_check(unit.health == 500 and unit.statuses.b.lock_remaining == 0, "The second equal-floor lock protects the next hit")
	unit = _unit()
	_lock(unit, "cap", 100, 2, 600)
	_buff(unit, "heal", "EBT_SpecialBuffHP", {"MaxHpPercentChange": 1000})
	unit.add_buff("cap")
	unit.health = 400
	unit.add_buff("heal")
	_check(unit.health == 600 and unit.statuses.cap.lock_remaining == 2, "Healing obeys the upper cap without consuming finite uses")
	unit.statuses.cap.lock_remaining = 0
	unit.add_buff("heal")
	_check(unit.health == 600, "Exhausted finite locks retain the upper cap until removal")

func _all_health_paths() -> void:
	var unit = _unit()
	_lock(unit, "lock", 500)
	unit.add_buff("lock")
	var dot = _buff(unit, "dot", "EBT_SpecialTriggerRangeDamage")
	dot.merge({"selfOnlyDamage": true, "fixedDamage": 10000, "firstDelay": 0.01, "interval": 1}, true)
	unit.add_buff("dot")
	unit.tick(0.01)
	_check(unit.health == 500, "Self DOT cannot bypass the HP floor")
	unit = _unit()
	_lock(unit, "lock", 500)
	unit.add_buff("lock")
	_buff(unit, "convert", "EBT_SBuffChangeSpecAttributeToOther", {"SourceType": "Hp", "TargetType": "Shield", "ThresholdCurrentPercent": 1000, "SourceCost": 1, "TargetGain": 1})
	unit.add_buff("convert")
	_check(unit.health == 500 and unit.shield == 500, "HP-to-shield conversion uses actual HP spent after locking")
	unit = _unit()
	_buff(unit, "marker", "EBT_NumericalBuff")
	_lock(unit, "lock", 100, -1, 600, "marker")
	_buff(unit, "heal", "EBT_SpecialBuffHP", {"MaxHpPercentChange": 1000})
	unit.health = 400
	unit.add_buff("lock")
	unit.add_buff("heal")
	unit.tick(0.01)
	_check(unit.health == 600 and unit.buff_layers("marker") == 1, "Unlimited upper-cap adjustment also queues the native active trigger")

func _restore_and_refresh() -> void:
	var unit = _unit()
	_buff(unit, "marker", "EBT_NumericalBuff")
	var definition = _lock(unit, "lock", 500, 2, 1000, "marker")
	unit.add_buff("lock")
	_damage(unit)
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(unit.snapshot()))
	var copy = _unit()
	copy._buff_index = unit._buff_index.duplicate(true)
	_check(copy.restore(snapshot), "Snapshot restores finite lock and pending next-frame trigger")
	copy.tick(0.01)
	_check(copy.buff_layers("marker") == 1 and copy.statuses.lock.lock_remaining == 1, "Pending trigger and remaining count survive JSON save/load")
	copy.tick(0.01)
	_check(copy.buff_layers("marker") == 1, "Restored trigger fires only once")
	unit.remove_buff("lock")
	unit.add_buff("lock")
	unit.tick(0.01)
	_check(unit.buff_layers("marker") == 0 and unit.statuses.lock.lock_remaining == 2, "Stale callbacks cannot target a removed and readded lock")
	_damage(unit)
	definition.raw_data.BuffSettingDataList[0].MaxLockCount = 4
	unit._refresh_health_lock(unit.statuses.lock, unit._settings(definition))
	_check(unit.statuses.lock.lock_remaining == 1, "Finite refresh preserves consumption rather than refilling")
	definition.raw_data.BuffSettingDataList[0].MaxLockCount = -1
	unit._refresh_health_lock(unit.statuses.lock, unit._settings(definition))
	_check(unit.statuses.lock.lock_remaining == -1, "Refresh to unlimited restores unlimited sentinel")
	definition.raw_data.BuffSettingDataList[0].MaxLockCount = 3
	unit._refresh_health_lock(unit.statuses.lock, unit._settings(definition))
	_check(unit.statuses.lock.lock_remaining == 3, "Unlimited-to-finite refresh initializes the new remaining limit")
	var legacy = unit.statuses.lock
	legacy.erase("lock_remaining")
	legacy.lock_count = 2
	unit._refresh_health_lock(legacy, unit._settings(definition))
	_check(legacy.lock_remaining == 1, "Legacy saved consumed-count migrates to remaining uses")

func _shields() -> void:
	var unit = _unit()
	unit.add_buff("42300203")
	unit.add_buff("42300203")
	_check(unit.shield == 2000 and not unit.statuses.has("42300203"), "Real lava-dragon shield is a repeatable one-shot, not a retained status")
	unit.add_buff("42300204")
	unit.add_buff("42300204")
	_check(unit.shield == 1932, "Real lava-dragon drain subtracts 3.4 percent maximum HP each application")
	var caster = _unit()
	caster.max_health = 2000
	caster.set_external_attributes({"ShieldEmpower": 500})
	unit.shield = 0
	unit.set_external_attributes({"ShieldEmpower": 9000})
	var definition = _buff(unit, "shield", "EBT_SpecialSheild", {"Attr": "MaxHp", "MulValue": 100, "AddValue": 500, "Mode": "Add"})
	definition.raw_data.AttribSourceType = "Self"
	unit.bind_buff_caster("shield", caster)
	unit.add_buff("shield")
	_check(unit.shield == 150, "Shield scales additive constant by 1/1000, uses caster empowerment, then truncates")
	definition.raw_data.AttribSourceType = "CasterUnit"
	unit.add_buff("shield")
	_check(caster.shield == 300 and unit.shield == 150, "CasterUnit selects caster as both shield recipient and attribute source")
	definition.raw_data.BuffSettingDataList[0].Mode = "Reduce"
	definition.raw_data.BuffSettingDataList[0].MinShieldValue = 220
	unit.add_buff("shield")
	_check(caster.shield == 80, "Shield reduction ignores empowerment and honors a positive minimum")
	definition.raw_data.BuffSettingDataList[0].MaxShieldValue = 30
	unit.add_buff("shield")
	_check(caster.shield == 50, "Shield reduction honors a positive maximum after the minimum")
	_check(not unit.add_buff("shield", -1) and caster.shield == 50, "Removing a one-shot shield cannot apply it again")

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)
