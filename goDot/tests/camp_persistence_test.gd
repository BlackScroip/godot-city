extends SceneTree

const Profile = preload("res://scripts/domain/profile.gd")
const Store = preload("res://scripts/save_store.gd")
const Catalog = preload("res://scripts/domain/catalog.gd")
const Systems = preload("res://scripts/domain/systems.gd")
const Ads = preload("res://scripts/domain/ad_rewards.gd")
var checks := 0
var failures: Array[String] = []
var path := ""
var now := 100 * 86400 + 22 * 3600 - 1
var healthy: Dictionary

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	path = "user://camp-persistence-%d.json" % Time.get_ticks_usec()
	healthy = Profile.new().data
	healthy.materials["101"] = 4321
	_test_optional_state_validation()
	_test_legacy_state()
	_test_daily_reload()
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	var report = {"checks": checks, "failures": failures, "passed": failures.is_empty(), "scope": "Camp save corruption recovery, legacy schema compatibility, persisted ad receipts and daily limits. Local reconstruction behavior only; no APK runtime parity claim."}
	var file = FileAccess.open("res://reports/camp-persistence-test.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("CAMP_PERSISTENCE_TEST ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func _test_optional_state_validation() -> void:
	for value in [[], {"day": 99, "counts": [], "skips": 0, "receipts": [], "reset_version": 1}, {"day": 99, "counts": {}, "skips": 0, "reset_version": 1}, {"day": 99, "counts": {"MonsterWork_AdSpeedUp": -1}, "skips": 0, "receipts": []}, {"day": 99, "counts": {"MonsterWork_AdSpeedUp": 0.5}, "skips": 0, "receipts": []}, {"day": 99, "counts": {}, "skips": -1, "receipts": []}, {"day": 99, "counts": {}, "skips": 4, "receipts": []}, {"day": "99", "counts": {}, "skips": 0, "receipts": []}, {"day": 99.5, "counts": {}, "skips": 0, "receipts": []}, {"day": 99, "counts": {}, "skips": 0, "receipts": [1]}, {"day": 99, "counts": {}, "skips": 0, "receipts": [""]}, {"day": 99, "counts": {}, "skips": 0, "receipts": [], "reset_version": 2}]:
		_reject("ad_rewards", value, "malformed ad ledger " + str(checks))
	for value in [[], {"npc_id": 1}, {"function_id": 220201, "index": 0, "lines": "bad"}, {"function_id": 220201, "index": 0, "lines": ["bad"]}, {"function_id": 220201, "index": 0.5, "lines": [{}]}, {"function_id": 220201, "index": 1, "lines": [{}]}, {"function_id": 220201, "index": -1, "lines": [{}]}, {"function_id": 220201, "index": 0, "lines": [{}], "stage": "invalid"}, {"function_id": 220201, "index": 0, "lines": [{}], "npc_id": []}]:
		_reject("dialogue_state", value, "malformed dialogue checkpoint " + str(checks))
	for field in ["char_equipped_tokens", "char_token_amplifier_slots", "token_amplifier_unlocked_slots", "token_amplifier_presets", "amplifier_draw_state"]:
		_reject(field, [], "new camp state without schema: " + field)
	_reject("ad_rewards", {"day": 99, "counts": {"MonsterWork_AdSpeedUp": 1e30}, "skips": 0, "receipts": []}, "overflowed ad count")
	for value in [[], 0, 1.5, 1e30]: _reject("selected_character", value, "invalid selected character " + str(value))
	for value in [[], 0, 101.5]: _reject("selected_weapon", value, "invalid selected weapon " + str(value))
	for value in [-1, 11, 0.5]: _reject("selected_difficulty", value, "invalid selected difficulty " + str(value))
	_reject("selected_meal", [], "invalid legacy selected meal")
	_reject("meal_rank", -1, "invalid legacy meal rank")

func _reject(field: String, value, label: String) -> void:
	var broken = healthy.duplicate(true)
	broken[field] = value
	var profile = Profile.new()
	profile.data = broken
	var accepted = profile.validate()
	check(not accepted, label + " rejected before restore")
	if accepted: return
	profile = Profile.new()
	var before = profile.data.duplicate(true)
	check(not profile.restore(broken) and profile.data == before, label + " keeps live state")
	_write(path, broken)
	_write(path + ".bak", healthy)
	var store = Store.new(path)
	var loaded = store.load_profile()
	check(int(loaded.get("materials", {}).get("101", 0)) == 4321 and "备份" in store.warning, label + " restores backup")
	var original = FileAccess.get_file_as_string(path + ".bak")
	check(not store.save(broken) and FileAccess.get_file_as_string(path + ".bak") == original, label + " cannot replace backup")

func _test_legacy_state() -> void:
	var restored = Profile.new()
	check(restored.restore(JSON.parse_string(JSON.stringify(healthy))), "legacy profile without optional camp state restores")
	for stage in ["story", "choices", ""]:
		var snapshot = healthy.duplicate(true)
		snapshot.dialogue_state = {"function_id": 220201, "index": 0, "lines": [{"Text": "Ready", "Speaker": "Resident"}]}
		if not stage.is_empty(): snapshot.dialogue_state.stage = stage
		check(restored.restore(JSON.parse_string(JSON.stringify(snapshot))), "valid dialogue survives JSON: " + stage)
		check(restored.data.dialogue_state.index is int and restored.data.dialogue_state.function_id is int, "dialogue indexes normalize after JSON: " + stage)
	var choices = healthy.duplicate(true)
	choices.dialogue_state = {"function_id": 220201, "npc_id": 1, "index": 0, "lines": [], "stage": "choices"}
	check(restored.restore(JSON.parse_string(JSON.stringify(choices))), "empty story choice checkpoint remains valid")
	var empty = healthy.duplicate(true)
	empty.ad_rewards = {}
	empty.dialogue_state = {}
	check(restored.restore(empty), "unused optional state dictionaries remain valid")

func _test_daily_reload() -> void:
	var catalog = Catalog.new()
	check(catalog.load_all(), "catalog loads")
	var profile = Profile.new()
	profile.data.buildings["6"] = 1
	var systems = Systems.new(catalog, profile)
	systems.utc_now = func(): return now
	check(systems.start_work(101).success, "work starts for persisted daily state")
	var ads = Ads.new(systems)
	var context = {"kind": "work", "id": 101}
	check(ads.claim(context, "camp-daily-receipt", true).success, "ad work reward succeeds before reset")
	profile.data.work_claims = {"day": 99, "count": 30}
	var store = Store.new(path)
	check(store.save(profile.data), "camp state saves with ad and work ledgers")
	var resumed = Profile.new()
	check(resumed.restore(store.load_profile()), "camp state restores through real JSON file")
	var resumed_systems = Systems.new(catalog, resumed)
	resumed_systems.utc_now = func(): return now
	var resumed_ads = Ads.new(resumed_systems)
	check(resumed_ads.free_skips() == 2 and resumed_systems.work_status(101).daily_remaining == 0, "reload preserves both used daily quotas")
	check(not resumed_ads.claim(context, "camp-daily-receipt", true).success, "reload cannot replay a rewarded receipt")
	now += 1
	check(resumed_ads.free_skips() == 3 and resumed_systems.work_status(101).daily_remaining == 30, "22 UTC refresh applies after reload")
	check(not resumed_ads.claim(context, "camp-daily-receipt", true).success, "daily refresh retains processed receipt identities")
	check(resumed_ads.claim(context, "camp-next-day-receipt", true).success, "new daily receipt succeeds")
	check(store.save(resumed.data), "refreshed daily state persists")
	now -= 86400
	var rollback = Profile.new()
	check(rollback.restore(store.load_profile()), "refreshed state reloads after clock rollback")
	var rollback_systems = Systems.new(catalog, rollback)
	rollback_systems.utc_now = func(): return now
	check(Ads.new(rollback_systems).free_skips() == 2, "clock rollback and reload cannot restore used free skips")
	var legacy = healthy.duplicate(true)
	legacy.ad_rewards = {"day": 100, "counts": {"MonsterWork_AdSpeedUp": 10}, "skips": 2, "receipts": ["legacy"]}
	check(resumed.restore(JSON.parse_string(JSON.stringify(legacy))), "previous ad ledger without reset version restores")
	resumed_systems = Systems.new(catalog, resumed)
	resumed_systems.utc_now = func(): return now
	resumed_ads = Ads.new(resumed_systems)
	check(resumed_ads.free_skips() == 1 and resumed.data.ad_rewards.counts.MonsterWork_AdSpeedUp == 10 and resumed.data.ad_rewards.receipts.has("legacy"), "legacy daily reset migration preserves consumed quotas and receipts")

func _write(destination: String, value: Dictionary) -> void:
	var file = FileAccess.open(destination, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)
