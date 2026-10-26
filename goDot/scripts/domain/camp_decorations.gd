extends RefCounted

var _owner: WeakRef
var systems:
	get: return _owner.get_ref()

func _init(owner_systems) -> void:
	_owner = weakref(owner_systems)
	_ensure_saved_defaults()

func global_status() -> Dictionary:
	var level = 0
	var maximum = 0
	for row in systems.catalog.rows("Buildings"):
		var cap = int(row.get("max_level", 0))
		maximum += cap
		level += clampi(systems.rank(systems.profile.data.buildings, row.id), 0, cap)
	var ready = maximum > 0 and level >= maximum
	var reason = "" if ready else "完成全部主城建设后开放外观装饰（%d / %d）" % [level, maximum]
	if systems.profile.data.run.active:
		reason = "请返回营地后操作"
	return {"available": ready and not systems.profile.data.run.active, "completed": level, "maximum": maximum, "reason": reason}

func available() -> bool:
	return bool(global_status().available)

func slots() -> Array:
	var result: Array = []
	for source in _slot_rows():
		var row: Dictionary = source.duplicate(true)
		var slot_id = int(row.slot_id)
		row["current_id"] = current_id(slot_id)
		row["repaired"] = _slot_repaired(row)
		row["display_id"] = row.current_id if row.repaired else int(row.locked_decoration_id)
		row["options"] = []
		for option in _decoration_rows():
			if int(option.get("slot_id", 0)) == slot_id and int(option.id) != int(row.locked_decoration_id):
				row.options.append(status(int(option.id)))
		result.append(row)
	return result

func current_id(slot_id: int) -> int:
	var slot = _slot(slot_id)
	if slot.is_empty(): return 0
	var fallback = int(slot.default_decoration_id)
	var selected = int(systems.profile.data.get("camp_decorations", {}).get(str(slot_id), fallback))
	var row = _decoration(selected)
	if row.is_empty() or int(row.slot_id) != slot_id or selected == int(slot.locked_decoration_id): return fallback
	return selected if selected == fallback or _purchased().has(selected) else fallback

func status(decoration_id: int) -> Dictionary:
	var row = _decoration(decoration_id)
	var slot = _slot(int(row.get("slot_id", 0)))
	var valid = not row.is_empty() and not slot.is_empty()
	var is_ruins = valid and decoration_id == int(slot.locked_decoration_id)
	var is_default = valid and decoration_id == int(slot.default_decoration_id)
	var owned = valid and not is_ruins and (is_default or _purchased().has(decoration_id))
	var price = _price(row)
	var unlock_id = int(row.get("unlock_data_id", 0))
	var unlock_reason = ""
	if valid and not owned and not is_ruins:
		# The shipped unlock routine rejects missing UnlockData, even with a price.
		if unlock_id <= 0 or systems.catalog.find("UnlockData", unlock_id).is_empty():
			unlock_reason = "该外观尚未配置解锁条件"
		else:
			unlock_reason = systems.unlock_reason(unlock_id)
	var reason = ""
	if not valid: reason = "外观不存在"
	elif is_ruins: reason = "废墟外观不可选用"
	elif not available(): reason = str(global_status().reason)
	elif not owned:
		if not unlock_reason.is_empty(): reason = unlock_reason
		elif price.has("invalid") or price.is_empty(): reason = "外观解锁费用配置无效"
		elif not systems.can_afford(price): reason = "解锁外观所需资源不足"
	var selected = valid and current_id(int(row.get("slot_id", 0))) == decoration_id
	var prefab_valid = not str(row.get("prefab_name", "")).is_empty()
	return {"id": decoration_id, "row": row, "slot_id": int(row.get("slot_id", 0)), "valid": valid, "is_ruins": is_ruins, "is_default": is_default, "owned": owned, "selected": selected, "price": price, "unlock_id": unlock_id, "unlock_reason": unlock_reason, "reason": reason, "can_unlock": reason.is_empty() and not owned, "can_equip": reason.is_empty() and owned and prefab_valid}

func unlock(decoration_id: int) -> Dictionary:
	var quote = status(decoration_id)
	if not quote.reason.is_empty(): return systems._fail(quote.reason)
	if quote.owned: return systems._ok("外观已解锁", decoration_id)
	if not quote.can_unlock or not systems.spend(quote.price): return systems._fail("解锁外观所需资源不足")
	systems.profile.data.unlocked_camp_decorations.append(decoration_id)
	return systems._done("外观已解锁", decoration_id)

func equip(slot_id: int, decoration_id: int) -> Dictionary:
	var quote = status(decoration_id)
	if not quote.valid or int(quote.slot_id) != slot_id: return systems._fail("外观与装饰位置不匹配")
	if not quote.reason.is_empty(): return systems._fail(quote.reason)
	if not quote.can_equip: return systems._fail("请先解锁外观")
	if quote.selected: return systems._ok("已使用该外观", decoration_id)
	systems.profile.data.camp_decorations[str(slot_id)] = decoration_id
	return systems._done("已更换外观", decoration_id)

func _slot_repaired(slot: Dictionary) -> bool:
	var building = int(slot.get("unlock_develop_type", 0))
	var level = 1 if building == 0 else systems.rank(systems.profile.data.buildings, building)
	return level >= int(slot.get("unlock_level", 1))

func _slot_rows() -> Array:
	return systems.catalog.config.get("MainCityDecorationSlotList", [])

func _decoration_rows() -> Array:
	return systems.catalog.config.get("MainCityDecorationDataList", [])

func _slot(slot_id: int) -> Dictionary:
	for row in _slot_rows():
		if int(row.get("slot_id", 0)) == slot_id: return row
	return {}

func _decoration(decoration_id: int) -> Dictionary:
	for row in _decoration_rows():
		if int(row.get("id", 0)) == decoration_id: return row
	return {}

func _purchased() -> Array:
	return systems.profile.data.get("unlocked_camp_decorations", [])

func _price(row: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for cost in row.get("unlock_cost_list", []):
		var resource = int(cost.get("item_id", 0))
		var amount = int(cost.get("count", 0))
		if resource <= 0 or amount <= 0: continue
		var key = str(resource)
		result[key] = int(result.get(key, 0)) + amount
	return result

func _ensure_saved_defaults() -> void:
	var data: Dictionary = systems.profile.data
	if not data.get("camp_decorations", null) is Dictionary: data["camp_decorations"] = {}
	if not data.get("unlocked_camp_decorations", null) is Array: data["unlocked_camp_decorations"] = []
	var normalized: Array = []
	for value in data.unlocked_camp_decorations:
		var id = int(value)
		var row = _decoration(id)
		var slot = _slot(int(row.get("slot_id", 0)))
		if not slot.is_empty() and id != int(slot.locked_decoration_id) and not normalized.has(id): normalized.append(id)
	data.unlocked_camp_decorations = normalized
	var selections: Dictionary = {}
	for slot in _slot_rows():
		var id = int(slot.slot_id)
		selections[str(id)] = current_id(id)
	data.camp_decorations = selections
