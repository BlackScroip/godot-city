extends RefCounted

# Source branches and ARM64 offsets: reports/APK_RESOURCE_DROP_FORMULAS.md.
var systems
var random: Callable

func _init(owner, random_source: Callable = Callable()) -> void:
	systems = owner
	random = random_source if random_source.is_valid() else owner.next_random

func _roll(limit: int) -> int:
	return int(random.call(maxi(1, limit)))

func _round_even(value: float) -> int:
	var lower := floori(value)
	if is_equal_approx(value - lower, 0.5): return lower if lower % 2 == 0 else lower + 1
	return roundi(value)

func resource_amount(data: Dictionary, depth: int) -> int:
	var spread := float(data.get("DropRandomFactor", 0)) / 1000.0
	var multiplier := 1.0 - spread + 2.0 * spread * _roll(1000001) / 1000000.0
	return maxi(1, int(float(data.get("DropBase", 0)) * (1.0 + float(data.get("DropLevelDepthFactor", 0)) * depth / 1000.0) * multiplier))

func _item(result: Array, id: int) -> void:
	if id > 0: result.append({"id": id, "amount": 1, "material": false})

func _pool(result: Array, field: String, count: int = 1) -> void:
	var excluded: Array = []
	for entry in result:
		if not entry.material: excluded.append(int(entry.id))
	for id in systems.roll_pool(int(systems.catalog.config.get(field, 0)), count, 0, excluded):
		_item(result, int(id))

func _resources(result: Array, pool: Dictionary, depth: int, attrs: Dictionary, enemy_rate := "") -> void:
	var rows: Array = []
	for field in ["GoldData", "MagicPointData", "MineralData"]:
		if pool.get(field) is Dictionary: rows.append(pool[field])
	rows.append_array(pool.get("OtherRewardDataList", []))
	for row in rows:
		var id := int(row.get("DropMaterialType", 0))
		var chance := int(row.get("DropChance", 0))
		var factor := 1.0
		match id:
			101:
				factor = 1.0 + float(attrs.get("DropGoldFactor", 0)) / 1000.0
				if not enemy_rate.is_empty():
					factor *= 1.0 + float(attrs.get("DropGoldMonsterFactor", 0)) / 1000.0
					chance += int(attrs.get("DropGoldChanceAdd", 0))
			102:
				factor = 1.0 + float(attrs.get("DropMagicPointFactor", 0)) / 1000.0
				if not enemy_rate.is_empty():
					factor += float(attrs.get("DropMagicPointFactorAddOnCompleteRegion", 0)) * maxi(0, int(systems.profile.data.run.region) - 1) / 1000.0
					chance += int(attrs.get("DropMagicPointChanceAdd", 0))
			103:
				factor = 1.0 + float(attrs.get("DropMineralMatFactor", 0)) / 1000.0
				if not enemy_rate.is_empty(): chance += int(attrs.get("DropMineralMatChanceAdd_" + enemy_rate, 0))
			90002: factor = 1.0 + float(attrs.get("DropFreeCoinFactor", 0)) / 1000.0
		var amount := int(resource_amount(row, depth) * factor)
		# GetMonsterResDrop initializes mineral count to one before adding the roll.
		if id == 103 and not enemy_rate.is_empty() and row == pool.get("MineralData", {}): amount += 1
		# APK uses Range(0,1001) and a strict comparison for material drops.
		if _roll(1001) < chance and amount > 0 and id > 0:
			result.append({"id": id, "amount": amount, "material": true})

