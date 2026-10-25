extends SceneTree

const Catalog = preload("res://scripts/domain/catalog.gd")
const Profile = preload("res://scripts/domain/profile.gd")
const Systems = preload("res://scripts/domain/systems.gd")
var checks = 0
var failures: Array[String] = []
var catalog
var now = 100000

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _run() -> void:
	catalog = Catalog.new()
	check(catalog.load_all(), "source catalogs load")
	_test_construction()
	_test_vouchers()
	_test_dispatch()
	_test_currency_transactions()
	var result = {"checks": checks, "failures": failures, "passed": failures.is_empty(), "scope": "Domain transactions, all construction stage prices, feature prerequisites, voucher breakthrough, offline dispatch, continuing assignments, storage queue caps, settlement acceleration, idempotence and save validation. Does not establish APK runtime or visual parity."}
	var report = FileAccess.open("res://reports/camp-economy-tests.json", FileAccess.WRITE)
	if report:
		report.store_string(JSON.stringify(result, "\t"))
		report.close()
	print("CAMP_ECONOMY_TEST ", JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)

func _test_construction() -> void:
	var p = Profile.new()
	var s = Systems.new(catalog, p)
	var before = JSON.stringify(p.data)
	check(not s.upgrade_building(3).success and JSON.stringify(p.data) == before, "unfunded construction is atomic")
	var quote = s.building_status(2)
	check(not quote.can_upgrade and quote.price == {"101": 100} and "探索1次" in quote.reason and "0 / 1" in quote.reason, "guild prerequisite reports exact progress and cost")
	check(not s.camp_feature_status("talents").available, "fresh guild talent facility is locked")
	s.begin_run(7, 1, 100)
	before = JSON.stringify(p.data)
	check(not s.upgrade_building(2).success and JSON.stringify(p.data) == before, "building cannot be changed during an adventure")
	s.end_run(false)
	check(s.upgrade_building(2).success and s.material(101) == 0, "first adventure unlocks guild for initial one hundred gold")
	check(s.camp_feature_status("talents").available and not s.camp_feature_status("gold_apple").available, "each construction stage unlocks its specific functionality")
	s.grant_material(101, 100000)
	while s.stat("runs") < 5:
		s.begin_run(100 + s.stat("runs"), 1, 100)
		s.end_run(false)
	for row in catalog.rows("Buildings"):
		if int(row.max_level) == 0: continue
		while s.rank(p.data.buildings, row.id) < int(row.max_level):
			quote = s.building_status(int(row.id))
			var gold = s.material(101)
			check(quote.can_upgrade and s.upgrade_building(int(row.id)).success, "all configured construction stages are reachable: %d/%d" % [int(row.id), int(quote.level) + 1])
			check(s.material(101) == gold - int(quote.price.get("101", 0)), "construction deducts exact stage gold: %d" % int(row.id))
		before = JSON.stringify(p.data)
		check(not s.upgrade_building(int(row.id)).success and JSON.stringify(p.data) == before, "completed facility cannot charge again: %d" % int(row.id))
	var restored = Profile.new()
	check(restored.restore(JSON.parse_string(JSON.stringify(p.data))), "construction survives JSON restore")
	var resumed = Systems.new(catalog, restored)
	check(resumed.camp_feature_status("weapon_upgrade").available and resumed.camp_feature_status("work_precious").available, "restored stage gates remain open")
	check(not resumed.building_status(9999).can_upgrade, "invalid building is rejected")

