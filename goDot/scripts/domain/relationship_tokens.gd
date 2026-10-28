extends RefCounted

const Catalog = preload("res://scripts/domain/catalog.gd")
const SCHEMA_VERSION := 2
const PRESET_COUNT := 15
var _owner: WeakRef
var _mutating := false
var systems:
	get: return _owner.get_ref()

func _init(owner) -> void:
	_owner = weakref(owner)
	migrate(systems.profile.data)
	normalize()

static func migrate(data: Dictionary) -> void:
	if int(data.get("camp_schema_version", 0)) >= SCHEMA_VERSION: return
	var character := str(int(data.get("selected_character", 1)))
	data["char_equipped_tokens"] = {character: data.get("equipped_tokens", []).duplicate()}
	data["char_token_amplifier_slots"] = {}
	data["token_amplifier_unlocked_slots"] = {}
	data["token_amplifier_presets"] = {}
	data["amplifier_draw_state"] = {"base_seed": 0, "tiers": {}, "revision": 0, "last": {}}
	data["legacy_camp_equipment"] = {"tokens": data.get("equipped_tokens", []).duplicate(), "amplifiers": data.get("equipped_amplifiers", []).duplicate(), "amplifier_slots": int(data.stats.get("amplify:slots", 0))}
	data["equipped_amplifiers"] = []
	data["camp_schema_version"] = SCHEMA_VERSION

static func _integer(value, minimum := 0, maximum := 2147483647) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= minimum and value <= maximum

static func _id_list(value, maximum_count := 100) -> bool:
	return value is Array and value.size() <= maximum_count and value.all(func(id): return _integer(id, 1))

static func _slots(value) -> bool:
	if not value is Dictionary: return false
	for key in value:
		if not str(key).is_valid_int() or int(key) < 1: return false
		if not value[key] is Array or value[key].size() != 3: return false
		if not value[key].all(func(id): return _integer(id)): return false
	return true

static func validate_state(data: Dictionary) -> bool:
	if not data.has("camp_schema_version"): return true
	if not _integer(data.camp_schema_version, SCHEMA_VERSION, SCHEMA_VERSION): return false
	for field in ["char_equipped_tokens", "char_token_amplifier_slots", "token_amplifier_unlocked_slots", "token_amplifier_presets", "amplifier_draw_state"]:
		if not data.get(field) is Dictionary: return false
	for key in data.char_equipped_tokens:
		if not str(key).is_valid_int() or int(key) < 1 or not _id_list(data.char_equipped_tokens[key], 7): return false
		var seen := {}
		for id in data.char_equipped_tokens[key]:
			if seen.has(str(int(id))): return false
			seen[str(int(id))] = true
	for key in data.char_token_amplifier_slots:
		if not str(key).is_valid_int() or int(key) < 1 or not _slots(data.char_token_amplifier_slots[key]): return false
	for key in data.token_amplifier_unlocked_slots:
		if not str(key).is_valid_int() or int(key) < 1: return false
		var slots = data.token_amplifier_unlocked_slots[key]
		if not slots is Array or slots.size() > 3 or not slots.all(func(id): return _integer(id, 0, 2)): return false
		var seen := {}
		for index in slots:
			if seen.has(int(index)): return false
			seen[int(index)] = true
	for key in data.token_amplifier_presets:
		if not str(key).is_valid_int() or int(key) < 0 or int(key) >= PRESET_COUNT: return false
		var preset = data.token_amplifier_presets[key]
		if not preset is Dictionary or not _id_list(preset.get("tokens"), 7) or not _slots(preset.get("slots")): return false
	var draw: Dictionary = data.amplifier_draw_state
	if not _integer(draw.get("base_seed")) or not _integer(draw.get("revision")) or not draw.get("tiers") is Dictionary or not draw.get("last") is Dictionary: return false
	for key in draw.tiers:
		var tier = draw.tiers[key]
		if not str(key).is_valid_int() or int(key) < 1 or int(key) > 5 or not tier is Dictionary: return false
		if not _integer(tier.get("seed")) or not _integer(tier.get("counter")): return false
	if not draw.last.is_empty():
		if not draw.last.get("outputs") is Dictionary or not _integer(draw.last.get("rerolls")): return false
		for key in draw.last.outputs:
			if not str(key).is_valid_int() or int(key) < 1 or not _integer(draw.last.outputs[key], 1): return false
	return true

