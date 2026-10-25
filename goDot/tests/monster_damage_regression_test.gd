extends SceneTree

var checks := 0
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_status_attribution()
	var world := DungeonWorld.new()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.presentation.set_process(false)
	world.presentation.audio_enabled = false
	var player := DungeonActor.new()
	player.is_player = true
	player.combat = DungeonCombat.new()
	player.combat.configure()
	player.combat.actor_key = "player"
	world.add_child(player)
	world.actors.append(player)
	world.player = player
	var monster := DungeonActor.new()
	monster.combat = DungeonCombat.new()
	monster.combat.configure_enemy(12003, 731)
	monster.combat.actor_key = "flower"
	monster.facing = Vector3.BACK
	world.add_child(monster)
	world.actors.append(monster)
	var action = monster.combat._action("ActGroup_senlinyaohua", "attack")
	var definition: Dictionary = action.hits[0].duplicate(true)
	definition.conditions = []
	monster.combat.drain_events()
	monster.combat._emit_hit({"hit": definition, "at": 0.0, "action": action.id, "slot": 0, "sequence": 1})
	var hit: Dictionary = monster.combat.drain_events().filter(func(event): return event.type == "hit")[0]
	check(float(hit.damage) > 0, "Source flower attack retains its recovered damage coefficient")
	for hz in [30, 60, 120]:
		player.position = Vector3(0, 0, 5)
		player.combat.health = player.combat.max_health
		player.combat.clear_impact_state()
		player.invulnerability = 0
		world._projectile(monster, hit.duplicate(true))
		var state: DungeonProjectile = world.projectiles.back().state
		check(not state.intersects(Vector3(3, 0.75, 5)), "High shot cannot hit outside horizontal range %dHz" % hz)
		check(not state.intersects(Vector3(0, -3, 5)), "High shot does not ignore vertical separation %dHz" % hz)
		for frame in hz:
			world._tick_projectiles(1.0 / hz)
		check(player.combat.health < player.combat.max_health, "Authored flower shot damages standing player %dHz" % hz)
		for entry in world.projectiles: world._recycle_projectile(entry)
		world.projectiles.clear()
	var launch := DungeonProjectile.new()
	launch.configure({"definition": {"raw": JSON.stringify({"EmitProperty": {"EmitOffset": {"z": 2}, "EmitRotation": {"y": 90}, "AfterRotateEmitOffset": {"z": 3}}})}}, Vector3.ZERO, Vector3.BACK, Vector3.ZERO)
	check(launch.position.is_equal_approx(Vector3(3, 0, 2)), "Initial offset uses unrotated basis and secondary offset uses emission yaw")
	var copy := DungeonProjectile.new()
	copy.restore(JSON.parse_string(JSON.stringify(launch.snapshot())))
	check(copy.position.is_equal_approx(launch.position), "Corrected launch position survives JSON restore")
	for key in ["ActGroup_feimolong/attack6", "ActGroup_feimolong/attack7_1", "ActGroup_jiaolu/attack7"]:
		var source_action: Dictionary = monster.combat._action_index[key]
		for source_hit in source_action.hits:
			var raw = DungeonWorld._raw_definition(source_hit)
			if not source_hit.projectile or str(raw.get("EmitProperty", {}).get("PosType", "")) not in ["EEPT_TargetPos", "EEPT_TargetPos_Ground"]: continue
			var event = {"definition": source_hit, "damage": 10.0, "target_key": "player"}
			player.position = Vector3(10, 0, 10)
			check(world._hit_origin(monster, event).is_equal_approx(player.position), "Source target-position attack follows player: " + key)
			world._projectile(monster, event)
			var state: DungeonProjectile = world.projectiles.back().state
			var offset = DungeonWorld.vector(raw.EmitProperty.AfterRotateEmitOffset)
			check(state.position.is_equal_approx(player.position + offset), "Source approach attack starts at authored offset: " + key)
			for entry in world.projectiles: world._recycle_projectile(entry)
			world.projectiles.clear()
	var report = {"passed": failures.is_empty(), "checks": checks, "failures": failures}
	FileAccess.open("res://reports/monster-damage-regression.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("MONSTER_DAMAGE_REGRESSION ", JSON.stringify(report))
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _status_attribution() -> void:
	var caster := DungeonCombat.new()
	caster.configure()
	caster.actor_key = "player"
	for mode in ["bound", "restored", "self"]:
		var victim := DungeonCombat.new()
		victim.configure_enemy(11001)
		victim.actor_key = "monster"
		victim._buff_index = {"test_dot": {"type": "EBT_SpecialTriggerRangeDamage", "selfOnlyDamage": true, "fixedDamage": 100, "interval": 1.0}}
		victim.statuses = {"test_dot": {"id": "test_dot", "time": 1.0, "tick": 0.0, "layers": 1, "attack": 1.0, "modifier_cooldown": 0.0}}
		if mode == "bound": victim.bind_buff_caster("test_dot", caster)
		if mode == "restored": victim.statuses.test_dot.caster_key = "player"
		victim.health = 5
		var ticks: Array = []
		victim.impact_confirmed.connect(func(event): ticks.append(event))
		victim.tick(0.02)
		check(ticks.size() == 1 and ticks[0].resolved_damage == 5, "DOT records actual lethal damage once: " + mode)
		check(ticks[0].source_key == ("monster" if mode == "self" else "player") and ticks[0].receiver_key == "monster", "DOT retains caster and victim identity: " + mode)
