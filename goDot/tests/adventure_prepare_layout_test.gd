extends SceneTree

var failures: Array[String] = []
var checks := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var catalog = DungeonCatalog.new()
	check(catalog.load_all(), "Catalog loads")
	var systems = DungeonSystems.new(catalog, DungeonProfile.new())
	var canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var page = preload("res://scripts/presentation/adventure_prepare.gd").new()
	page.theme = DungeonStyle.theme()
	canvas.add_child(page)
	var rows: Array = []
	for level in range(11): rows.append({"difficulty_status": systems.difficulty_status(level)})
	page.configure(null, rows, {"difficulty": 0, "systems": systems, "catalog": catalog, "preparation": systems.adventure_preparation_status(0), "resources": [["sprite_materialicon_101", "229"], ["sprite_materialicon_90002", "0"]]})
	check(not page.start.disabled and page.row_buttons.size() == 11, "Default difficulty has an entry button and all tiers")
	page._select(1)
	check(page.start.disabled and not page.reason.text.is_empty(), "Locked tier can be inspected but cannot start")
	check(not systems.begin_run(12, 1, 100, 1).success, "UI gate is enforced by actual begin_run")
	for dimensions in [Vector2i(2460, 1080), Vector2i(1600, 900), Vector2i(844, 390)]:
		canvas.size = dimensions
		page.size = Vector2(dimensions)
		for frame in 10: await process_frame
		for control in [page.header, page.left, page.right, page.start, page.list]:
			check(page.get_global_rect().encloses(control.get_global_rect()), "Preparation control fits %s: %s" % [dimensions, control.get_class()])
		check(page.list.size.y > 90, "Difficulty list remains scrollable %s" % dimensions)
		check(page.equipment.get_child(0).get_child(0).get_global_rect().end.y <= page.equipment.get_global_rect().end.y, "Equipment content fits its card %s" % dimensions)
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var picture = canvas.get_texture().get_image()
			check(not picture.is_empty(), "Rendered preparation pixels")
			picture.save_png("/private/tmp/adventure-prepare-%dx%d.png" % [dimensions.x, dimensions.y])
	canvas.queue_free()
	await process_frame
	systems.decorations = null
	print("ADVENTURE_PREPARE_LAYOUT ", JSON.stringify({"checks": checks, "passed": failures.is_empty(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)
