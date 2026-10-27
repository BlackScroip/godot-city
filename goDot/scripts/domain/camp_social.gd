extends RefCounted

var _owner: WeakRef
var systems:
	get: return _owner.get_ref()

func _init(owner) -> void:
	_owner = weakref(owner)

func gift_status(npc_id: int) -> Dictionary:
	var row: Dictionary = systems.catalog.find("NPCData", npc_id)
	var talks := DungeonCatalog.ids(row.get("relationship_talkid", ""))
	var level: int = systems.stat("relationship:" + str(npc_id))
	if talks.is_empty() or systems.profile.data.run.active: return systems._fail("该NPC当前不可赠礼")
	var function_id := int(row.get("relationship_entryid", 0))
	var available: Dictionary = systems.npc_function_status(function_id)
	if not available.success: return available
	if level >= talks.size(): return systems._fail("好感度已满。")
	if systems.material(106) < 1: return systems._fail("需要金苹果")
	return {"success": true, "function_id": function_id, "level": level,
		"talk_id": int(talks[level]), "story": "talkcfg_npc_" + str(talks[level])}

func visitor_choices(level: int, selected_character: int, random_source: Callable) -> Array:
	var result: Array = []
	if level < 2: return result
	var candidates: Array = []
	for row in systems.catalog.rows("CharData"):
		if str(row.get("available_state", "Normal")) != "Normal" or int(row.id) == selected_character: continue
		if visitor_npc_id(int(row.id)) == 0: continue
		candidates.append(int(row.id))
	var thresholds: Array = systems.catalog.config.get("RandomPlayerSeatList", [0, 50, 75])
	var threshold := int(thresholds[mini(level - 1, thresholds.size() - 1)])
	for seat in mini(level, 3):
		if candidates.is_empty(): break
		if int(random_source.call(101)) > threshold: continue
		var index := clampi(int(random_source.call(candidates.size())), 0, candidates.size() - 1)
		result.append({"seat": seat + 1, "character_id": candidates[index]})
		candidates.remove_at(index)
	return result

func visitor_npc_id(character_id: int) -> int:
	if not systems.catalog.find("NPCData", character_id).is_empty(): return character_id
	var prefab := str(systems.catalog.find("CharData", character_id).get("main_city_npc_prefab", ""))
	if prefab.is_empty(): return 0
	for row in systems.catalog.rows("CharData"):
		if str(row.get("main_city_npc_prefab", "")) == prefab and not systems.catalog.find("NPCData", int(row.id)).is_empty(): return int(row.id)
	return 0

func golden_apple_appears(room_key: String, marker_id: String, region: int, attrs: Dictionary, random_source: Callable, node_level := 1) -> bool:
	var run: Dictionary = systems.profile.data.run
	var key := "gold-apple:room:" + room_key + ":" + marker_id
	if run.counters.has(key): return bool(run.counters[key])
	var region_key := "gold-apple:region:" + str(region)
	var accepted := false
	if systems.rank(systems.profile.data.buildings, 2) >= 2 and not run.counters.get(region_key, false):
		var chance := 50.0 + float(attrs.get("GoldAppleAppearChance", 0)) + (25.0 + float(attrs.get("GoldAppleAppearChanceFactor", 0))) * maxi(0, node_level - 1)
		accepted = float(random_source.call(1001)) <= chance
		if accepted: run.counters[region_key] = true
	run.counters[key] = accepted
	return accepted