static func normalize_saved_ids(data: Dictionary) -> void:
	for field in ["char_equipped_tokens", "token_amplifier_unlocked_slots"]:
		for key in data.get(field, {}):
			data[field][key] = data[field][key].map(func(id): return int(id))
	for character in data.get("char_token_amplifier_slots", {}):
		_normalize_socket_ids(data.char_token_amplifier_slots[character])
	for preset in data.get("token_amplifier_presets", {}).values():
		preset.tokens = preset.tokens.map(func(id): return int(id))
		_normalize_socket_ids(preset.slots)

static func _normalize_socket_ids(slots_by_token: Dictionary) -> void:
	for token in slots_by_token:
		slots_by_token[token] = slots_by_token[token].map(func(id): return int(id))

func _character(id := 0) -> int:
	return systems._selected_character(id)

func ids() -> Array:
	var result: Array = []
	for row in systems.catalog.rows("RelationshipTokenData"):
		var id := int(row.material_id)
		if not result.has(id): result.append(id)
	return result

func level_row(token_id: int, level: int) -> Dictionary:
	for row in systems.catalog.rows("RelationshipTokenData"):
		if int(row.material_id) == token_id and int(row.level) == level: return row
	return {}

func equipped(character_id := 0) -> Array:
	return systems.profile.data.char_equipped_tokens.get(str(_character(character_id)), []).duplicate()

func slots(token_id: int, character_id := 0) -> Array:
	return systems.profile.data.char_token_amplifier_slots.get(str(_character(character_id)), {}).get(str(token_id), [0, 0, 0]).duplicate()

func _write_slots(character_id: int, token_id: int, values: Array) -> void:
	var all: Dictionary = systems.profile.data.char_token_amplifier_slots
	if not all.has(str(character_id)): all[str(character_id)] = {}
	all[str(character_id)][str(token_id)] = values.duplicate()

func refresh() -> int:
	var count := 0
	for row in systems.catalog.rows("RelationshipTokenData"):
		if int(row.auto_unlock_data_id) <= 0 or not systems.is_unlocked(int(row.auto_unlock_data_id)): continue
		var key := "token:" + str(int(row.material_id))
		if systems.stat(key) < int(row.level):
			systems.set_record(key, int(row.level))
			count += 1
	return count

func normalize() -> void:
	var data: Dictionary = systems.profile.data
	normalize_saved_ids(data)
	for character in data.char_equipped_tokens:
		var valid: Array = []
		for token in data.char_equipped_tokens[character]:
			var id := int(token)
			if valid.size() < systems.token_slots() and not valid.has(id) and not level_row(id, 1).is_empty() and systems.stat("token:" + str(id)) > 0: valid.append(id)
		data.char_equipped_tokens[character] = valid
	for character in data.char_token_amplifier_slots:
		var used := {}
		for token in data.char_token_amplifier_slots[character]:
			var values: Array = data.char_token_amplifier_slots[character][token]
			for index in values.size():
				var id := int(values[index])
				if not socket_unlocked(int(token), index) or systems.catalog.find("RelationshipAmplifyData", id).is_empty() or int(used.get(str(id), 0)) >= systems.material(id): values[index] = 0
				else: used[str(id)] = int(used.get(str(id), 0)) + 1
	data.equipped_tokens = equipped()
	data.equipped_amplifiers = active_amplifiers()

