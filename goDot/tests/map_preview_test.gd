extends SceneTree

var failures: Array[String] = []
var assertions := 0

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var campaign = DungeonCampaign.new()
	campaign.configure()
	campaign.generate(12345, 0)
	var initial = campaign.route_map()
	check(not initial.is_empty(), "Route selection has a map")
	var region = int(campaign.state.layers[0].region)
	for row in initial: check(int(row.Region) == region, "Map stays within the current chapter")
	campaign.enter(int(campaign.choices()[0].node_id))
	var snapshot = campaign.snapshot().duplicate(true)
	var preview = campaign.route_map()
	check(preview.size() == initial.size(), "Room can inspect its chapter")
	check(preview.filter(func(row): return row.get("current", false)).size() == 1, "Preview has one current room")
	for row in preview:
		check(not row.available and not row.vertical, "Preview cannot enter or shift rooms")
		row["config_id"] = int(row.layer_index) * 100000000 + int(row.node_id)
	check(campaign.snapshot() == snapshot, "Preview does not mutate progress")
	var page = DungeonRoutePage.new()
	root.add_child(page)
	page.size = Vector2(1280, 720)
	page.configure(preview, {"preview": true, "current_layer": 0, "first_layer": 0})
	var commands: Array = []
	page.command.connect(func(kind, _id, _extra): commands.append(kind))
	page._select(int(preview[0].node_id))
	page._confirm()
	check(not page.confirm.visible and not page.automatic.visible, "Preview hides route mutation controls")
	check(page.selected_id == 0 and commands.is_empty(), "Preview rejects selection and confirmation")
	await process_frame
	check(page.nodes.any(func(key): return key.portrait != null and key.room.get("current", false)), "Current room displays the character portrait")
	page.queue_free()
	campaign.resolve_action()
	campaign.complete_room()
	check(not campaign.route_map().is_empty(), "Reward phase retains read-only map")
	campaign.advance()
	var rows: Array = [
		{"node_id": 10, "config_id": 10, "layer_index": 0, "lane": 0, "lane_count": 1, "available": true},
		{"node_id": 20, "config_id": 20, "layer_index": 0, "lane": 0, "lane_count": 1, "available": true},
		{"node_id": 10, "config_id": 100000010, "layer_index": 1, "lane": 0, "lane_count": 1, "available": false}
	]
	page = DungeonRoutePage.new()
	root.add_child(page)
	page.configure(rows, {})
	page._select(20, 0)
	page.nodes[2].pressed.emit()
	check(page.selected_id == 20, "Future duplicate ID cannot change the selected current node")
	check(page.nodes.filter(func(key): return key.chosen).size() == 1, "Only one occurrence is highlighted")
	page.queue_free()
	var hud = DungeonHud.new()
	root.add_child(hud)
	var actions: Array = []
	hud.action.connect(func(kind, _id, _extra): actions.append(kind))
	hud.adventure_button.pressed.emit()
	hud.set_adventure_mode(true)
	hud.adventure_button.pressed.emit()
	check(hud.adventure_caption.text == "难度", "Adventure HUD shows difficulty entry")
	hud.set_adventure_mode(false)
	hud.adventure_button.pressed.emit()
	check(actions == ["primary", "page:difficulty", "primary"], "Navigation dispatch follows current adventure state")
	check(hud.adventure_caption.text == "开始冒险", "Camp restores adventure caption")
	hud.queue_free()
	await process_frame
	print("MAP_PREVIEW ", JSON.stringify({"passed": failures.is_empty(), "assertions": assertions, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
