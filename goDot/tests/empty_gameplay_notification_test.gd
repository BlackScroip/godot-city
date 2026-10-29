extends SceneTree

const Combat = preload("res://scripts/domain/combat.gd")

# Preserve the former empty-status path as an independent comparison oracle.
class LegacyNotificationCombat extends DungeonCombat:
	func notify_gameplay(kind: String, payload: Dictionary = {}) -> void:
		if not statuses.is_empty():
			super.notify_gameplay(kind, payload)
			return
		if _condition_depth > 16:
			_report("Condition event recursion exceeds 16")
			return
		_condition_depth += 1
		if kind == "cause_damage":
			custom_properties["ComboCount"] = int(custom_properties.get("ComboCount", 0)) + 1
		for _entry in statuses.values().duplicate():
			pass
		_condition_depth -= 1

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _actor(actor: DungeonCombat, key: String) -> void:
	check(actor.configure(null, null, 1, 0, 541).success, "Configure " + key)
	actor.actor_key = key
	actor.statuses.clear()
	actor.diagnostics.clear()
	actor.drain_events()
	actor.defense = 0
	actor.max_health = 1000000
	actor.health = actor.max_health

func _events(actor: DungeonCombat) -> Array:
	var result := actor.drain_events().duplicate(true)
	for event in result:
		if event.get("source") is DungeonCombat: event.source = event.source.actor_key
	return result

func _equal(pair: Array, label: String) -> void:
	check(pair[0]._condition_depth == pair[1]._condition_depth, "Depth differs: " + label)
	check(pair[0].custom_properties == pair[1].custom_properties, "Properties differ: " + label)
	check(pair[0].statuses == pair[1].statuses, "Statuses differ: " + label)
	check(pair[0].diagnostics == pair[1].diagnostics, "Diagnostics differ: " + label)
	check(_events(pair[0]) == _events(pair[1]), "Events differ: " + label)

func _depth_boundaries(pair: Array) -> void:
	for depth in [0, 15, 16, 17, 18]:
		for kind in ["move", "tick", "heal", "cause_damage"]:
			for initial in [-1, 7]:
				for actor in pair:
					actor.statuses.clear()
					actor.diagnostics.clear()
					actor.drain_events()
					actor._condition_depth = depth
					actor.custom_properties.erase("ComboCount")
					if initial >= 0: actor.custom_properties["ComboCount"] = initial
					actor.notify_gameplay(kind, {"moving": true, "distance": 1.0, "delta": 0.1, "damage": 12.0})
				var label := "%s/%d/%d" % [kind, depth, initial]
				_equal(pair, label)
				check(pair[0]._condition_depth == depth, "Depth preserved: " + label)
				var expected_count := maxi(0, initial) + (1 if depth <= 16 and kind == "cause_damage" else 0)
				check(int(pair[0].custom_properties.get("ComboCount", 0)) == expected_count, "Combo count: " + label)
				check(pair[0].diagnostics.size() == (1 if depth > 16 else 0), "Recursion diagnostic: " + label)
	for actor in pair:
		actor._condition_depth = 17
		actor.diagnostics.clear()
		actor.drain_events()
		actor.notify_gameplay("cause_damage")
		actor.notify_gameplay("cause_damage")
	check(pair[0].diagnostics.size() == 1 and pair[0].events.size() == 1, "Repeated recursion diagnostic is deduplicated")
	_equal(pair, "repeated recursion")
	for actor in pair: actor._condition_depth = 0

func _strike(sources: Array, targets: Array, damage: float, serial: int, damage_id := 1) -> Array:
	var results: Array = []
	for index in sources.size():
		var hit := {"source": sources[index], "damage": damage, "sequence": serial, "emission": serial,
			"definition": {"damageId": damage_id, "actType": "Buff", "element": "Thunder"}}
		var actual: float = targets[index].receive(hit, sources[index].attack)
		results.append({"damage": actual, "accepted": hit.resolved_accepted, "absorbed": hit.resolved_absorbed,
			"health": targets[index].health, "shield": targets[index].shield})
	check(results[0] == results[1], "Damage differs on strike %d" % serial)
	_equal(sources, "source strike %d" % serial)
	_equal(targets, "target strike %d" % serial)
	return results

