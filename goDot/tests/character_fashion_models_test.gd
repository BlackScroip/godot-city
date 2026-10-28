extends SceneTree

const Models = preload("res://scripts/presentation/character_fashion_models.gd")
const SOURCE := "res://assets/ui/role_character/CharaFashionConfigData.json"
const REGISTRY := "res://assets/characters/fashions/catalog.json"
const APK_SHA256 := "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505"
const SIZES := [Vector2i(1600, 900), Vector2i(844, 390)]
const SCREENSHOT_IDS := [1001, 1002, 2003, 7201, 8004]

var checks := 0
var failures: Array[String] = []
var rendered := false
var coverage := {"models": 0, "meshes": 0, "skins": 0, "animation_clips": 0, "character_previews": 0, "fashion_previews": 0, "render_cases": 0}
var model_cases: Array = []
var render_cases: Array = []
var commands: Array = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("CHARACTER_FASHION_MODELS: " + message)

func _run() -> void:
	rendered = "--render-check" in OS.get_cmdline_user_args()
	if rendered and DisplayServer.get_name() == "headless":
		check(false, "Render checks require an explicitly coordinated graphics run")
		_finish()
		return
	var source: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
	var registry: Variant = JSON.parse_string(FileAccess.get_file_as_string(REGISTRY))
	check(source is Array and source.size() == 45, "The exact APK table contains all 45 fashion records")
	check(registry is Dictionary and int(registry.get("schema", 0)) == 1, "Fashion model registry uses its declared schema")
	if not source is Array or not registry is Dictionary:
		_finish()
		return
	var models: Dictionary = registry.get("models", {})
	check(str(registry.get("apk_sha256", "")) == APK_SHA256, "All fashion models identify the requested APK")
	check(models.size() == 45 and models.size() == source.size(), "Registry covers the whole source table without extra records")
	check(Models.path_for(0).is_empty() and Models.path_for(999999).is_empty(), "Unknown fashions cannot resolve to a default model")
	var paths := {}
	var appearances := {}
	var stage := Node3D.new()
	root.add_child(stage)
	for row in source:
		var id := int(row.id)
		var character_id := int(row.chara_id)
		var entry: Dictionary = models.get(str(id), {})
		var expected := "res://assets/characters/fashions/fashion_%d.glb" % id
		check(not entry.is_empty() and int(entry.get("id", 0)) == id, "Registry has the exact source fashion id %d" % id)
		check(int(entry.get("character_id", 0)) == character_id, "Fashion %d retains its source character" % id)
		check(str(entry.get("prefab", "")) == str(row.model_prefab_path), "Fashion %d uses its full source prefab" % id)
		check(str(entry.get("source_asset", "")).get_file() == str(row.model_prefab_path) + ".prefab", "Fashion %d retains full prefab provenance" % id)
		check(str(entry.get("path", "")) == expected and Models.path_for(id) == expected, "Fashion %d resolves its own model without a default substitute" % id)
		check(not paths.has(expected), "Fashion %d has a distinct scene path" % id)
		paths[expected] = true
		if not ResourceLoader.exists(expected):
			check(false, "Fashion %d model is imported and loadable" % id)
			continue
		check(FileAccess.get_sha256(expected) == str(entry.get("glb_sha256", "")), "Fashion %d file matches the registered extracted content" % id)
		var packed = load(expected)
		check(packed is PackedScene, "Fashion %d imports as an actual scene" % id)
		if not packed is PackedScene: continue
		var model = packed.instantiate()
		stage.add_child(model)
		var result := _inspect_model(model, entry, id)
		result["character_id"] = character_id
		model_cases.append(result)
		if not appearances.has(character_id): appearances[character_id] = []
		if not result.appearance in appearances[character_id]: appearances[character_id].append(result.appearance)
		coverage.models += 1
		model.free()
	stage.free()
	for character_id in range(1, 9):
		check(appearances.get(character_id, []).size() >= 2, "Character %d fashions contain distinct source material or texture content" % character_id)
	check(coverage.models == 45 and coverage.meshes == 135 and coverage.skins == 135, "All 45 full source models and 135 skinned renderers are exercised")
	if coverage.models == 45: await _real_preview_flow(source)
	_finish()

