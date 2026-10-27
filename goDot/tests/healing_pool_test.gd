extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	var pool = load("res://scripts/domain/healing_pool.gd").new()
	var counters: Dictionary = {}
	var result: Dictionary = pool.drink(counters, "room-a", 105.0, 20.0)
	_check(result.success and result.amount == 31.0 and result.health == 51.0, "spring uses truncated 300/1000 maximum HP")
	_check(pool.is_used(counters, "room-a"), "successful drink persists the room consumption")
	_check(not pool.drink(counters, "room-a", 105.0, 20.0).success, "same room cannot grant a second drink")
	_check(pool.drink(counters, "room-b", 105.0, 100.0, 500.0).amount == 52.0, "spring attribute override uses per mille")
	_check(pool.drink({}, "full", 100.0, 100.0).success, "full HP still consumes the spring")
	_check(pool.drink({}, "full", 100.0, 100.0).health == 100.0, "preview health respects maximum HP")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(counters))
	_check(not pool.drink(saved, "room-a", 105.0, 1.0).success, "save and restore cannot refill a used spring")
	var invalid: Dictionary = {}
	_check(not pool.drink(invalid, "", 100.0, 10.0).success and invalid.is_empty(), "invalid room identity is rejected without consumption")
	_check(not pool.drink(invalid, "bad", NAN, 10.0).success and invalid.is_empty(), "invalid health values do not consume a spring")
	var zero: Dictionary = {}
	_check(pool.drink(zero, "blocked", 100.0, 10.0, 0.0).success and pool.is_used(zero, "blocked"), "zero recovery still consumes the spring")
	_check(pool.reward_plan({}, 1, 1).is_empty(), "spring has no unconditional loot")
	_check(pool.reward_plan({"DrinkSpringGetPurseLv": 1}, 1, 1) == [11001], "first purse level yields the source small purse")
	_check(pool.reward_plan({"DrinkSpringGetPurseLv": 3}, 1, 1) == [11003], "third purse level yields the source large purse")
	_check(pool.reward_plan({"DrinkSpringGetPurseLv": 4}, 1, 1).is_empty(), "out of range purse levels do not clamp to a valid reward")
	var rewards: Dictionary = {"DrinkSpringGetPurseLv": 2, "DrinkSpringGetRedgemLv": 150, "DrinkSpringGetGreengemLv": 1000}
	_check(pool.reward_plan(rewards, 150, 1000) == [11002, 10000, 10010], "per mille reward chance includes its upper boundary")
	_check(pool.reward_plan(rewards, 151, 1000) == [11002, 10010], "red gem chance rejects the next integer roll")
	_check(pool.reward_plan({"DrinkSpringGetRedgemLv": 0}, 1, 1).is_empty(), "zero chance never grants a gem")
	if failures.is_empty(): print("healing_pool_test PASS")
	else:
		for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