func _damage_and_buffs() -> void:
	var sources := [Combat.new(), LegacyNotificationCombat.new()]
	var targets := [Combat.new(), LegacyNotificationCombat.new()]
	for actor in sources: _actor(actor, "source")
	for actor in targets: _actor(actor, "target")
	var hit := _strike(sources, targets, 100.0, 1, 2392301)
	check(is_equal_approx(hit[0].damage, 100.0) and sources[0].custom_properties.ComboCount == 1, "Real positive damage increments combo")
	_strike(sources, targets, 0.0, 2)
	check(sources[0].custom_properties.ComboCount == 1, "Zero damage does not increment combo")
	for target in targets: target.shield = 1000.0
	_strike(sources, targets, 25.0, 3)
	check(sources[0].custom_properties.ComboCount == 1, "Shield-only hit does not increment combo")
	for target in targets:
		target.shield = 0.0
		target.invincible = 1.0
	_strike(sources, targets, 25.0, 4)
	check(sources[0].custom_properties.ComboCount == 1, "Invincible hit does not increment combo")
	for target in targets: target.invincible = 0.0
	_strike(sources, targets, 100.0, 5)
	check(sources[0].custom_properties.ComboCount == 2, "Second positive hit increments combo")
	for actor in sources: check(actor.add_buff("50202800"), "Add authored damage modifier")
	_equal(sources, "add damage modifier")
	hit = _strike(sources, targets, 100.0, 6, 2392301)
	check(is_equal_approx(hit[0].damage, 170.0), "Newly added buff retains its source damage bonus")
	for actor in sources:
		for id in actor.statuses.keys(): actor.remove_buff(str(id))
	for actor in targets:
		for id in actor.statuses.keys(): actor.remove_buff(str(id))
	check(sources[0].statuses.is_empty() and sources[1].statuses.is_empty(), "All source buffs removed")
	hit = _strike(sources, targets, 100.0, 7, 2392301)
	check(is_equal_approx(hit[0].damage, 100.0) and sources[0].custom_properties.ComboCount == 4, "Damage and combo return to empty-status behavior after buff removal")

func _later_movement_listener() -> void:
	var pair := [Combat.new(), LegacyNotificationCombat.new()]
	for actor in pair:
		_actor(actor, "walker")
		for _index in 20: actor.notify_gameplay("move", {"moving": true, "distance": 1.0, "delta": 1.0})
	_equal(pair, "empty movement")
	for actor in pair: check(actor.add_buff("50202550"), "Add authored movement listener")
	_equal(pair, "add movement listener")
	for actor in pair: actor.notify_gameplay("move", {"moving": true, "distance": 34.9, "delta": 1.0})
	_equal(pair, "movement before threshold")
	for actor in pair: actor.notify_gameplay("move", {"moving": true, "distance": 0.2, "delta": 0.1})
	var first := _events(pair[0])
	var second := _events(pair[1])
	check(first == second, "Movement listener events match reference")
	check(first.filter(func(event): return event.get("type", "") == "summon" and str(event.get("id", "")) == "502025510").size() == 1, "New movement listener triggers at its original distance")
	_equal(pair, "movement threshold")
	for actor in pair:
		for id in actor.statuses.keys(): actor.remove_buff(str(id))
		actor.notify_gameplay("move", {"moving": true, "distance": 40.0, "delta": 1.0})
	_equal(pair, "movement after buff removal")

func _run() -> void:
	var pair := [Combat.new(), LegacyNotificationCombat.new()]
	for actor in pair: _actor(actor, "boundary")
	_depth_boundaries(pair)
	_damage_and_buffs()
	_later_movement_listener()
	print("EMPTY_GAMEPLAY_NOTIFICATION ", JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
