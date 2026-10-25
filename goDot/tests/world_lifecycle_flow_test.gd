extends SceneTree

const Combat = preload("res://scripts/domain/combat.gd")
var assertions := 0
var failures: Array[String] = []
var results: Dictionary = {}

class DropProbe extends RefCounted:
	var profile := {"data": {"run": {"active": true, "inventory": {}}}}
	var drop_calls := 0
	var grants: Dictionary = {}
	func monster_drops(_enemy_id: int) -> Array[Dictionary]:
		drop_calls += 1
		return [{"id": 101, "amount": 7, "material": true}]

	func grant_material(id: int, amount: int) -> void:
		grants[id] = int(grants.get(id, 0)) + amount

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for action in ["move_left", "move_right", "move_up", "move_down"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	await _test_spawn_and_born_gate()
	await _test_wave_clear_gates()
	await _test_pause_and_restore()
	await _test_world_death_and_drops()
	var report := {"passed": failures.is_empty(), "assertions": assertions, "failures": failures, "results": results, "scope": "Real DungeonWorld lifecycle in an empty physical arena, source enemy actions and true death/drop dispatch. APK timing is supported by shipped ARM64 evidence; no APK runtime observation."}
	FileAccess.open("res://reports/world-lifecycle-flow.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("WORLD LIFECYCLE FLOW: %d assertions, %d failures" % [assertions, failures.size()])
	for failure in failures: printerr(failure)
	quit(0 if failures.is_empty() else 1)

func _world() -> DungeonWorld:
	var world := DungeonWorld.new()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.auto_attack_enabled = false
	world.low_effects = true
	world.catalog = {}
	world.presentation.set_process(false)
	world.presentation.audio_enabled = false
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(200, 1, 200)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	world.add_child(floor_body)
	floor_body.position.y = -0.5
	var navigation := NavigationRegion3D.new()
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-99, 0, -99), Vector3(-99, 0, 99), Vector3(99, 0, 99), Vector3(99, 0, -99)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	navigation.navigation_mesh = mesh
	world.add_child(navigation)
	world.navigation_region = navigation
	NavigationServer3D.map_force_update(world.get_world_3d().navigation_map)
	var combat = Combat.new()
	combat.configure()
	combat.max_health = 1000000000.0
	combat.health = combat.max_health
	world.create_player(combat, 1, Vector3(80, 0, 80))
	return world

func _spawns(count: int) -> Array:
	var result: Array = []
	for index in count:
		result.append({"enemy_id": 11001, "position": [float(index) * 3.0, 0, 0]})
	return result

func _test_spawn_and_born_gate() -> void:
	var world := _world()
	world.player.position = Vector3(9, 0.05, 0)
	await physics_frame
	world.start_wave(_spawns(3), 1, 71)
	_check(world.actors.size() == 2 and world.wave_spawn_queue.size() == 2, "First enemy appears immediately while the other two remain queued")
	_check(world._enemy_count() == 3, "Queued enemies prevent an early wave clear")
	var first: DungeonActor = world.actors[1]
	_check(first.combat.current_action == "born", "World starts the source born action at creation")
	world._physics_process(0.199)
	_check(world.actors.size() == 2, "Second enemy does not appear before 0.2 seconds")
	_check(first.desired_velocity.is_zero_approx(), "Pending run AI cannot move an enemy during born")
	world._physics_process(0.001)
	_check(world.actors.size() == 3 and world.wave_spawn_queue.size() == 1, "Second enemy appears after the APK 0.2 second interval")
	world._physics_process(0.199)
	_check(world.actors.size() == 3, "Third enemy does not appear before the next interval")
	world._physics_process(0.001)
	_check(world.actors.size() == 4 and world.wave_spawn_queue.is_empty(), "Third enemy appears at 0.4 seconds")
	world._physics_process(0.599)
	_check(first.combat.current_action == "born" and first.desired_velocity.is_zero_approx(), "First enemy remains still through 0.999 seconds of its born action")
	world._physics_process(0.002)
	await physics_frame
	world._physics_process(0.001)
	await physics_frame
	world._physics_process(0.001)
	_check(first.combat.current_action == "run" and first.desired_velocity.length_squared() > 0, "World starts pursuit only after the one second source born gate: action=%s, velocity=%s, position=%s, target=%s, path=%s" % [first.combat.current_action, first.desired_velocity, first.position, first.navigation.target_position, first.navigation.get_current_navigation_path()])
	results["spawn_interval"] = 0.2
	results["born_gate"] = 1.0
	world.free()
	await process_frame

func _test_wave_clear_gates() -> void:
	var world := _world()
	var clears := {"count": 0}
	world.wave_cleared.connect(func(): clears.count += 1)
	await physics_frame
	world.start_wave([], 1, 72)
	for index in 3: world._physics_process(0.5)
	world._physics_process(0.49)
	_check(clears.count == 0, "Empty ordinary wave cannot finish before the APK two second observation gate")
	world._physics_process(0.011)
	_check(clears.count == 1, "Ordinary wave finishes once the two second gate passes")
	world._physics_process(1.0)
	_check(clears.count == 1, "Ordinary wave emits completion once")
	world.start_wave([], 1, 73, 0.0, true)
	for index in 4: world._physics_process(0.5)
	_check(clears.count == 1 and is_equal_approx(world._wave_clear_remaining, 0.05), "Final wave starts its extra 0.05 second wait after the two second gate")
	world._physics_process(0.049)
	_check(clears.count == 1, "Final completion remains blocked before the extra wait finishes")
	world._physics_process(0.0011)
	_check(clears.count == 2, "Final wave completes after its extra 0.05 seconds")
	world.start_wave(_spawns(2), 1, 74, 1.0)
	_check(world.actors.size() == 1 and world.wave_spawn_queue.size() == 2, "Next wave waits before its first enemy appears")
	world._physics_process(0.999)
	_check(world.actors.size() == 1, "Next wave respects the source one second delay")
	world._physics_process(0.001)
	_check(world.actors.size() == 2 and world.wave_spawn_queue.size() == 1, "Next wave creates its first enemy at one second")
	world._physics_process(0.199)
	_check(world.actors.size() == 2, "Delayed next wave still spaces its second spawn")
	world._physics_process(0.001)
	_check(world.actors.size() == 3 and world.wave_spawn_queue.is_empty(), "Delayed next wave retains the 0.2 second spawn interval")
	_check(clears.count == 2, "Living enemies still block completion after delayed creation")
	results["ordinary_clear_gate"] = 2.0
	results["final_extra_wait"] = 0.05
	results["next_wave_delay"] = 1.0
	world.free()
	await process_frame

func _test_pause_and_restore() -> void:
	var world := _world()
	await physics_frame
	world.start_wave(_spawns(3), 2, 812, 1.0, true)
	world._physics_process(0.25)
	world.paused = true
	var snapshot := world.transient_snapshot()
	var elapsed_before: float = world.elapsed
	world._physics_process(5.0)
	_check(world.wave_spawn_queue.size() == 3 and world.actors.size() == 1, "Pause freezes queued enemy creation")
	_check(is_equal_approx(world.elapsed, elapsed_before), "Pause freezes battle time")
	_check(is_equal_approx(world._wave_spawn_wait, snapshot.wave_spawn_wait) and is_equal_approx(world._wave_gate_remaining, snapshot.wave_gate), "Pause freezes source spawn and clear timers")
	var restored := _world()
	restored.start_wave([], 1, 0)
	restored.restore_transients(snapshot)
	_check(restored.wave_spawn_queue == snapshot.wave_spawns, "Transient restore preserves enemy identities, difficulty, seeds and order")
	_check(is_equal_approx(restored._wave_spawn_wait, 0.75) and is_equal_approx(restored._wave_gate_remaining, 2.75), "Transient restore preserves remaining delay and observation gate")
	_check(restored._wave_final and restored._wave_clear_remaining < 0, "Transient restore preserves final wave state")
	restored._physics_process(0.749)
	_check(restored.actors.size() == 1, "Restored next wave cannot spawn early")
	restored._physics_process(0.001)
	_check(restored.actors.size() == 2 and restored.wave_spawn_queue.size() == 2, "Restored delay resumes at the original next spawn time")
	world.free()
	restored.free()
	await process_frame
	world = _world()
	world.start_wave([], 1, 2, 0.0, true)
	for index in 4: world._physics_process(0.5)
	world._physics_process(0.02)
	snapshot = world.transient_snapshot()
	_check(is_equal_approx(snapshot.wave_clear_wait, 0.03), "Snapshot records a partially elapsed final wait")
	restored = _world()
	var clears := {"count": 0}
	restored.wave_cleared.connect(func(): clears.count += 1)
	restored.start_wave([], 1, 3)
	restored.restore_transients(snapshot)
	restored._physics_process(0.029)
	_check(clears.count == 0, "Restored final wait cannot complete early")
	restored._physics_process(0.0011)
	_check(clears.count == 1, "Restored final wait finishes after its exact remaining duration")
	world.free()
	restored.free()
	await process_frame

func _test_world_death_and_drops() -> void:
	var world := _world()
	var probe := DropProbe.new()
	world.systems = probe
	var counts := {"defeated": 0, "cleared": 0}
	world.enemy_defeated.connect(func(_id): counts.defeated += 1)
	world.wave_cleared.connect(func(): counts.cleared += 1)
	var spawns: Array = []
	for enemy in world.player.combat.catalog.enemies:
		spawns.append({"enemy_id": int(enemy.id), "position": [float(spawns.size() % 8) * 3, 0, float(spawns.size() / 8) * 3]})
	await physics_frame
	world.spawn_wave(spawns, 1, 99)
	var enemies := world.actors.slice(1)
	var longest := 0.0
	for actor in enemies:
		actor.combat.health = 0
		world._die(actor)
		world._die(actor)
		_check(actor.dead and actor.collision_layer == 0, "Monster %s death immediately removes combat collision" % actor.actor_id)
		_check(actor.combat.current_action == "dead", "Monster %s world dispatch starts the authored dead action" % actor.actor_id)
		for command in actor.combat._action(str(actor.combat.enemy.group), "dead").events:
			if command.enabled and command.type == "EET_DelUnit":
				var raw: Dictionary = JSON.parse_string(command.raw)
				if raw.get("Delete", true): longest = maxf(longest, float(command.time) / float(actor.combat.custom_properties.get("_feel_action_speed", 1)))
	_check(probe.drop_calls == spawns.size() and counts.defeated == spawns.size(), "Repeated world death dispatch grants one drop roll and defeat signal per monster")
	_check(world.ground_loot.entries.size() == spawns.size(), "Actual world death creates one visible coin drop for every probe result")
	_check(world._enemy_count() == 0 and world.actors.size() > 1, "Corpses immediately stop blocking clear while their authored animation remains")
	world._physics_process(0.001)
	_check(world.actors.size() > 1, "Dead monsters remain until their source delete events")
	for frame in int(ceil((longest + 0.1) * 100)):
		world._physics_process(0.01)
	_check(world.actors.size() == 1, "World removes every authored corpse once its death timeline finishes")
	_check(enemies.all(func(actor): return is_instance_valid(actor) and actor.is_queued_for_deletion() and not actor.visible), "Every finished corpse is invisible and queued for scene deletion")
	_check(probe.drop_calls == spawns.size() and counts.defeated == spawns.size() and world.defeated_count == spawns.size(), "Later death ticks never roll additional drops or inflate defeat counts")
	var remaining := 0
	for entry in world.ground_loot.entries: remaining += int(entry.amount)
	_check(remaining + int(probe.grants.get(101, 0)) == spawns.size() * 7, "Automatic coin attraction preserves each single death reward")
	await process_frame
	_check(enemies.all(func(actor): return not is_instance_valid(actor)), "Source deletion actually frees all corpse nodes on the next scene flush")
	results["source_death_count"] = spawns.size()
	results["longest_source_death"] = longest
	results["drop_calls"] = probe.drop_calls
	world.free()
	await process_frame

func _check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message)
