extends "res://tests/impact_visual_test.gd"

const REPRESENTATIVE_BOSS_ACTIONS = {13001: "attack", 23001: "attack5", 33001: "attack2", 43001: "attack3", 52001: "attack4", 52002: "attack5", 52003: "ComboAttack1", 53001: "attack5"}

func _run() -> void:
	root.size = Vector2i(960, 540)
	world = DungeonWorld.new()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.presentation.set_process(false)
	world.presentation.audio_enabled = false
	world.presentation.low_quality = _arg("quality", "full") == "low"
	_ground()
	world.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	var canvas := CanvasLayer.new()
	root.add_child(canvas)
	label = Label.new()
	label.position = Vector2(24, 18)
	label.theme = DungeonStyle.theme()
	label.add_theme_font_size_override("font_size", 20)
	canvas.add_child(label)
	var fixture := DungeonCombat.new()
	fixture.configure()
	for enemy in fixture.catalog.enemies:
		if _arg("enemy", "") != "" and int(_arg("enemy", "0")) != int(enemy.id): continue
		await _monster(enemy, fixture)
	var report = {"passed": failures.is_empty(), "failures": failures, "shots": rows, "rendered": DisplayServer.get_name() != "headless", "quality": _arg("quality", "full"), "scope": "One source-authored representative action for each of 39 monsters, with real actor animation, effects, projectiles, summons and warning dispatch. Isolated casts preserve source event conditions; source AI selection and mobile frame rate are validated separately."}
	var report_name = _arg("quality", "full") + ("-" + _arg("enemy", "") if _arg("enemy", "") != "" else "") + ("-complete" if _arg("complete", "false") == "true" else "")
	FileAccess.open("res://reports/monster-presentation-visual-%s.json" % report_name, FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("MONSTER_PRESENTATION_VISUAL ", JSON.stringify({"passed": report.passed, "failures": failures, "shots": rows.size(), "rendered": report.rendered}))
	world.queue_free()
	canvas.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _selected_action(enemy: Dictionary, fixture: DungeonCombat) -> Dictionary:
	if REPRESENTATIVE_BOSS_ACTIONS.has(int(enemy.id)): return fixture._action(str(enemy.group), REPRESENTATIVE_BOSS_ACTIONS[int(enemy.id)])
	var selected: Dictionary = {}
	var best := -1
	for name in enemy.actions:
		if "attack" not in str(name).to_lower(): continue
		var action = fixture._action(str(enemy.group), str(name))
		var score := 0
		for command in action.get("events", []):
			if command.get("enabled", false) and command.get("type", "") == "EET_PlayEffect": score += 1
		if score > best:
			best = score
			selected = action
	if selected.is_empty(): selected = fixture._action(str(enemy.group), "run")
	return selected

func _monster(enemy: Dictionary, fixture: DungeonCombat) -> void:
	world.presentation.clear()
	for projectile in world.projectiles:
		if is_instance_valid(projectile.visual): projectile.visual.queue_free()
	world.projectiles.clear()
	for unit in world.summon_units:
		if is_instance_valid(unit.get("visual")): unit.visual.queue_free()
	world.summon_units.clear()
	for actor in world.actors: actor.queue_free()
	world.actors.clear()
	world.player = null
	await process_frame
	var combat := DungeonCombat.new()
	combat.configure()
	combat.max_health = 1000000000
	combat.health = combat.max_health
	var player = world.create_player(combat, 1, Vector3(0, 0, 4))
	world.spawn_wave([{"enemy_id": int(enemy.id), "position": Vector3.ZERO}], 0, SEED)
	var monster: DungeonActor = world.actors.back()
	monster.facing = Vector3.BACK
	while world.presentation.has_pending_preparation():
		world.presentation.prepare_step()
		await process_frame
	var action = _selected_action(enemy, fixture)
	if action.is_empty():
		failures.append("No representative source action %d" % int(enemy.id))
		return
	label.text = "%d  %s  |  %s  |  %s" % [int(enemy.id), enemy.name, str(action.id), _arg("quality", "full").to_upper()]
	var sample := 0.4
	for command in action.get("events", []):
		if not command.get("enabled", false) or command.get("type", "") != "EET_PlayEffect" or not command.get("conditions", []).is_empty(): continue
		var name = str(DungeonWorld._raw_definition(command).get("EffectTriggerDef", {}).get("EffectName", "")).to_lower()
		if name.is_empty() or "attackprompt" in name or "enemyatkrange" in name: continue
		sample = maxf(sample, minf(float(command.time) + 0.16, 2.5))
		break
	monster.combat._start(action, 0)
	var before_effects: int = world.presentation.spawned
	var warnings := 0
	var max_effects := 0
	var max_emitters := 0
	var captures: Array[String] = []
	var frames = maxi(70, int(sample * 60.0) + 18)
	if _arg("complete", "false") == "true": frames = maxi(frames, int(float(action.duration) * 60.0) + 18)
	var screenshot_frames: Array[int] = [maxi(1, int(sample * 60.0)), frames - 1]
	if _arg("complete", "false") == "true": screenshot_frames.append_array([138, 270])
	for frame in frames:
		for actor in world.actors.duplicate():
			actor.combat.custom_properties["EnemyDistances"] = [actor.position.distance_to(player.position)]
			actor.combat.tick(1.0 / 60.0)
			for event in actor.combat.drain_events(): world._consume(actor, event)
		for actor in world.actors: actor._physics_process(1.0 / 60.0)
		world._tick_projectiles(1.0 / 60.0)
		world._tick_summons(1.0 / 60.0)
		world.presentation._process(1.0 / 60.0)
		warnings = maxi(warnings, world.presentation.telegraphs.filter(func(entry): return entry.node.visible).size())
		max_effects = maxi(max_effects, world.presentation.active.size())
		max_emitters = maxi(max_emitters, world.presentation._active_emitters)
		world.camera.size = maxf(10.0, maxf(monster.impact_bounds.size.x, monster.impact_bounds.size.y) * 2.4)
		world.camera.position = monster.position + Vector3(8, 12, -16)
		world.camera.look_at(monster.position + Vector3.UP * monster.impact_bounds.get_center().y)
		await process_frame
		if frame in screenshot_frames and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var path = "res://reports/monster-%d-%s%s-%d.png" % [int(enemy.id), _arg("quality", "full"), "-complete" if _arg("complete", "false") == "true" else "", frame]
			root.get_texture().get_image().save_png(path)
			captures.append(path)
	rows.append({"enemy": enemy.id, "name": enemy.name, "rank": enemy.rank, "action": action.id, "frames": frames, "effects": world.presentation.spawned - before_effects, "peak_effects": max_effects, "peak_emitters": max_emitters, "peak_warnings": warnings, "captures": captures})
	print("MONSTER_SHOT ", int(enemy.id), " ", action.id, " effects=", world.presentation.spawned - before_effects)
