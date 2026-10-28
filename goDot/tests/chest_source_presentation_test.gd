extends SceneTree

const PROPS = preload("res://scripts/presentation/room_props.gd")
const EFFECTS = preload("res://scripts/presentation/environment_effects.gd")
const PRESENTER = preload("res://scripts/presentation/chest_source_presentation.gd")
const QUALITIES := ["Normal", "Unusual", "Luxury", "Curse"]

class TestWorld extends Node3D:
	var low_effects := false
	var paused := false
	var _background := false
	var hud: Node
	var player: Node3D
	var environment_root: Node3D
	var interactions := DungeonWorldInteractions.new()

var failures: Array[String] = []
var checks := 0
var captures: Array[Dictionary] = []
var source: Dictionary

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr(message)

func _run() -> void:
	source = JSON.parse_string(FileAccess.get_file_as_string(PRESENTER.CATALOG_PATH))
	check(source.apk_sha256 == "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505", "Models retain the selected APK identity")
	check(source.models.Curse_Final.path == source.models.Curse.path, "Final curse uses the native rendering alias")
	for size in [Vector2i(1600, 900), Vector2i(844, 390)]:
		await _verify_size(size, OS.get_cmdline_user_args().has("--capture"))
	var result := {"checks": checks, "failures": failures, "passed": failures.is_empty(), "captures": captures}
	var file := FileAccess.open("res://reports/chest-source-presentation-20261028.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t") + "\n")
	file.close()
	print("CHEST_SOURCE_PRESENTATION ", JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)

