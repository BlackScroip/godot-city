class_name DungeonCharacterFashion
extends RefCounted

const SOURCE := "res://assets/ui/role_character/CharaFashionConfigData.json"
static var _rows: Array = []
static var _index: Dictionary = {}
var systems

func _init(owner) -> void:
	systems = owner
	if not _rows.is_empty(): return
	var source = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
	if source is Array:
		_rows = source
		for row in _rows: _index[int(row.id)] = row

func _visible(row: Dictionary) -> bool:
	return not row.is_empty() and not bool(row.get("is_admin_only", false))

func _core_owned(row: Dictionary) -> bool:
	return bool(row.get("default_unlock", false)) or int(row.get("id", 0)) in systems.profile.data.get("fashion_owned", [])

func _grant_owner(id: int) -> int:
	for row in _rows:
		if id in DungeonCatalog.ids(row.get("auto_grant_fashion_ids", [])): return int(row.id)
	return 0

func _owned(row: Dictionary) -> bool:
	if not _visible(row): return false
	if _core_owned(row): return true
	var owner: Dictionary = _index.get(_grant_owner(int(row.id)), {})
	return _visible(owner) and _core_owned(owner)

func owned_ids() -> Array:
	var result: Array = []
	for row in _rows:
		if _owned(row): result.append(int(row.id))
	return result

func selected_id(character_id: int) -> int:
	var id = int(systems.profile.data.get("fashion_equipped", {}).get(str(character_id), 0))
	var row: Dictionary = _index.get(id, {})
	if int(row.get("chara_id", 0)) == character_id and _owned(row): return id
	for candidate in _rows:
		if int(candidate.chara_id) == character_id and bool(candidate.get("default_unlock", false)) and _visible(candidate): return int(candidate.id)
	return 0

func equipped_ids() -> Dictionary:
	var result: Dictionary = {}
	for row in systems.catalog.rows("CharData"):
		result[str(int(row.id))] = selected_id(int(row.id))
	return result

func status(id: int, character_id := 0) -> Dictionary:
	var row: Dictionary = _index.get(id, {})
	if character_id <= 0: character_id = int(row.get("chara_id", 0))
	var price: Dictionary = {}
	for cost in row.get("purchase_cost", []):
		var material_id = int(cost.get("item_id", 0))
		var amount = int(cost.get("get_num", 0))
		if material_id <= 0 or amount < 0 or systems.catalog.find("MaterialData", material_id).is_empty():
			price = {"invalid": -1}
			break
		price[str(material_id)] = int(price.get(str(material_id), 0)) + amount
	var owned = _owned(row)
	var equipped = owned and selected_id(character_id) == id
	var reason = systems._camp_action_reason()
	if not _visible(row): reason = "未知或不可用的时装"
	elif int(row.chara_id) != character_id: reason = "该时装不属于当前角色"
	elif systems.rank(systems.profile.data.character_levels, character_id) < 1: reason = "请先解锁该角色"
	var equip_reason = reason
	if equip_reason.is_empty() and not owned: equip_reason = "时装尚未解锁"
	if reason.is_empty() and not owned:
		var owner_id = _grant_owner(id)
		if owner_id > 0:
			reason = "随%s一并解锁" % DungeonCatalog.clean(_index[owner_id].name)
		elif bool(row.get("is_cash_only_unlock", false)):
			reason = "需通过平台购买，当前版本尚未接入支付"
		elif price.is_empty() or price.has("invalid"):
			reason = "当前没有可用的解锁途径"
		elif not systems.can_afford(price): reason = "时装解锁材料不足"
	return {"id": id, "character_id": character_id, "owned": owned, "equipped": equipped, "price": price,
		"can_unlock": not owned and reason.is_empty(), "can_equip": owned and not equipped and equip_reason.is_empty(),
		"reason": reason, "equip_reason": equip_reason, "grant_owner_id": _grant_owner(id)}

func unlock(id: int, character_id := 0) -> Dictionary:
	var quote = status(id, character_id)
	if not quote.can_unlock:
		return systems._fail("时装已解锁" if quote.owned else quote.reason)
	if not systems.spend(quote.price): return systems._fail("时装解锁材料不足")
	if not systems.profile.data.has("fashion_owned"): systems.profile.data["fashion_owned"] = []
	systems.profile.data.fashion_owned.append(id)
	return systems._done("时装已解锁", id)

func equip(id: int, character_id := 0) -> Dictionary:
	var quote = status(id, character_id)
	if not quote.equip_reason.is_empty(): return systems._fail(quote.equip_reason)
	if quote.equipped: return systems._ok("时装已装备", id)
	if not systems.profile.data.has("fashion_equipped"): systems.profile.data["fashion_equipped"] = {}
	systems.profile.data.fashion_equipped[str(quote.character_id)] = id
	return systems._done("时装已装备", id)

func attributes(character_id: int) -> Dictionary:
	var result: Dictionary = {}
	var fields = {"unlock_atk_add": "BaseAtk", "unlock_def_add": "BaseDef", "unlock_hp_add": "BaseHp", "unlock_criti_rate_add": "CriticalRate", "unlock_criti_mult_add": "CriticalMulti"}
	for row in _rows:
		if int(row.chara_id) != character_id or not _owned(row): continue
		for field in fields:
			var amount = int(row.get(field, 0))
			if amount != 0: result[fields[field]] = int(result.get(fields[field], 0)) + amount
	return result

func equipped_buffs(character_id: int) -> Array:
	return DungeonCatalog.ids(_index.get(selected_id(character_id), {}).get("unlock_buff_id_list", []))