func monster(rate: String, depth: int, attrs: Dictionary, mohua: bool = false) -> Array:
	var result: Array = []
	var index := ["Normal", "Elite", "Boss"].find(rate)
	if index < 0: return result
	var cfg: Dictionary = systems.catalog.config
	var resource_key := "DefaultBossDropResPoolData" if rate == "Boss" else "DefaultEliteDropResPoolData" if rate == "Elite" else "DefaultEnemyDropResPoolData"
	_resources(result, cfg.get(resource_key, {}), depth, attrs, rate)
	if _roll(1001) < int(attrs.get("DropFreeCoinChanceAdd_" + rate, 0)):
		result.append({"id": 90002, "amount": 1, "material": true})
	if mohua and rate in ["Normal", "Elite"]:
		var essence_counts := str(cfg.get("MohuaEnemyDropMonsterEssence", "1|4|10")).split("|", false)
		if essence_counts.size() != 3: essence_counts = PackedStringArray(["1", "4", "10"])
		result.append({"id": 107, "amount": int(essence_counts[index]), "material": true})
	var token_counts := str(cfg.get("EnemyDropRelationshipTokenUpgradeItem_ByDifficulty", {}).get(str(int(systems.profile.data.run.difficulty)), "")).split("|", false)
	if token_counts.size() == 3 and int(token_counts[index]) > 0:
		result.append({"id": 108, "amount": int(token_counts[index]), "material": true})
	if rate == "Elite" and int(attrs.get("EliteDropExtraRelicBag", 0)) >= 1:
		_item(result, int(cfg.get("AbilityItem_SelectLootItem_Low", 0)))
	if rate == "Boss":
		var extra := int(attrs.get("BossDropExtraChance", 0))
		var guaranteed := int(extra / 1000.0)
		var count := guaranteed + (1 if _roll(1001) <= extra - guaranteed * 1000 else 0)
		if count > 0: _pool(result, "DefaultAbilityItemLootPoolId", count)
	var chances: Array = cfg.get("EnemyExtraDropLowRareAbilityItemChanceArray", [])
	var counts: Array = cfg.get("EnemyExtraDropLowRareAbilityItemMaxCountArray", [])
	var chance := int(chances[index]) if index < chances.size() else 0
	# HandleMonsterDrop applies the rank modifier before its rank-specific cap.
	chance = mini(200 if rate == "Normal" else 1000, _round_even(chance * (1.0 + int(attrs.get("EnemyDropLowAbilityChance_" + rate, 0)) / 1000.0)))
	for attempt in maxi(0, int(counts[index]) if index < counts.size() else 0):
		var roll := _roll(1001)
		if chance > 0 and roll <= chance: _pool(result, "LowRareAbilityItemLootPoolId")
	var recover := int(attrs.get("EnemyDropRecoverRate" if rate == "Normal" else "EliteEnemyDropRecoverRate", 0)) if rate != "Boss" else 0
	if 1 + _roll(1000) <= recover: _pool(result, "DefaultRecoverItemLootPoolId")
	_amplifiers(result, index, attrs)
	return result

func _amplifiers(result: Array, rank: int, attrs: Dictionary) -> void:
	var run: Dictionary = systems.profile.data.run
	var level := int(run.difficulty)
	var encoded := str(systems.catalog.config.get("AmplifyDropByTierAndDifficulty", {}).get(str(level), ""))
	if level < 6 or encoded.is_empty(): return
	var rates := encoded.split("|", false)
	for tier_index in int(rates.size() / 3.0):
		var chance := int(rates[tier_index * 3 + rank])
		chance = int(chance * systems.chaos_drop_rate_multiplier())
		chance = int(chance * maxf(0.0, 1.0 + float(attrs.get("BlessingPlusAmplifyDropRateMulti", 0)) / 1000.0))
		if chance < 1 or 1 + _roll(1000) > chance: continue
		var tier := "Tier" + str(tier_index + 1)
		var options: Array = systems.catalog.rows("RelationshipAmplifyData").filter(func(row): return str(row.rare) == tier)
		if not options.is_empty(): result.append({"id": int(options[_roll(options.size())].id), "amount": 1, "material": true})

func reward_slime(enemy_id: int, event: String, attrs: Dictionary) -> Array:
	if enemy_id not in [90001, 90002, 90003] or event not in ["hit", "dead"]: return []
	var pool: Dictionary = systems.catalog.config.get("DefaultRewardSlimeDropResPoolData", {})
	var row: Dictionary = pool.get("GoldData", {}) if enemy_id == 90001 else pool.get("MagicPointData", {})
	if enemy_id == 90003:
		row = {}
		for other in pool.get("OtherRewardDataList", []):
			if int(other.get("DropMaterialType", 0)) == 90002: row = other; break
	var base := int(float(row.get("DropBase", 0)) * (0.05 if event == "hit" else 0.8))
	var attribute: String = {90001: "DropGoldFactor", 90002: "DropMagicPointFactor", 90003: "DropFreeCoinFactor"}[enemy_id]
	# The native slime branch adds one to magic's existing 1000 baseline.
	var factor := (2.0 if enemy_id == 90002 else 1.0) + float(attrs.get(attribute, 0)) / 1000.0
	var amount := int(base * factor)
	return [{"id": int(row.get("DropMaterialType", 0)), "amount": amount, "material": true}] if amount > 0 and not row.is_empty() else []