func _inspect_model(model: Node, entry: Dictionary, id: int) -> Dictionary:
	check(model.scene_file_path == str(entry.path), "Loaded scene preserves exact fashion identity %d" % id)
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	var skins := 0
	var texture_count := 0
	var signatures: Array[String] = []
	check(not meshes.is_empty() and meshes.size() == int(entry.get("meshes", 0)), "Fashion %d imports every declared mesh" % id)
	for mesh in meshes:
		check(mesh.mesh != null and mesh.mesh.get_surface_count() > 0, "Fashion %d has renderable mesh surfaces" % id)
		check(mesh.skin != null and mesh.get_node_or_null(mesh.skeleton) is Skeleton3D, "Fashion %d binds its source skin to an actual skeleton" % id)
		if mesh.skin != null: skins += 1
		if mesh.mesh == null: continue
		for surface in mesh.mesh.get_surface_count():
			var material = mesh.get_active_material(surface)
			check(material != null, "Fashion %d mesh surface has an imported material" % id)
			if not material is BaseMaterial3D: continue
			var texture: Texture2D = material.albedo_texture
			if texture == null: continue
			var image := texture.get_image()
			check(image != null and not image.is_empty(), "Fashion %d has real texture pixels" % id)
			if image == null or image.is_empty(): continue
			texture_count += 1
			var digest := HashingContext.new()
			digest.start(HashingContext.HASH_SHA256)
			digest.update(image.get_data())
			signatures.append(str(material.albedo_color) + ":" + digest.finish().hex_encode())
	check(skins == int(entry.get("skins", 0)) and skins > 0, "Fashion %d imports all registered skins" % id)
	check(texture_count > 0, "Fashion %d is textured rather than a blank substitute" % id)
	var players := model.find_children("*", "AnimationPlayer", true, false)
	check(not players.is_empty(), "Fashion %d contains an animation player" % id)
	var clips: Dictionary = {}
	var idle_player: AnimationPlayer
	var idle := ""
	for player in players:
		for clip in player.get_animation_list():
			clips[str(clip)] = true
			if idle.is_empty() and "idle" in str(clip).to_lower():
				idle = str(clip)
				idle_player = player
	var expected_clips: Array = entry.get("animations", [])
	check(not expected_clips.is_empty(), "Fashion %d registry retains source animation names" % id)
	for clip in expected_clips: check(clips.has(str(clip)), "Fashion %d imports source animation %s" % [id, clip])
	check(not idle.is_empty(), "Fashion %d has a source idle animation" % id)
	if not idle.is_empty():
		var animation := idle_player.get_animation(idle)
		check(animation.length > 0 and animation.get_track_count() > 0, "Fashion %d idle contains actual animation tracks" % id)
		idle_player.play(idle)
		idle_player.seek(0.0, true)
		idle_player.advance(0.0)
		var before := _bone_poses(model)
		idle_player.seek(animation.length * 0.37, true)
		idle_player.advance(0.0)
		var after := _bone_poses(model)
		check(_poses_differ(before, after), "Fashion %d idle changes actual bone poses" % id)
	signatures.sort()
	coverage.meshes += meshes.size()
	coverage.skins += skins
	coverage.animation_clips += expected_clips.size()
	return {"id": id, "path": model.scene_file_path, "meshes": meshes.size(), "skins": skins, "textured_surfaces": texture_count, "animation_clips": expected_clips.size(), "idle": idle, "appearance": "|".join(signatures)}

func _bone_poses(model: Node) -> Array:
	var result: Array = []
	for skeleton in model.find_children("*", "Skeleton3D", true, false):
		for bone in skeleton.get_bone_count(): result.append(skeleton.get_bone_pose(bone))
	return result

