extends "res://tests/spirit_world_abilities_test.gd"

func _run() -> void:
	world = ObservedWorld.new()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.presentation.set_process(false)
	world.presentation.audio_enabled = false
	world.low_effects = true
	var audit: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://reports/boss-ability-source.json"))
	var ids: Array = audit.get("fresh_source_parity", {}).get("closure_ids", {}).get("summon", [])
	_check(bool(audit.get("passed", false)) and ids.size() >= 134, "Source audit provides the complete current-APK Boss summon closure")
	for id in ids:
		_reset()
		world.player.position = Vector3(0, 0, 1)
		world.player.combat.max_health = 1000000000
		world.player.combat.health = world.player.combat.max_health
		var boss := _actor("boss", false, Vector3.ZERO)
		boss.actor_id = 52001
		boss.combat.configure_enemy(52001, 191)
		boss.combat.actor_key = "boss"
		boss.face_direction(Vector3.BACK)
		_check(boss.combat.spawn_summon(str(id), {"world_position": [0.0, 0.0, 0.0]}, "player"), "Boss source summon exists: " + str(id))
		for frame in 350:
			boss.combat.custom_properties["EnemyDistances"] = [boss.position.distance_to(world.player.position)]
			_step()
		var created: Array = world.summons.map(func(unit): return unit.id)
		_check(created.has(str(id)), "Boss summon reaches the real world adapter: " + str(id))
		var issues: Array = world.diagnostics.filter(func(message): return "Missing " in message or "Unsupported " in message or "recursion" in message)
		_check(issues.is_empty(), "Boss summon world dispatch has no missing or unsupported branch: " + str(id))
		rows.append({"id": str(id), "created": created, "contacts": world.impacts.size(), "diagnostics": world.diagnostics.duplicate()})
		await process_frame
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "summons": rows, "missing_effects": world.presentation.missing.keys(), "scope": "Every current-APK Boss summon dependency is spawned and advanced seven seconds through real domain/world adapters in a controlled stationary arena. This checks adapter dispatch, child chains and diagnostics; one representative caster does not exercise every owner-specific condition, lifetime, AI context, rendered pixel or original APK behavior."}
	FileAccess.open("res://reports/boss-summon-world.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("BOSS_SUMMON_WORLD ", JSON.stringify({"passed": failures.is_empty(), "checks": checks, "summons": rows.size(), "failures": failures, "missing_effects": world.presentation.missing.keys()}))
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
