extends SceneTree

var failures: Array[String] = []
var captures: Array = []
var canvas: SubViewport
var game: Node

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _run() -> void:
	canvas = SubViewport.new()
	canvas.size = Vector2i(2460, 1080)
	canvas.size_2d_override = Vector2i(2050, 900)
	canvas.size_2d_override_stretch = true
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var display = TextureRect.new()
	display.texture = canvas.get_texture()
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(display)
	game = load("res://scenes/main.tscn").instantiate()
	game.save_store = DungeonSaveStore.new("res://reports/camp-presentation-profile-%d.json" % Time.get_ticks_usec())
	canvas.add_child(game)
	await process_frame
	var fx = game.world.environment_root.get_node("CampEffects")
	check(fx.bindings.get("portal", 0) > 0, "Summoning platform has an active effect")
	check(fx.portal_surface_count == 5, "Only the five source portal mesh materials are restored")
	var source_materials: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/environment_effects/camp_portal_materials.json")).materials
	for material in fx.circles:
		var definition: Dictionary = source_materials[material.resource_name]
		var tint: Dictionary = definition.source_colors._Color
		check(material.get_shader_parameter("source_tint") == Color(tint.r, tint.g, tint.b, tint.a), "Portal material retains exact APK tint " + material.resource_name)
		check(material.get_shader_parameter("use_shape2") == ("SHAPE2_ON" in definition.keywords), "Portal material retains original second shape switch")
		var main_map: Dictionary = definition.textures.filter(func(slot): return slot.property == "_MainTex")[0]
		check(material.get_shader_parameter("shape1_st") == Vector4(main_map.scale.x, main_map.scale.y, main_map.offset.x, main_map.offset.y), "Portal material retains original UV scale and offset")
		check(material.get_shader_parameter("main_texture") != null, "Portal material resolves original raster texture")
	var environment_fx = game.world.environment_root.get_node("EnvironmentEffects")
	var portal_bindings: Array = environment_fx.bindings.filter(func(entry): return entry.address == "24102301_fx_env_maincityprotal")
	check(portal_bindings.size() == int(fx.bindings.get("portal", 0)), "Every camp portal uses exactly one APK particle binding")
	check(fx.find_children("RunicCircle", "MeshInstance3D", true, false).is_empty() and fx.find_children("SpiralFlow", "MeshInstance3D", true, false).is_empty(), "Portal adds no invented ring or cylinder geometry")
	_check_portal_material_scope()
	check(fx.bindings.get("campfire", 0) > 0, "Campfires have flame, ember and smoke emitters")
	check(fx.bindings.get("steam", 0) == 2, "Inactive scenery does not emit steam")
	print("CAMP EFFECT BINDINGS ", fx.bindings, " spawn=", game.world.player.position)
	game.world.player.position = Vector3(31, 0.2, 29.8)
	for i in 100: await process_frame
	var before: Image = await capture("wide")
	if before:
		fx.hide()
		for i in 3: await process_frame
		await RenderingServer.frame_post_draw
		var hidden = canvas.get_texture().get_image()
		var changed := 0
		for y in range(150, before.get_height() - 150, 3):
			for x in range(150, before.get_width() - 450, 3):
				var a = before.get_pixel(x, y)
				var b = hidden.get_pixel(x, y)
				if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.1: changed += 1
		check(changed > 100, "Camp effects visibly contribute to rendered pixels")
		print("CAMP EFFECT PIXELS ", changed)
		fx.show()
	for dimensions in [Vector2i(1600, 900), Vector2i(1200, 900), Vector2i(2050, 900)]:
		canvas.size = dimensions
		canvas.size_2d_override = dimensions
		for i in 8: await process_frame
		check(Rect2(Vector2.ZERO, game.hud.root.size).encloses(game.hud.navigation.get_rect()), "Top navigation stays inside " + str(dimensions))
		check(game.hud.navigation.get_child_count() == 5, "Reference navigation retains five commands")
		await capture("%dx%d" % [dimensions.x, dimensions.y])
	var commands: Array[String] = []
	game.hud.action.connect(func(kind, _id, _extra): commands.append(kind))
	game.hud.navigation.get_child(1).pressed.emit()
	check(commands.has("save"), "Cloud artwork button dispatches local save")
	check(game.hud.message_label.text == "进度已保存", "Save button completes existing offline save")
	game.menus.open("settings")
	for i in 3: await process_frame
	fx.set_process(false)
	var frozen: float = fx.clock
	fx._process(0.2)
	check(is_equal_approx(fx.clock, frozen), "Opening a menu freezes ambient animation")
	for particle in fx.emitters: check(particle.speed_scale == 0, "Paused menus freeze particle simulation")
	game.hud.close_page()
	for i in 3: await process_frame
	game.world._background = false
	fx._process(0.2)
	check(fx.clock > frozen, "Closing the menu resumes ambient animation")
	game.world._background = true
	frozen = fx.clock
	fx._process(0.2)
	check(is_equal_approx(fx.clock, frozen), "Backgrounding freezes ambient animation")
	game.world._background = false
	game.world.low_effects = true
	fx._update_visibility()
	for particle in fx.emitters:
		check(particle.amount < int(particle.get_meta("full_amount")), "Reduced effects lowers particle budgets")
	for light in fx.lights: check(not light.visible, "Reduced effects disables local lighting")
	game.world.low_effects = false
	fx.set_process(true)
	game._camp()
	for i in 3: await process_frame
	check(not is_instance_valid(fx), "Reloading camp releases old effects")
	check(game.world.environment_root.find_children("CampEffects", "Node3D", true, false).size() == 1, "Camp reload has one effects owner")
	var report = {"passed": failures.is_empty(), "failures": failures, "captures": captures, "bindings": game.world.environment_root.get_node("CampEffects").bindings}
	var output = FileAccess.open("res://reports/camp-presentation-tests.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t"))
	print("CAMP PRESENTATION ", JSON.stringify(report))
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func capture(label: String) -> Image:
	if DisplayServer.get_name() == "headless": return null
	await RenderingServer.frame_post_draw
	var image = canvas.get_texture().get_image()
	var path = "res://reports/camp-restored-" + label + ".png"
	image.save_png(path)
	captures.append(path)
	return image

func _check_portal_material_scope() -> void:
	var scope := Node3D.new()
	root.add_child(scope)
	var anchor := Node3D.new()
	scope.add_child(anchor)
	var neighbor := MeshInstance3D.new()
	neighbor.mesh = BoxMesh.new()
	var original := StandardMaterial3D.new()
	neighbor.mesh.surface_set_material(0, original)
	scope.add_child(neighbor)
	var probe = preload("res://scripts/presentation/camp_effects.gd").new()
	scope.add_child(probe)
	probe._portal(anchor)
	check(neighbor.get_active_material(0) == original and neighbor.get_surface_override_material(0) == null, "Portal configuration never changes neighboring scene materials")
	check(probe.emitters.is_empty() and probe.lights.is_empty(), "Portal configuration does not add invented particles or local lights")
	scope.queue_free()
