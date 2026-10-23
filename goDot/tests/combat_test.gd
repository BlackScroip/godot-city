extends SceneTree

const Combat = preload("res://scripts/domain/combat.gd")
var assertions: int = 0
var failures: Array = []
var observed_diagnostics: Dictionary = {}
var cases: Array = []
var effect_checks: Dictionary = {}

func _initialize() -> void:
	var baseline = Combat.new()
	_check(baseline.configure().success, "Combat catalog loads")
	_check(baseline.catalog.characters.size() == 7, "7 characters")
	_check(baseline.catalog.enemies.size() == 39, "39 enemies")
	for character in baseline.catalog.characters:
		for slot in range(5):
			var actor = Combat.new()
			actor.configure(null, null, int(character.id), 0, 123)
			if slot == 4 and int(character.id) == 4:
				actor.add_buff(str(character.jp), 25)
			if slot == 4 and int(character.id) == 3:
				actor.add_buff(str(character.jp), 5)
			_check(actor.request_attack(slot).success, "Character %s slot %s casts" % [character.id, slot])
			var result = _advance(actor, 20.0, true)
			_check(is_finite(result.damage), "Character damage finite")
			if slot != 1:
				_check(result.hits > 0, "Character %s slot %s emits hits" % [character.id, slot])
			cases.append({"character": character.id, "slot": slot, "hits": result.hits, "damage": result.damage, "diagnostics": actor.diagnostics.duplicate()})
			_collect(actor)
		var natural = Combat.new()
		natural.configure(null, null, int(character.id), 0, 982)
		_advance(natural, 0.25, true)
		for index in range(30):
			_check(natural.request_attack(0).success, "Natural combo character %s attack %s" % [character.id, index])
			var guard = 0
			while natural.is_busy() and guard < 1000:
				_advance(natural, 0.02, true)
				guard += 1
			_advance(natural, 0.12, true)
		_check(natural.special_resource() > 0, "Natural on-hit character resource %s" % character.id)
		if int(character.id) == 4:
			_check(natural.special_resource() >= 25, "Wand naturally charges heavy")
			var before = natural.special_resource()
			_check(natural.request_attack(4).success, "Wand heavy cast")
			_check(_advance(natural, 0.3, true).hits > 0, "Wand heavy hits")
			_check(natural.special_resource() == before - 25, "Wand first heavy volley consumes 25 water")
			natural.request_attack(4, false)
			_advance(natural, 2.0, true)
			_check(natural.special_resource() == before % 25, "Released wand preserves alternating volleys until water is insufficient")
		_collect(natural)
	for definition in baseline.catalog.enemies:
		var actor = Combat.new()
		_check(actor.configure_enemy(int(definition.id)).success, "Enemy configured %s" % definition.id)
		var request = actor.request_enemy_attack()
		_check(request.success or not actor.diagnostics.is_empty(), "Enemy missing attack diagnosed %s" % definition.id)
		var result = _advance(actor, 20.0, false)
		cases.append({"enemy": definition.id, "hits": result.hits, "damage": result.damage, "diagnostics": actor.diagnostics.duplicate()})
		_collect(actor)
	_test_resources_and_restore()
	_test_health_and_attributes()
	_test_status_effects()
	_test_raw_modifiers()
	_test_raw_conditions()
	_test_state_timers_and_casters()
	_test_enemy_phases_and_world_contracts()
	_test_area_targets()
	var report = {"schema": 1, "assertions": assertions, "failures": failures, "cases": cases, "effect_checks": effect_checks, "diagnostics": observed_diagnostics.keys(), "limitation": "Defense formula, interruption windows, enemy action selection and summon spatial behavior are reconstructed. Diagnostic messages are unresolved acceptance items, not passing parity claims. Recorded effect checks cover the named behavior, not every field or level variant."}
	var file = FileAccess.open("res://reports/combat_test.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report, "\t"))
	print("COMBAT TEST: %s assertions, %s failures, %s diagnostics" % [assertions, failures.size(), observed_diagnostics.size()])
	for failure in failures:
		printerr(failure)
	quit(0 if failures.is_empty() else 1)

func _test_resources_and_restore() -> void:
	var lance = Combat.new()
	lance.configure(null, null, 7)
	lance.add_buff(str(lance.fighter.jp), 300)
	lance.add_buff("700301")
	var attack = lance.effective_attack_power()
	_check(lance.request_attack(4).success, "Lance full heavy starts")
	_advance(lance, 0.12, true)
	_check(lance.charging and lance.is_transformed(), "Lance dragon form from full souls")
	_check(lance.special_resource() == 0, "Lance consumes normal resource")
	_check(is_equal_approx(lance.effective_attack_power(), attack * 1.5), "Dragon form original 50 percent attack")
	var snapshot = JSON.parse_string(JSON.stringify(lance.snapshot()))
	var copy = Combat.new()
	copy.configure(null, null, 7)
	_check(copy.restore(snapshot), "Lance snapshot restores")
	_advance(lance, 2.7, true)
	_advance(copy, 2.7, true)
	_check(lance.current_action == "lance_satk_special", "Dragon charge automatically releases")
	_check(copy.current_action == lance.current_action and copy.buff_layers("700200") == lance.buff_layers("700200"), "Dragon timers survive restore")
	_check(lance.buff_layers("700311") > 0, "Delayed third-stage damage boost fires")
	_advance(lance, 15.0, true)
	_check(not lance.is_transformed(), "Dragon transform expires")
	_check(is_equal_approx(lance.effective_attack_power(), attack), "Dragon stats expire")
	var early = Combat.new()
	early.configure(null, null, 7)
	early.add_buff(str(early.fighter.jp), 3)
	early.request_attack(4)
	_advance(early, 0.6, false)
	early.request_attack(4, false)
	_advance(early, 0.02, false)
	_check(early.current_action == "lance_satk_nomal" and early.charge_stage() == 1, "Lance early release stage one")
	var wand = Combat.new()
	wand.configure(null, null, 4)
	_advance(wand, 0.5, false)
	var normal_hit = {"definition": {"actType": "NormalAtk"}}
	wand.confirm_hit(normal_hit)
	_check(wand.special_resource() == 3, "Wand hit grants three water")
	var wand_copy = Combat.new()
	wand_copy.configure(null, null, 4)
	_check(wand_copy.restore(JSON.parse_string(JSON.stringify(wand.snapshot()))), "Resource cooldown snapshot")
	wand_copy.confirm_hit(normal_hit)
	_check(wand_copy.special_resource() == 3, "Water cooldown preserved")
	_advance(wand_copy, 0.11, false)
	wand_copy.confirm_hit(normal_hit)
	_check(wand_copy.special_resource() == 6, "Water cooldown recovers")
	var live = Combat.new()
	live.configure(null, null, 5, 0, 701)
	live.request_attack(3)
	_advance(live, 0.78, false)
	var resumed = Combat.new()
	resumed.configure(null, null, 5)
	_check(resumed.restore(JSON.parse_string(JSON.stringify(live.snapshot()))), "Pending summon timeline restores")
	var a = _advance(live, 8.0, false)
	var b = _advance(resumed, 8.0, false)
	_check(a.hits == b.hits and a.hits > 0, "Restored summon hit counts exact")
	_check(is_equal_approx(a.damage, b.damage), "Restored random and damage exact")
	_collect(lance)
	_collect(early)
	_collect(live)

func _test_health_and_attributes() -> void:
	var actor = Combat.new()
	actor.configure(null, null, 1)
	actor.health = 10.0
	actor.add_buff("110100122")
	_check(actor.health == 20.0, "Original max HP healing interpreted")
	actor.set_external_attributes({"HpAddRate": 500, "MoveSpeedRate": 200})
	_check(actor.max_health == 150, "External HP modifier once")
	_check(is_equal_approx(actor.move_multiplier(), 1.2), "External movement modifier")
	actor.set_external_attributes({"MoveSpeedRate": 100})
	actor.set_progression_buffs([{"id": "100100101", "layers": 1}], ["100100101"])
	_check(is_equal_approx(actor.move_multiplier(), 1.1), "Numeric progression root no double counting")
	_check(actor.buff_layers("100100101") == 1, "Numeric markers retained for conditions")
	actor.set_external_attributes({})
	actor.set_progression_buffs([{"id": "26012001", "layers": 1}])
	_check(actor.max_health == 200, "Progression initializes numeric child")
	actor.set_progression_buffs([])
	_check(actor.max_health == 100, "Removing progression releases owned child")
	var base = actor.effective_attack_power()
	actor.add_buff("191100")
	_check(is_equal_approx(actor.effective_attack_power(), base * 1.05), "Weapon base attack rate")
	actor.add_buff("191200")
	_check(is_equal_approx(actor.effective_attack_power(), base * 1.15), "Weapon ranks exclude previous")
	actor.invincible = 1.0
	var hit = {"damage": 100.0, "definition": {}}
	_check(actor.receive(hit, 100) == 0, "Dodge invulnerability")
	_advance(actor, 1.1, false)
	_check(actor.receive(hit, 100) > 0, "Damage after invulnerability")
	actor.request_attack(3)
	actor.health = 0
	_check(actor.revive(50), "Dead actor revives")
	_check(actor.health == 50 and actor.invincible == 2 and not actor.is_busy(), "Revive restores health and cancels fatal cast")
	_check(actor.snapshot().pending.is_empty(), "Revive clears pending hits")
	_check(not actor.revive(100), "Living actor cannot revive")
	var malformed = actor.snapshot()
	malformed.character_id = 5
	_check(not actor.restore(malformed), "Actor mismatch snapshot rejected")
	_collect(actor)

func _test_status_effects() -> void:
	var actor = Combat.new()
	actor.configure(null, null, 1)
	actor.set_stats(actor.attack, actor.defense, 10000.0)
	actor.health = actor.max_health
	actor.add_buff("119901", 1, 100)
	var before = actor.health
	_advance(actor, 1.0, false)
	_check(actor.health < before, "Original burn ticks")
	_advance(actor, 10.0, false)
	_check(actor.buff_layers("119901") == 0, "Burn expires")
	actor.add_buff("100300101")
	_check(actor.armor > 0, "Recovered armor coefficient applied")
	var armor_before = actor.armor
	actor.receive({"damage": 10, "definition": {}}, 10)
	_check(actor.armor < armor_before, "Armor absorbs incoming damage")
	actor.add_buff("202511191")
	_check(actor.shield > 0, "Recovered shield coefficient applied")
	actor.add_buff("not_present")
	_check(actor.diagnostics.has("Missing buff not_present"), "Unknown buff is diagnosed")
	_collect(actor)

func _test_raw_modifiers() -> void:
	var source = Combat.new()
	source.configure(null, null, 1)
	var target = Combat.new()
	target.configure_enemy(11001)
	target.set_stats(1, 100, 10000)
	target.health = target.max_health
	var hit = {"source": source, "damage": 100.0, "sequence": 1, "emission": 1, "definition": {"damageId": 210101, "actType": "NormalAtk", "element": "Fire"}}
	_check(is_equal_approx(target.receive(hit, source.attack), 50.0), "Unmodified defense curve")
	source.add_buff("103101")
	_check(is_equal_approx(target.receive(hit, source.attack), 65.0), "Recovered overheat adds 30 percent normal damage", ["103101"])
	hit.definition.actType = "SpecAtk"
	_check(is_equal_approx(target.receive(hit, source.attack), 50.0), "Overheat excludes heavy attacks")
	source.remove_buff("103101")
	source.add_buff("100300201")
	_check(is_equal_approx(target.receive(hit, source.attack), 100.0 * 100.0 / 185.0), "Recovered 15 percent defense penetration", ["100300201"])
	source.remove_buff("100300201")
	target.set_stats(1, 0, 10000)
	target.health = target.max_health
	target.add_buff("50230430")
	hit.damage = 100000.0
	_check(is_equal_approx(target.receive(hit, source.attack), 3000.0), "Sacrifice set caps damage at original 30 percent max HP", ["50230430"])
	target.remove_buff("50230430")
	target.add_buff("740901")
	hit.damage = 100.0
	_check(target.receive(hit, source.attack) == 0.0, "Awakening original immunity modifier")
	_check(target.receive(hit, source.attack) == 100.0, "Immunity cooldown prevents immediate retrigger")
	var saved = JSON.parse_string(JSON.stringify(target.snapshot()))
	var copy = Combat.new()
	copy.configure_enemy(11001)
	_check(copy.restore(saved), "Raw modifier cooldown snapshot restores")
	_check(copy.receive(hit, source.attack) == 100.0, "Restored raw modifier cooldown enforced")
	_advance(copy, 1.01, false)
	_check(copy.receive(hit, source.attack) == 0.0, "Raw immunity returns after cooldown", ["740901"])
	_collect(source)
	_collect(target)

func _test_area_targets() -> void:
	var target = Combat.new()
	target.configure(null, null, 1)
	var event = {"definition": {"radius": 2.0, "includeSelf": false, "sameCamp": false, "enableDamage": true, "damageId": 1, "attribute": "FinalAtk", "element": "Fire", "actType": "Other", "targetBuffs": []}, "damage": 10.0, "caster_attack": 10.0}
	_check(not target.apply_area(event, false, 4.01), "Area exact radius excludes beyond boundary")
	_check(not target.apply_area(event, true, 1.0), "Enemy area excludes allies")
	_check(not target.apply_area(event, false, 1.0, true), "Area excludes self when configured")
	var before = target.health
	_check(target.apply_area(event, false, 4.0), "Area includes exact radius boundary")
	_check(target.health < before, "Area applies damage through defense")
	event.definition.sameCamp = true
	event.definition.includeSelf = true
	_check(target.apply_area(event, true, 0.0, true), "Area can explicitly include self")
	_check(not target.apply_area(event, false, NAN), "Area rejects invalid distance")

func _test_raw_conditions() -> void:
	var actor = Combat.new()
	actor.configure(null, null, 1)
	actor.add_buff("103100")
	_check(actor.request_attack(3).success, "Burst for raw action-end listener starts")
	_check(actor.buff_layers("103101") == 0, "Overheat waits for burst end")
	_advance(actor, actor.busy + 0.02, false)
	_check(actor.buff_layers("103101") == 1, "Original burst end grants overheat", ["103100", "103101"])
	actor.health = 30.0
	actor.add_buff("110100190")
	actor.confirm_hit({"definition": {"actType": "SpecAtk"}})
	_check(actor.health == 30.0, "Lifesteal filters heavy damage")
	actor.confirm_hit({"definition": {"actType": "NormalAtk"}})
	_check(actor.health == 40.0, "Original normal-hit listener heals ten percent", ["110100190", "110100191"])
	actor.confirm_hit({"definition": {"actType": "NormalAtk"}})
	_check(actor.health == 40.0, "Lifesteal cooldown avoids repeated hit heal")
	_advance(actor, 1.01, false)
	actor.confirm_hit({"definition": {"actType": "NormalAtk"}})
	_check(actor.health == 50.0, "Lifesteal cooldown recovers")
	var axe = Combat.new()
	axe.configure(null, null, 3)
	axe.health = 30.0
	axe.add_buff("391100")
	_check(axe.buff_layers("391101") == 1, "Weapon initializes kill listener")
	var victim = Combat.new()
	victim.configure_enemy(11001)
	victim.health = 1.0
	victim.receive({"source": axe, "damage": 1000.0, "definition": {"actType": "NormalAtk"}}, axe.attack)
	_check(axe.health == 31.0, "Kill event heals original fixed one HP damage definition", ["391100", "391101", "391102"])
	var delayed = Combat.new()
	delayed.configure(null, null, 3)
	delayed.add_buff("340400")
	delayed.notify_gameplay("action_end", {"slot": 3})
	_check(delayed.buff_layers("340401") == 0, "Awakening waits original two hundred milliseconds")
	_check(delayed.request_attack(1).success, "Dodge interrupts pending awakening cast")
	var copy = Combat.new()
	copy.configure(null, null, 3)
	_check(copy.restore(JSON.parse_string(JSON.stringify(delayed.snapshot()))), "Delayed condition JSON snapshot restores")
	_advance(delayed, 0.21, false)
	_advance(copy, 0.21, false)
	_check(delayed.buff_layers("340401") == 10, "Delayed awakening survives dodge cancellation")
	_check(copy.buff_layers("340401") == delayed.buff_layers("340401"), "Delayed awakening readback exact", ["340400", "340401"])
	_collect(actor)
	_collect(axe)
	_collect(delayed)

func _test_state_timers_and_casters() -> void:
	var attacker = Combat.new()
	attacker.configure_enemy(11001)
	var hit = {"source": attacker, "damage": 10.0, "definition": {}}
	for id in ["214105", "795110"]:
		var actor = Combat.new()
		actor.configure(null, null, 1)
		actor.add_buff("50201120")
		actor.add_buff(id)
		_check(actor.receive(hit, attacker.attack) == 0.0, "State %s prevents contact damage" % id)
		_check(actor.buff_layers("50201121") > 0, "State %s dispatches successful dodge/block" % id, [id, "50201120"])
		var copy = Combat.new()
		copy.configure(null, null, 1)
		_check(copy.restore(JSON.parse_string(JSON.stringify(actor.snapshot()))), "State %s timers restore" % id)
		_check(copy.receive(hit, attacker.attack) == 0.0, "State %s restored protection remains" % id)
		_advance(copy, 1.01, false)
		_check(copy.receive(hit, attacker.attack) > 0.0, "State %s protection expires" % id)
		_collect(actor)
	var wounded = Combat.new()
	wounded.configure(null, null, 1)
	wounded.health = 20.0
	wounded.add_buff("50221911")
	wounded.add_buff("110100191")
	_check(wounded.health == 20.0, "Original antiheal blocks healing")
	var resumed = Combat.new()
	resumed.configure(null, null, 1)
	_check(resumed.restore(JSON.parse_string(JSON.stringify(wounded.snapshot()))), "Antiheal JSON timers restore")
	resumed.add_buff("110100191")
	_check(resumed.health == 20.0, "Antiheal persists after restore")
	_advance(resumed, 2.01, false)
	resumed.add_buff("110100191")
	_check(resumed.health == 30.0, "Antiheal expiration permits healing", ["50221911"])
	var caster = Combat.new()
	caster.configure_enemy(11001)
	caster.actor_key = "room:8:enemy:4"
	caster.shield = 25.0
	var receiver = Combat.new()
	receiver.configure(null, null, 1)
	receiver.bind_buff_caster("25112501", caster)
	receiver.add_buff("25112501")
	_check(receiver.attribute("DefAddFixed") == 25.0, "Transferred dynamic conversion uses caster shield")
	caster.shield = 32.0
	_check(receiver.attribute("DefAddFixed") == 32.0, "Dynamic caster attribute conversion updates")
	var saved = JSON.parse_string(JSON.stringify(receiver.snapshot()))
	_check(saved.statuses["25112501"].caster_key == caster.actor_key, "Transferred buff serializes stable caster identity")
	var caster_copy = Combat.new()
	caster_copy.configure_enemy(11001)
	_check(caster_copy.restore(JSON.parse_string(JSON.stringify(caster.snapshot()))), "Caster actor snapshot restores")
	_check(caster_copy.actor_key == caster.actor_key, "Unique actor identity survives reload")
	var receiver_copy = Combat.new()
	receiver_copy.configure(null, null, 1)
	_check(receiver_copy.restore(saved), "Transferred attribute snapshot restores")
	_check(receiver_copy.rebind_buff_casters({}).has(caster.actor_key), "Unresolved transferred caster is reported")
	_check(receiver_copy.rebind_buff_casters({caster_copy.actor_key: caster_copy}).is_empty(), "Actor map rebinds restored transferred caster")
	_check(receiver_copy.attribute("DefAddFixed") == 32.0, "Transferred caster rebind gives same attributes", ["25112501"])
	receiver.remove_buff("25112501")
	receiver.defense = 90.0
	receiver.add_buff("326101")
	_check(receiver.attribute("AtkAddFixed") == 30.0, "Snapshot conversion uses original per-three defense coefficient")
	receiver.defense = 120.0
	_check(receiver.attribute("AtkAddFixed") == 30.0, "Snapshot conversion retains application-time defense")
	receiver.add_buff("326101")
	_check(receiver.attribute("AtkAddFixed") == 40.0, "Reapplication refreshes snapshot basis", ["326101"])
	receiver.add_buff("111103")
	_check(receiver.property_value("111103_rangeup") == 20.0, "BuffExist level one provides default property")
	_advance(receiver, 5.01, false)
	_check(receiver.property_value("111103_rangeup") == null, "Editor property follows source buff expiration", ["111103"])
	_check(receiver.attribute("AtkAddFixed") == 0.0, "Snapshot conversion expires with original lifetime")
	_collect(receiver)

func _test_enemy_phases_and_world_contracts() -> void:
	for config in [{"id": 13001, "ratio": 0.5, "action": "roar"}, {"id": 23001, "ratio": 0.599, "action": "attack3"}, {"id": 33001, "ratio": 0.5, "action": "roar"}, {"id": 41002, "ratio": 0.199, "action": "attack2"}, {"id": 43001, "ratio": 0.499, "action": "P2action"}, {"id": 52001, "ratio": 0.5, "action": "LastStand"}, {"id": 53001, "ratio": 0.8, "action": "Fly2Origin"}]:
		var enemy = Combat.new()
		enemy.configure_enemy(int(config.id))
		enemy.health = enemy.max_health * float(config.ratio)
		_check(enemy.request_enemy_attack().success, "Enemy %s enters HP phase" % config.id)
		_check(enemy.current_action == config.action, "Enemy %s starts original phase action %s" % [config.id, config.action])
		_check(enemy.enemy_phase() > 0, "Enemy %s records phase" % config.id)
		var phase_events = enemy.drain_events().filter(func(event): return event.type == "phase_changed")
		_check(not phase_events.is_empty(), "Enemy %s emits phase feedback" % config.id)
		var restored = Combat.new()
		restored.configure_enemy(int(config.id))
		_check(restored.restore(JSON.parse_string(JSON.stringify(enemy.snapshot()))), "Enemy %s phase JSON restores" % config.id)
		restored.cancel()
		_check(restored.request_enemy_attack().success, "Enemy %s continues after phase restore" % config.id)
		_check(restored.drain_events().filter(func(event): return event.type == "phase_changed").is_empty(), "Enemy %s phase cannot repeat after restore" % config.id)
		_collect(enemy)
	var griffin = Combat.new()
	griffin.configure_enemy(23001)
	griffin.health = griffin.max_health * 0.6
	griffin.request_enemy_attack()
	_check(griffin.enemy_phase() == 0, "Griffin original less-than threshold excludes exactly sixty percent")
	griffin.cancel()
	griffin.health -= 0.01
	griffin.request_enemy_attack()
	_check(griffin.current_action == "attack3", "Griffin takeoff begins below sixty percent")
	_advance(griffin, 61.0, false)
	_check(not bool(griffin.custom_properties.BB_IsFlyState), "Griffin original sixty-second air timer lands")
	_check(griffin.request_enemy_attack().success and griffin.current_action == "attack6", "Griffin original landing attack dequeues")
	var dragon = Combat.new()
	dragon.configure_enemy(53001)
	dragon.health = dragon.max_health * 0.2
	dragon.request_enemy_attack()
	_check(dragon.enemy_phase() == 3, "Dragon large damage crosses all three phase thresholds")
	_check(dragon.custom_properties._enemy_phase_triggered.size() == 3, "Dragon threshold IDs persisted")
	var saved = JSON.parse_string(JSON.stringify(dragon.snapshot()))
	var dragon_copy = Combat.new()
	dragon_copy.configure_enemy(53001)
	_check(dragon_copy.restore(saved), "Dragon threshold sequence restores")
	for expected in ["roar1", "Fly2Origin", "roar2", "Fly2Origin", "roar3"]:
		dragon_copy.cancel()
		_check(dragon_copy.request_enemy_attack().success and dragon_copy.current_action == expected, "Dragon ordered phase action %s survives restore" % expected)
	var slime = Combat.new()
	slime.configure_enemy(90001)
	_check(slime.request_enemy_attack().success and slime.current_action == "runaway", "Noncombat slime uses recovered flee action")
	var player = Combat.new()
	player.configure(null, null, 1)
	player.actor_key = "player:one"
	dragon.actor_key = "room:3:boss:1"
	var hit = {"source": player, "damage": 1.0, "definition": {}}
	dragon.receive(hit, player.attack)
	_check(hit.receiver_key == dragon.actor_key and hit.source_key == player.actor_key, "Resolved hit retains actor identities")
	player.drain_events()
	_check(player.spawn_summon("295200", {"OriginType": "bornpos", "InitPosOffset": {"x": 2, "y": 0, "z": 3}}, dragon.actor_key), "World lifecycle can spawn original summon")
	var summon_events = player.drain_events().filter(func(event): return event.type == "summon")
	_check(summon_events.size() == 1 and summon_events[0].target_key == dragon.actor_key and summon_events[0].origin.OriginType == "bornpos", "Summon creation retains original origin and receiver")
	player.tick(0.01)
	var hits = player.drain_events().filter(func(event): return event.type == "hit")
	_check(not hits.is_empty() and hits[0].target_key == dragon.actor_key and hits[0].origin.InitPosOffset.x == 2, "Summon damage retains placement context")
	_collect(player)
	_collect(griffin)

func _advance(actor: DungeonCombat, seconds: float, confirm: bool) -> Dictionary:
	var hits = 0
	var damage = 0.0
	for index in range(int(ceil(seconds / 0.01))):
		actor.tick(0.01)
		for event in actor.drain_events():
			if event.type == "hit":
				hits += 1
				damage += float(event.damage)
				if confirm:
					actor.confirm_hit(event)
	return {"hits": hits, "damage": damage}

func _check(value: bool, message: String, effect_ids: Array = []) -> void:
	assertions += 1
	if not value:
		failures.append(message)
	for id in effect_ids:
		if not effect_checks.has(id):
			effect_checks[id] = []
		effect_checks[id].append({"check": message, "passed": value})

func _collect(actor: DungeonCombat) -> void:
	for diagnostic in actor.diagnostics:
		observed_diagnostics[diagnostic] = true
	actor.drain_events()