func _poses_differ(before: Array, after: Array) -> bool:
	if before.is_empty() or before.size() != after.size(): return false
	for index in before.size():
		if not before[index].is_equal_approx(after[index]): return true
	return false

func _real_preview_flow(source: Array) -> void:
	var canvas := SubViewport.new()
	canvas.size = SIZES[0]
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var game = load("res://scenes/main.tscn").instantiate()
	game.save_store = DungeonSaveStore.new("/private/tmp/character-fashion-models-%d.json" % Time.get_ticks_usec())
	canvas.add_child(game)
	var deadline := Time.get_ticks_msec() + 60000
	while not game.initialized and Time.get_ticks_msec() < deadline: await process_frame
	check(game.initialized, "Actual game initializes with an isolated fashion preview save")
	if not game.initialized:
		canvas.queue_free()
		await process_frame
		return
	game.set_process(false)
	game.world.set_physics_process(false)
	game.audio.stop()
	# The paid-fashions owner is available so payment checks cannot pass just because the character is locked.
	game.profile.data.character_levels["7"] = 1
	game.menus.open("characters", 1)
	await _settle()
	var initial_profile: Dictionary = game.profile.data.duplicate(true)
	var initial_owned: Array = game.systems.character_fashion_owned().duplicate()
	check(initial_owned.size() == 8 and not 7201 in initial_owned, "Preview starts with only the eight source defaults and no paid entitlement")
	for character_id in range(1, 9):
		game.menus.open("characters", character_id)
		await _settle()
		var view = game.hud.page.character_view
		check(is_instance_valid(view) and view._character_id() == character_id, "Real character menu browses character %d" % character_id)
		view.command.connect(func(kind, id, extra): commands.append([kind, id, extra]))
		view.fashion_button.pressed.emit()
		await _settle()
		var page = view._fashion_overlay
		var rows: Array = source.filter(func(row): return int(row.chara_id) == character_id)
		check(page.visible and page.swatches.size() == rows.size(), "Fashion page exposes every source swatch for character %d" % character_id)
		for index in rows.size():
			var row: Dictionary = rows[index]
			var id := int(row.id)
			var expected := Models.path_for(id)
			page.swatches[index].pressed.emit()
			check(page.selected_id == id and int(view._selected_fashion().get("id", 0)) == id, "Swatch selects the exact fashion %d" % id)
			check(not page._model_button.disabled, "Fashion %d exposes its recovered 3D preview even when unowned" % id)
			if not page._use_model: page._model_button.pressed.emit()
			view._select_showcase(view.selected)
			check(not view.model_button.disabled, "Character page also exposes the selected fashion %d model" % id)
			if not view.use_model: view.model_button.pressed.emit()
			await _settle()
			var fashion_preview := _check_preview(page._art, expected, "fashion %d" % id)
			var character_preview := _check_preview(view.showcase, expected, "character fashion %d" % id)
			coverage.fashion_previews += 1
			coverage.character_previews += 1
			var quote: Dictionary = game.systems.character_fashion_status(id, character_id)
			check(bool(quote.owned) == bool(row.default_unlock), "Preview does not grant source fashion %d ownership" % id)
			if not bool(row.default_unlock):
				var action = page.find_child("FashionAction", true, false)
				check(action is Button and action.disabled, "Unowned fashion %d retains its purchase or entitlement restriction" % id)
			if id in [7201, 7202, 7203, 7204, 7205]:
				check(not quote.can_unlock and (bool(row.is_cash_only_unlock) or int(quote.grant_owner_id) == 7201), "Paid fashion %d is blocked by its source payment or core-entitlement rule" % id)
				var before: Dictionary = game.profile.data.duplicate(true)
				check(not game.systems.unlock_character_fashion(id, character_id).success and game.profile.data == before, "Preview cannot fabricate paid core or attached variant %d" % id)
			for dimensions in SIZES:
				canvas.size = dimensions
				game.hud._layout()
				await _settle()
				_check_layout(view, page, dimensions, id)
				if rendered and is_instance_valid(fashion_preview):
					await _render_preview(fashion_preview, id, dimensions, "fashion")
					if id in SCREENSHOT_IDS:
						await RenderingServer.frame_post_draw
						canvas.get_texture().get_image().save_png("res://reports/character-fashion-model-%d-%dx%d.png" % [id, dimensions.x, dimensions.y])
						page.hide()
						await _settle()
						if is_instance_valid(character_preview): await _render_preview(character_preview, id, dimensions, "character")
						await RenderingServer.frame_post_draw
						canvas.get_texture().get_image().save_png("res://reports/character-fashion-equipped-preview-%d-%dx%d.png" % [id, dimensions.x, dimensions.y])
						page.show()
			check(game.profile.data == initial_profile and game.systems.character_fashion_owned() == initial_owned, "All fashion %d preview controls leave progression and entitlements unchanged" % id)
			check(commands.is_empty(), "Fashion %d preview emits no purchase, equip or character command" % id)
		page.close()
		await _settle()
		check(view._preview_fashion == 0 and not view.owner_page.page_context.fashion_open, "Closing fashion returns character %d to its equipped appearance" % character_id)
		_check_preview(view.showcase, Models.path_for(character_id * 1000 + 1), "restored character %d default" % character_id)
	check(coverage.character_previews == 45 and coverage.fashion_previews == 45, "Both actual page previews exercised all 45 source fashions")
	check(game.profile.data == initial_profile and commands.is_empty(), "The complete browsing flow cannot unlock, equip, spend or grant payment")
	canvas.queue_free()
	await process_frame

