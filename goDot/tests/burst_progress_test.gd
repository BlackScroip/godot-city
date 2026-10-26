extends SceneTree

const Combat = preload("res://scripts/domain/combat.gd")
var checks := 0
var failures: Array[String] = []

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func hit(amount := 2.0, chance := 1000, damage := 10.0) -> Dictionary:
	return {"definition": {"raw": {"RecoverSkillCharge": amount, "RecoverSkillChargeChance": chance}}, "resolved_accepted": true, "resolved_calculated_damage": damage}

func _run() -> void:
	for character in range(1, 9):
		var actor = Combat.new()
		actor.configure(null, null, character)
		check(actor.energy[3] == 0 and actor.skill_charge_fraction(3) == 0, "Character %d starts with empty ultimate" % character)
		check(not actor.request_attack(3).success, "Character %d cannot use uncharged ultimate" % character)
		actor.tick(10.0)
		check(actor.energy[3] == 0, "Character %d has no passive ultimate regeneration" % character)
		var contact := hit()
		actor.confirm_hit(contact)
		check(is_equal_approx(actor.energy[3], 2.0), "Character %d gains authored SP on accepted hit" % character)
		actor.confirm_hit(contact)
		check(is_equal_approx(actor.energy[3], 2.0), "Character %d gains SP once per hit instance" % character)
		actor.add_skill_charge(3, 10000)
		check(actor.energy[3] == actor.skill_capacity(3), "Character %d caps at capacity" % character)
		check(actor.request_attack(3).success and actor.energy[3] == 0, "Character %d spends authored cost on cast" % character)
		check(actor.cooldowns[3] > 0, "Character %d retains cooldown after cast" % character)
	var actor = Combat.new()
	actor.configure()
	for amount in [0.0, -2.0]:
		actor.confirm_hit(hit(amount))
		check(actor.energy[3] == 0, "Zero or negative authored recovery does not fabricate SP")
	var low_damage := hit(2, 1000, 0.5)
	actor.confirm_hit(low_damage)
	low_damage.resolved_calculated_damage = 100
	actor.confirm_hit(low_damage)
	check(actor.energy[3] == 0 and low_damage.skill_charge_attempted, "First low-damage contact consumes the instance attempt")
	var rejected := hit()
	rejected.resolved_accepted = false
	actor.confirm_hit(rejected)
	check(actor.energy[3] == 0 and not rejected.get("skill_charge_attempted", false), "Rejected contact preserves the attempt")
	var failed_roll := hit(10, -1)
	actor.confirm_hit(failed_roll)
	failed_roll.definition.raw.RecoverSkillChargeChance = 1000
	actor.confirm_hit(failed_roll)
	check(actor.energy[3] == 0, "Failed chance cannot retry on another target")
	actor.energy[3] = 100
	var full_contact := hit()
	actor.confirm_hit(full_contact)
	actor.energy[3] = 90
	actor.confirm_hit(full_contact)
	check(actor.energy[3] == 90, "Contact at full energy cannot recharge after spending")
	actor.energy[3] = 0
	actor.set_external_attributes({"SkillActive2ChargeSpeed": 1000})
	actor.confirm_hit(hit(10))
	check(is_equal_approx(actor.energy[3], 15.0), "Charge-speed bonus follows source diminishing formula")
	actor.energy[3] = 0
	actor.add_buff("213101")
	check(is_equal_approx(actor.energy[3], 15.0), "Original flat-charge buff also uses charge speed")
	actor.set_external_attributes({"SkillActive2ExtraUseCount": 1})
	actor.energy[3] = 0
	actor.add_buff("50211331")
	check(is_equal_approx(actor.energy[3], 25.0), "Percent-charge buff uses single-cast cost with extra stock")
	actor.cooldowns[3] = 2.5
	actor.add_buff("240402")
	check(is_equal_approx(actor.cooldowns[3], 2.0), "Original cooldown buff reduces remaining time")
	actor.energy[1] = 0
	var before_dodge := float(actor.energy[3])
	actor.add_buff("292312")
	check(actor.energy[1] == actor.skill_cost(1) and actor.energy[3] == before_dodge, "Dodge recovery targets dodge instead of ultimate")
	actor.energy[3] = 100
	check(actor.skill_charge_fraction(3) == 0.5 and actor.skill_charge_fraction(3, true) == 1.0, "Capacity bar and per-cast button normalize separately")
	actor.cooldowns[3] = 2.5
	var saved: Dictionary = JSON.parse_string(JSON.stringify(actor.skill_resource_snapshot()))
	var copy = Combat.new()
	copy.configure()
	copy.set_external_attributes({"SkillActive2ExtraUseCount": 1})
	check(copy.restore_skill_resources(saved) and copy.energy[3] == 100 and copy.cooldowns[3] == 2.5, "SP and cooldown survive JSON resource transfer")
	saved.energy[3] = -1
	check(not copy.restore_skill_resources(saved) and copy.energy[3] == 100, "Malformed resource transfer fails atomically")
	var shielded = Combat.new()
	shielded.configure_enemy(11001)
	shielded.shield = 1000
	var shield_contact := {"damage": 20.0, "definition": {"charge": 2.0, "raw": JSON.stringify({"RecoverSkillCharge": 2, "RecoverSkillChargeChance": 1000})}, "source": actor}
	actor.energy[3] = 0
	shielded.receive(shield_contact, actor.attack)
	actor.confirm_hit(shield_contact)
	check(shield_contact.resolved_damage == 0 and shield_contact.resolved_calculated_damage >= 1 and actor.energy[3] == 2, "Shield absorption keeps calculated-damage SP eligibility")
	var projectile := DungeonProjectile.new()
	projectile.configure({"definition": {}}, Vector3.ZERO, Vector3.BACK, Vector3.ZERO)
	projectile.hit["skill_charge_attempted"] = true
	var projectile_copy := DungeonProjectile.new()
	projectile_copy.restore(JSON.parse_string(JSON.stringify(projectile.snapshot())))
	check(projectile_copy.hit.get("skill_charge_attempted", false), "Projectile save preserves its consumed recovery attempt")
	var hud := DungeonHud.new()
	root.add_child(hud)
	await process_frame
	actor.set_external_attributes({})
	for fraction in [0.0, 0.001, 0.19, 0.37, 0.8, 0.999, 1.0]:
		actor.energy[3] = fraction * actor.skill_capacity(3)
		actor.cooldowns[3] = 0
		hud.update_combat(actor, false)
		check(is_equal_approx(hud.charge.value / hud.charge.max_value, fraction), "HUD reflects continuous %.3f capacity progress" % fraction)
		check(is_equal_approx(hud.skill_by_slot[3].resource_fraction, fraction), "Button reflects continuous %.3f cast progress" % fraction)
	actor.add_buff("100300", 4)
	actor.energy[3] = 37
	hud.update_combat(actor, false)
	check(is_equal_approx(hud.reference_vitals.charge_fraction, 0.8), "Five sword-intent segments follow JP layers")
	check(is_equal_approx(hud.skill_by_slot[3].resource_fraction, 0.37), "Ultimate SP remains independent from sword intent")
	actor.energy[3] = 0
	hud.update_combat(actor, false)
	check(not hud.skill_by_slot[3].ready_full and hud.skill_by_slot[3].unavailable, "Spent ultimate clears full indication")
	var expected_segments := [5, 20, 10, 20, 10, 20, 15, 15]
	for character in range(1, 9):
		var other := Combat.new()
		other.configure(null, null, character)
		hud.update_combat(other, false)
		check(hud.reference_vitals.resource_segments == expected_segments[character - 1], "Character %d uses its original JP slot count" % character)
		check(hud.skill_by_slot[3].resource_color == DungeonTouchButton.skill_resource_color(int(other.fighter.skills[3].element)), "Character %d SP color follows attack element" % character)
	hud.free()
	var report := {"checks": checks, "failures": failures, "passed": failures.is_empty(), "scope": "Eight characters, source SP guards and instance latch, chance, formula, shield calculation, transfer and actual HUD. Static source reconstruction; not APK runtime parity."}
	FileAccess.open("res://reports/burst-progress-test.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("BURST_PROGRESS_TEST ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