func _verify_size(size: Vector2i, capture: bool) -> void:
	var timeline := {"size": [size.x, size.y], "timing": "Script and CPUParticles3D advance together once per rendered engine frame; particles are paused while screenshots are read back. Simulated seconds use the engine frame delta, not wall time.", "engine_arguments": OS.get_cmdline_args(), "stages": {}}
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var background := ColorRect.new()
	background.color = Color("192128")
	background.size = size
	viewport.add_child(background)
	var views: Array[Dictionary] = []
	for index in QUALITIES.size():
		var frame := SubViewportContainer.new()
		var cell_size := Vector2i(size.x / 2, size.y / 2)
		frame.position = Vector2((index % 2) * cell_size.x, (index / 2) * cell_size.y)
		frame.size = cell_size
		viewport.add_child(frame)
		var scene_view := SubViewport.new()
		scene_view.size = cell_size
		scene_view.own_world_3d = true
		scene_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		frame.add_child(scene_view)
		var entry := _build_world(scene_view, QUALITIES[index])
		views.append(entry)
		var label := Label.new()
		label.text = QUALITIES[index]
		label.position = frame.position + Vector2(14, 10)
		label.add_theme_font_size_override("font_size", 20 if size.x > 1000 else 14)
		viewport.add_child(label)
		check(entry.prop.source_quality == QUALITIES[index], QUALITIES[index] + " selects its source model")
		check(entry.prop.source_model.find_children("*", "MeshInstance3D", true, false).size() == 2, QUALITIES[index] + " has the source base and lid")
		check(entry.prop.source_lid is MeshInstance3D and entry.prop.source_lid.mesh is ArrayMesh, QUALITIES[index] + " uses recovered lid geometry")
		check(entry.old_mesh.layers == 0, QUALITIES[index] + " replaces preexisting scene quality art")
		check(is_equal_approx(entry.prop.item.chest_disappear_seconds, 1.0), QUALITIES[index] + " binds native disposal time")
		var material: ShaderMaterial = entry.prop.source_materials[0]
		check(is_equal_approx(float(material.get_shader_parameter("rim_amount")), float(source.models[QUALITIES[index]].materials[0].floats._RimAmount)), QUALITIES[index] + " preserves source rim amount")
		check(material.get_shader_parameter("base_texture") is Texture2D, QUALITIES[index] + " binds the packaged color texture")
	if capture:
		timeline.stages["closed"] = await _advance_rendered_frames(views, 0.65)
	else:
		for tick in 60: _tick(views, 1.0 / 60.0)
	for view in views:
		var ambient: Array = view.effects.bindings.filter(func(binding): return PROPS.CHEST_EFFECTS.values().has(binding.address))
		check(ambient.size() == 1 and ambient[0].active, view.prop.source_quality + " has exactly one source ambient instance")
	if capture:
		_freeze_particles(views)
		var closed := await _capture(viewport, size, "closed")
		for view in views: view.prop.effect_anchor.hide()
		var surface_on := await _capture(viewport, size, "surface-shine-on")
		for view in views:
			for material: ShaderMaterial in view.prop.source_materials:
				material.set_shader_parameter("rim_amount", 0.0)
				material.set_shader_parameter("emissive_color", Color(0, 0, 0, 0))
		var surface_off := await _capture(viewport, size, "surface-shine-off")
		var differences := _pixel_differences(surface_on, surface_off)
		for index in QUALITIES.size():
			check(int(differences[index]) > 40, "%s %s source surface shine changes rendered pixels" % [size, QUALITIES[index]])
		for view in views:
			var source_material: Dictionary = source.models[view.prop.source_quality].materials[0]
			for material: ShaderMaterial in view.prop.source_materials:
				material.set_shader_parameter("rim_amount", float(source_material.floats._RimAmount))
				var value: Dictionary = source_material.colors._Emissive
				material.set_shader_parameter("emissive_color", Color(value.r, value.g, value.b, value.a))
			view.prop.source_model.hide()
		var empty := await _capture(viewport, size, "empty-reference", false)
		var model_pixels := _pixel_differences(surface_on, empty)
		for index in QUALITIES.size(): check(int(model_pixels[index]) > 100, "%s %s model renders nonblank" % [size, QUALITIES[index]])
		for view in views:
			view.prop.source_model.show()
			view.prop.effect_anchor.show()
		var ambient_pixels := _pixel_differences(closed, surface_on)
		for index in QUALITIES.size(): check(int(ambient_pixels[index]) > 40, "%s %s ambient gloss renders" % [size, QUALITIES[index]])
		timeline["surface_shine_pixels"] = differences
		timeline["model_pixels"] = model_pixels
		timeline["ambient_pixels"] = ambient_pixels
	for view in views:
		check(bool(view.world.interactions.interact("chest").get("success", false)), view.prop.source_quality + " opens through interaction")
	var opening_elapsed := 0.0
	var sequence: Dictionary = {}
	if capture and size.x == 844 and OS.get_cmdline_user_args().has("--capture-sequence"):
		sequence = {"viewport": viewport, "frame": 0, "elapsed": 0.0, "frames": []}
		check(DirAccess.make_dir_recursive_absolute("res://reports/chest-opening-fixed-frames") == OK, "Opening sequence directory exists")
		_tick(views, 0.0)
		_freeze_particles(views)
		await _capture(viewport, size, "sequence-initial", false)
		_save_sequence_frame(sequence)
	if capture:
		for stage in [[0.1, "opening-010"], [0.3, "opening-030"], [0.75, "opening-075"]]:
			var timing := await _advance_rendered_frames(views, maxf(0.0, float(stage[0]) - opening_elapsed), sequence)
			opening_elapsed += float(timing.simulated_seconds)
			timing["opening_elapsed_seconds"] = opening_elapsed
			timing["requested_opening_seconds"] = float(stage[0])
			timing["particles"] = _opening_particles(views)
			timeline.stages[str(stage[1])] = timing
			_freeze_particles(views)
			await _capture(viewport, size, str(stage[1]))
		for view in views:
			if view.prop.source_quality == "Curse": continue
			var rings: Array = timeline.stages["opening-075"].particles[view.prop.source_quality].emitters.filter(func(emitter): return emitter.layer == "24050601_treasureboxopen_ring")
			check(rings.size() == 1 and rings[0].finished, "%s %s half-second ring has actually finished by the 0.75-second render" % [size, view.prop.source_quality])
	else:
		for tick in 45: _tick(views, 1.0 / 60.0)
		opening_elapsed = 0.75
	for view in views:
		var phase := clampf(opening_elapsed, 0.0, 1.0)
		var expected_angle := 45.0 * (3.0 * phase * phase - 2.0 * phase * phase * phase)
		var angle := deg_to_rad(expected_angle)
		var expected := Basis(Vector3(0, sin(angle), cos(angle)), Vector3(0, cos(angle), -sin(angle)), Vector3(-1, 0, 0))
		check(view.prop.source_lid.basis.is_equal_approx(expected), view.prop.source_quality + " follows the source Euler curve at the measured opening time")
		check(view.prop.source_lid.position.is_equal_approx(view.lid_rest_position), view.prop.source_quality + " keeps its source hinge position")
		check(view.prop.source_lid.global_basis.z.normalized().is_equal_approx(view.lid_rest_hinge_axis), view.prop.source_quality + " opens around the fixed rear hinge without sideways roll")
		check(view.prop.item.visual.visible, view.prop.source_quality + " remains visible while opening")
		check(not view.prop.effect_anchor.visible, view.prop.source_quality + " disables ambient at animation start")
		check(view.effects.bindings.any(func(binding): return binding.transient and str(binding.address).contains("treasurebox")), view.prop.source_quality + " emits source opening burst")
	if capture:
		var timing := await _advance_rendered_frames(views, maxf(0.0, 1.05 - opening_elapsed), sequence)
		timing["opening_elapsed_seconds"] = opening_elapsed + float(timing.simulated_seconds)
		timing["requested_opening_seconds"] = 1.05
		timing["particles"] = _opening_particles(views)
		timeline.stages["opened-105"] = timing
	else:
		for tick in 18: _tick(views, 1.0 / 60.0)
	for view in views:
		check(not view.prop.item.visual.visible and is_zero_approx(view.prop.item.chest_open_remaining), view.prop.source_quality + " disappears at native disposal threshold")
		check(not view.prop.has("fade_materials"), view.prop.source_quality + " never synthesizes an alpha fade")
	if capture:
		_freeze_particles(views)
		await _capture(viewport, size, "opened-105")
		if not sequence.is_empty():
			await _advance_rendered_frames(views, maxf(0.0, 1.1 - float(sequence.elapsed)), sequence)
			timeline["sequence"] = {"directory": "res://reports/chest-opening-fixed-frames", "frames": sequence.frames}
		captures.append(timeline)
	viewport.queue_free()
	await process_frame

