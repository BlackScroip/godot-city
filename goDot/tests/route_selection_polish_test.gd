extends SceneTree

var checks := 0
var failures: Array[String] = []
var captures: Array[String] = []
var canvas: SubViewport
var background: TextureRect

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _run() -> void:
	Engine.max_fps = 60
	create_timer(90).timeout.connect(func(): quit(2))
	canvas = SubViewport.new()
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var display = TextureRect.new()
	display.texture = canvas.get_texture()
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(display)
	background = TextureRect.new()
	background.texture = DungeonStyle.texture("res://assets/ui/route/world_background_1.png")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	canvas.add_child(background)
	for dimensions in [Vector2i(2460, 1080), Vector2i(1600, 900), Vector2i(844, 390), Vector2i(640, 900)]:
		for scope in ["world", "rooms"]:
			await _check_page(scope, dimensions)
	await _check_reference_world()
	canvas.queue_free()
	display.queue_free()
	await process_frame
	var report = {"checks": checks, "passed": failures.is_empty(), "failures": failures, "captures": captures}
	FileAccess.open("res://reports/route-selection-polish-test.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("ROUTE_SELECTION_POLISH ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func _rows(scope: String) -> Array:
	var result: Array = []
	var first = 1 if scope == "world" else 0
	for column in 10:
		for lane in 3:
			var id = column * 3 + lane + 1
			var layer = first + column
			var locked = scope == "world" and column == 3 and lane == 0
			var row = {"node_id": id, "config_id": layer * 100000000 + id,
				"layer_index": layer, "lane": lane, "lane_count": 3, "map_mode": scope,
				"available": not locked, "selectable": true, "locked": locked,
				"name": "Forest" if scope == "world" else "Battle", "world_icon": "森林图标",
				"flow": "Boss" if column == 9 else "Battle", "parents": [], "vertical_neighbors": [],
				"is_anchor": column == 0 and lane == 1, "lock_reason": "Requires difficulty 10" if locked else ""}
			if column > 0:
				row.parents.append((layer - 1) * 100000000 + id - 3)
				if lane < 2: row.parents.append((layer - 1) * 100000000 + id - 2)
			if scope == "rooms" and lane < 2: row.vertical_neighbors.append(id + 1)
			if scope == "rooms" and lane == 1: row["NodeIncrementData"] = {"70002": 1}
			result.append(row)
	return result

func _check_page(scope: String, dimensions: Vector2i) -> void:
	canvas.size = dimensions
	background.size = Vector2(dimensions)
	var page = DungeonRoutePage.new()
	page.theme = DungeonStyle.theme()
	canvas.add_child(page)
	page.size = Vector2(dimensions)
	page.configure(_rows(scope), {"map_scope": scope, "first_layer": 1 if scope == "world" else 0,
		"current_layer": 1, "portrait": "sprite_cardicon_square_jiannan", "magic": 60, "search": 2})
	var emitted: Array = []
	page.command.connect(func(kind, id, extra): emitted.append([kind, id, extra]))
	await create_timer(0.85).timeout
	var label = "%s at %s" % [scope, dimensions]
	check(page.selected_index == -1 and not page.confirm.visible, "Opening waits for selection: " + label)
	for index in [0, 16, 29]:
		var node = page.nodes[index]
		_partially_clip(page, node, index != 29)
		await process_frame
		check(not _viewport_rect(page).encloses(_global_selection_bounds(node)), "Fixture starts with a clipped candidate: %s node %d" % [label, index])
		page._select(int(node.room.node_id), int(node.room.layer_index))
		await create_timer(0.36).timeout
		check(node.chosen and page.selected_index == index, "Selecting the clipped candidate changes selection: %s node %d" % [label, index])
		_assert_visible(page, node, "Selected peak is visible: %s node %d" % [label, index])
		if scope == "rooms": _assert_arrows_clear(page, node, label)
		_assert_chrome(page, label)
	var selected = page.nodes[29]
	var layout = selected.get_rect()
	var narrowest := INF
	var widest := 0.0
	for sample in 16:
		await create_timer(0.04).timeout
		narrowest = minf(narrowest, selected._selection_scale)
		widest = maxf(widest, selected._selection_scale)
		check(selected._selection_scale >= 0.999 and selected._selection_scale <= DungeonRouteNode.SELECTION_PEAK_SCALE + 0.001,
			"Selection animation remains within its reserved bounds: " + label)
		check(selected.get_rect() == layout and selected.scale == Vector2.ONE, "Selection animation preserves input geometry: " + label)
	check(widest - narrowest > 0.003, "Selected frame visibly animates: " + label)
	if scope == "rooms":
		var animated_scale = selected._selection_scale
		selected._selection_scale = 1.0
		var outline: Rect2 = selected._selection_outline_rect()
		var inner: Rect2 = selected._room_rect()
		check(outline.position.distance_to(inner.position) < 1.0 and outline.end.distance_to(inner.end) < 1.0,
			"Contracted selection stroke aligns with the room border: " + label)
		selected._selection_scale = animated_scale
	await _capture(scope, dimensions)
	if scope == "rooms" and dimensions == Vector2i(1600, 900): await _check_boss_pixels(selected)
	var focused = page.nodes[16]
	_partially_clip(page, focused, true)
	await process_frame
	focused.grab_focus()
	await create_timer(0.36).timeout
	_assert_visible(page, focused, "Focused peak is visible: " + label)
	check(page.selected_index == 29 and selected.chosen and not focused.chosen, "Keyboard focus does not confirm or select another node: " + label)
	page._select(int(focused.room.node_id), int(focused.room.layer_index))
	await create_timer(0.03).timeout
	page._select(int(selected.room.node_id), int(selected.room.layer_index))
	await create_timer(0.03).timeout
	page._select(int(focused.room.node_id), int(focused.room.layer_index))
	await create_timer(0.36).timeout
	check(page.nodes.filter(func(node): return node.chosen).size() == 1 and focused.chosen, "Fast switching leaves exactly one selected frame: " + label)
	check(is_equal_approx(selected._selection_scale, 1.0), "Previous selected node stops its animation: " + label)
	var resized = Vector2i(maxi(480, dimensions.x - 97), dimensions.y)
	canvas.size = resized
	background.size = Vector2(resized)
	page.size = Vector2(resized)
	await create_timer(0.36).timeout
	_assert_visible(page, focused, "Selected peak remains visible after resize: " + label)
	check(page.get_rect().grow(1).encloses(page.header.get_rect()) and page.get_rect().grow(1).encloses(page.footer.get_rect()),
		"Header and controls remain inside the resized viewport: " + label)
	if scope == "world":
		var locked = page.nodes[9]
		page._select(int(locked.room.node_id), int(locked.room.layer_index))
		await create_timer(0.36).timeout
		_assert_visible(page, locked, "Locked selected frame remains visible: " + label)
		check(locked.chosen and page.confirm.disabled, "Locked world region keeps its selection with entry disabled: " + label)
		page._confirm()
		check(emitted.is_empty(), "Locked region never dispatches entry: " + label)
	var destination = page.nodes[16]
	page._select(int(destination.room.node_id), int(destination.room.layer_index))
	var duration = page.play_departure(int(destination.room.node_id), int(destination.room.layer_index))
	check(is_equal_approx(duration, 1.0), "Confirmed travel retains the recovered one-second duration: " + label)
	check(is_instance_valid(page._departing_portrait) and page._departing_portrait.texture != null, "Travel displays the actual character portrait: " + label)
	var start = page._departing_portrait.position
	await create_timer(0.4).timeout
	check(page._departing_portrait.position.distance_to(start) > 1, "Character visibly travels toward its destination: " + label)
	check(page.play_departure(int(destination.room.node_id), int(destination.room.layer_index)) == 0.0, "Repeated confirmation cannot restart travel: " + label)
	page._select(int(page.nodes[0].room.node_id), int(page.nodes[0].room.layer_index))
	check(page.nodes[16].chosen and page.back_button.disabled and page.map_switch.disabled, "Travel locks route changes until transition: " + label)
	await create_timer(0.7).timeout
	var center: Vector2 = destination._world_frame_rect().get_center() if scope == "world" else destination.size * 0.5
	check(page._departing_portrait.get_rect().get_center().distance_to(destination.position + center) < 1, "Travel finishes at the selected node center: " + label)
	page.queue_free()
	await process_frame

func _partially_clip(page: DungeonRoutePage, node: DungeonRouteNode, left: bool) -> void:
	node.release_focus()
	var center = node.get_rect().get_center().x
	var maximum = maxf(0, page.graph.size.x - page.scroll.size.x)
	var target = center if left else center - page.scroll.size.x
	if target < 0 or target > maximum:
		target = center - page.scroll.size.x if left else center
	page.scroll.scroll_horizontal = roundi(target)

func _viewport_rect(page: DungeonRoutePage) -> Rect2:
	var result = page.scroll.get_global_rect()
	var bar = page.scroll.get_h_scroll_bar()
	if bar.visible: result.size.y -= bar.size.y
	return result.grow(1.0)

func _global_selection_bounds(node: DungeonRouteNode) -> Rect2:
	var bounds: Rect2 = node.selection_bounds(true)
	bounds.position += node.global_position
	return bounds

func _assert_visible(page: DungeonRoutePage, node: DungeonRouteNode, message: String) -> void:
	var bounds: Rect2 = node.selection_bounds(true)
	bounds.position += node.position
	check(Rect2(Vector2.ZERO, page.graph.size).grow(1.0).encloses(bounds), message + " (scroll content)")
	check(_viewport_rect(page).encloses(_global_selection_bounds(node)), message + " (visible viewport)")

func _assert_arrows_clear(page: DungeonRoutePage, selected: DungeonRouteNode, label: String) -> void:
	var bounds: Rect2 = selected.selection_bounds(true)
	bounds.position += selected.position
	var selected_polygon = _rect_polygon(bounds.grow(-0.5))
	for edge in page.edges:
		if edge.from != selected and edge.to != selected: continue
		if edge.vertical:
			var areas = page._vertical_path_rects(edge)
			check(areas.size() == 2, "Both vertical arrows remain visible beside an expanded frame: " + label)
			for area in areas:
				check(area.size.y >= 14.0, "Vertical arrows retain a readable size: " + label)
				check(not bounds.grow(-0.5).intersects(area), "Expanded frame clears both vertical arrows: " + label)
		else:
			var path = page._path_geometry(edge)
			var polygon = _rect_polygon(Rect2(Vector2.ZERO, path.draw_size))
			for index in polygon.size():
				polygon[index] = path.draw_position + (polygon[index] * path.draw_scale).rotated(path.draw_rotation)
			check(Geometry2D.intersect_polygons(selected_polygon, polygon).is_empty(), "Expanded frame clears each forward arrow: " + label)

func _rect_polygon(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])

