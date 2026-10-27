extends SceneTree

var checks := 0
var failures: Array[String] = []
var catalog := DungeonCatalog.new()

func _initialize() -> void:
	_check(catalog.load_all(), "Catalog loads")
	_all_acquisitions()
	_water_upgrade_and_fusion()
	_interrupted_water_burst()
	_light_dark_fusion()
	_twins_cleanup()
	_checkpoint()
	print("SPIRIT_PROGRESSION ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func _systems() -> DungeonSystems:
	var profile := DungeonProfile.new()
	profile.data.run.active = true
	profile.data.run.character_id = 1
	profile.data.stats["max-region"] = 4
	for id in [20211, 20221, 20231, 20241, 20251, 20261]: profile.data.stats["loot-region:" + str(id)] = 2
	return DungeonSystems.new(catalog, profile)

func _actor() -> DungeonCombat:
	var result := DungeonCombat.new()
	result.configure(null, null, 1, 0, 541)
	result.actor_key = "player"
	result.drain_events()
	return result

func _bind(combat: DungeonCombat, systems: DungeonSystems) -> void:
	combat.set_external_attributes(systems.attributes())
	var bindings := systems.progression_buff_bindings()
	combat.set_progression_buffs(bindings.roots, bindings.externally_counted_numeric_ids)

func _all_acquisitions() -> void:
	var media: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/spirit_followers/catalog.json"))
	for key in media.loot_bindings:
		var id := int(key)
		var systems := _systems()
		var replacements: Array = systems.follower_replacements(catalog.find("LootData", id))
		if str(catalog.find("LootData", id).loot_type) == "高级随从":
			for component in replacements:
				_check(systems.add_loot(component, false).success, "Fusion component is obtainable: %d for %d" % [component, id])
		_check(systems.add_loot(id, false).success, "Every spirit is obtainable through add_loot: %d" % id)
		var combat := _actor()
		_bind(combat, systems)
		var bindings := systems.progression_buff_bindings()
		_check(not bindings.roots.is_empty() and bindings.roots.all(func(row): return combat.buff_layers(str(row.id)) > 0), "Owned spirit installs all progression roots: %d" % id)
		_check(replacements.all(func(previous): return int(systems.profile.data.run.inventory.get(str(previous), 0)) == 0), "Acquisition consumes replaced components: %d" % id)
		_check(not systems.can_add_loot(id), "Spirit cannot be duplicated: %d" % id)
		for previous in replacements:
			_check(not systems.can_add_loot(previous), "Spirit prevents reacquiring its consumed lower tier: %d after %d" % [previous, id])

func _water_upgrade_and_fusion() -> void:
	var systems := _systems()
	var combat := _actor()
	_check(systems.add_loot(20220, false).success, "Water acquired")
	_bind(combat, systems)
	combat.add_buff("50202201", 4)
	_check(systems.add_loot(20221, false).success, "Water upgraded")
	_bind(combat, systems)
	_check(combat.buff_layers("50202200") == 0 and combat.buff_layers("50202210") == 1, "Upgrade replaces the root on the current character")
	_check(combat.buff_layers("50202201") == 4, "Upgrade preserves the shared water charges")
	_check(systems.add_loot(20222, false).success and systems.add_loot(20242, false).success, "Highest water and thunder acquired")
	_bind(combat, systems)
	_check(systems.add_loot(20290, false).success, "Water thunder fusion acquired")
	_bind(combat, systems)
	_check(combat.buff_layers("50202201") == 0 and combat.buff_layers("50202203") == 0, "Fusion clears obsolete water charge and heavy-hit observer")
	var victim := _actor()
	victim.actor_key = "enemy"
	var hit := {"source": combat, "damage": 1.0, "sequence": 1, "emission": 1, "definition": {"actType": "SpecAtk"}}
	victim.receive(hit, combat.effective_attack_power())
	combat.confirm_hit(hit)
	var events: Array = combat.drain_events()
	for frame in 100:
		combat.tick(0.02)
		events.append_array(combat.drain_events())
	_check(not events.any(func(event): return event.get("type", "") == "summon" and str(event.get("id", "")) == "50202201"), "Fusion heavy attack cannot discharge an obsolete base-water burst")

func _twins_cleanup() -> void:
	var combat := _actor()
	combat.set_progression_buffs([{"id": "50203100", "layers": 1}])
	for frame in 751: combat.tick(0.02)
	_check(combat.buff_layers("50203101") == 1, "Twins reaches its dynamic second form")
	combat.set_progression_buffs([])
	_check(combat.buff_layers("50203101") == 0 and combat.buff_layers("50203102") == 0, "Removing twins clears both forms without disposal revival")
	combat.drain_events()
	for frame in 1600: combat.tick(0.02)
	_check(combat.buff_layers("50203101") == 0 and combat.buff_layers("50203102") == 0, "Removed twins cannot restart its alternating forms")
	_check(is_zero_approx(combat.attribute("NormalAtkDamageRate")) and is_zero_approx(combat.attribute("AttackSpeedRate")), "Removed twins cannot retain its attack bonuses")

func _interrupted_water_burst() -> void:
	var combat := _actor()
	combat.set_progression_buffs([{"id": "50202220", "layers": 1}])
	combat.add_buff("50202201", 10)
	var victim := _actor()
	var hit := {"source": combat, "damage": 1.0, "sequence": 1, "emission": 1, "definition": {"actType": "SpecAtk"}}
	victim.receive(hit, combat.effective_attack_power())
	combat.confirm_hit(hit)
	_check(combat.buff_layers("50202204") == 1, "Real heavy hit starts the water discharge controller")
	combat.set_progression_buffs([{"id": "50202900", "layers": 1}])
	_check(combat.buff_layers("50202204") == 0, "Fusion during discharge removes the obsolete firing controller")
	combat.drain_events()
	for frame in 100: combat.tick(0.02)
	_check(combat.buff_layers("50202204") == 0 and combat.buff_layers("50202201") == 0, "Removed firing controller cannot outlive the fusion")
	combat.drain_events()
	victim.drain_events()

func _light_dark_fusion() -> void:
	var systems := _systems()
	var combat := _actor()
	_check(systems.add_loot(20252, false).success and systems.add_loot(20262, false).success, "Highest light and dark acquired")
	_bind(combat, systems)
	for frame in 1501: combat.tick(0.02)
	_check(combat.buff_layers("50202601") == 1 and combat.buff_layers("50202521") == 1, "Both component spirits activate their real temporary bonuses")
	_check(systems.add_loot(20310, false).success, "Twins fusion consumes both active components")
	_bind(combat, systems)
	_check(combat.buff_layers("50202601") == 0 and combat.buff_layers("50202521") == 0, "Twins fusion removes the old component bonuses")
	_check(combat.buff_layers("50203100") == 1 and combat.buff_layers("50203102") == 1, "Twins fusion installs the source initial form on the current character")
	combat.drain_events()
	combat._pending.clear()

func _checkpoint() -> void:
	var systems := _systems()
	_check(systems.add_loot(20240, false).success, "Thunder acquired")
	var combat := _actor()
	_bind(combat, systems)
	for frame in 100: combat.tick(0.02)
	var cooldown: float = combat.statuses["50202400"].raw_cooldown
	_bind(combat, systems)
	_check(is_equal_approx(float(combat.statuses["50202400"].raw_cooldown), cooldown), "Unchanged progression binding preserves charge clock")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(combat.snapshot()))
	var restored := _actor()
	_check(restored.restore(saved), "Spirit combat checkpoint restores")
	_bind(restored, systems)
	_check(is_equal_approx(float(restored.statuses["50202400"].raw_cooldown), cooldown), "Binding after checkpoint keeps the saved clock")
	for frame in 251: restored.tick(0.02)
	_check(restored.buff_layers("50202401") == 1, "Restored thunder naturally reaches its pending charge")
	restored.set_progression_buffs([])
	_check(restored.buff_layers("50202401") == 0, "Removing restored thunder also clears its stored charge")

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)
