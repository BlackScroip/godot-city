extends RefCounted

# APK ApplyModify_EnemySpStrengthen; reports/APK_ENEMY_ENHANCEMENTS.md.
var systems
var random: Callable

func _init(owner, random_source: Callable = Callable()) -> void:
	systems = owner
	random = random_source if random_source.is_valid() else owner.next_random

func for_enemy(enemy_id: int) -> Array:
	var row: Dictionary = systems.catalog.find("EnemyData", enemy_id)
	var candidates: Array = systems._difficulty_rows(int(systems.profile.data.run.difficulty)).filter(func(entry): return str(entry.get("DifficultyType", "")) == "EnemySpStrengthen")
	return roll(enemy_id, str(row.get("enemy_rate", "")), systems.attributes(), candidates)

func creation_buffs(enemy_id: int) -> Array:
	if enemy_id in [90001, 90002, 90003]: return []
	var rank := str(systems.catalog.find("EnemyData", enemy_id).get("enemy_rate", ""))
	if rank not in ["Normal", "Elite", "Boss"]: return []
	var result: Array = []
	for row in systems._difficulty_rows(int(systems.profile.data.run.difficulty)):
		var kind := str(row.get("DifficultyType", ""))
		if kind != "AllEnemyStrengthen" and kind != {"Normal": "NormalEnemyStrengthen", "Elite": "EliteStrengthen", "Boss": "BossStrengthen"}[rank]: continue
		for buff in str(row.get("BuffId", "")).split("|", false): result.append(buff)
	return result

func roll(enemy_id: int, rate: String, attrs: Dictionary, candidates: Array) -> Array:
	var result: Array = []
	if enemy_id in [90001, 90002, 90003] or rate not in ["Normal", "Elite"]: return result
	var chance_value := float(attrs.get(rate + "EnemySpStrengthenChance", 0))
	var count_value := float(attrs.get("Max" + rate + "EnemySpStrengthenCount", 0))
	if not is_finite(chance_value) or not is_finite(count_value): return result
	var chance := int(chance_value)
	var count := int(count_value)
	if chance < 1 or count < 1: return result
	var remaining := candidates.duplicate()
	for attempt in count:
		# RandomTools includes both endpoints; the native comparison is <=.
		if int(random.call(1001)) > chance: continue
		var total := 0.0
		for row in remaining: total += _weight(row)
		var chosen := total * int(random.call(1000001)) / 1000000.0
		var cumulative := 0.0
		for index in remaining.size():
			cumulative += _weight(remaining[index])
			if cumulative >= chosen:
				var row: Dictionary = remaining[index]
				result.append({"id": int(row.get("Id", row.get("id", 0))), "name": str(row.get("Name", "")), "buff_id": str(row.get("BuffId", ""))})
				remaining.remove_at(index)
				break
	return result

func _weight(row: Dictionary) -> float:
	return 100.0 / maxi(1, int(row.get("Tier", 0)))