func _build_world(viewport: SubViewport, quality: String) -> Dictionary:
	var world := TestWorld.new()
	viewport.add_child(world)
	world.environment_root = Node3D.new()
	world.add_child(world.environment_root)
	world.player = Node3D.new()
	world.add_child(world.player)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("29333b")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.75, 0.79, 0.82)
	environment.environment.ambient_light_energy = 0.7
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -30, 0)
	light.light_energy = 0.65
	world.add_child(light)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12, 12)
	floor_mesh.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("465159")
	floor_material.roughness = 1.0
	floor_mesh.material_override = floor_material
	floor_mesh.position.y = -0.01
	world.add_child(floor_mesh)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.6
	camera.position = Vector3(2.7, 2.9, 5.8)
	camera.look_at(Vector3(0, 0.65, 0))
	camera.current = true
	var chest := Node3D.new()
	chest.name = "Chest"
	world.environment_root.add_child(chest)
	var old := MeshInstance3D.new()
	old.mesh = BoxMesh.new()
	chest.add_child(old)
	world.interactions.setup(world.environment_root, [{"SceneName": "SourcePresentation", "SourceGameObjectId": "chest", "Type": "EEUT_AbilityItemTreasureBox", "DataJson": JSON.stringify({"TreasureId": 1, "TreasureType": quality}), "exported_node_name": "Chest"}])
	var props := PROPS.new()
	world.environment_root.add_child(props)
	props.configure(world)
	props.set_process(false)
	var effects := EFFECTS.new()
	effects.name = "EnvironmentEffects"
	world.environment_root.add_child(effects)
	effects.configure(world)
	effects.set_process(false)
	props._process(0.0)
	var prop: Dictionary = props.props[0]
	return {"world": world, "props": props, "effects": effects, "prop": prop, "old_mesh": old, "lid_rest_position": prop.source_lid.position, "lid_rest_hinge_axis": prop.source_lid.global_basis.z.normalized()}

