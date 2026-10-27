extends SceneTree

const Catalog = preload("res://scripts/domain/catalog.gd")
const Profile = preload("res://scripts/domain/profile.gd")
const Systems = preload("res://scripts/domain/systems.gd")
const Choices = preload("res://scripts/domain/room_choices.gd")
const Partners = preload("res://scripts/domain/partner_skills.gd")
const Combat = preload("res://scripts/domain/combat.gd")
var catalog
var profile
var systems
var choices
var checks := 0
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func reset() -> void:
	profile = Profile.new()
	systems = Systems.new(catalog, profile)
	systems.begin_run(73281, 1, 500)
	profile.data.partners["12003"] = 1
	profile.data.partners["13001"] = 1
	choices = Choices.new(systems)

func _initialize() -> void:
	catalog = Catalog.new()
	check(catalog.load_all(), "catalog loads")
	reset()
	var altar: Dictionary = choices.open_sacrifice("altar-a")
	check(altar.success and altar.options.size() == 3, "altar opens three original reward choices")
	check(altar.options.all(func(option): return int(option.hp_cost) >= 30 and int(option.hp_cost) <= 50), "region one prices use inclusive 30..50")
	check(choices.open_sacrifice("altar-a").options == altar.options, "reopening keeps random prices and IDs")
	check(int(profile.data.run.counters.SelectLootRemainCount_Reward) == 1, "reopening increments reward counter once")
	var first: Dictionary = altar.options[0]
	var health: float = profile.data.run.health
	profile.data.run.max_health = int(first.hp_cost)
	check(not choices.choose_sacrifice("altar-a", int(first.id)).success, "exactly matching max HP cannot pay")
	profile.data.run.max_health = 500
	check(choices.choose_sacrifice("altar-a", int(first.id)).success, "first item can be bought")
	check(profile.data.run.max_health == 500 - int(first.hp_cost) and profile.data.run.health == minf(health, profile.data.run.max_health), "sacrifice reduces and clamps max and current HP")
	check(int(choices.extra_attributes().HpAddFixed) == -int(first.hp_cost), "sacrifice penalty persists as signed fixed HP")
	var remaining: Dictionary = choices.open_sacrifice("altar-a")
	check(remaining.options == altar.options.slice(1), "buy does not immediately reprice remaining choices")
	check(not choices.choose_sacrifice("altar-a", int(first.id)).success, "same item cannot be bought twice")
	var second: Dictionary = remaining.options[0]
	check(choices.choose_sacrifice("altar-a", int(second.id)).success, "same altar allows multiple item purchases")
	check(int(profile.data.run.counters.get("SacrificialAltarRefreshCount", 0)) == 0, "purchase factor commits on refresh or close")
	profile.data.run.counters.SelectRefreshTime = 1
	check(choices.refresh_sacrifice("altar-a").success, "refresh spends available refresh count")
	check(int(profile.data.run.counters.SacrificialAltarRefreshCount) == 2, "refresh commits both purchases")
	check(not choices.refresh_sacrifice("altar-a").success, "no refresh remains after spending it")
	check(choices.finish_sacrifice("altar-a").success and choices.open_sacrifice("altar-a").closed, "finish persists closed altar")
	check(int(profile.data.run.counters.SelectLootRemainCount_Reward) == 0 and not choices.finish_sacrifice("altar-a").success, "finish decrements reward count once")
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(profile.data))
	profile.data = snapshot
	check(Choices.new(systems).open_sacrifice("altar-a").closed, "JSON restoration preserves consumed altar")
	reset()
	profile.data.run["region_rewards"] = [{"AttributeType": "BlessingPlusSelectExtraCount", "Value": 1}]
	profile.data.run.region_rewards.append({"AttributeType": "SelectLootExtraOption", "Value": 9})
	check(choices.open_sacrifice("blessing").options.size() == 4, "altar count uses original 4100 blessing extra count")
	profile.data.run.region_rewards.append({"AttributeType": "FreeRefreshInFirstRoom", "Value": 1})
	altar = choices.open_sacrifice("free-first", true)
	var locked_id := int(altar.options[0].id)
	var locked_cost := int(altar.options[0].hp_cost)
	check(not choices.toggle_sacrifice_lock("free-first", locked_id).success, "source permanent talent 221 gates altar locking")
	profile.data.talents["221"] = 1
	check(choices.toggle_sacrifice_lock("free-first", locked_id).success, "altar candidate can be locked")
	profile.data.run.counters.SelectRefreshTime = 0
	check(altar.free_refresh and choices.refresh_sacrifice("free-first").success, "first-node attribute grants refresh without a token")
	var locked_options: Array = choices.open_sacrifice("free-first").options.filter(func(option): return int(option.id) == locked_id)
	check(locked_options.size() == 1 and int(locked_options[0].hp_cost) == locked_cost and locked_options[0].locked, "refresh keeps locked candidate and its original HP cost")
	check(int(profile.data.run.counters.SelectRefreshTime) == 0, "free refresh does not consume unavailable refresh tokens")
	check(not choices.open_sacrifice("other-node").free_refresh and not choices.refresh_sacrifice("other-node").success, "first-room attribute does not grant other nodes a free refresh")
	reset()
	var initial_step: int = profile.data.run.random_step
	var base: Array = choices._sacrifice_options()
	profile.data.run.random_step = initial_step
	profile.data.run.region = 2
	var region: Array = choices._sacrifice_options()
	check(base.size() == region.size(), "region scaling preserves candidate count")
	for index in mini(base.size(), region.size()): check(int(region[index].hp_cost) == int(float(base[index].hp_cost) * 1.5), "native missing-field default adds 50% per region")
	profile.data.run.random_step = initial_step
	profile.data.run.region = 1
	profile.data.run.counters.SacrificialAltarRefreshCount = 5
	var paid: Array = choices._sacrifice_options()
	for index in mini(base.size(), paid.size()): check(int(paid[index].hp_cost) == int(base[index].hp_cost) * 2, "native missing-field default adds 20% per committed buy")
	reset()
	var partner: Dictionary = choices.open_partner("partner-a")
	check(partner.success and partner.options.size() == 4, "empty loadout offers two skills plus two generic loot choices")
	check(partner.options.filter(func(option): return option.mode == "new").size() == 2, "new skill candidate positions have two distinct unlocked skills")
	check(partner.options[0].name.find("Lv.1") >= 0 and str(partner.options[0].description).find("召唤") >= 0 or str(partner.options[0].description).find("毒元素") >= 0, "skill display uses original AttackData instead of monster resonance")
	check(choices.choose_partner("partner-a", 0).success, "new partner fills first slot")
	check(choices.partner_slots().size() == 1 and int(profile.data.run.counters.CurMonsterPartnerSkillSelectCout) == 1, "successful choice increments total once")
	check(not choices.choose_partner("partner-a", 0).success, "closed selector cannot increment choice again")
	profile.data.run.counters[Choices.SLOTS] = [{"id": 12003, "level": 1}, {"id": 13001, "level": 2}]
	partner = choices.open_partner("partner-b")
	check(partner.options.size() == 6, "two equipped skills offer six positions with fallback new choices")
	check(partner.options.filter(func(option): return option.mode == "upgrade").size() == 2, "both slots below cap can upgrade")
	check(choices.choose_partner("partner-b", 0).success and int(choices.partner_slots()[0].level) == 2, "upgrade modifies run level")
	check(int(profile.data.partners["12003"]) == 1, "run upgrade preserves persistent camp partner rank")
	profile.data.run.counters[Choices.SLOTS][0].level = 3
	profile.data.run.counters[Choices.SLOTS][1].level = 3
	partner = choices.open_partner("partner-c")
	check(partner.options.filter(func(option): return option.mode == "upgrade").is_empty(), "level three never offers upgrade")
	for pair in [[12003, 3, 1], [12003, 4, 2], [12003, 8, 3], [13001, 4, 1], [13001, 5, 2], [13001, 10, 3]]:
		profile.data.run.counters.CurMonsterPartnerSkillSelectCout = pair[1]
		check(choices._new_partner_level(pair[0]) == pair[2], "source tier-specific initial skill threshold")
	_test_partner_combat()
	_test_all_partner_levels()
	if failures.is_empty(): print("room_choices_test PASS ", checks)
	else:
		for failure in failures: push_error(failure)
		print("room_choices_test FAIL ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)

func _test_partner_combat() -> void:
	reset()
	profile.data.run.counters[Choices.SLOTS] = [{"id": 13001, "level": 1}]
	var controller = Partners.new(systems)
	var combat = Combat.new()
	check(combat.configure(null, systems, 1).success, "player combat loads")
	var bindings: Dictionary = systems.progression_buff_bindings()
	combat.set_progression_buffs(bindings.roots, bindings.externally_counted_numeric_ids)
	check(combat.buff_layers("91300110") == 1, "equipped level one buff reaches real combat")
	var status: Dictionary = controller.state(combat)
	check(float(status.max_sp) == 75 and float(status.sp) == 0 and float(status.slots[0].remaining) == 3, "source defaults start with zero SP and empty 3s cooldown charge")
	controller.tick(combat, 10, false)
	check(controller.state().sp == 0 and controller.state().slots[0].remaining == 0, "cooldowns charge without nearby enemies while SP does not")
	controller.tick(combat, 100, true)
	check(controller.state().sp == 50, "nearby-enemy charge defaults to half SP per second")
	check(controller.request(combat, 0).success, "ready original partner action starts")
	check(combat.current_action == "mpskill_613001" and combat._current_slot == 5, "partner button dispatches original action in its own slot")
	check(controller.state().sp == 0 and controller.state().slots[0].remaining == 3, "cast spends shared SP and resets own cooldown")
	check(not controller.request(combat, 0).success, "cannot cast twice without charge")
	var summons: Array = []
	for tick in 15:
		combat.tick(0.1)
		for event in combat.drain_events():
			if event.type == "summon": summons.append(str(event.id))
	check(summons.has("6130011") and not summons.has("6130012"), "level one wolf uses original level one summon")
	profile.data.run.counters[Choices.SLOTS][0].level = 2
	bindings = systems.progression_buff_bindings()
	combat.set_progression_buffs(bindings.roots, bindings.externally_counted_numeric_ids)
	controller.tick(combat, 100, true)
	check(controller.request(combat, 0).success, "level two partner casts")
	summons.clear()
	for tick in 15:
		combat.tick(0.1)
		for event in combat.drain_events():
			if event.type == "summon": summons.append(str(event.id))
	check(summons.has("6130013") and not summons.has("6130011"), "level two wolf uses original level two summon branch")
	profile.data.run.counters[Choices.SLOTS][0].level = 3
	bindings = systems.progression_buff_bindings()
	combat.set_progression_buffs(bindings.roots, bindings.externally_counted_numeric_ids)
	check(combat.buff_layers("91300130") == 1 and combat.buff_layers("91300110") == 0, "upgrade replaces level one passive root with exact level three root")
	check(controller.state().slots[0].remaining == 3, "upgrade resets source cooldown data")
	controller.tick(combat, 100, true)
	check(controller.request(combat, 0).success, "upgraded partner casts")
	summons.clear()
	for tick in 15:
		combat.tick(0.1)
		for event in combat.drain_events():
			if event.type == "summon": summons.append(str(event.id))
	check(summons.has("6130012") and not summons.has("6130011"), "level three wolf executes original upgraded summon branch")
	profile.data = JSON.parse_string(JSON.stringify(profile.data))
	check(Partners.new(systems).state().slots[0].remaining == 3, "JSON restore preserves cooldown instead of granting a ready cast")
	controller.tick(combat, 1000, true)
	check(controller.state().sp == 75, "shared SP clamps to source max")
	controller.charge({"ChargeCount": -50000, "ReduceCooldown": 1000, "ReduceCooldownPercent": 500})
	check(controller.state().sp == 25 and is_equal_approx(controller.state().slots[0].remaining, 0), "native charge buff uses units of 25 SP and reduces cooldown")

func _test_all_partner_levels() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Partners.DATA))
	for skill in source.skills:
		for level in range(1, 4):
			reset()
			profile.data.run.counters[Choices.SLOTS] = [{"id": int(skill.id), "level": level}]
			var controller = Partners.new(systems)
			var combat = Combat.new()
			combat.configure(null, systems, 1)
			combat.custom_properties["EnemyDistances"] = [3.0]
			var bindings: Dictionary = systems.progression_buff_bindings()
			combat.set_progression_buffs(bindings.roots, bindings.externally_counted_numeric_ids)
			controller.tick(combat, 150, true)
			check(controller.request(combat, 0).success, "all original partner level actions can cast: %s level %d" % [skill.id, level])
			var gameplay := false
			var spawned: Array[String] = []
			for tick in 15:
				combat.tick(0.1)
				for event in combat.drain_events():
					if event.type in ["summon", "hit", "buff_added"]: gameplay = true
					if event.type == "summon": spawned.append(str(event.id))
					if event.type == "partner_charge": controller.charge(event.settings)
			check(gameplay or not combat.statuses.is_empty(), "selected partner level produces gameplay data: %s level %d" % [skill.id, level])
			var unexpected: Array = combat.diagnostics.filter(func(message):
				if not str(message).begins_with("Summon behavior requires world adapter: "): return true
				return not spawned.has(str(message).trim_prefix("Summon behavior requires world adapter: ").get_slice(" ", 0)))
			check(unexpected.is_empty(), "original partner action dependencies resolve or emit their world carrier: %s level %d %s" % [skill.id, level, unexpected])
			if int(skill.id) == 53001 and level == 2: check(is_equal_approx(float(controller.state().sp), 25.0), "dragon level two returns the native one support point")
