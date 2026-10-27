extends RefCounted

var systems

func _init(source) -> void:
	systems = source

func _state() -> Dictionary:
	var data: Dictionary = systems.profile.data
	var day = floori((float(systems.utc_now.call()) - 22 * 3600) / 86400.0)
	if not data.get("ad_rewards", {}) is Dictionary: data.ad_rewards = {}
	var saved: Dictionary = data.get("ad_rewards", {})
	if saved.is_empty():
		data.ad_rewards = {"day": day, "counts": {}, "skips": 0, "receipts": [], "reset_version": 1}
	elif int(saved.get("reset_version", 0)) == 0:
		# Keep used limits when migrating the previous UTC-midnight ledger.
		saved.day = day
		saved.reset_version = 1
	elif day > int(saved.day):
		data.ad_rewards = {"day": day, "counts": {}, "skips": 0, "receipts": saved.receipts, "reset_version": 1}
	return data.ad_rewards

func free_skips() -> int:
	return maxi(0, 3 - int(_state().skips))

func quote(context: Dictionary) -> Dictionary:
	var kind = str(context.get("kind", ""))
	var id = int(context.get("id", 0))
	var point = ""
	var meal_order: Dictionary = {}
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
		var status = systems.meal_order_status(true)
		if not status.can_ad: return _fail(status.ad_reason)
		meal_order = status.meals
		point = "CatMeal_FreeOrder"
	elif kind == "work":
		if systems.profile.data.run.active: return _fail("请在营地加速派遣")
		var status = systems.work_status(id)
		if status.order.is_empty() or int(status.completed_quantity) >= int(status.queue_max): return _fail("没有需要加速的派遣")
		point = "MonsterWork_AdSpeedUp"
	elif kind.begins_with("extra_challenge_"):
		var bounty = systems.extra_challenges.ad_quote(kind.trim_prefix("extra_challenge_"), id)
		if not bounty.success: return bounty
		point = bounty.point
	else:
		return _fail("奖励入口不可用")
	var maximum = int(systems.catalog.config.get("AdsDailyLimitConfig", {}).get(point, 0))
	if maximum <= 0 or int(_state().counts.get(point, 0)) >= maximum: return _fail("今日次数已用完")
	return {"success": true, "point": point, "meals": meal_order}

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
		systems._complete_meal_purchase(check.meals)
	elif context.kind == "work":
		systems.add_work_progress(id, 30 * 60)
	elif str(context.kind).begins_with("extra_challenge_"):
		var bounty = systems.extra_challenges.apply_ad(str(context.kind).trim_prefix("extra_challenge_"), id)
		if not bounty.success: return bounty
	state.counts[check.point] = int(state.counts.get(check.point, 0)) + 1
	if skip: state.skips += 1
	state.receipts.append(receipt)
	# Receipts cover duplicate SDK delivery without growing saves indefinitely.
	while state.receipts.size() > 256: state.receipts.pop_front()
	systems.changed.emit()
	return {"success": true, "message": "奖励已领取"}

func _fail(text: String) -> Dictionary:
	return {"success": false, "message": text}
