class_name DungeonRoomMeals
extends RefCounted

const Catalog = preload("res://scripts/domain/catalog.gd")
const BUTTON_KEY := "EnvUnit_MonoData_BtnDisplayName_CatMeal_Shop"
var systems

func _init(service) -> void:
	systems = service

func meal_status(id: int, level: int = 1) -> Dictionary:
	var row: Dictionary = systems.catalog.find("CatMealData", id)
	var reason := _reason(row, level)
	var maximum := Catalog.ids(row.get("AbilityItemId", "")).size()
	var researched: int = systems.rank(systems.profile.data.recipes, id)
	var price: Dictionary = systems._meal_price(row, level) if level > 0 and level <= maximum else {}
	var selected: bool = systems.rank(systems.profile.data.get("meal_selection", {}), id) == level
	var select_reason := reason
	if select_reason.is_empty() and not selected and not systems.profile.data.get("meal_selection", {}).has(str(id)) and systems.profile.data.get("meal_selection", {}).size() >= systems.meal_order_limit():
		select_reason = "餐单最多选择 %d 道料理" % systems.meal_order_limit()
	var buy_reason := reason
	if buy_reason.is_empty() and not systems.can_afford(price): buy_reason = "料理材料不足"
	return {"id": id, "level": level, "max_level": maximum, "researched_level": researched, "selected": selected, "purchased": systems.rank(systems.purchased_meals(), id) == level, "price": price, "can_cook": buy_reason.is_empty(), "can_select": select_reason.is_empty(), "select_reason": select_reason, "reason": buy_reason, "description": Catalog.clean(systems._part(row.get("Description", ""), level - 1))}

func select_meal(id: int, level: int = 1) -> Dictionary:
	return systems._camp_transaction(_select_meal.bind(id, level))

func _select_meal(id: int, level: int) -> Dictionary:
	var status := meal_status(id, level)
	if not status.can_select: return systems._fail(status.select_reason)
	var selection: Dictionary = systems.profile.data.get("meal_selection", {}).duplicate()
	if status.selected: selection.erase(str(id))
	else: selection[str(id)] = level
	systems.profile.data.meal_selection = selection
	systems.profile.data.last_meals = selection.duplicate()
	return systems._done("已更新餐单", id)

func order_status(order: Dictionary = {}) -> Dictionary:
	var meals: Dictionary = order.duplicate() if not order.is_empty() else systems.profile.data.get("meal_selection", {}).duplicate()
	var reason := ""
	var price: Dictionary = {}
	if not bool(systems.profile.data.run.active): reason = "请在冒险中的料理商店点餐"
	elif meals.is_empty(): reason = "请先选择料理"
	elif meals.size() > systems.meal_order_limit(): reason = "餐单最多选择 %d 道料理" % systems.meal_order_limit()
	for key in meals:
		if not str(key).is_valid_int() or not (meals[key] is int or meals[key] is float) or not is_finite(float(meals[key])) or float(meals[key]) != floor(float(meals[key])):
			if reason.is_empty(): reason = "料理等级不存在"
			continue
		var row: Dictionary = systems.catalog.find("CatMealData", int(key))
		var level := int(meals[key])
		var meal_reason := _reason(row, level)
		if reason.is_empty() and not meal_reason.is_empty(): reason = meal_reason
		if not meal_reason.is_empty(): continue
		var meal_price: Dictionary = systems._meal_price(row, level)
		for resource in meal_price: systems._add(price, resource, int(meal_price[resource]))
	if reason.is_empty() and not systems.can_afford(price): reason = "料理材料不足"
	return {"meals": meals, "price": price, "count": meals.size(), "limit": systems.meal_order_limit(), "can_buy": reason.is_empty(), "reason": reason}

func buy(id: int = 0, level: int = 1) -> Dictionary:
	return systems._camp_transaction(_buy.bind(id, level))

func _buy(id: int, level: int) -> Dictionary:
	var status := order_status({str(id): level} if id > 0 else {})
	if not status.can_buy: return systems._fail(status.reason)
	if not systems.spend(status.price): return systems._fail("料理材料不足")
	# Native BuyMeal has no PurchasedMealOnRegin gate; only the recook shortcut does.
	systems._complete_meal_purchase(status.meals)
	return systems._done("已享用 %d 道料理" % int(status.count))

func _reason(row: Dictionary, level: int) -> String:
	if not bool(systems.profile.data.run.active): return "请在冒险中的料理商店点餐"
	if row.is_empty() or level < 1 or level > Catalog.ids(row.get("AbilityItemId", "")).size(): return "料理等级不存在"
	for gate in Catalog.ids(row.get("UnlockDataId", "")):
		if gate > 0 and not systems.is_unlocked(gate): return systems.unlock_reason(gate)
	if level > systems.rank(systems.profile.data.recipes, Catalog.row_id(row)): return "请先研究该料理等级"
	return ""
