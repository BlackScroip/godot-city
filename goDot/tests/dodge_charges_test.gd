extends SceneTree

const Combat = preload("res://scripts/domain/combat.gd")
const Intent = preload("res://scripts/player_intent.gd")
var failures: Array[String] = []
var assertions := 0

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var hud = DungeonHud.new()
	root.add_child(hud)
	await process_frame
	for character in range(1, 8):
		for fps in [30, 60, 120]:
			var combat = Combat.new()
			combat.configure(null, null, character)
			var cost = float(combat.fighter.skills[1].sp)
			check(is_equal_approx(float(combat.energy[1]), 2.0 * cost), "Two initial charges %d/%d" % [character, fps])
			check(float(combat.fighter.skills[1].maxSp) == 2.0, "Recovered catalog remains unchanged")
			hud.update_combat(combat, false)
			check(hud.skill_by_slot[1].stock == 2, "HUD displays two charges")
			var intent = Intent.new()
			check(intent.request(combat, 1, true).success and intent.take_ready(combat, 0) == 1, "Input accepts first dodge")
			check(combat.request_attack(1).success, "First dodge casts")
			combat.tick(0.3)
			hud.update_combat(combat, false)
			check(hud.skill_by_slot[1].stock == 1 and not hud.skill_by_slot[1].unavailable and hud.skill_by_slot[1].recharge_remaining > 0, "Remaining charge usable during recharge")
			check(combat.request_attack(1).success, "Second dodge casts before recharge")
			check(not combat.request_attack(1).success, "Third dodge rejected")
			check(not intent.request(combat, 1, true).success, "Input rejects empty stock")
			hud.update_combat(combat, false)
			check(hud.skill_by_slot[1].stock == 0 and hud.skill_by_slot[1].unavailable and is_equal_approx(hud.skill_by_slot[1].recharge_remaining, 1.0), "Empty stock has recharge countdown")
			for frame in fps - 1: combat.tick(1.0 / fps)
			check(is_zero_approx(float(combat.energy[1])), "No recharge before last-use delay")
			var restored = Combat.new()
			restored.configure(null, null, character)
			check(restored.restore(JSON.parse_string(JSON.stringify(combat.snapshot()))), "Snapshot restores")
			check(is_equal_approx(restored.dodge_recharge_remaining(), combat.dodge_recharge_remaining()), "Save retains recharge progress")
			combat.tick(1.0 / fps)
			restored.tick(1.0 / fps)
			check(is_equal_approx(float(combat.energy[1]), cost) and is_equal_approx(float(restored.energy[1]), cost), "APK grants one charge at delay boundary")
			combat.tick(0)
			check(is_equal_approx(float(combat.energy[1]), cost), "Zero-delta update cannot replenish")
			combat.tick(1.0 / fps)
			check(is_equal_approx(float(combat.energy[1]), 2 * cost), "APK grants next charge on following update")
			combat.tick(5)
			hud.update_combat(combat, false)
			check(hud.skill_by_slot[1].stock == 2 and hud.skill_by_slot[1].recharge_remaining == 0, "Full stock caps and clears progress")
			combat.drain_events()
			restored.drain_events()
	var combat = Combat.new()
	combat.configure()
	combat.set_external_attributes({"SkillDodgeChargeTimeAdd": 500, "SkillDodgeExtraUseCount": 1})
	check(combat.skill_capacity(1) == 6 and combat.dodge_recharge_duration() == 1.5, "Dodge modifiers affect capacity and delay")
	combat.request_attack(1)
	combat.tick(1.49)
	check(combat.energy[1] == 2, "Modified recharge waits")
	combat.tick(0.01)
	check(combat.energy[1] == 4, "Modified recharge boundary")
	combat.health = 0
	var previous = float(combat.energy[1])
	combat.tick(1)
	check(combat.energy[1] == previous and not combat.request_attack(1).success, "Defeated player cannot recharge or cast")
	combat.drain_events()
	hud.free()
	await process_frame
	print("DODGE_CHARGES ", JSON.stringify({"assertions": assertions, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
