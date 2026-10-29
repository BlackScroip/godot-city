extends "res://tests/impact_visual_test.gd"

const BOSS_ID := 13002
const GROUP := "ActGroup_mojiehua"
const EFFECT := "26071801_fx_enemy_mojiehua_attack3_duyejidang"
const CAPTURE_FRAMES := [40, 60, 90, 130, 190, 235]

func _run() -> void:
	var rendered := DisplayServer.get_name() != "headless"
	if not rendered and _arg("headless-diagnostic", "") != "true":
		printerr("FLOWER_POISON_VISUAL requires a graphical renderer")
		quit(1)
		return
	root.size = Vector2i(960, 540)
	Engine.physics_ticks_per_second = HZ
	seed(SEED)
	world = DungeonWorld.new()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.paused = false
	world._background = false
	world.fighting = true
	world.low_effects = _arg("quality", "low") == "low"
	world.presentation.set_process(false)
	world.presentation.suspended = false
	world.presentation.audio_enabled = false
	world.presentation.effects_density = clampi(int(_arg("density", "2")), 0, 2)
	world.presentation.effects_opacity = 1.0
	world.presentation.low_quality = world.low_effects
	_ground()
	world.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	world.camera.size = 14.0
	world.camera.position = Vector3(10, 10, -15)
	world.camera.look_at(Vector3(0, 1, 2))
	var player_combat := DungeonCombat.new()
	player_combat.configure(null, null, 1, 0, SEED)
	player_combat.max_health = 1000000000
	player_combat.health = player_combat.max_health
	world.create_player(player_combat, 1, Vector3(0, 0, 5))
	world.spawn_wave([{"enemy_id": BOSS_ID, "position": Vector3.ZERO}], 0, SEED)
	var boss: DungeonActor = world.actors.back()
	boss.face_direction(Vector3.BACK)
	for actor in world.actors:
		actor.suspended = false
		actor.simulation_scale = 1.0
		actor.set_process(false)
		actor.set_physics_process(false)
	while world.presentation.has_pending_preparation():
		world.presentation.prepare_step()
		await process_frame
	world.presentation.clear()
	await physics_frame
	await process_frame
	var action: Dictionary = boss.combat._action(GROUP, "attack3")
	if action.is_empty():
		failures.append("Flower attack3 not found")
		quit(1)
		return
	var builds_before: int = world.presentation.authored_builds
	boss.combat._start(action, 0)
	var first_frame := -1
	var first_effect_state: Dictionary = {}
	var summon_frame := -1
	var peak := {"emitters": 0, "particles": 0}
	var captures: Array[Dictionary] = []
	var poison_transitions: Array[Dictionary] = []
	for frame in 251:
		for actor in world.actors.duplicate():
			actor.combat.custom_properties["EnemyDistances"] = [actor.position.distance_to(world.player.position)]
			actor.combat.tick(1.0 / HZ)
			for event in actor.combat.drain_events():
				if event.type == "summon" and str(event.get("id", "")) == "41300230": summon_frame = frame
				var previous := _poison_state()
				world._consume(actor, event)
				if not previous.is_empty() and _poison_state().is_empty(): poison_transitions.append({"frame": frame, "step": "consume", "event": event, "previous": previous, "active_after": _active_effects()})
		for actor in world.actors:
			actor._physics_process(1.0 / HZ)
			actor._process(1.0 / HZ)
		world._tick_attack_entities(1.0 / HZ)
		world._tick_projectiles(1.0 / HZ)
		var before_summons := _poison_state()
		world._tick_summons(1.0 / HZ)
		if not before_summons.is_empty() and _poison_state().is_empty(): poison_transitions.append({"frame": frame, "step": "summons", "previous": before_summons})
		var before_presentation := _poison_state()
		world.presentation._process(1.0 / HZ)
		if not before_presentation.is_empty() and _poison_state().is_empty(): poison_transitions.append({"frame": frame, "step": "presentation", "previous": before_presentation, "actor_sequence": boss.combat._cast_sequence, "actor_dead": boss.dead})
		for entry in world.presentation.active:
			if str(entry.key) == EFFECT and first_frame < 0:
				first_frame = frame
				first_effect_state = _poison_state()
		if frame == 235 and _poison_state().is_empty(): failures.append("Poison effect was recycled during the attack before its source lifetime ended")
		peak.emitters = maxi(peak.emitters, world.presentation._active_emitters)
		peak.particles = maxi(peak.particles, world.presentation._active_particles)
		await process_frame
		if rendered and frame in CAPTURE_FRAMES: captures.append(await _capture(boss, frame))
	if first_frame < 29 or first_frame > 30: failures.append("Poison effect did not start at the authored 0.5-second event: " + str(first_frame))
	if summon_frame < 192 or summon_frame > 194: failures.append("Poison summon did not occur at the authored 3.217-second event: " + str(summon_frame))
	if rendered and not captures.any(func(item): return item.frame < 90 and item.changed_pixels >= 12): failures.append("No visible poison charge before 1.5 seconds")
	if rendered and not captures.any(func(item): return item.frame >= 130 and item.changed_pixels >= 12): failures.append("No visible poison effect during the later attack")
	if rendered:
		for captured in captures:
			if captured.frame in [90, 130] and captured.changed_pixels < 100: failures.append("Poison silhouette is too faint at frame " + str(captured.frame))
			if captured.frame == 235 and (captured.hit_roots == 0 or captured.hit_changed_pixels < 3): failures.append("Poison budget protection removed visible hit feedback")
			if captured.frame == 40 and not world.low_effects:
				var stars: Array = captured.layers.filter(func(layer): return layer.layer == "26070901_shoubuxuli_xingxing")
				if stars.size() != 1 or stars[0].changed_pixels < 12 or stars[0].dark_pixels > 0: failures.append("Poison charge star is missing or draws opaque black pixels")
	if world.presentation.authored_builds > builds_before: failures.append("Effect template built during attack")
	if not world.presentation.missing.is_empty(): failures.append("Missing effects: " + str(world.presentation.missing.keys()))
	if not world.presentation.unresolved_anchors.is_empty(): failures.append("Unresolved anchors: " + str(world.presentation.unresolved_anchors.keys()))
	var report := {"passed": failures.is_empty(), "failures": failures, "boss": BOSS_ID, "action": "attack3", "quality": _arg("quality", "low"), "density": world.presentation.effects_density, "hz": HZ, "viewport": str(root.size), "first_effect_frame": first_frame, "first_effect_state": first_effect_state, "summon_frame": summon_frame, "poison_transitions": poison_transitions, "captures": captures, "peak": peak, "runtime_effect_builds": world.presentation.authored_builds - builds_before, "scope": "Scripted attack3 with actual combat events and Godot-rendered source effects; isolated pixel differences are not an original APK runtime comparison or a mobile-device performance measurement."}
	FileAccess.open(_arg("output", "/private/tmp/flower-poison-visual.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("FLOWER_POISON_VISUAL ", JSON.stringify(report))
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _poison_state() -> Dictionary:
	for entry in world.presentation.active:
		if str(entry.key) == EFFECT:
			return {"age": entry.age, "duration": entry.duration, "authored_lifetime": entry.authored.lifetime, "sequence": entry.sequence, "important": entry.important, "particles": entry.authored.particle_count, "emitters": entry.authored.emitters.size(), "layers": _effect_layers(entry.authored), "active_particles": world.presentation._active_particles, "active_emitters": world.presentation._active_emitters, "active_effects": _active_effects()}
	return {}

func _effect_layers(effect: Node3D) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for node in effect.get_children():
		if not node.has_meta("source_layer"): continue
		var emitters := 0
		var particles := 0
		for emitter in effect.emitters:
			if emitter.node.get_parent() != node: continue
			emitters += 1
			particles += int(emitter.node.amount)
		for retained in effect.retained_particles:
			if retained.node.get_parent() != node: continue
			emitters += 1
			particles += 1
		result.append({"layer": str(node.get_meta("source_layer")), "emitters": emitters, "particles": particles})
	return result

func _active_effects() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in world.presentation.active:
		result.append({"key": entry.key, "emitters": entry.authored.emitters.size() if entry.authored else 0, "particles": entry.authored.particle_count if entry.authored else 0, "important": entry.important, "priority": entry.get("priority", false), "summon_token": entry.get("summon_token", 0)})
	return result

func _capture(boss: DungeonActor, frame: int) -> Dictionary:
	var frozen: Array[Dictionary] = []
	var selected: Array[Node3D] = []
	for entry in world.presentation.active:
		if not entry.authored: continue
		for emitter in entry.authored.emitters:
			frozen.append({"node": emitter.node, "speed": emitter.node.speed_scale})
			emitter.node.speed_scale = 0.0
		if str(entry.key) == EFFECT and entry.root.visible: selected.append(entry.root)
	var was_playing := boss.animation != null and boss.animation.is_playing()
	if boss.animation: boss.animation.pause()
	await process_frame
	await RenderingServer.frame_post_draw
	var visible := root.get_texture().get_image()
	var prefix := "/private/tmp/flower-poison-%s-%03d" % [_arg("quality", "low"), frame]
	visible.save_png(prefix + ".png")
	for node in selected: node.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	var baseline := root.get_texture().get_image()
	baseline.save_png(prefix + "-without.png")
	for node in selected: node.show()
	var hit_roots: Array[Node3D] = []
	var hit_changed := 0
	if frame == 235:
		for entry in world.presentation.active:
			if str(entry.key) == "26072201_fx_enemy_mojiehua_attack_hit" and entry.root.visible:
				hit_roots.append(entry.root)
				entry.root.hide()
		await process_frame
		await RenderingServer.frame_post_draw
		var hit_baseline := root.get_texture().get_image()
		hit_baseline.save_png(prefix + "-without-hit.png")
		hit_changed = _different_pixels(visible, hit_baseline)
		for node in hit_roots: node.show()
	var layers: Array[Dictionary] = []
	if (frame == 40 and not world.low_effects) or (frame in [40, 90, 130] and _arg("inspect-layers", "") == "true"): layers = await _inspect_layers(visible)
	for particle in frozen:
		if is_instance_valid(particle.node): particle.node.speed_scale = particle.speed
	if was_playing: boss.animation.play()
	return {"frame": frame, "time": float(frame) / HZ, "selected_roots": selected.size(), "changed_pixels": _different_pixels(visible, baseline), "hit_roots": hit_roots.size(), "hit_changed_pixels": hit_changed, "sample_stride": 2, "image": prefix + ".png", "baseline": prefix + "-without.png", "layers": layers}

func _different_pixels(first: Image, second: Image) -> int:
	var changed := 0
	for y in range(0, first.get_height(), 2):
		for x in range(0, first.get_width(), 2):
			var a := first.get_pixel(x, y)
			var b := second.get_pixel(x, y)
			if maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) > 0.045: changed += 1
	return changed

func _inspect_layers(visible: Image) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in world.presentation.active:
		if str(entry.key) != EFFECT or not entry.authored: continue
		for node in entry.authored.get_children():
			if not node is Node3D or not node.visible: continue
			if _arg("inspect-layers", "") != "true" and str(node.get_meta("source_layer", "")) != "26070901_shoubuxuli_xingxing": continue
			var emitter_count := 0
			var particle_count := 0
			for emitter in entry.authored.emitters:
				if emitter.node.get_parent() != node: continue
				emitter_count += 1
				particle_count += int(emitter.node.amount)
			for retained in entry.authored.retained_particles:
				if retained.node.get_parent() != node: continue
				emitter_count += 1
				particle_count += 1
			node.hide()
			await process_frame
			await RenderingServer.frame_post_draw
			var baseline := root.get_texture().get_image()
			node.show()
			var dark_pixels := 0
			var changed_pixels := 0
			for y in range(0, visible.get_height(), 2):
				for x in range(0, visible.get_width(), 2):
					var a := visible.get_pixel(x, y)
					var b := baseline.get_pixel(x, y)
					if maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) <= 0.045: continue
					changed_pixels += 1
					if maxf(a.r, maxf(a.g, a.b)) < 0.05 and maxf(b.r, maxf(b.g, b.b)) > 0.08: dark_pixels += 1
			result.append({"layer": str(node.get_meta("source_layer", "")), "node": str(node.name), "emitters": emitter_count, "particles": particle_count, "changed_pixels": changed_pixels, "dark_pixels": dark_pixels})
	return result
