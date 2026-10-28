extends RefCounted

const Catalog = preload("res://scripts/domain/catalog.gd")
const TOKENS := "<#(backpack_(?:layer|progress|record_trigger|buff_layer))(?::(\\d+))?>"
const PREVIEW_STATUS := "<color=[^>]*>\\s*（[^）]*<#backpack_[^>]*>[^）]*）\\s*</color>"

var _owner: WeakRef
var systems:
	get: return _owner.get_ref()

func _init(owner_systems: RefCounted) -> void:
	_owner = weakref(owner_systems)

func source(ability_id: int, loot_id := 0, combat: RefCounted = null) -> String:
	var row: Dictionary = systems.catalog.find("AbilityItems", ability_id)
	var text := DungeonLocale.text(Catalog.description(row))
	var tokens := RegEx.create_from_string(TOKENS)
	if tokens.search(text) == null: return text
	if loot_id <= 0:
		for loot in systems.catalog.rows("LootData"):
			if int(loot.get("ability_item_id", 0)) == ability_id:
				loot_id = int(loot.id)
				break
	# The APK strips backpack-only status clauses from previews without an owned item.
	if not bool(systems.profile.data.run.active) or int(systems.profile.data.run.inventory.get(str(loot_id), 0)) <= 0:
		text = RegEx.create_from_string(PREVIEW_STATUS).sub(text, "", true)
		return tokens.sub(text, "", true)
	for token in tokens.search_all(text):
		var id := int(token.get_string(2))
		var kind := token.get_string(1)
		var ability: Dictionary = row if id <= 0 or kind == "backpack_buff_layer" else systems.catalog.find("AbilityItems", id)
		var replacement := ""
		match kind:
			"backpack_layer": replacement = str(_display_layer(ability, combat))
			"backpack_buff_layer": replacement = str(_buff_layer(id, ability, combat))
			"backpack_progress": replacement = _progress(loot_id)
			"backpack_record_trigger": replacement = _trigger_count(ability)
		text = text.replace(token.get_string(), replacement)
	return text

func effect_factor(row: Dictionary, count: int) -> int:
	var factor := 1
	if bool(row.get("EnableCaculateAttributeSource", false)):
		var divisor := int(row.get("CaculateAttributeSourcePercent", 0))
		if divisor > 0: factor = int(source_attribute(str(row.get("CaculateAttributeSource", "None"))) / divisor)
	var maximum := int(row.get("CaculateAttributeSourceMaxFactor", 0))
	if maximum > 0: factor = mini(factor, maximum)
	return maxi(0, factor * count)

func component_factor(row: Dictionary, data: Dictionary, count: int) -> int:
	return effect_factor(row, count) if bool(data.get("IsNotLayer", false)) else 1

func capped_buff_layers(buff_id: int, layers: int) -> int:
	var data: Dictionary = systems.catalog.find("Buffs", buff_id).get("BuffData", {})
	var maximum := int(data.get("MaxLayerNum", 1))
	return mini(maxi(0, layers), maximum) if maximum > 0 else maxi(0, layers)

func source_attribute(kind: String) -> int:
	var run: Dictionary = systems.profile.data.run
	match kind:
		"MagicPoint": return int(systems.material(102))
		"SearchPoint": return int(systems.search_point_count())
		"CampNpcSupportCount": return int(run.counters.get("CampNpcSupportCount", 0))
	var total := 0
	for key in run.inventory:
		var count := int(run.inventory[key])
		if count <= 0: continue
		var loot: Dictionary = systems.catalog.find("LootData", int(key))
		var ability: Dictionary = systems.catalog.find("AbilityItems", int(loot.get("ability_item_id", 0)))
		var rarity := int(ability.get("Rare", 0))
		var category := str(loot.get("loot_type", ""))
		match kind:
			"BackPackLootCount":
				if bool(loot.get("is_visible", false)): total += count
			"BackPackLootCount_1Star", "BackPackLootCount_2Star", "BackPackLootCount_3Star", "BackPackLootCount_4Star", "BackPackLootCount_5Star":
				if bool(loot.get("is_visible", false)) and rarity == int(kind.get_slice("_", 1).left(1)): total += count
			"GemHaveCount":
				if category in ["攻击宝石", "防御宝石", "生命宝石"]: total += count
			"SpritesRarityTotal":
				if category == "高级随从": total += 7
				elif category == "随从": total += {3: 1, 4: 2, 5: 3}.get(rarity, 0)
			"LootAllStarNum":
				if not bool(ability.get("IsTriggerFinishCost", false)): total += rarity
			"MonsterPartnerGeneralCount":
				if category == "怪物支援通用遗物": total += count
	return total

