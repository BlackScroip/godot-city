extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("MultiMesh comparison requires rendering")
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(0, 0, 20)
	camera.current = true
	var mesh := SphereMesh.new()
	mesh.radius = 0.13
	mesh.height = 0.26
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("82e0cb")
	mesh.material = material
	var rows: Array = []
	for batched in [false, true]:
		var host := Node3D.new()
		root.add_child(host)
		var nodes: Array[MeshInstance3D] = []
		var multimesh := MultiMesh.new()
		if batched:
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			multimesh.mesh = mesh
			multimesh.instance_count = 512
			var instance := MultiMeshInstance3D.new()
			instance.multimesh = multimesh
			host.add_child(instance)
		else:
			for index in 512:
				var instance := MeshInstance3D.new()
				instance.mesh = mesh
				host.add_child(instance)
				nodes.append(instance)
		var samples: Array[float] = []
		var updates: Array[float] = []
		for frame in 240:
			var before := Time.get_ticks_usec()
			for index in 512:
				var point := Vector3((index % 32 - 16) * 0.4, (index / 32 - 8) * 0.4, sin(frame * 0.04 + index))
				if batched: multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, point))
				else: nodes[index].position = point
			var update_ms := (Time.get_ticks_usec() - before) / 1000.0
			await process_frame
			if frame >= 60:
				updates.append(update_ms)
				samples.append((Time.get_ticks_usec() - before) / 1000.0)
		samples.sort()
		updates.sort()
		rows.append({"multimesh": batched, "instances": 512, "frame_p95_ms": samples[ceili(samples.size() * 0.95) - 1], "update_p95_ms": updates[ceili(updates.size() * 0.95) - 1], "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)})
		host.queue_free()
		await process_frame
	var report = {"platform": OS.get_name(), "renderer": RenderingServer.get_video_adapter_name(), "rows": rows, "production_enabled": false, "scope": "Opaque shared mesh prototype only; transparent effects, per-instance culling and Android acceptance remain separate."}
	FileAccess.open("res://reports/multimesh-probe.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("MULTIMESH_PROBE ", JSON.stringify(report))
	quit()