func status(token_id: int, character_id := 0) -> Dictionary:
	var level: int = systems.stat("token:" + str(token_id))
	var row := level_row(token_id, maxi(1, level))
	var next := level_row(token_id, level + 1)
	var reason: String = systems._camp_action_reason("tokens")
	var price := {}
	if row.is_empty(): reason = "信物不存在"
	elif next.is_empty(): reason = "信物已满级"
	elif int(next.auto_unlock_data_id) > 0:
		if not systems.is_unlocked(int(next.auto_unlock_data_id)): reason = Catalog.clean(next.get("unlcok_desc", "解锁条件未满足"))
	elif level == 0: reason = "信物尚未解锁"
	else:
		price["108"] = int(next.upgrade_need_item)
		if reason.is_empty() and not systems.can_afford(price): reason = "信物精华不足"
	var selected := equipped(character_id)
	var equip_reason: String = systems._camp_action_reason("tokens")
	if row.is_empty() or level == 0: equip_reason = Catalog.clean(row.get("unlcok_desc", "信物尚未解锁"))
	elif not selected.has(token_id) and selected.size() >= systems.token_slots(): equip_reason = "没有空闲信物槽"
	return {"id": token_id, "name": Catalog.clean(systems.material_name(token_id)), "icon": str(row.get("icon_name", "")), "level": level, "max_level": 6, "effect": Catalog.clean(row.get("effect_desc", "")) if level > 0 else "", "next_effect": Catalog.clean(next.get("effect_desc", "")), "unlock_description": Catalog.clean(row.get("unlcok_desc", "")), "price": price, "can_upgrade": reason.is_empty(), "reason": reason, "equipped": selected.has(token_id), "can_equip": equip_reason.is_empty(), "equip_reason": equip_reason, "sockets": socket_statuses(token_id, character_id)}

func upgrade(token_id: int) -> Dictionary:
	return systems._camp_transaction(_upgrade.bind(token_id))

func _upgrade(token_id: int) -> Dictionary:
	if _mutating: return systems._fail("信物交易处理中")
	var state := status(token_id)
	if not state.can_upgrade: return systems._fail(state.reason)
	_mutating = true
	if not systems.spend(state.price):
		_mutating = false
		return systems._fail("信物精华不足")
	systems.set_record("token:" + str(token_id), int(state.level) + 1)
	return _finish_transaction("信物等级 " + str(int(state.level) + 1), token_id)

func equip(token_id: int) -> Dictionary:
	return systems._camp_transaction(_equip.bind(token_id))

func _equip(token_id: int) -> Dictionary:
	if _mutating: return systems._fail("信物交易处理中")
	var state := status(token_id)
	if not state.can_equip: return systems._fail(state.equip_reason)
	var selected := equipped()
	if selected.has(token_id): selected.erase(token_id)
	else: selected.append(token_id)
	systems.profile.data.char_equipped_tokens[str(_character())] = selected
	normalize()
	return systems._done("信物已卸下" if state.equipped else "信物已装备", token_id)

func socket_unlocked(token_id: int, index: int) -> bool:
	return index >= 0 and index < 3 and systems.stat("token:" + str(token_id)) >= 3 and systems.profile.data.token_amplifier_unlocked_slots.get(str(token_id), []).has(index)

func socket_statuses(token_id: int, character_id := 0) -> Array:
	var result: Array = []
	var values := slots(token_id, character_id)
	for index in 3:
		var unlocked := socket_unlocked(token_id, index)
		var reason: String = systems._camp_action_reason("tokens")
		var price := {"108": int(systems.catalog.config.get("UnlockAmplifySlotCost", 500))}
		if systems.stat("token:" + str(token_id)) < 3: reason = "信物三级后开放增幅镶嵌"
		elif unlocked: reason = "槽位已解锁"
		elif not systems.can_afford(price): reason = "信物精华不足"
		result.append({"index": index, "token_id": token_id, "amplifier_id": int(values[index]), "unlocked": unlocked, "price": price, "can_unlock": reason.is_empty(), "reason": reason})
	return result

func unlock_socket(token_id: int, index: int) -> Dictionary:
	return systems._camp_transaction(_unlock_socket.bind(token_id, index))

func _unlock_socket(token_id: int, index: int) -> Dictionary:
	if _mutating: return systems._fail("信物交易处理中")
	if index < 0 or index >= 3 or level_row(token_id, 1).is_empty(): return systems._fail("增幅槽不存在")
	var state: Dictionary = socket_statuses(token_id)[index]
	if not state.can_unlock: return systems._fail(state.reason)
	_mutating = true
	if not systems.spend(state.price):
		_mutating = false
		return systems._fail("信物精华不足")
	var all: Dictionary = systems.profile.data.token_amplifier_unlocked_slots
	if not all.has(str(token_id)): all[str(token_id)] = []
	all[str(token_id)].append(index)
	return _finish_transaction("增幅槽已解锁", token_id)