func _assert_chrome(page: DungeonRoutePage, label: String) -> void:
	for bar in page.resource_counters.get_children():
		var icon = bar.get_node("Icon") as TextureRect
		check(icon.texture != null and icon.size.x >= 24 and icon.size.y >= 24, "Resource icon is initialized and readable: " + label)
		check(icon.texture is AtlasTexture and icon.texture.atlas != null, "Resource counter uses the recovered icon with transparent padding removed: " + label)
		check(not icon.get_rect().intersects(bar.get_node("Amount").get_rect()), "Resource icon does not cover its amount: " + label)
	check(page.get_global_rect().grow(1).encloses(page.selection_info.get_global_rect()), "Selected title remains inside viewport: " + label)
	check(page.selection_info.get_global_rect().end.y <= page.scroll.position.y + 1, "Selected title never overlaps graph: " + label)
	if page.size.x >= 800:
		check(absf(page.confirm.global_position.x + page.confirm.size.x * 0.5 - page.size.x * 0.5) < 2, "Confirm button is centered independently of checkbox: " + label)

func _check_boss_pixels(node: DungeonRouteNode) -> void:
	check(is_instance_valid(node.boss_effect) and node.boss_effect.visible, "Reachable boss uses recovered red effect layers")
	if DisplayServer.get_name() == "headless" or not is_instance_valid(node.boss_effect): return
	if node._selection_tween: node._selection_tween.kill()
	node._selection_scale = 1.0
	var material: ShaderMaterial = node.boss_effect.effect_material
	material.set_shader_parameter("preview_time", 0.0)
	await process_frame
	await RenderingServer.frame_post_draw
	var first = canvas.get_texture().get_image()
	material.set_shader_parameter("preview_time", 8.0)
	await process_frame
	await RenderingServer.frame_post_draw
	var second = canvas.get_texture().get_image()
	node.boss_effect.intensity = 0.0
	await process_frame
	await RenderingServer.frame_post_draw
	var without = canvas.get_texture().get_image()
	var area = Rect2i(node.boss_effect.get_global_rect()).intersection(Rect2i(Vector2i.ZERO, canvas.size))
	var red_pixels := 0
	var moving_pixels := 0
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var a = first.get_pixel(x, y)
			var b = second.get_pixel(x, y)
			var plain = without.get_pixel(x, y)
			if a.r - plain.r > 0.02: red_pixels += 1
			if absf(a.r - b.r) > 0.02: moving_pixels += 1
	check(red_pixels > 20, "Boss glow produces visible red pixels")
	check(moving_pixels > 20, "Boss flow changes rendered pixels over time")
	node.boss_effect.intensity = 1.0
	material.set_shader_parameter("preview_time", -1.0)
	node._animate_selection()

