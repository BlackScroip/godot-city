extends SceneTree

var checks := 0
var failures: Array[String] = []
var serial := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func actor(buff := "", key := "player") -> DungeonCombat:
	var combat := DungeonCombat.new()
	combat.configure(null, null, 1, 0, 541)
	combat.actor_key = key
	combat.defense = 0
	combat.max_health = 1000000
	combat.health = combat.max_health
	if not buff.is_empty(): check(combat.add_buff(buff), "Root installs " + buff)
	combat.drain_events()
	return combat

func advance(combat: DungeonCombat, duration: float, fps := 60) -> Array:
	var output: Array = []
	var steps := int(ceil(duration * fps))
	for frame in steps:
		combat.tick(minf(1.0 / fps, duration - float(frame) / fps))
		output.append_array(combat.drain_events())
	return output

func strike(source: DungeonCombat, target: DungeonCombat, act_type: String, damage_id := 0, damage := 10.0) -> void:
	serial += 1
	var hit = {"source": source, "damage": damage, "sequence": serial, "emission": serial, "definition": {"damageId": damage_id, "actType": act_type, "element": "Physical"}}
	target.receive(hit, source.effective_attack_power())
	source.confirm_hit(hit)

func events_of(events: Array, type: String, id: String) -> Array:
	return events.filter(func(event): return event.get("type", "") == type and str(event.get("id", "")) == id)

func source_settings(combat: DungeonCombat, id: String) -> Dictionary:
	return combat._settings(combat._buff_index[id], combat._caster_for(id))

