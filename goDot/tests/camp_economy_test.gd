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
	var before = JSON.stringify(p.data)
	check(not s.start_work(101).success and JSON.stringify(p.data) == before, "dispatch requires repaired rune stone")
	p.data.buildings["6"] = 1
	check(s.work_status(101).can_start and not s.work_status(107).can_start, "normal rune stone locks advanced voucher expedition")
	p.data.buildings["6"] = 2
	s.begin_run(600, 1, 100)
	s.complete_node("new-apk-work-unlock", 2010000, 2, true)
	s.end_run(false)
	p.data.materials["101"] = 0
	var quote = s.work_status(107)
	check(quote.price == {"101": 50} and quote.reward == {"id": 501, "amount": 3} and quote.duration_seconds == 1200 and quote.queue_max == 6, "new APK voucher expedition has six stored cycles and fifty gold per claim")
	check(s.start_work(107).success and s.material(101) == 0 and p.data.partners.is_empty(), "work starts without materials or an owned idle partner")
	before = JSON.stringify(p.data)
	check(not s.start_work(101).success and not s.start_work(107).success and JSON.stringify(p.data) == before, "only one global assignment can run")
	now += 59
	check(s.work_status(107).next_claim_seconds == 1200, "offline work accrues only complete source minutes")
	now += 1
	check(s.work_status(107).next_claim_seconds == 1140, "a completed minute advances work once")
	now += 1140
	before = JSON.stringify(p.data)
	check(s.work_status(107).completed_quantity == 1 and not s.collect_work(107).success and JSON.stringify(p.data) == before, "completed work waits for claim materials without losing progress")
	s.grant_material(101, 150)
	now += 1500
	var restored = Profile.new()
	check(restored.restore(JSON.parse_string(JSON.stringify(p.data))), "dispatch order survives JSON reload")
	var resumed = Systems.new(catalog, restored)
	resumed.utc_now = func(): return now
	check(resumed.work_status(107).claimable_quantity == 2 and resumed.work_status(107).next_claim_seconds == 900, "offline progress retains two outputs and five partial minutes")
	resumed.begin_run(999, 1, 100)
	before = JSON.stringify(restored.data)
	check(not resumed.collect_work(107).success and JSON.stringify(restored.data) == before, "camp rewards cannot leak into adventure collection statistics")
	resumed.end_run(false)
	var replay = {"success": false}
	var listener = func(event):
		if event.type == "resource_gained": replay.success = resumed.collect_work(107).success
	resumed.gameplay_event.connect(listener)
	check(resumed.collect_work(107).success and resumed.material(501) == 6 and resumed.material(101) == 50 and not replay.success, "claim deducts cost for both outputs and rejects reentrant delivery")
	resumed.gameplay_event.disconnect(listener)
	check(not resumed.collect_work(107).success and resumed.stat("work:finished") == 2, "completed outputs cannot be replayed")
	check(not resumed.work_status(107).order.is_empty() and resumed.work_status(107).next_claim_seconds == 900, "claim keeps assignment and fractional progress")
	check(resumed.upgrade_character(1).success and resumed.material(501) == 5, "collected vouchers fund permanent character growth")
	now += 900
	resumed.grant_material(101, 10000)
	resumed.grant_material(107, 10000)
	check(resumed.upgrade_work(107).success and resumed.work_status(107).reward.amount == 5, "active work can upgrade before accumulated outputs are claimed")
	var vouchers = resumed.material(501)
	var gold = resumed.material(101)
	check(resumed.collect_work(107).success and resumed.material(501) == vouchers + 5 and resumed.material(101) == gold - 100, "stored work uses current upgraded reward and claim cost")
	check(resumed.stop_work(107).success, "collected work can stop")
	check(resumed.start_work(107).success, "another assignment can start")
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
	check(quote.duration_seconds == 600 and quote.queue_max == 24 and quote.daily_limit == 48, "Ultra halves duration, stores twenty-four outputs and permits forty-eight daily claims")
	gold = resumed.material(101)
	check(resumed.start_work(107).success and resumed.material(101) == gold and resumed.work_status(107).quantity == 24, "Ultra work also starts without a fee")
	now += 1500
	check(resumed.work_status(107).claimable_quantity == 2 and resumed.work_status(107).next_claim_seconds == 300, "partial Ultra cycles are available before storage fills")
	var discarded = Profile.new()
	check(discarded.restore(JSON.parse_string(JSON.stringify(restored.data))), "completed assignment snapshot restores")
	var discarded_systems = Systems.new(catalog, discarded)
	discarded_systems.utc_now = func(): return now
	check(discarded_systems.stop_work(107).success and discarded.data.work.is_empty() and discarded_systems.material(501) == resumed.material(501), "confirmed stop discards completed and fractional progress without paying rewards")
	vouchers = resumed.material(501)
	check(resumed.collect_work(107).success and resumed.material(501) == vouchers + 10 and resumed.work_status(107).next_claim_seconds == 300, "partial claim preserves five remaining progress minutes")
	resumed.begin_run(1001, 1, 100)
	var bonus = resumed.advance_work_from_adventure(3, 2, false, "run-one")
	check(bonus.success and bonus.minutes == 8 and resumed.work_status(107).completed_quantity == 1 and resumed.work_status(107).next_claim_seconds == 420, "loss settlement adds depth plus completed-region minutes to remaining work")
	before = JSON.stringify(restored.data)
	check(not resumed.advance_work_from_adventure(3, 2, false, "run-one-retry").success and JSON.stringify(restored.data) == before, "settlement acceleration cannot repeat under another caller key")
	resumed.end_run(false)
	resumed.begin_run(1002, 1, 100)
	bonus = resumed.advance_work_from_adventure(2, 5, true, "run-two")
	check(bonus.success and bonus.minutes == 27, "victory settlement includes final region work progress")
	resumed.end_run(true)
	var queued_restore = Profile.new()
	check(queued_restore.restore(JSON.parse_string(JSON.stringify(restored.data))) and int(queued_restore.data.work[0].quantity) == 24, "new queue and daily counters survive reload")
	now += 1000000
	check(resumed.work_status(107).claimable_quantity == 24, "long offline time is capped to twenty-four stored outputs")
	vouchers = resumed.material(501)
	check(resumed.collect_work(107).success and resumed.material(501) == vouchers + 120 and resumed.work_status(107).completed_quantity == 0, "capped payout discards overflow time instead of refilling storage immediately")
	resumed.add_work_progress(107, 24000)
	check(resumed.collect_work(107).success and resumed.work_status(107).daily_remaining == 0, "second full Ultra batch reaches forty-eight global daily outputs")
	resumed.add_work_progress(107, 24000)
	before = JSON.stringify(restored.data)
	check(not resumed.collect_work(107).success and JSON.stringify(restored.data) == before and resumed.work_status(107).completed_quantity == 24, "daily cap preserves stored outputs without mutating wallet")
	var saved_day = int(restored.data.work_claims.day)
	now = (saved_day + 1) * 86400 + 22 * 3600 - 1
	check(resumed.work_status(107).daily_remaining == 0, "daily claims remain exhausted one second before 22:00 UTC")
	now += 1
	check(resumed.work_status(107).daily_remaining == 48 and resumed.collect_work(107).success, "22:00 UTC resets the daily limit while retaining stored output")
	now -= 86400
	check(resumed.work_status(107).daily_remaining == 24, "clock rollback cannot restore a spent daily quota")
	var invalid = restored.data.duplicate(true)
	invalid.work_claims.count = -1
	check(not Profile.new().restore(invalid), "negative saved daily claims are rejected")
	var legacy = Profile.new()
	legacy.data.buildings["6"] = 2
	legacy.data.materials["101"] = 0
	legacy.data.work = [{"work_id": 107, "partner_id": 11001, "started_utc": now - 1200, "due_utc": now, "material_id": 501, "reward": 3}]
	check(Profile.new().restore(JSON.parse_string(JSON.stringify(legacy.data))), "old prepaid single-output save remains readable")
	var migrated = Systems.new(catalog, legacy)
	migrated.utc_now = func(): return now
	check(migrated.collect_work(107).success and migrated.material(501) == 3 and migrated.material(101) == 0 and legacy.data.work[0].economy_version == 2, "legacy prepaid first output is credited without charging twice")
	migrated.begin_run(9999, 1, 100)
	legacy.data.work.clear()
	check(migrated.advance_work_from_adventure(10, 5, true, "no-work").minutes == 0, "settlement cannot report work acceleration without an assignment")

func _test_currency_transactions() -> void:
	var p = Profile.new()
	var s = Systems.new(catalog, p)
	var before = JSON.stringify(p.data)
	check(not s.spend({101: 60, "101": 60}) and JSON.stringify(p.data) == before, "mixed integer and string currency keys cannot overspend")
	check(not s.spend({"101": -1}) and not s.spend({"101": 0.5}) and not s.spend({"invalid": 0}) and JSON.stringify(p.data) == before, "invalid currency quantities never mutate balance")
	check(s.spend({101: 30, "101": 20}) and s.material(101) == 50 and s.stat("spent:101") == 50, "canonical currency transaction accounts for combined keys")
