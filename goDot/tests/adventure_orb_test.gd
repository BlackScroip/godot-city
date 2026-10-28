extends "res://tests/adventure_complete_flow_test.gd"

const AUTHORED = preload("res://scripts/presentation/authored_effect.gd")
const RETAINED = preload("res://scripts/presentation/retained_particle.gd")
const ADDRESS := "24071901_fx_env_void"
const RETAINED_NAMES := ["sphere", "line", "energy", "glow", "floorglow", "wave"]
const CONSUMED_NAMES := ["line", "outsidestarchain", "energy", "glow"]
var render_metrics: Array = []

func _run() -> void:
	create_timer(240).timeout.connect(func(): quit(2))
	canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	await _test_retained_particle()
	await _test_map("normal", "Battle", "LevelMap_1010101", DungeonWorldInteractions.ADVENTURE_EVENT)
	await _test_map("special", "Event", "LevelMap_1010801", DungeonWorldInteractions.SPECIAL_EVENT)
	var report := {"checks": checks, "failures": failures, "passed": failures.is_empty(), "captures": captures, "render_metrics": render_metrics, "scope": "Godot source-map lifecycle and GPU pixels; original Android runtime and Unity shader pixel equivalence are not observed."}
	FileAccess.open("res://reports/adventure-orb-20261028-%s.json" % ("headless" if DisplayServer.get_name() == "headless" else "gpu"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t") + "\n")
	print("ADVENTURE_ORB ", JSON.stringify(report))
	canvas.free()
	quit(0 if failures.is_empty() else 1)

func _test_retained_particle() -> void:
	var definition: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/environment_effects/catalog.json")).effects[ADDRESS]
	var source_layers: Array = definition.layers.filter(func(layer): return int(layer.get("ring_buffer_mode", 0)) == 1)
	check(source_layers.size() == 6, "APK retains exactly six single-burst orb layers")
	var looping_layer: Dictionary = source_layers[0].duplicate(true)
	looping_layer.looping = true
	check(not RETAINED.handles(looping_layer), "Looping particle systems never use the stationary single-burst path")
	for low_quality in [false, true]:
		var effect = AUTHORED.new()
		canvas.add_child(effect)
		effect.configure(definition, low_quality, {})
		effect.restart()
		check(effect.retained_particles.size() == 6, "Both quality modes retain all six source orb layers")
		for layer in source_layers:
			check(RETAINED.handles(layer), "Source layer uses the supported stationary single-particle lifetime: " + str(layer.name))
			var particle := _retained(effect, str(layer.name).trim_prefix("24071901_void_"))
			check(not particle.is_empty(), "Source layer exists: " + str(layer.name))
			if particle.is_empty(): continue
			var instance: MultiMeshInstance3D = particle.node
			check(instance.multimesh.instance_count == 1, "Retained layer has exactly one source particle")
			# The headless dummy renderer does not retain MultiMesh instance buffers.
			if DisplayServer.get_name() != "headless":
				check(is_equal_approx(instance.multimesh.get_instance_transform(0).basis.x.length(), float(layer.initial.startSize.scalar)), "Retained layer preserves source size")
				var color := instance.multimesh.get_instance_color(0)
				var expected: Color = AUTHORED.rgba(layer.initial.startColor.maxColor)
				check(absf(color.r - expected.r) + absf(color.g - expected.g) + absf(color.b - expected.b) + absf(color.a - expected.a) < 0.016, "Retained layer preserves source color within GPU buffer precision")
			if not str(layer.mesh).is_empty(): check(instance.multimesh.mesh.resource_path == str(layer.mesh), "Retained layer uses the exported APK mesh")
		effect.advance(0.1, false)
		var sphere := _retained(effect, "sphere")
		check(sphere.node.is_visible_in_tree(), "Sphere is visible immediately after spawn")
		check(is_equal_approx(sphere.node.global_position.y, 1.11), "Sphere retains its authored height above the carpet")
		check(sphere.node.material_override.get_shader_parameter("source_rim") == true, "Sphere restores the exact APK RIM_ON material variant")
		check(sphere.node.material_override.get_shader_parameter("source_cull") == 2, "Sphere retains source backface culling")
		check(sphere.node.material_override.get_shader_parameter("source_rim_shape").is_equal_approx(Vector3(0.01, 1.0, 3.0)), "Sphere uses the APK Fresnel bias, scale and power")
		effect.advance(2.0, false)
		if DisplayServer.get_name() != "headless":
			await process_frame
			await RenderingServer.frame_post_draw
		check(effect.retained_particles.all(func(entry): return entry.node.is_visible_in_tree()), "All retained layers survive their original one-second particle lifetime")
		if DisplayServer.get_name() != "headless": check(is_equal_approx(sphere.node.multimesh.get_instance_custom_data(0).g, 1.0), "Paused particle lifetime stays at its terminal phase: " + str(sphere.node.multimesh.get_instance_custom_data(0)))
		var before: float = sphere.node.material_override.get_shader_parameter("clock")
		effect.advance(2.0, true)
		check(is_equal_approx(sphere.node.material_override.get_shader_parameter("clock"), before), "Modal pause freezes retained texture time")
		effect.advance(120.0, false)
		check(sphere.node.is_visible_in_tree() and sphere.node.material_override.get_shader_parameter("clock") > before, "Sphere survives long idle time while its source texture keeps animating")
		var duplicate: Node3D = effect.instantiate_effect()
		canvas.add_child(duplicate)
		duplicate.restart()
		duplicate.advance(0.25, false)
		var cloned := _retained(duplicate, "sphere")
		check(cloned.node.multimesh != sphere.node.multimesh and cloned.node.material_override != sphere.node.material_override, "Independent encounters never share mutable retained particle state")
		check(is_equal_approx(cloned.node.material_override.get_shader_parameter("clock"), 0.25), "Cloned effect owns its own animation clock")
		effect.stop()
		check(not sphere.node.is_visible_in_tree() and cloned.node.is_visible_in_tree(), "Stopping one encounter leaves its clone visible")
		effect.restart()
		effect.advance(0.05, false)
		check(sphere.node.is_visible_in_tree() and is_equal_approx(effect.age, 0.05), "Reactivation restores the sphere and resets its particle lifetime")
		duplicate.free()
		effect.free()

func _retained(effect: Node3D, suffix: String) -> Dictionary:
	for entry in effect.retained_particles:
		if entry.node.get_meta("source_layer", "") == "24071901_void_" + suffix: return entry
	return {}

func _binding(marker: Dictionary) -> Dictionary:
	var effects: Node3D = game.world.environment_root.get_node("EnvironmentEffects")
	effects.set_process(false)
	game.world._background = false
	_stand_at(marker)
	var matching: Array = effects.bindings.filter(func(entry): return str(entry.address) == ADDRESS and marker.visual.is_ancestor_of(entry.anchor))
	check(matching.size() == 1, "Actual source map registers exactly one orb for this event")
	if matching.is_empty(): return {}
	effects._process(0.05)
	check(is_instance_valid(matching[0].effect), "Source event anchor creates a live particle presentation")
	return matching[0]

func _check_state(marker: Dictionary, entry: Dictionary, consumed: bool, label: String) -> void:
	check(entry.loop and entry.active and not entry.finished, label + ": permanent source orb stays active")
	check(marker.visual.is_visible_in_tree(), label + ": source carpet remains visible")
	check(entry.effect.retained_particles.size() == 6, label + ": all six source retained particles exist")
	check(_retained(entry.effect, "sphere").node.is_visible_in_tree(), label + ": central sphere remains visible")
	check(entry.source_layers.size() == entry.effect.get_child_count(), label + ": every displayed layer tracks its original source node")
	for layer in entry.source_layers:
		var suffix: String = str(layer.visual.get_meta("source_layer", "")).trim_prefix("24071901_void_")
		check(layer.visual.is_visible_in_tree() == (not consumed or suffix not in CONSUMED_NAMES), label + ": source activation for " + suffix)

func _test_map(label: String, flow: String, scene: String, button: String) -> void:
	await _fixture(flow, scene)
	var marker := _item(button)
	check(not marker.is_empty(), label + ": source event marker exists")
	if marker.is_empty(): return
	var entry := _binding(marker)
	if entry.is_empty() or not is_instance_valid(entry.effect): return
	var effects: Node3D = game.world.environment_root.get_node("EnvironmentEffects")
	for frame in 180: effects._process(1.0 / 60.0)
	_check_state(marker, entry, false, label + " initial")
	if label == "special": await _capture_gameplay(marker, entry)
	await _capture_orb(label + "-initial", entry, false)
	check(game.world.interactions.interact(str(marker.id)).success and game.hud.modal_open, label + ": source interaction opens the event")
	var paused_age: float = entry.effect.age
	effects._process(3.0)
	check(is_equal_approx(entry.effect.age, paused_age), label + ": event modal freezes orb motion")
	_check_state(marker, entry, false, label + " interaction")
	var encounter: Dictionary = game.profile.data.run.events[0]
	var encounter_key := str(encounter.key)
	var random_step: int = game.profile.data.run.random_step
	game.hud.close_page()
	effects._process(0.2)
	_check_state(marker, entry, false, label + " returned from interaction")
	check(game.world.interactions.interact(str(marker.id)).success and game.profile.data.run.events.size() == 1 and str(game.profile.data.run.events[0].key) == encounter_key and game.profile.data.run.random_step == random_step, label + ": returning and reopening preserves the same encounter")
	encounter.event_id = 4
	game._show_adventure_event({"marker_id": str(marker.id)}, str(encounter.key))
	var before: int = game.systems.material(102)
	game._action("event_choice", 42, {"key": encounter.key, "marker_id": str(marker.id)})
	check(game.systems.material(102) == before + 100 and not marker.state.used, label + ": source reward waits for acknowledgement")
	game._save(true)
	game._load_room(true)
	await _wait()
	marker = _item(button)
	entry = _binding(marker)
	effects = game.world.environment_root.get_node("EnvironmentEffects")
	_check_state(marker, entry, false, label + " pending reload")
	game._interact()
	check(game.hud.modal_open and game.hud.page.adventure_event_view._context.finished, label + ": saved result reopens without rerolling")
	game._action("event_continue", 0, {"key": encounter.key, "marker_id": str(marker.id)})
	game.hud.close_page()
	effects._process(0.05)
	_check_state(marker, entry, true, label + " consumed")
	check(marker.state.used and not game.world.interactions.interact(str(marker.id)).success, label + ": completed event cannot be activated twice")
	await _capture_orb(label + "-completed", entry, true)
	game._save(true)
	game._load_room(true)
	await _wait()
	marker = _item(button)
	entry = _binding(marker)
	_check_state(marker, entry, true, label + " consumed reload")
	check(game.systems.material(102) == before + 100, label + ": consumed reload never duplicates the reward")
	effects = game.world.environment_root.get_node("EnvironmentEffects")
	game.world.low_effects = true
	effects.set_low_quality(true)
	effects._process(0.05)
	_check_state(marker, entry, true, label + " low quality")
	await _capture_orb(label + "-low", entry, true)

func _capture_gameplay(marker: Dictionary, entry: Dictionary) -> void:
	if DisplayServer.get_name() == "headless" or "--capture" not in OS.get_cmdline_user_args(): return
	_stand_at(marker)
	var center: Vector3 = game.world.player.position
	for offset in [Vector3(-1.5, 0.0, 0.0), Vector3(-1.0, 0.0, 0.0), Vector3(-0.5, 0.0, 0.0)]:
		if game.world.interactions.can_interact_at(str(marker.id), center + offset):
			game.world.player.position = center + offset
			break
	game.world.player.set_physics_process(false)
	game.world.snap_camera()
	game._process(0.0)
	check(game.world.interactions.can_interact_at(str(marker.id), game.world.player.position) and game.hud.primary.visible, "Default gameplay camera exposes the nearby event interaction")
	var camera: Camera3D = game.world.camera
	var camera_size := camera.size
	var camera_offset: Vector3 = game.world._camera_offset
	var sphere: MultiMeshInstance3D = _retained(entry.effect, "sphere").node
	entry.effect.advance(0.0, true)
	for size in [Vector2i(1600, 900), Vector2i(844, 390)]:
		canvas.size = size
		game.hud._layout()
		for frame in 6: await process_frame
		await RenderingServer.frame_post_draw
		var shown := canvas.get_texture().get_image()
		check(_has_visual_content(shown) and is_equal_approx(camera.size, camera_size) and game.world._camera_offset == camera_offset, "Normal gameplay framing is preserved at " + str(size))
		var point := camera.unproject_position(sphere.global_position)
		var radius := absf(camera.unproject_position(sphere.global_position + camera.global_basis.x * 0.65).x - point.x)
		var region := Rect2i(Vector2i(point - Vector2.ONE * radius), Vector2i(Vector2.ONE * radius * 2.0)).intersection(Rect2i(Vector2i.ZERO, shown.get_size()))
		var path := "res://reports/adventure-orb-special-gameplay-%dx%d.png" % [size.x, size.y]
		shown.save_png(path)
		captures.append(path)
		sphere.hide()
		await process_frame
		await RenderingServer.frame_post_draw
		var hidden := canvas.get_texture().get_image()
		sphere.show()
		var pixels := _changed_pixels(shown, hidden, region)
		check(pixels > 20, "Source sphere is visible from the default gameplay camera at " + str(size))
		render_metrics.append({"label": "special-gameplay", "size": str(size), "sphere_pixels": pixels, "camera_size": camera_size, "camera_offset": str(camera_offset), "region": str(region)})
	canvas.size = Vector2i(1600, 900)

func _capture_orb(label: String, entry: Dictionary, consumed: bool) -> void:
	if DisplayServer.get_name() == "headless" or "--capture" not in OS.get_cmdline_user_args(): return
	var camera: Camera3D = game.world.camera
	var sphere: MultiMeshInstance3D = _retained(entry.effect, "sphere").node
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8.5
	camera.global_position = entry.anchor.global_position + Vector3(4.0, 5.5, -6.5)
	camera.look_at(entry.anchor.global_position + Vector3.UP * 0.7, Vector3.UP)
	game.world.player.set_physics_process(false)
	game.world.player.position = entry.anchor.global_position + Vector3(-2.0, 0.0, -1.5)
	entry.effect.advance(0.0, true)
	for size in [Vector2i(1600, 900), Vector2i(844, 390)]:
		canvas.size = size
		game.hud._layout()
		for frame in 5: await process_frame
		await RenderingServer.frame_post_draw
		var shown := canvas.get_texture().get_image()
		check(_has_visual_content(shown), label + ": rendered map is nonblank")
		var center := camera.unproject_position(sphere.global_position)
		var radius := absf(camera.unproject_position(sphere.global_position + camera.global_basis.x * 0.6).x - center.x)
		var region := Rect2i(Vector2i(center - Vector2.ONE * radius), Vector2i(Vector2.ONE * radius * 2.0)).intersection(Rect2i(Vector2i.ZERO, shown.get_size()))
		var path := "res://reports/adventure-orb-%s-%dx%d.png" % [label, size.x, size.y]
		shown.save_png(path)
		captures.append(path)
		sphere.hide()
		await process_frame
		await RenderingServer.frame_post_draw
		var hidden := canvas.get_texture().get_image()
		sphere.show()
		var changed := _changed_pixels(shown, hidden, region)
		var purple := 0
		for y in range(region.position.y, region.end.y):
			for x in range(region.position.x, region.end.x):
				var color := shown.get_pixel(x, y)
				if color.b > color.g * 1.18 and color.r > color.g * 1.1 and color.b > 0.25: purple += 1
		check(changed > 30, label + ": central source sphere contributes visible GPU pixels at " + str(size))
		check(purple > 20, label + ": central sphere is visibly purple at " + str(size))
		var old_clock: float = sphere.material_override.get_shader_parameter("clock")
		sphere.material_override.set_shader_parameter("clock", old_clock + 0.6)
		await process_frame
		await RenderingServer.frame_post_draw
		var moved := canvas.get_texture().get_image()
		var animated := _changed_pixels(shown, moved, region)
		check(animated > 20, label + ": source texture visibly animates at " + str(size))
		sphere.material_override.set_shader_parameter("clock", old_clock)
		render_metrics.append({"label": label, "size": str(size), "sphere_pixels": changed, "purple_pixels": purple, "animated_pixels": animated, "consumed": consumed, "region": str(region)})
	canvas.size = Vector2i(1600, 900)

func _changed_pixels(a: Image, b: Image, region: Rect2i) -> int:
	var count := 0
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var first := a.get_pixel(x, y)
			var second := b.get_pixel(x, y)
			if absf(first.r - second.r) + absf(first.g - second.g) + absf(first.b - second.b) > 0.06: count += 1
	return count
