class_name DungeonSystems
extends RefCounted

signal changed
signal gameplay_event(event: Dictionary)

const Catalog = preload("res://scripts/domain/catalog.gd")
const Profile = preload("res://scripts/domain/profile.gd")
const Effects = preload("res://scripts/domain/effects.gd")
const CampDecorations = preload("res://scripts/domain/camp_decorations.gd")
const RelationshipTokens = preload("res://scripts/domain/relationship_tokens.gd")
const ExtraChallenges = preload("res://scripts/domain/extra_challenges.gd")
const CampHistory = preload("res://scripts/domain/camp_history.gd")
const CampSocial = preload("res://scripts/domain/camp_social.gd")
var catalog
var profile
var effects
var decorations
var relationship_tokens
var extra_challenges
var history
var social
var diagnostics: Array = []
var utc_now: Callable = func(): return int(Time.get_unix_time_from_system())
var _depth = 0
var _collecting_work = false
var _partner_mutating = false
var _camp_transaction_active := false
var _camp_notifying := false
var _camp_changed := false
var _camp_events: Array[Dictionary] = []
static var _event_node_areas: Dictionary = {}

func _init(source, state) -> void:
	catalog = source
	profile = state
	profile.normalize_ids()
	effects = Effects.new(self)
	decorations = CampDecorations.new(self)
	relationship_tokens = RelationshipTokens.new(self)
	extra_challenges = ExtraChallenges.new(self)
	history = CampHistory.new(self)
	social = CampSocial.new(self)
	relationship_tokens.refresh()

func _ok(message = "完成", id = 0) -> Dictionary:
	return {"success": true, "message": str(message), "id": int(id)}

func _fail(message) -> Dictionary:
	return {"success": false, "message": str(message), "id": 0}

func _camp_transaction(action: Callable) -> Dictionary:
	if _camp_transaction_active: return _fail("营地操作处理中")
	_camp_transaction_active = true
	_camp_changed = false
	_camp_events.clear()
	var result: Dictionary = action.call()
	# Subscribers may save or request another action, so publish only committed state.
	_camp_notifying = true
	for event in _camp_events: gameplay_event.emit(event)
	if _camp_changed: changed.emit()
	_camp_events.clear()
	_camp_changed = false
	_camp_notifying = false
	_camp_transaction_active = false
	return result

func _emit_gameplay_event(event: Dictionary) -> void:
	if _camp_transaction_active: _camp_events.append(event.duplicate(true))
	else: gameplay_event.emit(event)

func _done(message = "完成", id = 0) -> Dictionary:
	if _depth == 0:
		if relationship_tokens != null:
			relationship_tokens.refresh()
			relationship_tokens.normalize()
		if _camp_transaction_active: _camp_changed = true
		else: changed.emit()
	return _ok(message, id)

func diagnose(message: String) -> void:
	if not diagnostics.has(message):
		diagnostics.append(message)

func material(id: int) -> int:
	if id == 504: return int(awakening_progress().total)
	return int(profile.data.materials.get(str(id), 0))

func material_name(id: int) -> String:
	return Catalog.row_name(catalog.find("MaterialData", id))

func stat(key: String) -> int:
	return int(profile.data.stats.get(key, 0))

func rank(values: Dictionary, id) -> int:
	return int(values.get(str(int(id)), 0))

func record(key: String, amount: int = 1) -> void:
	if amount > 0:
		profile.data.stats[key] = stat(key) + amount

func set_record(key: String, value: int) -> void:
	profile.data.stats[key] = maxi(0, value)

func _add(values: Dictionary, key, amount) -> void:
	var text = str(key)
	values[text] = values.get(text, 0) + amount

func grant_material(id: int, amount: int) -> void:
	if amount <= 0:
		return
	if id != 504: _add(profile.data.materials, id, amount)
	record("get:" + str(id), amount)
	if profile.data.run.active:
		_add(profile.data.run.materials, id, amount)
		record("adventure:get:" + str(id), amount)
		record_purification_event("ChangeResCount", str(id), amount, "0", false)
		effects.dispatch("ChangeResCount", str(id), "0", str(amount))
	_emit_gameplay_event({"type": "resource_gained", "id": id, "amount": amount})

static func costs(expression) -> Dictionary:
	var result = {}
	for token in str(expression).replace("|", ",").split(",", false):
		var pair = token.strip_edges().split(":")
		if pair.size() != 2 or not pair[0].is_valid_int() or not pair[1].is_valid_int() or int(pair[1]) < 0:
			return {"invalid": -1}
		var id = str(int(pair[0]))
		result[id] = int(result.get(id, 0)) + int(pair[1])
	return result

func spend(values: Dictionary) -> bool:
	if _camp_notifying: return false
	if not can_afford(values): return false
	var normalized = _normalized_costs(values)
	for key in normalized:
		_add(profile.data.materials, key, -int(normalized[key]))
		record("spent:" + str(key), int(normalized[key]))
	for key in normalized:
		if int(normalized[key]) > 0: _emit_gameplay_event({"type": "resource_spent", "id": int(key), "amount": int(normalized[key])})
	return true

func _normalized_costs(values: Dictionary) -> Dictionary:
	var normalized: Dictionary = {}
	for key in values:
		var amount = values[key]
		if not str(key).is_valid_int() or int(key) <= 0 or not (amount is int or amount is float): return {"invalid": -1}
		if not is_finite(float(amount)) or float(amount) < 0 or float(amount) != floor(float(amount)): return {"invalid": -1}
		_add(normalized, int(key), int(amount))
	return normalized

func can_afford(values: Dictionary) -> bool:
	var normalized = _normalized_costs(values)
	if normalized.has("invalid"): return false
	if int(normalized.get("504", 0)) > 0: return false
	for key in normalized:
		if material(int(key)) < int(normalized[key]): return false
	return true

func price_description(values: Dictionary) -> String:
	var lines: Array[String] = []
	for key in values:
		if int(values[key]) <= 0: continue
		lines.append("%s %d / %d" % [Catalog.clean(material_name(int(key))), material(int(key)), int(values[key])])
	return "\n".join(lines)

func resource_summary() -> Array:
	var result: Array = []
	for id in [101, 501, 502, 503, 504, 103, 90002, 107, 108, 106]:
		var row = catalog.find("MaterialData", id)
		result.append({"id": id, "name": Catalog.clean(Catalog.row_name(row)), "amount": material(id), "description": Catalog.clean(Catalog.description(row)), "earned": stat("get:" + str(id)), "spent": stat("spent:" + str(id))})
	return result

func camp_feature_status(feature: String) -> Dictionary:
	# Facility IDs and stages follow MainCityDevelopDataList descriptions.
	var gates = {"characters": [1, 1], "recruit": [1, 1], "talents": [2, 1], "tokens": [2, 1], "treasure": [2, 1], "chests": [2, 1], "gold_apple": [2, 2], "history": [2, 3], "weapons": [3, 1], "training": [3, 2], "weapon_upgrade": [3, 3], "archive": [4, 1], "partners": [4, 2], "partner_skill": [4, 3], "tasks": [5, 1], "work": [6, 1], "work_rare": [6, 2], "work_precious": [6, 3], "meals": [7, 1]}
	gates["awakening"] = [2, 1]
	gates["storage"] = [2, 1]
	gates["amplifiers"] = [2, 1]
	gates["extra_challenges"] = [5, 2]
	var gate: Array = gates.get(feature, [0, 0])
	var level = rank(profile.data.buildings, gate[0])
	var available = int(gate[1]) == 0 or level >= int(gate[1])
	var name = _part(Catalog.row_name(catalog.find("Buildings", gate[0])), int(gate[1]) - 1)
	return {"feature": feature, "available": available, "building_id": int(gate[0]), "required_level": int(gate[1]), "level": level, "reason": "" if available else "请先建设%s（设施等级 %d）" % [name, int(gate[1])]}

func _camp_action_reason(feature: String = "") -> String:
	if profile.data.run.active: return "请返回营地后操作"
	return str(camp_feature_status(feature).reason)

func unlock_reason(id: int) -> String:
	if is_unlocked(id): return ""
	var progress = unlock_progress(id)
	return "%s（%d / %d）" % [Catalog.clean(progress.description), int(progress.current), int(progress.required)]

func _reward(expression) -> void:
	for id in costs(expression):
		grant_material(int(id), int(costs(expression)[id]))

func _part(text, index: int, delimiter = "|") -> String:
	var values = str(text).split(delimiter)
	return values[index] if index >= 0 and index < values.size() else ""

func _alias(id: int) -> int:
	return 101 if id == 1 else 102 if id == 2 else 103 if id == 3 else id

func is_unlocked(id: int, visiting: Array = []) -> bool:
	if id == 0:
		return true
	var row = catalog.find("UnlockData", id)
	if row.is_empty():
		diagnose("Missing unlock " + str(id))
		return false
	return _unlock_condition_complete(row, visiting)

func _unlock_condition_complete(row: Dictionary, visiting: Array = []) -> bool:
	if row.is_empty(): return false
	var id = int(row.get("id", 0))
	if id != 0 and visiting.has(id):
		diagnose("Circular unlock " + str(id))
		return false
	var path = visiting.duplicate()
	if id != 0: path.append(id)
	var a = int(row.get("unlock_param1", 0))
	var b = int(row.get("unlock_param2", 0))
	var c = int(row.get("unlock_param3", 0))
	var d = profile.data
	match int(row.get("unlock_condition_type", -1)):
		0: return true
		10: return stat("runs") >= a
		11: return stat("wins") >= a
		12: return stat("losses") >= a
		13: return stat("region:" + str(a)) >= b
		20: return stat("kill:" + str(a)) >= b
		21: return d.talents.values().filter(func(x): return x > 0).size() >= a
		23: return _kill_count_by_enemy_type(a) >= b
		30: return _total_resource_acquired(a) >= b
		31: return stat("spent:" + str(_alias(a))) >= b
		40: return d.discovered_loot.has(a)
		41: return d.discovered_loot.size() >= a
		51: return stat("work:finished") >= a
		52: return stat("work:upgraded") >= a
		100: return d.buildings.values().reduce(func(x, y): return x + y, 0) >= a
		101: return rank(d.buildings, a) >= b
		200: return stat("talk:" + str(a)) > 0
		201: return stat("relationship:" + str(a)) >= b
		300: return stat("weapon:" + str(a)) > 0
		301: return stat("weapon:" + str(a)) >= b
		302: return stat("weapons:crafted") >= a
		400: return rank(d.character_levels, a) > 0
		401: return rank(d.character_levels, a) >= b
		402: return d.partners.values().filter(func(x): return x >= b + 1).size() >= a
		403: return stat("character:upgraded") >= a
		404: return stat("character-region:" + str(a)) >= b
		500: return stat("shop:level") >= a
		600: return d.claimed_achievements.has(a)
		601: return d.claimed_achievements.size() >= a
		1000: return rank(d.run.inventory, a) > 0
		1001: return stat("loot-region:" + str(a)) >= b
		1002: return rank(d.run.inventory, a) == 0
		1010: return rank(d.run.materials, _alias(a)) >= b
		1021: return stat("boss-rating:" + str(a)) >= b
		1030: return stat("max-region" if a == 0 else "character-region:" + str(a)) >= b
		1040: return stat("hard:losses") >= a
		1051: return rank(d.talents, a) > 0
		1052: return rank(d.talents, a) == 0
		1053: return int(d.run.difficulty) >= a
		1055: return chaos_cleared_level() >= a
		1056: return selected_chaos_level() >= a
		1061: return stat("meal:research") >= a
		1062: return stat("meal:upgraded") >= a
		9001: return is_unlocked(a, path) and is_unlocked(b, path) and is_unlocked(c, path)
		9002: return is_unlocked(a, path) or is_unlocked(b, path) or is_unlocked(c, path)
		9201: return d.run.active == (a == 1)
		9999:
			if id == 50001: return a == 101 and stat("adventure:get:101") >= b
			if id == 50002: return a == 102 and stat("get:102") >= b
			if id >= 50003 and id <= 50007: return stat("kill:" + str(a)) >= b
			if id >= 50022 and id <= 50027: return stat("character-region:" + str(a)) >= b
			if id >= 50028 and id <= 50037: return d.discovered_loot.has(a)
	diagnose("Unsupported unlock " + str(id))
	return false

func _kill_count_by_enemy_type(enemy_type: int) -> int:
	var total = 0
	var rates = ["Normal", "Elite", "Boss"]
	if enemy_type < 0 or enemy_type >= rates.size(): return total
	for enemy in catalog.rows("EnemyData"):
		if str(enemy.get("enemy_rate", "")) == rates[enemy_type]:
			total += stat("kill:" + str(int(enemy.id)))
	return total

func _total_resource_acquired(resource: int) -> int:
	# Native selector 1 reads settlement gold history, excluding camp payouts.
	return stat("adventure:get:101") if resource == 1 else stat("get:" + str(_alias(resource)))

func unlock_progress(id: int) -> Dictionary:
	var row = catalog.find("UnlockData", id)
	if id == 0:
		return {"current": 1, "required": 1, "complete": true, "description": ""}
	return _unlock_condition_progress(row)

func _unlock_condition_progress(row: Dictionary) -> Dictionary:
	if row.is_empty():
		return {"current": 0, "required": 1, "complete": false, "description": "未知条件"}
	var id = int(row.get("id", 0))
	var a = int(row.get("unlock_param1", 0))
	var b = int(row.get("unlock_param2", 0))
	var current = 0
	var required = maxi(1, a)
	var d = profile.data
	match int(row.get("unlock_condition_type", -1)):
		10: current = stat("runs")
		11: current = stat("wins")
		12: current = stat("losses")
		13: current = stat("region:" + str(a)); required = b
		20: current = stat("kill:" + str(a)); required = b
		21: current = d.talents.values().filter(func(x): return x > 0).size()
		23: current = _kill_count_by_enemy_type(a); required = b
		30: current = _total_resource_acquired(a); required = b
		31: current = stat("spent:" + str(_alias(a))); required = b
		41: current = d.discovered_loot.size()
		51: current = stat("work:finished")
		52: current = stat("work:upgraded")
		100: current = d.buildings.values().reduce(func(x, y): return x + y, 0)
		101: current = rank(d.buildings, a); required = b
		201: current = stat("relationship:" + str(a)); required = b
		301: current = stat("weapon:" + str(a)); required = b
		302: current = stat("weapons:crafted")
		401: current = rank(d.character_levels, a); required = b
		402: current = d.partners.values().filter(func(x): return x >= b + 1).size()
		403: current = stat("character:upgraded")
		404: current = stat("character-region:" + str(a)); required = b
		500: current = stat("shop:level")
		601: current = d.claimed_achievements.size()
		1001: current = stat("loot-region:" + str(a)); required = b
		1010: current = rank(d.run.materials, _alias(a)); required = b
		1021: current = stat("boss-rating:" + str(a)); required = b
		1030: current = stat("max-region" if a == 0 else "character-region:" + str(a)); required = b
		1040: current = stat("hard:losses")
		1053: current = int(d.run.difficulty)
		1055: current = chaos_cleared_level()
		1056: current = selected_chaos_level()
		1061: current = stat("meal:research")
		1062: current = stat("meal:upgraded")
		9999:
			required = maxi(1, b)
			if id == 50001: current = stat("adventure:get:101")
			elif id == 50002: current = stat("get:102")
			elif id >= 50003 and id <= 50007: current = stat("kill:" + str(a))
			elif id >= 50022 and id <= 50027: current = stat("character-region:" + str(a))
			else: current = required if _unlock_condition_complete(row) else 0
		_:
			required = 1
			current = 1 if _unlock_condition_complete(row) else 0
	return {"current": current, "required": required, "complete": _unlock_condition_complete(row), "description": str(row.get("unlock_desc", ""))}

func _all_unlocked(expression) -> bool:
	for id in Catalog.ids(expression):
		if not is_unlocked(id): return false
	return true

func task_status(id: int) -> Dictionary:
	var row = catalog.find("SubAchieveData", id)
	if row.is_empty(): return {"available": false, "claimed": false, "complete": false}
	var group = catalog.find("AchieveData", int(row.group_id))
	var condition = row.get("unlock_data", null)
	var result = _unlock_condition_progress({})
	if condition is Dictionary: result = _unlock_condition_progress(condition)
	elif row.has("unlock_data_id"): result = unlock_progress(int(row.unlock_data_id))
	result["available"] = _all_unlocked(group.get("unlock_group_id", ""))
	result["claimed"] = profile.data.claimed_tasks.has(id)
	return result

func claim_task(id: int) -> Dictionary:
	return _camp_transaction(_claim_task.bind(id))

func _claim_task(id: int) -> Dictionary:
	var row = catalog.find("SubAchieveData", id)
	var status = task_status(id)
	if row.is_empty() or status.claimed: return _fail("任务已领取或不存在")
	if not status.available: return _fail("任务组前置未完成")
	if not status.complete: return _fail("任务尚未完成")
	profile.data.claimed_tasks.append(id)
	_reward(row.reward_get_materials)
	_emit_gameplay_event({"type": "task_claimed", "id": id})
	return _done(Catalog.row_name(row), id)

func claim_achievement(id: int) -> Dictionary:
	return _camp_transaction(_claim_achievement.bind(id))

func _claim_achievement(id: int) -> Dictionary:
	var row = catalog.find("AchieveData", id)
	if row.is_empty() or profile.data.claimed_achievements.has(id): return _fail("成就已领取或不存在")
	if not _all_unlocked(row.unlock_group_id): return _fail("成就前置未完成")
	var found = false
	for task in catalog.rows("SubAchieveData"):
		if int(task.group_id) == id:
			found = true
			if not profile.data.claimed_tasks.has(int(task.id)): return _fail("请完成并领取本组全部任务")
	if not found: return _fail("空成就组")
	profile.data.claimed_achievements.append(id)
	_reward(row.reward_get_materials)
	_emit_gameplay_event({"type": "achievement_claimed", "id": id})
	return _done(Catalog.row_name(row), id)

func character_recruit_status(id: int) -> Dictionary:
	var reason = _camp_action_reason("recruit")
	var row = catalog.find("CharData", id)
	var price = costs(row.get("need_unlock_materials", ""))
	if row.is_empty() or row.get("available_state", "") != "Normal": reason = "角色不可招募"
	elif rank(profile.data.character_levels, id) > 0: reason = "角色已拥有"
	elif bool(row.get("is_cash_only_unlock", false)): reason = "需通过商城完成付费与凭证验证"
	elif reason.is_empty() and not is_unlocked(int(row.get("unlock_data_id", 0))): reason = unlock_reason(int(row.unlock_data_id))
	elif reason.is_empty() and not can_afford(price): reason = "招募材料不足"
	return {"id": id, "price": price, "owned": rank(profile.data.character_levels, id) > 0, "can_recruit": reason.is_empty(), "reason": reason}

func unlock_character(id: int) -> Dictionary:
	return _camp_transaction(_unlock_character.bind(id))

func _unlock_character(id: int) -> Dictionary:
	var status = character_recruit_status(id)
	if not status.can_recruit: return _fail(status.reason)
	if not spend(status.price): return _fail("招募材料不足")
	var row = catalog.find("CharData", id)
	profile.data.character_levels[str(id)] = 1
	set_record("weapon:" + str(int(row.default_weapon)), 1)
	return _done(Catalog.row_name(row), id)

func select_character(id: int) -> Dictionary:
	return _camp_transaction(_select_character.bind(id))

func _select_character(id: int) -> Dictionary:
	var reason = _camp_action_reason()
	if not reason.is_empty(): return _fail(reason)
	var row = catalog.find("CharData", id)
	if row.is_empty() or row.get("available_state", "") != "Normal" or rank(profile.data.character_levels, id) < 1: return _fail("请选择已拥有的角色")
	if int(profile.data.selected_character) == id: return _ok("当前角色已出战", id)
	profile.data.selected_character = id
	var weapon = int(profile.data.get("selected_weapons", {}).get(str(id), row.get("default_weapon", 0)))
	if not Catalog.ids(row.get("can_equip_weapon_id_list", "")).has(weapon) or stat("weapon:" + str(weapon)) < 1: weapon = int(row.get("default_weapon", 0))
	profile.data.selected_weapon = weapon
	return _done("已选择" + Catalog.clean(Catalog.row_name(row)), id)

