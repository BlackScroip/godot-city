extends RefCounted

var systems

func _init(source) -> void:
	systems = source

func _state() -> Dictionary:
	var data: Dictionary = systems.profile.data
	var day = int(int(systems.utc_now.call()) / 86400)
	if not data.get("ad_rewards", {}) is Dictionary: data.ad_rewards = {}
	if int(data.get("ad_rewards", {}).get("day", -1)) != day:
		data.ad_rewards = {"day": day, "counts": {}, "skips": 0, "receipts": []}
	return data.ad_rewards

func free_skips() -> int:
	return maxi(0, 3 - int(_state().skips))

func quote(context: Dictionary) -> Dictionary:
	var kind = str(context.get("kind", ""))
	var id = int(context.get("id", 0))
	var point = ""
	if kind == "mall":
		var row: Dictionary = systems.catalog.find("MallTradeData", id)
		if not row.get("Enable", false) or row.get("GoodsPayType", "") != "Ad": return _fail("商品不可用")
		if systems._mall_reward_options(row).is_empty(): return _fail("奖励配置不可用")
		var period = str(int(int(systems.utc_now.call()) / 86400)) if row.RefreshMode == "OneDay" else str(systems.stat("runs")) if row.RefreshMode == "OneBattle" else "never"
		var purchase = "purchase:" + str(id) + ":" + period
		if int(row.GoodsNum) >= 0 and systems.stat(purchase) >= int(row.GoodsNum): return _fail("已达领取上限")
		point = "Mall_" + str(id)
		return {"success": true, "point": point, "purchase": purchase}
	elif kind == "meal":
		var row: Dictionary = systems.catalog.find("CatMealData", id)
		var level = int(context.get("level", 1))
		if systems.profile.data.run.active or row.is_empty() or level < 1: return _fail("请在营地点餐")
		if level > systems.rank(systems.profile.data.recipes, id): return _fail("请先研究该料理等级")
		if level > DungeonCatalog.ids(row.AbilityItemId).size(): return _fail("料理等级不可用")
		point = "CatMeal_FreeOrder"
	elif kind == "work":
		if systems.profile.data.run.active: return _fail("请在营地加速派遣")
		var active = systems.profile.data.work.filter(func(order): return int(order.work_id) == id and int(order.due_utc) > int(systems.utc_now.call()))
		if active.is_empty(): return _fail("没有需要加速的派遣")
		point = "MonsterWork_AdSpeedUp"
	else:
		return _fail("奖励入口不可用")
	var maximum = int(systems.catalog.config.get("AdsDailyLimitConfig", {}).get(point, 0))
	if maximum <= 0 or int(_state().counts.get(point, 0)) >= maximum: return _fail("今日次数已用完")
	return {"success": true, "point": point}

func claim(context: Dictionary, receipt: String, skip: bool = false) -> Dictionary:
	var state = _state()
	if receipt.is_empty() or state.receipts.has(receipt): return _fail("奖励已处理")
	var check = quote(context)
	if not check.success: return check
	if skip and free_skips() == 0: return _fail("今日免广告次数已用完")
	var id = int(context.id)
	if context.kind == "mall":
		var row: Dictionary = systems.catalog.find("MallTradeData", id)
		for option in systems._mall_reward_options(row):
			if option.ids.size() == 1: systems.grant_material(int(option.ids[0]), int(option.amount))
			else:
				for draw in int(option.amount): systems.grant_material(int(option.ids[systems.next_random(option.ids.size())]), 1)
		systems.record(str(check.purchase))
	elif context.kind == "meal":
		systems.profile.data.selected_meal = id
		systems.profile.data.meal_rank = int(context.get("level", 1))
	elif context.kind == "work":
		# APK stable-data default: 30 minutes. Existing dispatch uses UTC seconds.
		for order in systems.profile.data.work:
			if int(order.work_id) == id:
				order.due_utc = maxi(int(systems.utc_now.call()), int(order.due_utc) - 30 * 60)
	state.counts[check.point] = int(state.counts.get(check.point, 0)) + 1
	if skip: state.skips += 1
	state.receipts.append(receipt)
	# Receipts cover duplicate SDK delivery without growing saves indefinitely.
	while state.receipts.size() > 256: state.receipts.pop_front()
	systems.changed.emit()
	return {"success": true, "message": "奖励已领取"}

func _fail(text: String) -> Dictionary:
	return {"success": false, "message": text}