func available(amplifier_id: int, character_id := 0) -> int:
	var used := 0
	for values in systems.profile.data.char_token_amplifier_slots.get(str(_character(character_id)), {}).values():
		for value in values:
			if int(value) == amplifier_id: used += 1
	return maxi(0, systems.material(amplifier_id) - used)

func equip_amplifier(character_id: int, token_id: int, index: int, amplifier_id: int) -> Dictionary:
	return systems._camp_transaction(_equip_amplifier.bind(character_id, token_id, index, amplifier_id))

func _equip_amplifier(character_id: int, token_id: int, index: int, amplifier_id: int) -> Dictionary:
	if _mutating: return systems._fail("信物交易处理中")
	var reason: String = systems._camp_action_reason("tokens")
	if not reason.is_empty(): return systems._fail(reason)
	if character_id != _character() or not socket_unlocked(token_id, index): return systems._fail("请选择当前角色已解锁的信物槽")
	if systems.catalog.find("RelationshipAmplifyData", amplifier_id).is_empty(): return systems._fail("增幅不存在")
	var values := slots(token_id, character_id)
	if int(values[index]) == amplifier_id: return systems._ok("该槽位已装备此增幅", amplifier_id)
	if available(amplifier_id, character_id) < 1: return systems._fail("没有可用的同类增幅")
	values[index] = amplifier_id
	_write_slots(character_id, token_id, values)
	normalize()
	return systems._done("增幅已镶嵌", amplifier_id)

func unequip(token_id: int, index: int) -> Dictionary:
	return systems._camp_transaction(_unequip.bind(token_id, index))

func _unequip(token_id: int, index: int) -> Dictionary:
	if _mutating: return systems._fail("信物交易处理中")
	var reason: String = systems._camp_action_reason("tokens")
	if not reason.is_empty(): return systems._fail(reason)
	if index < 0 or index >= 3: return systems._fail("增幅槽不存在")
	var values := slots(token_id)
	if int(values[index]) == 0: return systems._fail("槽位没有增幅")
	values[index] = 0
	_write_slots(_character(), token_id, values)
	normalize()
	return systems._done("增幅已卸下", token_id)

func unequip_all(token_id := 0) -> Dictionary:
	return systems._camp_transaction(_unequip_all.bind(token_id))

func _unequip_all(token_id: int) -> Dictionary:
	if _mutating: return systems._fail("信物交易处理中")
	var reason: String = systems._camp_action_reason("tokens")
	if not reason.is_empty(): return systems._fail(reason)
	var all: Dictionary = systems.profile.data.char_token_amplifier_slots.get(str(_character()), {})
	for key in all:
		if token_id == 0 or int(key) == token_id: all[key] = [0, 0, 0]
	normalize()
	return systems._done("增幅已全部卸下")

func active_amplifiers(character_id := 0) -> Array:
	var result: Array = []
	for token in equipped(character_id):
		var values := slots(int(token), character_id)
		for index in values.size():
			if socket_unlocked(int(token), index) and int(values[index]) > 0: result.append(int(values[index]))
	return result

func ability_ids(character_id := 0) -> Array:
	var result: Array = []
	for token in equipped(character_id): result.append_array(Catalog.ids(level_row(int(token), systems.stat("token:" + str(int(token)))).get("abilityitem_id", "")))
	for id in active_amplifiers(character_id): result.append_array(Catalog.ids(systems.catalog.find("RelationshipAmplifyData", id).get("abilityitem_id", "")))
	return result

func tier_of(id: int) -> int:
	return int(str(systems.catalog.find("RelationshipAmplifyData", id).get("rare", "Tier0")).trim_prefix("Tier"))

func _candidates(tier: int) -> Array:
	return systems.catalog.rows("RelationshipAmplifyData").filter(func(row): return str(row.rare) == "Tier" + str(tier))

