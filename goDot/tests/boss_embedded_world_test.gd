extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _flush(presentation: Node3D) -> void:
	var count := 0
	while presentation.has_pending_preparation() or not presentation._boss_embedded_queue.is_empty():
		presentation._process(0.016)
		count += 1
		if count > 10000:
			check(false, "World presentation preparation terminates")
			return
		await process_frame

func _run() -> void:
	var world := DungeonWorld.new()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.presentation.set_process(false)
	var player_combat := DungeonCombat.new()
	player_combat.configure()
	world.create_player(player_combat, 1, Vector3(2, 0, 2))
	world.spawn_wave([{"enemy_id": 52003, "position": Vector3.ZERO}, {"enemy_id": 53001, "position": Vector3(3, 0, 0)}], 0, 42)
	var reaper: DungeonActor = world.actors.filter(func(actor): return actor.actor_id == 52003)[0]
	var dragon: DungeonActor = world.actors.filter(func(actor): return actor.actor_id == 53001)[0]
	check(world.presentation._boss_embedded_actors.has(reaper.get_instance_id()), "World registers reaper on spawn")
	check(world.presentation._boss_embedded_actors.has(dragon.get_instance_id()), "World registers dragon on spawn")
	await _flush(world.presentation)
	check(world.presentation._boss_embedded_live.get(reaper.get_instance_id(), {}).size() == 4, "World spawn initializes all reaper roots")
	check(not world.presentation._boss_embedded_live.has(dragon.get_instance_id()), "World spawn leaves dragon phase roots disabled")
	var roar: Dictionary = dragon.combat._action(str(dragon.combat.enemy.group), "roar1")
	for command in roar.events:
		if command.get("enabled", false) and command.get("type", "") == "EET_SetGameObjectActive":
			world.presentation.command(dragon, {"command": command, "sequence": dragon.combat._cast_sequence})
	await _flush(world.presentation)
	check(world.presentation._boss_embedded_live.get(dragon.get_instance_id(), {}).size() == 11, "World actor runs the APK fire/wind activation")
	world._die(reaper)
	world.presentation.sync_buffs(world.actors)
	check(reaper.dead and not world.presentation._boss_embedded_live.has(reaper.get_instance_id()), "World death clears reaper ownership")
	check(world.presentation._boss_embedded_live.has(dragon.get_instance_id()), "World death preserves another boss's effects")
	world.free()
	print("BOSS_EMBEDDED_WORLD ", JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
