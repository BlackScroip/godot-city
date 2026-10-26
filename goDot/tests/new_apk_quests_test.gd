extends SceneTree

const Catalog = preload("res://scripts/domain/catalog.gd")
const Profile = preload("res://scripts/domain/profile.gd")
const Systems = preload("res://scripts/domain/systems.gd")
var checks = 0
var failures: Array[String] = []
var catalog

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _run() -> void:
	catalog = Catalog.new()
	check(catalog.load_all(), "new source catalogs load")
	_test_migrated_tasks()
	_test_legacy_conditions()
	_test_enemy_types_and_chaos()
	var result = {"checks": checks, "failures": failures, "passed": failures.is_empty(), "scope": "New APK embedded quest conditions, changed economic thresholds, legacy condition API, cycle guards, enemy categories and per-character chaos gates. Static evidence and domain tests; no original APK runtime parity claim."}
	var report = FileAccess.open("res://reports/new-apk-quests-tests.json", FileAccess.WRITE)
	if report:
		report.store_string(JSON.stringify(result, "\t"))
		report.close()
	print("NEW_APK_QUESTS_TEST ", JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)

func _put(table: String, row: Dictionary) -> void:
	catalog.tables[table].append(row)
	catalog._indices[table][str(int(row.id))] = row

func _test_migrated_tasks() -> void:
	var p = Profile.new()
	var s = Systems.new(catalog, p)
	check(catalog.rows("SubAchieveData").size() == 271 and catalog.rows("AchieveData").size() == 68, "new APK includes thirty extra tasks and six extra groups")
	check(catalog.find("SubAchieveData", 40003).has("unlock_data"), "new task conditions are embedded")
	s.grant_material(101, 3000)
	check(not s.task_status(40003).complete and s.task_status(40003).current == 0, "camp gold rewards do not count as dungeon gold collection")
	s.begin_run(321, 1, 100)
	s.grant_material(101, 2999)
	check(not s.task_status(40003).complete and s.task_status(40003).required == 3000, "new gold task requires three thousand cumulative dungeon gold")
	s.grant_material(101, 1)
	s.end_run(false)
	check(s.task_status(40003).complete and s.is_unlocked(4040003), "embedded and global gold conditions agree after settlement")
	s.grant_material(102, 2999)
	check(not s.task_status(40102).complete and s.task_status(40102).required == 3000, "new magic task requires three thousand cumulative essence")
	s.grant_material(102, 1)
	check(s.task_status(40102).complete and s.is_unlocked(4040102), "magic threshold uses cumulative acquisition")
	s.grant_material(10101, 2)
	var gold = s.material(101)
	check(s.claim_task(10001).success and s.material(101) == gold + 25, "embedded material task grants its configured reward")
	check(not s.claim_task(10001).success and s.material(101) == gold + 25, "embedded task reward cannot be claimed twice")
	check(s.stat("adventure:get:101") == 3000, "camp quest payout does not advance dungeon gold history")
	p.data.character_levels["7"] = 8
	check(s.task_status(57006).complete and s.task_status(57006).required == 8, "new dragon knight task sees existing character levels")
	s.set_record("weapon:805", 5)
	check(s.task_status(52805).complete, "new warrior weapon task sees existing weapon history")
	var restored = Profile.new()
	check(restored.restore(JSON.parse_string(JSON.stringify(p.data))), "migrated quest state survives JSON restore")
	var resumed = Systems.new(catalog, restored)
	check(resumed.task_status(10001).claimed and not resumed.claim_task(10001).success, "saved old task IDs retain claim guards with embedded conditions")

func _test_legacy_conditions() -> void:
	var p = Profile.new()
	var s = Systems.new(catalog, p)
	_put("UnlockData", {"id": 930001, "unlock_desc": "Legacy material condition", "unlock_condition_type": 30, "unlock_param1": 10101, "unlock_param2": 2, "unlock_param3": 0})
	_put("SubAchieveData", {"id": 930001, "group_id": 100, "unlock_data_id": 930001, "reward_get_materials": "101:1"})
	s.grant_material(10101, 2)
	check(s.is_unlocked(930001) and s.task_status(930001).complete, "legacy referenced task and public unlock API remain supported")
	_put("SubAchieveData", {"id": 930002, "group_id": 100, "unlock_data_id": 930001, "unlock_data": {"id": 930002, "unlock_condition_type": 401, "unlock_param1": 1, "unlock_param2": 8}, "reward_get_materials": "101:1"})
	check(not s.task_status(930002).complete, "embedded condition takes precedence over a stale legacy reference")
	_put("UnlockData", {"id": 930003, "unlock_condition_type": 9001, "unlock_param1": 930003})
	check(not s.is_unlocked(930003) and not s.unlock_progress(930003).complete, "recursive global condition remains fail closed")
	_put("SubAchieveData", {"id": 930004, "group_id": 100, "unlock_data": {"id": 930004, "unlock_condition_type": 9002, "unlock_param1": 930003, "unlock_param2": 930001}, "reward_get_materials": "101:1"})
	check(s.task_status(930004).complete, "embedded OR evaluates valid alternative after a cyclic branch")
	_put("SubAchieveData", {"id": 930005, "group_id": 100, "unlock_data": {"id": 930005, "unlock_condition_type": 987654}, "reward_get_materials": "101:1"})
	_put("SubAchieveData", {"id": 930006, "group_id": 100, "reward_get_materials": "101:1"})
	check(not s.task_status(930005).complete and not s.task_status(930006).complete, "unsupported and missing task conditions cannot grant rewards")
	check(s.is_unlocked(0) and s.unlock_progress(0).complete, "zero global unlock still denotes no condition")

func _test_enemy_types_and_chaos() -> void:
	var p = Profile.new()
	var s = Systems.new(catalog, p)
	var normal_ids: Array = []
	var elite_id = 0
	for enemy in catalog.rows("EnemyData"):
		if str(enemy.get("enemy_rate", "")) == "Normal" and normal_ids.size() < 2: normal_ids.append(int(enemy.id))
		if str(enemy.get("enemy_rate", "")) == "Elite": elite_id = int(enemy.id)
	check(normal_ids.size() == 2 and elite_id > 0, "enemy categories exist for native type condition")
	if normal_ids.size() != 2 or elite_id == 0: return
	s.set_record("kill:" + str(normal_ids[0]), 40)
	s.set_record("kill:" + str(normal_ids[1]), 59)
	s.set_record("kill:" + str(elite_id), 100)
	check(not s.is_unlocked(601002) and s.unlock_progress(601002).current == 99, "type zero counts all normal enemy IDs and excludes elites")
	s.record_kill(normal_ids[0])
	check(s.is_unlocked(601002) and s.unlock_progress(601002).required == 100, "new condition accepts omitted zero parameters and cumulative kills")
	s.set_record("chaos:clear:1", 9)
	s.set_record("chaos:selected:1", 10)
	check(not s.is_unlocked(10600) and s.is_unlocked(10601), "cleared and selected chaos conditions are distinct")
	s.set_record("chaos:clear:1", 10)
	check(s.is_unlocked(10600) and s.unlock_progress(10600).current == 10, "cleared chaos ten reaches native threshold")
	p.data.selected_character = 2
	check(not s.is_unlocked(10600) and not s.is_unlocked(10601), "chaos unlock conditions follow the current character")