func equip_weapon(id: int, character_id: int = 0) -> Dictionary:
	return _camp_transaction(_equip_weapon.bind(id, character_id))

func _equip_weapon(id: int, character_id: int) -> Dictionary:
	var reason = _camp_action_reason()
	if not reason.is_empty(): return _fail(reason)
	if character_id == 0: character_id = int(profile.data.selected_character)
	var row = catalog.find("CharData", character_id)
	if rank(profile.data.character_levels, character_id) < 1 or catalog.find("WeaponData", id).is_empty() or stat("weapon:" + str(id)) < 1: return _fail("武器尚未打造")
	if not Catalog.ids(row.get("can_equip_weapon_id_list", "")).has(id): return _fail("该角色无法装备此武器")
	if character_id == int(profile.data.selected_character): profile.data.selected_weapon = id
	if not profile.data.has("selected_weapons"): profile.data["selected_weapons"] = {}
	profile.data.selected_weapons[str(character_id)] = id
	return _done("武器已装备", id)

func equipped_weapon(character_id: int = 0) -> int:
	var selected = _selected_character(character_id)
	var row = catalog.find("CharData", selected)
	var weapon = int(profile.data.selected_weapon) if selected == int(profile.data.selected_character) else int(profile.data.get("selected_weapons", {}).get(str(selected), row.get("default_weapon", 0)))
	if not Catalog.ids(row.get("can_equip_weapon_id_list", "")).has(weapon) or stat("weapon:" + str(weapon)) < 1:
		weapon = int(row.get("default_weapon", 0))
	return weapon

func character_upgrade_status(id: int) -> Dictionary:
	var level = rank(profile.data.character_levels, id)
	var upgrades = catalog.config.get("CharaLevelUpCostList_UpgradeItem", [])
	var price: Dictionary = {}
	var reason = _camp_action_reason()
	if catalog.find("CharData", id).is_empty() or level < 1: reason = "角色未解锁"
	elif level > upgrades.size(): reason = "角色已满级"
	else: price["501"] = int(upgrades[level - 1])
	var breaks = catalog.config.get("CharaLevelUpCostList_BreakUpItem", [])
	if level > 0 and level <= breaks.size() and not price.is_empty(): price["503"] = int(breaks[level - 1])
	if reason.is_empty() and not can_afford(price): reason = "冒险凭证或彩虹魔方不足"
	var character = catalog.find("CharData", id)
	var growth = float(catalog.config.get("CharaPerLevelAddStatusPercent", 0)) / 1000.0
	var stats: Array = []
	var next_level = mini(level + 1, upgrades.size() + 1)
	for pair in [["生命", "hp"], ["攻击", "atk"], ["防御", "def"]]:
		var base = float(character.get(pair[1], 0))
		stats.append({"name": pair[0], "current": int(base * (1.0 + maxi(0, level - 1) * growth)), "next": int(base * (1.0 + maxi(0, next_level - 1) * growth))})
	return {"id": id, "level": level, "next_level": next_level, "max_level": upgrades.size() + 1, "price": price, "stats": stats, "can_upgrade": reason.is_empty(), "reason": reason}

func character_fashion_status(id: int, character_id := 0) -> Dictionary:
	return preload("res://scripts/domain/character_fashion.gd").new(self).status(id, character_id)

func character_fashion_owned() -> Array:
	return preload("res://scripts/domain/character_fashion.gd").new(self).owned_ids()

func character_fashion_equipped() -> Dictionary:
	return preload("res://scripts/domain/character_fashion.gd").new(self).equipped_ids()

func unlock_character_fashion(id: int, character_id := 0) -> Dictionary:
	return preload("res://scripts/domain/character_fashion.gd").new(self).unlock(id, character_id)

func equip_character_fashion(id: int, character_id := 0) -> Dictionary:
	return preload("res://scripts/domain/character_fashion.gd").new(self).equip(id, character_id)

func upgrade_character(id: int) -> Dictionary:
	return _camp_transaction(_upgrade_character.bind(id))

func _upgrade_character(id: int) -> Dictionary:
	var status = character_upgrade_status(id)
	if not status.can_upgrade: return _fail(status.reason)
	if not spend(status.price): return _fail("升级或突破材料不足")
	profile.data.character_levels[str(id)] = int(status.level) + 1
	record("character:upgraded")
	refresh_tokens(false)
	_emit_gameplay_event({"type": "character_upgraded", "id": id, "level": int(status.level) + 1})
	return _done("角色等级 " + str(int(status.level) + 1), id)

func weapon_upgrade_status(id: int) -> Dictionary:
	var row = catalog.find("WeaponData", id)
	var level = stat("weapon:" + str(id))
	var prices = Catalog.ids(row.get("unlock_mineral_mat_count", ""))
	var price = {"103": int(prices[level])} if level >= 0 and level < prices.size() else {}
	var reason = _camp_action_reason("weapons" if stat("weapon:" + str(id)) == 0 else "weapon_upgrade")
	if row.is_empty(): reason = "未知武器"
	elif level >= prices.size(): reason = "武器已满级"
	elif not is_unlocked(int(row.unlock_data_id)): reason = unlock_reason(int(row.unlock_data_id))
	elif reason.is_empty() and not can_afford(price): reason = "矿石不足"
	return {"id": id, "level": level, "max_level": prices.size(), "price": price, "can_upgrade": reason.is_empty(), "reason": reason}

func upgrade_weapon(id: int) -> Dictionary:
	return _camp_transaction(_upgrade_weapon.bind(id))

func _upgrade_weapon(id: int) -> Dictionary:
	var status = weapon_upgrade_status(id)
	if not status.can_upgrade: return _fail(status.reason)
	if not spend(status.price): return _fail("矿石不足")
	set_record("weapon:" + str(id), int(status.level) + 1)
	if int(status.level) == 0: record("weapons:crafted")
	return _done("武器等级 " + str(int(status.level) + 1), id)

func global_talent_status(id: int) -> Dictionary:
	var reason = _camp_action_reason("talents")
	var row = catalog.find("TalentTreeData", id)
	var level = rank(profile.data.talents, id)
	var levels = Catalog.ids(row.get("level_data_id_list", ""))
	var price: Dictionary = {}
	if row.is_empty(): reason = "未知天赋"
	elif level >= levels.size(): reason = "天赋已满级"
	else:
		var target = catalog.find("TalentTreeLevelData", levels[level])
		price = costs(target.get("need_material", ""))
		_add(price, 101, int(target.get("price", 0)))
		if target.is_empty(): reason = "天赋等级配置缺失"
		for parent in Catalog.ids(row.get("parent_id_list", "")):
			if rank(profile.data.talents, parent) == 0: reason = "请先学习" + Catalog.clean(Catalog.row_name(catalog.find("TalentTreeData", parent)))
		if reason.is_empty() and not can_afford(price): reason = "金币或天赋材料不足"
	return {"id": id, "level": level, "max_level": levels.size(), "price": price, "can_upgrade": reason.is_empty(), "reason": reason}

func upgrade_global_talent(id: int) -> Dictionary:
	return _camp_transaction(_upgrade_global_talent.bind(id))

func _upgrade_global_talent(id: int) -> Dictionary:
	var status = global_talent_status(id)
	if not status.can_upgrade: return _fail(status.reason)
	if not spend(status.price): return _fail("金币或天赋材料不足")
	profile.data.talents[str(id)] = int(status.level) + 1
	var row = catalog.find("TalentTreeData", id)
	return _done(Catalog.row_name(row), id)

func is_character_talent_marked(id: int) -> bool:
	return not catalog.find("CharTalentData", id).is_empty() and profile.data.get("marked_character_talents", []).has(id)

func toggle_character_talent_mark(id: int, character_id := 0) -> Dictionary:
	var row = catalog.find("CharTalentData", id)
	if row.is_empty(): return _fail("未知角色天赋")
	if character_id != 0 and int(row.chara_id) != character_id: return _fail("天赋不属于当前角色")
	var marks: Array = profile.data.marked_character_talents
	var marked = not marks.has(id)
	if marked: marks.append(id)
	else: marks.erase(id)
	var result = _done("已标记天赋" if marked else "已取消标记", id)
	result["marked"] = marked
	return result

func clear_character_talent_marks(character_id: int) -> Dictionary:
	if catalog.find("CharData", character_id).is_empty(): return _fail("未知角色")
	var marks: Array = profile.data.marked_character_talents
	var retained: Array = []
	for id in marks:
		var row = catalog.find("CharTalentData", int(id))
		if int(row.get("chara_id", 0)) != character_id: retained.append(id)
	profile.data.marked_character_talents = retained
	return _done("已清除当前角色的天赋标记", character_id)

func learn_character_talent(id: int) -> Dictionary:
	if not profile.data.run.get("talent_rewards", []).is_empty():
		var reward = pending_character_talent_reward()
		return choose_character_talent_reward(str(reward.get("key", "")), id)
	var row = catalog.find("CharTalentData", id)
	var run = profile.data.run
	if row.is_empty() or not run.active: return _fail("没有冒险或未知天赋")
	if int(row.chara_id) != int(run.character_id) or rank(profile.data.character_levels, row.chara_id) < int(row.unlock_chara_level): return _fail("角色等级不满足")
	var level = rank(run.talents, id)
	if level >= Catalog.ids(row.level_data_id_list).size() or stat("talent:choices") < 1: return _fail("无天赋选择次数或已满级")
	set_record("talent:choices", stat("talent:choices") - 1)
	run.talents[str(id)] = level + 1
	return _done(Catalog.row_name(row), id)

func _talent_candidates() -> Array:
	var run = profile.data.run
	var result: Array = []
	for row in catalog.rows("CharTalentData"):
		if int(row.chara_id) != int(run.character_id): continue
		if rank(profile.data.character_levels, row.chara_id) < int(row.unlock_chara_level): continue
		if rank(run.talents, row.id) >= Catalog.ids(row.level_data_id_list).size(): continue
		var weight = maxi(0, int(row.get("base_weight", 1)))
		# Packaged links raise the chance of synergistic talents already owned.
		for held in run.talents:
			if int(run.talents[held]) <= 0: continue
			for pair in str(catalog.find("CharTalentData", int(held)).get("get_add_weight_group", "")).split("|", false):
				var parts = pair.split(":")
				if parts.size() == 2 and int(parts[0]) == int(row.id): weight += maxi(0, int(parts[1]))
		if weight > 0: result.append({"id": int(row.id), "weight": weight})
	return result

func _fill_talent_reward(reward: Dictionary) -> void:
	var candidates = _talent_candidates()
	var choices: Array = []
	var levels: Dictionary = {}
	while choices.size() < 3 and not candidates.is_empty():
		var total: int = candidates.reduce(func(value, entry): return value + int(entry.weight), 0)
		var roll = next_random(total)
		for entry in candidates:
			roll -= int(entry.weight)
			if roll >= 0: continue
			var id = int(entry.id)
			var limit = Catalog.ids(catalog.find("CharTalentData", id).level_data_id_list).size()
			choices.append(id)
			levels[str(id)] = mini(limit, rank(profile.data.run.talents, id) + (3 if reward.get("max_level", false) else 1))
			candidates = candidates.filter(func(other): return int(other.id) != id)
			break
	reward.choices = choices
	reward.levels = levels

func queue_character_talent_reward(quality: String, count: int = 1, max_level: bool = false) -> void:
	var run = profile.data.run
	if not run.active: return
	if not run.has("talent_rewards"): run.talent_rewards = []
	for index in clampi(count, 0, 99):
		var serial = int(run.counters.get("talent_reward_serial", 0)) + 1
		run.counters.talent_reward_serial = serial
		run.talent_rewards.append({"key": "talent-" + str(serial), "quality": quality if quality in ["Low", "Normal", "High"] else "Low", "max_level": max_level, "choices": [], "levels": {}})
		record("talent:choices")

func pending_character_talent_reward() -> Dictionary:
	var run = profile.data.run
	if not run.active: return {}
	if run.get("talent_rewards", []).is_empty() and stat("talent:choices") > 0:
		# Older saves have a count only; materialize it once without adding chances.
		var legacy_count = stat("talent:choices")
		set_record("talent:choices", 0)
		queue_character_talent_reward("Low", legacy_count)
	while not run.get("talent_rewards", []).is_empty():
		var reward: Dictionary = run.talent_rewards[0]
		reward.choices = reward.choices.map(func(value): return int(value))
		for id in reward.levels: reward.levels[id] = int(reward.levels[id])
		if reward.choices.is_empty(): _fill_talent_reward(reward)
		if not reward.choices.is_empty(): return reward
		var suffix = {"Low": "", "Normal": "_Normal", "High": "_High"}.get(str(reward.quality), "")
		var magic = int(catalog.config.get("SelectTalentIfMaxChangeToMaterialPoint" + suffix, catalog.config.get("SelectTalentIfMaxChangeToMaterialPoint", 100)))
		grant_material(102, magic)
		run.counters["talent_claim:" + str(reward.key)] = 1
		run.talent_rewards.pop_front()
		set_record("talent:choices", maxi(0, stat("talent:choices") - 1))
	return {}

func choose_character_talent_reward(key: String, id: int) -> Dictionary:
	var run = profile.data.run
	if not run.active: return _fail("没有进行中的冒险")
	for reward in run.get("talent_rewards", []):
		if str(reward.key) != key: continue
		if not reward.choices.any(func(value): return int(value) == id): return _fail("不在本次天赋候选中")
		var row = catalog.find("CharTalentData", id)
		var target = int(reward.levels.get(str(id), 0))
		if row.is_empty() or int(row.chara_id) != int(run.character_id) or target <= rank(run.talents, id) or target > Catalog.ids(row.level_data_id_list).size(): return _fail("天赋已变化，请刷新候选")
		run.talents[str(id)] = target
		run.counters["talent_claim:" + key] = 1
		run.talent_rewards.erase(reward)
		set_record("talent:choices", maxi(0, stat("talent:choices") - 1))
		return _done("%s Lv.%d" % [Catalog.row_name(row), target], id)
	return _fail("天赋奖励已领取或不存在")

func refresh_character_talent_reward(key: String) -> Dictionary:
	var run = profile.data.run
	if not run.active or int(run.counters.get("SelectRefreshTime", 0)) <= 0: return _fail("重选次数不足")
	for reward in run.get("talent_rewards", []):
		if str(reward.key) != key: continue
		if _talent_candidates().is_empty(): return _fail("没有可选天赋")
		_fill_talent_reward(reward)
		_add(run.counters, "SelectRefreshTime", -1)
		return _done("天赋已重选")
	return _fail("天赋奖励不存在")

func building_status(id: int) -> Dictionary:
	var row = catalog.find("Buildings", id)
	var level = rank(profile.data.buildings, id)
	var maximum = int(row.get("max_level", 0))
	var complete = level >= maximum
	var stage = mini(level, maxi(0, maximum - 1))
	var gate = int(_part(row.get("unlock_data_id", ""), stage))
	var requirement = unlock_progress(gate)
	requirement["id"] = gate
	var price = costs(_part(row.get("need_materials", ""), stage, ";")) if not complete else {}
	if not complete: _add(price, 101, int(_part(row.get("need_gold", ""), stage)))
	var reason = _camp_action_reason()
	if row.is_empty(): reason = "未知设施"
	elif maximum == 0: reason = "建筑师负责营地设施建设"
	elif complete: reason = "设施已满级"
	elif not requirement.complete: reason = unlock_reason(gate)
	elif reason.is_empty() and not can_afford(price): reason = "建设材料不足"
	return {"id": id, "exists": not row.is_empty(), "level": level, "max_level": maximum, "stage": stage, "name": _part(Catalog.row_name(row), stage), "description": Catalog.clean(_part(row.get("description", ""), stage)), "price": price, "requirements": [requirement] if gate != 0 else [], "unlocked": bool(requirement.complete), "affordable": can_afford(price), "complete": complete, "can_upgrade": reason.is_empty(), "reason": reason, "target": _part(row.get("build_anim_target_transform_name", ""), stage)}

func upgrade_building(id: int) -> Dictionary:
	return _camp_transaction(_upgrade_building.bind(id))

func _upgrade_building(id: int) -> Dictionary:
	var status = building_status(id)
	if not status.can_upgrade: return _fail(status.reason)
	if not spend(status.price): return _fail("建设材料不足")
	profile.data.buildings[str(id)] = int(status.level) + 1
	record("building:upgraded")
	_emit_gameplay_event({"type": "building_upgraded", "id": id, "level": int(status.level) + 1, "target": status.target})
	return _done(status.name, id)

func partner_status(id: int) -> Dictionary:
	var row = catalog.find("MonsterPartnerData", id)
	var level = rank(profile.data.partners, id)
	var levels = str(row.get("levelup_need_material", "")).split(",", false)
	var price = costs(levels[level - 1]) if level >= 1 and level <= levels.size() else {}
	var reason = _camp_action_reason("partners")
	if row.is_empty(): reason = "伙伴不存在"
	elif bool(row.get("is_admin_only", false)): reason = "管理员专用伙伴"
	var unlock_reason_text = reason
	if level > 0: unlock_reason_text = "伙伴已解锁"
	elif unlock_reason_text.is_empty() and stat("kill:" + str(int(row.get("enemy_id", 0)))) < int(row.get("unlock_need_kill_count", 0)): unlock_reason_text = "击败该怪物次数不足"
	var upgrade_reason = reason
	if level == 0: upgrade_reason = "伙伴未解锁"
	elif level > levels.size(): upgrade_reason = "伙伴已满级"
	elif upgrade_reason.is_empty() and not can_afford(price): upgrade_reason = "伙伴升级材料不足"
	var equip_reason = reason
	if level == 0: equip_reason = "伙伴未解锁"
	elif profile.data.work.any(func(order): return int(order.get("partner_id", 0)) == id): equip_reason = "伙伴派遣中"
	var skill = preload("res://scripts/domain/partner_skills.gd").new(self).definition(id, maxi(1, level))
	return {"id": id, "level": level, "max_level": levels.size() + 1, "price": price, "unlocked": level > 0,
		"can_unlock": unlock_reason_text.is_empty(), "unlock_reason": unlock_reason_text, "can_upgrade": upgrade_reason.is_empty(), "reason": upgrade_reason,
		"can_equip": equip_reason.is_empty(), "equip_reason": equip_reason, "equipped": profile.data.equipped_partners.has(id),
		"skills": skill, "skill_description": str(skill.get("description", row.get("resonance_skill_description", ""))), "skill_unlocked": camp_feature_status("partner_skill").available}

func unlock_partner(id: int) -> Dictionary:
	return _camp_transaction(_unlock_partner.bind(id))

func _unlock_partner(id: int) -> Dictionary:
	if _partner_mutating: return _fail("伙伴操作处理中")
	var state = partner_status(id)
	if not state.can_unlock: return _fail(state.unlock_reason)
	_partner_mutating = true
	profile.data.partners[str(id)] = 1
	return _finish_partner_transaction("伙伴已解锁", id)

func equip_partner(id: int) -> Dictionary:
	return _camp_transaction(_equip_partner.bind(id))

func _equip_partner(id: int) -> Dictionary:
	if _partner_mutating: return _fail("伙伴操作处理中")
	var state = partner_status(id)
	if not state.can_equip: return _fail(state.equip_reason)
	_partner_mutating = true
	profile.data.equipped_partners = [id]
	return _finish_partner_transaction("伙伴已装备", id)

func unequip_partner(id: int) -> Dictionary:
	return _camp_transaction(_unequip_partner.bind(id))

func _unequip_partner(id: int) -> Dictionary:
	if _partner_mutating: return _fail("伙伴操作处理中")
	var reason = _camp_action_reason("partners")
	if not reason.is_empty(): return _fail(reason)
	if not profile.data.equipped_partners.has(id): return _fail("未装备该伙伴")
	_partner_mutating = true
	profile.data.equipped_partners.erase(id)
	return _finish_partner_transaction("伙伴已卸下", id)

func upgrade_partner(id: int) -> Dictionary:
	return _camp_transaction(_upgrade_partner.bind(id))

func _upgrade_partner(id: int) -> Dictionary:
	if _partner_mutating: return _fail("伙伴操作处理中")
	var state = partner_status(id)
	if not state.can_upgrade: return _fail(state.reason)
	_partner_mutating = true
	if not spend(state.price):
		_partner_mutating = false
		return _fail("伙伴升级材料不足")
	profile.data.partners[str(id)] = int(state.level) + 1
	return _finish_partner_transaction("伙伴等级 " + str(int(state.level) + 1), id)

