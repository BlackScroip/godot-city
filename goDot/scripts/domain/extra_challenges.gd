extends RefCounted

const LETTER_ID = 40001
const RECEIVE_COUNT = 3
const DELETE_PENALTY = 7
const AD_POINTS = {"receive": "ExtraChallenge_GetQuest", "finish": "ExtraChallenge_FinishQuest", "double": "ExtraChallenge_GetRewardDouble"}
var _owner: WeakRef
var systems:
	get: return _owner.get_ref()

func _init(owner_systems) -> void:
	_owner = weakref(owner_systems)
	if not systems.profile.data.has("extra_challenges"):
		systems.profile.data.extra_challenges = {"active": {}, "penalties": {}, "rng_state": maxi(1, randi() & 0x7fffffff)}
	for field in ["active", "penalties"]:
		for key in _state()[field].keys():
			if systems.catalog.find("ExtraChallengeData", int(key)).is_empty(): _state()[field].erase(key)
			else: _state()[field][key] = int(_state()[field][key])
	_state().rng_state = int(_state().rng_state)

static func validate_state(value) -> bool:
	if not value is Dictionary: return false
	for field in ["active", "penalties"]:
		if not value.get(field) is Dictionary: return false
		for key in value[field]:
			var amount = value[field][key]
			if not str(key).is_valid_int() or int(key) <= 0: return false
			if not (amount is int or amount is float) or not is_finite(float(amount)) or float(amount) != floor(float(amount)) or amount < 0: return false
			if field == "penalties" and amount > DELETE_PENALTY: return false
	var seed_value = value.get("rng_state")
	return (seed_value is int or seed_value is float) and is_finite(float(seed_value)) and float(seed_value) == floor(float(seed_value)) and seed_value > 0 and seed_value <= 0x7fffffff

func _state() -> Dictionary:
	return systems.profile.data.extra_challenges

func capacity() -> int:
	var level = systems.rank(systems.profile.data.buildings, 5)
	return 9 if level >= 3 else 6 if level == 2 else 0

func status() -> Dictionary:
	var count = _state().active.size()
	var remaining = maxi(0, capacity() - count)
	var reason = _camp_reason()
	if reason.is_empty() and remaining == 0: reason = "悬赏栏位已满"
	if reason.is_empty() and _candidates().is_empty(): reason = "暂无可接取的悬赏"
	return {"unlocked": capacity() > 0, "capacity": capacity(), "count": count, "remaining": remaining, "receive_count": mini(RECEIVE_COUNT, remaining), "letter_id": LETTER_ID, "letters": systems.material(LETTER_ID), "price": {str(LETTER_ID): 1}, "reason": reason, "can_receive": reason.is_empty() and systems.material(LETTER_ID) > 0, "can_receive_ad": reason.is_empty()}

func entries() -> Array:
	var result: Array = []
	for row in systems.catalog.rows("ExtraChallengeData"):
		if _state().active.has(str(int(row.id))): result.append(entry(int(row.id)))
	return result

func entry(id: int) -> Dictionary:
	var row = systems.catalog.find("ExtraChallengeData", id)
	var active = not row.is_empty() and _state().active.has(str(id))
	var material_request = int(row.get("request_type", 0)) == 2
	var materials = systems.costs(row.get("need_mat_id_array", "")) if material_request else {}
	var required = maxi(1, int(row.get("rogue_event_trigger_time", 1))) if not material_request else 1
	var current = int(_state().active.get(str(id), 0))
	if material_request: current = 1 if systems.can_afford(materials) else 0
	var complete = active and current >= required
	var reason = _camp_reason()
	if reason.is_empty() and not active: reason = "悬赏未接取或已处理"
	var reward = systems.costs(row.get("reward", ""))
	if reason.is_empty() and (reward.is_empty() or reward.has("invalid") or materials.has("invalid")): reason = "悬赏配置无效"
	return {"id": id, "row": row, "active": active, "material_request": material_request, "materials": materials, "reward": reward, "current": mini(current, required), "required": required, "complete": complete, "reason": reason, "can_claim": reason.is_empty() and complete, "can_finish_ad": reason.is_empty() and not complete, "can_double_ad": reason.is_empty() and complete}

func receive() -> Dictionary:
	var quote = status()
	if not quote.reason.is_empty(): return systems._fail(quote.reason)
	if not quote.can_receive or not systems.spend(quote.price): return systems._fail("需要一封悬赏信件")
	var ids = _receive()
	var result = systems._done("已接取 %d 项悬赏" % ids.size())
	result["ids"] = ids
	return result

