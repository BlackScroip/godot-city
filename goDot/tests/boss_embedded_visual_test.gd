extends "res://tests/impact_visual_test.gd"

const PHASES := {
	"reaper": {"boss": 52003, "names": []},
	"fire": {"boss": 53001, "names": ["24122501_fx_enemy_feimolong_firewindbuff_behind", "24122501_fx_enemy_feimolong_firewindbuff_front", "24122501_fx_enemy_feimolong_firewindbuff_trail"]},
	"water": {"boss": 53001, "names": ["24122502_fx_enemy_feimolong_waterthunderbuff_behind", "24122502_fx_enemy_feimolong_waterthunderbuff_body", "24122502_fx_enemy_feimolong_waterthunderbuff_front", "24122502_fx_enemy_feimolong_waterthunderbuff_wing"]},
	"light": {"boss": 53001, "names": ["24122503_fx_enemy_feimolong_lightdarkbuff_behind", "24122503_fx_enemy_feimolong_lightdarkbuff_front", "24122503_fx_enemy_feimolong_lightdarkbuff_wing"]}
}

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("BOSS_EMBEDDED_VISUAL requires a graphical renderer")
		quit(1)
		return
	root.size = Vector2i(960, 540)
	world = DungeonWorld.new()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.presentation.set_process(false)
	world.presentation.audio_enabled = false
	world.presentation.effects_density = 2
	_ground()
	world.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	world.camera.size = 14
	world.camera.position = Vector3(10, 8, -14)
	world.camera.look_at(Vector3(0, 2, 0))
	for low in [false, true]:
		if not _arg("quality", "").is_empty() and low != (_arg("quality", "") == "low"): continue
		for phase in PHASES:
			if not _arg("phase", "").is_empty() and phase != _arg("phase", ""): continue
			await _check_phase(phase, PHASES[phase], low)
	var report := {"passed": failures.is_empty(), "failures": failures, "rows": rows,
		"scope": "Recovered model-bound effects rendered on imported Godot models; pixel differences isolate the active roots, not a comparison with original APK runtime or mobile performance."}
	FileAccess.open(_arg("output", "/private/tmp/boss-embedded-visual.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("BOSS_EMBEDDED_VISUAL ", JSON.stringify(report))
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _check_phase(phase: String, definition: Dictionary, low: bool) -> void:
	world.presentation.clear()
	for previous in world.actors: previous.queue_free()
	world.actors.clear()
	world._actor_index.clear()
	await process_frame
	world.low_effects = low
	world.presentation.low_quality = low
	world.spawn_wave([{"enemy_id": definition.boss, "position": Vector3.ZERO}], 0, SEED)
	var boss: DungeonActor = world.actors.back()
	boss.set_process(false)
	boss.set_physics_process(false)
	while world.presentation.has_pending_preparation():
		world.presentation.prepare_step()
		await process_frame
	world.presentation.clear()
	world.presentation.register_boss_embedded(boss)
	if not definition.names.is_empty():
		world.presentation.command(boss, {"sequence": boss.combat._cast_sequence, "command": {"type": "EET_SetGameObjectActive", "raw": JSON.stringify({"gameobjectNames": definition.names, "booleanToSet": true})}})
	if phase == "fire" and boss.animation: boss.animation.play("attack2")
	var captures: Array[Dictionary] = []
	for frame in 151:
		if phase == "fire": boss.position.x = 1.4 * sin(float(frame) * 0.04)
		world.presentation._process(1.0 / HZ)
		await process_frame
		if frame in [45, 100, 150]: captures.append(await _capture(phase, boss, low, frame))
	var live: Dictionary = world.presentation._boss_embedded_live.get(boss.get_instance_id(), {})
	if live.is_empty(): failures.append("%s %s has no active embedded effects" % [phase, low])
	if not captures.any(func(item): return item.changed_pixels >= 3): failures.append("%s %s has no visibly rendered embedded effects" % [phase, low])
	if phase == "fire" and not captures.any(func(item): return item.trail_changed_pixels >= 3): failures.append("%s %s has no visible moving wing trails" % [phase, low])
	if not world.presentation.unresolved_anchors.is_empty(): failures.append("%s %s has unresolved model anchors" % [phase, low])
	rows.append({"phase": phase, "boss": definition.boss, "low_quality": low, "active_roots": live.size(), "captures": captures})

func _capture(phase: String, boss: DungeonActor, low: bool, frame: int) -> Dictionary:
	var frozen: Array[Dictionary] = []
	for entry in world.presentation.active:
		if not entry.authored: continue
		for emitter in entry.authored.emitters:
			frozen.append({"node": emitter.node, "speed": emitter.node.speed_scale})
			emitter.node.speed_scale = 0.0
	var was_playing := boss.animation != null and boss.animation.is_playing()
	if boss.animation: boss.animation.pause()
	await process_frame
	await RenderingServer.frame_post_draw
	var visible := root.get_texture().get_image()
	var prefix := "/private/tmp/boss-embedded-%s-%s-%03d" % [phase, "low" if low else "full", frame]
	visible.save_png(prefix + ".png")
	var hidden: Array[Node3D] = []
	for entry in world.presentation._boss_embedded_live.get(boss.get_instance_id(), {}).values():
		if entry.root.visible:
			hidden.append(entry.root)
			entry.root.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	var baseline := root.get_texture().get_image()
	baseline.save_png(prefix + "-without.png")
	for node in hidden: node.show()
	var trails: Array[MeshInstance3D] = []
	var trail_debug: Array[Dictionary] = []
	for entry in world.presentation._boss_embedded_live.get(boss.get_instance_id(), {}).values():
		for trail in entry.get("active_boss_trails", []):
			if trail.node.visible:
				if "--trail-debug" in OS.get_cmdline_user_args():
					var arrays: Array = trail.node.mesh.surface_get_arrays(0)
					trail_debug.append({"samples": trail._points.size(), "vertices": arrays[Mesh.ARRAY_VERTEX].size(), "colors": str(arrays[Mesh.ARRAY_COLOR]), "aabb": str(trail.node.get_aabb()), "world_transform": str(trail.node.global_transform), "visible_in_tree": trail.node.is_visible_in_tree()})
				trails.append(trail.node)
				trail.node.hide()
	var trail_changed := 0
	if not trails.is_empty():
		await process_frame
		await RenderingServer.frame_post_draw
		var without_trails := root.get_texture().get_image()
		without_trails.save_png(prefix + "-without-trails.png")
		trail_changed = _different_pixels(visible, without_trails)
		for trail in trails: trail.show()
	for particle in frozen:
		if is_instance_valid(particle.node): particle.node.speed_scale = particle.speed
	if was_playing: boss.animation.play()
	return {"frame": frame, "active_roots": hidden.size(), "active_trails": trails.size(), "changed_pixels": _different_pixels(visible, baseline), "trail_changed_pixels": trail_changed, "trail_debug": trail_debug, "image": prefix + ".png", "baseline": prefix + "-without.png", "sample_stride": 2}

func _different_pixels(first: Image, second: Image) -> int:
	var changed := 0
	for y in range(0, first.get_height(), 2):
		for x in range(0, first.get_width(), 2):
			var a := first.get_pixel(x, y)
			var b := second.get_pixel(x, y)
			if maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) > 0.045: changed += 1
	return changed
