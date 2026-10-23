extends SceneTree

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _run() -> void:
	var canvas := SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	var loading = load("res://scripts/presentation/room_loading.gd").new()
	canvas.add_child(loading)
	check(not loading.visible, "Overlay starts hidden")
	loading.begin("幽暗密林 · 精英关卡")
	check(loading.visible and loading.spinner.texture != null, "Loading shows original game art")
	loading.set_progress(0.42)
	loading.set_progress(0.2)
	check(is_equal_approx(loading.progress_bar.value, 42.0), "Progress never moves backwards")
	loading.set_progress(2.0)
	check(is_equal_approx(loading.progress_bar.value, 100.0), "Progress clamps at completion")
	loading.begin("幽暗密林 · 精英关卡")
	loading.set_progress(0.42)
	check(is_equal_approx(loading.progress_bar.value, 42.0), "A new transition resets progress")
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390)]:
		canvas.size = dimensions
		await process_frame
		await process_frame
		check(loading.blocker.size.is_equal_approx(Vector2(dimensions)), "Overlay fills viewport %s" % dimensions)
		check(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(loading.content.get_global_rect()), "Loading content fits viewport %s" % dimensions)
		check(loading.title_label.size.y >= loading.title_label.get_minimum_size().y, "Title fits its container")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var first: Image = canvas.get_texture().get_image()
			first.save_png("/private/tmp/room-loading-%dx%d-a.png" % [dimensions.x, dimensions.y])
			var rotation_before: float = loading.spinner.rotation
			await create_timer(0.35).timeout
			await RenderingServer.frame_post_draw
			var second: Image = canvas.get_texture().get_image()
			second.save_png("/private/tmp/room-loading-%dx%d-b.png" % [dimensions.x, dimensions.y])
			check(loading.spinner.rotation > rotation_before, "Spinner changes between rendered frames")
			check(first.get_data() != second.get_data(), "Rendered animation pixels change")
	var event := InputEventKey.new()
	event.keycode = KEY_ENTER
	event.pressed = true
	canvas.push_input(event, true)
	check(canvas.is_input_handled(), "Loading consumes keyboard input")
	loading.finish()
	check(not loading.visible, "Finish releases overlay")
	canvas.queue_free()
	await process_frame
	print("ROOM_LOADING_TEST ", JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
