extends SceneTree

const Campaign = preload("res://scripts/domain/campaign.gd")
const Catalog = preload("res://scripts/domain/catalog.gd")
const Profile = preload("res://scripts/domain/profile.gd")
const Systems = preload("res://scripts/domain/systems.gd")
var assertions := 0
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message)

func _initialize() -> void:
	var catalog = Catalog.new()
	check(catalog.load_all(), "Trial loot data loads")
	var campaign = Campaign.new()
	check(campaign.configure(), "Trial campaign loads")
	var profile = Profile.new()
	var systems = Systems.new(catalog, profile)
	var nodes: Array = campaign.database.Nodes.filter(func(node): return node.Flow == "TreasureTrial")
	check(nodes.size() == 8, "Both high-risk trial rooms retain four difficulty variants")
	for node in nodes:
		for choice in 3:
			profile.data.run = Profile.new_run()
			check(systems.begin_run(123, 1, 100, 0).success and campaign.start_practice(int(node.Id), 123).success, "Start trial fixture")
			check(campaign.trial_status().phase == "choice" and not campaign.room_ready(), "Trial begins with unopened choices")
			check(not campaign.resolve_action().success and not campaign.complete_room().success, "Generic noncombat action cannot bypass trial")
			check(not systems.start_chest_trial(campaign, -1).success and not systems.start_chest_trial(campaign, 3).success, "Unknown chest indices are rejected")
			check(systems.start_chest_trial(campaign, choice).success, "One chest starts a trial")
			var initial: Dictionary = campaign.trial_status()
			check(initial.phase == "wave" and initial.wave_count == choice + 2 and initial.quality == ["Normal", "Unusual", "Luxury"][choice], "Quality chooses the APK action pipeline")
			check(not systems.start_chest_trial(campaign, (choice + 1) % 3).success and not campaign.decline_trial().success, "A started trial cannot change chest or be declined")
			check(not systems.claim_chest_trial_reward(campaign).success, "Trial cannot claim before surviving")
			var saved = campaign.snapshot()
			check(not campaign.tick_trial(-1).success and campaign.snapshot() == saved, "Invalid delta preserves trial")
			campaign.tick_trial(float(initial.remaining) * 0.5)
			check(campaign.trial_status().phase == "wave" and is_equal_approx(float(campaign.trial_status().remaining), float(initial.remaining) * 0.5), "Trial uses exact recovered action duration")
			_restore(campaign.snapshot(), "Wave cursor")
			campaign.tick_trial(100)
			check(campaign.trial_status().phase == "gap" and campaign.trial_status().remaining == 1.0, "Between-wave gap is exactly one battle second")
			_restore(campaign.snapshot(), "Gap cursor")
			campaign.tick_trial(0.5)
			check(campaign.trial_status().phase == "gap", "Half of gap cannot trigger next action")
			campaign.tick_trial(0.5)
			check(campaign.trial_status().phase == "wave" and int(campaign.trial_status().wave_index) == 1, "Next wave begins after full gap")
			for step in 20:
				if campaign.trial_status().phase == "drain": break
				campaign.tick_trial(100, true)
			check(campaign.trial_status().phase == "drain" and not campaign.room_ready(), "All actions finish before attack drain")
			campaign.tick_trial(9, true)
			check(campaign.trial_status().phase == "drain", "Alive attacks delay reward for up to ten seconds")
			_restore(campaign.snapshot(), "Attack drain cursor")
			campaign.tick_trial(1, true)
			check(campaign.trial_status().phase == "complete" and not campaign.room_ready(), "Drain timeout ends trial before reward is issued")
			check(systems.claim_chest_trial_reward(campaign).success and campaign.room_ready(), "Survival claims one selected-quality treasure reward")
			var before = profile.data.duplicate(true)
			check(not systems.claim_chest_trial_reward(campaign).success and profile.data == before, "Duplicate claim does not reroll drops")
			_restore(campaign.snapshot(), "Claimed reward")
			check(campaign.complete_room().success and campaign.advance().success, "Claimed trial advances normally")
	profile.data.run = Profile.new_run()
	systems.begin_run(123, 1, 100, 0)
	campaign.start_practice(int(nodes[0].Id), 123)
	profile.data.run.inventory["22122"] = 1
	check(systems.start_chest_trial(campaign, 2).success and campaign.trial_status().skipped and campaign.trial_status().phase == "complete", "Owned skip relic bypasses all trial attacks")
	check(systems.claim_chest_trial_reward(campaign).success and profile.data.run.inventory["22122"] == 1, "Skip retains relic and grants chosen treasure once")
	var old = campaign.snapshot()
	old.erase("trial")
	check(campaign.restore(old) and campaign.trial_status().phase == "declined", "Legacy resolved trial cannot create a second reward")
	campaign.start_practice(int(nodes[0].Id), 123)
	check(campaign.decline_trial().success and campaign.room_ready() and not systems.claim_chest_trial_reward(campaign).success, "Unopened trial can be left without rewards")
	campaign.start_practice(int(nodes[0].Id), 123)
	profile.data.run.inventory.erase("22122")
	systems.start_chest_trial(campaign, 0)
	var invalid = campaign.snapshot()
	invalid.trial.reward_claimed = true
	check(not campaign.restore(invalid), "Active wave cannot masquerade as claimed")
	invalid = campaign.snapshot()
	invalid.trial.remaining = 99999
	check(not campaign.restore(invalid), "Saved action cursor cannot exceed recovered duration")
	profile.data.run.health = 0
	check(not systems.claim_chest_trial_reward(campaign).success, "Defeated player cannot receive trial rewards")
	campaign.fail()
	check(not campaign.tick_trial(100).success and not campaign.claim_trial_reward().success, "Failed campaign cannot finish or claim a trial")
	print("CHEST_TRIAL ", JSON.stringify({"passed": failures.is_empty(), "assertions": assertions, "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func _restore(saved: Dictionary, message: String) -> void:
	var reloaded = Campaign.new()
	reloaded.configure()
	check(reloaded.restore(JSON.parse_string(JSON.stringify(saved))), message + " survives JSON round trip")
	check(reloaded.trial_status().phase == saved.trial.phase and int(reloaded.trial_status().wave_index) == int(saved.trial.wave_index), message + " preserves phase and wave")
