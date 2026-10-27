extends SceneTree

var checks := 0
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func combat() -> DungeonCombat:
	var actor := DungeonCombat.new()
	actor.configure(null, null, 1, 0, 541)
	actor.max_health = 1000000
	actor.health = actor.max_health
	return actor

func _initialize() -> void:
	for spec in [["50202100", "SubActiveSkill", "50202102"], ["50202300", "DodgeAtk", "50202301"]]:
		var player := combat()
		player.actor_key = "player"
		var enemy := combat()
		enemy.actor_key = "enemy"
		player.add_buff(spec[0])
		player.drain_events()
		enemy.receive({"source": player, "damage": 10.0, "sequence": 1, "emission": 1, "definition": {"actType": spec[1]}}, player.attack)
		var own_summons := player.drain_events().filter(func(event): return event.type == "summon" and str(event.id) == spec[2])
		check(own_summons.size() == 1, "Spirit %s summons on caster" % spec[0])
		if not own_summons.is_empty():
			check(own_summons[0].get("target_key", "") == "enemy", "Spirit summon retains hit target position")
		check(enemy.drain_events().filter(func(event): return event.type == "summon").is_empty(), "Victim does not own hostile spirit summons")
	var dark := combat()
	dark.add_buff("50202600")
	for frame in 299: dark.tick(0.1)
	check(dark.buff_layers("50202601") == 0, "Dark spirit waits configured 30 seconds")
	dark.tick(0.2)
	check(dark.buff_layers("50202601") == 1, "Dark spirit applies timed buff")
	check(is_equal_approx(dark.attribute("NormalAtkDamageRate"), 600.0), "Dark spirit increases normal damage by 60 percent")
	for frame in 51: dark.tick(0.1)
	check(dark.buff_layers("50202601") == 0, "Dark spirit burst expires after 5 seconds")
	var water := combat()
	var target := combat()
	water.add_buff("50202200")
	for hit in 12:
		target.receive({"source": water, "damage": 10.0, "sequence": hit + 1, "emission": hit + 1, "definition": {"actType": "NormalAtk"}}, water.attack)
		water.tick(0.11)
	check(water.buff_layers("50202201") == 5, "Water spirit caps normal hit stacks at five")
	water.drain_events()
	target.receive({"source": water, "damage": 10.0, "sequence": 2, "emission": 2, "definition": {"actType": "SpecAtk"}}, water.attack)
	var shots := 0
	for frame in 60:
		water.tick(0.02)
		shots += water.drain_events().filter(func(event): return event.type == "summon" and str(event.id) == "50202201").size()
	check(shots == 5 and water.buff_layers("50202201") == 0, "Heavy hit consumes five stacks and fires five water rays")
	var upgraded_water := combat()
	upgraded_water.add_buff("50202210")
	for hit in 16:
		target.receive({"source": upgraded_water, "damage": 10.0, "sequence": hit + 1, "emission": hit + 1, "definition": {"actType": "NormalAtk"}}, upgraded_water.attack)
		upgraded_water.tick(0.11)
	check(upgraded_water.buff_layers("50202201") == 7, "Upgraded water raises stack cap to seven")
	var upgraded_dark := combat()
	upgraded_dark.add_buff("50202610")
	for frame in 301: upgraded_dark.tick(0.1)
	check(upgraded_dark.buff_layers("50202601") == 1 and is_equal_approx(upgraded_dark.attribute("NormalAtkDamageRate"), 800.0), "Upgraded dark uses upgraded damage value")
	for frame in 52: upgraded_dark.tick(0.1)
	check(upgraded_dark.buff_layers("50202601") == 1, "Upgraded dark burst lasts six seconds")
	print(JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
