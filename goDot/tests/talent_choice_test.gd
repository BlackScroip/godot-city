extends SceneTree

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _run() -> void:
	var catalog = DungeonCatalog.new()
	catalog.load_all()
	var profile = DungeonProfile.new()
	profile.data.character_levels["1"] = 30
	var systems = DungeonSystems.new(catalog, profile)
	systems.begin_run(919191, 1, 100)
	for id in [13101, 13102, 13103]:
		check(systems.add_loot(id).success, "Scroll is usable")
	check(systems.stat("talent:choices") == 3, "Three scrolls create three choices")
	check(profile.data.run.talent_rewards.map(func(r): return r.quality) == ["Low", "Normal", "High"], "Scroll qualities persist separately")
	check(not profile.data.run.talent_rewards[0].max_level and not profile.data.run.talent_rewards[1].max_level and profile.data.run.talent_rewards[2].max_level, "Native high-scroll max-level flag preserved")
	check(profile.data.run.inventory.is_empty(), "Consumed scrolls do not remain as relics")
	var first = systems.pending_character_talent_reward()
	check(first.choices.size() == 3, "Three candidates are shown")
	check(first.choices[0] != first.choices[1] and first.choices[1] != first.choices[2] and first.choices[0] != first.choices[2], "Candidates are unique")
	var fingerprint = JSON.stringify(first)
	var step = profile.data.run.random_step
	check(JSON.stringify(systems.pending_character_talent_reward()) == fingerprint and profile.data.run.random_step == step, "Reopening does not reroll or consume RNG")
	var restored = DungeonProfile.new()
	check(restored.restore(JSON.parse_string(JSON.stringify(profile.data))), "Profile restore succeeds")
	var restored_systems = DungeonSystems.new(catalog, restored)
	check(JSON.stringify(restored_systems.pending_character_talent_reward()) == fingerprint, "Exact options survive JSON save and restore")
	check(not restored_systems.choose_character_talent_reward(first.key, 999999).success, "Forged candidate rejected")
	var id = int(first.choices[0])
	check(restored_systems.choose_character_talent_reward(first.key, id).success, "Selected candidate applies")
	check(restored_systems.rank(restored.data.run.talents, id) == 1 and restored.data.run.talents.size() == 1, "Only chosen talent gains a level")
	check(restored.data.talents.is_empty(), "Permanent talent tree is unchanged")
	check(not restored_systems.choose_character_talent_reward(first.key, id).success, "Repeated choice cannot grant twice")
	var next = restored_systems.pending_character_talent_reward()
	restored.data.run.counters.SelectRefreshTime = 1
	check(restored_systems.refresh_character_talent_reward(next.key).success, "Refresh uses available charge")
	check(next.quality == "Normal" and next.choices.size() == 3 and restored.data.run.counters.SelectRefreshTime == 0, "Refresh preserves quality and exact charge accounting")
	check(not restored_systems.refresh_character_talent_reward(next.key).success, "Refresh without charge rejected")
	profile.data.run.talent_rewards.clear()
	systems.set_record("talent:choices", 0)
	systems.queue_character_talent_reward("High", 1, true)
	var boosted = systems.pending_character_talent_reward()
	check(int(boosted.levels[str(boosted.choices[0])]) == 3, "Explicit native max-level mode previews three-level upgrade")
	check(systems.choose_character_talent_reward(boosted.key, int(boosted.choices[0])).success, "Max-level mode applies selected preview")
	for row in catalog.rows("CharTalentData"):
		if int(row.chara_id) == 1: profile.data.run.talents[str(int(row.id))] = DungeonCatalog.ids(row.level_data_id_list).size()
	var gold = systems.material(102)
	systems.queue_character_talent_reward("High")
	check(systems.pending_character_talent_reward().is_empty(), "All-max talents convert rather than show empty modal")
	check(systems.material(102) == gold + 500 and systems.stat("talent:choices") == 0, "All-max legendary conversion grants APK high-quality 500 magic once")
	systems.pending_character_talent_reward()
	check(systems.material(102) == gold + 500, "All-max conversion cannot replay")
	print("TALENT_CHOICE_TEST ", JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
