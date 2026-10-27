extends SceneTree

const FIXTURES := [
	["sprites", 1010104, "EnvUnit_MonoData_BtnDisplayName_SpritesAltar", "SpritesAltar", "25040703_fx_other_spritesaltar"],
	["curse", 1010001, "EnvUnit_MonoData_BtnDisplayName_CurseAltar", "sprite_abilityitemicon_14104", "25040701_fx_other_cursealtar"],
	["sacrifice", 1019101, "EnvUnit_MonoData_BtnDisplayName_SacrificialAltar", "sprite_abilityitemicon_14103", "25040702_fx_other_sacrificialaltar"],
	["old_day", 1010901, "EnvUnit_MonoData_BtnDisplayName_OldDayAltar", "sprite_abilityitemicon_14105", "25040701_fx_other_cursealtar"]]
var checks := 0
var failures: Array[String] = []
var captures: Array = []
var world: DungeonWorld

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1000, 650)
	world = DungeonWorld.new()
	world.catalog = JSON.parse_string(FileAccess.get_file_as_string("res://assets/catalog.json"))
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.presentation.set_process(false)
	world.presentation.audio_enabled = false
	for fixture in FIXTURES: await _fixture(fixture)
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "captures": captures, "scope": "Actual imported source map geometry, source altar SpriteRenderer images, particle bindings, source trigger interaction and consumed-state restoration. Rendering runs on the Godot reconstruction; original APK runtime and Unity shader pixel equivalence remain unobserved."}
	FileAccess.open("res://reports/altar-map-presentation.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("ALTAR_MAP_PRESENTATION ", JSON.stringify(report))
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _fixture(fixture: Array) -> void:
	world.load_environment(fixture[1])
	await process_frame
	var item: Dictionary = {}
	for candidate in world.interactions._items.values():
		if candidate.data.get("UIBtnName", "") == fixture[2]: item = candidate
	_check(not item.is_empty(), "%s source altar resolves by its semantic identity" % fixture[0])
	if item.is_empty(): return
	var node: Node3D = item.visual
	while node and node != world.environment_root:
		node.show()
		node.set_meta("unityActive", true)
		node = node.get_parent() as Node3D
	item.visible = true
	item.state.enabled = true
	world.interactions._apply(item)
	world.player = DungeonActor.new()
	world.player.combat = DungeonCombat.new()
	world.player.combat.configure(null, null, 1)
	world.player.set_physics_process(false)
	world.add_child(world.player)
	world.actors.append(world.player)
	world.player.position = item.visual.global_position
	world.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	world.camera.size = 5.6
	world.camera.global_position = item.visual.global_position + Vector3(3.7, 4.8, -4.4)
	world.camera.look_at(item.visual.global_position + Vector3.UP * 0.65, Vector3.UP)
	var sprites: Array[Node] = item.visual.find_children("SourceAltarPickup", "Sprite3D", true, false)
	_check(sprites.size() == 1, "%s recovers one missing source SpriteRenderer" % fixture[0])
	if sprites.is_empty(): return
	var sprite: Sprite3D = sprites[0]
	_check(sprite.get_meta("source_sprite", "") == fixture[3], "%s selects its actual source image despite the shared exported node name" % fixture[0])
	_check(sprite.texture != null and sprite.is_visible_in_tree(), "%s source pickup image is visible on its map" % fixture[0])
	_check(is_equal_approx(float(sprite.texture.get_width()) * sprite.pixel_size, 2.56), "%s uses the source image size and pixels per unit" % fixture[0])
	_check(not is_zero_approx(sprite.get_parent_node_3d().basis.determinant()), "%s converted planar sprite retains a valid billboard basis" % fixture[0])
	var before := sprite.get_parent_node_3d().transform
	var restored := preload("res://scripts/presentation/altar_billboards.gd").restore(sprite.get_parent_node_3d(), fixture[2])
	_check(restored == sprite and sprite.get_parent_node_3d().transform == before, "%s repeated restoration preserves its source transform" % fixture[0])
	var models: Array[Node] = item.visual.find_children("EnvUnit_CurseAltar*", "MeshInstance3D", true, false)
	_check(models.size() == 1 and models[0].mesh != null and models[0].is_visible_in_tree(), "%s retains the actual shared source stone platform" % fixture[0])
	_check(world.interactions.prompt_for(item)[2] == "sprite_conversation_get", "%s uses the source interaction icon" % fixture[0])
	_check(world.interactions.can_interact_at(str(item.id), item.visual.global_position), "%s is reachable through the actual imported trigger" % fixture[0])
	var effects: Node3D = world.environment_root.get_node("EnvironmentEffects")
	effects.set_process(false)
	var matching: Array = effects.bindings.filter(func(entry): return str(entry.address) == fixture[4] and item.visual.is_ancestor_of(entry.anchor))
	_check(matching.size() == 1, "%s binds its source altar effect once" % fixture[0])
	for frame in 90: effects._process(1.0 / 60.0)
	_check(not matching.is_empty() and is_instance_valid(matching[0].effect) and not matching[0].effect.emitters.is_empty(), "%s plays its recovered particle layers" % fixture[0])
	if fixture[0] == "old_day":
		_check(effects.bindings.any(func(entry): return entry.address == "23122101_fx_other_treasureboxcurse" and item.visual.is_ancestor_of(entry.anchor)), "Old-day altar retains its additional source curse aura")
	if DisplayServer.get_name() != "headless":
		await _capture(str(fixture[0]) + "-desktop", sprite)
		root.size = Vector2i(844, 390)
		await _capture(str(fixture[0]) + "-phone", sprite)
		root.size = Vector2i(1000, 650)
	var activation: Dictionary = world.interactions.interact(str(item.id))
	_check(activation.success and activation.context.data.UIBtnName == fixture[2], "%s interaction carries its exact source altar identity" % fixture[0])
	var consumed: bool = world.interactions.set_altar_consumed(str(item.id)) if fixture[0] == "sprites" else world.interactions.set_room_action_consumed(str(item.id))
	_check(consumed and not sprite.is_visible_in_tree(), "%s consumption hides the pickup" % fixture[0])
	_check(item.visual.is_visible_in_tree() and models[0].is_visible_in_tree(), "%s consumption retains its stone platform" % fixture[0])
	_check(not world.interactions.interact(str(item.id)).success, "%s consumed altar rejects another activation" % fixture[0])
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(world.interactions.snapshot()))
	_check(world.interactions.restore(snapshot) and not sprite.is_visible_in_tree(), "%s map-state restore keeps the pickup consumed" % fixture[0])
	effects._process(0.05)
	if fixture[0] != "sprites": _check(not matching[0].active, "%s source interaction effect stops after consumption" % fixture[0])