func _finish_partner_transaction(message: String, id: int) -> Dictionary:
	var result = _done(message, id)
	_partner_mutating = false
	return result

func work_status(id: int) -> Dictionary:
	var row = catalog.find("MonsterWorkData", id)
	var level = rank(profile.data.work_levels, id)
	var rewards = Catalog.ids(row.get("finish_get_materials", ""))
	var price = costs(_part(row.get("start_cost_materials", ""), level))
	var upgrade_price = costs(_part(row.get("level_up_need_materials", ""), level))
	var upgrade_gold = _part(row.get("level_up_need_gold", ""), level)
	if not upgrade_gold.is_empty(): _add(upgrade_price, 101, int(upgrade_gold))
	var feature = {"Rare": "work_rare", "Precious": "work_precious"}.get(str(row.get("type", "")), "work")
	var reason = _camp_action_reason(feature)
	var gate = int(row.get("unlock_data_id", 0))
	if row.is_empty(): reason = "未知派遣"
	elif not is_unlocked(gate): reason = unlock_reason(gate)
	elif level < 0 or level >= rewards.size(): reason = "派遣等级配置无效"
	var unlocked = reason.is_empty()
	var upgrade_reason = reason
	var order: Dictionary = {}
	var available: Array = []
	for existing in profile.data.work:
		if int(existing.work_id) == id: order = existing.duplicate(true)
	for partner in profile.data.partners:
		var partner_id = int(partner)
		if rank(profile.data.partners, partner_id) < 1 or profile.data.equipped_partners.has(partner_id): continue
		if not profile.data.work.any(func(job): return int(job.partner_id) == partner_id): available.append(partner_id)
	available.sort()
	if reason.is_empty():
		if not order.is_empty(): reason = "派遣进行中" if int(order.due_utc) > int(utc_now.call()) else "请先领取派遣奖励"
		elif not profile.data.work.is_empty(): reason = "已有派遣进行中，请先领取奖励并停止当前派遣"
	if upgrade_reason.is_empty():
		if upgrade_gold.is_empty() or level + 1 >= rewards.size(): upgrade_reason = "派遣已满级"
		elif not can_afford(upgrade_price): upgrade_reason = "派遣升级材料不足"
	var duration = _work_duration(row)
	var queue = _work_queue_progress(order)
	var daily = _work_daily_status()
	var prepaid = int(order.get("prepaid_quantity", 1 if not order.is_empty() and not order.has("economy_version") else 0))
	var claimable = mini(int(queue.completed), int(daily.remaining))
	for key in price:
		if int(price[key]) > 0: claimable = mini(claimable, prepaid + int(material(int(key)) / int(price[key])))
	var claim_price: Dictionary = {}
	for key in price: claim_price[key] = int(price[key]) * maxi(0, claimable - prepaid)
	var claim_reason = ""
	if profile.data.run.active: claim_reason = "请返回营地领取派遣奖励"
	elif queue.completed == 0: claim_reason = "派遣尚未完成"
	elif daily.remaining == 0: claim_reason = "今日派遣领取次数已用完"
	elif claimable == 0: claim_reason = "领取材料不足"
	return {"id": id, "exists": not row.is_empty(), "level": level, "max_level": rewards.size(), "name": Catalog.row_name(row), "description": Catalog.clean(Catalog.description(row)), "price": price, "claim_price": claim_price, "upgrade_price": upgrade_price, "reward": {"id": int(row.get("materia_id", 0)), "amount": int(rewards[level]) if level >= 0 and level < rewards.size() else 0}, "duration_seconds": duration, "queue_max": _work_queue_max(), "quantity": queue.quantity, "completed_quantity": queue.completed, "claimable_quantity": claimable, "daily_limit": daily.limit, "daily_remaining": daily.remaining, "next_claim_seconds": queue.next_claim_seconds, "order": order, "remaining_seconds": queue.next_claim_seconds, "ready": claimable > 0 and claim_reason.is_empty(), "claim_reason": claim_reason, "unlocked": unlocked, "can_start": reason.is_empty(), "can_upgrade": upgrade_reason.is_empty(), "reason": reason, "upgrade_reason": upgrade_reason, "available_partners": available}

func _work_duration(row: Dictionary) -> int:
	var minutes = maxi(1, int(row.get("cost_time", 1)))
	return maxi(1, int(minutes / 2) if stat("blessing") > 0 else minutes) * 60

func unlock_camp_decoration(id: int) -> Dictionary:
	return decorations.unlock(id)

func equip_camp_decoration(slot_id: int, id: int) -> Dictionary:
	return decorations.equip(slot_id, id)

func _work_queue_max() -> int:
	return 24 if stat("blessing") == 2 else 6

func _work_daily_status() -> Dictionary:
	# The package resets daily data at 22:00 UTC (06:00 in China).
	var day = floori((float(utc_now.call()) - 22 * 3600) / 86400.0)
	var saved: Dictionary = profile.data.get("work_claims", {})
	var saved_day = int(saved.get("day", day))
	var count = 0 if day > saved_day else int(saved.get("count", 0))
	var limit = 48 if stat("blessing") == 2 else 30
	return {"day": maxi(day, saved_day), "count": count, "limit": limit, "remaining": maxi(0, limit - count)}

func _work_queue_progress(order: Dictionary) -> Dictionary:
	if order.is_empty(): return {"quantity": 0, "completed": 0, "claimable": 0, "next_claim_seconds": 0, "seconds": 0, "duration": 0}
	var old_quantity = maxi(1, int(order.get("quantity", 1)))
	var remaining = maxi(0, int(order.due_utc) - int(utc_now.call()))
	var old_duration = maxi(1, int(order.get("cycle_seconds", int(order.due_utc) - int(order.started_utc))))
	var progress = clampi(old_quantity * old_duration - remaining, 0, old_quantity * old_duration)
	progress = maxi(0, progress - int(order.get("claimed_quantity", 0)) * old_duration)
	progress = int(progress / 60) * 60
	var duration = _work_duration(catalog.find("MonsterWorkData", int(order.work_id)))
	var quantity = _work_queue_max()
	progress = mini(progress, quantity * duration)
	var completed = int(progress / duration)
	return {"quantity": quantity, "completed": completed, "claimable": completed, "seconds": progress, "duration": duration, "next_claim_seconds": 0 if completed == quantity else duration - progress % duration}

func _store_work_progress(order: Dictionary, seconds: int, queue: Dictionary) -> void:
	var now = int(utc_now.call())
	order["started_utc"] = now
	order["due_utc"] = now + int(queue.quantity) * int(queue.duration) - clampi(seconds, 0, int(queue.quantity) * int(queue.duration))
	order["cycle_seconds"] = int(queue.duration)
	order["quantity"] = int(queue.quantity)
	order["claimed_quantity"] = 0
	order["economy_version"] = 2

func add_work_progress(id: int, seconds: int) -> bool:
	if seconds <= 0: return false
	for order in profile.data.work:
		if int(order.work_id) != id: continue
		var queue = _work_queue_progress(order)
		var progress = mini(int(queue.quantity) * int(queue.duration), int(queue.seconds) + seconds)
		if progress == int(queue.seconds): return false
		if not order.has("economy_version"): order["prepaid_quantity"] = 1
		_store_work_progress(order, progress, queue)
		return true
	return false

func start_work(id: int, _partner_id: int = 0, quantity: int = 0) -> Dictionary:
	return _camp_transaction(_start_work.bind(id, _partner_id, quantity))

func _start_work(id: int, _partner_id: int = 0, quantity: int = 0) -> Dictionary:
	var status = work_status(id)
	if not status.can_start: return _fail(status.reason)
	if quantity < 0 or quantity > int(status.queue_max): return _fail("派遣队列数量超过当前上限")
	quantity = int(status.queue_max)
	var now = int(utc_now.call())
	profile.data.work.append({"work_id": id, "partner_id": 0, "started_utc": now, "due_utc": now + int(status.duration_seconds) * quantity, "material_id": int(status.reward.id), "reward": int(status.reward.amount), "level": int(status.level), "quantity": quantity, "claimed_quantity": 0, "cycle_seconds": int(status.duration_seconds), "economy_version": 2, "prepaid_quantity": 0})
	_emit_gameplay_event({"type": "work_started", "id": id, "quantity": quantity})
	return _done("派遣已开始", id)

func collect_work(id: int) -> Dictionary:
	return _camp_transaction(_collect_work.bind(id))

func _collect_work(id: int) -> Dictionary:
	if profile.data.run.active: return _fail("请返回营地领取派遣奖励")
	if _collecting_work: return _fail("派遣奖励正在领取")
	for order in profile.data.work:
		if int(order.work_id) == id:
			var status = work_status(id)
			if not status.ready: return _fail(status.claim_reason)
			var queue = _work_queue_progress(order)
			var count = int(status.claimable_quantity)
			if not spend(status.claim_price): return _fail("领取材料不足")
			_collecting_work = true
			var prepaid = int(order.get("prepaid_quantity", 1 if not order.has("economy_version") else 0))
			order["prepaid_quantity"] = maxi(0, prepaid - count)
			_store_work_progress(order, int(queue.seconds) - count * int(queue.duration), queue)
			var daily = _work_daily_status()
			profile.data["work_claims"] = {"day": daily.day, "count": int(daily.count) + count}
			var reward = int(status.reward.amount) * count
			record("work:finished", count)
			grant_material(int(status.reward.id), reward)
			_emit_gameplay_event({"type": "work_collected", "id": id, "material_id": int(status.reward.id), "amount": reward, "quantity": count})
			_collecting_work = false
			return _done("派遣奖励已领取", id)
	return _fail("没有该派遣订单")

func stop_work(id: int) -> Dictionary:
	return _camp_transaction(_stop_work.bind(id))

func _stop_work(id: int) -> Dictionary:
	if profile.data.run.active: return _fail("请返回营地后操作")
	for order in profile.data.work:
		if int(order.work_id) != id: continue
		profile.data.work.erase(order)
		_emit_gameplay_event({"type": "work_stopped", "id": id, "partner_id": int(order.partner_id)})
		return _done("派遣已停止", id)
	return _fail("没有该派遣订单")

func advance_work_from_adventure(total_depth: int, region: int, is_final_level: bool, once_key: String) -> Dictionary:
	var run = profile.data.run
	if once_key.is_empty() or not run.active: return _fail("没有可结算的冒险派遣进度")
	# One settlement per run, including retries with a different caller key.
	if run.counters.has("work:settlement_progress"): return _fail("冒险派遣进度已结算")
	var minutes = 0
	if total_depth >= 2 and not profile.data.work.is_empty():
		minutes = total_depth * maxi(0, int(catalog.config.get("MonsterWork_CaculateProccess_PerRoom", 1)))
		minutes += maxi(0, region - (0 if is_final_level else 1)) * maxi(0, int(catalog.config.get("MonsterWork_CaculateProccess_PerLevel", 5)))
	run.counters["work:settlement_progress"] = once_key
	run.counters["work:bonus_minutes"] = minutes
	var affected: Array = []
	for order in profile.data.work:
		var queue = _work_queue_progress(order)
		var progress = mini(int(queue.quantity) * int(queue.duration), int(queue.seconds) + minutes * 60)
		# Legacy assignments prepaid one output when they started.
		if not order.has("economy_version"): order["prepaid_quantity"] = 1
		_store_work_progress(order, progress, queue)
		if progress > int(queue.seconds): affected.append({"id": int(order.work_id), "seconds": progress - int(queue.seconds)})
	var result = _done("冒险为派遣增加 %d 分钟进度" % minutes)
	result["minutes"] = minutes
	result["affected"] = affected
	return result

func upgrade_work(id: int) -> Dictionary:
	return _camp_transaction(_upgrade_work.bind(id))

func _upgrade_work(id: int) -> Dictionary:
	var status = work_status(id)
	if not status.can_upgrade: return _fail(status.upgrade_reason)
	if not spend(status.upgrade_price): return _fail("派遣升级材料不足")
	profile.data.work_levels[str(id)] = int(status.level) + 1
	record("work:upgraded")
	return _done("派遣已升级", id)

func meal_status(id: int, level: int = 1) -> Dictionary:
	var row = catalog.find("CatMealData", id)
	var maximum = Catalog.ids(row.get("AbilityItemId", "")).size()
	var researched = rank(profile.data.recipes, id)
	var reason = _meal_reason(row, level)
	var price = _meal_price(row, level) if level > 0 and level <= maximum else {}
	var selected = rank(profile.data.get("meal_selection", {}), id) == level
	var select_reason = reason
	if select_reason.is_empty() and level > researched: select_reason = "请先研究该料理等级"
	if select_reason.is_empty() and not selected and not profile.data.get("meal_selection", {}).has(str(id)) and profile.data.get("meal_selection", {}).size() >= meal_order_limit(): select_reason = "餐单最多选择 %d 道料理" % meal_order_limit()
	var research_reason = _meal_reason(row, researched + 1)
	var research_price = _meal_price(row, researched + 1) if researched < maximum else {}
	if researched >= maximum: research_reason = "料理研究已满级"
	if research_reason.is_empty() and not can_afford(research_price): research_reason = "料理研究材料不足"
	var buy_reason = reason
	if buy_reason.is_empty() and level > researched: buy_reason = "请先研究该料理等级"
	if buy_reason.is_empty() and not can_afford(price): buy_reason = "料理材料不足"
	return {"id": id, "level": level, "max_level": maximum, "researched_level": researched, "selected": selected, "purchased": rank(purchased_meals(), id) == level, "price": price, "can_cook": buy_reason.is_empty(), "can_select": select_reason.is_empty(), "select_reason": select_reason, "reason": buy_reason, "can_research": research_reason.is_empty(), "research_reason": research_reason, "research_price": research_price, "description": Catalog.clean(_part(row.get("Description", ""), level - 1))}

func meal_order_limit() -> int:
	return 3 if rank(profile.data.buildings, 7) > 2 else 2

func _meal_price(row: Dictionary, level: int) -> Dictionary:
	var materials = str(row.get("NeedMaterials", "")).split(";")
	var gold = str(row.get("NeedGold", "")).split("|")
	var price = costs(materials[clampi(level - 1, 0, materials.size() - 1)])
	_add(price, 101, int(gold[clampi(level - 1, 0, gold.size() - 1)]))
	return price

func _meal_reason(row: Dictionary, level: int, recook: bool = false) -> String:
	var reason = str(camp_feature_status("meals").reason) if recook else _camp_action_reason("meals")
	if not reason.is_empty(): return reason
	if row.is_empty() or level < 1 or level > Catalog.ids(row.get("AbilityItemId", "")).size(): return "料理等级不存在"
	for gate in Catalog.ids(row.get("UnlockDataId", "")):
		if gate > 0 and not is_unlocked(gate): return unlock_reason(gate)
	return ""

func purchased_meals() -> Dictionary:
	if profile.data.has("purchased_meals"): return profile.data.purchased_meals
	# Older saves stored the one purchased dish in these two fields.
	var id = int(profile.data.get("selected_meal", 0))
	var level = int(profile.data.get("meal_rank", 0))
	return {str(id): level} if id > 0 and level > 0 else {}

func research_meal(id: int) -> Dictionary:
	return _camp_transaction(_research_meal.bind(id))

func _research_meal(id: int) -> Dictionary:
	var status = meal_status(id)
	if not status.can_research: return _fail(status.research_reason)
	if not spend(status.research_price): return _fail("料理研究材料不足")
	var previous = int(status.researched_level)
	profile.data.recipes[str(id)] = previous + 1
	record("meal:research" if previous == 0 else "meal:upgraded")
	profile.data.meal_selection = {str(id): previous + 1}
	profile.data.last_meals = profile.data.meal_selection.duplicate()
	return _done("料理研究至 Lv.%d" % (previous + 1), id)

func select_meal(id: int, level: int = 1) -> Dictionary:
	return _camp_transaction(_select_meal.bind(id, level))

func _select_meal(id: int, level: int = 1) -> Dictionary:
	var status = meal_status(id, level)
	if not status.can_select: return _fail(status.select_reason)
	var selection: Dictionary = profile.data.get("meal_selection", {}).duplicate()
	if status.selected: selection.erase(str(id))
	else: selection[str(id)] = level
	profile.data.meal_selection = selection
	profile.data.last_meals = selection.duplicate()
	return _done("已更新餐单", id)

func _meal_recook_order() -> Dictionary:
	var restored: Dictionary = {}
	for key in profile.data.get("last_meals", {}):
		var row = catalog.find("CatMealData", int(key))
		var maximum = mini(rank(profile.data.recipes, key), Catalog.ids(row.get("AbilityItemId", "")).size())
		if maximum < 1 or not _meal_reason(row, 1, true).is_empty(): continue
		restored[str(int(key))] = clampi(int(profile.data.last_meals[key]), 1, maximum)
		if restored.size() >= meal_order_limit(): break
	return restored

func meal_order_status(recook: bool = false, order: Dictionary = {}) -> Dictionary:
	var meals: Dictionary = _meal_recook_order() if recook else order.duplicate() if not order.is_empty() else profile.data.get("meal_selection", {}).duplicate()
	var reason = ""
	var price: Dictionary = {}
	if meals.is_empty(): reason = "没有可复购的餐单" if recook else "请先选择料理"
	elif meals.size() > meal_order_limit(): reason = "餐单最多选择 %d 道料理" % meal_order_limit()
	elif recook and bool(profile.data.get("meal_purchased", not purchased_meals().is_empty())): reason = "本区域已享用料理"
	for key in meals:
		var id = int(key)
		var level = int(meals[key])
		var row = catalog.find("CatMealData", id)
		var meal_reason = _meal_reason(row, level, recook)
		if meal_reason.is_empty() and level > rank(profile.data.recipes, id): meal_reason = "请先研究该料理等级"
		if reason.is_empty() and not meal_reason.is_empty(): reason = meal_reason
		if row.is_empty() or level < 1: continue
		var meal_price = _meal_price(row, level)
		for resource in meal_price: _add(price, int(resource), int(meal_price[resource]))
	var buy_reason = reason
	if buy_reason.is_empty() and not can_afford(price): buy_reason = "料理材料不足"
	return {"meals": meals, "price": price, "count": meals.size(), "limit": meal_order_limit(), "can_buy": buy_reason.is_empty(), "reason": buy_reason, "can_ad": reason.is_empty(), "ad_reason": reason}

func _complete_meal_purchase(meals: Dictionary) -> void:
	var purchased = purchased_meals().duplicate()
	for key in meals: purchased[str(key)] = int(meals[key])
	profile.data.purchased_meals = purchased
	profile.data.last_meals = meals.duplicate()
	profile.data.meal_selection = {}
	profile.data.meal_purchased = true
	profile.data.selected_meal = 0
	profile.data.meal_rank = 0

func buy_meal(id: int = 0, level: int = 1) -> Dictionary:
	return _camp_transaction(_buy_meal.bind(id, level))

func _buy_meal(id: int = 0, level: int = 1) -> Dictionary:
	var status = meal_order_status(false, {str(id): level} if id > 0 else {})
	if not status.can_buy: return _fail(status.reason)
	if not spend(status.price): return _fail("料理材料不足")
	_complete_meal_purchase(status.meals)
	return _done("已享用 %d 道料理" % int(status.count))

func recook_meal(_id: int = 0) -> Dictionary:
	return _camp_transaction(_recook_meal)

func _recook_meal() -> Dictionary:
	var status = meal_order_status(true)
	if not status.can_buy: return _fail(status.reason)
	if not spend(status.price): return _fail("料理材料不足")
	_complete_meal_purchase(status.meals)
	return _done("已复购上次餐单")

func clear_invalid_meals(event: String) -> void:
	var purchased = purchased_meals().duplicate()
	if not profile.data.has("last_meals") and not purchased.is_empty(): profile.data.last_meals = purchased.duplicate()
	for key in purchased.keys():
		if event == "CompleteRun" or (event == "CompleteRegion" and int(catalog.find("CatMealData", int(key)).get("EffectType", 1)) == 1): purchased.erase(key)
	profile.data.purchased_meals = purchased
	profile.data.meal_purchased = false
	profile.data.selected_meal = 0
	profile.data.meal_rank = 0
	if event == "CompleteRun": profile.data.meal_selection = {}