func compose_quote(request: Dictionary = {}) -> Dictionary:
	var requested = request.get("groups", request)
	if not requested is Dictionary: return _invalid_composition()
	var groups: Dictionary = {}
	for key in requested:
		if not str(key).is_valid_int() or not _integer(requested[key], 1): return _invalid_composition()
		var normalized := str(int(key))
		if groups.has(normalized): return _invalid_composition()
		groups[normalized] = int(requested[key])
	if groups.is_empty():
		for row in systems.catalog.rows("RelationshipAmplifyData"):
			var count := available(int(row.id)) / 5
			if count > 0 and tier_of(int(row.id)) < 5: groups[str(int(row.id))] = count
	var reason: String = systems._camp_action_reason("tokens")
	var price := {"101": 0}
	var tiers := {}
	var prices := Catalog.ids(systems.catalog.config.get("ComposeAmplifyGoldCost", "500|1000|2000|10000"))
	for key in groups:
		var id := int(key)
		var tier := tier_of(id)
		var count := int(groups[key])
		if tier < 1 or tier >= 5 or _candidates(tier + 1).is_empty(): reason = "增幅不存在或已达最高阶"
		elif available(id) < count * 5: reason = "每份合成需要五个未镶嵌的同类增幅"
		else:
			price[str(id)] = count * 5
			price["101"] += count * int(prices[mini(tier - 1, prices.size() - 1)])
			tiers[str(tier + 1)] = int(tiers.get(str(tier + 1), 0)) + count
	if groups.is_empty(): reason = "没有可合成的增幅"
	if reason.is_empty() and not systems.can_afford(price): reason = "合成金币不足"
	return {"success": reason.is_empty(), "reason": reason, "groups": groups, "price": price, "tiers": tiers, "revision": int(systems.profile.data.amplifier_draw_state.revision)}

func _invalid_composition() -> Dictionary:
	return {"success": false, "reason": "合成数量无效", "groups": {}, "price": {}, "tiers": {}}

func _draw(tier: int) -> int:
	var state: Dictionary = systems.profile.data.amplifier_draw_state
	if int(state.base_seed) == 0: state.base_seed = int(Time.get_unix_time_from_system()) % 2147483647
	var key := str(tier)
	if not state.tiers.has(key):
		var raw := (int(state.base_seed) + tier * 1000003) & 0xffffffff
		if raw >= 2147483648: raw -= 4294967296
		state.tiers[key] = {"seed": absi(raw % 2147483647), "counter": 0}
	var entry: Dictionary = state.tiers[key]
	# APK seeds each tier draw with seed+counter. Godot owns an isolated RNG here.
	var random := RandomNumberGenerator.new()
	random.seed = int(entry.seed) + int(entry.counter)
	entry.counter = int(entry.counter) + 1
	var candidates := _candidates(tier)
	return int(candidates[random.randi_range(0, candidates.size() - 1)].id)

func compose(request: Dictionary) -> Dictionary:
	return systems._camp_transaction(_compose.bind(request))

func _compose(request: Dictionary) -> Dictionary:
	if _mutating: return systems._fail("信物交易处理中")
	var state: Dictionary = systems.profile.data.amplifier_draw_state
	if request.has("revision") and int(request.revision) != int(state.revision): return systems._fail("合成预览已更新，请重新确认")
	var quote := compose_quote(request)
	if not quote.success: return systems._fail(quote.reason)
	_mutating = true
	if not systems.spend(quote.price):
		_mutating = false
		return systems._fail("合成材料不足")
	var outputs := {}
	var keys: Array = quote.groups.keys()
	keys.sort_custom(func(a, b): return int(a) < int(b))
	for key in keys:
		for count in int(quote.groups[key]):
			var id := _draw(tier_of(int(key)) + 1)
			outputs[str(id)] = int(outputs.get(str(id), 0)) + 1
	for key in outputs: systems.grant_material(int(key), int(outputs[key]))
	state.last = {"outputs": outputs, "rerolls": 0}
	state.revision = int(state.revision) + 1
	normalize()
	var result: Dictionary = _finish_transaction("合成完成", int(outputs.keys()[0]))
	result["outputs"] = outputs.duplicate()
	return result