func _settle() -> void:
	for frame in 3: await process_frame

func _check_preview(holder: Control, expected: String, label: String) -> DungeonModelPreview:
	var preview: DungeonModelPreview
	for child in holder.get_children():
		if child is DungeonModelPreview:
			preview = child
			break
	check(is_instance_valid(preview), "Actual 3D control exists for " + label)
	if not is_instance_valid(preview): return null
	check(preview.pivot.get_child_count() == 1, "Preview contains exactly one fashion scene for " + label)
	if preview.pivot.get_child_count() != 1: return preview
	var model := preview.pivot.get_child(0)
	check(model.scene_file_path == expected and not expected.is_empty(), "Preview displays the exact registered scene for " + label)
	var players := model.find_children("*", "AnimationPlayer", true, false)
	check(players.any(func(player): return player.is_playing() and "idle" in str(player.current_animation).to_lower()), "Preview starts its real idle animation for " + label)
	check(players.any(func(player): return not str(player.current_animation).is_empty() and player.get_animation(player.current_animation).loop_mode != Animation.LOOP_NONE), "Preview keeps idle animation looping for " + label)
	return preview

func _check_layout(view, page, dimensions: Vector2i, id: int) -> void:
	var bounds := Rect2(Vector2.ZERO, Vector2(dimensions)).grow(1)
	var label := "%d/%dx%d" % [id, dimensions.x, dimensions.y]
	check(bounds.encloses(page._model_button.get_global_rect()), "Fashion 3D toggle stays reachable " + label)
	check(bounds.encloses(view.model_button.get_global_rect()), "Character 3D toggle stays reachable " + label)
	check(bounds.encloses(page._art.get_global_rect()) and page._art.get_global_rect().size.x > 100, "Fashion model area stays visible " + label)
	check(page._art.get_global_rect().end.x <= page._details.get_global_rect().position.x + 1, "Fashion model and details remain separate " + label)
	check(view.showcase.get_global_rect().end.x <= view.right_column.get_global_rect().position.x + 1, "Character model and attributes remain separate " + label)
	var effect_scroll = page.find_child("FashionEffectsScroll", true, false)
	var suit_card = page.find_child("SuitCard", true, false)
	check(effect_scroll is ScrollContainer and effect_scroll.get_global_rect().end.y <= suit_card.get_global_rect().position.y, "Long fashion effects stay scrollable above the suit and purchase controls " + label)

