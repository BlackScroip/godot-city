extends "res://tests/impact_visual_test.gd"

func _run() -> void:
	root.size = Vector2i(960, 540)
	Engine.physics_ticks_per_second = HZ
	seed(SEED)
	world = DungeonWorld.new()
	root.add_child(world)
	world.set_physics_process(false)
	world._camera_offset = Vector3(0, 10, -9)
	world.camera.size = 12
	world.paused = false
	world._background = false
	world.fighting = true
	world.low_effects = _arg("quality", "full") == "low"
	_ground()
	var canvas := CanvasLayer.new()
	root.add_child(canvas)
	label = Label.new()
	label.position = Vector2(24, 18)
	label.add_theme_font_size_override("font_size", 21)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	canvas.add_child(label)
	var shots: Array[Dictionary] = [
		{"name": "heavy-sword", "title": "KAI / DRAW + EMPOWERED STRIKE", "character": 1, "resource": 5, "release": 0.1},
		{"name": "heavy-sickle", "title": "NILO / HEAVY + TRANSFORMATION", "character": 2, "resource": 20, "release": 1.6},
		{"name": "heavy-axe", "title": "AX / WINDUP + FIVE SPINS + FINISH", "character": 3, "resource": 5, "release": 4.0},
		{"name": "heavy-wand", "title": "NEZMI / ALTERNATING WATER BLADES", "character": 4, "resource": 75, "release": 0.1},
		{"name": "heavy-bow", "title": "UMA / EMPOWERED VOLLEY", "character": 5, "resource": 10, "release": 0.1},
		{"name": "heavy-orb", "title": "ORBA / WINDUP + FAITH STRIKE", "character": 6, "resource": 20, "release": 0.1},
		{"name": "heavy-lance", "title": "FIONA / DRAGON CHARGE + RELEASE", "character": 7, "resource": 300, "release": 2.8}
	]
	for shot in shots:
		if not _arg("shot", "").is_empty() and str(shot.name) != _arg("shot", ""): continue
		shot.merge({"slot": 4, "enemy": 11001, "points": [Vector3(-0.9, 0, 2.2), Vector3(0, 0, 2.2), Vector3(0.9, 0, 2.2)], "frames": 300, "ultimate_energy": 0})
		await _shot(shot)
	cpu_ms.sort()
	var report = {"schema": 1, "seed": SEED, "hz": HZ, "quality": _arg("quality", "full"), "shots": rows, "failures": failures, "missing_effects": world.presentation.missing.keys(), "simulation_cpu_ms_p95": cpu_ms[int(cpu_ms.size() * 0.95)], "scope": "Seven characters, original heavy action assemblies against stationary high-HP targets. MovieWriter recording is visual verification, not device frame-rate measurement."}
	FileAccess.open("res://reports/heavy-visual-%s.json" % _arg("label", "current"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("HEAVY_VISUAL ", JSON.stringify(report))
	world.queue_free()
	canvas.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
