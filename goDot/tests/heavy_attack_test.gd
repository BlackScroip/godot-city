extends SceneTree

const Combat = preload("res://scripts/domain/combat.gd")
var checks := 0
var failures: Array[String] = []
var rows: Array[Dictionary] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _initialize() -> void:
	for hz in [30, 60, 120]:
		var sword = run_case("sword-tap", 1, 0, 0.1, hz)
		check(sword.actions == ["sword_satk_normal", "sword_satk_normal_ready", "sword_satk_normal_attack"], "Sword restores ready and strike at %dHz" % hz)
		var sword_full = run_case("sword-full", 1, 5, 0.1, hz)
		check(sword_full.actions == ["sword_satk_normal", "sword_satk_upgrade"], "Sword full resource branch at %dHz" % hz)
		check(sword_full.resource == 0, "Sword source buff consumes five intent at %dHz" % hz)
		var sword_hold = run_case("sword-hold", 1, 0, 1.5, hz)
		check(sword_hold.actions.count("sword_satk_normal_attack") >= 2, "Sword held strike repeats at %dHz" % hz)
		var sickle_tap = run_case("sickle-tap", 2, 20, 0.1, hz)
		check(not sickle_tap.actions.has("sickle_satk_special"), "Sickle tap keeps ordinary strike at %dHz" % hz)
		var sickle_hold = run_case("sickle-hold", 2, 20, 1.2, hz)
		check(sickle_hold.actions.has("sickle_satk_special"), "Sickle held full resource transforms at %dHz" % hz)
		check(sickle_hold.transformed, "Sickle source transformation buff starts at %dHz" % hz)
		var axe = run_case("axe-spin", 3, 5, 5.0, hz)
		check(axe.actions[0] == "axe_satk_start", "Axe preserves windup at %dHz" % hz)
		check(axe.actions.count("axe_satk_loop") == 5 and axe.actions.has("axe_satk_end"), "Axe five spins finish at %dHz" % hz)
		check(axe.resource == 0, "Axe spends one rage per spin at %dHz" % hz)
		var wand = run_case("wand-alternate", 4, 75, 0.1, hz)
		check(wand.actions == ["wand_satk1", "wand_satk2", "wand_satk1"], "Wand preserves APK latched attack mode after release at %dHz" % hz)
		check(wand.resource == 0, "Wand pays 25 per volley and stops at %dHz" % hz)
		var bow = run_case("bow-normal", 5, 0, 0.1, hz)
		check(bow.actions == ["bow_satk"], "Bow low resource ordinary heavy at %dHz" % hz)
		var bow_full = run_case("bow-full", 5, 10, 0.1, hz)
		check(bow_full.actions == ["bow_satk", "bow_fullsatk"] and bow_full.resource == 0, "Bow ten resources select empowered volley at %dHz" % hz)
		var bow_weapon = run_case("bow-weapon", 5, 10, 0.1, hz, ["594101"])
		check(bow_weapon.actions.has("bow_fullsatk_weapon4_combine"), "Bow weapon branch retains original assembly at %dHz" % hz)
		var orb = run_case("orb-normal", 6, 0, 0.1, hz)
		check(orb.actions == ["orb_satk_start", "orb_smite_0jp"], "Orb low resource windup and strike at %dHz" % hz)
		var orb_full = run_case("orb-full", 6, 20, 0.1, hz)
		check(orb_full.actions == ["orb_satk_start", "orb_satk_shoot"], "Orb twenty faith source branch at %dHz" % hz)
		var lance = run_case("lance-early", 7, 0, 0.8, hz)
		check(lance.actions == ["lance_satk", "lance_satk_nomal"], "Lance release after window start is detected at %dHz" % hz)
		var lance_second = run_case("lance-second", 7, 0, 1.7, hz, ["700200"])
		check(lance_second.actions.has("lance_satk_nomal2"), "Lance second charge chains second strike at %dHz" % hz)
		var lance_full = run_case("lance-full", 7, 300, 5.0, hz)
		check(lance_full.actions.has("lance_satk_special"), "Lance dragon charge auto releases at %dHz" % hz)
		_test_cancel_restore(hz)
	_test_windows()
	_test_input_and_damage_gates()
	for row in rows:
		var baseline: Dictionary = rows.filter(func(other): return other.name == row.name and other.hz == 60)[0]
		check(row.actions == baseline.actions, "%s action order matches 60Hz at %dHz" % [row.name, row.hz])
		check(row.beats.size() == baseline.beats.size(), "%s damage beat count matches 60Hz at %dHz" % [row.name, row.hz])
	var report = {"checks": checks, "failures": failures, "cases": rows, "scope": "Source heavy state branches, resource costs, late release, cancellation, save compatibility and damage beats at 30/60/120Hz. No runtime parity claim against APK."}
	FileAccess.open("res://reports/heavy-attack-tests.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("HEAVY_ATTACK: %d checks, %d failures" % [checks, failures.size()])
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func run_case(title: String, id: int, resource: int, release: float, hz: int, buffs: Array = []) -> Dictionary:
	var combat = Combat.new()
	combat.configure(null, null, id, 0, 731)
	for frame in hz / 4: combat.tick(1.0 / hz)
	combat.drain_events()
	if resource > 0: combat.add_buff(str(combat.fighter.jp), resource)
	for buff in buffs: combat.add_buff(buff)
	var initial_energy = combat.energy.duplicate()
	check(combat.request_attack(4).success, "%s starts at %dHz" % [title, hz])
	var actions: Array[String] = []
	var beats: Array[Dictionary] = []
	var released = false
	for frame in 6 * hz:
		var elapsed = float(frame) / hz
		if not released and elapsed >= release:
			combat.request_attack(4, false)
			released = true
		combat.tick(1.0 / hz)
		for event in combat.drain_events():
			if event.type == "action_started": actions.append(event.action)
			if event.type == "hit": beats.append({"action": event.action, "id": event.definition.damageId, "t": elapsed, "value": event.damage})
	check(not beats.is_empty(), "%s emits damage at %dHz" % [title, hz])
	check(combat.energy[3] == initial_energy[3], "%s keeps ultimate energy separate at %dHz" % [title, hz])
	check(combat.diagnostics.is_empty(), "%s has no missing combat definitions at %dHz: %s" % [title, hz, combat.diagnostics])
	var row = {"name": title, "hz": hz, "actions": actions, "resource": combat.special_resource(), "transformed": combat.buff_layers("200202") > 0, "beats": beats}
	rows.append(row)
	return row

func _test_cancel_restore(hz: int) -> void:
	var combat = Combat.new()
	combat.configure(null, null, 7)
	combat.request_attack(4)
	for frame in hz: combat.tick(1.0 / hz)
	combat.drain_events()
	var saved = JSON.parse_string(JSON.stringify(combat.snapshot()))
	var copy = Combat.new()
	copy.configure(null, null, 7)
	check(copy.restore(saved), "Heavy local clock restores at %dHz" % hz)
	combat.request_attack(4, false)
	copy.request_attack(4, false)
	combat.tick(1.0 / hz)
	copy.tick(1.0 / hz)
	check(combat.current_action == copy.current_action and copy.current_action == "lance_satk_nomal", "Restored release window matches at %dHz" % hz)
	check(copy.request_attack(1).success, "Dodge cancels heavy immediately at %dHz" % hz)
	copy.drain_events()
	for frame in 3 * hz:
		copy.tick(1.0 / hz)
		for event in copy.drain_events():
			check(event.type != "hit" or event.slot != 4, "Dodge removes unlaunched heavy hit at %dHz" % hz)
	check(not copy.charging and not copy.custom_properties.InputAttack_LongPress, "Dodge clears held charge at %dHz" % hz)
	var legacy = saved.duplicate(true)
	legacy.custom_properties.erase("_local_action_elapsed")
	legacy.custom_properties.erase("AttackModeStr")
	check(copy.restore(legacy), "Legacy heavy save remains readable at %dHz" % hz)

func _test_windows() -> void:
	var axe = Combat.new()
	axe.configure(null, null, 3)
	check(not axe.request_attack(4).success, "Axe cannot start spin without rage")
	var sword = Combat.new()
	sword.configure()
	sword.request_attack(4)
	for frame in 30: sword.tick(0.01)
	check(sword.input_action_delay(2) == 0, "Sword ready exposes source skill cancel window")
	check(sword.request_attack(2).success, "Skill cancels ready action through source window")
	sword.drain_events()
	for frame in 100:
		sword.tick(0.01)
		for event in sword.drain_events():
			check(event.type != "hit" or event.slot != 4, "Cancelled ready cannot emit a stale heavy strike")

func _test_input_and_damage_gates() -> void:
	var combat = Combat.new()
	combat.configure()
	combat.add_buff("100300", 5)
	combat.request_attack(4)
	combat.request_attack(4, false)
	for frame in 60: combat.tick(0.01)
	check(combat.can_receive_attack(), "Empowered sword source IsCanBeHit overrides its protected base")
	var lance = Combat.new()
	lance.configure(null, null, 7)
	lance._start(lance._action("ActGroup_playerchara", "lance_satk_nomal"), 4)
	lance.tick(0.01)
	check(lance.can_receive_attack(), "Ordinary lance release does not invent charged protection")
	lance.add_buff("700003")
	lance.tick(0.01)
	check(lance.can_receive_attack(), "A failed trigger condition does not become eligible later in its duration")
	lance._start(lance._action("ActGroup_playerchara", "lance_satk_nomal"), 4)
	lance.tick(0.01)
	check(not lance.can_receive_attack(), "Lance charge at the original trigger enables source collision protection")
	lance.remove_buff("700003")
	lance.custom_properties["_action_can_hit"] = true
	lance.tick(0.01)
	check(not lance.can_receive_attack(), "Registered duration continues writing without rechecking the trigger condition")
	var collision = {"definition": {"damageId": 1}, "damage": 10.0}
	check(lance.receive(collision) == 0 and not collision.resolved_accepted, "Attack collision rejection emits no flesh confirmation")
	var buff_damage = {"definition": {}, "damage": 10.0, "attack_collision": false}
	check(lance.receive(buff_damage) > 0, "Action collision gate does not invent immunity for buff damage")
	var restored = Combat.new()
	restored.configure(null, null, 7)
	check(restored.restore(lance.snapshot()) and not restored.can_receive_attack(), "Save restores action-local collision override")
	var legacy = lance.snapshot()
	legacy.custom_properties.erase("_action_can_hit")
	legacy.custom_properties.erase("_can_hit_evaluated")
	legacy.custom_properties.erase("_can_hit_windows")
	lance.add_buff("700003")
	legacy.statuses = lance.snapshot().statuses
	check(restored.restore(legacy) and not restored.can_receive_attack(), "Legacy save reconstructs source collision override")
	lance.request_attack(1)
	for frame in 60: lance.tick(0.01)
	check(lance.can_receive_attack(), "Dodge resets source collision override without residual immunity")
	combat.custom_properties.InputMove = true
	for frame in 48: combat.tick(0.01)
	check(not combat.is_busy() and combat.can_receive_attack(), "Movement cancels source recovery and collision protection")
	var intent = preload("res://scripts/player_intent.gd").new()
	combat.configure()
	intent.request(combat, 4, true)
	check(intent.take_ready(combat, 0.01) == 4, "Heavy initial request uses input buffer")
	combat.request_attack(4)
	for frame in 10: combat.tick(0.01)
	intent.request(combat, 4, false)
	for frame in 65: combat.tick(0.01)
	check(intent.request(combat, 4, true).success and combat.custom_properties.InputAttack, "Heavy re-press updates held input during strike")
	for frame in 15: combat.tick(0.01)
	check(combat.current_action == "sword_satk_normal_attack" and combat.action_elapsed < 0.1, "Re-press is consumed by the original repeat window")
	for frame in 37: combat.tick(0.01)
	check(intent.request(combat, 0, true).success, "Normal attack fits recovery input buffer")
	check(combat.custom_properties.AttackModeStr == "normal", "Buffered normal input changes mode before repeat can steal it")
	var taken := 0
	for frame in 30:
		var slot = intent.take_ready(combat, 0.01)
		if slot >= 0:
			taken += 1
			check(combat.request_attack(slot).success, "Buffered normal starts at source cancel window")
		combat.tick(0.01)
	check(taken == 1 and combat._current_slot == 0, "Normal input executes once after held heavy")
	var sickle = Combat.new()
	sickle.configure(null, null, 2)
	sickle.add_buff("200200", 20)
	sickle.request_attack(4)
	for frame in 200: sickle.tick(0.01)
	check(sickle.is_transformed(), "Sickle form remains after source transformation starts")
	sickle.request_attack(4, false)
	for frame in 800: sickle.tick(0.01)
	check(sickle.buff_layers("200202") > 0 and sickle.buff_layers("200201") > 0, "Sickle form bonuses stay synchronized with remaining layers")
	for frame in 800: sickle.tick(0.01)
	check(not sickle.is_transformed() and sickle.buff_layers("200201") == 0, "Sickle form and bonuses expire together")
	var sword = Combat.new()
	sword.configure()
	sword.add_buff("100300", 5)
	sword.request_attack(4)
	var times: Array[float] = []
	for frame in 160:
		if frame == 80: sword.request_attack(1)
		sword.tick(0.01)
		for event in sword.drain_events():
			if event.type == "hit" and event.slot == 4: times.append(float(frame) * 0.01)
	check(times.size() == 9, "Dodge retains all nine already summoned empowered strikes")
	for index in range(1, times.size()): check(absf(times[index] - times[index - 1] - 0.05) <= 0.011, "Dimensional strike retains its source 50ms beats")
	combat.drain_events()
	sickle.drain_events()
	lance.drain_events()
	restored.drain_events()