func reroll_quote() -> Dictionary:
	var last: Dictionary = systems.profile.data.amplifier_draw_state.last
	var reason: String = systems._camp_action_reason("tokens")
	var prices := Catalog.ids(systems.catalog.config.get("ComposeAmplifyRerollCost", "100|120|140|160|180|200"))
	var price := {"90002": int(prices[mini(int(last.get("rerolls", 0)), prices.size() - 1)])}
	var outputs: Dictionary = last.get("outputs", {})
	if outputs.is_empty(): reason = "没有可重选的合成结果"
	for key in outputs:
		if not str(key).is_valid_int() or not _integer(outputs[key], 1) or tier_of(int(key)) < 2 or tier_of(int(key)) > 5:
			return {"success": false, "reason": "合成结果存档无效", "price": {}, "outputs": {}, "rerolls": int(last.get("rerolls", 0))}
		price[str(key)] = int(outputs[key])
		if available(int(key)) < int(outputs[key]): reason = "合成结果已使用，请先卸下增幅"
	if reason.is_empty() and not systems.can_afford(price): reason = "七彩结晶不足"
	return {"success": reason.is_empty(), "reason": reason, "price": price, "outputs": outputs.duplicate(), "rerolls": int(last.get("rerolls", 0))}

func reroll() -> Dictionary:
	return systems._camp_transaction(_reroll)

func _reroll() -> Dictionary:
	if _mutating: return systems._fail("信物交易处理中")
	var quote := reroll_quote()
	if not quote.success: return systems._fail(quote.reason)
	_mutating = true
	if not systems.spend(quote.price):
		_mutating = false
		return systems._fail("重选材料不足")
	var tiers := {}
	for key in quote.outputs:
		var tier := str(tier_of(int(key)))
		tiers[tier] = int(tiers.get(tier, 0)) + int(quote.outputs[key])
	var outputs := {}
	var keys: Array = tiers.keys()
	keys.sort_custom(func(a, b): return int(a) < int(b))
	for tier in keys:
		for count in int(tiers[tier]):
			var id := _draw(int(tier))
			outputs[str(id)] = int(outputs.get(str(id), 0)) + 1
	for key in outputs: systems.grant_material(int(key), int(outputs[key]))
	var state: Dictionary = systems.profile.data.amplifier_draw_state
	state.last = {"outputs": outputs, "rerolls": int(quote.rerolls) + 1}
	state.revision = int(state.revision) + 1
	normalize()
	return _finish_transaction("重选完成", int(outputs.keys()[0]))

func _finish_transaction(message: String, id: int) -> Dictionary:
	# The shared camp transaction retains its guard while publishing notifications.
	var result: Dictionary = systems._done(message, id)
	_mutating = false
	return result

func save_preset(index: int) -> Dictionary:
	return systems._camp_transaction(_save_preset.bind(index))

func _save_preset(index: int) -> Dictionary:
	if _mutating: return systems._fail("信物交易处理中")
	var reason: String = systems._camp_action_reason("tokens")
	if not reason.is_empty(): return systems._fail(reason)
	if index < 0 or index >= PRESET_COUNT: return systems._fail("预设槽不存在")
	systems.profile.data.token_amplifier_presets[str(index)] = {"tokens": equipped(), "slots": systems.profile.data.char_token_amplifier_slots.get(str(_character()), {}).duplicate(true)}
	return systems._done("已保存预设 " + str(index + 1))

func load_preset(index: int) -> Dictionary:
	return systems._camp_transaction(_load_preset.bind(index))

func _load_preset(index: int) -> Dictionary:
	if _mutating: return systems._fail("信物交易处理中")
	var reason: String = systems._camp_action_reason("tokens")
	if not reason.is_empty(): return systems._fail(reason)
	var preset: Dictionary = systems.profile.data.token_amplifier_presets.get(str(index), {})
	if preset.is_empty(): return systems._fail("预设为空")
	var data: Dictionary = systems.profile.data
	data.char_equipped_tokens[str(_character())] = preset.tokens.duplicate()
	data.char_token_amplifier_slots[str(_character())] = preset.slots.duplicate(true)
	normalize()
	return systems._done("预设已应用，未解锁或数量不足的项目已跳过")

func delete_preset(index: int) -> Dictionary:
	return systems._camp_transaction(_delete_preset.bind(index))

func _delete_preset(index: int) -> Dictionary:
	if _mutating: return systems._fail("信物交易处理中")
	var reason: String = systems._camp_action_reason("tokens")
	if not reason.is_empty(): return systems._fail(reason)
	if not systems.profile.data.token_amplifier_presets.has(str(index)): return systems._fail("预设为空")
	systems.profile.data.token_amplifier_presets.erase(str(index))
	return systems._done("预设已清除")