func _ability_count(id: int) -> int:
	var count := 0
	for key in systems.profile.data.run.inventory:
		var loot: Dictionary = systems.catalog.find("LootData", int(key))
		if int(loot.get("ability_item_id", 0)) == id: count += int(systems.profile.data.run.inventory[key])
	return count

func _display_layer(row: Dictionary, combat: RefCounted) -> int:
	var id := Catalog.row_id(row)
	var components: Array = row.get("CombineDataList", [])
	for index in components.size():
		var component: Dictionary = components[index]
		if component.get("CombineDataType", "") != "RecordTrigger": continue
		var data: Dictionary = component.get("Data", {})
		var key := "effect:%d:%d" % [id, index]
		var counters: Dictionary = systems.profile.data.run.counters
		if counters.has(key + ":layers"): return int(counters[key + ":layers"])
		if counters.has(key + ":record"):
			var layers := int(int(counters[key + ":record"]) / maxi(1, int(data.get("TriggerPercent", 1))))
			var maximum := int(data.get("MaxLayer", -1))
			return mini(layers, maximum) if maximum >= 0 else layers
		for buff in Catalog.ids(data.get("ModifyBuff", "")):
			if counters.has("rogue-event-buff:" + str(buff)): return int(counters["rogue-event-buff:" + str(buff)])
		return 0
	for component in components:
		var data: Dictionary = component.get("Data", {})
		if component.get("CombineDataType", "") == "NormalModifyBuff" and bool(data.get("IsNotLayer", false)):
			var buffs := Catalog.ids(data.get("ModifyBuff", ""))
			if not buffs.is_empty(): return _buff_layer(int(buffs[0]), row, combat)
	return effect_factor(row, _ability_count(id))

func _buff_layer(id: int, row: Dictionary, combat: RefCounted) -> int:
	if combat != null and combat.has_method("buff_layers"): return int(combat.buff_layers(str(id)))
	var counters: Dictionary = systems.profile.data.run.counters
	if counters.has("rogue-event-buff:" + str(id)): return int(counters["rogue-event-buff:" + str(id)])
	var count := _ability_count(Catalog.row_id(row))
	if Catalog.ids(row.get("ModifyBuff", "")).has(id): return capped_buff_layers(id, effect_factor(row, count))
	for component in row.get("CombineDataList", []):
		var data: Dictionary = component.get("Data", {})
		if component.get("CombineDataType", "") == "NormalModifyBuff" and Catalog.ids(data.get("ModifyBuff", "")).has(id):
			return capped_buff_layers(id, component_factor(row, data, count))
	return 0

func _progress(loot_id: int) -> String:
	var rule: Dictionary = systems.loot_state_change_rule(loot_id)
	var conditions: Array = rule.get("ConditionList", [])
	for index in conditions.size():
		if conditions[index].get("ConditionType", "") != "RecordValue": continue
		var condition: Dictionary = conditions[index].get("Condition", {})
		var target := int(condition.get("MinValue", 0))
		var value := int(systems.profile.data.run.counters.get("purify:%d:%d" % [loot_id, index], 0))
		return "%d/%d" % [mini(value, target), target] if target > 0 else str(value)
	return "0"

func _trigger_count(row: Dictionary) -> String:
	var components: Array = row.get("CombineDataList", [])
	for index in components.size():
		if components[index].get("CombineDataType", "") != "RecordTrigger": continue
		var data: Dictionary = components[index].get("Data", {})
		var maximum := int(data.get("MaxEffectCount", 0))
		var value := int(systems.profile.data.run.counters.get("effect:%d:%d:used" % [Catalog.row_id(row), index], 0))
		return "%d/%d" % [value, maximum] if maximum > 0 else str(value)
	return "0"