func completion_quality(room: Dictionary, attrs: Dictionary, outcome: Dictionary = {}) -> String:
	var flow := str(room.get("flow", room.get("Flow", "")))
	if flow == "Entrance":
		return ["Normal", "Unusual", "Luxury"][clampi(int(attrs.get("RegionEnterTreasureBoxType", 0)), 0, 2)]
	if flow == "Treasure": return str(room.get("TreasureBoxType", "Normal"))
	var fight_type := str(room.get("FightType", ""))
	if fight_type in ["TimeLimit", "DodgeBattle", "ProtectTarget", "Endless"]:
		if outcome.is_empty(): return "None"
		var data: Dictionary = room.get("FightData", {})
		for rank in [3, 2, 1]:
			if rank == 3 and int(attrs.get("ChallengeGoldUnlock", 0)) <= 0: continue
			var passed := false
			match fight_type:
				"TimeLimit": passed = int(outcome.get("elapsed", 2147483647)) <= int(data.get("RewardTimeLimit_Lv" + str(rank), 0)) + int(attrs.get("TimeLimitRoomAddTime", 0))
				"DodgeBattle": passed = int(outcome.get("hits", 0)) < int(data.get("BeHitCount_Lv" + str(rank), 0)) + int(attrs.get("DodgeRoomAddDodgeCount", 0))
				"ProtectTarget": passed = float(outcome.get("target_hp", 0)) > 0 if rank == 1 else float(outcome.get("target_hp", 0)) >= clampi(int(data.get("RemainTargetHp_Lv" + str(rank), 100)) - int(attrs.get("RemainTargetAddHp", 0)), 10, 100)
				"Endless": passed = int(outcome.get("kills", 0)) >= int(data.get("KillCount_Lv" + str(rank), 0))
			if passed: return ["Normal", "Unusual", "Luxury"][rank - 1]
		return "None"
	if str(room.get("FightType", "")) != "Regular": return ""
	match str(room.get("EnemyClass", "")):
		"Elite": return "Unusual"
		"Boss": return "Curse_Final" if room.get("FinalBoss", false) else "Curse"
	return "Normal"

func treasure(quality: String, treasure_id: int, first_node: bool, first_region: bool, depth: int, attrs: Dictionary) -> Array:
	var result: Array = []
	if quality not in ["Normal", "Unusual", "Luxury", "Curse", "Curse_Final"]: return result
	var cfg: Dictionary = systems.catalog.config
	if quality == "Normal":
		_pool(result, "LowRareAbilityItemLootPoolId")
		if not (first_node and first_region):
			if _roll(1001) <= 500: _pool(result, "DefaultRecoverItemLootPoolId")
			elif _roll(1001) <= 500: _pool(result, "DefaultArmorItemLootPoolId")
	if quality in ["Normal", "Unusual", "Luxury"]:
		var extra := int(attrs.get("TreasureBoxDropLowAbilityChance_" + quality, 0))
		if extra > 0 and _roll(1001) <= extra: _pool(result, "LowRareAbilityItemLootPoolId")
	for bag in maxi(0, 1 + int(attrs.get("ExtraRelicBagCount", 0))):
		if quality == "Unusual":
			# RandomTools.GetRandomInt includes its maximum; Unity Range excludes it.
			var high := _roll(1001) <= int(attrs.get("DropLuxuryBag", 0))
			_item(result, int(cfg.get("AbilityItem_SelectLootItem_High" if high else "AbilityItem_SelectLootItem_Middle", 0)))
			var upgrade := int(attrs.get("NormalBagUpgradeToHighBag", 0))
			if upgrade > 0:
				for index in range(result.size() - 1, -1, -1):
					var entry: Dictionary = result[index]
					if not entry.material and int(entry.id) == int(cfg.get("AbilityItem_SelectLootItem_Middle", 0)) and _roll(1001) <= upgrade:
						entry.id = int(cfg.get("AbilityItem_SelectLootItem_High", 0))
		elif quality in ["Luxury", "Curse"]:
			_item(result, int(cfg.get("AbilityItem_SelectLootItem_High", 0)))
	if quality == "Curse" and int(attrs.get("BossTreasureBoxDropExtraHighLoot", 0)) >= 1:
		_item(result, int(cfg.get("AbilityItem_SelectLootItem_High", 0)))
	if treasure_id == 1 and not first_node and quality != "Curse_Final":
		if _roll(1002) <= int(cfg.get(quality + "TreasureBoxDropSelectCharaItemChance", 0)):
			_item(result, int(cfg.get("AbilityItem_CharaTalentItem_Super" if quality == "Curse" else "AbilityItem_CharaTalentItem_Normal", 0)))
	if quality == "Curse":
		for scroll in maxi(0, int(attrs.get("BossTreasureBoxDropExtraSuperTalentItem", 0))):
			_item(result, int(cfg.get("AbilityItem_CharaTalentItem_Super", 0)))
	var extra_scroll := int(attrs.get("OpenTreasureBoxExtraGetSelectChara_Low", 0))
	if _roll(1002) <= extra_scroll:
		_item(result, int(cfg.get("AbilityItem_CharaTalentItem_Curse", 0)))
	if treasure_id == 1 and first_node and first_region and quality in ["Unusual", "Luxury"]:
		_item(result, int(cfg.get("AbilityItem_CharaTalentItem_Normal" if quality == "Unusual" else "AbilityItem_CharaTalentItem_Super", 0)))
	_resources(result, cfg.get("TreasureBoxResDropData_" + quality, {}), depth, attrs)
	return result