func cook_meal(id: int, level: int = 1) -> Dictionary:
	return buy_meal(id, level)

func difficulty_unlocked(level: int) -> bool:
	return level >= 0 and level <= 10 and (level == 0 or stat("difficulty:win:" + str(level - 1)) > 0 or (level == 1 and stat("wins") > 0))

func chaos_max_level() -> int:
	var maximum = 1
	for key in catalog.config.get("ChaosLevelRewardDict", {}): maximum = maxi(maximum, int(key))
	return maximum

func chaos_cleared_level(character: int = 0) -> int:
	return clampi(stat("chaos:clear:" + str(_selected_character(character))), 0, chaos_max_level())

func selected_chaos_level(character: int = 0) -> int:
	var id = _selected_character(character)
	var maximum = mini(chaos_max_level(), chaos_cleared_level(id) + 1)
	var stored = stat("chaos:selected:" + str(id)) if profile.data.stats.has("chaos:selected:" + str(id)) else maximum
	return clampi(stored, 1, maximum)

func chaos_drop_rate_multiplier(layer: int = -1) -> float:
	if layer < 0:
		if not profile.data.run.active or int(profile.data.run.difficulty) != 10: return 1.0
		layer = int(profile.data.run.counters.get("chaos_level", 1))
	return float(catalog.config.get("ChaosLevelDropRateMulti", {}).get(str(layer), 1.0))

func select_chaos_level(level: int, character: int = 0) -> Dictionary:
	return _camp_transaction(_select_chaos_level.bind(level, character))

func _select_chaos_level(level: int, character: int = 0) -> Dictionary:
	var id = _selected_character(character)
	if profile.data.run.active: return _fail("请返回营地后选择混沌层数")
	if not difficulty_unlocked(10): return _fail("通关难度 9 后解锁混沌模式")
	if rank(profile.data.character_levels, id) == 0 or level < 1 or level > mini(chaos_max_level(), chaos_cleared_level(id) + 1): return _fail("混沌层数尚未解锁")
	set_record("chaos:selected:" + str(id), level)
	return _done("已选择混沌 %d 层" % level, level)

func _difficulty_rows(level: int, rewards_only: bool = false) -> Array:
	var result: Array = []
	for row in catalog.rows("RogueLevelDifficultyInfluencerData"):
		if bool(row.get("IsDisable", false)): continue
		var category = str(row.get("DifficultyCategory", "Normal"))
		var tier = int(row.get("Tier", 0))
		if category == "Heat" or (category == "Chaos" and level != 10): continue
		if category == "Normal" and tier > mini(level, 9): continue
		if category == "Chaos" and tier > 1: continue
		if rewards_only and (str(row.get("DifficultyType", "")) != "Reward" or category != ("Chaos" if level == 10 else "Normal") or tier != (1 if level == 10 else level)): continue
		result.append(row)
	return result

func difficulty_attributes(level: int = -1) -> Dictionary:
	if level < 0: level = int(profile.data.run.difficulty)
	var result: Dictionary = {}
	var chosen: Dictionary = {}
	for row in _difficulty_rows(level):
		var attribute = str(row.get("AttributeType", "None"))
		if attribute in ["", "None"]: continue
		var priority = int(row.get("Tier", 0)) + (100 if row.get("DifficultyCategory", "Normal") == "Chaos" else 0)
		if chosen.has(attribute) and int(chosen[attribute]) > priority: continue
		chosen[attribute] = priority
		result[attribute] = int(row.get("Value", 0))
	return result

func difficulty_status(level: int, character: int = 0) -> Dictionary:
	var id = _selected_character(character)
	var unlocked = difficulty_unlocked(level)
	var reason = "" if unlocked else "通关难度 %d 后解锁" % maxi(0, level - 1)
	if level < 0 or level > 10: reason = "难度不存在"
	var rewards: Array = []
	for row in _difficulty_rows(level, true):
		rewards.append({"id": Catalog.row_id(row), "attribute": str(row.AttributeType), "value": int(row.Value), "description": Catalog.clean(row.get("Description", ""))})
	var descriptions: Array[String] = []
	for row in _difficulty_rows(level):
		if str(row.get("DifficultyType", "")) == "Reward" or not bool(row.get("EnableShowUI", true)): continue
		var text = Catalog.clean(row.get("Description", ""))
		if not text.is_empty() and not text.begins_with("RogueLevelDifficulty_"): descriptions.append(text)
	var can_start = unlocked and not profile.data.run.active and profile.data.run.get("outcome", {}).is_empty() and rank(profile.data.character_levels, id) > 0
	if unlocked and profile.data.run.active: reason = "冒险中无法更改难度"
	elif unlocked and not profile.data.run.get("outcome", {}).is_empty(): reason = "请先完成冒险结算"
	elif unlocked and rank(profile.data.character_levels, id) == 0: reason = "角色尚未解锁"
	var chaos_rewards: Array = []
	var unclaimed: Dictionary = {}
	var cleared = chaos_cleared_level(id)
	var claimed = stat("chaos:claimed:" + str(id))
	for layer in range(1, chaos_max_level() + 1):
		var reward = costs(catalog.config.get("ChaosLevelRewardDict", {}).get(str(layer), ""))
		var available = layer <= cleared and layer > claimed
		chaos_rewards.append({"level": layer, "rewards": reward, "claimed": layer <= claimed, "available": available, "unlocked": layer <= mini(chaos_max_level(), cleared + 1)})
		if available:
			for key in reward: _add(unclaimed, key, int(reward[key]))
	return {"difficulty": level, "name": "混沌模式" if level == 10 else "难度 %d" % level, "category": "Chaos" if level == 10 else "Normal", "tier": 1 if level == 10 else level, "unlocked": unlocked, "can_start": can_start, "reason": reason, "description": "\n".join(descriptions), "rewards": rewards, "win_count": stat("difficulty:win:" + str(level)), "chaos_level": selected_chaos_level(id), "chaos_cleared": cleared, "chaos_max": chaos_max_level(), "chaos_rewards": chaos_rewards, "unclaimed_chaos_rewards": unclaimed}

func adventure_preparation_status(level: int, character: int = 0) -> Dictionary:
	var status = difficulty_status(level, character)
	status["chaos_drop_multiplier"] = chaos_drop_rate_multiplier(int(status.chaos_level)) if level == 10 else 1.0
	var owned_tokens: Array = []
	for row in catalog.rows("RelationshipTokenData"):
		var id = int(row.get("material_id", 0))
		if stat("token:" + str(id)) > 0 and not owned_tokens.has(id): owned_tokens.append(id)
	status["tokens_unlocked"] = not owned_tokens.is_empty()
	status["tokens_reason"] = "" if not owned_tokens.is_empty() else "获得信物后解锁"
	status["token_count"] = relationship_tokens.equipped().size()
	status["extra_challenge_unlocked"] = rank(profile.data.buildings, 5) >= 2
	status["extra_challenge_reason"] = "" if status.extra_challenge_unlocked else "委托设施达到 2 级后解锁"
	status["selected_weapon"] = int(profile.data.selected_weapon)
	return status

func claim_chaos_rewards(character: int = 0) -> Dictionary:
	return _camp_transaction(_claim_chaos_rewards.bind(character))

func _claim_chaos_rewards(character: int = 0) -> Dictionary:
	var id = _selected_character(character)
	if profile.data.run.active: return _fail("请返回营地后领取混沌奖励")
	if rank(profile.data.character_levels, id) == 0: return _fail("角色尚未解锁")
	var status = difficulty_status(10, id)
	var rewards: Dictionary = status.unclaimed_chaos_rewards
	if rewards.is_empty(): return _fail("没有可领取的混沌奖励")
	set_record("chaos:claimed:" + str(id), int(status.chaos_cleared))
	for key in rewards: grant_material(int(key), int(rewards[key]))
	var result = _done("混沌首通奖励已领取", id)
	result["rewards"] = rewards
	return result

func begin_run(seed_value: int, character: int, health_value: float, difficulty: int = 0) -> Dictionary:
	if _camp_transaction_active: return _fail("请等待营地操作完成")
	if profile.data.run.active or not profile.data.run.get("outcome", {}).is_empty() or rank(profile.data.character_levels, character) == 0 or health_value <= 0: return _fail("无法开始冒险")
	if not difficulty_unlocked(difficulty): return _fail(str(difficulty_status(difficulty, character).reason))
	profile.data.run = Profile.new_run(seed_value, character, health_value)
	profile.data.run.active = true
	profile.data.run.difficulty = difficulty
	if difficulty == 10: profile.data.run.counters["chaos_level"] = selected_chaos_level(character)
	profile.data.materials["102"] = 0
	set_record("talent:choices", 0)
	record("runs")
	for ability in persistent_ability_ids(): effects.acquire(int(ability))
	var attrs = attributes()
	_add(profile.data.run.counters, "SelectRefreshTime", maxi(0, int(attrs.get("AddSelectCharaTalentRefreshTimeWhenNewRun", 0))))
	_add(profile.data.run.counters, "RevivalRemainCount", maxi(0, int(attrs.get("TalentOfferRevivalCount", 0))))
	effects.dispatch("StartNewRun", "0")
	return _done("冒险已开始")

func record_kill(enemy_id: int, gold: int = 0) -> void:
	if profile.data.run.active: _add(profile.data.run.counters, "run:kills", 1)
	record("kill:" + str(enemy_id))
	record("kills")
	grant_material(101, gold)
	var row = catalog.find("EnemyData", enemy_id)
	if not row.is_empty():
		var rate = str(row.enemy_rate)
		record_purification_event("KillEnemy", "2" if rate == "Boss" else "1" if rate == "Elite" else "0", 1, "", false)
	effects.dispatch("KillEnemy", "2" if row.get("enemy_rate", "") == "Boss" else "1" if row.get("enemy_rate", "") == "Elite" else "0", str(enemy_id))
	gameplay_event.emit({"type": "enemy_killed", "id": enemy_id})

func record_boss_rating(enemy_id: int, rating: int) -> void:
	set_record("boss-rating:" + str(enemy_id), maxi(stat("boss-rating:" + str(enemy_id)), rating))

func complete_node(occurrence_key, node_id: int, region: int, region_complete: bool, node_type: String = "0") -> Dictionary:
	var run = profile.data.run
	var key = str(occurrence_key)
	if not run.active or key.is_empty() or run.completed_occurrences.has(key): return _fail("房间不可结算或已结算")
	run.completed_occurrences.append(key)
	run.completed_nodes.append(node_id)
	run.current_node = node_id
	run.region = region
	record("nodes")
	record_purification_event("CompleteNode", node_type, 1, "", false)
	if region_complete:
		record("region:" + str(region))
		set_record("max-region", maxi(region, stat("max-region")))
		set_record("character-region:" + str(int(run.character_id)), maxi(region, stat("character-region:" + str(int(run.character_id)))))
		for loot in run.inventory:
			if int(run.inventory[loot]) > 0: set_record("loot-region:" + str(loot), maxi(region, stat("loot-region:" + str(loot))))
		record_purification_event("CompleteRegion", str(region), 1, "", false)
		clear_invalid_meals("CompleteRegion")
		effects.dispatch("CompleteRegion", str(region))
	effects.dispatch("CompleteNode", node_type)
	return _done("房间已结算", node_id)

func end_run(victory: bool) -> Dictionary:
	if _camp_transaction_active: return _fail("请等待当前操作完成")
	if not profile.data.run.active: return _fail("没有进行中的冒险")
	if victory:
		var level = int(profile.data.run.difficulty)
		record("difficulty:win:" + str(level))
		if level == 10:
			var character = int(profile.data.run.character_id)
			var cleared = chaos_cleared_level(character)
			var completed = int(profile.data.run.counters.get("chaos_level", 1))
			if completed == mini(chaos_max_level(), cleared + 1) and cleared < chaos_max_level(): set_record("chaos:clear:" + str(character), cleared + 1)
	if not victory and int(profile.data.run.difficulty) > 0: record("hard:losses")
	history.capture(victory, str(profile.data.run.get("outcome", {}).get("reason", "battle")))
	profile.data.run.active = false
	record("wins" if victory else "losses")
	clear_invalid_meals("CompleteRun")
	return _done("冒险胜利" if victory else "返回营地")

func settlement_experience(total_depth: int, region: int, kills: int) -> Dictionary:
	var experience = maxi(0, total_depth - 1) * int(catalog.config.get("CharaExpGet_PerDepth", 50))
	experience += maxi(0, region - 1) * int(catalog.config.get("CharaExpGet_PerLevel", 50))
	experience += maxi(0, kills) * int(catalog.config.get("CharaExpGet_PerKillMonster", 0))
	var effective = experience * experience_multiplier()
	var divisor = maxi(1, int(catalog.config.get("CharaUpgradeItemProvideExp", 100)))
	return {"experience": experience, "effective_experience": effective, "vouchers": 0 if effective < 50 else ceili(float(effective) / divisor)}

func claim_settlement_experience() -> Dictionary:
	return _camp_transaction(_claim_settlement_experience)

func _claim_settlement_experience() -> Dictionary:
	var outcome: Dictionary = profile.data.run.get("outcome", {})
	if outcome.is_empty() or profile.data.run.active or outcome.get("experience_claimed", false): return _fail("结算奖励已领取或尚未结算")
	outcome["experience_claimed"] = true
	var count = maxi(0, int(outcome.get("vouchers", 0)))
	grant_material(501, count)
	return _done("获得冒险凭证 × %d" % count, 501)

func clear_completed_run() -> bool:
	if profile.data.run.active or not profile.data.run.get("outcome", {}).is_empty(): return false
	profile.data.run = Profile.new_run()
	profile.data.materials["102"] = 0
	return true

func next_random(maximum: int) -> int:
	if maximum <= 0: return 0
	profile.data.run.random_step = int(profile.data.run.random_step) + 1
	var n = (int(profile.data.run.seed) + int(profile.data.run.random_step) * 747796405) & 0xffffffff
	n = ((n ^ (n >> 16)) * 2246822519) & 0xffffffff
	n = ((n ^ (n >> 13)) * 3266489917) & 0xffffffff
	return int((n ^ (n >> 16)) % maximum)

func persistent_ability_ids(selected_character_id: int = 0) -> Array:
	var d = profile.data
	var character = _selected_character(selected_character_id)
	var result = []
	for id in d.active_awakenings:
		var row = catalog.find("CharaTalentAwakeTreeData", id)
		if int(row.get("chara_id", 0)) == character: result.append(int(row.ability_item_id))
	result.append_array(relationship_tokens.ability_ids(character))
	return result

func _selected_character(selected_character_id: int = 0) -> int:
	if profile.data.run.active: return int(profile.data.run.character_id)
	return selected_character_id if selected_character_id > 0 else int(profile.data.selected_character)

func selected_weapon_buffs(selected_character_id: int = 0) -> Array:
	var weapon_id = equipped_weapon(selected_character_id)
	var level = stat("weapon:" + str(weapon_id))
	if level < 1: return []
	return Catalog.ids(_part(catalog.find("WeaponData", weapon_id).get("buff_list", ""), level - 1))

func ability_sources(selected_character_id: int = 0) -> Dictionary:
	var d = profile.data
	var sources = {}
	if d.run.active:
		for key in d.run.inventory:
			if is_shop_sealed(int(key)): continue
			var row = catalog.find("LootData", int(key))
			if int(d.run.inventory[key]) > 0: _add(sources, int(row.get("ability_item_id", 0)), int(d.run.inventory[key]))
	for key in d.talents:
		var row = catalog.find("TalentTreeData", int(key))
		var ids = Catalog.ids(row.get("level_data_id_list", ""))
		var level = int(d.talents[key])
		if level > 0 and level <= ids.size():
			_add(sources, int(catalog.find("TalentTreeLevelData", ids[level - 1]).get("ability_item_id", 0)), 1)
	for key in purchased_meals():
		var ids = Catalog.ids(catalog.find("CatMealData", int(key)).get("AbilityItemId", ""))
		var level = rank(purchased_meals(), key)
		if level > 0 and level <= ids.size(): _add(sources, ids[level - 1], 1)
	for id in persistent_ability_ids(selected_character_id): _add(sources, id, 1)
	return sources

func attributes(selected_character_id: int = 0) -> Dictionary:
	var result = {}
	var d = profile.data
	var character_id = _selected_character(selected_character_id)
	var character = catalog.find("CharData", character_id)
	var growth = maxi(0, rank(d.character_levels, character_id) - 1) * float(catalog.config.get("CharaPerLevelAddStatusPercent", 0)) / 1000.0
	# Combat keeps the level-one database stats; external values are increments.
	for pair in [["BaseAtk", "atk"], ["BaseDef", "def"], ["BaseHp", "hp"]]:
		result[pair[0]] = float(character.get(pair[1], 0)) * growth
	var fashion = preload("res://scripts/domain/character_fashion.gd").new(self)
	var fashion_attributes: Dictionary = fashion.attributes(character_id)
	for attribute in fashion_attributes: result[attribute] = result.get(attribute, 0) + fashion_attributes[attribute]
	for buff in fashion.equipped_buffs(character_id): effects.buff_attributes(buff, 1, result)
	for buff in selected_weapon_buffs(selected_character_id): effects.buff_attributes(buff, 1, result)
	var sources = ability_sources(selected_character_id)
	for id in sources:
		effects.ability_attributes(int(id), int(sources[id]), result)
	if d.run.active:
		result["SealedLootCount"] = int(d.run.counters.get("SealedLootCount", 0))
		var difficulty_modifiers = difficulty_attributes()
		for attribute in difficulty_modifiers: result[attribute] = result.get(attribute, 0) + difficulty_modifiers[attribute]
		for reward in d.run.get("region_rewards", []):
			var attribute_name = str(reward.get("AttributeType", ""))
			if not attribute_name.is_empty(): result[attribute_name] = result.get(attribute_name, 0) + int(reward.get("Value", 0))
		for key in d.run.talents:
			var row = catalog.find("CharTalentData", int(key))
			var ids = Catalog.ids(row.get("level_data_id_list", ""))
			var level = int(d.run.talents[key])
			if level > 0 and level <= ids.size():
				for buff in Catalog.ids(catalog.find("CharTalentLevelData", ids[level - 1]).get("buff_list", "")): effects.buff_attributes(buff, 1, result)
		for key in d.run.counters:
			if str(key).begins_with("rogue-event-buff:"): effects.buff_attributes(int(str(key).trim_prefix("rogue-event-buff:")), int(d.run.counters[key]), result)
		var room_attributes: Dictionary = preload("res://scripts/domain/room_choices.gd").new(self).extra_attributes()
		for key in room_attributes: result[key] = result.get(key, 0) + room_attributes[key]
	for id in d.equipped_partners:
		var row = catalog.find("MonsterPartnerData", int(id))
		var milestones = str(row.get("add_attribute_array", "")).split(",")
		for i in mini(rank(d.partners, id) - 1, milestones.size()):
			for key in costs(milestones[i]):
				var attr = {"1": "BaseAtk", "2": "BaseDef", "3": "BaseHp", "4": "CriticalRate", "5": "CriticalMulti"}.get(key, "")
				if not attr.is_empty(): result[attr] = result.get(attr, 0) + int(costs(milestones[i])[key])
	return result

func progression_buff_bindings(selected_character_id: int = 0) -> Dictionary:
	var roots = {}
	var counted = []
	_gather_buffs(selected_weapon_buffs(selected_character_id), 1, roots, counted)
	_gather_buffs(preload("res://scripts/domain/character_fashion.gd").new(self).equipped_buffs(_selected_character(selected_character_id)), 1, roots, counted)
	var sources = ability_sources(selected_character_id)
	for ability_id in sources: _gather_ability_buffs(int(ability_id), int(sources[ability_id]), roots, counted)
	if profile.data.run.active:
		for key in profile.data.run.talents:
			var row = catalog.find("CharTalentData", int(key))
			var levels = Catalog.ids(row.get("level_data_id_list", ""))
			var level = int(profile.data.run.talents[key])
			if level > 0 and level <= levels.size(): _gather_buffs(catalog.find("CharTalentLevelData", levels[level - 1]).get("buff_list", ""), 1, roots, counted)
		for key in profile.data.run.counters:
			if str(key).begins_with("rogue-event-buff:"):
				_gather_buffs(str(key).trim_prefix("rogue-event-buff:"), int(profile.data.run.counters[key]), roots, counted)
		for buff in persistent_node_entry_buffs(): _gather_buffs(buff.key, int(buff.value), roots, counted)
		_gather_buffs(preload("res://scripts/domain/room_choices.gd").new(self).extra_buff_ids(), 1, roots, counted)
	var applications = []
	for id in roots: applications.append({"id": str(id), "layers": int(roots[id])})
	return {"roots": applications, "externally_counted_numeric_ids": counted}

