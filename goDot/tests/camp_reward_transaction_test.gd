extends SceneTree

var catalog = DungeonCatalog.new()
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("CAMP REWARD: " + message)

func _fresh():
	var systems = DungeonSystems.new(catalog, DungeonProfile.new())
	systems.profile.data.buildings["5"] = 3
	return systems

func _run() -> void:
	check(catalog.load_all(), "catalog loads")
	_test_bounty_receive()
	_test_bounty_claim()
	_test_ad_receipt()
	_test_refresh_boundary()
	print(JSON.stringify({"suite": "camp_reward_transaction", "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func _test_bounty_receive() -> void:
	var systems = _fresh()
	systems.grant_material(40001, 3)
	var reentered: Array = []
	var saved: Array = []
	var callback = func(event):
		if event.type != "resource_spent" or int(event.id) != 40001: return
		saved.append(systems.profile.data.duplicate(true))
		if reentered.is_empty():
			reentered.append({})
			reentered[0] = systems.receive_extra_challenges()
	systems.gameplay_event.connect(callback)
	var result = systems.receive_extra_challenges()
	check(result.success and result.ids.size() == 3, "letter transaction receives three bounties")
	check(systems.material(40001) == 2 and systems.extra_challenges.entries().size() == 3, "notification cannot spend a second letter")
	check(reentered.size() == 1 and not reentered[0].success, "nested receive rejected")
	check(saved.size() == 1 and saved[0].extra_challenges.active.size() == 3, "notification snapshot includes awarded bounties")
	systems.gameplay_event.disconnect(callback)

func _test_bounty_claim() -> void:
	var systems = _fresh()
	systems.profile.data.extra_challenges.active = {"2001": 0}
	systems.grant_material(10101, 20)
	systems.grant_material(10102, 20)
	var before = systems.material(801)
	var attempted: Array = []
	var callback = func(event):
		if event.type != "resource_spent" or not attempted.is_empty(): return
		attempted.append({})
		attempted[0] = systems.claim_extra_challenge(2001)
	systems.gameplay_event.connect(callback)
	check(systems.claim_extra_challenge(2001).success, "material bounty claim succeeds")
	check(systems.material(10101) == 10 and systems.material(10102) == 10, "material bounty charges once")
	check(systems.material(801) == before + 1, "material bounty rewards once")
	check(attempted.size() == 1 and not attempted[0].success, "nested bounty claim rejected")
	systems.gameplay_event.disconnect(callback)

func _test_ad_receipt() -> void:
	var systems = _fresh()
	var rewards = preload("res://scripts/domain/ad_rewards.gd").new(systems)
	var context = {"kind": "mall", "id": 1002}
	var nested: Array = []
	var snapshots: Array = []
	var callback = func(event):
		if event.type != "resource_gained": return
		snapshots.append(systems.profile.data.duplicate(true))
		if nested.is_empty():
			nested.append({})
			nested[0] = rewards.claim(context, "atomic-receipt")
	systems.gameplay_event.connect(callback)
	check(rewards.claim(context, "atomic-receipt").success, "ad reward commits")
	check(nested.size() == 1 and not nested[0].success, "reward callback cannot reuse receipt")
	check(not snapshots.is_empty() and snapshots[0].ad_rewards.receipts.has("atomic-receipt"), "reward snapshot already includes receipt")
	check(systems.profile.data.ad_rewards.receipts.count("atomic-receipt") == 1, "receipt stored once")
	systems.gameplay_event.disconnect(callback)

func _test_refresh_boundary() -> void:
	var systems = _fresh()
	var boundary := 86400 * 30 + 22 * 3600
	var calls := [0]
	systems.utc_now = func():
		calls[0] += 1
		return boundary - 1 if calls[0] == 1 else boundary
	var rewards = preload("res://scripts/domain/ad_rewards.gd").new(systems)
	var context = {"kind": "extra_challenge_receive", "id": 0}
	check(rewards.claim(context, "boundary-receipt", true).success, "reward commits at day boundary")
	check(systems.profile.data.ad_rewards.receipts.has("boundary-receipt"), "boundary receipt reaches active ledger")
	check(int(systems.profile.data.ad_rewards.counts.get("ExtraChallenge_GetQuest", 0)) == 1, "one daily count committed")
	check(int(systems.profile.data.ad_rewards.skips) == 1, "one free skip committed")
	check(not rewards.claim(context, "boundary-receipt", true).success, "same callback rejected after reset")
	check(systems.extra_challenges.entries().size() == 3, "day transition does not duplicate bounties")
	var profile = DungeonProfile.new()
	check(profile.restore(JSON.parse_string(JSON.stringify(systems.profile.data))), "committed reward reloads")
	var restored = DungeonSystems.new(catalog, profile)
	restored.utc_now = func(): return boundary
	check(not preload("res://scripts/domain/ad_rewards.gd").new(restored).claim(context, "boundary-receipt").success, "receipt remains consumed after JSON reload")