func _check_reference_world() -> void:
	var campaign = DungeonCampaign.new()
	check(campaign.configure() and campaign.generate(12345, 0).success, "Reference world uses actual campaign data")
	for dimensions in [Vector2i(2460, 1080), Vector2i(844, 390)]:
		canvas.size = dimensions
		background.size = Vector2(dimensions)
		var page = DungeonRoutePage.new()
		page.theme = DungeonStyle.theme()
		canvas.add_child(page)
		page.size = Vector2(dimensions)
		page.configure(campaign.region_map(), {"map_scope": "world", "first_layer": 1, "current_layer": 1,
			"portrait": "sprite_cardicon_square_jiannan", "character": "迷宫入口", "magic": 60, "search": 2})
		await create_timer(0.9).timeout
		page._select(2, 1)
		await create_timer(0.5).timeout
		_assert_visible(page, page.nodes[page.selected_index], "Actual forest highlight remains fully visible")
		_assert_chrome(page, "Actual campaign world")
		await _capture("world-reference", dimensions)
		page.queue_free()
		await process_frame

func _capture(scope: String, dimensions: Vector2i) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var path = "res://reports/route-selection-polish-%s-%dx%d.png" % [scope, dimensions.x, dimensions.y]
	canvas.get_texture().get_image().save_png(path)
	captures.append(path)
