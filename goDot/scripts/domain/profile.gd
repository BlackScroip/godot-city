class_name DungeonProfile
extends RefCounted

var data: Dictionary

func _init() -> void:
	data = {
		"version": 1, "saved_utc": 0,
		"materials": {"101": 100}, "stats": {"weapon:101": 1},
		"talents": {}, "marked_character_talents": [], "character_levels": {"1": 1}, "partners": {},
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
	if not data.has("camp_schema_version"):
		for field in ["char_equipped_tokens", "char_token_amplifier_slots", "token_amplifier_unlocked_slots", "token_amplifier_presets", "amplifier_draw_state"]:
			if data.has(field): return false
	if not preload("res://scripts/domain/relationship_tokens.gd").validate_state(data): return false
	if not preload("res://scripts/domain/camp_history.gd").validate(data): return false
	if data.has("extra_challenges") and not preload("res://scripts/domain/extra_challenges.gd").validate_state(data.extra_challenges): return false
	if data.has("ad_rewards") and not _ad_rewards_state(data.ad_rewards): return false
	if data.has("dialogue_state") and not _dialogue_state(data.dialogue_state): return false
	for field in ["selected_character", "selected_weapon"]:
		if data.has(field) and not _integer(data[field], 1): return false
	for field in ["selected_meal", "meal_rank"]:
		if data.has(field) and not _integer(data[field]): return false
	if data.has("selected_difficulty") and (not _integer(data.selected_difficulty) or data.selected_difficulty > 10): return false
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
	if data.has("selected_weapons"):
		if not data.selected_weapons is Dictionary: return false
		for key in data.selected_weapons:
			var weapon = data.selected_weapons[key]
			if not str(key).is_valid_int() or int(key) < 1 or not _number(weapon) or weapon < 1 or float(weapon) != floor(float(weapon)): return false
	if data.has("fashion_owned"):
		if not data.fashion_owned is Array or not _ids(data.fashion_owned): return false
	if data.has("marked_character_talents"):
		if not data.marked_character_talents is Array or not _ids(data.marked_character_talents): return false
		for id in data.marked_character_talents:
			if int(id) <= 0: return false
	if data.has("fashion_equipped"):
		if not data.fashion_equipped is Dictionary: return false
		for key in data.fashion_equipped:
			var fashion = data.fashion_equipped[key]
			if not str(key).is_valid_int() or int(key) < 1 or not _number(fashion) or fashion < 1 or float(fashion) != floor(float(fashion)): return false
	var assigned_partners: Array = []
	var assigned_work: Array = []
	for job in data.work:
		if not job is Dictionary: return false
		for key in ["work_id", "partner_id", "started_utc", "due_utc", "material_id", "reward"]:
			if not _number(job.get(key)) or job[key] < 0 or float(job[key]) != floor(float(job[key])): return false
		if job.work_id <= 0 or job.material_id <= 0 or job.reward <= 0: return false
		if int(job.partner_id) == 0 and int(job.get("economy_version", 0)) != 2: return false
		if int(job.work_id) in assigned_work or (int(job.partner_id) > 0 and int(job.partner_id) in assigned_partners): return false
		if job.has("level") and (not _number(job.level) or job.level < 0 or float(job.level) != floor(float(job.level))): return false
		for key in ["quantity", "claimed_quantity", "cycle_seconds", "economy_version", "prepaid_quantity"]:
			if job.has(key) and (not _number(job[key]) or job[key] < 0 or float(job[key]) != floor(float(job[key]))): return false
		if int(job.get("quantity", 1)) < 1 or int(job.get("quantity", 1)) > 24: return false
		if int(job.get("economy_version", 0)) not in [0, 2] or int(job.get("prepaid_quantity", 0)) > 1: return false
		if int(job.get("claimed_quantity", 0)) >= int(job.get("quantity", 1)): return false
		if job.has("cycle_seconds") and int(job.cycle_seconds) < 1: return false
		if int(job.get("quantity", 1)) > 1 and not job.has("cycle_seconds"): return false
		assigned_work.append(int(job.work_id))
		assigned_partners.append(int(job.partner_id))
	if data.has("work_claims"):
		if not data.work_claims is Dictionary: return false
		for key in ["day", "count"]:
			if not _number(data.work_claims.get(key)) or float(data.work_claims[key]) != floor(float(data.work_claims[key])): return false
		if data.work_claims.count < 0: return false
	for field in ["meal_selection", "purchased_meals", "last_meals"]:
		if not data.has(field): continue
		if not data[field] is Dictionary: return false
		if field != "purchased_meals" and data[field].size() > 3: return false
		for key in data[field]:
			if not str(key).is_valid_int() or int(key) < 1: return false
			var level = data[field][key]
			if not _number(level) or level < 1 or float(level) != floor(float(level)): return false
	if data.has("meal_purchased") and not data.meal_purchased is bool: return false
	if data.has("unlocked_camp_decorations"):
		if not data.unlocked_camp_decorations is Array or not _ids(data.unlocked_camp_decorations): return false
	if data.has("camp_decorations"):
		if not data.camp_decorations is Dictionary: return false
		for slot_id in data.camp_decorations:
			var decoration = data.camp_decorations[slot_id]
			if not str(slot_id).is_valid_int() or int(slot_id) <= 0: return false
			if not _number(decoration) or decoration <= 0 or float(decoration) != floor(float(decoration)): return false
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
		if reward.has("locked_ids") and (not reward.locked_ids is Array or not _ids(reward.locked_ids)): return false
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
			for key in ["experience", "effective_experience", "vouchers", "elapsed", "kills", "damage", "max_damage"]:
				if outcome.has(key) and (not _number(outcome[key]) or outcome[key] < 0): return false
			for key in ["talents", "inventory"]:
				if not outcome.has(key): continue
				if not outcome[key] is Dictionary: return false
				for amount in outcome[key].values():
					if not _number(amount) or amount < 0: return false
	return run.health >= 0 and run.max_health >= run.health and int(run.random_step) >= 0

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _integer(value: Variant, minimum := 0) -> bool:
	return _number(value) and value >= minimum and value <= 2147483647 and float(value) == floor(float(value))

static func _ad_rewards_state(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.is_empty(): return true
	if not _integer(value.get("day"), -2147483648) or not _integer(value.get("skips")) or value.skips > 3: return false
	if not value.get("counts") is Dictionary or not value.get("receipts") is Array: return false
	if not _integer(value.get("reset_version", 0)) or value.get("reset_version", 0) > 1: return false
	for point in value.counts:
		if not point is String or point.is_empty() or not _integer(value.counts[point]): return false
	for receipt in value.receipts:
		if not receipt is String or receipt.is_empty(): return false
	return true

static func _dialogue_state(value: Variant) -> bool:
	if not value is Dictionary: return false
	if value.is_empty(): return true
	if not _integer(value.get("function_id"), 1) or not _integer(value.get("index")): return false
	if value.has("npc_id") and not _integer(value.npc_id, 1): return false
	if not value.get("lines") is Array or value.get("stage", "story") not in ["story", "choices"]: return false
	for line in value.lines:
		if not line is Dictionary: return false
	var maximum = maxi(0, value.lines.size() - 1) if value.get("stage", "story") == "choices" else value.lines.size() - 1
	return value.index <= maximum

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
	preload("res://scripts/domain/relationship_tokens.gd").normalize_saved_ids(data)
	for field in ["selected_character", "selected_weapon", "selected_difficulty", "selected_meal", "meal_rank"]:
		if data.has(field): data[field] = int(data[field])
	for field in ["function_id", "npc_id", "index"]:
		if data.get("dialogue_state", {}).has(field): data.dialogue_state[field] = int(data.dialogue_state[field])
	var ad_rewards: Dictionary = data.get("ad_rewards", {})
	if not ad_rewards.is_empty():
		for field in ["day", "skips", "reset_version"]:
			if ad_rewards.has(field): ad_rewards[field] = int(ad_rewards[field])
		for point in ad_rewards.counts: ad_rewards.counts[point] = int(ad_rewards.counts[point])
	var marks: Array = []
	for id in data.get("marked_character_talents", []):
		if not marks.has(int(id)): marks.append(int(id))
	data["marked_character_talents"] = marks
	if data.has("fashion_owned"): data.fashion_owned = data.fashion_owned.map(func(value): return int(value))
	if data.has("fashion_equipped"):
		for key in data.fashion_equipped: data.fashion_equipped[key] = int(data.fashion_equipped[key])
	for field in ["meal_selection", "purchased_meals", "last_meals"]:
		if not data.has(field): continue
		for key in data[field]: data[field][key] = int(data[field][key])
	for key in ["claimed_tasks", "claimed_achievements", "discovered_loot", "equipped_partners", "active_awakenings", "equipped_tokens", "equipped_amplifiers"]:
		data[key] = data[key].map(func(value): return int(value))
	if data.has("unlocked_camp_decorations"): data.unlocked_camp_decorations = data.unlocked_camp_decorations.map(func(value): return int(value))
	data.run.completed_nodes = data.run.completed_nodes.map(func(value): return int(value))
	for reward in data.run.rewards:
		reward.choices = reward.choices.map(func(value): return int(value))
		if reward.has("locked_ids"): reward.locked_ids = reward.locked_ids.map(func(value): return int(value))
	for job in data.work:
		for key in ["work_id", "partner_id", "started_utc", "due_utc", "material_id", "reward", "level", "quantity", "claimed_quantity", "cycle_seconds", "economy_version", "prepaid_quantity"]:
			if job.has(key): job[key] = int(job[key])
