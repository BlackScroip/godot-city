extends RefCounted

# Source branches and ARM64 offsets: reports/APK_RESOURCE_DROP_FORMULAS.md.
var systems
var random: Callable

func _init(owner, random_source: Callable = Callable()) -> void:
	systems = owner
	random = random_source if random_source.is_valid() else owner.next_random

func _roll(limit: int) -> int:
	return int(random.call(maxi(1, limit)))

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
		var amount := int(resource_amount(row, depth) * maxf(0.0, factor))
		# APK uses Range(0,1001) and a strict comparison for material drops.
		if _roll(1001) < chance and amount > 0 and id > 0:
			result.append({"id": id, "amount": amount, "material": true})

func monster(rate: String, depth: int, attrs: Dictionary) -> Array:
	var result: Array = []
	var index := ["Normal", "Elite", "Boss"].find(rate)
	if index < 0: return result
	var cfg: Dictionary = systems.catalog.config
	var resource_key := "DefaultBossDropResPoolData" if rate == "Boss" else "DefaultEliteDropResPoolData" if rate == "Elite" else "DefaultEnemyDropResPoolData"
	_resources(result, cfg.get(resource_key, {}), depth, attrs, rate)
	if rate == "Elite" and int(attrs.get("EliteDropExtraRelicBag", 0)) >= 1:
		_item(result, int(cfg.get("AbilityItem_SelectLootItem_Low", 0)))
	if rate == "Boss" and _roll(1001) <= int(attrs.get("BossDropExtraChance", 0)):
		_pool(result, "DefaultAbilityItemLootPoolId", 1 + int(attrs.get("BossDropCount", 0)))
	var chances: Array = cfg.get("EnemyExtraDropLowRareAbilityItemChanceArray", [])
	var counts: Array = cfg.get("EnemyExtraDropLowRareAbilityItemMaxCountArray", [])
	var chance := int(chances[index]) if index < chances.size() else 0
	chance += int(attrs.get("EnemyDropLowAbilityChance_" + rate, 0))
	if rate == "Normal": chance = maxi(100, chance)
	for attempt in maxi(0, int(counts[index]) if index < counts.size() else 0):
		if _roll(1001) <= chance: _pool(result, "LowRareAbilityItemLootPoolId")
	var recover := int(attrs.get("EnemyDropRecoverRate" if rate == "Normal" else "EliteEnemyDropRecoverRate", 0)) if rate != "Boss" else 0
	if 1 + _roll(1000) <= recover: _pool(result, "DefaultRecoverItemLootPoolId")
	return result

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
			var high := _roll(1000) <= int(attrs.get("DropLuxuryBag", 0))
			_item(result, int(cfg.get("AbilityItem_SelectLootItem_High" if high else "AbilityItem_SelectLootItem_Middle", 0)))
			var upgrade := int(attrs.get("NormalBagUpgradeToHighBag", 0))
			if upgrade > 0:
				for index in range(result.size() - 1, -1, -1):
					var entry: Dictionary = result[index]
					if not entry.material and int(entry.id) == int(cfg.get("AbilityItem_SelectLootItem_Middle", 0)) and _roll(1000) <= upgrade:
						entry.id = int(cfg.get("AbilityItem_SelectLootItem_High", 0))
		elif quality in ["Luxury", "Curse"]:
			_item(result, int(cfg.get("AbilityItem_SelectLootItem_High", 0)))
			if quality == "Curse" and int(attrs.get("BossTreasureBoxDropExtraHighLoot", 0)) >= 1:
				_item(result, int(cfg.get("AbilityItem_SelectLootItem_High", 0)))
	if treasure_id == 1 and not first_node and quality != "Curse_Final":
		if _roll(1001) <= int(cfg.get(quality + "TreasureBoxDropSelectCharaItemChance", 0)):
			_item(result, int(cfg.get("AbilityItem_CharaTalentItem_Super" if quality == "Curse" else "AbilityItem_CharaTalentItem_Normal", 0)))
	var extra_scroll := int(attrs.get("OpenTreasureBoxExtraGetSelectChara_Low", 0))
	if extra_scroll > 0 and _roll(1001) <= extra_scroll:
		_item(result, int(cfg.get("AbilityItem_CharaTalentItem_Curse", 0)))
	if treasure_id == 1 and first_node and first_region and quality in ["Unusual", "Luxury"]:
		_item(result, int(cfg.get("AbilityItem_CharaTalentItem_Normal" if quality == "Unusual" else "AbilityItem_CharaTalentItem_Super", 0)))
	_resources(result, cfg.get("TreasureBoxResDropData_" + quality, {}), depth, attrs)
	return result