func _gather_ability_buffs(id: int, count: int, roots: Dictionary, counted: Array, path: Array = []) -> void:
	if path.has(id): return
	var row = catalog.find("AbilityItems", id)
	if row.is_empty(): return
	var next_path = path.duplicate()
	next_path.append(id)
	if str(row.get("TriggerEventType", "")) in ["", "None"]:
		_gather_buffs(row.get("ModifyBuff", ""), count, roots, counted)
		for component in row.get("CombineDataList", []):
			var data = component.get("Data", {})
			if component.get("CombineDataType", "") == "NormalModifyBuff" and component.get("ConditionList", []).is_empty() and data.get("TargetType", "") == "Player" and int(data.get("ModifyBuffChance", 0)) >= 1000: _gather_buffs(data.get("ModifyBuff", ""), count, roots, counted)
	for child in Catalog.ids(row.get("ExtraAbilityItemIDList", "")): _gather_ability_buffs(child, count, roots, counted, next_path)

func _gather_buffs(value, count: int, roots: Dictionary, counted: Array) -> void:
	for id in Catalog.ids(value):
		var key = str(id)
		roots[key] = int(roots.get(key, 0)) + count
		if catalog.find("Buffs", id).get("BuffType", "") == "EBT_NumericalBuff" and not counted.has(key): counted.append(key)

func upgrade_awakening_level(character_id: int) -> Dictionary:
	if rank(profile.data.character_levels, character_id) == 0 or profile.data.run.active: return _fail("请在营地升级已拥有角色")
	return _ok("领取混沌首通奖励后自动提升觉醒等级", character_id)

func awakening_progress() -> Dictionary:
	var total = 0
	for key in profile.data.stats:
		if not str(key).begins_with("chaos:claimed:"): continue
		for layer in range(1, mini(chaos_max_level(), stat(key)) + 1):
			total += int(costs(catalog.config.get("ChaosLevelRewardDict", {}).get(str(layer), "")).get("504", 0))
	if stat("purchase:2019:never") > 0 or stat("entitlement:awake_pack") > 0: total += 1000
	var thresholds = Catalog.ids(catalog.config.get("AwakeTreeGlobalData", {}).get("level_to_material_count_str", ""))
	var remaining = total
	var level = 0
	for threshold in thresholds:
		if threshold <= 0 or remaining < threshold: break
		remaining -= threshold
		level += 1
	var points = level + (5 if stat("entitlement:blessing_plus") > 0 else 0) + (5 if stat("entitlement:blessing_ultra") > 0 else 0)
	return {"total": total, "level": level, "points": points, "progress": remaining, "required": int(thresholds[level]) if level < thresholds.size() else 0, "maximum": thresholds.size()}

func unlock_awakening(id: int) -> Dictionary:
	return _camp_transaction(_unlock_awakening.bind(id))

func _unlock_awakening(id: int) -> Dictionary:
	var reason = _camp_action_reason("awakening")
	if not reason.is_empty(): return _fail(reason)
	var row = catalog.find("CharaTalentAwakeTreeData", id)
	if row.is_empty() or bool(row.get("is_admin_mode", false)) or not bool(row.get("is_enabled", true)) or stat("awake:unlocked:" + str(id)) > 0: return _fail("觉醒不可解锁")
	if rank(profile.data.character_levels, int(row.chara_id)) == 0: return _fail("角色尚未解锁")
	if profile.data.run.active or int(awakening_progress().level) < int(row.unlock_awake_tree_level): return _fail("觉醒等级不足")
	if not spend(costs(row.unlock_need_material_list)): return _fail("觉醒材料不足")
	set_record("awake:unlocked:" + str(id), 1)
	return _done(Catalog.row_name(row), id)

func awakening_status(id: int) -> Dictionary:
	var row = catalog.find("CharaTalentAwakeTreeData", id)
	var reason = _camp_action_reason("awakening")
	var unlocked = stat("awake:unlocked:" + str(id)) > 0
	var active = profile.data.active_awakenings.has(id)
	var price = costs(row.get("unlock_need_material_list", ""))
	var used = 0
	for active_id in profile.data.active_awakenings:
		var node = catalog.find("CharaTalentAwakeTreeData", int(active_id))
		if int(node.get("chara_id", 0)) == int(row.get("chara_id", -1)): used += int(node.get("active_need_awake_point", 0))
	var progress = awakening_progress()
	if row.is_empty() or bool(row.get("is_admin_mode", false)) or not bool(row.get("is_enabled", true)): reason = "觉醒不可用"
	elif rank(profile.data.character_levels, int(row.get("chara_id", 0))) < 1: reason = "角色尚未解锁"
	var activation_reason = reason
	if reason.is_empty() and not unlocked:
		if int(progress.level) < int(row.get("unlock_awake_tree_level", 0)): reason = "觉醒等级不足"
		elif not can_afford(price): reason = "觉醒材料不足"
	if activation_reason.is_empty():
		if not unlocked: activation_reason = "觉醒尚未解锁"
		elif not active and used + int(row.get("active_need_awake_point", 0)) > int(progress.points): activation_reason = "潜能点不足"
	return {"id": id, "unlocked": unlocked, "active": active, "price": price, "used_points": used, "points": int(progress.points), "cost_points": int(row.get("active_need_awake_point", 0)), "can_unlock": not unlocked and reason.is_empty(), "can_toggle": activation_reason.is_empty(), "reason": reason, "activation_reason": activation_reason}

func toggle_awakening(id: int) -> Dictionary:
	return _camp_transaction(_toggle_awakening.bind(id))

func _toggle_awakening(id: int) -> Dictionary:
	var row = catalog.find("CharaTalentAwakeTreeData", id)
	var status = awakening_status(id)
	if not status.can_toggle: return _fail(status.activation_reason)
	if profile.data.active_awakenings.has(id):
		profile.data.active_awakenings.erase(id)
		return _done("已取消激活", id)
	var used = 0
	for active_id in profile.data.active_awakenings:
		var active = catalog.find("CharaTalentAwakeTreeData", int(active_id))
		if int(active.get("chara_id", 0)) == int(row.chara_id): used += int(active.active_need_awake_point)
	if used + int(row.active_need_awake_point) > int(awakening_progress().points): return _fail("觉醒点不足")
	profile.data.active_awakenings.append(id)
	return _done("觉醒已激活", id)

func npc_gift_status(npc_id: int) -> Dictionary:
	return social.gift_status(npc_id)

func give_npc_gift(npc_id: int) -> Dictionary:
	return _camp_transaction(_give_npc_gift.bind(npc_id))

func _give_npc_gift(npc_id: int) -> Dictionary:
	if _depth == 0: return _fail("请先完成关系对话")
	var status = npc_gift_status(npc_id)
	if not status.success: return status
	if not spend({"106": 1}): return _fail("需要金苹果")
	var level = int(status.level)
	var token_levels: Dictionary = {}
	for token_id in relationship_tokens.ids(): token_levels[token_id] = stat("token:" + str(token_id))
	set_record("relationship:" + str(npc_id), level + 1)
	set_record("talk:" + str(status.talk_id), 1)
	refresh_tokens(false)
	var rewards: Dictionary = {}
	for token_id in token_levels:
		if stat("token:" + str(token_id)) > int(token_levels[token_id]): rewards[str(token_id)] = 1
	var result = _done("好感等级 " + str(level + 1), npc_id)
	result["rewards"] = rewards
	return result

func refresh_tokens(notify: bool = true) -> Dictionary:
	var count: int = relationship_tokens.refresh()
	return _done("信物解锁 " + str(count)) if notify else _ok()

func upgrade_token(material_id: int) -> Dictionary:
	return relationship_tokens.upgrade(material_id)

func token_status(material_id: int, character_id := 0) -> Dictionary:
	return relationship_tokens.status(material_id, character_id)

func token_slots() -> int:
	return 1 + stat("token:slots") + int(catalog.config.get("BlessingMode_RelationshipTokenSlotAddCount", 0) if stat("blessing") == 1 else catalog.config.get("BlessingUltra_RelationshipTokenSlotAddCount", 0) if stat("blessing") == 2 else 0)

func unlock_token_slot() -> Dictionary:
	return _camp_transaction(_unlock_token_slot)

func _unlock_token_slot() -> Dictionary:
	var reason = _camp_action_reason("tokens")
	if not reason.is_empty(): return _fail(reason)
	var prices = catalog.config.get("UnlockRelationshipTokenSlotNeedGold", [])
	var count = stat("token:slots")
	if profile.data.run.active or count >= prices.size(): return _fail("信物槽已满")
	if not spend({"101": int(prices[count])}): return _fail("金币不足")
	record("token:slots")
	return _done("信物槽已解锁")

func equip_token(id: int) -> Dictionary:
	return relationship_tokens.equip(id)

func set_blessing_mode(mode: int) -> Dictionary:
	return _camp_transaction(_set_blessing_mode.bind(mode))

func _set_blessing_mode(mode: int) -> Dictionary:
	if profile.data.run.active or mode < 0 or mode > 2: return _fail("请在营地选择祝福")
	var progress: Array = []
	for order in profile.data.work: progress.append(_work_queue_progress(order))
	set_record("blessing", mode)
	for index in profile.data.work.size():
		var order: Dictionary = profile.data.work[index]
		if not order.has("economy_version"): order["prepaid_quantity"] = 1
		_store_work_progress(order, int(progress[index].seconds), {"quantity": _work_queue_max(), "duration": _work_duration(catalog.find("MonsterWorkData", int(order.work_id)))})
	relationship_tokens.normalize()
	return _done("已选择祝福 " + str(mode))

func experience_multiplier() -> int:
	return maxi(1, int(catalog.config.get("BlessingExpEfficiencyMultiplier", 1))) if stat("blessing") > 0 else 1

func unlock_amplifier_slot(token_id: int, slot_index: int) -> Dictionary:
	return relationship_tokens.unlock_socket(token_id, slot_index)

func equip_amplifier(character_id: int, token_id: int, slot_index: int, amplifier_id: int) -> Dictionary:
	return relationship_tokens.equip_amplifier(character_id, token_id, slot_index, amplifier_id)

func unequip_amplifier(token_id: int, slot_index: int) -> Dictionary:
	return relationship_tokens.unequip(token_id, slot_index)

func unequip_all_amplifiers(token_id := 0) -> Dictionary:
	return relationship_tokens.unequip_all(token_id)

func amplifier_compose_quote(request: Dictionary = {}) -> Dictionary:
	return relationship_tokens.compose_quote(request)

func compose_amplifier(id: int) -> Dictionary:
	return relationship_tokens.compose({str(id): 1})

func compose_amplifier_batch(request: Dictionary) -> Dictionary:
	return relationship_tokens.compose(request)

func reroll_amplifier() -> Dictionary:
	return relationship_tokens.reroll()

func save_token_preset(index: int) -> Dictionary:
	return relationship_tokens.save_preset(index)

func load_token_preset(index: int) -> Dictionary:
	return relationship_tokens.load_preset(index)

func delete_token_preset(index: int) -> Dictionary:
	return relationship_tokens.delete_preset(index)

func receive_extra_challenges() -> Dictionary:
	return extra_challenges.receive()

func remove_extra_challenge(id: int) -> Dictionary:
	return extra_challenges.remove(id)

func claim_extra_challenge(id: int) -> Dictionary:
	return extra_challenges.claim(id)

func follower_replacements(row: Dictionary) -> Array:
	var result = []
	if row.get("loot_type", "") not in ["随从", "高级随从"]: return result
	var gate = catalog.find("UnlockData", int(row.unlock_data_id))
	var ability = catalog.find("AbilityItems", int(row.ability_item_id))
	var rejects = Catalog.ids(ability.get("RejectIdArray", ""))
	if row.loot_type == "随从":
		for previous in rejects:
			var old = catalog.find("LootData", previous)
			var old_ability = catalog.find("AbilityItems", int(old.get("ability_item_id", 0)))
			if old.get("loot_type", "") == "随从" and not Catalog.ids(old_ability.get("RejectIdArray", "")).has(int(row.id)): result.append(previous)
	elif int(gate.get("unlock_condition_type", 0)) == 9001:
		for i in range(1, 4):
			var requirement = catalog.find("UnlockData", int(gate.get("unlock_param" + str(i), 0)))
			if int(requirement.get("unlock_condition_type", 0)) == 1000 and rejects.has(int(requirement.unlock_param1)): result.append(int(requirement.unlock_param1))
		if result.size() != 2: result.clear()
	return result

func can_add_loot(id: int) -> bool:
	if is_shop_sealed(id): return false
	var row = catalog.find("LootData", id)
	var ability = catalog.find("AbilityItems", int(row.get("ability_item_id", 0)))
	if row.is_empty() or ability.is_empty() or row.get("is_admin_only", false) or not is_unlocked(int(row.unlock_data_id)): return false
	if rank(profile.data.run.inventory, id) >= maxi(1, int(ability.get("MaxHaveCount", 1))): return false
	var replacements = follower_replacements(row)
	for other in Catalog.ids(ability.get("RejectIdArray", "")):
		if rank(profile.data.run.inventory, other) > 0 and not replacements.has(other): return false
	if row.get("loot_type", "") in ["随从", "高级随从"]:
		for held in profile.data.run.inventory:
			if int(profile.data.run.inventory[held]) <= 0 or replacements.has(int(held)): continue
			var held_row = catalog.find("LootData", int(held))
			var held_ability = catalog.find("AbilityItems", int(held_row.get("ability_item_id", 0)))
			if Catalog.ids(held_ability.get("RejectIdArray", "")).has(id): return false
	return true

func add_loot(id: int, notify: bool = true) -> Dictionary:
	if not profile.data.run.active or not can_add_loot(id): return _fail("物品未解锁、冲突或已达上限")
	var row = catalog.find("LootData", id)
	var ability = catalog.find("AbilityItems", int(row.ability_item_id))
	for previous in follower_replacements(row): profile.data.run.inventory.erase(str(previous))
	if not profile.data.discovered_loot.has(id): profile.data.discovered_loot.append(id)
	if not (str(ability.get("TriggerEventType", "")) in ["Init", "Get"] and ability.get("IsTriggerFinishCost", false)):
		if rank(profile.data.run.inventory, id) == 0: _reset_purification(id)
		_add(profile.data.run.inventory, id, 1)
	effects.acquire(int(row.ability_item_id))
	effects.dispatch("GetAbilityItemLoot", str(id))
	return _done(loot_name(id), id) if notify else _ok(loot_name(id), id)

func loot_name(id: int) -> String:
	var row = catalog.find("LootData", id)
	return Catalog.row_name(catalog.find("AbilityItems", int(row.get("ability_item_id", id))))

func loot_description(id: int) -> String:
	var row = catalog.find("LootData", id)
	return Catalog.description(catalog.find("AbilityItems", int(row.get("ability_item_id", id))))

func _pool_candidates(pool_id: int, green_rate: float = 0, rarity_weights: Dictionary = {}) -> Array:
	var result = []
	var base_weights: Dictionary = {}
	var pool = catalog.find("ItemPoolData", pool_id)
	for sub_id in Catalog.ids(pool.get("sub_data_id_list", "")):
		var sub = catalog.find("ItemPoolSubData", sub_id)
		var gates = Catalog.ids(sub.get("unlock_data_id_list_str", ""))
		var available = gates.is_empty() or gates.any(func(x): return is_unlocked(x)) if sub.get("unlock_judge_mode", "") == "Or" else gates.all(func(x): return is_unlocked(x))
		if not available: continue
		var ids = Catalog.ids(sub.item_id_list_str)
		var weights = Catalog.ids(sub.weight_list_str)
		for i in ids.size():
			if not can_add_loot(ids[i]): continue
			base_weights[ids[i]] = float(base_weights.get(ids[i], 0)) + float(weights[mini(i, weights.size() - 1)] if not weights.is_empty() else 1)
	var attrs = attributes()
	for id in base_weights:
		var loot = catalog.find("LootData", id)
		var rare = int(catalog.find("AbilityItems", int(loot.get("ability_item_id", id))).get("Rare", 0))
		var modifier := 0
		if rare >= 1 and rare <= 5:
			modifier += int(attrs.get("Star%dItemExtraWeightAddPercent" % rare, 0))
			if loot.get("loot_type", "") in ["攻击宝石", "防御宝石", "生命宝石"]:
				modifier += int(attrs.get("GemExtraWeightRare%dAddPercent" % rare, 0))
		var weight := (float(base_weights[id]) + float(rarity_weights.get(rare, 0))) * (1.0 + modifier / 1000.0)
		if loot.get("loot_type", "") == "生命宝石" and 1 + green_rate / 1000.0 > 0: weight *= 1 + green_rate / 1000.0
		result.append({"id": id, "weight": maxf(0, weight)})
	return result

func roll_pool(pool_id: int, count: int, green_rate: float = 0, excluded: Array = [], rarity_weights: Dictionary = {}) -> Array:
	var result = []
	if not profile.data.run.active or count < 1: return result
	var candidates = _pool_candidates(pool_id, green_rate, rarity_weights).filter(func(entry): return not excluded.has(int(entry.id)))
	while result.size() < mini(20, count) and not candidates.is_empty():
		var total = candidates.reduce(func(value, entry): return value + float(entry.weight), 0.0)
		if total <= 0: break
		var rolled: float = total * next_random(16777217) / 16777216.0
		var cumulative := 0.0
		for entry in candidates:
			if float(entry.weight) <= 0: continue
			cumulative += float(entry.weight)
			if cumulative >= rolled:
				result.append(int(entry.id))
				candidates = candidates.filter(func(x): return int(x.id) != int(entry.id))
				break
	return result

func ensure_map_node_increments(campaign) -> void:
	preload("res://scripts/domain/room_appearance.gd").new(self).ensure_map(campaign)

func room_node_increments(key: String, room: Dictionary) -> Dictionary:
	return preload("res://scripts/domain/room_appearance.gd").new(self).node_increments(key, room)

func room_environment_appearance(key: String, room: Dictionary, items: Array) -> Dictionary:
	return preload("res://scripts/domain/room_appearance.gd").new(self).environment_decisions(key, room, items)

func enemy_enhancements(enemy_id: int) -> Array:
	if not profile.data.run.active: return []
	return preload("res://scripts/domain/enemy_enhancements.gd").new(self).for_enemy(enemy_id)

func enemy_creation_buffs(enemy_id: int) -> Array:
	if not profile.data.run.active: return []
	return preload("res://scripts/domain/enemy_enhancements.gd").new(self).creation_buffs(enemy_id)

func monster_drops(enemy_id: int, mohua: bool = false) -> Array:
	if not profile.data.run.active: return []
	var row = catalog.find("EnemyData", enemy_id)
	return preload("res://scripts/domain/loot_rewards.gd").new(self).monster(str(row.get("enemy_rate", "")), int(profile.data.run.counters.get("run:total_depth", 0)), attributes(), mohua)

func treasure_drops(quality: String, treasure_id: int, first_node: bool) -> Array:
	if not profile.data.run.active: return []
	return preload("res://scripts/domain/loot_rewards.gd").new(self).treasure(quality, treasure_id, first_node, int(profile.data.run.region) == 1, int(profile.data.run.counters.get("run:total_depth", 0)), attributes())

func reward_slime_drops(enemy_id: int, event: String) -> Array:
	if not profile.data.run.active: return []
	return preload("res://scripts/domain/loot_rewards.gd").new(self).reward_slime(enemy_id, event, attributes())

func room_treasure_quality(key: String, room: Dictionary, outcome: Dictionary = {}) -> String:
	if not profile.data.run.active: return ""
	var storage := "room_treasure_quality:" + key
	var counters: Dictionary = profile.data.run.counters
	if counters.has(storage) and (outcome.is_empty() or str(room.get("FightType", "")) not in ["TimeLimit", "DodgeBattle", "ProtectTarget", "Endless"]): return str(counters[storage])
	var quality: String = preload("res://scripts/domain/loot_rewards.gd").new(self).completion_quality(room, attributes(), outcome)
	counters[storage] = quality
	return quality

