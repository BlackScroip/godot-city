extends SceneTree

const Catalog = preload("res://scripts/domain/catalog.gd")
const Profile = preload("res://scripts/domain/profile.gd")
const Systems = preload("res://scripts/domain/systems.gd")
const Extra = preload("res://scripts/domain/extra_challenges.gd")
const Ads = preload("res://scripts/domain/ad_rewards.gd")
var checks = 0
var failures: Array[String] = []
var catalog

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _systems():
	var s = Systems.new(catalog, Profile.new())
	return s

func _run() -> void:
	catalog = Catalog.new()
	check(catalog.load_all(), "catalog loads")
	check(catalog.rows("ExtraChallengeData").size() == 56, "all 56 source bounties imported")
	check(catalog.rows("RelationshipTokenData").size() == 96, "all 96 token levels imported")
	check(not catalog.find("MaterialData", 50081).is_empty(), "Petra token display material exists")
	for id in range(648001, 648007): check(not catalog.find("AbilityItems", id).is_empty(), "Petra token ability %d exists" % id)
	_test_receive()
	_test_progress_and_claims()
	_test_advertisements()
	_test_persistence()
	var result = {"checks": checks, "failures": failures, "passed": failures.is_empty(), "scope": "Source-backed independent bounties, native admission/deletion/material/advertisement rules; no original APK runtime claim."}
	var file = FileAccess.open("res://reports/extra-challenges-tests.json", FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(result, "\t"))
	print("EXTRA_CHALLENGES_TEST ", JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)

func _test_receive() -> void:
	var s = _systems()
	var b = s.extra_challenges
	s.grant_material(40001, 10)
	check(b.capacity() == 0 and not b.receive().success and s.material(40001) == 10, "locked board cannot spend letters")
	s.profile.data.buildings["5"] = 2
	check(b.capacity() == 6, "level2 has six slots")
	var first = b.receive()
	check(first.success and first.ids.size() == 3 and s.material(40001) == 9, "one letter buys three quests")
	check(b.receive().success and b.entries().size() == 6 and s.material(40001) == 8, "second batch fills capacity")
	check(not b.receive().success and s.material(40001) == 8, "full board cannot consume a letter")
	var deleted = int(first.ids[0])
	check(b.remove(deleted).success and int(s.profile.data.extra_challenges.penalties[str(deleted)]) == 7, "deletion starts seven refill penalty")
	check(not b.remove(deleted).success, "repeat delete rejected")
	var next = b.receive()
	check(next.success and next.ids.size() == 1 and s.material(40001) == 7, "partial capacity buys only one quest with one letter")
	check(not next.ids.has(deleted) and int(s.profile.data.extra_challenges.penalties[str(deleted)]) == 6, "penalized ID excluded and decremented after refill")
	s.profile.data.buildings["5"] = 3
	check(b.capacity() == 9 and b.receive().ids.size() == 3, "level3 expands board to nine")
	s.profile.data.run.active = true
	check(not b.remove(int(b.entries()[0].id)).success and not b.receive().success, "transactions blocked during adventure")
	var limited = _systems()
	limited.profile.data.buildings["5"] = 2
	check(not limited.extra_challenges.receive().success, "empty wallet rejected")
	for row in catalog.rows("ExtraChallengeData"): limited.profile.data.extra_challenges.penalties[str(int(row.id))] = 7
	limited.grant_material(40001, 1)
	check(limited.extra_challenges.receive().success, "native insufficient candidate pool fallback avoids deadlocked board")

func _test_progress_and_claims() -> void:
	var s = _systems()
	s.profile.data.buildings["5"] = 2
	var b = s.extra_challenges
	s.profile.data.extra_challenges.active = {"1001": 0, "1002": 0, "1003": 0, "1022": 0, "1028": 0, "2001": 0}
	s.grant_material(101, 2000)
	check(b.entry(1001).current == 0, "camp rewards do not advance dungeon acquisition")
	s.begin_run(81, 1, 100)
	s.grant_material(101, 999)
	check(b.entry(1001).current == 999 and not b.entry(1001).complete, "source resource amount drives progress")
	s.grant_material(101, 1)
	s.grant_material(102, 1000)
	check(b.entry(1001).complete and b.entry(1002).complete, "source numeric threshold wins over mismatching descriptive text")
	s.effects.dispatch("KillEnemy", "2", "23001")
	check(b.entry(1003).current == 0, "different boss does not advance selected bounty")
	s.effects.dispatch("KillEnemy", "2", "13001")
	s.effects.dispatch("KillEnemy", "2", "13001")
	check(b.entry(1003).complete, "boss IDs matched in param2")
	s.effects.dispatch("GetAbilityItemLoot", "21114")
	check(b.entry(1028).complete, "loot event advances matching bounty")
	b.record_event("XChara_YWeapon_ZDifficulty", "2", "201", "0")
	check(not b.entry(1022).complete, "other character clear ignored")
	b.record_event("XChara_YWeapon_ZDifficulty", "1", "101", "0")
	check(b.entry(1022).complete, "matching character clear accepted")
	check(not b.claim(1001).success, "reward cannot be claimed during adventure")
	s.profile.data.run.active = false
	var wood_before = s.material(801)
	check(b.claim(1001).success and s.material(801) == wood_before + 1, "completed bounty pays configured reward")
	check(not b.claim(1001).success and s.material(801) == wood_before + 1, "repeat reward rejected")
	check(not b.claim(2001).success, "material submission requires all ingredients")
	s.grant_material(10101, 10)
	s.grant_material(10102, 9)
	check(not b.claim(2001).success and s.material(10101) == 10, "insufficient second ingredient spends nothing")
	s.grant_material(10102, 1)
	check(b.claim(2001).success and s.material(10101) == 0 and s.material(10102) == 0, "material claim atomically spends exact quantities")