func _test_vouchers() -> void:
	var p = Profile.new()
	var s = Systems.new(catalog, p)
	check(s.character_upgrade_status(1).price == {"501": 1, "503": 0}, "first character level costs one voucher")
	var before = JSON.stringify(p.data)
	check(not s.upgrade_character(1).success and JSON.stringify(p.data) == before, "unfunded character upgrade preserves state")
	s.grant_material(501, 1000)
	for stage in 5: check(s.upgrade_character(1).success, "owned starter can grow without recruitment building")
	var quote = s.character_upgrade_status(1)
	check(quote.price == {"501": 50, "503": 1}, "level six breakthrough costs configured vouchers and rainbow cube")
	before = JSON.stringify(p.data)
	check(not s.upgrade_character(1).success and JSON.stringify(p.data) == before, "missing cube never consumes vouchers")
	s.grant_material(503, 1)
	var vouchers = s.material(501)
	check(s.upgrade_character(1).success and s.material(501) == vouchers - 50 and s.material(503) == 0, "breakthrough spends both resources together")
	check(s.resource_summary().any(func(row): return row.id == 501 and row.amount == s.material(501) and row.spent == 126), "resource ledger links voucher balance and upgrade expenditure")

func _test_dispatch() -> void:
	var p = Profile.new()
	var s = Systems.new(catalog, p)
	s.utc_now = func(): return now
	s.grant_material(101, 100000)
	s.record_kill(11001)
	for index in 5:
		s.begin_run(600 + index, 1, 100)
		s.complete_node("camp-job-unlock-" + str(index), 2010000, 2, true)
		s.end_run(false)
	for stage in 2: s.upgrade_building(4)
	check(s.unlock_partner(11001).success, "monster defeat and stone altar unlock partner")
	s.record_kill(11002)
	check(s.unlock_partner(11002).success, "second partner is available for global assignment regression")
	var before = JSON.stringify(p.data)
	check(not s.start_work(101, 11001).success and JSON.stringify(p.data) == before, "dispatch requires repaired rune stone")
	s.upgrade_building(6)
	check(s.work_status(101).can_start and not s.work_status(107).can_start, "normal rune stone locks advanced voucher expedition")
	s.upgrade_building(6)
	var quote = s.work_status(107)
	check(quote.price == {"101": 50} and quote.reward == {"id": 501, "amount": 3} and quote.duration_seconds == 1200, "voucher expedition quote uses source currency reward and minutes")
	var gold = s.material(101)
	check(s.start_work(107, 11001).success and s.material(101) == gold - 50, "voucher expedition spends exactly fifty gold")
	before = JSON.stringify(p.data)
	check(not s.start_work(101, 11002).success and JSON.stringify(p.data) == before, "native single active assignment blocks another available partner")
	check(not s.start_work(101, 11001).success and not s.upgrade_work(107).success and JSON.stringify(p.data) == before, "busy partner and in-flight upgrade are atomic failures")
	now += 1199
	check(not s.collect_work(107).success and s.work_status(107).remaining_seconds == 1, "reward cannot be collected before timer")
	var restored = Profile.new()
	check(restored.restore(JSON.parse_string(JSON.stringify(p.data))), "dispatch order survives JSON reload")
	var resumed = Systems.new(catalog, restored)
	resumed.utc_now = func(): return now
	now += 1
	check(resumed.work_status(107).ready and int(restored.data.work[0].reward) == 3, "offline due time and snapshotted payout survive reload")
	resumed.begin_run(999, 1, 100)
	before = JSON.stringify(restored.data)
	check(not resumed.collect_work(107).success and JSON.stringify(restored.data) == before, "camp rewards cannot leak into adventure collection statistics")
	resumed.end_run(false)
	var replay = {"success": false}
	var listener = func(event):
		if event.type == "resource_gained": replay.success = resumed.collect_work(107).success
	resumed.gameplay_event.connect(listener)
	check(resumed.collect_work(107).success and resumed.material(501) == 3 and not replay.success, "dispatch pays once even when reward listeners reenter collection")
	resumed.gameplay_event.disconnect(listener)
	check(not resumed.collect_work(107).success and resumed.stat("work:finished") == 1, "completed order cannot be replayed")
	check(not resumed.work_status(107).order.is_empty() and resumed.work_status(107).remaining_seconds == 1200, "collection retains assignment and restarts progress without another charge")
	check(resumed.upgrade_character(1).success and resumed.material(501) == 2, "collected dispatch vouchers immediately upgrade owned character")
	check(resumed.stop_work(107).success, "stopping collected assignment releases partner")
	check(resumed.upgrade_work(107).success and resumed.work_status(107).reward.amount == 5, "job upgrade improves next payout")
	check(resumed.start_work(107, 11001).success, "freed partner can be sent again")
	var corrupt = restored.data.duplicate(true)
	corrupt.work.append(corrupt.work[0].duplicate(true))
	check(not Profile.new().restore(corrupt), "duplicate saved orders are rejected")
	corrupt = restored.data.duplicate(true)
	corrupt.work[0].reward = -1
	check(not Profile.new().restore(corrupt), "invalid saved payout is rejected")
	corrupt = restored.data.duplicate(true)
	corrupt.work[0].erase("due_utc")
	check(not Profile.new().restore(corrupt), "incomplete saved order is rejected")
	resumed.stop_work(107)
	resumed.set_blessing_mode(2)
	quote = resumed.work_status(107)
	check(quote.duration_seconds == 600 and quote.queue_max == 5, "native blessing halves work time and ultra stores five results")
	gold = resumed.material(101)
	check(resumed.start_work(107, 11001).success and resumed.material(101) == gold - 100 and resumed.work_status(107).quantity == 5, "ultra assignment automatically stores five results and pays start materials once")
	now += 1200
	check(resumed.work_status(107).claimable_quantity == 2 and resumed.work_status(107).ready, "two completed cycles are claimable before five-result storage fills")
	check(not resumed.stop_work(107).success, "stop cannot discard completed unclaimed rewards")
	var vouchers = resumed.material(501)
	check(resumed.collect_work(107).success and resumed.material(501) == vouchers + 10 and resumed.work_status(107).remaining_seconds == 3000, "partial queue claim pays completed cycles and restarts native accumulation")
	resumed.begin_run(1001, 1, 100)
	var bonus = resumed.advance_work_from_adventure(3, 2, false, "run-one")
	check(bonus.success and bonus.minutes == 8 and resumed.work_status(107).next_claim_seconds == 120, "loss settlement uses depth plus completed-region minutes")
	before = JSON.stringify(restored.data)
	check(not resumed.advance_work_from_adventure(3, 2, false, "run-one-retry").success and JSON.stringify(restored.data) == before, "settlement acceleration cannot repeat under another caller key")
	resumed.end_run(false)
	resumed.begin_run(1002, 1, 100)
	bonus = resumed.advance_work_from_adventure(2, 5, true, "run-two")
	check(bonus.success and bonus.minutes == 27, "victory settlement includes final region work progress")
	resumed.end_run(true)
	var queued_restore = Profile.new()
	check(queued_restore.restore(JSON.parse_string(JSON.stringify(restored.data))) and int(queued_restore.data.work[0].quantity) == 5, "queued assignment and settlement guard survive reload")
	now += 1000000
	check(resumed.work_status(107).claimable_quantity == 5, "long offline time is capped to five stored outputs")
	vouchers = resumed.material(501)
	check(resumed.collect_work(107).success and resumed.material(501) == vouchers + 25, "offline queue payout is capped and uses snapshotted upgraded reward")

func _test_currency_transactions() -> void:
	var p = Profile.new()
	var s = Systems.new(catalog, p)
	var before = JSON.stringify(p.data)
	check(not s.spend({101: 60, "101": 60}) and JSON.stringify(p.data) == before, "mixed integer and string currency keys cannot overspend")
	check(not s.spend({"101": -1}) and not s.spend({"101": 0.5}) and not s.spend({"invalid": 0}) and JSON.stringify(p.data) == before, "invalid currency quantities never mutate balance")
	check(s.spend({101: 30, "101": 20}) and s.material(101) == 50 and s.stat("spent:101") == 50, "canonical currency transaction accounts for combined keys")