func start_chest_trial(campaign, chest_index: int) -> Dictionary:
	if not profile.data.run.active or profile.data.run.health <= 0 or int(campaign.state.get("seed", -1)) != int(profile.data.run.seed): return _fail("试炼不可开始")
	return campaign.start_trial(chest_index, profile.data.run.inventory)

func claim_chest_trial_reward(campaign) -> Dictionary:
	var run: Dictionary = profile.data.run
	var trial: Dictionary = campaign.trial_status()
	if not run.active or run.health <= 0 or int(campaign.state.get("seed", -1)) != int(run.seed) or trial.is_empty() or trial.phase != "complete" or trial.reward_claimed: return _fail("试炼尚未完成或奖励已领取")
	var key = "trial_reward:%d:%d:%d" % [int(run.seed), int(campaign.state.layer_index), int(campaign.state.current_node_id)]
	if not campaign.claim_trial_reward().success: return _fail("试炼奖励不可领取")
	var drops: Array = []
	if not run.counters.get(key, false):
		run.counters[key] = true
		drops = treasure_drops(str(trial.quality), 1, false)
	var result = _ok("试炼完成", int(campaign.state.current_node_id))
	result["drops"] = drops
	result["quality"] = str(trial.quality)
	return result

func queue_loot_reward(rarity: String, count: int) -> void:
	var field = {"Curse": "AbilityItemLootPoolId_Curse", "OldDay": "AbilityItemLootPoolId_OldDay", "Reward": "AbilityItemLootPoolId_Reward", "Sprites": "AbilityItemLootPoolId_Sprites"}.get(rarity, "DefaultAbilityItemLootPoolId")
	var weights: Dictionary = {"Low": {1: 50, 2: 50, 3: 50, 4: 0, 5: -1000}, "Middle": {1: -1000, 2: 50, 3: 50, 4: 50, 5: 0}, "High": {1: -1000, 2: -1000, 3: -5, 4: 50, 5: 200}}.get(rarity, {})
	var fallback = "AbilityItemLootGuaranteedPoolId_" + ({"Low": "LowRare", "Middle": "MiddleRare", "High": "HighRare"}.get(rarity, rarity))
	var excluded = _reward_pure_group_exclusions()
	var candidate_count = maxi(1, 3 + int(attributes().get("BlessingPlusSelectExtraCount", 0)))
	for i in mini(99, count):
		var pool = int(catalog.config.get(field, 0))
		var choices = roll_pool(pool, candidate_count, 0, excluded, weights)
		_replace_normal_reward_with_curse(choices, rarity)
		if choices.is_empty():
			pool = int(catalog.config.get(fallback, 0))
			choices = roll_pool(pool, candidate_count, 0, excluded)
		profile.data.run.rewards.append({"key": "reward-" + str(profile.data.run.random_step) + "-" + str(profile.data.run.rewards.size()), "pool_id": pool, "quality": rarity, "choices": choices, "candidate_count": candidate_count})

func _reward_pure_group_exclusions() -> Array:
	var groups = {"诅咒遗物": {}, "净化遗物": {}}
	for key in profile.data.run.inventory:
		if int(profile.data.run.inventory[key]) <= 0: continue
		var held = catalog.find("LootData", int(key))
		var type = str(held.get("loot_type", ""))
		var group = int(held.get("pure_group_id", 0))
		if groups.has(type) and group > 0: groups[type][group] = true
	var excluded: Array = []
	if groups["诅咒遗物"].is_empty() and groups["净化遗物"].is_empty(): return excluded
	for loot in catalog.rows("LootData"):
		var type = str(loot.get("loot_type", ""))
		var opposite = {"诅咒遗物": "净化遗物", "净化遗物": "诅咒遗物"}.get(type, "")
		if not opposite.is_empty() and groups[opposite].has(int(loot.get("pure_group_id", 0))): excluded.append(Catalog.row_id(loot))
	return excluded

func _replace_normal_reward_with_curse(choices: Array, rarity: String) -> void:
	if rarity not in ["Low", "Middle", "High"] or choices.is_empty(): return
	var chance = int(attributes().get("CurseRelicInNormalPool", 0))
	if chance <= 0 or next_random(1000) + 1 > chance: return
	var curse = roll_pool(int(catalog.config.get("AbilityItemLootPoolId_Curse", 0)), 1, 0, _reward_pure_group_exclusions())
	if not curse.is_empty(): choices[next_random(choices.size())] = curse[0]

func choose_loot_reward(key: String, id: int) -> Dictionary:
	for reward in profile.data.run.rewards:
		if reward.key != key: continue
		if not reward.choices.has(id): return _fail("不在奖励候选中")
		var result = add_loot(id, false)
		if not result.success: return result
		profile.data.run.rewards.erase(reward)
		return _done(result.message, id)
	return _fail("奖励已领取或不存在")

func is_loot_lock_unlocked() -> bool:
	return profile.data.talents.has("221") or profile.data.talents.has(221)

func toggle_loot_reward_lock(key: String, id: int) -> Dictionary:
	if not is_loot_lock_unlocked(): return _fail("尚未解锁遗物锁定")
	for reward in profile.data.run.rewards:
		if str(reward.key) != key: continue
		if not reward.choices.has(id): return _fail("不在奖励候选中")
		var locked: Array = reward.get("locked_ids", []).duplicate()
		if locked.has(id): locked.erase(id)
		else: locked.append(id)
		reward["locked_ids"] = locked
		return _done("物品已锁定" if locked.has(id) else "物品已解锁", id)
	return _fail("奖励不存在")

func refresh_loot_reward(key: String) -> Dictionary:
	if int(profile.data.run.counters.get("SelectRefreshTime", 0)) <= 0: return _fail("重选次数不足")
	for reward in profile.data.run.rewards:
		if reward.key != key: continue
		var candidate_count = int(reward.get("candidate_count", maxi(3, reward.choices.size())))
		var locked: Array = reward.choices.filter(func(id): return is_loot_lock_unlocked() and reward.get("locked_ids", []).has(id))
		if locked.size() >= candidate_count: return _fail("请先解锁一个候选物")
		var excluded: Array = _reward_pure_group_exclusions()
		excluded.append_array(locked)
		var fresh = roll_pool(int(reward.pool_id), candidate_count - locked.size(), 0, excluded)
		if fresh.is_empty(): return _fail("没有可选物品")
		var choices: Array = []
		for old in reward.choices:
			if locked.has(old): choices.append(old)
			elif not fresh.is_empty(): choices.append(fresh.pop_front())
		choices.append_array(fresh)
		_add(profile.data.run.counters, "SelectRefreshTime", -1)
		reward.choices = choices
		reward["locked_ids"] = locked
		return _done("奖励已重选")
	return _fail("奖励不存在")

func claim_node_materials(key: String, _region: int, _boss: bool) -> Dictionary:
	var run = profile.data.run
	if not run.active or not run.completed_occurrences.has(key) or int(run.counters.get("harvest:" + key, 0)) > 0: return _fail("材料已领取或房间未完成")
	# World loot already pays on pickup. Room completion records delivery only.
	run.counters["harvest:" + key] = 1
	return _done("房间奖励已记录")

func create_loot_reward(pool_id: int, key: String, count: int = 3) -> Array:
	if not profile.data.run.active: return []
	for reward in profile.data.run.rewards:
		if reward.key == key: return reward.choices.duplicate()
	var choices = roll_pool(pool_id, count)
	if choices.is_empty(): return []
	profile.data.run.rewards.append({"key": key, "pool_id": pool_id, "choices": choices})
	_done()
	return choices.duplicate()

func _shop_attributes() -> Dictionary:
	var result = attributes().duplicate()
	for row in catalog.config.get("GameShopCfg", {}).get("ShopLevelData", []):
		if int(row.Level) <= maxi(1, stat("shop:level")): effects.ability_attributes(int(row.AbilityItemId), 1, result)
	return result

func _shop_rarity_weights(attrs: Dictionary) -> Dictionary:
	var quality = _shop_float(_shop_float(float(attrs.get("ShopItemQualityIncrease", 0))) / 1000.0)
	return {1: 0, 2: 0, 3: 50, 4: 40 + int(_shop_float(40 * quality)), 5: 30 + int(_shop_float(30 * quality))}

func _shop_float(value: float) -> float:
	# IL2CPP prices truncate after single-precision arithmetic.
	return PackedFloat32Array([value])[0]

func _shop_base_price(rarity: int, region: int = 0) -> int:
	var cfg = catalog.config.get("GameShopCfg", {})
	var prices = cfg.get("BaseRarePriceList", [])
	var index = clampi(rarity, 1, 5) - 1
	var base_price = float(prices[index]) if index < prices.size() else 100.0
	var difficulty_factor := 0.0
	for row in cfg.get("PriceLevelIndexAddList", []):
		if int(row.DifficultyLevel) - 1 > int(profile.data.run.difficulty): break
		difficulty_factor = float(row.PriceFactor)
	var depth = maxi(0, (region if region > 0 else int(profile.data.run.region)) - 1)
	var depth_factor = _shop_float(_shop_float(float(cfg.get("PriceLevelIndexFactor", 0)) / 1000.0) * depth)
	var factor = _shop_float(_shop_float(difficulty_factor / 1000.0) + _shop_float(1 + depth_factor))
	return int(_shop_float(_shop_float(base_price * factor) + depth * int(cfg.get("PriceLevelIndexAdd", 0))))

func _shop_price_rate(rate: float) -> float:
	rate = _shop_float(rate)
	if rate >= 0: return rate
	var discount = _shop_float(-rate / 1000.0)
	if discount > _shop_float(0.3):
		var band = [0.3, 0.3, 0.5]
		if discount > _shop_float(0.8): band = [0.8, 0.45, 0.25]
		elif discount > _shop_float(0.6): band = [0.6, 0.4, 0.25]
		elif discount > _shop_float(0.4): band = [0.4, 0.35, 0.25]
		var excess = _shop_float(discount - _shop_float(band[0]))
		discount = minf(0.5, _shop_float(_shop_float(band[1]) + _shop_float(excess * band[2])))
	return _shop_float(-discount * 1000.0)

func _shop_price(rarity: int, attrs: Dictionary, change: int = 0, region: int = 0) -> int:
	var base_price = _shop_base_price(rarity, region)
	var base_factor = _shop_float(1 + _shop_float(int(attrs.get("ShopBasePriceAddRate", 0)) / 1000.0))
	var discount_factor = _shop_float(1 + _shop_float(_shop_price_rate(float(attrs.get("ShopPriceAddRate", 0))) / 1000.0))
	var price = _shop_float(_shop_float(base_price * base_factor) * discount_factor)
	if change != 0: price = _shop_float(price * _shop_float(1 + _shop_float(change * _shop_float(0.001))))
	return maxi(maxi(1, int(base_price / 2.0)), int(price))

func _shop_supply_price(loot_type: String, attrs: Dictionary) -> int:
	var price_key = {"调查点数": "FixedCostItemPrice_SearchPoint", "生命药水": "FixedCostItemPrice_Potion", "护甲": "FixedCostItemPrice_Armor"}.get(loot_type, "")
	var base_price = int(catalog.config.get("GameShopCfg", {}).get(price_key, 100))
	var factor = _shop_float(1 + _shop_float(_shop_float(float(attrs.get("PotionPriceAddRate", 0))) / 1000.0))
	var price = _shop_float(base_price * factor)
	var floor_base = int(price) / int(factor) if int(factor) != 0 else 0
	return maxi(maxi(1, int(floor_base / 2)), int(price))

func _shop_is_supply(loot_id: int) -> bool:
	return str(catalog.find("LootData", loot_id).get("loot_type", "")) in ["调查点数", "生命药水", "护甲"]

func _reprice_shop(shop: Dictionary) -> void:
	var attrs = _shop_attributes()
	var markup = int(shop.get("buy_count", 0)) * int(attrs.get("NormalShopPriceIncreasePerBuy", 0))
	for offer in shop.offers:
		var loot = catalog.find("LootData", int(offer.loot_id))
		if _shop_is_supply(int(offer.loot_id)):
			offer["price_change"] = 0
			offer.price = _shop_supply_price(str(loot.loot_type), attrs)
		else:
			offer["price_change"] = int(offer.get("offer_change", 0)) + markup
			var rarity = int(catalog.find("AbilityItems", int(loot.get("ability_item_id", 0))).get("Rare", 1))
			offer.price = _shop_price(rarity, attrs, int(offer.price_change), int(shop.get("region", profile.data.run.region)))

func _roll_shop_offer_changes(shop: Dictionary) -> void:
	var candidates: Array[int] = []
	for i in shop.offers.size():
		var offer: Dictionary = shop.offers[i]
		offer["offer_change"] = 0
		if not offer.sold and not _shop_is_supply(int(offer.loot_id)): candidates.append(i)
	var cfg: Dictionary = catalog.config.get("GameShopCfg", {})
	var minimum = int(cfg.get("NormalShopPriceChangePercentMin", 0))
	var maximum = int(cfg.get("NormalShopPriceChangePercentMax", 0))
	if maximum <= minimum: return
	for change in [["ShopPriceIncreaseCount", 1], ["ShopPriceDecreaseCount", -1]]:
		for _i in mini(maxi(0, int(profile.data.run.counters.get(change[0], 0))), candidates.size()):
			var picked = next_random(candidates.size())
			var slot = candidates[picked]
			candidates.remove_at(picked)
			shop.offers[slot]["offer_change"] = (minimum + next_random(maximum - minimum + 1)) * int(change[1])

func _fill_shop(shop: Dictionary, reroll_changes: bool = true, replace_bought: bool = true) -> void:
	var cfg = catalog.config.get("GameShopCfg", {})
	var attrs = _shop_attributes()
	var count = int(cfg.get("DefaultShopShowCount", 3)) + int(attrs.get("ShopShowCount", 0))
	var old_offers: Array = shop.offers.duplicate(true)
	var offers: Array = []
	var supply_pools: Array = ["DefaultRecoverItemLootPoolId", "DefaultArmorItemLootPoolId", "DefaultSearchPointItemLootPoolId"] if shop.get("supplies", false) else []
	if replace_bought:
		for pool in supply_pools:
			for id in roll_pool(int(catalog.config.get(pool, 0)), 1):
				var slot = offers.size()
				offers.append({"loot_id": id, "price": 0, "sold": false, "supply": true, "offer_change": int(old_offers[slot].get("offer_change", 0)) if slot < old_offers.size() else 0})
		for id in roll_pool(int(catalog.config.get("DefaultAbilityItemLootPoolId", 0)), count, 0, [], _shop_rarity_weights(attrs)):
			var slot = offers.size()
			offers.append({"loot_id": id, "price": 0, "sold": false, "supply": false, "offer_change": int(old_offers[slot].get("offer_change", 0)) if slot < old_offers.size() else 0})
		shop.offers = offers
		if reroll_changes: _roll_shop_offer_changes(shop)
		_reprice_shop(shop)
		return
	var total = old_offers.size()
	var excluded: Array = []
	for old in old_offers: excluded.append(int(old.loot_id))
	for i in total:
		var old: Dictionary = old_offers[i] if i < old_offers.size() else {}
		if old.get("sold", false):
			offers.append(old)
			continue
		excluded.erase(int(old.get("loot_id", 0)))
		var is_supply = i < supply_pools.size()
		var pool_id = int(catalog.config.get(supply_pools[i] if is_supply else "DefaultAbilityItemLootPoolId", 0))
		var choices = roll_pool(pool_id, 1, 0, excluded, {} if is_supply else _shop_rarity_weights(attrs))
		if choices.is_empty():
			if not old.is_empty(): offers.append(old)
			continue
		var id = int(choices[0])
		excluded.append(id)
		offers.append({"loot_id": id, "price": 0, "sold": false, "supply": is_supply, "offer_change": int(old.get("offer_change", 0))})
	shop.offers = offers
	if reroll_changes: _roll_shop_offer_changes(shop)
	_reprice_shop(shop)

func get_room_shop(key: String, region: int = 0) -> Dictionary:
	if not profile.data.run.active: return {}
	if region > 0: profile.data.run.region = region
	for shop in profile.data.run.shops:
		if shop.key == key:
			_reprice_shop(shop)
			return shop
	var shop = {"key": key, "refreshes": 0, "paid_refreshes": 0, "buy_count": 0, "offers": [], "supplies": true, "region": int(profile.data.run.region)}
	profile.data.run.counters["ShopPriceIncreaseCount"] = 0
	profile.data.run.counters["ShopPriceDecreaseCount"] = 0
	effects.dispatch("EnterNewNormalShop", "0")
	_fill_shop(shop)
	profile.data.run.shops.append(shop)
	_done()
	return shop

func buy_room_offer(key: String, loot_id: int) -> Dictionary:
	return _camp_transaction(_buy_room_offer.bind(key, loot_id))

func _buy_room_offer(key: String, loot_id: int) -> Dictionary:
	if not profile.data.run.active: return _fail("没有进行中的冒险")
	for shop in profile.data.run.shops:
		if shop.key != key: continue
		_reprice_shop(shop)
		for offer in shop.offers:
			if int(offer.loot_id) != loot_id: continue
			if offer.sold or not can_add_loot(loot_id): return _fail("商品已售罄或不兼容")
			var free = int(profile.data.run.counters.get("FreePurchaseAttempts", 0)) > 0
			if not free and not spend({"102": int(offer.price)}): return _fail("魔力不足")
			if free: _add(profile.data.run.counters, "FreePurchaseAttempts", -1)
			elif not _shop_is_supply(loot_id): shop["buy_count"] = int(shop.get("buy_count", 0)) + 1
			offer.sold = true
			offer["offer_change"] = 0
			var result = add_loot(loot_id, false)
			var rarity = int(catalog.find("AbilityItems", int(catalog.find("LootData", loot_id).get("ability_item_id", 0))).get("Rare", 0))
			record_purification_event("BuyNormalShopItem", str(rarity), 1, "", false)
			effects.dispatch("BuyNormalShopItem", str(rarity))
			_reprice_shop(shop)
			return _done(result.message, loot_id)
	return _fail("商品不存在")

func refresh_room_shop(key: String) -> Dictionary:
	return _camp_transaction(_refresh_room_shop.bind(key))

func _refresh_room_shop(key: String) -> Dictionary:
	for shop in profile.data.run.shops:
		if shop.key != key: continue
		var status = room_shop_status(key)
		if not profile.data.run.active or not status.can_refresh: return _fail(str(status.refresh_reason))
		if int(status.refresh_cost) > 0:
			if not spend({"102": int(status.refresh_cost)}): return _fail("魔力不足")
			shop["paid_refreshes"] = int(shop.get("paid_refreshes", 0)) + 1
		shop.refreshes = int(shop.refreshes) + 1
		_fill_shop(shop, false, float(_shop_attributes().get("ShopRefreshReplaceBoughtItems", 0)) >= 1)
		return _done("商店已刷新")
	return _fail("商店不存在")

func room_shop_status(key: String) -> Dictionary:
	var cfg: Dictionary = catalog.config.get("GameShopCfg", {})
	var level = maxi(1, stat("shop:level"))
	var next: Dictionary = {}
	var levels: Array = cfg.get("ShopLevelData", [])
	for row in levels:
		if int(row.Level) > level and (next.is_empty() or int(row.Level) < int(next.Level)): next = row
	var deposit = int(_shop_float(_shop_float(float(next.get("NeedSaveResCount", 0)) * float(cfg.get("ShopSaveResOnceNeedCountPercent", 0))) / 1000.0))
	var refreshes := 0
	var paid_refreshes := 0
	for shop in profile.data.run.shops:
		if str(shop.key) == key:
			refreshes = int(shop.get("refreshes", 0))
			paid_refreshes = int(shop.get("paid_refreshes", 0))
	var attrs = _shop_attributes()
	var refresh_remaining = maxi(0, int(cfg.get("ShopRefreshTime", 0)) + int(attrs.get("ShopMaxRefreshTime", 0)) - refreshes)
	var refresh_cost = maxi(0, int(attrs.get("ShopRefreshCostByMagicEssence", 0))) << paid_refreshes
	var refresh_reason = "该效果禁止刷新商店" if float(attrs.get("DisableShopRefresh", 0)) >= 1 else "商店刷新次数不足" if refresh_remaining <= 0 else "魔力不足" if material(102) < refresh_cost else ""
	return {"level": level, "invested": stat("shop:invested"), "next_needed": maxi(0, int(next.get("NeedSaveResCount", 0)) - stat("shop:invested")), "max_level": next.is_empty(), "deposit": deposit,
		"remaining": maxi(0, int(cfg.get("ShopMaxSaveResTime", 5)) + int(attrs.get("ShopMaxSaveResTime", 0)) - int(profile.data.run.counters.get("shop:deposits", 0))),
		"refresh_remaining": refresh_remaining, "refresh_cost": refresh_cost, "can_refresh": refresh_reason.is_empty(), "refresh_reason": refresh_reason, "levels": levels.duplicate(true)}