func _tick(views: Array[Dictionary], delta: float) -> void:
	for view in views:
		view.props._process(delta)
		view.effects._process(delta)

func _advance_rendered_frames(views: Array[Dictionary], seconds: float, sequence: Dictionary = {}) -> Dictionary:
	var elapsed := 0.0
	var frames := 0
	var minimum_delta := INF
	var maximum_delta := 0.0
	var start := Time.get_ticks_usec()
	while elapsed + 0.000001 < seconds:
		await process_frame
		var delta := root.get_process_delta_time()
		minimum_delta = minf(minimum_delta, delta)
		maximum_delta = maxf(maximum_delta, delta)
		_tick(views, delta)
		for view in views:
			for binding: Dictionary in view.effects.bindings:
				if not is_instance_valid(binding.effect): continue
				for emitter: Dictionary in binding.effect.emitters:
					var particle: CPUParticles3D = emitter.node
					if particle.has_meta("capture_observed"): continue
					particle.set_meta("capture_observed", true)
					particle.finished.connect(_particle_finished.bind(particle))
		elapsed += delta
		frames += 1
		# The particle servers consume the same frame delta after process_frame.
		await RenderingServer.frame_post_draw
		if not sequence.is_empty():
			sequence.frame += 1
			sequence.elapsed += delta
			if int(sequence.frame) % 2 == 0: _save_sequence_frame(sequence)
	return {"simulated_seconds": elapsed, "rendered_frames": frames, "frame_delta_min": minimum_delta if frames > 0 else 0.0, "frame_delta_max": maximum_delta, "wall_seconds": (Time.get_ticks_usec() - start) / 1000000.0}

func _save_sequence_frame(sequence: Dictionary) -> void:
	var image: Image = sequence.viewport.get_texture().get_image()
	var path := "res://reports/chest-opening-fixed-frames/frame-%03d.png" % int(sequence.frame)
	check(image != null and image.save_png(path) == OK, "Saved " + path)
	sequence.frames.append({"frame": sequence.frame, "opening_elapsed_seconds": sequence.elapsed, "path": path})

func _particle_finished(particle: CPUParticles3D) -> void:
	particle.set_meta("capture_finished", true)

func _freeze_particles(views: Array[Dictionary]) -> void:
	for view in views:
		for binding: Dictionary in view.effects.bindings:
			if is_instance_valid(binding.effect): binding.effect.advance(0.0, true)

func _opening_particles(views: Array[Dictionary]) -> Dictionary:
	var result: Dictionary = {}
	for view in views:
		var state := {"effect_age": 0.0, "emitters": []}
		for binding: Dictionary in view.effects.bindings:
			if not binding.transient or not is_instance_valid(binding.effect): continue
			state.effect_age = binding.effect.age
			for emitter: Dictionary in binding.effect.emitters:
				var particle: CPUParticles3D = emitter.node
				state.emitters.append({"layer": str(particle.get_parent().get_meta("source_layer", "")), "lifetime": particle.lifetime, "emitting": particle.emitting, "finished": bool(particle.get_meta("capture_finished", false))})
		result[view.prop.source_quality] = state
	return result

func _capture(viewport: SubViewport, size: Vector2i, stage: String, save := true) -> Image:
	for frame in 3: await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	check(image != null and image.get_size() == size, "%s %s renders at requested resolution" % [size, stage])
	if save and image != null:
		var path := "res://reports/chest-source-%s-%dx%d.png" % [stage, size.x, size.y]
		check(image.save_png(path) == OK, "Saved " + path)
	return image

func _pixel_differences(first: Image, second: Image) -> Array[int]:
	var counts: Array[int] = [0, 0, 0, 0]
	if first == null or second == null: return counts
	var size := first.get_size()
	for y in range(30, size.y, 2):
		for x in range(0, size.x, 2):
			var a := first.get_pixel(x, y)
			var b := second.get_pixel(x, y)
			if maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) < 0.025: continue
			var index := (0 if x < size.x / 2 else 1) + (0 if y < size.y / 2 else 2)
			counts[index] += 1
	return counts
