extends RefCounted

const SOURCE := "res://assets/ui/spirit_skills/catalog.json"
static var _icons: Dictionary = {}
var systems: RefCounted

func _init(owner_systems: RefCounted) -> void:
	systems = owner_systems
	if _icons.is_empty():
		var source: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
		if source is Dictionary: _icons = source.get("icons", {})

func definition(loot_id: int) -> Dictionary:
	var loot: Dictionary = systems.catalog.find("LootData", loot_id)
	var ability_id := int(loot.get("ability_item_id", 0))
	if not _icons.has(str(ability_id)): return {}
	var ability: Dictionary = systems.catalog.find("AbilityItems", ability_id)
	var combined := str(loot.get("loot_type", "")) == "高级随从"
	return {"id": loot_id, "ability_id": ability_id, "name": DungeonCatalog.clean(DungeonCatalog.row_name(ability)),
		"description": DungeonCatalog.clean(DungeonCatalog.description(ability)), "rarity": int(ability.get("Rare", 3)),
		"icon": str(_icons[str(ability_id)].icon), "combined": combined,
		"grade": "融合精灵" if combined else ["基础精灵", "进阶精灵", "高阶精灵"][clampi(int(ability.get("Rare", 3)) - 3, 0, 2)]}

func owned() -> Array:
	var result: Array = []
	if not bool(systems.profile.data.run.active): return result
	var inventory: Dictionary = systems.profile.data.run.inventory
	var suppressed: Dictionary = {}
	for key in inventory:
		if int(inventory[key]) <= 0 or definition(int(key)).is_empty(): continue
		var loot: Dictionary = systems.catalog.find("LootData", int(key))
		var ability: Dictionary = systems.catalog.find("AbilityItems", int(loot.ability_item_id))
		for previous in DungeonCatalog.ids(ability.get("RejectIdArray", "")): suppressed[previous] = true
	var keys: Array = inventory.keys()
	keys.sort_custom(func(a, b): return int(a) < int(b))
	for key in keys:
		if int(inventory[key]) <= 0 or suppressed.has(int(key)) or systems.is_shop_sealed(int(key)): continue
		var entry := definition(int(key))
		if not entry.is_empty(): result.append(entry)
	return result

func preview(loot_id: int) -> Dictionary:
	var entry := definition(loot_id)
	if entry.is_empty(): return entry
	var replacements: Array = systems.follower_replacements(systems.catalog.find("LootData", loot_id))
	var previous: Array = owned().filter(func(row): return replacements.has(int(row.id)))
	var names: Array[String] = []
	for row in previous: names.append(str(row.name))
	entry["replacements"] = previous
	entry["mode"] = "融合" if bool(entry.combined) else "升级" if not previous.is_empty() else "获得"
	entry["transition"] = " + ".join(names) + " → " + str(entry.name) if not names.is_empty() else "附加到角色"
	entry["available"] = systems.can_add_loot(loot_id)
	var gate: Dictionary = systems.catalog.find("UnlockData", int(systems.catalog.find("LootData", loot_id).get("unlock_data_id", 0)))
	entry["requirement"] = DungeonCatalog.clean(gate.get("unlock_desc", ""))
	return entry

func upgrade_options(loot_id: int) -> Array:
	var result: Array = []
	for loot in systems.catalog.rows("LootData"):
		if not systems.follower_replacements(loot).has(loot_id): continue
		var entry := preview(int(loot.id))
		if not entry.is_empty(): result.append(entry)
	return result