func _render_preview(preview: DungeonModelPreview, id: int, dimensions: Vector2i, page: String) -> void:
	if preview.pivot.get_child_count() != 1: return
	var model := preview.pivot.get_child(0)
	var players := model.find_children("*", "AnimationPlayer", true, false)
	var idle_player: AnimationPlayer
	for player in players:
		if "idle" in str(player.current_animation).to_lower():
			idle_player = player
			break
	if not is_instance_valid(idle_player): return
	var idle := str(idle_player.current_animation)
	var animation := idle_player.get_animation(idle)
	idle_player.seek(0.0, true)
	idle_player.advance(0.0)
	idle_player.pause()
	await _settle()
	await RenderingServer.frame_post_draw
	var first := preview.viewport.get_texture().get_image()
	check(first != null and not first.is_empty(), "GPU returns actual model pixels %s/%d/%s" % [page, id, dimensions])
	if first == null or first.is_empty():
		idle_player.play(idle)
		return
	idle_player.seek(animation.length * 0.37, true)
	idle_player.advance(0.0)
	await _settle()
	await RenderingServer.frame_post_draw
	var second := preview.viewport.get_texture().get_image()
	var visible := 0
	var changed := 0
	var colors := {}
	var minimum := first.get_size()
	var maximum := Vector2i(-1, -1)
	for y in range(0, first.get_height(), 2):
		for x in range(0, first.get_width(), 2):
			var before := first.get_pixel(x, y)
			var after := second.get_pixel(x, y)
			if before.a > 0.1:
				visible += 1
				minimum = minimum.min(Vector2i(x, y))
				maximum = maximum.max(Vector2i(x, y))
				colors[Vector3i(int(before.r * 15), int(before.g * 15), int(before.b * 15))] = true
			if maxf(maxf(absf(before.r - after.r), absf(before.g - after.g)), maxf(absf(before.b - after.b), absf(before.a - after.a))) > 0.025: changed += 1
	var sample_count := ceili(first.get_width() / 2.0) * ceili(first.get_height() / 2.0)
	var label := "%s/%d/%dx%d" % [page, id, dimensions.x, dimensions.y]
	check(visible > sample_count * 0.015 and colors.size() > 8, "Rendered model is visibly textured and nonblank " + label)
	check(minimum.x > 0 and minimum.y > 0 and maximum.x < first.get_width() - 2 and maximum.y < first.get_height() - 2, "Camera frames the whole idle model with a visible margin " + label)
	check(changed > 12, "Actual idle animation changes rendered model pixels " + label)
	render_cases.append({"page": page, "id": id, "viewport": str(dimensions), "visible_samples": visible, "changed_samples": changed, "color_bins": colors.size(), "model_pixels": str(first.get_size())})
	coverage.render_cases += 1
	idle_player.play(idle)

func _finish() -> void:
	var report := {"checks": checks, "passed": failures.is_empty(), "failures": failures, "rendered": rendered, "coverage": coverage, "models": model_cases, "render_cases": render_cases, "scope": "Exact APK full fashion prefab scenes, textures, skin bindings, source idle bone motion and actual Godot character/fashion page previews. Optional GPU checks cover desktop/mobile pixels and layout. Browsing uses an isolated save and grants no material purchases, paid entitlements or equipped fashions. Original APK runtime and platform payments are not executed."}
	var file := FileAccess.open("res://reports/character-fashion-models.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("CHARACTER_FASHION_MODELS ", JSON.stringify({"checks": checks, "passed": failures.is_empty(), "failures": failures, "rendered": rendered, "coverage": coverage}))
	quit(0 if failures.is_empty() else 1)