func _test_advertisements() -> void:
	var s = _systems()
	s.profile.data.buildings["5"] = 3
	var now = [86400 * 20 + 22 * 3600 - 1]
	s.utc_now = func(): return now[0]
	var a = Ads.new(s)
	var receive = {"kind": "extra_challenge_receive", "id": 0}
	check(a.quote(receive).success and s.extra_challenges.entries().is_empty(), "ad quote alone grants nothing")
	check(a.claim(receive, "receive-1").success and s.extra_challenges.entries().size() == 3 and s.material(40001) == 0, "confirmed ad receives three quests without letter")
	check(not a.claim(receive, "receive-1").success and s.extra_challenges.entries().size() == 3, "duplicate ad receipt cannot add more quests")
	s.profile.data.extra_challenges.active = {"2001": 0, "1003": 0}
	var finish = {"kind": "extra_challenge_finish", "id": 2001}
	var before = s.material(801)
	check(a.claim(finish, "finish-1").success and s.material(801) == before + 1 and s.material(10101) == 0, "finish ad grants reward without material submission")
	check(not a.claim(finish, "finish-2").success, "finished ad quest cannot be rewarded again")
	var doubled = {"kind": "extra_challenge_double", "id": 1003}
	check(not a.quote(doubled).success, "double ad requires completed objective")
	s.profile.data.extra_challenges.active["1003"] = 2
	check(a.claim(doubled, "double-1").success and s.material(501) == 20, "double ad applies source reward multiplier")
	s.profile.data.extra_challenges.active = {"2001": 0}
	s.grant_material(10101, 10)
	s.grant_material(10102, 10)
	check(a.claim({"kind": "extra_challenge_double", "id": 2001}, "double-material").success and s.material(10101) == 0, "double material reward still spends submission items")
	for i in range(1, 10):
		s.profile.data.extra_challenges.active.clear()
		check(a.claim(receive, "receive-" + str(i + 1)).success, "independent get-quest quota %d" % i)
	s.profile.data.extra_challenges.active.clear()
	check(not a.quote(receive).success, "get-quest daily limit is ten")
	now[0] -= 86400
	check(not a.quote(receive).success, "clock rollback cannot replenish ad quota")
	now[0] += 86401
	check(a.quote(receive).success, "ad quota resets at 06:00 China")
	check(not a.claim(receive, "receive-1").success, "prior-day duplicate receipt remains invalid")

func _test_persistence() -> void:
	var s = _systems()
	s.profile.data.buildings["5"] = 3
	s.grant_material(40001, 10)
	s.extra_challenges.receive()
	s.extra_challenges.remove(int(s.extra_challenges.entries()[0].id))
	var serialized = JSON.parse_string(JSON.stringify(s.profile.data))
	var p = Profile.new()
	check(p.restore(serialized), "bounties survive validated JSON restore")
	var restored = Systems.new(catalog, p)
	check(restored.profile.data.extra_challenges == s.profile.data.extra_challenges, "active progress and penalty state preserved")
	check(restored.extra_challenges.receive().ids == s.extra_challenges.receive().ids, "saved bounty random state restores deterministic next draw")
	var state = s.profile.data.extra_challenges.duplicate(true)
	check(Extra.validate_state(state), "generated bounty save valid")
	state.active["1001"] = -1
	check(not Extra.validate_state(state), "negative progress rejected")
	state.active["1001"] = 0
	state.penalties["1001"] = 8
	check(not Extra.validate_state(state), "invalid penalty rejected")
	state.penalties["1001"] = 1
	state.rng_state = 0
	check(not Extra.validate_state(state), "zero RNG state rejected")
