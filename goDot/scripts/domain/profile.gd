class_name DungeonProfile
extends RefCounted

var data: Dictionary

func _init() -> void:
	data = {
		"version": 1, "saved_utc": 0,
		"materials": {"101": 100}, "stats": {"weapon:101": 1},
		"talents": {}, "character_levels": {"1": 1}, "partners": {},
		"work_levels": {}, "buildings": {}, "recipes": {"70101000": 1, "70101020": 1},
		"equipped_partners": [], "claimed_tasks": [], "claimed_achievements": [],
		"discovered_loot": [], "active_awakenings": [], "equipped_tokens": [],
		"equipped_amplifiers": [], "work": [], "selected_meal": 0, "meal_rank": 0,
		"selected_character": 1, "selected_weapon": 101,
		"run": new_run(), "options": {"volume": 0.7, "fps": 60}
	}

static func new_run(seed_value: int = 0, character: int = 1, health_value: float = 0.0) -> Dictionary:
	return {
		"active": false, "seed": seed_value, "random_step": 0, "character_id": character,
		"current_node": 0, "region": 1, "health": health_value, "max_health": health_value,
		"armor": 0.0, "difficulty": 0, "route": {}, "battle": {}, "counters": {},
		"events": [], "rewards": [], "shops": [], "node_entry_buffs": [],
		"completed_nodes": [], "completed_occurrences": [], "inventory": {}, "talents": {}, "materials": {}
	}

func validate() -> bool:
	if int(data.get("version", 0)) != 1 or not data.get("run") is Dictionary:
		return false
	for key in ["materials", "stats", "talents", "character_levels", "partners", "work_levels", "buildings", "recipes"]:
		if not data.get(key) is Dictionary:
			return false
		for amount in data[key].values():
			if not (amount is int or amount is float) or amount < 0:
				return false
	for key in ["claimed_tasks", "claimed_achievements", "discovered_loot", "work", "equipped_partners", "active_awakenings", "equipped_tokens", "equipped_amplifiers"]:
		if not data.get(key) is Array:
			return false
	var run = data.run
	for key in new_run():
		if not run.has(key):
			return false
	return run.health >= 0 and run.max_health >= run.health and int(run.random_step) >= 0

func restore(snapshot: Dictionary) -> bool:
	var previous = data
	data = snapshot.duplicate(true)
	if not validate():
		data = previous
		return false
	normalize_ids()
	return true

func normalize_ids() -> void:
	for key in ["claimed_tasks", "claimed_achievements", "discovered_loot", "equipped_partners", "active_awakenings", "equipped_tokens", "equipped_amplifiers"]:
		data[key] = data[key].map(func(value): return int(value))
	data.run.completed_nodes = data.run.completed_nodes.map(func(value): return int(value))
	for reward in data.run.rewards:
		reward.choices = reward.choices.map(func(value): return int(value))
