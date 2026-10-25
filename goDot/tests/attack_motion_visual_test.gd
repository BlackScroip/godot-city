extends "res://tests/impact_visual_test.gd"

func _run() -> void:
	root.size = Vector2i(960, 540)
	Engine.physics_ticks_per_second = HZ
	seed(SEED)
	world = DungeonWorld.new()
	root.add_child(world)
	world.set_physics_process(false)
	world._camera_offset = Vector3(0, 11, -10)
	world.camera.size = 15
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
	canvas.add_child(label)
	var names = ["", "KAI", "NILO", "AX", "NEZMI", "UMA", "ORBA", "FIONA"]
	for id in range(1, 8):
		for slot in [0, 4, 2, 3]:
			var shot: Dictionary = {"name": "motion-%d-%d" % [id, slot], "title": "%s / %s / MOVE + TURN + RELEASE" % [names[id], {0: "NORMAL", 4: "HEAVY", 2: "SKILL", 3: "ULTIMATE"}[slot]], "character": id, "slot": slot, "enemy": 11001, "points": [Vector3(-1, 0, 2.3), Vector3(0, 0, 2.3), Vector3(1, 0, 2.3)], "frames": 210, "resource": 300 if id == 7 else 75, "ultimate_energy": 100000, "release": 1.2, "require_contact": false, "moves": [{"start": 38, "end": 80, "direction": Vector3.RIGHT * 0.45}, {"start": 80, "end": 115, "direction": Vector3.LEFT * 0.45}]}
			if not _arg("shot", "").is_empty() and str(shot.name) != _arg("shot", ""): continue
			await _shot(shot)
			print("MOTION_VISUAL_SHOT ", shot.name)
	cpu_ms.sort()
	var report = {"schema": 1, "seed": SEED, "hz": HZ, "quality": _arg("quality", "full"), "shots": rows, "failures": failures, "missing_effects": world.presentation.missing.keys(), "simulation_cpu_ms_p95": cpu_ms[int(cpu_ms.size() * 0.95)], "scope": "Seven characters x four attack categories with held directional input, direction reversal and release. Whiffs and healing skills are allowed; contacts are reported. GPU recordings and PNGs verify current assembly, not original APK runtime fidelity or mobile device FPS."}
	FileAccess.open("res://reports/attack-motion-visual-%s.json" % _arg("label", "current"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("ATTACK_MOTION_VISUAL ", JSON.stringify(report))
	world.queue_free()
	canvas.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
