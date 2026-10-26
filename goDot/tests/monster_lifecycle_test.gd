extends SceneTree

const Combat = preload("res://scripts/domain/combat.gd")
const Actor = preload("res://scripts/actor.gd")
var assertions := 0
var failures: Array = []
var catalog: Dictionary

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	catalog = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/combat.json"))
	_test_born_action_gate()
	_test_source_death_timelines()
	_test_actor_disappearance()
	var file = FileAccess.open("res://reports/monster-lifecycle-test.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"assertions": assertions, "failures": failures, "evidence": "APK authored born/dead action timelines and EventDelUnit ARM64 implementation; no APK runtime observation."}, "\t"))
	print("MONSTER LIFECYCLE TEST: %d assertions, %d failures" % [assertions, failures.size()])
	for failure in failures: printerr(failure)
	quit(0 if failures.is_empty() else 1)

func _test_born_action_gate() -> void:
	var wolf = _combat(11001)
	_check(wolf.begin_enemy_spawn(), "Wolf enters the authored born action immediately")
	_check(wolf.current_action == "born", "Wolf starts born")
	_check(not wolf.begin_enemy_spawn(), "Repeated spawn entry does not restart born")
	_check(not wolf.enemy_navigation_requested(), "Born does not request navigation")
	var context = {"target_available": true, "distance": 2.0, "line_blocked": false, "battle_time": 0.0}
	wolf.enemy_ai.blackboard.BB_AttackCDTimer = 3.0
	var result: Dictionary = wolf.tick_enemy_ai(0.0, context)
	_check(result.action == "attack", "Source graph may choose an attack before born ends")
	_check(wolf.current_action == "born", "AI output cannot bypass the source born interrupt time")
	wolf.tick(0.999)
	wolf.tick_enemy_ai(0.0, context)
	_check(wolf.current_action == "born", "Wolf remains born before the source one second gate")
	wolf.tick(0.001)
	wolf.tick_enemy_ai(0.0, context)
	_check(wolf.current_action in ["attack", "attack2"], "Ready wolf starts a source attack only after the authored one second born gate")
	var far_wolf = _combat(11001)
	context.distance = 9.0
	far_wolf.tick_enemy_ai(0.0, context)
	_check(far_wolf.custom_properties.OP_AIAction == "run", "Source graph requests pursuit at long range")
	_check(not far_wolf.enemy_navigation_requested(), "Pending pursuit does not move a monster during born")
	far_wolf.tick(1.0)
	far_wolf.tick_enemy_ai(0.0, context)
	_check(far_wolf.current_action == "run" and far_wolf.enemy_navigation_requested(), "Navigation begins after the actual run action starts")
	var shark = _combat(52002)
	shark.tick_enemy_ai(0.0, context)
	_check(shark.current_action == "born", "Shark starts its own born chain")
	shark.tick(0.017)
	shark.tick_enemy_ai(0.0, context)
	_check(shark.current_action == "born_bosspose", "Shark retains the source 0.017 second opening transition")
	_check(not shark.enemy_navigation_requested(), "Shark opening pose cannot chase")

func _test_source_death_timelines() -> void:
	for enemy in catalog.enemies:
		var combat = _combat(int(enemy.id))
		combat.begin_enemy_spawn()
		combat.drain_events()
		combat.health = 0
		_check(combat.begin_enemy_death(), "Enemy %s starts its source dead action" % enemy.id)
		_check(combat.current_action == "dead", "Enemy %s stops its prior action" % enemy.id)
		_check(not combat.begin_enemy_death(), "Enemy %s death is idempotent" % enemy.id)
		var deletion = _deletion(combat)
		_check(float(deletion.delete) < INF, "Enemy %s has an authored real deletion" % enemy.id)
		combat.tick_enemy_death(float(deletion.delete) - 0.0001)
		_check(not combat.custom_properties.get("_enemy_deleted", false), "Enemy %s persists until its authored deletion time" % enemy.id)
		combat.tick_enemy_death(0.0002)
		_check(combat.custom_properties.get("_enemy_deleted", false), "Enemy %s deletes at its source timeline time" % enemy.id)
		var events: Array = combat.drain_events()
		_check(events.any(func(event): return event.type == "delete_unit" and event.definition.get("Delete", false)), "Enemy %s emits a real deletion to the world" % enemy.id)
		_check(not events.any(func(event): return event.type == "hit"), "Enemy %s does not release old pending attacks after death" % enemy.id)
		_check(combat._pending.is_empty(), "Enemy %s leaves no pending timeline after deletion" % enemy.id)
		_check(not combat.enemy_navigation_requested(), "Enemy %s cannot pursue after death" % enemy.id)

func _test_actor_disappearance() -> void:
	var actor = Actor.new()
	actor.actor_id = 11001
	actor.combat = _combat(actor.actor_id)
	root.add_child(actor)
	actor.set_visual("")
	actor.combat.health = 0
	actor.begin_death()
	var deletion = _deletion(actor.combat)
	_check(actor.dead and actor.collision_layer == 0, "Death immediately removes monster combat collision")
	_check(actor.visual.visible, "Source corpse is visible before its hide event")
	if float(deletion.hide) < float(deletion.delete):
		actor.advance_death(float(deletion.hide) - 0.0001)
		_check(actor.visual.visible, "Corpse remains visible before source hide time")
		actor.advance_death(0.0002)
		_check(not actor.visual.visible, "Delete=false hides the model at its source time")
		_check(not actor.death_finished(), "Visual hiding preserves the later real deletion")
		actor.advance_death(float(deletion.delete) - float(deletion.hide))
	else:
		actor.advance_death(float(deletion.delete) + 0.0001)
	_check(actor.death_finished() and not actor.visible, "Real deletion removes the corpse from the scene")
	_check(actor.collision_mask == 0, "Removed corpse leaves no collision mask")
	actor.free()

func _deletion(combat: RefCounted) -> Dictionary:
	var result = {"hide": INF, "delete": INF}
	for command in combat._action(str(combat.enemy.group), "dead").events:
		if not command.enabled or command.type != "EET_DelUnit": continue
		var raw: Dictionary = JSON.parse_string(command.raw)
		var key = "delete" if raw.get("Delete", true) else "hide"
		result[key] = minf(result[key], float(command.time) / float(combat.custom_properties.get("_feel_action_speed", 1.0)))
	return result

func _combat(id: int) -> RefCounted:
	var combat = Combat.new()
	_check(combat.configure_enemy(id, 55).success, "Configure monster %s" % id)
	return combat

func _check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message)
