extends SceneTree

const Combat = preload("res://scripts/domain/combat.gd")
const Campaign = preload("res://scripts/domain/campaign.gd")
var assertions := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var world := DungeonWorld.new()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	var player_combat = Combat.new()
	player_combat.configure()
	world.create_player(player_combat, 1, Vector3(30, 0, 30))
	world.environment_entry = {"events": [{"id": "300021", "position": {"X": 2, "Y": 0, "Z": -7}}]}
	var child_count := world.get_child_count()
	world.enemy_stage_layer = 2
	world.spawn_wave([
		{"enemy_id": 99999999, "position": Vector3.ZERO},
		{"enemy_id": 11001, "position": Vector3.ZERO, "rotation": {"X": 0, "Y": 90, "Z": 0}, "health_override": 789, "attack_override": 123},
		{"EnemyId": 11001, "Position": {"X": -5, "Y": 1, "Z": 8}, "Rotation": {"X": 0, "Y": 180, "Z": 0}, "HealthOverride": 456, "AttackOverride": 67},
		{"enemy_id": 11001, "position": [4, 0, -2], "born_position": {"X": 6, "Y": 0, "Z": -3}, "rotation": [0, -90, 0]}
	], 2, 17)
	_check(world.actors.size() == 4, "Unknown enemy is skipped while all three valid enemies spawn")
	_check(world.get_child_count() == child_count + 3, "Unknown enemy does not leave an invalid actor child")
	_check(world.diagnostics.has("Unknown spawn enemy: 99999999"), "Unknown enemy produces a retained diagnostic")
	if world.actors.size() == 4:
		var zero: DungeonActor = world.actors[1]
		_check(zero.position.is_equal_approx(Vector3(0, 0.05, 0)), "Authored zero is a valid world spawn, not a player ring fallback")
		_check(zero.born_position.is_equal_approx(zero.position), "Absent born position inherits authored zero")
		_check(zero.facing.is_equal_approx(Vector3.RIGHT) and zero.born_facing.is_equal_approx(Vector3.RIGHT), "Lowercase rotation controls live and initial facing")
		_check(zero.visual != null and is_equal_approx(zero.visual.rotation.y, PI / 2), "Rendered model receives the same authored yaw")
		_check(zero.combat.health == 789 and zero.combat.max_health == 789 and zero.combat.attack == 123, "Health and attack overrides survive real enemy configuration")
		var legacy: DungeonActor = world.actors[2]
		_check(legacy.position.is_equal_approx(Vector3(-5, 1.05, 8)), "Legacy uppercase position preserves every coordinate")
		_check(legacy.born_position.is_equal_approx(legacy.position), "Legacy position becomes the initial position")
		_check(legacy.facing.is_equal_approx(Vector3.FORWARD) and legacy.born_facing.is_equal_approx(Vector3.FORWARD), "Legacy uppercase rotation preserves 180 degree facing")
		_check(legacy.combat.health == 456 and legacy.combat.max_health == 456 and legacy.combat.attack == 67, "Legacy uppercase stat overrides remain compatible")
		var relocated: DungeonActor = world.actors[3]
		_check(relocated.combat.max_health == 3675 and relocated.combat.health == 3675, "Room stage two scales difficulty two wolf HP to source 300 * 12.25")
		_check(relocated.position.is_equal_approx(Vector3(4, 0.05, -2)), "Array world position reaches actual actor")
		_check(relocated.born_position.is_equal_approx(Vector3(6, 0.05, -3)), "Explicit born position is independent of current position")
		_check(relocated.facing.is_equal_approx(Vector3.LEFT) and relocated.born_facing.is_equal_approx(Vector3.LEFT), "Negative yaw preserves direction")
		for actor in [zero, legacy, relocated]:
			_check(actor.previous_position.is_equal_approx(actor.position), "Spawn starts without an artificial previous-position motion")
			_check(actor.field_center.is_equal_approx(Vector3(2, 0, -7)), "APK field center marker reaches each spawned monster")
		_check(zero.combat.actor_key != legacy.combat.actor_key and legacy.combat.actor_key != relocated.combat.actor_key, "Repeated species retain distinct combat actor identities")
	var campaign = Campaign.new()
	_check(campaign.configure(), "Campaign loads for a real room-to-world handoff")
	campaign.start_practice(1010101, 17)
	var spawns: Array = campaign.wave_spawns(1)
	_check(not spawns.is_empty(), "Reference room has a retained first wave")
	var first := world.actors.size()
	world.spawn_wave(spawns, 1, 17)
	_check(world.actors.size() == first + spawns.size(), "World count equals the APK-referenced first wave count")
	for index in spawns.size():
		if first + index >= world.actors.size(): break
		var actor: DungeonActor = world.actors[first + index]
		var spawn: Dictionary = spawns[index]
		var point := DungeonWorld.vector(spawn.position) + Vector3.UP * 0.05
		var yaw := deg_to_rad(DungeonWorld.vector(spawn.rotation).y)
		var direction := Vector3(sin(yaw), 0, cos(yaw))
		_check(actor.actor_id == int(spawn.enemy_id), "Real wave retains the sampled monster species")
		_check(actor.position.is_equal_approx(point) and actor.born_position.is_equal_approx(point), "Real wave retains the exact authored world and born positions")
		_check(actor.facing.is_equal_approx(direction) and actor.born_facing.is_equal_approx(direction), "Real wave retains the exact authored direction")
		_check(actor.visual != null and is_equal_approx(actor.visual.rotation.y, yaw), "Real wave model and gameplay use one authored direction")
	world.free()
	var report = {"passed": failures.is_empty(), "assertions": assertions, "real_room": 1010101, "seed": 17, "real_first_wave_count": spawns.size(), "failures": failures}
	FileAccess.open("res://reports/monster-spawn-world.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("MONSTER SPAWN WORLD: %d assertions, %d failures" % [assertions, failures.size()])
	for failure in failures: printerr(failure)
	quit(0 if failures.is_empty() else 1)

func _check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message)
