extends RefCounted

var _owner: WeakRef
var systems:
	get: return _owner.get_ref()

func _init(owner) -> void:
	_owner = weakref(owner)

func capture(victory: bool, reason := "battle") -> Dictionary:
	var data: Dictionary = systems.profile.data
	var run: Dictionary = data.run
	if not run.active or run.get("history_recorded", false): return {}
	if not data.has("run_history"): data["run_history"] = []
	var record: Dictionary = run.get("outcome", {}).duplicate(true)
	record.merge({"id": data.run_history.size() + 1, "completed_utc": int(Time.get_unix_time_from_system()),
		"victory": victory, "reason": reason, "character_id": int(run.character_id),
		"weapon_id": int(data.get("selected_weapon", 101)), "difficulty": int(run.difficulty),
		"region": int(run.region), "rooms": run.completed_occurrences.size(),
		"elapsed": float(run.counters.get("run:elapsed", 0)), "kills": int(run.counters.get("run:kills", 0)),
		"damage": float(run.counters.get("run:damage", 0)), "max_damage": float(run.counters.get("run:max_damage", 0)),
		"revivals": int(run.counters.get("revivals:used", 0)), "gold_apples": int(run.counters.get("EatGoldAppleCount", 0)),
		"materials": run.materials.duplicate(true), "inventory": run.inventory.duplicate(true),
		"talents": run.talents.duplicate(true), "route": run.route.duplicate(true)}, true)
	record.erase("stage")
	record.erase("experience_claimed")
	data.run_history.append(record)
	run["history_recorded"] = true
	return record.duplicate(true)

func records() -> Array:
	var result: Array = systems.profile.data.get("run_history", []).duplicate(true)
	result.reverse()
	return result

func detail(id: int) -> Dictionary:
	for record in systems.profile.data.get("run_history", []):
		if int(record.id) == id: return record.duplicate(true)
	return {}

func region_summary(record: Dictionary) -> Array:
	var regions: Dictionary = {}
	for layer in record.get("route", {}).get("layers", []):
		if not layer is Dictionary: continue
		var completed: Array = layer.get("completed_ids", [])
		if int(layer.get("selected_id", 0)) <= 0 and completed.is_empty() and not layer.get("complete", false): continue
		var region := int(layer.get("region", 0))
		if region <= 0: continue
		var key := "%d:%d" % [int(layer.get("module_index", 0)), region]
		if not regions.has(key): regions[key] = {"region": region, "rooms": 0, "entered": 0, "module_index": int(layer.get("module_index", 0))}
		regions[key].rooms += completed.size() if not completed.is_empty() else 1 if layer.get("complete", false) else 0
		regions[key].entered += 1
	return regions.values()

func overview() -> Dictionary:
	var characters: Dictionary = {}
	var weapons: Dictionary = {}
	var elapsed := 0.0
	for record in systems.profile.data.get("run_history", []):
		var char_key := str(int(record.character_id))
		var weapon_key := str(int(record.weapon_id))
		characters[char_key] = int(characters.get(char_key, 0)) + 1
		weapons[weapon_key] = int(weapons.get(weapon_key, 0)) + 1
		elapsed += float(record.elapsed)
	var data: Dictionary = systems.profile.data
	var construction := 0
	var talents := 0
	for level in data.buildings.values(): construction += int(level)
	for level in data.talents.values(): talents += int(level)
	return {"runs": systems.stat("runs"), "wins": systems.stat("wins"), "losses": systems.stat("losses"),
		"record_count": data.get("run_history", []).size(), "recorded_seconds": elapsed,
		"characters": characters, "weapons": weapons, "most_used_character": _most_used(characters),
		"most_used_weapon": _most_used(weapons), "construction": construction, "talents": talents,
		"gold_spent": systems.stat("spent:101")}

func _most_used(counts: Dictionary) -> int:
	var selected := 0
	var maximum := 0
	for id in counts:
		if int(counts[id]) > maximum:
			selected = int(id)
			maximum = int(counts[id])
	return selected

static func validate(data: Dictionary) -> bool:
	if data.get("run") is Dictionary and data.run.has("history_recorded") and not data.run.history_recorded is bool: return false
	if not data.has("run_history"): return true
	if not data.run_history is Array: return false
	var ids: Array = []
	for record in data.run_history:
		if not record is Dictionary or not record.get("victory") is bool: return false
		for key in ["id", "completed_utc", "character_id", "weapon_id", "difficulty", "region", "rooms", "elapsed", "kills", "damage", "max_damage", "revivals", "gold_apples"]:
			var value: Variant = record.get(key)
			if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0: return false
			if key not in ["elapsed", "damage", "max_damage"] and float(value) != floor(float(value)): return false
		if not record.get("reason") is String: return false
		if int(record.id) <= 0 or int(record.id) in ids: return false
		ids.append(int(record.id))
		for key in ["materials", "inventory", "talents", "route"]:
			if not record.get(key) is Dictionary: return false
		for key in ["materials", "inventory", "talents"]:
			for value in record[key].values():
				if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0: return false
	return true