func invest_shop(amount: int = 0) -> Dictionary:
	return _camp_transaction(_invest_shop.bind(amount))

func _invest_shop(amount: int = 0) -> Dictionary:
	if not profile.data.run.active: return _fail("请在冒险中存入")
	var status = room_shop_status("")
	if status.max_level: return _fail("商店已达最高等级")
	if int(status.remaining) <= 0: return _fail("本次冒险存入次数已用完")
	if amount == 0: amount = int(status.deposit)
	if amount <= 0 or amount != int(status.deposit): return _fail("存入金额已变化，请重新打开商店")
	if not spend({"102": amount}): return _fail("魔力不足")
	_add(profile.data.run.counters, "shop:deposits", 1)
	record("shop:invested", amount)
	for row in catalog.config.get("GameShopCfg", {}).get("ShopLevelData", []):
		if stat("shop:invested") >= int(row.NeedSaveResCount): set_record("shop:level", maxi(stat("shop:level"), int(row.Level)))
	return _done("商店升至 %d 级" % stat("shop:level") if stat("shop:level") > int(status.level) else "已存入 %d 魔力" % amount)

func is_shop_sealed(loot_id: int) -> bool:
	return int(profile.data.run.counters.get("shop:sealed:" + str(loot_id), 0)) > 0

func shop_seal_quote(loot_id: int) -> Dictionary:
	if not profile.data.run.active: return {}
	var loot = catalog.find("LootData", loot_id)
	if loot.get("loot_type", "") not in ["普通遗物", "套装遗物", "净化遗物", "强化遗物"] or rank(profile.data.run.inventory, loot_id) <= 0 or is_shop_sealed(loot_id): return {}
	var ability = catalog.find("AbilityItems", int(loot.get("ability_item_id", 0)))
	var rarity = clampi(int(ability.get("Rare", 1)), 1, 5)
	var factors = str(catalog.config.get("GameShopCfg", {}).get("SealLootGetMagicPoint", "")).split("|", false)
	if factors.is_empty(): return {}
	var factor = int(factors[mini(rarity - 1, factors.size() - 1)])
	var attrs = _shop_attributes()
	var price = _shop_float(_shop_base_price(rarity) * _shop_float(1.0 + _shop_float(_shop_float(float(attrs.get("ShopBasePriceAddRate", 0))) / 1000.0)))
	price = _shop_float(price * _shop_float(1.0 + _shop_float(_shop_float(float(attrs.get("ShopPriceAddRate", 0))) / 1000.0)))
	var value = maxi(1, int(_shop_float(_shop_float(price * factor) / 1000.0)))
	value += int(value * int(attrs.get("SealLootGetMagicPointBonusPercent", 0)) / 1000.0)
	return {"loot_id": loot_id, "rarity": rarity, "magic": value, "count": rank(profile.data.run.inventory, loot_id)}

func seal_room_loot(key: String, loot_id: int) -> Dictionary:
	return _camp_transaction(_seal_room_loot.bind(key, loot_id))

func _seal_room_loot(key: String, loot_id: int) -> Dictionary:
	if not profile.data.run.shops.any(func(shop): return str(shop.key) == key): return _fail("请在商店中封印")
	var quote = shop_seal_quote(loot_id)
	if quote.is_empty(): return _fail("该遗物不能封印或已封印")
	profile.data.run.counters["shop:sealed:" + str(loot_id)] = int(quote.count)
	_add(profile.data.run.counters, "SealedLootCount", 1)
	grant_material(102, int(quote.magic))
	return _done("已封印%s，获得 %d 魔力" % [loot_name(loot_id), int(quote.magic)], loot_id)

func _mall_reward_options(row: Dictionary) -> Array:
	var result = []
	if row.get("DetailsDataType", "") not in ["Default", "Rate"]: return result
	for detail in row.get("Details", []):
		var target = catalog.find("MallTradeDetailsData", int(detail.DetailsId))
		var ids = Catalog.ids(target.get("MaterialId", str(detail.DetailsId)))
		if target.get("MallDetailsType", "") == "RegionMaterial_MainCityLevel":
			ids.clear()
			for material_row in catalog.rows("MaterialData"):
				var material_id = Catalog.row_id(material_row)
				if material_id >= 10101 and material_id <= 10501 and int((material_id - 10000) / 100) <= clampi(stat("max-region") + 1, 1, 5): ids.append(material_id)
		if ids.is_empty() or int(detail.Num) <= 0: return []
		for material_id in ids:
			if catalog.find("MaterialData", material_id).is_empty(): return []
		result.append({"ids": ids, "amount": int(detail.Num)})
	return result

func offer_quote(id: int) -> Dictionary:
	var row = catalog.find("MallTradeData", id)
	if row.is_empty(): return _fail("商品不可用")
	var options = _mall_reward_options(row)
	var pay = str(row.get("GoodsPayType", ""))
	var currency = 101 if pay == "Gold" else 90001 if pay == "PurchaseCion" else 90002 if pay == "FreeCion" else 0
	var price = int(row.get("Price", 0))
	var iap: Dictionary = row.get("IAPProductConfigData", {}).duplicate(true)
	# Keep the existing refresh boundaries; no additional daily reset is inferred.
	var period = str(int(int(utc_now.call()) / 86400)) if row.get("RefreshMode", "") == "OneDay" else str(stat("runs")) if row.get("RefreshMode", "") == "OneBattle" else "never"
	var key = "purchase:" + str(id) + ":" + period
	var limit = int(row.get("GoodsNum", -1))
	var purchased = stat(key)
	var reason = ""
	if not row.get("Enable", false): reason = "商品不可用"
	elif options.is_empty(): reason = "商品奖励配置无法解释"
	elif limit >= 0 and purchased >= limit: reason = "已达购买上限"
	elif price < 0: reason = "商品价格配置无效"
	elif pay == "Ad": reason = "请通过广告奖励入口领取"
	elif pay == "Money": reason = "应用内购买暂不可用：尚未接入支付与凭证验证"
	elif pay == "Other": reason = "特殊商品支付暂不可用：尚未接入支付与权益验证"
	elif currency == 0: reason = "未知商品货币"
	elif not can_afford({str(currency): price}): reason = "货币不足"
	return {"success": reason.is_empty(), "can_buy": reason.is_empty(), "id": id, "payment": pay, "currency": currency, "price": price, "payment_price": iap.get("ServerPrice", price), "iap": iap, "offline_conversion": false, "message": reason if not reason.is_empty() else "原配置兑换", "reason": reason, "rewards": options, "purchase": key, "purchased": purchased, "limit": limit, "remaining": maxi(0, limit - purchased) if limit >= 0 else -1, "refresh_mode": str(row.get("RefreshMode", ""))}

func buy_offer(id: int) -> Dictionary:
	return _camp_transaction(_buy_offer.bind(id))

func _buy_offer(id: int) -> Dictionary:
	var quote = offer_quote(id)
	if not quote.success: return quote
	var row = catalog.find("MallTradeData", id)
	if not spend({str(quote.currency): int(quote.price)}): return _fail("货币不足")
	for option in quote.rewards:
		if option.ids.size() == 1: grant_material(int(option.ids[0]), int(option.amount))
		else:
			for draw in int(option.amount): grant_material(int(option.ids[next_random(option.ids.size())]), 1)
	record(str(quote.purchase))
	return _done(Catalog.row_name(row), id)

func buy_mall(id: int) -> Dictionary:
	return buy_offer(id)

func open_material_box(id: int, count: int = 1) -> Dictionary:
	return _camp_transaction(_open_material_box.bind(id, count))

func _open_material_box(id: int, count: int = 1) -> Dictionary:
	var row = catalog.find("ShopTreasureBoxData", id)
	if row.is_empty() or count < 1 or count > 300: return _fail("宝箱或数量无效")
	var guaranteed = costs(row.get("guaranteed_id", ""))
	if guaranteed.has("invalid"): return _fail("宝箱保底格式无效")
	for material_id in guaranteed:
		if catalog.find("MaterialData", material_id).is_empty(): return _fail("宝箱保底材料不存在")
	var entries = []
	var total = 0
	for token in str(row.get("sub_data_id_list", "")).split("|", false):
		var values = token.strip_edges().split(":")
		if values.size() != 3: return _fail("宝箱权重格式无效")
		var entry = {"id": int(values[0]), "amount": int(values[1]), "weight": int(values[2])}
		if entry.amount <= 0 or entry.weight <= 0 or catalog.find("MaterialData", entry.id).is_empty(): return _fail("宝箱奖励配置无效")
		entries.append(entry)
		total += entry.weight
	if total == 0 or not spend({str(id): count}): return _fail("持有宝箱不足")
	for opening in count:
		for material_id in guaranteed: grant_material(int(material_id), int(guaranteed[material_id]))
		var rolled = next_random(total)
		for entry in entries:
			rolled -= entry.weight
			if rolled < 0:
				grant_material(int(entry.id), int(entry.amount))
				break
	record("box:" + str(id) + ":opened", count)
	return _done("宝箱已开启 " + str(count), id)

func event_for_node(node_id: int, seed_value: int, key: String = "", special: bool = false) -> Dictionary:
	if not profile.data.run.active: return {}
	if key.is_empty(): key = str(node_id)
	for encounter in profile.data.run.events:
		if encounter.key == key: return event_view(encounter)
	var candidates = event_candidates(node_id, special)
	if candidates.is_empty(): return {}
	var total = candidates.reduce(func(sum, entry): return sum + int(entry.weight), 0)
	if total <= 0: return {}
	var state = (seed_value * 1664525 + node_id * 1013904223) & 0xffffffff
	for codepoint in key.to_utf8_buffer(): state = ((state ^ codepoint) * 16777619) & 0xffffffff
	var roll = state % total
	var chosen = candidates[0].row
	for entry in candidates:
		roll -= int(entry.weight)
		if roll < 0:
			chosen = entry.row
			break
	var encounter = {"key": key, "event_id": Catalog.row_id(chosen), "step": 0, "finished": false, "result": ""}
	profile.data.run.events.append(encounter)
	_done()
	return event_view(encounter)

func event_candidates(node_id: int, special: bool = false) -> Array:
	var candidates: Array = []
	var sources = ability_sources()
	var area = event_area_level(node_id)
	for row in catalog.rows("AdvantureEventData"):
		var rule = row.get("EventGenerateData", {})
		if not row.get("IsEnable", false): continue
		if (str(row.get("EventType", "Normal")) == "Spacial") != special: continue
		if int(rule.get("NodeLevel", 0)) != 0 and int(rule.NodeLevel) != area: continue
		var appeared = profile.data.run.events.filter(func(x): return int(x.event_id) == Catalog.row_id(row)).size()
		if appeared > 0 and appeared >= int(rule.get("MaxAppearTime", 1)): continue
		var weight = int(rule.get("AppearChance", 0))
		for token in str(rule.get("AddAppearChanceList", "")).replace("|", ",").split(",", false):
			var pair = token.split(":")
			if pair.size() == 2 and rank(sources, int(pair[0])) > 0: weight += int(pair[1])
		if int(rule.get("SpecifyRoomID", 0)) == node_id: weight += 100000
		if weight > 0: candidates.append({"row": row, "weight": weight})
	return candidates

func event_area_level(node_id: int) -> int:
	if _event_node_areas.is_empty():
		var campaign_data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/campaign.json"))
		if campaign_data is Dictionary:
			for row in campaign_data.get("Nodes", []) + campaign_data.get("SpecialStages", []):
				_event_node_areas[int(row.Id)] = int(row.Region)
	return int(_event_node_areas.get(node_id, profile.data.run.get("area_level", profile.data.run.region)))

func event_view(encounter: Dictionary) -> Dictionary:
	var row = catalog.find("AdvantureEventData", int(encounter.event_id))
	if row.is_empty(): return {}
	var data = row.TypeData
	var gamble = row.RuleType == "GambleType"
	var result = {"occurrence_key": encounter.key, "event_id": int(encounter.event_id), "name": Catalog.row_name(row), "icon": row.get("Icon", ""), "event_type": row.get("EventType", "Normal"), "story": data.get("Gamble_StoryText" if gamble else "StoryText", ""), "finished": encounter.finished, "result": encounter.result, "result_story": encounter.get("result_story", encounter.result), "response": encounter.get("response", "继续冒险"), "acknowledged": encounter.get("acknowledged", false), "step": int(encounter.step), "choices": []}
	if encounter.finished: return result
	var options = data.get("GambleOptionList" if gamble else "OptionList", [])
	for i in options.size():
		if gamble and i != int(encounter.step): continue
		var option = options[i]
		var enabled = _event_choice_allowed(option, gamble)
		result.choices.append({"id": int(option.get("GambleOptionDataID" if gamble else "OptionDataId", 0)), "text": option.get("StartGambleText" if gamble else "OptionText", ""), "enabled": enabled, "reason": "" if enabled else "条件或资源不足"})
	if gamble: result.choices.append({"id": -1, "text": options[mini(int(encounter.step), options.size() - 1)].get("EndGambleText", "离开") if not options.is_empty() else "离开", "enabled": true, "reason": ""})
	return result

func _event_condition(row: Dictionary) -> bool:
	var kind = int(row.get("unlock_condition_type", 0))
	var a = int(row.get("unlock_param1", 0))
	var b = int(row.get("unlock_param2", 0))
	var c = int(row.get("unlock_param3", 0))
	match kind:
		0: return true
		1010: return material(_alias(a)) >= b
		1000: return rank(ability_sources(), a) > 0
		9101:
			var value = int(profile.data.run.max_health) if a == 1 else 0
			return value >= b and value <= c
		9102:
			var value = material(102) if a == 8000 else int(profile.data.run.counters.get("SearchPoint", 0)) if a == 8013 else -1
			return value >= b and value <= c
	diagnose("Unknown event condition " + str(kind))
	return false

func _event_choice_allowed(option: Dictionary, gamble: bool) -> bool:
	return _event_condition(option.get("UnlockData", {}))

func _event_rewards(abilities, loot) -> void:
	_depth += 1
	for token in str(abilities).replace("|", ",").split(",", false):
		var pair = token.split(":")
		var id = int(pair[0])
		for i in mini(99, int(pair[1]) if pair.size() > 1 else 1): effects.instant(catalog.find("AbilityItems", id), [id])
	for token in str(loot).replace("|", ",").split(",", false):
		var pair = token.split(":")
		for i in mini(99, int(pair[1]) if pair.size() > 1 else 1): add_loot(int(pair[0]), false)
	_depth -= 1

func resolve_event(key: String, choice_id: int) -> Dictionary:
	return _camp_transaction(func(): return _resolve_event(key, choice_id))

func _resolve_event(key: String, choice_id: int) -> Dictionary:
	if not profile.data.run.active: return _fail("没有进行中的冒险")
	for encounter in profile.data.run.events:
		if encounter.key != key: continue
		if encounter.finished: return _fail("事件已完成")
		var row = catalog.find("AdvantureEventData", int(encounter.event_id))
		if row.is_empty(): return _fail("事件配置不存在")
		var data = row.TypeData
		var gamble = row.RuleType == "GambleType"
		var options = data.get("GambleOptionList" if gamble else "OptionList", [])
		if gamble and choice_id == -1 and not options.is_empty():
			var leaving = options[mini(int(encounter.step), options.size() - 1)]
			encounter.finished = true
			encounter.result = leaving.get("EndGambleText", "离开")
			encounter["result_story"] = encounter.result
			encounter["response"] = "继续冒险"
			_event_rewards(leaving.get("Gamble_EndAddAbilityItemId", ""), leaving.get("Gamble_EndAddRogueLootItemId", ""))
			return _done(encounter.result)
		for index in options.size():
			var option = options[index]
			if int(option.get("GambleOptionDataID" if gamble else "OptionDataId", 0)) != choice_id: continue
			if gamble and index != int(encounter.step): return _fail("赌博步骤不匹配")
			if not _event_choice_allowed(option, gamble): return _fail("选项条件或资源不足")
			_event_rewards(option.get("Gamble_NeedAbilityItemId" if gamble else "NeedAbilityItemId", ""), "")
			if gamble:
				var success = next_random(101) <= int(option.get("Gamble_SuccessChance", 0))
				var outcome = "Success" if success else "Failure"
				encounter.result = option.get("Gameble_SuccessText" if success else "Gamble_FailureText", "")
				encounter["result_story"] = encounter.result
				encounter.step = int(encounter.step) + 1
				var rule = str(data.get("GambleType", "Guaranteed"))
				encounter.finished = (success and rule == "Guaranteed") or (not success and rule == "Promotion") or int(encounter.step) >= options.size()
				if encounter.finished: encounter.result += "\n" + str(data.get("WinToLeaveText" if success else "FailToLeaveText", ""))
				encounter["response"] = data.get("WinToLeaveText" if success else "FailToLeaveText", "继续冒险")
				_event_rewards(option.get("Gamble_" + outcome + "AddAbilityItemId", ""), option.get("Gamble_" + outcome + "AddRogueLootItemId", ""))
			else:
				encounter.finished = true
				encounter.result = str(option.get("OptionSelectFinishText", "")) + "\n" + str(option.get("ResponseText", ""))
				encounter["result_story"] = option.get("OptionSelectFinishText", "")
				encounter["response"] = option.get("ResponseText", "继续冒险")
				_event_rewards(option.get("AddAbilityItemId", ""), option.get("AddRogueLootItemId", ""))
			return _done(encounter.result, choice_id)
		return _fail("未知事件选项")
	return _fail("事件不存在")

func acknowledge_event(key: String) -> Dictionary:
	if not profile.data.run.active: return _fail("没有进行中的冒险")
	for encounter in profile.data.run.events:
		if str(encounter.key) != key: continue
		if not encounter.finished or encounter.get("acknowledged", false): return _fail("事件尚未结束或已经确认")
		encounter["acknowledged"] = true
		return _done()
	return _fail("事件不存在")

func purification_rule(id: int) -> Dictionary:
	var row = catalog.find("LootData", id)
	if row.get("loot_type", "") != "诅咒遗物": return {}
	for component in catalog.find("AbilityItems", int(row.ability_item_id)).get("CombineDataList", []):
		if component.get("CombineDataType", "") == "StateChange": return component
	return {}

func purification_target(id: int) -> int:
	return int(purification_rule(id).get("Data", {}).get("AfterAbilityItemLootId", 0))

func _reset_purification(id: int) -> void:
	for i in purification_rule(id).get("ConditionList", []).size(): profile.data.run.counters["purify:" + str(id) + ":" + str(i)] = 0

func purification_progress(id: int) -> String:
	var result = []
	var conditions = purification_rule(id).get("ConditionList", [])
	for i in conditions.size():
		var condition = conditions[i].get("Condition", {})
		result.append(str(condition.get("RogueEventTriggerData", {}).get("EventType", "")) + " " + str(profile.data.run.counters.get("purify:" + str(id) + ":" + str(i), 0)) + "/" + str(int(condition.get("MinValue", 0))))
	return "; ".join(result)

