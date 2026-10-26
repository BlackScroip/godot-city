extends RefCounted

const Combat = preload("res://scripts/domain/combat.gd")
const Reference = preload("res://tests/fixtures/status_substeps_reference.gd")

static func run(check: Callable) -> void:
	# 324 epsilon/health/depth assertions plus 14 state-transition assertions.
	var deltas := [0.0, 0.0000001, 0.0000009999, 0.000001, 0.0000010001, 0.001, 0.009, 0.0099999999, 0.01, 0.0100000001, 1.0 / 120, 1.0 / 60, 0.0199999999, 0.02, 0.0200000001, 1.0 / 30, 0.1, 0.5]
	for delta in deltas:
		for depth in [0, 16, 17]:
			for excess_hp in [false, true]:
				var pair := _pair()
				for actor in pair:
					actor._condition_depth = depth
					if excess_hp: actor.health = actor.max_health + 20
					actor.tick(delta)
				var label := "delta %.10f/depth %d/excess %s" % [delta, depth, excess_hp]
				check.call(pair[0].snapshot() == pair[1].snapshot(), "Boundary snapshot differs: " + label)
				check.call(pair[0].events == pair[1].events, "Boundary events differ: " + label)
				check.call(pair[0]._condition_depth == pair[1]._condition_depth and pair[0].action_step == pair[1].action_step, "Boundary recursion/timeline differs: " + label)
	for scenario in 7:
		var pair := _pair()
		for actor in pair:
			match scenario:
				0: actor.health = 0
				1:
					actor.health = actor.max_health + 20
					actor.frozen = 1
				2:
					actor.health = actor.max_health + 20
					actor.impact_pause = 1
				3:
					actor.health = actor.max_health + 20
					actor.stagger_remaining = 1
				4:
					actor.add_buff("41300104", 1)
					actor.statuses["41300104"].time = 0.005
				5:
					actor._pending.append({"at": 0.0, "sequence": actor._cast_sequence, "action": actor.current_action, "slot": 0, "command_index": 0, "action_timeline": true, "command": {"type": "EET_AddBuff", "buff": "41300104", "layers": 1, "raw": "{}"}})
				6:
					actor.add_buff("103100", 1)
					actor._current_slot = 3
					actor.busy = 0.001
			actor.tick(0.02)
			actor.tick(0.02)
		check.call(pair[0].snapshot() == pair[1].snapshot(), "Empty/nonempty transition snapshot differs: %d" % scenario)
		check.call(pair[0].events == pair[1].events, "Empty/nonempty transition events differ: %d" % scenario)

static func _pair() -> Array:
	var pair := [Combat.new(), Reference.new()]
	for actor in pair: actor.configure_enemy(11001, 731)
	return pair
