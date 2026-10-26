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
	assert(not rewards.quote(meal).success)
	profile.data.buildings["7"] = 1
	for resource in [101, 10101, 10102]: systems.grant_material(resource, 1000)
	assert(systems.rank(profile.data.recipes, 70101000) == 1)
	assert(systems.buy_meal(70101000).success)
	snapshot = profile.data.materials.duplicate(true)
	for index in 3:
		systems.clear_invalid_meals("CompleteRegion")
		assert(rewards.claim(meal, "skip-" + str(index), true).success)
	systems.clear_invalid_meals("CompleteRegion")
	assert(not rewards.claim(meal, "skip-4", true).success)
	assert(rewards.free_skips() == 0)
	assert(profile.data.materials == snapshot)
	var whole_order = rewards.quote({"kind": "meal", "id": 999, "level": 99})
	assert(whole_order.success and whole_order.meals == {"70101000": 1})
	profile.data.run.active = true
	profile.data.meal_purchased = true
	assert(not rewards.claim(meal, "battle").success)
	profile.data.run.active = false
	now[0] += 86400
	assert(rewards.free_skips() == 3 and rewards.quote(offer).success)
	for index in 100:
		systems.clear_invalid_meals("CompleteRegion")
		assert(rewards.claim(meal, "meal-" + str(index)).success)
	systems.clear_invalid_meals("CompleteRegion")
	assert(not rewards.claim(meal, "meal-limit").success)
	var work = {"kind": "work", "id": 101}
	assert(not rewards.quote(work).success)
	profile.data.buildings["6"] = 1
	assert(systems.start_work(101).success)
	for index in 10:
		assert(rewards.claim(work, "work-" + str(index)).success)
		assert(not rewards.claim(work, "work-" + str(index)).success)
		var state = systems.work_status(101)
		assert(state.completed_quantity == 3 if index % 2 == 0 else state.completed_quantity == 6)
		if state.completed_quantity == state.queue_max:
			assert(not rewards.quote(work).success)
			assert(systems.collect_work(101).success)
	assert(not rewards.claim(work, "work-limit").success)
	assert(profile.validate())
	ads.queue_free()
	print("ADS PASS: reward deduplication, stale callbacks, cancellation, timeout retry, failures, limits, daily reset, free skips, recipe gates, work acceleration")
	quit(0)