func _capture(label: String, sprite: Sprite3D) -> void:
	for frame in 4: await process_frame
	await RenderingServer.frame_post_draw
	var shown := root.get_texture().get_image()
	var image_scale := Vector2(shown.get_size()) / world.camera.get_viewport().get_visible_rect().size
	var center := world.camera.unproject_position(sprite.global_position) * image_scale
	var extent := Vector2(float(sprite.texture.get_width()), float(sprite.texture.get_height())) * sprite.pixel_size * Vector2(sprite.global_basis.x.length(), sprite.global_basis.y.length()) * 0.5
	var edge_x := world.camera.unproject_position(sprite.global_position + world.camera.global_basis.x * extent.x) * image_scale
	var edge_y := world.camera.unproject_position(sprite.global_position + world.camera.global_basis.y * extent.y) * image_scale
	var half := Vector2(absf(edge_x.x - center.x), absf(edge_y.y - center.y)) + Vector2.ONE * 2
	var region := Rect2i(Vector2i((center - half).floor()), Vector2i((half * 2).ceil())).intersection(Rect2i(Vector2i.ZERO, shown.get_size()))
	var path := "res://reports/altar-map-" + label + ".png"
	shown.save_png(path)
	sprite.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	var hidden := root.get_texture().get_image()
	var changed := 0
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			var a := shown.get_pixel(x, y)
			var b := hidden.get_pixel(x, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.1: changed += 1
	sprite.show()
	_check(changed > 80, label + " pickup contributes visible pixels")
	captures.append({"path": path, "pickup_pixels": changed, "sample_region": str(region)})

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)
