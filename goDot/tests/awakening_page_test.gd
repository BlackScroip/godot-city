extends SceneTree

const Page = preload("res://scripts/presentation/awakening_page.gd")
var checks := 0
var failures: Array[String] = []
var catalog
var profile
var systems
var canvas: SubViewport
var view
var context: Dictionary
var last_result: Dictionary = {}
var emitted: Array = []

func _initialize() -> void:
	_run.call_deferred()

func settle() -> void:
	for frame in 12: await process_frame

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); printerr("AWAKENING PAGE: " + message)

func _run() -> void:
	catalog = DungeonCatalog.new()
	check(catalog.load_all(), "source catalog loads")
	profile = DungeonProfile.new()
	systems = DungeonSystems.new(catalog, profile)
	canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	view = Page.new()
	canvas.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	context = {"systems": systems, "catalog": catalog, "character_id": 1}
	view.command.connect(_command)
	view.configure(null, [], context)
	await settle()
	check(view.node_buttons.size() == 15 and view.character_buttons.size() == 8, "starter page contains all real nodes and eight character choices")
	check(view.selected_awakening == 103, "initial selection follows source unlock level rather than numeric id")
	check(view.unlock_button.disabled and view.toggle_button.disabled, "unbuilt guild blocks unlock and activation controls")
	profile.data.buildings["2"] = 1
	systems.grant_material(101, 1000000)
	systems.grant_material(503, 1000)
	view.refresh()
	await settle()
	check(view.unlock_button.disabled and str(view.selected_status.reason) == "觉醒等级不足", "source global level gate remains visible after funding")
	systems.set_record("entitlement:awake_pack", 1)
	view.refresh()
	await settle()
	check(not view.unlock_button.disabled and view.toggle_button.disabled, "funded eligible node unlocks independently of activation")
	var gold = systems.material(101)
	var cubes = systems.material(503)
	view.unlock_button.pressed.emit()
	await settle()
	check(last_result.get("success", false) and systems.stat("awake:unlocked:103") == 1, "unlock button changes source node ownership")
	check(systems.material(101) == gold - 10000 and systems.material(503) == cubes - 5, "unlock button pays exact source node price")
	check(view.selected_awakening == 103 and context.selected_awakening == 103 and view.unlock_button.disabled and not view.toggle_button.disabled, "refresh preserves selection and switches to activation")
	view.toggle_button.pressed.emit()
	await settle()
	check(profile.data.active_awakenings.has(103) and view.toggle_button.text == "停用", "activation applies selected node and exposes disable command")
	check(view.selected_status.used_points == 1 and view.budget_label.text.contains("1 /"), "active budget updates immediately")
	for id in [101, 105, 104, 102]:
		view.select_awakening(id)
		view.unlock_button.pressed.emit()
		await settle()
		check(last_result.get("success", false), "eligible node unlock " + str(id))
		if id != 102:
			view.toggle_button.pressed.emit()
			await settle()
			check(last_result.get("success", false), "affordable node activation " + str(id))
	check(view.toggle_button.disabled and view.selected_status.activation_reason == "潜能点不足", "per-character budget prevents over-activation")
	view.select_awakening(105)
	view.toggle_button.pressed.emit()
	await settle()
	check(not profile.data.active_awakenings.has(105) and view.selected_status.used_points == 5, "disable refunds potential budget without changing ownership")
	view.select_awakening(102)
	check(not view.toggle_button.disabled, "released points make eligible node actionable")
	view.select_character(2)
	await settle()
	check(view.selected_character == 2 and profile.data.selected_character == 1 and context.character_id == 1, "viewing another character preserves active camp character")
	check(view.node_buttons.size() == 10 and not view.node_buttons.has(211), "source admin nodes remain unavailable")
	check(view.unlock_button.disabled and view.selected_status.reason == "角色尚未解锁", "unowned character can be inspected without bypassing recruitment")
	check(context.awakening_character_id == 2 and view.selected_status.used_points == 0, "character selection persists and uses independent active budget")
	var expected_count := 0
	for character in range(1, 9):
		view.select_character(character)
		await settle()
		var expected: Array = catalog.rows("CharaTalentAwakeTreeData").filter(func(row): return int(row.chara_id) == character and not row.get("is_admin_mode", false) and row.get("is_enabled", true))
		expected_count += expected.size()
		check(view.node_buttons.size() == expected.size(), "all public source nodes rendered for character " + str(character))
		var previous_level := 0
		for row in view.node_rows:
			check(view.node_buttons.has(int(row.id)) and int(row.unlock_awake_tree_level) >= previous_level, "ordered source node " + str(int(row.id)))
			var source_icon = DungeonStyle.texture(str(row.icon_name))
			check(source_icon != null and view.node_buttons[int(row.id)].icon == source_icon, "source node uses its exact authored icon " + str(int(row.id)))
			previous_level = int(row.unlock_awake_tree_level)
	check(expected_count == 110, "all 110 public nodes have an accessible page")
	await _check_scroll_state()
	if "--render-check" in OS.get_cmdline_user_args():
		for dimensions in [Vector2i(1600, 900), Vector2i(390, 844)]:
			canvas.size = dimensions
			await settle()
			await RenderingServer.frame_post_draw
			canvas.get_texture().get_image().save_png("res://reports/awakening-page-character8-%dx%d.png" % [dimensions.x, dimensions.y])
	view.select_character(1)
	view.select_awakening(103)
	await settle()
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390), Vector2i(2460, 1080), Vector2i(390, 844)]:
		canvas.size = dimensions
		await settle()
		if not _inside(view.body, dimensions): print("AWAKENING_LAYOUT ", dimensions, " page=", view.get_global_rect(), " body=", view.body.get_global_rect(), " collection=", view.collection_scroll.get_global_rect(), " detail=", view.detail_scroll.get_global_rect(), " characters=", view.character_scroll.get_global_rect())
		check(_inside(view.body, dimensions), "body remains inside viewport " + str(dimensions))
		check(view.collection_scroll.size.x > 100 and view.collection_scroll.size.y > 80 and view.detail_scroll.size.x > 100 and view.detail_scroll.size.y > 80, "both interactive regions remain usable " + str(dimensions))
		check(not view.collection_scroll.get_global_rect().intersects(view.detail_scroll.get_global_rect()), "node collection and detail do not overlap " + str(dimensions))
		var last_node: Button = view.node_buttons[int(view.node_rows.back().id)]
		view.collection_scroll.ensure_control_visible(last_node)
		await settle()
		check(view.collection_scroll.get_global_rect().grow(1).encloses(last_node.get_global_rect()), "last source level can be reached " + str(dimensions))
		view.detail_scroll.ensure_control_visible(view.toggle_button)
		await settle()
		check(view.detail_scroll.get_global_rect().grow(1).encloses(view.toggle_button.get_global_rect()), "activation command can be reached " + str(dimensions))
		view.collection_scroll.scroll_vertical = 0
		view.detail_scroll.scroll_vertical = 0
		await settle()
		if "--render-check" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			var image = canvas.get_texture().get_image()
			var colors: Dictionary = {}
			for y in range(0, dimensions.y, 20):
				for x in range(0, dimensions.x, 20): colors[image.get_pixel(x, y).to_rgba32()] = true
			check(colors.size() > 20, "nonblank rendered page " + str(dimensions))
			image.save_png("res://reports/awakening-page-%dx%d.png" % [dimensions.x, dimensions.y])
	var restored = DungeonProfile.new()
	check(restored.restore(JSON.parse_string(JSON.stringify(profile.data))), "UI unlock and activation transactions survive JSON restore")
	check(restored.data.active_awakenings.has(103) and restored.data.stats["awake:unlocked:105"] == 1 and not restored.data.active_awakenings.has(105), "reload preserves ownership and disabled activation separately")
	view.free()
	canvas.queue_free()
	await settle()
	var report = {"checks": checks, "failures": failures, "passed": failures.is_empty(), "rendered": "--render-check" in OS.get_cmdline_user_args(), "source_nodes": 120, "public_nodes": 110, "scope": "Local dedicated awakening page, source-level ordering, exact source icons for every public node, actual domain transactions, budget and four viewport layouts. Includes recovered character-eight artwork renders. Source APK not executed."}
	var file = FileAccess.open("res://reports/awakening-page-test.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("AWAKENING_PAGE_TEST ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func _command(kind: String, id: Variant, extra: Variant) -> void:
	emitted.append({"kind": kind, "id": id, "extra": extra})
	if kind.begins_with("op:"):
		last_result = systems.call(kind.trim_prefix("op:"), int(id))
		view.refresh.call_deferred()

func _check_scroll_state() -> void:
	canvas.size = Vector2i(844, 390)
	view.select_character(8)
	view.select_awakening(815)
	await settle()
	view.collection_scroll.scroll_vertical = 220
	view.detail_scroll.scroll_vertical = 50
	await settle()
	var collection_y = view.collection_scroll.scroll_vertical
	var detail_y = view.detail_scroll.scroll_vertical
	check(collection_y > 0 and detail_y > 0, "scroll fixture moves both collections and long node details")
	check(int(context.awakening_collection_scroll) == collection_y and int(context.awakening_detail_scroll) == detail_y, "both scroll positions are retained in page context")
	view.refresh()
	await settle()
	check(view.collection_scroll.scroll_vertical == collection_y and view.detail_scroll.scroll_vertical == detail_y, "same-node refresh preserves collection and detail positions")
	view.select_awakening(815)
	await settle()
	check(view.detail_scroll.scroll_vertical == detail_y, "selecting the current node preserves detail position")
	view.free()
	view = Page.new()
	canvas.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.command.connect(_command)
	view.configure(null, [], context)
	await settle()
	check(view.selected_character == 8 and view.selected_awakening == 815, "reopening from context preserves inspected character and node")
	check(view.collection_scroll.scroll_vertical == collection_y and view.detail_scroll.scroll_vertical == detail_y, "reopening from context restores both scroll positions")
	view.select_awakening(814)
	await settle()
	check(view.collection_scroll.scroll_vertical == collection_y and view.detail_scroll.scroll_vertical == 0, "changing node resets only detail position")
	view.detail_scroll.scroll_vertical = 50
	view.select_character(1)
	await settle()
	check(view.collection_scroll.scroll_vertical == 0 and view.detail_scroll.scroll_vertical == 0, "changing character resets both scroll positions")
	check(int(context.awakening_collection_scroll) == 0 and int(context.awakening_detail_scroll) == 0, "character change clears persisted scroll offsets")
	view.select_character(8)
	await settle()

func _inside(control: Control, dimensions: Vector2i) -> bool:
	return Rect2(Vector2.ZERO, Vector2(dimensions)).grow(1).encloses(control.get_global_rect())
