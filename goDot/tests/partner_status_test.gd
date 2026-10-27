extends SceneTree

const Catalog = preload("res://scripts/domain/catalog.gd")
const Profile = preload("res://scripts/domain/profile.gd")
const Systems = preload("res://scripts/domain/systems.gd")
const Skills = preload("res://scripts/domain/partner_skills.gd")
var checks := 0
var failures: Array[String] = []
var catalog

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _fresh():
	var s = Systems.new(catalog, Profile.new())
	s.profile.data.buildings["4"] = 2
	return s

func _run() -> void:
	catalog = Catalog.new()
	check(catalog.load_all(), "catalog loads")
	_test_catalog_queries()
	_test_growth_and_equipment()
	_test_admin_and_unknown()
	_test_reentrant_upgrade()
	var report = {"checks": checks, "failures": failures, "passed": failures.is_empty(), "source_rows": catalog.rows("MonsterPartnerData").size()}
	FileAccess.open("res://reports/partner-status-tests.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("PARTNER_STATUS_TEST ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func _test_catalog_queries() -> void:
	var s = _fresh()
	var skills = Skills.new(s)
	var count := 0
	for row in catalog.rows("MonsterPartnerData"):
		if bool(row.get("is_admin_only", false)): continue
		count += 1
		var id = int(row.id)
		var before = JSON.stringify(s.profile.data)
		var status = s.partner_status(id)
		check(before == JSON.stringify(s.profile.data), "status query does not mutate save " + str(id))
		check(status.level == 0 and status.max_level == 4 and not status.unlocked and not status.can_upgrade and not status.can_equip, "source partner has three paid growth milestones " + str(id))
		var skill = skills.definition(id, 1)
		check(status.skill_description == str(skill.get("description", row.get("resonance_skill_description", ""))) and status.skills == skill, "source skill description and definition " + str(id))
		check(not status.skill_unlocked, "active altar needs research level3 " + str(id))
	check(count == 39, "all39 shipped nonadmin partner rows queried")
	s.profile.data.buildings["4"] = 3
	check(s.partner_status(13001).skill_unlocked and not s.partner_status(13001).skills.is_empty(), "research level3 exposes boss support skill")

func _test_growth_and_equipment() -> void:
	var s = _fresh()
	var original = JSON.stringify(s.profile.data)
	check(not s.unlock_partner(11001).success and original == JSON.stringify(s.profile.data), "unlock fails without required kills")
	for kill in 9: s.record_kill(11001)
	check(not s.partner_status(11001).can_unlock, "nine kills below ten threshold")
	s.record_kill(11001)
	s.profile.data.buildings["4"] = 1
	check(not s.partner_status(11001).can_unlock, "research level1 blocks partner unlock")
	s.profile.data.buildings["4"] = 2
	check(s.unlock_partner(11001).success and s.partner_status(11001).level == 1, "tenth kill unlocks at base rank1")
	check(not s.unlock_partner(11001).success, "repeat unlock rejected")
	check(s.partner_status(11001).price == {"101": 100, "10101": 1, "10102": 1}, "first paid rank exact source materials")
	var before = JSON.stringify(s.profile.data)
	check(not s.upgrade_partner(11001).success and before == JSON.stringify(s.profile.data), "missing growth material does not spend gold")
	for id in [101, 10101, 10102, 107]: s.grant_material(id, 10000)
	for tier in range(1, 4):
		var state = s.partner_status(11001)
		check(state.price == {"101": 100 * tier, "10101": tier, "10102": tier}, "source growth fee " + str(tier))
		var gold = s.material(101)
		var fiber = s.material(10101)
		check(s.upgrade_partner(11001).success and s.material(101) == gold - 100 * tier and s.material(10101) == fiber - tier, "growth consumes exact quote " + str(tier))
	var maximum = s.partner_status(11001)
	check(maximum.level == 4 and maximum.max_level == 4 and not maximum.can_upgrade and maximum.price.is_empty(), "fourth rank is max with no next fee")
	before = JSON.stringify(s.profile.data)
	check(not s.upgrade_partner(11001).success and before == JSON.stringify(s.profile.data), "max rank does not spend resources")
	check(s.unlock_partner(13001).success and s.partner_status(13001).price == {"101": 300, "10101": 2, "10102": 2, "107": 5}, "boss partner price includes essence")
	check(s.equip_partner(11001).success and s.equip_partner(13001).success and s.profile.data.equipped_partners == [13001], "single equipment slot replaces previous partner")
	s.profile.data.work = [{"partner_id": 11001}]
	check(not s.partner_status(11001).can_equip and not s.equip_partner(11001).success, "legacy dispatched partner cannot be equipped")
	s.profile.data.work = []
	check(s.unequip_partner(13001).success and s.profile.data.equipped_partners.is_empty(), "equipped partner can be removed")
	check(s.equip_partner(13001).success, "partner can be re-equipped")
	var p = Profile.new()
	check(p.restore(JSON.parse_string(JSON.stringify(s.profile.data))), "growth equipment wallet save restores")
	var resumed = Systems.new(catalog, p)
	check(resumed.partner_status(11001).level == 4 and resumed.partner_status(13001).equipped and resumed.partner_status(13001).price == s.partner_status(13001).price, "reload retains maxrank equipment and next fee")
	check(resumed.begin_run(9102, 1, 100).success, "run fixture starts")
	before = JSON.stringify(p.data)
	check(not resumed.partner_status(13001).can_upgrade and not resumed.partner_status(13001).can_equip, "active run quotes block camp actions")
	check(not resumed.unlock_partner(23001).success and not resumed.upgrade_partner(13001).success and not resumed.equip_partner(11001).success and not resumed.unequip_partner(13001).success, "active run rejects all partner mutations")
	check(before == JSON.stringify(p.data), "blocked adventure actions leave save untouched")

func _test_admin_and_unknown() -> void:
	var row = catalog.find("MonsterPartnerData", 11001).duplicate(true)
	row.id = 999001
	row.is_admin_only = true
	row.unlock_need_kill_count = 0
	catalog.tables.MonsterPartnerData.append(row)
	catalog._indices.MonsterPartnerData["999001"] = row
	var s = _fresh()
	check(not s.partner_status(999001).can_unlock and not s.unlock_partner(999001).success, "admin source rows cannot unlock")
	s.profile.data.partners["999001"] = 1
	s.grant_material(10101, 5)
	s.grant_material(10102, 5)
	check(not s.partner_status(999001).can_upgrade and not s.partner_status(999001).can_equip and not s.upgrade_partner(999001).success and not s.equip_partner(999001).success, "legacy-owned admin row remains blocked")
	check(not s.unlock_partner(999999).success and not s.upgrade_partner(999999).success and not s.equip_partner(999999).success, "unknown partner IDs fail closed")
	catalog.tables.MonsterPartnerData.erase(row)
	catalog._indices.MonsterPartnerData.erase("999001")

func _test_reentrant_upgrade() -> void:
	var s = _fresh()
	for id in [101, 10101, 10102, 107]: s.grant_material(id, 1000)
	s.unlock_partner(13001)
	s.unlock_partner(23001)
	s.equip_partner(13001)
	var attempts: Array = []
	var attempt = func():
		attempts.append(s.upgrade_partner(13001).success)
		attempts.append(s.unlock_partner(33001).success)
		attempts.append(s.equip_partner(23001).success)
		attempts.append(s.unequip_partner(13001).success)
	var listener = func(event):
		if event.type == "resource_spent": attempt.call()
	s.gameplay_event.connect(listener)
	s.changed.connect(attempt)
	var gold = s.material(101)
	var essence = s.material(107)
	check(s.upgrade_partner(13001).success, "outer partner upgrade succeeds")
	s.gameplay_event.disconnect(listener)
	s.changed.disconnect(attempt)
	check(attempts.size() >= 8 and not attempts.has(true), "resource and changed listeners cannot reenter partner mutations")
	check(s.partner_status(13001).level == 2 and s.material(101) == gold - 300 and s.material(107) == essence - 5 and s.profile.data.equipped_partners == [13001], "reentrant upgrade commits one rank and one charge")
	check(s.upgrade_partner(13001).success and s.partner_status(13001).level == 3, "partner transaction lock releases after commit")