func _initialize() -> void:
	_base_tiers()
	_water_cycle()
	_lightning_tiers()
	_light_and_dark()
	_rock_and_ice()
	_fusions()
	_transferred_effects()
	_modifier_identity()
	_source_damage_modifiers()
	_zero_damage_carriers()
	_spirit_modifiers()
	_wolf_projectile_count()
	print(JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func _base_tiers() -> void:
	for family in [["502021", "SubActiveSkill", ["50202102", "50202112", "50202122"]], ["502023", "DodgeAtk", ["50202301", "50202311", "50202321"]]]:
		for tier in 3:
			var player := actor(str(family[0]) + str(tier) + "0")
			var target := actor("", "enemy")
			strike(player, target, family[1])
			var summons := events_of(player.drain_events(), "summon", family[2][tier])
			check(summons.size() == 1, "%s tier %d owns configured summon" % [family[0], tier])
			if not summons.is_empty():
				check(summons[0].target_key == "enemy" and summons[0].origin.OriginType == "targetPosAndSelfDir", "Transferred spirit starts at hit target")
			check(target.drain_events().filter(func(event): return event.type == "summon").is_empty(), "Target never owns friendly spirit summon")
			if family[0] == "502021":
				var emitted = advance(player, 1.9).filter(func(event): return event.type == "hit" and str(event.get("summon_id", "")) == family[2][tier])
				check(emitted.size() == [1, 2, 5][tier], "Fire tier emits authored meteor count")
				if tier > 0:
					strike(player, target, "Spirit", [50202100, 50202110, 50202120][tier])
					check(target.buff_layers("119901") == 1, "Advanced meteor applies burn")
			else:
				var raw: Dictionary = player._summon_index[family[2][tier]].raw_data
				check(is_equal_approx(float(raw.Duration), [5.0, 7.5, 10.0][tier]) and int(raw.MaxExistCount) == [1, 3, 5][tier], "Wind tier retains duration and active limit")

func _water_cycle() -> void:
	for tier in 3:
		var player := actor("502022%d0" % tier)
		var target := actor("", "enemy")
		var maximum: int = [5, 7, 10][tier]
		for cycle in 2:
			for hit in 24:
				strike(player, target, "NormalAtk")
				advance(player, 0.11)
			check(player.buff_layers("50202201") == maximum, "Water tier %d cycle %d reaches cap" % [tier, cycle])
			strike(player, target, "SpecAtk")
			var output := advance(player, 1.1)
			check(events_of(output, "summon", "50202201").size() == maximum, "Water tier releases every stored ray")
			check(player.buff_layers("50202201") == 0 and player.buff_layers("50202204") == 0 and player.buff_layers("50202203") == 0, "Water exhaustion resets hit observer and permits recharging")

func _lightning_tiers() -> void:
	for tier in 3:
		var player := actor("502024%d0" % tier)
		player.custom_properties.EnemyDistances = []
		advance(player, [7.0, 4.0, 2.0][tier] + 0.01)
		check(player.buff_layers("50202401") == 1, "Lightning tier stores one configured charge")
		player.custom_properties.EnemyDistances = [2.0, 3.0, 4.0, 8.0]
		var output := advance(player, 0.1)
		var areas := events_of(output, "area", "50202403")
		check(areas.size() == 1, "Lightning tier spends charge on nearby target area")
		if not areas.is_empty():
			check(int(areas[0].definition.maxTargets) == [1, 1, 3][tier] and areas[0].definition.randomTargets, "Lightning tier uses source random target limit")
			var target := actor("", "enemy")
			target.apply_area(areas[0], false, 4.0, false)
			check(events_of(player.drain_events(), "summon", "119905").size() == 1, "Zero damage lightning marker creates damaging lightning")
		check(player.buff_layers("50202401") == 0, "Lightning consumes one stored charge")

func _light_and_dark() -> void:
	for tier in 3:
		var light := actor("502025%d0" % tier)
		check(events_of(advance(light, 29.9), "summon", "502025%d0" % tier).is_empty(), "Light waits full source 30 seconds")
		var output := advance(light, 0.2)
		check(events_of(output, "summon", "502025%d0" % tier).size() == 1, "Light emits selected sword carrier")
		check(is_equal_approx(light.attribute("DefAddRate"), [0.0, 300.0, 600.0][tier]), "Light tier uses authored defense bonus")
		var dark := actor("502026%d0" % tier)
		advance(dark, 30.01)
		check(is_equal_approx(dark.attribute("NormalAtkDamageRate"), [600.0, 800.0, 1000.0][tier]) and is_equal_approx(dark.attribute("AttackSpeedRate"), [100.0, 150.0, 200.0][tier]), "Dark tier applies configured speed and damage")
		var settings := source_settings(dark, "50202601")
		var duration := 5.0 + float(settings.get("InitLifeTimeAdd", 0)) / 1000.0
		advance(dark, duration + 0.1)
		check(dark.buff_layers("50202601") == 0, "Dark selected lifetime expires")

func _rock_and_ice() -> void:
	for tier in 3:
		var rock := actor("502025%d0" % (tier + 5))
		var distance: float = [35.0, 24.0, 24.0][tier]
		rock.notify_gameplay("move", {"moving": true, "distance": distance - 0.1, "delta": 1.0})
		check(events_of(rock.drain_events(), "summon", "502025510").is_empty(), "Rock movement waits threshold")
		rock.notify_gameplay("move", {"moving": true, "distance": 0.2, "delta": 1.0})
		check(events_of(rock.drain_events(), "summon", "502025510").size() == 1, "Rock movement emits earthquake")
		var target := actor("", "enemy")
		strike(rock, target, "SummonUnit", 502025000)
		check(target.buff_layers("800511") == [1, 1, 2][tier], "Rock earthquake applies tier wound layers")
		var ice := actor("502026%d0" % (tier + 5))
		var storage := "502026%d4" % (tier + 5)
		advance(ice, 12.1)
		check(ice.buff_layers(storage) == tier + 4, "Ice storage fills selected capacity")
		ice.notify_gameplay("action_start", {"slot": 2, "action": "test_subskill"})
		check(events_of(ice.drain_events(), "summon", "50202650%d" % (tier + 1)).size() == 1 and ice.buff_layers(storage) == 0, "Ice full storage releases on subskill")
		advance(ice, [30.0, 20.0, 15.0][tier])
		ice.notify_gameplay("action_start", {"slot": 3, "action": "test_ultimate"})
		check(events_of(ice.drain_events(), "summon", "50202650%d" % (tier + 1)).size() == 1, "Ice ultimate releases selected carrier after configured cooldown")
		var victim := actor("", "enemy")
		strike(ice, victim, "SummonUnit", 502026000)
		check(victim.buff_layers("700206") == tier + 2, "Ice hit applies selected frostbite layers")

func _fusions() -> void:
	var target := actor("", "enemy")
	var firewind := actor("50202700")
	advance(firewind, 4.6)
	strike(firewind, target, "SubActiveSkill")
	var seed_events := firewind.drain_events()
	check(events_of(seed_events, "summon", "50202704").size() == 2, "Fire wind retains both authored direct and child seed summons on caster")
	check(firewind.buff_layers("50202701") == 0 and firewind.buff_layers("50202704") == 0, "Fire wind consumes final charge and clears summon permission")
	var firethunder := actor("50202800")
	firethunder.custom_properties.EnemyDistances = [2.0]
	check(events_of(advance(firethunder, 0.01), "area", "50202403").size() == 1, "Fire thunder starts immediately with source InitResetCD false")
	check(events_of(advance(firethunder, 1.4), "area", "50202403").is_empty(), "Fire thunder waits source 1.5-second interval")
	check(events_of(advance(firethunder, 0.2), "area", "50202403").size() == 1, "Fire thunder repeats after source 1.5-second interval")
	var waterthunder := actor("50202900")
	strike(waterthunder, target, "NormalAtk")
	check(events_of(advance(waterthunder, 0.2), "summon", "50202903").size() == 1, "Water thunder normal hit emits ray")
	strike(waterthunder, target, "SpecAtk")
	check(events_of(advance(waterthunder, 0.2), "summon", "50202903").size() == 1, "Water thunder heavy hit emits ray")
	var waterwind := actor("50203000")
	advance(waterwind, 1.51)
	waterwind.notify_gameplay("action_start", {"slot": 1, "action": "dodge_attack"})
	check(events_of(waterwind.drain_events(), "summon", "50203002").size() == 1, "Water wind dodge emits bubbles")
	advance(waterwind, 1.51)
	waterwind.notify_gameplay("action_start", {"slot": 4, "action": "heavy_attack"})
	check(events_of(waterwind.drain_events(), "summon", "50203002").size() == 1, "Water wind heavy emits bubbles after cooldown")
	var twins := actor("50203100")
	advance(twins, 15.02)
	check(twins.buff_layers("50203101") == 1, "Twins dispose dark form into light form")
	check(is_equal_approx(twins.attribute("NormalAtkDamageRate"), 1200.0), "Twins source dark-form bonus is 120 percent")
	var twin_output := advance(twins, 15.1)
	check(twins.buff_layers("50203102") == 1 and events_of(twin_output, "summon", "50203101").size() == 1, "Twins final light tick emits six-sword carrier and returns dark")
	check(is_equal_approx(twins.attribute("DefAddRate"), 300.0), "Twins use source defense value")
	var icefire := actor("50203200")
	var bluefire_count := 0
	var frost_peak := 0
	var burn_peak := 0
	for attempt in 50:
		strike(icefire, target, "SubActiveSkill")
		bluefire_count += events_of(icefire.drain_events(), "summon", "502032510").size()
		frost_peak = maxi(frost_peak, target.buff_layers("700206"))
		burn_peak = maxi(burn_peak, target.buff_layers("119901"))
		advance(icefire, 1.01)
		advance(target, 1.01)
	check(bluefire_count > 0 and frost_peak >= 10 and burn_peak > 0, "Ice fire chance creates blue fire, burn and frostbite")
	var frozen_target := actor("", "blue_fire_target")
	frozen_target.add_buff("700206", 10)
	for hit in 4: strike(icefire, frozen_target, "SummonUnit", 502032000)
	check(frozen_target.buff_layers("700603") == 1 and frozen_target.buff_layers("700206") == 9 and frozen_target.buff_layers("50203210") == 0, "Four blue fire hits convert exactly one frostbite to shattered ice")
	var icewind := actor("50203300")
	strike(icewind, target, "DodgeAtk")
	check(events_of(icewind.drain_events(), "summon", "502033510").size() == 1, "Ice wind victim summon belongs to caster")
	strike(icewind, target, "SummonUnit", 502033000)
	check(target.buff_layers("700206") > 0, "Ice wind ice spike applies frostbite")
	var rockthunder := actor("50203400")
	var magnetic := actor("", "magnetic")
	strike(rockthunder, magnetic, "DodgeAtk")
	check(magnetic.buff_layers("50203402") == 1, "Rock thunder dodge magnetizes target")
	var pulses := advance(magnetic, 6.2)
	check(magnetic.buff_layers("800511") > 0 and magnetic.buff_layers("50203406") == 0 and events_of(pulses, "status_damage", "50203402").size() == 5, "Magnetized lightning applies wounds and consumes fifth-hit counter")
	var quake := events_of(rockthunder.drain_events(), "summon", "502025510")
	check(quake.size() == 1 and quake[0].target_key == "magnetic", "Fifth magnetic lightning creates caster-owned target earthquake")
	check(events_of(pulses, "buff_effect", "50203402").size() == 5, "Each magnetic pulse emits source effect")
	var mud := actor("50203500")
	mud.notify_gameplay("move", {"moving": true, "distance": 20.1, "delta": 1.0})
	check(events_of(mud.drain_events(), "summon", "502035510").size() == 1, "Water rock movement emits mudslide")
	var muddy := actor("", "muddy")
	strike(mud, muddy, "SummonUnit", 502035000)
	strike(mud, muddy, "DodgeAtk")
	check(muddy.buff_layers("50203507") == 1 and muddy.buff_layers("800511") == 3, "Mudslide marker enables dodge wound bonus")

func _transferred_effects() -> void:
	var player := actor("50203400")
	var target := actor("", "enemy")
	strike(player, target, "DodgeAtk")
	var checkpoint: Dictionary = JSON.parse_string(JSON.stringify(target.snapshot()))
	var restored := actor("", "enemy")
	restored.restore(checkpoint)
	var missing = restored.rebind_buff_casters({"player": player, "character:1": restored})
	check(missing.is_empty(), "Saved transferred status rebinds caster")
	advance(restored, 6.2, 120)
	check(events_of(player.drain_events(), "summon", "502025510").size() == 1, "Restored magnetic chain retains caster through fifth lightning")
	var instant := actor()
	instant.add_buff("50202205")
	instant.add_buff("50202205")
	check(events_of(instant.drain_events(), "summon", "50202201").size() == 2, "Two instant buffs in one frame execute twice")
	instant.add_buff("50203511")
	instant.add_buff("50203511")
	check(events_of(instant.drain_events(), "summon", "502035510").size() == 1, "Explicit source add cooldown gates repeated instant buff")
	advance(instant, 0.51)
	instant.add_buff("50203511")
	check(events_of(instant.drain_events(), "summon", "502035510").size() == 1, "Explicit source add cooldown permits next application")

func _modifier_identity() -> void:
	var player := actor("50202800")
	var target := actor("", "enemy")
	var lava_count := 0
	for index in 50:
		var hit = {"source": player, "damage": 10.0, "sequence": 1, "emission": index, "origin": {"_summon_token": "lightning:%d" % index}, "definition": {"damageId": 2392301, "actType": "Buff", "element": "Thunder"}}
		target.receive(hit, player.attack)
		lava_count += events_of(player.drain_events(), "summon", "50202101").size()
		advance(player, 0.02)
	check(lava_count >= 3, "Separate lightning summons each retain their own modifier counter")
	var rock := actor("50203400")
	var victim := actor("", "victim")
	strike(rock, victim, "DodgeAtk", 0)
	check(victim.buff_layers("800511") == 0 and victim.buff_layers("50203406") == 0, "Unused damage-ID zero never matches configured lightning or quake modifiers")
	check(not source_settings(victim, "119901").is_empty(), "Source Level zero selects default burn settings")

func _source_damage_modifiers() -> void:
	var firethunder := actor("50202800")
	var target := actor("", "red_lightning_target")
	var lightning := {"source": firethunder, "damage": 100.0, "sequence": 1, "emission": 1, "definition": {"damageId": 2392301, "actType": "Buff", "element": "Thunder"}}
	check(is_equal_approx(target.receive(lightning, firethunder.attack), 170.0), "Fresh red lightning applies source final damage bonus700")
	target.add_buff("119901", 2)
	var lava := {"source": firethunder, "damage": 100.0, "sequence": 2, "emission": 2, "definition": {"damageId": 50202101, "actType": "SummonUnit", "element": "Fire"}}
	check(is_equal_approx(target.receive(lava, firethunder.attack), 130.0) and target.buff_layers("119901") == 3, "Lava gains source15 percent per existing burn and adds one burn")
	var icefire := actor("50203200")
	var frozen := actor("", "blue_fire_damage_target")
	frozen.add_buff("119901", 2)
	frozen.add_buff("700206", 10)
	var blue_fire := {"source": icefire, "damage": 100.0, "sequence": 1, "emission": 1, "definition": {"damageId": 502032000, "actType": "SummonUnit", "element": "Ice"}}
	check(is_equal_approx(frozen.receive(blue_fire, icefire.attack), 130.0), "Blue fire gains10 percent per burn and1 percent per frostbite")
	var waterthunder := actor("50202900")
	for damage_id in [50202201, 2392301]:
		var wet := actor("", "wet_damage_target")
		wet.add_buff("119902", 3)
		var ray := {"source": waterthunder, "damage": 100.0, "sequence": damage_id, "emission": damage_id, "definition": {"damageId": damage_id, "actType": "SummonUnit", "element": "Thunder"}}
		check(is_equal_approx(wet.receive(ray, waterthunder.attack), 115.0), "Water thunder rays and lightning gain5 percent per wet layer")
	var rockthunder := actor("50203400")
	for damage_id in [502025000, 2392301]:
		var wounded := actor("", "wound_damage_target")
		wounded.add_buff("800511", 10)
		var quake := {"source": rockthunder, "damage": 100.0, "sequence": damage_id, "emission": damage_id, "definition": {"damageId": damage_id, "actType": "SummonUnit", "element": "Thunder"}}
		var damage := wounded.receive(quake, rockthunder.attack)
		check(is_equal_approx(damage, 102.0 + float(wounded.buff_layers("800511"))), "Rock thunder gains0.2 percent per existing wound plus current general wound modifier")
	for layers in [1, 10]:
		var wounded := actor("", "general_wound_target")
		wounded.add_buff("800511", layers)
		var hit := {"damage": 100.0, "sequence": 1, "emission": 1, "definition": {"damageId": 123, "actType": "NormalAtk", "element": "Physical"}}
		check(is_equal_approx(wounded.receive(hit), 100.0 + float(layers)), "Native combat modifier multiplies its own current buff layers")

func _zero_damage_carriers() -> void:
	var source := actor()
	var target := actor("", "enemy")
	target.shield = 75
	target.armor = 20
	var originals: Array = []
	for group_action in [["ActGroup_dilong", "attack6"], ["ActGroup_huoyanshi", "attack2"], ["ActGroup_jushimoxiang", "EX_Attack3"]]:
		var action: Dictionary = source._action(group_action[0], group_action[1])
		for hit in action.get("hits", []):
			var raw = JSON.parse_string(str(hit.get("raw", "{}")))
			if int(hit.get("damageId", 0)) <= 0 and not str(raw.get("EntityProperty", {}).get("AddSummonUnitDefOnEnd", {}).get("AddSummonUnitId", "")).is_empty():
				originals.append({"label": group_action[0] + "/" + group_action[1], "hit": hit})
	originals.append({"label": "delayed sword carrier", "hit": source._summon_index["45300206"].hit})
	check(originals.size() >= 5, "Source Boss actions retain non-physical ending-summon carrier examples")
	for original in originals:
		for condition in original.hit.get("conditions", []):
			if str(condition.get("type", "")) != "EECT_CheckBuffExist": continue
			if bool(condition.get("exists", false)): source.add_buff(str(condition.buff))
			else: source.remove_buff(str(condition.buff))
		source.drain_events()
		source._emit_hit({"at": 0.0, "hit": original.hit, "action": original.label, "slot": 0, "sequence": 1})
		var emitted := source.drain_events().filter(func(event): return event.type == "hit")
		check(emitted.size() == 1, "Zero-damage carrier reaches world lifecycle: " + original.label)
		if emitted.is_empty(): continue
		var hit: Dictionary = emitted[0]
		check(bool(hit.definition.get("carrier_only", false)) and is_zero_approx(float(hit.damage)), "Pure carrier retains zero damage and ending summon")
		var previous := target.health
		check(is_zero_approx(target.receive(hit, source.attack)) and target.health == previous and target.shield == 75 and target.armor == 20, "Pure carrier leaves health, shields and armor unchanged")
		check(not bool(hit.get("resolved_accepted", false)) and target.drain_events().is_empty(), "Pure carrier produces no receive, impact or gameplay side effects")
	for id in ["45300206", "423002301"]:
		var carrier := actor()
		carrier.spawn_summon(id)
		var source_hit: Dictionary = carrier._summon_index[id].hit
		var output := advance(carrier, 6.1)
		var emitted := output.filter(func(event): return event.type == "hit" and str(event.get("summon_id", "")) == id)
		check(emitted.size() == int(source_hit.count), "Zero-damage funnel schedules the authored ending-carrier count: " + id)
		check(emitted.all(func(event): return bool(event.definition.get("carrier_only", false))), "All emitted non-physical funnel carriers remain free of receive side effects")

func _spirit_modifiers() -> void:
	var source := actor()
	source.set_external_attributes({"SpiritRange": 1000, "SpiritDuration": 1000})
	for id in ["502032510", "502035510"]:
		var original: Dictionary = source._summon_index[id]
		var source_raw := JSON.stringify(original.raw_data)
		source.spawn_summon(id)
		var summons := events_of(source.drain_events(), "summon", id)
		check(summons.size() == 1, "Source spirit field spawns with effective modifiers: " + id)
		if summons.is_empty(): continue
		var resolved: Dictionary = summons[0].definition.raw_data
		var base_radius := float(original.raw_data.EntityProperty.Radius)
		var expected_life := 7.0 if id == "502032510" else 12.0
		check(is_equal_approx(float(summons[0].lifetime), expected_life) and is_equal_approx(float(resolved.Duration), expected_life), "Duration modifier adds native weighted attribute in seconds")
		check(is_equal_approx(float(resolved.EntityProperty.Radius), base_radius * 2.0), "Field collider respects effective SpiritRange")
		check(is_equal_approx(float(resolved.PrefabScale.x), float(original.raw_data.PrefabScale.x) * 2.0), "Field prefab and collider share one range multiplier")
		var emitted := advance(source, 0.02).filter(func(event): return event.type == "hit" and str(event.get("summon_id", "")) == id)
		check(not emitted.is_empty(), "Effective field retains damage pulses")
		if not emitted.is_empty():
			var hit_raw = JSON.parse_string(str(emitted[0].definition.raw))
			check(is_equal_approx(float(hit_raw.EntityProperty.Radius), base_radius * 2.0), "Scheduled field applies range modifier exactly once")
		check(JSON.stringify(original.raw_data) == source_raw, "Effective cast leaves source catalog unchanged")
	var thunder := actor()
	thunder.set_external_attributes({"SpiritTrigger": 1000, "SpiritRange": 1000})
	thunder.add_buff("50202420")
	thunder.custom_properties.EnemyDistances = []
	advance(thunder, 0.49)
	check(thunder.buff_layers("50202401") == 0, "Highest thunder respects modified initial cooldown")
	advance(thunder, 0.02)
	check(thunder.buff_layers("50202401") == 1, "SpiritTrigger subtracts1500ms from source2000ms charge timer")
	thunder.custom_properties.EnemyDistances = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 6.5]
	var areas := events_of(advance(thunder, 0.02), "area", "50202403")
	check(not areas.is_empty() and int(areas[0].definition.maxTargets) == 6, "SpiritRange adds three targets to highest thunder search")
	var legacy := {"Enabled": true, "Parameter": "Range", "PerMille": 2.0, "MinMultiplier": 0.0, "MaxMultiplier": 5.0}
	check(is_equal_approx(source._spirit_apply(3.0, legacy), 5.0), "Native modifier arithmetic adds contributions to the supplied base")
	source.set_external_attributes({"SpiritRange": -1000})
	check(is_equal_approx(source._spirit_apply(3.0, legacy), 3.0), "Spirit attributes enforce lower bound even without explicit flags")
	source.set_external_attributes({"SpiritRange": 10000})
	check(is_equal_approx(source._spirit_apply(3.0, legacy), 13.0), "Spirit attributes enforce source upper bound of five")
	var current := {"Enabled": true, "Influences": [{"Enabled": true, "Attribute": "SpiritRange", "PerMille": 2.0, "MinMultiplier": 0.0, "MaxMultiplier": 5.0}, {"Enabled": true, "Attribute": "SpiritDuration", "PerMille": 3.0, "MinMultiplier": 0.0, "MaxMultiplier": 5.0}]}
	source.set_external_attributes({"SpiritRange": 1000, "SpiritDuration": 2000})
	check(is_equal_approx(source._spirit_apply(1.0, current), 9.0), "New influence format sums independent weighted attributes")

func _wolf_projectile_count() -> void:
	for layers in [0, 1, 2]:
		var wolf := actor()
		if layers > 0: wolf.add_buff("41300112", layers)
		var action := wolf._action("ActGroup_senlinlangwang", "attack5")
		var source_hit: Dictionary = action.hits.filter(func(hit): return int(hit.get("damageId", 0)) == 41300151)[0]
		wolf._schedule(source_hit, 0.0, "attack5", 0, 0.0)
		var emitted := advance(wolf, 4.0).filter(func(event): return event.type == "hit" and int(event.definition.get("damageId", 0)) == 41300151)
		check(emitted.size() == 50 + layers * 10, "Fresh wolf modifier adds ten emitted fireballs per source buff layer")
		check(wolf.diagnostics.is_empty(), "Wolf emission modifier runs without unsupported adapter diagnostics")
