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
		"auto_attack_mode": "normal",
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
	if not _number(data.get("version")) or data.version != 1 or not data.get("run") is Dictionary:
		return false
	for key in ["materials", "stats", "talents", "character_levels", "partners", "work_levels", "buildings", "recipes"]:
		if not data.get(key) is Dictionary:
			return false
		for amount in data[key].values():
			if not _number(amount) or amount < 0:
				return false
	for key in ["claimed_tasks", "claimed_achievements", "discovered_loot", "work", "equipped_partners", "active_awakenings", "equipped_tokens", "equipped_amplifiers"]:
		if not data.get(key) is Array:
			return false
	for key in ["claimed_tasks", "claimed_achievements", "discovered_loot", "equipped_partners", "active_awakenings", "equipped_tokens", "equipped_amplifiers"]:
		if not _ids(data[key]): return false
	var assigned_partners: Array = []
	var assigned_work: Array = []
	for job in data.work:
		if not job is Dictionary: return false
		for key in ["work_id", "partner_id", "started_utc", "due_utc", "material_id", "reward"]:
			if not _number(job.get(key)) or job[key] < 0 or float(job[key]) != floor(float(job[key])): return false
		if job.work_id <= 0 or job.partner_id <= 0 or job.material_id <= 0 or job.reward <= 0: return false
		if int(job.work_id) in assigned_work or int(job.partner_id) in assigned_partners: return false
		if job.has("level") and (not _number(job.level) or job.level < 0 or float(job.level) != floor(float(job.level))): return false
		for key in ["quantity", "claimed_quantity", "cycle_seconds"]:
			if job.has(key) and (not _number(job[key]) or job[key] < 0 or float(job[key]) != floor(float(job[key]))): return false
		if int(job.get("quantity", 1)) < 1 or int(job.get("quantity", 1)) > 5: return false
		if int(job.get("claimed_quantity", 0)) >= int(job.get("quantity", 1)): return false
		if job.has("cycle_seconds") and int(job.cycle_seconds) < 1: return false
		if int(job.get("quantity", 1)) > 1 and not job.has("cycle_seconds"): return false
		assigned_work.append(int(job.work_id))
		assigned_partners.append(int(job.partner_id))
	var run = data.run
	var defaults = new_run()
	for key in defaults:
		if not run.has(key):
			return false
		if defaults[key] is int or defaults[key] is float:
			if not _number(run[key]): return false
		elif typeof(run[key]) != typeof(defaults[key]):
			return false
	for key in ["inventory", "talents", "materials"]:
		for amount in run[key].values():
			if not _number(amount) or amount < 0: return false
	if not _ids(run.completed_nodes): return false
	for key in ["events", "shops", "node_entry_buffs"]:
		for entry in run[key]:
			if not entry is Dictionary: return false
	for reward in run.rewards:
		if not reward is Dictionary or not reward.get("key") is String or not reward.get("choices") is Array: return false
		if not _ids(reward.choices): return false
	if run.armor < 0 or run.difficulty < 0 or run.difficulty > 10: return false
	if run.has("outcome"):
		if not run.outcome is Dictionary: return false
		var outcome: Dictionary = run.outcome
		if not outcome.is_empty():
			if run.active or not outcome.get("victory") is bool or outcome.get("stage") not in ["share", "summary", "rewards"]: return false
			for key in ["character_id", "region", "rooms", "revivals"]:
				if not _number(outcome.get(key)) or outcome[key] < 0: return false
			if not outcome.get("materials") is Dictionary: return false
			for amount in outcome.materials.values():
				if not _number(amount) or amount < 0: return false
			for key in ["experience", "effective_experience", "vouchers"]:
				if outcome.has(key) and (not _number(outcome[key]) or outcome[key] < 0): return false
	return run.health >= 0 and run.max_health >= run.health and int(run.random_step) >= 0

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _ids(values: Array) -> bool:
	for value in values:
		if not _number(value) or value < 0 or float(value) != floor(float(value)): return false
	return true

func restore(snapshot: Dictionary) -> bool:
	var previous = data
	data = snapshot.duplicate(true)
	if not validate():
		data = previous
		return false
	normalize_ids()
	data["auto_attack_mode"] = attack_mode(data)
	return true

static func attack_mode(value: Dictionary) -> String:
	var mode = value.get("auto_attack_mode", "normal" if value.get("auto_attack", true) else "off")
	return str(mode) if mode in ["normal", "heavy", "off"] else "normal"

func normalize_ids() -> void:
	for key in ["claimed_tasks", "claimed_achievements", "discovered_loot", "equipped_partners", "active_awakenings", "equipped_tokens", "equipped_amplifiers"]:
		data[key] = data[key].map(func(value): return int(value))
	data.run.completed_nodes = data.run.completed_nodes.map(func(value): return int(value))
	for reward in data.run.rewards:
		reward.choices = reward.choices.map(func(value): return int(value))
	for job in data.work:
		for key in ["work_id", "partner_id", "started_utc", "due_utc", "material_id", "reward", "level", "quantity", "claimed_quantity", "cycle_seconds"]:
			if job.has(key): job[key] = int(job[key])