func record_purification_event(event_type: String, param1: String = "", amount: int = 1, param2: String = "", notify: bool = true) -> Dictionary:
	if not profile.data.run.active or amount <= 0 or event_type not in ["KillEnemy", "EnterNode", "CompleteNode", "BuyNormalShopItem", "ChangeResCount", "CompleteRegion", "TradeWithGemShopMan"]: return _fail("净化事件无效")
	for key in profile.data.run.inventory.keys():
		if int(profile.data.run.inventory[key]) <= 0: continue
		var rule = purification_rule(int(key))
		if rule.is_empty(): continue
		var conditions = rule.get("ConditionList", [])
		for i in conditions.size():
			var condition = conditions[i].get("Condition", {})
			var trigger = condition.get("RogueEventTriggerData", {})
			if conditions[i].get("ConditionType", "") != "RecordValue" or str(trigger.get("EventType", "")) != event_type: continue
			if str(trigger.get("Param1", "")) not in ["", "-1", param1] or str(trigger.get("Param2", "")) not in ["", param2]: continue
			_add(profile.data.run.counters, "purify:" + str(key) + ":" + str(i), amount)
		purify_loot(int(key), false)
	return _done("净化进度已记录") if notify else _ok()

func purify_loot(id: int, notify: bool = true) -> Dictionary:
	var rule = purification_rule(id)
	if not profile.data.run.active or rule.is_empty() or rank(profile.data.run.inventory, id) < 1: return _fail("未持有该诅咒遗物")
	var conditions = rule.get("ConditionList", [])
	if conditions.is_empty(): return _fail("缺少净化条件")
	for i in conditions.size():
		var condition = conditions[i].get("Condition", {})
		var value = int(profile.data.run.counters.get("purify:" + str(id) + ":" + str(i), 0))
		if conditions[i].get("ConditionType", "") != "RecordValue": return _fail("未支持的净化条件")
		if value < int(condition.get("MinValue", 0)) or value > int(condition.get("MaxValue", 2147483647)): return _fail(purification_progress(id))
	var target = purification_target(id)
	if catalog.find("LootData", target).get("loot_type", "") != "净化遗物": return _fail("净化目标不存在")
	_add(profile.data.run.inventory, id, -1)
	var result = add_loot(target, false)
	if not result.success:
		_add(profile.data.run.inventory, id, 1)
		return result
	return _done("遗物已净化", target) if notify else _ok("遗物已净化", target)

func record_node_entry_resources(key: String, node_type: String, notify: bool = true) -> Dictionary:
	return record_node_entry_effects(key, node_type, notify)

func record_node_entry_effects(key: String, node_type: String, notify: bool = true) -> Dictionary:
	var run = profile.data.run
	if not run.active or key.is_empty() or node_type.is_empty(): return _fail("没有有效入房事件")
	var marker = "node-resource-entry:" + key
	if int(run.counters.get(marker, 0)) > 0: return _fail("该入房事件已处理")
	run.counters[marker] = 1
	record_purification_event("EnterNode", node_type, 1, "", false)
	effects.dispatch("EnterNode", node_type)
	return _done("入房效果已处理") if notify else _ok()

func pending_node_entry_buffs(key: String) -> Array:
	for batch in profile.data.run.node_entry_buffs:
		if batch.key == key: return batch.buffs.duplicate(true)
	return []

func confirm_node_entry_buffs_applied(key: String, notify: bool = true) -> Dictionary:
	for batch in profile.data.run.node_entry_buffs:
		if batch.key == key:
			profile.data.run.node_entry_buffs.erase(batch)
			return _done() if notify else _ok()
	return _fail("没有待处理入房效果")

func persistent_node_entry_buffs() -> Array:
	var count = int(profile.data.run.counters.get("node-persistent-buff:70101061", 0))
	return [{"key": "70101061", "value": count}] if profile.data.run.active and count > 0 else []

func revival_count() -> int:
	return maxi(0, int(profile.data.run.counters.get("RevivalRemainCount", 0)))

func search_point_max() -> int:
	return maxi(0, 3 + int(profile.data.run.counters.get("SearchPointMax", 0)))

func search_point_count() -> int:
	return clampi(int(profile.data.run.counters.get("SearchPoint", 0)), 0, search_point_max())

func add_search_points(amount: int) -> void:
	profile.data.run.counters["SearchPoint"] = clampi(search_point_count() + amount, 0, search_point_max())

func route_shift_quote() -> Dictionary:
	var cost = 0 if float(attributes().get("RoadMapVerticalMoveCostSearchPointExemption", 0)) > 0 else 1
	return {"success": profile.data.run.active and search_point_count() >= cost, "cost": cost, "remaining": search_point_count(), "maximum": search_point_max()}

func consume_route_shift() -> Dictionary:
	var quote = route_shift_quote()
	if not quote.success: return _fail("刻印圣典不足，无法上下换路")
	add_search_points(-int(quote.cost))
	if int(quote.cost) > 0:
		record("route:search_points_spent", int(quote.cost))
		record_purification_event("ChangeResCount", "3", int(quote.cost), "1", false)
		effects.dispatch("ChangeResCount", "3", "1", str(quote.cost))
	return _done("已消耗 %d 点刻印圣典" % int(quote.cost))

func revival_protection_seconds() -> float:
	return float(maxi(0, int(1 + float(attributes().get("RevivalGodTime", 0)))))

func revive_player() -> Dictionary:
	var run = profile.data.run
	if not run.active or float(run.health) > 0 or float(run.max_health) <= 0: return _fail("需要在冒险中倒下后复苏")
	if revival_count() < 1: return _fail("复苏宝石不足")
	var previous = attributes()
	_add(run.counters, "RevivalRemainCount", -1)
	# Native restoration precedes CharaRevive; its modifiers affect later revivals.
	var recovered = float(run.max_health) * maxf(0, 300 + float(previous.get("RevivalHpRatio", 0))) / 1000.0
	run.health = clampf(recovered, 0, float(run.max_health))
	effects.dispatch("CharaRevive")
	var current = attributes()
	var old_rate = maxf(0.001, 1 + float(previous.get("HpAddRate", 0)) / 1000.0)
	var new_rate = maxf(0, 1 + float(current.get("HpAddRate", 0)) / 1000.0)
	var basis = (float(run.max_health) - float(previous.get("HpAddFixed", 0))) / old_rate - float(previous.get("BaseHp", 0))
	run.max_health = maxf(1, round((basis + float(current.get("BaseHp", 0))) * new_rate + float(current.get("HpAddFixed", 0))))
	run.health = clampf(float(run.health), 0, float(run.max_health))
	_add(run.counters, "revivals:used", 1)
	record("revivals")
	return _done("已复苏", 12101)

func revive() -> Dictionary:
	return revive_player()

func _npc_unlock(id: int) -> bool:
	var row = catalog.find("UnlockData", id)
	if int(row.get("unlock_condition_type", 0)) == 1010: return material(_alias(int(row.unlock_param1))) >= int(row.unlock_param2)
	return is_unlocked(id)

func npc_function_status(function_id: int) -> Dictionary:
	var row = catalog.find("NPCFunctionData", function_id)
	if row.is_empty(): return _fail("未知NPC功能")
	if row.get("func_msg_name", "") == "NpcSupportTalk" and int(profile.data.run.counters.get("npc-support:" + str(int(row.npc_index)) + ":claimed", 0)) > 0: return _fail("本局已领取该NPC支援")
	if row.get("is_onetime_option", false) and (stat("npc:finished:" + str(function_id)) > 0 or stat("talk:" + str(function_id)) > 0): return _fail("该对话已完成")
	for id in Catalog.ids(row.get("unlock_data_id", "")) + Catalog.ids(row.get("option_active_unlock_id", "")):
		if not _npc_unlock(id):
			var condition = catalog.find("UnlockData", id)
			if int(condition.get("unlock_condition_type", 0)) == 1010:
				return _fail("%s（%d / %d）" % [Catalog.clean(condition.get("unlock_desc", "材料不足")), material(_alias(int(condition.get("unlock_param1", 0)))), int(condition.get("unlock_param2", 0))])
			return _fail(unlock_reason(id))
	return _ok("可用", function_id)

func _finish_npc(function_id: int) -> void:
	if stat("talk:" + str(function_id)) == 0:
		set_record("talk:" + str(function_id), 1)
		record("npc:talks")
	set_record("npc:finished:" + str(function_id), 1)
	record("npc:executions:" + str(function_id))

func execute_npc_function(function_id: int) -> Dictionary:
	return _camp_transaction(_execute_npc_function.bind(function_id))

func _execute_npc_function(function_id: int) -> Dictionary:
	var status = npc_function_status(function_id)
	if not status.success: return status
	var row = catalog.find("NPCFunctionData", function_id)
	var message = str(row.get("func_msg_name", ""))
	if message == "NpcSupportTalk": return prepare_npc_support(function_id)
	var count = {"MainCityTreasureBoxGacha": 1, "MainCityTreasureBoxGacha5": 5, "MainCityTreasureBoxGacha50": 50, "MainCityTreasureBoxGacha300": 300}.get(message, 0)
	if message not in ["", "EnvUnit_NPC_GiveGift"] and count == 0: return _fail("需要宿主导航: " + message)
	var rewards = costs(row.get("finish_talk_reward", ""))
	if rewards.has("invalid"): return _fail("NPC奖励格式无效")
	var granted: Dictionary = {}
	_depth += 1
	var result = _open_camp_boxes_core(count) if count > 0 else _give_npc_gift(int(row.npc_index)) if message == "EnvUnit_NPC_GiveGift" else _ok("对话完成", function_id)
	if result.success:
		granted = result.get("rewards", {}).duplicate()
		if stat("npc:reward:" + str(function_id)) == 0 and not rewards.is_empty():
			for id in rewards: grant_material(int(id), int(rewards[id]))
			set_record("npc:reward:" + str(function_id), 1)
			for id in rewards: granted[id] = int(granted.get(id, 0)) + int(rewards[id])
		_finish_npc(function_id)
	_depth -= 1
	if not result.success: return result
	var completed = _done(result.message, function_id)
	completed["rewards"] = granted
	return completed

func camp_treasure_quote(count: int) -> Dictionary:
	var function_id = {1: 140201, 5: 140203, 50: 140204, 300: 140205}.get(count, 0)
	var reason = _camp_action_reason("treasure")
	var row = catalog.find("ShopTreasureBoxData", int(catalog.config.get("StoreTreasureBoxId", 0)))
	var price = {"101": int(row.get("price", 0)) * maxi(0, count)}
	if function_id == 0: reason = "请选择1、5、50或300个宝箱"
	elif row.is_empty() or int(row.get("price", -1)) < 0: reason = "宝箱配置无效"
	elif reason.is_empty():
		var status = npc_function_status(function_id)
		if not status.success: reason = status.message
		elif not can_afford(price): reason = "金币不足"
	return {"count": count, "id": int(catalog.config.get("StoreTreasureBoxId", 0)), "function_id": function_id, "price": price, "can_buy": reason.is_empty(), "reason": reason}

func open_camp_treasure_boxes(count: int) -> Dictionary:
	var quote = camp_treasure_quote(count)
	if not quote.can_buy: return _fail(quote.reason)
	return execute_npc_function(int(quote.function_id))

func _open_camp_boxes_core(count: int) -> Dictionary:
	var reason = _camp_action_reason("treasure")
	if not reason.is_empty(): return _fail(reason)
	var box_id = int(catalog.config.get("StoreTreasureBoxId", 0))
	var row = catalog.find("ShopTreasureBoxData", box_id)
	if row.is_empty() or not str(row.get("guaranteed_id", "")).is_empty(): return _fail("宝箱缺少配置或保底规则尚未恢复")
	var minimum = int(catalog.config.get("StoreTreasureGachaRandomNum_Min", 1))
	var maximum = int(catalog.config.get("StoreTreasureGachaRandomNum_Max", 1))
	if minimum < 1 or maximum < minimum or maximum > 100: return _fail("宝箱抽数配置无效")
	var entries = []
	var total = 0
	for token in str(row.sub_data_id_list).split("|", false):
		var values = token.strip_edges().split(":")
		if values.size() != 3: return _fail("宝箱权重格式无效")
		var entry = {"id": int(values[0]), "amount": int(values[1]), "weight": int(values[2])}
		if entry.id <= 0 or entry.amount <= 0 or entry.weight <= 0: return _fail("宝箱奖励无效")
		entries.append(entry)
		total += entry.weight
	if total == 0 or not spend({"101": int(row.price) * count}): return _fail("金币不足")
	var draws = 0
	for i in count:
		for j in minimum + (next_random(maximum - minimum + 1) if maximum > minimum else 0):
			var rolled = next_random(total)
			for entry in entries:
				rolled -= entry.weight
				if rolled < 0:
					grant_material(entry.id, entry.amount)
					draws += 1
					break
	record("box:" + str(box_id) + ":opened", count)
	record("box:" + str(box_id) + ":draws", draws)
	return _ok("开启宝箱 " + str(count) + "，奖励 " + str(draws), box_id)

func npc_support_offer(function_id: int) -> Dictionary:
	var row = catalog.find("NPCFunctionData", function_id)
	if row.get("func_msg_name", "") != "NpcSupportTalk": return {}
	var key = "npc-support:" + str(int(row.npc_index))
	for shop in profile.data.run.shops:
		if shop.key == key: return shop
	return {}

func prepare_npc_support(function_id: int) -> Dictionary:
	var row = catalog.find("NPCFunctionData", function_id)
	var npc = catalog.find("NPCData", int(row.get("npc_index", 0)))
	if not profile.data.run.active or int(npc.get("support_item_pool_id", 0)) == 0: return _fail("当前没有冒险支援")
	if not npc_support_offer(function_id).is_empty(): return _ok("请选择一项支援", function_id)
	var step = profile.data.run.random_step
	var choices = roll_pool(int(npc.support_item_pool_id), 3)
	if choices.is_empty():
		profile.data.run.random_step = step
		return _fail("没有可用支援物品")
	var offer = {"key": "npc-support:" + str(Catalog.row_id(npc)), "offers": [], "refreshes": 0}
	for id in choices: offer.offers.append({"loot_id": id, "price": 0, "sold": false})
	profile.data.run.shops.append(offer)
	return _done("请选择一项支援", function_id)

func claim_npc_support(function_id: int, loot_id: int) -> Dictionary:
	var status = npc_function_status(function_id)
	if not status.success: return status
	var offer = npc_support_offer(function_id)
	if not profile.data.run.active or offer.is_empty() or not offer.offers.any(func(x): return int(x.loot_id) == loot_id) or offer.offers.any(func(x): return x.sold): return _fail("支援已领取或选择无效")
	if not can_add_loot(loot_id): return _fail("支援物品冲突或达到上限")
	var result = add_loot(loot_id, false)
	if not result.success: return result
	for item in offer.offers: item.sold = true
	var npc_id = int(catalog.find("NPCFunctionData", function_id).npc_index)
	profile.data.run.counters["npc-support:" + str(npc_id) + ":claimed"] = 1
	_add(profile.data.run.counters, "CampNpcSupportCount", 1)
	_finish_npc(function_id)
	return _done(result.message, loot_id)

func gem_offerings_used() -> int:
	return int(profile.data.run.counters.get("gem-offerings:" + str(int(profile.data.run.region)), 0))

func gem_offering_limit() -> int:
	return 1

func get_gem_offering(instance_key: String = "") -> Dictionary:
	var run = profile.data.run
	if not run.active or int(run.region) < 1: return {}
	if instance_key.is_empty(): instance_key = "region:%d:node:%d" % [int(run.region), int(run.current_node)]
	var key = "gem-offering:instance:" + instance_key
	for shop in run.shops:
		if str(shop.key) == key: return shop
	var offer = {"key": key, "kind": "gem", "instance_key": instance_key, "region": int(run.region), "used": false, "refreshes": 0, "offers": []}
	run.shops.append(offer)
	_done()
	return offer

func gem_offering_price(offer: Dictionary) -> int:
	if offer.is_empty() or int(profile.data.run.counters.get("GemShopFreeCostCount", 0)) > 0: return 0
	var cfg: Dictionary = catalog.config.get("GemShopCfg", {})
	var prices: Array = cfg.get("CostPriceList", [])
	if prices.is_empty(): return 0
	# Native GetTradeWithGemShopManNeedMagicPoint always selects the first price.
	var base = int(prices[0]) + maxi(0, int(offer.get("region", profile.data.run.region)) - 1) * int(cfg.get("NodeLevelAddPriceFixed", 0))
	var factor = _shop_float(1.0 + _shop_float(float(attributes().get("GemShopTradeCostRate", 0)) / 1000.0))
	return maxi(0, int(_shop_float(_shop_float(float(base)) * factor)))

func gem_offering_status(instance_key: String = "") -> Dictionary:
	var offer = get_gem_offering(instance_key)
	var price = gem_offering_price(offer)
	var used = bool(offer.get("used", false))
	var reason = "请在冒险中供奉" if not profile.data.run.active else "供奉配置不可用" if offer.is_empty() or catalog.config.get("GemShopCfg", {}).get("CostPriceList", []).is_empty() else "已经供奉过了" if used else "没有可用宝石" if _gem_offering_candidates(attributes()).is_empty() else "魔力不足" if material(102) < price else ""
	return {"offer": offer, "key": str(offer.get("key", "")), "price": price, "free": price == 0, "used": used, "remaining": 0 if used else 1, "can_buy": reason.is_empty(), "reason": reason}

func _gem_offering_candidates(attrs: Dictionary) -> Array:
	var candidates = _pool_candidates(int(catalog.config.get("GemShopCfg", {}).get("GemPoolId", 0)))
	var color_rates = {"攻击宝石": "GemShopManDropChanceAddRate_RedGem", "防御宝石": "GemShopManDropChanceAddRate_BlueGem", "生命宝石": "GemShopManDropChanceAddRate_GreenGem"}
	for entry in candidates:
		var loot_type = str(catalog.find("LootData", int(entry.id)).get("loot_type", ""))
		if color_rates.has(loot_type):
			var rate = maxi(0, 1000 + int(attrs.get(color_rates[loot_type], 0)))
			entry.weight = _shop_float(float(entry.weight) * _shop_float(float(rate) / 1000.0))
	return candidates.filter(func(entry): return float(entry.weight) > 0)

func _roll_gem_offering(attrs: Dictionary) -> Array:
	var count = maxi(0, 1 + int(attrs.get("GemShopManDropCount", 0)))
	var chance = int(attrs.get("GemShopManDropCountRandomAddChance", 0))
	if chance > 0 and next_random(1000) < chance: count += 1
	var candidates = _gem_offering_candidates(attrs)
	var result: Array = []
	while result.size() < count and not candidates.is_empty():
		var total = candidates.reduce(func(value, entry): return value + float(entry.weight), 0.0)
		var roll = total * next_random(16777217) / 16777216.0
		var cumulative := 0.0
		for entry in candidates:
			cumulative += float(entry.weight)
			if cumulative >= roll:
				result.append(int(entry.id))
				candidates = candidates.filter(func(other): return int(other.id) != int(entry.id))
				break
	return result

func buy_gem_offering(key: String, claim_rewards: bool = true) -> Dictionary:
	return _camp_transaction(_buy_gem_offering.bind(key, claim_rewards))

func _buy_gem_offering(key: String, claim_rewards: bool) -> Dictionary:
	var run = profile.data.run
	if not run.active: return _fail("请在冒险中供奉")
	for offer in run.shops:
		if offer.key != key: continue
		if str(offer.get("kind", "")) != "gem" or int(offer.get("region", 0)) != int(run.region): return _fail("报价已失效")
		if bool(offer.get("used", false)): return _fail("已经供奉过了")
		if _gem_offering_candidates(attributes()).is_empty(): return _fail("没有可用宝石")
		var price = gem_offering_price(offer)
		if not spend({"102": price}): return _fail("魔力不足")
		if int(run.counters.get("GemShopFreeCostCount", 0)) > 0: _add(run.counters, "GemShopFreeCostCount", -1)
		offer.used = true
		_add(run.counters, "gem-offerings:" + str(int(run.region)), 1)
		record("gem:trades")
		record_purification_event("TradeWithGemShopMan", "", 1, "", false)
		effects.dispatch("TradeWithGemShopMan")
		var drops: Array = []
		for loot_id in _roll_gem_offering(attributes()):
			offer.offers.append({"loot_id": loot_id, "price": price, "sold": true})
			drops.append({"id": loot_id, "amount": 1, "material": false})
			if claim_rewards: add_loot(loot_id, false)
		var result = _done("供奉完成，获得 %d 枚宝石" % drops.size(), 2100)
		result["drops"] = drops
		result["price"] = price
		return result
	return _fail("报价不存在")
