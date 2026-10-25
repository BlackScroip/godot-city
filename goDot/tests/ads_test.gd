extends SceneTree

class FakeBridge extends RefCounted:
	var shown: Array = []
	var configurations := 0
	var resets := 0
	func configure(_app, _key, _placement): configurations += 1
	func reset_preparation(): resets += 1
	func load_rewarded(): pass
	func show_rewarded(id, scene): shown.append([id, scene])
	func poll_events(): return "[]"

var grants := 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var ads = preload("res://scripts/ads_service.gd").new()
	root.add_child(ads)
	ads.bridge = FakeBridge.new()
	ads.configuration = {"app_id": "test", "app_key": "test", "rewarded_placement_id": "test"}
	assert(ads.request("meal", func(): grants += 1))
	assert(not ads.request("mall", func(): grants += 1))
	ads.handle_event({"type": "initialized"})
	ads.handle_event({"type": "ready"})
	var id = ads.pending.id
	ads.handle_event({"type": "reward", "id": "stale"})
	assert(grants == 0)
	ads.handle_event({"type": "reward", "id": id})
	ads.handle_event({"type": "reward", "id": id})
	assert(grants == 1)
	ads.handle_event({"type": "closed", "id": id})
	ads.handle_event({"type": "reward", "id": id})
	assert(grants == 1 and not ads.busy())
	assert(ads.request("meal", func(): grants += 1))
	ads.cancel()
	ads.handle_event({"type": "ready"})
	assert(ads.bridge.shown.size() == 1)
	assert(ads.request("meal", func(): grants += 1))
	id = ads.pending.id
	ads.handle_event({"type": "closed", "id": id})
	assert(grants == 1 and not ads.busy())
	assert(ads.request("meal", func(): grants += 1))
	ads.handle_event({"type": "load_failed"})
	assert(not ads.busy() and grants == 1)
	ads.initialized = false
	assert(ads.request("meal", func(): grants += 1))
	ads._process(61.0)
	assert(not ads.busy() and not ads.initializing and ads.bridge.resets == 1)
	var attempts = ads.bridge.configurations
	assert(ads.request("meal", func(): grants += 1))
	assert(ads.bridge.configurations == attempts + 1)
	ads.cancel()

	var catalog = DungeonCatalog.new()
	assert(catalog.load_all())
	var profile = DungeonProfile.new()
	var systems = DungeonSystems.new(catalog, profile)
	var now = [172800]
	systems.utc_now = func(): return now[0]
	var rewards = preload("res://scripts/domain/ad_rewards.gd").new(systems)
	var offer = {"kind": "mall", "id": 1002}
	assert(rewards.claim(offer, "one").success)
	var snapshot = profile.data.materials.duplicate(true)
	assert(not rewards.claim(offer, "one").success)
	assert(not rewards.claim(offer, "two").success)
	assert(profile.data.materials == snapshot)
	var meal = {"kind": "meal", "id": 70101000, "level": 1}
	for index in 3: assert(rewards.claim(meal, "skip-" + str(index), true).success)
	assert(not rewards.claim(meal, "skip-4", true).success)
	assert(rewards.free_skips() == 0)
	assert(profile.data.materials == snapshot)
	assert(not rewards.claim({"kind": "meal", "id": 70101000, "level": 99}, "bad").success)
	profile.data.run.active = true
	assert(not rewards.claim(meal, "battle").success)
	profile.data.run.active = false
	now[0] += 86400
	assert(rewards.free_skips() == 3 and rewards.quote(offer).success)
	for index in 100: assert(rewards.claim(meal, "meal-" + str(index)).success)
	assert(not rewards.claim(meal, "meal-limit").success)
	var work = {"kind": "work", "id": 101}
	assert(not rewards.quote(work).success)
	profile.data.work = [{"work_id": 101, "partner_id": 11001, "started_utc": now[0], "due_utc": now[0] + 3600, "material_id": 101, "reward": 500}]
	assert(rewards.claim(work, "work-1").success)
	assert(profile.data.work[0].due_utc == now[0] + 1800)
	assert(not rewards.claim(work, "work-1").success)
	assert(rewards.claim(work, "work-2").success)
	assert(profile.data.work[0].due_utc == now[0] and not rewards.quote(work).success)
	for index in range(2, 10):
		profile.data.work[0].due_utc = now[0] + 10
		assert(rewards.claim(work, "work-more-" + str(index)).success)
		assert(profile.data.work[0].due_utc == now[0])
	profile.data.work[0].due_utc = now[0] + 10
	assert(not rewards.claim(work, "work-limit").success)
	assert(profile.validate())
	ads.queue_free()
	print("ADS PASS: reward deduplication, stale callbacks, cancellation, timeout retry, failures, limits, daily reset, free skips, recipe gates, work acceleration")
	quit(0)
