extends "res://tests/fixtures/navigation_reference.gd"

var navigation_us := 0
var navigation_calls := 0

func enemy_navigation_requested() -> bool:
	var started := Time.get_ticks_usec()
	var result := super.enemy_navigation_requested()
	navigation_us += Time.get_ticks_usec() - started
	navigation_calls += 1
	return result
