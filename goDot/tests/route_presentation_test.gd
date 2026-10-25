extends SceneTree

var failures: Array[String] = []
var assertions := 0
var captures: Array[String] = []
var game: Node
var canvas: SubViewport

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message)

func _run() -> void:
	create_timer(90).timeout.connect(func():
		push_error("Route presentation test timed out")
		quit(2))
	canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var display = TextureRect.new()
	display.texture = canvas.get_texture()
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(display)
	game = load("res://scenes/main.tscn").instantiate()
	game.save_store = DungeonSaveStore.new("res://reports/route-presentation-profile-%d.json" % Time.get_ticks_usec())
	canvas.add_child(game)
	await process_frame
	game.set_process(false)
	game.world.set_physics_process(false)
	game.hud.close_page()
	var player: DungeonActor = game.world.player
	player.position = Vector3(28.8, 0.1, 66.2)
	var ground: Dictionary = game.world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(player.position + Vector3.UP * 3, player.position + Vector3.DOWN * 3, 1))
	if not ground.is_empty(): player.position.y = ground.position.y + 0.06
	game.world.camera.position = player.position + game.world._camera_offset
	game.world.camera.look_at(player.position)
	game.world._camera_focus = player.position + Vector3.UP * 0.4
	check(is_instance_valid(player.direction_indicator), "Player has a ground direction indicator")
	var arrow: MeshInstance3D = player.direction_indicator.get_node_or_null("FacingArrow")
	check(is_instance_valid(arrow) and arrow.mesh.get_surface_count() == 1, "Ground indicator includes the rendered facing arrow")
	var enemy = DungeonActor.new()
	game.world.add_child(enemy)
	check(enemy.direction_indicator == null, "Enemy does not receive player indicator")
	enemy.queue_free()
	for direction in [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT]:
		player.face_direction(direction)
		for step in 40: player._process(1.0 / 60)
		var forward = player.direction_indicator.global_basis * Vector3.BACK
		check(forward.dot(direction) > 0.999, "Indicator arrow matches facing " + str(direction))
		check(is_equal_approx(player.direction_indicator.rotation.y, player.visual.rotation.y), "Indicator follows visible rotation")
	player.start_dodge(Vector3.RIGHT)
	for step in 40: player._process(1.0 / 60)
	check((player.direction_indicator.global_basis * Vector3.BACK).dot(Vector3.RIGHT) > 0.999, "Dodge updates direction indicator")
	player.dodge_elapsed = -1
	player.dead = true
	player._process(0.016)
	check(not player.direction_indicator.visible, "Defeated player's indicator hides")
	player.dead = false
	player._process(0.016)
	for dimensions in [Vector2i(1280, 720), Vector2i(2460, 1080), Vector2i(844, 390)]:
		canvas.size = dimensions
		for step in 8: await process_frame
		await _capture("direction-%dx%d" % [dimensions.x, dimensions.y])
	canvas.size = Vector2i(1280, 720)
	var original_zoom: float = game.world.camera.size
	game.world.camera.size = 9
	for step in 8: await process_frame
	await _capture("direction-detail")
	game.world.camera.size = original_zoom
	game.systems.begin_run(12345, 1, player.combat.max_health, 0)
	game.campaign.generate(12345, 0)
	game._route()
	for step in 8: await process_frame
	check(game.hud.page._layout == "route", "Adventure opens route map")
	check(game.hud.page.route_view.rows.size() > game.campaign.choices().size(), "Map previews future region nodes")
	check(not game.hud.navigation.visible, "Map hides camp navigation")
	check(game.hud.page.position == Vector2.ZERO, "Map fills viewport")
	var route: DungeonRoutePage = game.hud.page.route_view
	route.confirm.pressed.emit()
	await _wait_transition()
	check(game.campaign.state.phase == "room", "Confirm enters selected entrance")
	game._finish_noncombat()
	game._action("next", 0, 0)
	check(game.campaign.state.phase == "reward", "Unopened entrance chest requires leave confirmation")
	game._action("leave_unclaimed", 0, 0)
	for step in 8: await process_frame
	check(game.campaign.choices().size() == 3, "First branch offers three rooms")
	for dimensions in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2460, 1080), Vector2i(1200, 900), Vector2i(844, 390)]:
		canvas.size = dimensions
		for step in 10: await process_frame
		route = game.hud.page.route_view
		check(Rect2(Vector2.ZERO, route.size).encloses(route.header.get_rect()), "Header fits " + str(dimensions))
		check(Rect2(Vector2.ZERO, route.size).encloses(route.footer.get_rect()), "Footer fits " + str(dimensions))
		check(route.scroll.get_rect().end.y <= route.footer.position.y, "Graph and footer do not overlap " + str(dimensions))
		check(route.graph.custom_minimum_size.x > route.scroll.size.x, "Map scrolls horizontally " + str(dimensions))
		for index in route.rows.size():
			var row: Dictionary = route.rows[index]
			check(route.nodes[index].disabled != bool(row.available), "Only reachable nodes are enabled")
			check(route.nodes[index].position.y >= 0 and route.nodes[index].get_rect().end.y <= route.graph.size.y, "Node fits graph")
		await _capture("route-%dx%d" % [dimensions.x, dimensions.y])
	var choices: Array = game.campaign.choices()
	var chosen = int(choices[2].node_id)
	route._select(chosen)
	check(game.campaign.state.phase == "route", "Selecting a room waits for confirmation")
	var future = 0
	for row in route.rows:
		if int(row.layer_index) > int(game.campaign.state.layer_index):
			future = int(row.node_id)
			break
	route._select(future)
	check(route.selected_id == chosen, "Future node cannot replace selection")
	route.automatic.button_pressed = true
	check(game.profile.data.get("auto_route", false), "Automatic route preference persists")
	check(game.campaign.state.phase == "route", "Automatic route does not skip a branching choice")
	route.confirm.pressed.emit()
	await _wait_transition()
	check(int(game.campaign.state.current_node_id) == chosen, "Confirm enters selected third branch")
	check(not game.hud.modal_open and game.hud.navigation.visible, "Entering restores combat HUD")
	await _check_lane_change()
	game.profile.data["auto_route"] = true
	game.campaign.generate(12345, 0)
	game._route()
	await _wait_transition()
	check(game.campaign.state.phase == "room", "Automatic route enters single entrance")
	game.profile.data["auto_route"] = false
	game._camp()
	game.menus.open("characters")
	check(game.hud.page.route_view == null and game.hud.page.body.visible == false, "Other specialized menus replace map")
	game.menus.open("camp")
	check(game.hud.page.body.visible, "Standard menus restore their content")
	var report = {"passed": failures.is_empty(), "assertions": assertions, "failures": failures, "captures": captures, "renderer": DisplayServer.get_name()}
	FileAccess.open("res://reports/route-presentation.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("ROUTE_PRESENTATION ", JSON.stringify(report))
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _check_lane_change() -> void:
	game.profile.data["auto_route"] = false
	_complete_route_room()
	game._route()
	for step in 8: await process_frame
	var destinations: Array = game.campaign.vertical_choices()
	check(destinations.size() == 1, "Completed lower lane exposes the authored upper neighbor")
	if destinations.is_empty(): return
	var target = int(destinations[0].node_id)
	var before: Dictionary = game.campaign.snapshot()
	game._enter_node(target)
	check(game.campaign.snapshot() == before, "Insufficient resource leaves route and room unchanged")
	check(game.systems.search_point_count() == 0, "Failed lane change never deducts resource")
	var route: DungeonRoutePage = game.hud.page.route_view
	for key in route.nodes:
		if int(key.room.node_id) == target and int(key.room.layer_index) == 1:
			check(key.disabled, "Unaffordable vertical destination is disabled")
	game.systems.effects.acquire(15102)
	check(game.systems.search_point_count() == 2, "Spirit bottle grants resource in the live game")
	game._route()
	canvas.size = Vector2i(1920, 1080)
	for step in 8: await process_frame
	route = game.hud.page.route_view
	check(int(route.context.search) == 2 and int(route.context.search_max) == 3, "Map displays actual resource balance and capacity")
	var blocked = int(game.campaign.state.layers[2].node_ids[0])
	game._enter_node(blocked)
	check(game.campaign.state.phase == "route" and game.systems.search_point_count() == 2, "Arrowless room is blocked without spending resource")
	var button: DungeonRouteNode
	for key in route.nodes:
		if int(key.room.node_id) == target and int(key.room.layer_index) == 1: button = key
	check(is_instance_valid(button) and not button.disabled, "Affordable linked neighbor is selectable")
	if not is_instance_valid(button): return
	button.pressed.emit()
	check(route.selected_id == target and route.confirm.text == "换路 · 1", "Vertical selection displays its one-point confirmation cost")
	check(game.campaign.state.phase == "route" and game.systems.search_point_count() == 2, "Selection alone does not enter or spend")
	await _capture("route-shift")
	route.confirm.pressed.emit()
	await _wait_transition()
	check(game.campaign.state.phase == "room" and int(game.campaign.state.current_node_id) == target, "Vertical confirmation enters the linked room")
	check(int(game.campaign.state.layer_index) == 1, "Vertical room stays in the same column")
	check(game.systems.search_point_count() == 1, "Confirmed lane change spends exactly one point")
	game._enter_node(target)
	check(game.systems.search_point_count() == 1, "Repeated confirmation cannot charge twice")
	var saved: Dictionary = game.save_store.load_profile()
	check(game.profile.restore(saved), "Paid lane change profile restores from disk")
	check(game.campaign.restore(saved.run.route), "Paid lane change route restores from disk")
	game._load_room(true)
	await _wait_transition()
	check(int(game.campaign.state.current_node_id) == target and int(game.campaign.state.layer_index) == 1, "Resume loads the same vertical room and column")
	check(game.systems.search_point_count() == 1, "Resume preserves the paid resource balance")
	_complete_route_room()
	check(game.campaign.state.layers[1].completed_ids.size() == 2, "Both lateral rooms remain completed")
	check(game.campaign.vertical_choices().is_empty(), "Completed lateral rooms cannot be revisited")
	game._route()
	check(game.campaign.state.phase == "route" and int(game.campaign.state.layer_index) == 2, "Lateral completion returns to forward route selection")

func _complete_route_room() -> void:
	if game.campaign.current_room().combat:
		while not game.campaign.room_ready(): game.campaign.clear_wave()
	else: game.campaign.resolve_action()
	check(game.campaign.complete_room().success, "Integration fixture completes its current room")
	check(game.campaign.advance().success, "Integration fixture advances to route selection")

func _wait_transition() -> void:
	while game._transitioning:
		await process_frame

func _capture(name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var path = "res://reports/" + name + ".png"
	canvas.get_texture().get_image().save_png(path)
	captures.append(path)
