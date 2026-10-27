extends RefCounted

# APK RoadMapNodeIncrementRandomCheck and CheckRoomEnvUnitRandomAppear.
const INCREMENTS := [
	[1, "GoldLode", "70001", "GoldIncrementAppearChance"],
	[2, "MagicpointLode", "70002", "MagicPointIncrementAppearChance"],
	[4, "CollectingMaterials", "10000", "CollectingMaterialsIncrementAppearChance"],
	[8, "MonsterPartner", "13006", "MonsterPartnerSkillSelectorIncrementAppearChance"],
	[16, "SpritesAltar", "13008", "SpritesAltarIncrementAppearChance"]]
const MATERIAL_IDS := ["10017", "10018", "10027", "10028", "10037", "10038", "10047", "10048", "10057"]
const BUTTON_IDS := {
	"EnvUnit_MonoData_BtnDisplayName_CurseAltar": "13004",
	"EnvUnit_MonoData_BtnDisplayName_OldDayAltar": "130041",
	"EnvUnit_MonoData_BtnDisplayName_MonsterPartnerSkillSelector": "13006",
	"EnvUnit_MonoData_BtnDisplayName_SpritesAltar": "13008"}

var systems
var random: Callable

func _init(owner, random_source: Callable = Callable()) -> void:
	systems = owner
	random = random_source if random_source.is_valid() else owner.next_random

func node_increments(key: String, room: Dictionary) -> Dictionary:
	if not systems.profile.data.run.active or key.is_empty(): return {}
	var counters: Dictionary = systems.profile.data.run.counters
	var storage := "node_increments:" + key
	if counters.get(storage) is Dictionary: return counters[storage].duplicate(true)
	var result := roll_increments(room, systems.attributes())
	counters[storage] = result
	return result.duplicate(true)

func ensure_map(campaign) -> void:
	if not systems.profile.data.run.active or campaign.state.is_empty() or int(campaign.state.seed) != int(systems.profile.data.run.seed): return
	if campaign.state.get("region_selection", false): return
	var index := int(campaign.state.layer_index)
	if index < 0 or index >= campaign.state.layers.size(): return
	var current: Dictionary = campaign.state.layers[index]
	for layer_index in campaign.state.layers.size():
		var layer: Dictionary = campaign.state.layers[layer_index]
		if int(layer.get("module_index", 0)) != int(current.get("module_index", 0)) or int(layer.region) != int(current.region): continue
		for id in layer.node_ids:
			var key := "%d:%d:%d" % [int(systems.profile.data.run.seed), layer_index, int(id)]
			node_increments(key, campaign._nodes[int(id)])

