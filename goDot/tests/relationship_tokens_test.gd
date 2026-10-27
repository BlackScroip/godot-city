extends SceneTree

const Catalog = preload("res://scripts/domain/catalog.gd")
const Profile = preload("res://scripts/domain/profile.gd")
const Systems = preload("res://scripts/domain/systems.gd")
const Tokens = preload("res://scripts/domain/relationship_tokens.gd")
var checks := 0
var failures: Array[String] = []
var catalog

func _initialize() -> void:
	run_tests.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func fresh():
	var s = Systems.new(catalog, Profile.new())
	s.profile.data.buildings["1"] = 3
	s.profile.data.buildings["2"] = 3
	s.grant_material(101, 1000000)
	s.grant_material(108, 100000)
	s.grant_material(90002, 100000)
	return s

func run_tests() -> void:
	catalog = Catalog.new()
	check(catalog.load_all(), "catalog loads")
	var old = Profile.new()
	old.data.selected_character = 81
	old.data.equipped_tokens = [50011]
	old.data.equipped_amplifiers = [51001]
	old.data.materials["51001"] = 7
	old.data.stats["token:50011"] = 3
	var wallet = old.data.materials.duplicate(true)
	Tokens.migrate(old.data)
	check(old.data.char_equipped_tokens.get("81") == [50011], "migration assigns legacy tokens to selected character")
	check(old.data.char_token_amplifier_slots.is_empty() and old.data.token_amplifier_unlocked_slots.is_empty(), "migration creates no free sockets")
	check(old.data.materials == wallet and old.data.equipped_amplifiers.is_empty(), "migration preserves wallet and releases global amplifiers")
	var migrated = old.data.duplicate(true)
	Tokens.migrate(old.data)
	check(migrated == old.data, "migration is idempotent")
	check(Tokens.validate_state(old.data), "migrated save validates")
	var s = fresh()
	var t = s.relationship_tokens
	var token = int(t.ids()[0])
	var amp = int(catalog.rows("RelationshipAmplifyData").filter(func(row): return str(row.rare) == "Tier1")[0].id)
	s.profile.data.selected_character = 81
	s.set_record("token:" + str(token), 2)
	check(not t.unlock_socket(token, 0).success, "level2 cannot unlock socket")
	s.set_record("token:" + str(token), 3)
	var essence = s.material(108)
	var gold = s.material(101)
	check(t.unlock_socket(token, 0).success, "level3 unlocks socket")
	check(s.material(108) == essence - 500 and s.material(101) == gold, "socket costs500 essence and no gold")
	check(not t.unlock_socket(token, 0).success and s.material(108) == essence - 500, "duplicate unlock does not charge")
	check(not t.unlock_socket(token, 3).success, "only three sockets")
	s.grant_material(amp, 1)
	check(t.equip(token).success, "token equips")
	check(t.equip_amplifier(81, token, 0, amp).success, "amplifier equips in current character socket")
	check(t.available(amp) == 0 and t.active_amplifiers() == [amp], "socket reserves owned copy")
	check(t.unlock_socket(token, 1).success and not t.equip_amplifier(81, token, 1, amp).success, "cannot reserve same copy twice")
	check(not t.equip_amplifier(82, token, 0, amp).success, "cannot mutate non-current character")
	var current_effects = Catalog.ids(t.level_row(token, 3).get("abilityitem_id", ""))
	current_effects.append_array(Catalog.ids(catalog.find("RelationshipAmplifyData", amp).get("abilityitem_id", "")))
	check(t.ability_ids() == current_effects, "only current token level effect applied")
	check(t.save_preset(14).success and not t.save_preset(15).success, "fifteen preset slots")
	s.profile.data.selected_character = 82
	t.normalize()
	check(t.equipped().is_empty() and t.active_amplifiers().is_empty() and t.available(amp) == 1, "new character has independent loadout")
	check(t.load_preset(14).success and t.active_amplifiers() == [amp], "shared preset can be applied to another character")
	s.profile.data.selected_character = 81
	t.normalize()
	check(t.slots(token)[0] == amp, "role switch preserves original sockets")
	check(t.unequip(token, 0).success and t.available(amp) == 1, "unequip releases reservation")
	s.grant_material(amp, 3)
	check(not t.compose({"groups": {str(amp): 1}}).success, "four copies cannot compose")
	s.grant_material(amp, 1)
	var quote = t.compose_quote({"groups": {str(amp): 1}})
	check(quote.success and int(quote.price[str(amp)]) == 5 and int(quote.price["101"]) == 500, "tier1 quote consumesfive and500gold")
	s.profile.data.amplifier_draw_state.base_seed = 12345
	var restored_profile = Profile.new()
	restored_profile.data = JSON.parse_string(JSON.stringify(s.profile.data))
	var restored = Systems.new(catalog, restored_profile)
	var run_before = s.profile.data.run.duplicate(true)
	gold = s.material(101)
	var result = t.compose({"groups": quote.groups, "revision": quote.revision})
	var replay = restored.relationship_tokens.compose({"groups": quote.groups, "revision": quote.revision})
	check(result.success and result.outputs == replay.outputs, "reloaded draw gives same result")
	check(s.material(amp) == 0 and s.material(101) == gold - 500, "composition charges exactly once")
	check(s.profile.data.run == run_before, "compose does not alter adventure random state")
	check(not t.compose({"groups": quote.groups, "revision": quote.revision}).success, "stale confirmation rejected")
	check(Tokens.validate_state(s.profile.data), "post-compose state validates")
	for index in 8:
		var fee = int(t.reroll_quote().price["90002"])
		check(fee == [100, 120, 140, 160, 180, 200, 200, 200][index], "rerollfee%d" % index)
		check(t.reroll().success, "reroll%d succeeds beyondsix" % index)
	check(t.load_preset(14).success and t.active_amplifiers().is_empty(), "preset skips consumed copies")
	var invalid = s.profile.data.duplicate(true)
	invalid.char_token_amplifier_slots["81"][str(token)] = [amp]
	check(not Tokens.validate_state(invalid), "invalid socket count rejected")
	invalid = s.profile.data.duplicate(true)
	invalid.amplifier_draw_state.tiers["2"].counter = -1
	check(not Tokens.validate_state(invalid), "invalid draw counter rejected")
	s.profile.data.run.active = true
	check(not t.equip(token).success and not t.reroll().success and not t.save_preset(0).success, "camp mutations blocked during run")
	_test_reentrant_transactions()
	_test_tiers_and_restore()
	_test_equipment_json_restore()
	var report = {"checks": checks, "failures": failures, "passed": failures.is_empty()}
	var file = FileAccess.open("res://reports/relationship-tokens-tests.json", FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "\t"))
	print("RELATIONSHIP_TOKENS_TEST ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func _attempt_reentrant_changes(t, token: int, amp: int) -> bool:
	var results: Array = [t.upgrade(token), t.unlock_socket(token, 1), t.compose({str(amp): 1}), t.reroll(), t.equip(token), t.equip_amplifier(81, token, 0, amp), t.unequip(token, 0), t.unequip_all(), t.save_preset(1), t.load_preset(0), t.delete_preset(0)]
	return results.any(func(result): return result.success)

func _test_reentrant_transactions() -> void:
	for action in ["upgrade", "unlock_socket", "compose", "reroll"]:
		var s = fresh()
		var t = s.relationship_tokens
		var token = int(t.ids()[0])
		var amp = 60001
		s.profile.data.selected_character = 81
		s.set_record("token:" + str(token), 3)
		s.grant_material(amp, 20)
		t.save_preset(0)
		if action == "reroll": check(t.compose({str(amp): 1}).success, "prepare reroll transaction")
		var attempts: Array = []
		var resource_listener = func(event):
			if event.type not in ["resource_spent", "resource_gained"]: return
			var before = JSON.stringify(s.profile.data)
			attempts.append(_attempt_reentrant_changes(t, token, amp))
			check(JSON.stringify(s.profile.data) == before, action + " resource callback leaves transaction state unchanged")
		var changed_listener = func(): attempts.append(_attempt_reentrant_changes(t, token, amp))
		s.gameplay_event.connect(resource_listener)
		s.changed.connect(changed_listener)
		var before_essence = s.material(108)
		var before_gold = s.material(101)
		var before_crystals = s.material(90002)
		var result: Dictionary
		match action:
			"upgrade": result = t.upgrade(token)
			"unlock_socket": result = t.unlock_socket(token, 0)
			"compose": result = t.compose({str(amp): 1})
			"reroll": result = t.reroll()
		s.gameplay_event.disconnect(resource_listener)
		s.changed.disconnect(changed_listener)
		check(result.success and attempts.size() >= 2 and not attempts.has(true), action + " blocks nested mutations through resource and completion signals")
		match action:
			"upgrade": check(s.material(108) == before_essence - 300 and s.stat("token:" + str(token)) == 4, "reentrant upgrade charges once and advances once")
			"unlock_socket": check(s.material(108) == before_essence - 500 and s.profile.data.token_amplifier_unlocked_slots[str(token)] == [0], "reentrant unlock charges once without duplicate slot")
			"compose": check(s.material(101) == before_gold - 500 and s.material(amp) == 15 and s.profile.data.amplifier_draw_state.revision == 1, "reentrant composition commits one batch")
			"reroll": check(s.material(90002) == before_crystals - 100 and s.profile.data.amplifier_draw_state.revision == 2 and s.profile.data.amplifier_draw_state.last.rerolls == 1, "reentrant reroll consumes one fee and one draw")
		check(Tokens.validate_state(s.profile.data), action + " leaves valid persistent state")
		check(t.unlock_socket(token, 2).success, action + " releases transaction lock afterward")

func _output_tiers(t, outputs: Dictionary) -> Dictionary:
	var result := {}
	for key in outputs:
		var tier = str(t.tier_of(int(key)))
		result[tier] = int(result.get(tier, 0)) + int(outputs[key])
	return result

func _test_tiers_and_restore() -> void:
	var s = fresh()
	var t = s.relationship_tokens
	s.profile.data.amplifier_draw_state.base_seed = 39429
	var request := {"60001": 2, "60101": 1, "60201": 1, "60301": 2}
	for key in request: s.grant_material(int(key), int(request[key]) * 5)
	s.grant_material(60401, 5)
	var before = JSON.stringify(s.profile.data)
	check(not t.compose({"60401": 1}).success and before == JSON.stringify(s.profile.data), "tier5 cannot compose or mutate state")
	check(not t.compose_quote({"groups": []}).success, "non-dictionary groups rejected")
	check(not t.compose_quote({"60001": 1, "060001": 1}).success, "duplicate numeric aliases cannot yield two outputs for one cost")
	check(not t.compose_quote({"60001": 0.5}).success and not t.compose_quote({"60001": -1}).success, "fractional and negative batch quantities rejected")
	var quote = t.compose_quote({"groups": request})
	check(quote.success and quote.price["101"] == 24000 and quote.tiers == {"2": 2, "3": 1, "4": 1, "5": 2}, "mixed batch sums each source tier price independently")
	var gold = s.material(101)
	var result = t.compose({"groups": request, "revision": quote.revision})
	check(result.success and s.material(101) == gold - 24000, "mixed tier batch charges exact total")
	check(_output_tiers(t, result.outputs) == quote.tiers and s.material(60401) >= 5, "mixed batch returns only the next tier and preserves existing tier5")
	for tier in quote.tiers: check(s.profile.data.amplifier_draw_state.tiers[tier].counter == quote.tiers[tier], "independent draw counter " + tier)
	var profile = Profile.new()
	check(profile.restore(JSON.parse_string(JSON.stringify(s.profile.data))), "batch state restores through profile validator")
	var resumed = Systems.new(catalog, profile)
	var crystals = s.material(90002)
	check(t.reroll().success and resumed.relationship_tokens.reroll().success, "mixed batch rerolls after reload")
	check(s.profile.data.amplifier_draw_state.last == resumed.profile.data.amplifier_draw_state.last and s.material(90002) == crystals - 100, "reload preserves every tier counter and batch reroll result")
	check(_output_tiers(t, s.profile.data.amplifier_draw_state.last.outputs) == quote.tiers, "reroll preserves per-tier batch counts")
	for malformed in [{"outputs": {"60101": -1}, "rerolls": 0}, {"outputs": {"60101": 1}, "rerolls": -1}, {"outputs": [], "rerolls": 0}]:
		var bad = s.profile.data.duplicate(true)
		bad.amplifier_draw_state.last = malformed
		check(not Profile.new().restore(bad), "malformed persisted reroll rejected")
	for unknown in [101, 60001, 999999]:
		var bad = s.profile.data.duplicate(true)
		bad.amplifier_draw_state.last = {"outputs": {str(unknown): 1}, "rerolls": 0}
		var loaded = Profile.new()
		check(loaded.restore(bad), "structurally valid old save can be inspected")
		var recovered = Systems.new(catalog, loaded)
		var saved = JSON.stringify(loaded.data)
		check(not recovered.relationship_tokens.reroll().success and saved == JSON.stringify(loaded.data), "unknown or impossible prior output fails without spending " + str(unknown))

func _test_equipment_json_restore() -> void:
	var s = fresh()
	var t = s.relationship_tokens
	for token in [50001, 50011]: s.set_record("token:" + str(token), 3)
	for amp in [60001, 60002, 60003]: s.grant_material(amp, 1)
	s.profile.data.selected_character = 1
	check(t.equip(50001).success, "JSON fixture equips first character token")
	for index in 3:
		check(t.unlock_socket(50001, index).success and t.equip_amplifier(1, 50001, index, 60001 + index).success, "JSON fixture first character socket " + str(index))
	check(t.save_preset(0).success, "JSON fixture first character preset")
	s.profile.data.selected_character = 2
	t.normalize()
	check(t.equip(50011).success, "JSON fixture equips second character token")
	for index in [0, 2]:
		check(t.unlock_socket(50011, index).success and t.equip_amplifier(2, 50011, index, 60002 if index == 0 else 60003).success, "JSON fixture second character socket " + str(index))
	check(t.save_preset(1).success, "JSON fixture second character preset")
	s.profile.data.selected_character = 1
	t.normalize()
	var serialized = JSON.parse_string(JSON.stringify(s.profile.data))
	check(serialized.token_amplifier_unlocked_slots["50001"][0] is float, "fixture exercises actual JSON floating point IDs")
	var restored = Profile.new()
	check(restored.restore(serialized), "valid JSON socket index arrays pass restore validation")
	if not restored.data.has("char_equipped_tokens"): return
	check(restored.data.char_equipped_tokens["1"] == [50001] and restored.data.char_equipped_tokens["2"] == [50011], "profile restore normalizes both character token ID arrays")
	check(restored.data.token_amplifier_unlocked_slots["50001"] == [0, 1, 2] and restored.data.token_amplifier_unlocked_slots["50011"] == [0, 2], "profile restore normalizes socket indices before membership checks")
	check(restored.data.char_token_amplifier_slots["1"]["50001"] == [60001, 60002, 60003] and restored.data.char_token_amplifier_slots["2"]["50011"] == [60002, 0, 60003], "profile restore normalizes both characters amplifier arrays")
	check(restored.data.token_amplifier_presets["0"].tokens == [50001] and restored.data.token_amplifier_presets["0"].slots["50001"] == [60001, 60002, 60003], "profile restore normalizes preset token and amplifier IDs")
	check(restored.data.token_amplifier_presets["1"].tokens == [50011] and restored.data.token_amplifier_presets["1"].slots["50011"] == [60002, 0, 60003], "second preset survives restore")
	var resumed = Systems.new(catalog, restored)
	var rt = resumed.relationship_tokens
	check(rt.equipped(1) == [50001] and rt.equipped(2) == [50011], "domain construction preserves both equipped token lists")
	check(rt.slots(50001, 1) == [60001, 60002, 60003] and rt.slots(50011, 2) == [60002, 0, 60003], "domain normalization does not erase loaded amplifiers")
	check(rt.socket_unlocked(50001, 0) and rt.socket_unlocked(50001, 1) and rt.socket_unlocked(50001, 2), "restored socket membership works for each index")
	check(rt.active_amplifiers(1) == [60001, 60002, 60003] and rt.active_amplifiers(2) == [60002, 60003], "restored active amplifier effects remain equipped")
	var wallet = restored.data.materials.duplicate(true)
	check(not rt.unlock_socket(50001, 0).success and wallet == restored.data.materials, "restored unlocked slot cannot charge a second time")
	restored.data.selected_character = 2
	rt.normalize()
	check(rt.status(50011).equipped and rt.available(60002) == 0, "role switch sees restored selection and reserved copies")
	check(rt.load_preset(0).success and rt.equipped() == [50001] and rt.active_amplifiers() == [60001, 60002, 60003], "restored preset applies integer IDs on another character")
	var again = Profile.new()
	check(again.restore(JSON.parse_string(JSON.stringify(restored.data))) and Tokens.validate_state(again.data), "second save roundtrip remains valid")
	var duplicate = serialized.duplicate(true)
	duplicate.token_amplifier_unlocked_slots["50001"] = [0.0, 0]
	check(not Profile.new().restore(duplicate), "mixed numeric duplicate socket indices rejected")
	duplicate.token_amplifier_unlocked_slots["50001"] = [0.5]
	check(not Profile.new().restore(duplicate), "fractional socket indices still rejected")