func remove(id: int) -> Dictionary:
	var quote = entry(id)
	if not quote.reason.is_empty(): return systems._fail(quote.reason)
	_state().active.erase(str(id))
	_state().penalties[str(id)] = DELETE_PENALTY
	return systems._done("已放弃悬赏", id)

func claim(id: int) -> Dictionary:
	var quote = entry(id)
	if not quote.can_claim: return systems._fail(quote.reason if not quote.reason.is_empty() else "悬赏尚未完成")
	return _claim(quote, false, true)

func ad_quote(action: String, id: int = 0) -> Dictionary:
	if not AD_POINTS.has(action): return systems._fail("悬赏广告入口无效")
	if action == "receive":
		var quote = status()
		if not quote.can_receive_ad: return systems._fail(quote.reason)
	else:
		var quote = entry(id)
		if not quote.reason.is_empty(): return systems._fail(quote.reason)
		if action == "double" and not quote.complete: return systems._fail("悬赏尚未完成")
		if action == "finish" and quote.complete: return systems._fail("悬赏已完成，请领取奖励")
	return {"success": true, "point": AD_POINTS[action]}

# Only the receipt-validating ad service calls this after a rewarded callback.
func apply_ad(action: String, id: int = 0) -> Dictionary:
	var quote = ad_quote(action, id)
	if not quote.success: return quote
	if action == "receive":
		var ids = _receive()
		return {"success": true, "message": "已接取 %d 项悬赏" % ids.size(), "ids": ids}
	return _claim(entry(id), action == "double", action != "finish")

func record_event(event: String, param1: String = "", param2: String = "", param3: String = "") -> void:
	if not systems.profile.data.run.active: return
	var amount = int(param3) if event == "ChangeResCount" else 1
	if amount <= 0: return
	for key in _state().active.keys():
		var row = systems.catalog.find("ExtraChallengeData", int(key))
		if int(row.get("request_type", 0)) != 1 or str(row.get("rogue_event_type", "")) != event: continue
		if not _matches(str(row.get("rogue_event_param1", "")), param1): continue
		if not _matches(str(row.get("rogue_event_param2", "")), param2): continue
		if event != "ChangeResCount" and not _matches(str(row.get("rogue_event_param3", "")), param3): continue
		_state().active[key] = mini(int(row.get("rogue_event_trigger_time", 1)), int(_state().active[key]) + amount)

func _matches(expected: String, actual: String) -> bool:
	return expected.is_empty() or expected == actual

func _camp_reason() -> String:
	if capacity() == 0: return "委托设施达到 2 级后解锁"
	if systems.profile.data.run.active: return "请返回据点后操作"
	return ""

func _candidates() -> Array:
	var all: Array = []
	var allowed: Array = []
	for row in systems.catalog.rows("ExtraChallengeData"):
		var id = int(row.id)
		if _state().active.has(str(id)): continue
		var unlock_id = int(row.get("active_data_id", 0))
		if unlock_id > 0 and not systems.is_unlocked(unlock_id): continue
		all.append(id)
		if int(_state().penalties.get(str(id), 0)) == 0: allowed.append(id)
	# APK falls back to the unlocked pool when the filtered pool is no larger
	# than the full board capacity, so deletion cannot exhaust the board.
	return all if allowed.size() <= capacity() else allowed

func _receive() -> Array:
	var candidates = _candidates()
	var result: Array = []
	for index in mini(RECEIVE_COUNT, mini(capacity() - _state().active.size(), candidates.size())):
		_state().rng_state = maxi(1, (int(_state().rng_state) * 48271) % 2147483647)
		var chosen = int(_state().rng_state) % candidates.size()
		var id = int(candidates[chosen])
		candidates.remove_at(chosen)
		_state().active[str(id)] = 0
		result.append(id)
	for key in _state().penalties.keys():
		_state().penalties[key] = int(_state().penalties[key]) - 1
		if int(_state().penalties[key]) <= 0: _state().penalties.erase(key)
	return result

func _claim(quote: Dictionary, doubled: bool, commit_materials: bool) -> Dictionary:
	if commit_materials and quote.material_request and not systems.spend(quote.materials): return systems._fail("提交材料不足")
	# Remove before issuing rewards so reentrant events cannot reward it twice.
	_state().active.erase(str(int(quote.id)))
	for key in quote.reward: systems.grant_material(int(key), int(quote.reward[key]) * (2 if doubled else 1))
	systems.gameplay_event.emit({"type": "extra_challenge_claimed", "id": int(quote.id)})
	return systems._done("悬赏奖励已领取", int(quote.id))