func roll_increments(room: Dictionary, attrs: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var options := _options(room.get("IncrementOptions", 0))
	var order := INCREMENTS.duplicate()
	for index in range(order.size() - 1, 0, -1):
		var chosen := int(random.call(index + 1))
		var previous = order[index]
		order[index] = order[chosen]
		order[chosen] = previous
	var chances: Dictionary = systems.catalog.config.get("IncrementRandomAppearChanceDic", {})
	for entry in order:
		if result.size() > 3: break
		if (options & int(entry[0])) != int(entry[0]): continue
		var enabled: bool = int(entry[0]) != 8 or systems.rank(systems.profile.data.buildings, 4) >= 3
		var chance := int(chances.get(entry[1], 0)) + _attribute(attrs, entry[3]) if enabled else 0
		# RandomTools.GetRandomInt includes its maximum; the comparison is strict.
		if int(random.call(1001)) < chance: result[entry[2]] = 0
	return result

func environment_decisions(key: String, room: Dictionary, items: Array) -> Dictionary:
	if not systems.profile.data.run.active or key.is_empty(): return {}
	var counters: Dictionary = systems.profile.data.run.counters
	var storage := "room_environment:" + key
	var stored = counters.get(storage)
	if stored is Dictionary:
		for item in items:
			var id := str(item.get("id", ""))
			if _res_id(item) == "70003" and not id.is_empty() and not stored.has(id):
				stored[id] = preload("res://scripts/domain/camp_social.gd").new(systems).golden_apple_appears(key, id, int(room.get("progress_region", room.get("region", 1))), systems.attributes(), random, int(room.get("region", 1)))
		return stored.duplicate(true)
	var increments := node_increments(key, room)
	var attrs: Dictionary = systems.attributes()
	var result: Dictionary = {}
	for item in items:
		var id := str(item.get("id", ""))
		if _res_id(item) == "70003" and not id.is_empty():
			result[id] = preload("res://scripts/domain/camp_social.gd").new(systems).golden_apple_appears(key, id, int(room.get("progress_region", room.get("region", 1))), attrs, random, int(room.get("region", 1)))
			continue
		var chance := environment_chance(_res_id(item), room, attrs, increments)
		if id.is_empty() or chance < 0: continue
		# Unity Random.Range(int,int) excludes 1000, unlike node increment rolls.
		result[id] = int(random.call(1000)) < chance
	counters[storage] = result
	return result.duplicate(true)

func environment_chance(res_id: String, room: Dictionary, attrs: Dictionary, increments: Dictionary) -> int:
	var chances: Dictionary = systems.catalog.config.get("EnvUnitRandomAppearChanceDic", {})
	var first := int(room.get("FirstOrFinal", room.get("IsFirstOrFinal", 0))) == 1
	var node_type := int(room.get("node_type", room.get("Type", 0)))
	var chance := 0
	if res_id in MATERIAL_IDS:
		chance = int(chances.get("CollectingMaterialsAppearChance", 0)) + _attribute(attrs, "CollectingMaterialsAppearChance")
		if increments.has("10000"): chance += _attribute(attrs, "CollectingMaterialsIncrementAddAppearChance")
		if not first and node_type == 3: chance += _attribute(attrs, "RestRoomCollectingMaterialsAppearChance")
	elif res_id == "70001" or res_id == "70002":
		var gold := res_id == "70001"
		chance = int(chances.get("NodeIncrementGoldMineAppearChance" if gold else "NodeIncrementMagicMineAppearChance", 0))
		chance += _attribute(attrs, "GoldLodeAppearChance" if gold else "MagicPointLodeAppearChance")
		if increments.has(res_id): chance += 1000
		if not gold and node_type == 11: chance += 1000
	elif res_id == "13006" or res_id == "13008":
		var spirit := res_id == "13008"
		if not spirit and systems.rank(systems.profile.data.buildings, 4) < 3: return 0
		chance = int(chances.get("NodeIncrementSpritesAltarAppearChance" if spirit else "NodeIncrementMonsterPartnerAppearChance", 0))
		chance += _attribute(attrs, "SpritesAltarAppearChance" if spirit else "MonsterPartnerSkillSelectorAppearChance")
		if increments.has(res_id): chance += 1000
	elif res_id == "13004" or res_id == "130041":
		var old_day := res_id == "130041"
		var attribute := "OldDayAltarAppearChance" if old_day else "CurseAltarAppearChance"
		chance = int(chances.get(attribute, 0)) + _attribute(attrs, attribute)
		if first or node_type == 12:
			chance = 1000 if _attribute(attrs, "OldDayAltarAppearRegionEnter" if old_day else "CurseAltarAppearRegionEnter") >= 1 else 0
		elif old_day and node_type == 13: chance = 1000
	else: return -1
	return clampi(chance, 0, 1000)

func _res_id(item: Dictionary) -> String:
	var binding: Dictionary = item.get("binding", {})
	var configured := str(binding.get("ConfigId", ""))
	if not configured.is_empty(): return configured
	return str(BUTTON_IDS.get(str(item.get("data", {}).get("UIBtnName", "")), ""))

func _options(value) -> int:
	if value is int or value is float or str(value).is_valid_int(): return int(value)
	var result := 0
	var names := str(value).split(",")
	for entry in INCREMENTS:
		for name in names:
			if name.strip_edges() == entry[1]: result |= int(entry[0])
	return result

func _attribute(attrs: Dictionary, name: String) -> int:
	var value := float(attrs.get(name, 0))
	return int(value) if is_finite(value) else 0
