extends SceneTree

const StateBar = preload("res://scripts/presentation/health_state_bar.gd")
const BAR_SIZE := Vector2(479.1588, 35.9008)

var failures: Array[String] = []
var checks := 0
var samples: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _viewport() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(560, 100)
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	return viewport

func _bar(viewport: SubViewport):
	var bar = StateBar.new()
	viewport.add_child(bar)
	bar.configure("boss", "HpStateBar")
	bar.position = Vector2(40, 30)
	bar.size = BAR_SIZE
	return bar

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Boss health bounds require a graphical renderer")
		quit(1)
		return
	var filled_view := _viewport()
	var empty_view := _viewport()
	var filled = _bar(filled_view)
	var empty = _bar(empty_view)
	empty.update_health(0, 100, 0)
	for current in [100.0, 99.0, 50.0, 1.0, 0.2, 0.0]:
		for elapsed in [0.0, 1.0 / 120.0, 1.0 / 30.0]:
			filled.reset()
			filled.update_health(100, 100, 0)
			filled.update_health(current, 100, elapsed)
			empty.scale = filled.scale
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var image := filled_view.get_texture().get_image()
			var reference := empty_view.get_texture().get_image()
			var overflow := 0
			var colored := 0
			for y in image.get_height():
				for x in image.get_width():
					var color := image.get_pixel(x, y)
					if color.a < 0.1 or color.r < 0.35 or color.r < color.b * 1.8: continue
					colored += 1
					var inside := false
					for row in range(maxi(0, y - 1), mini(image.get_height(), y + 2)):
						for column in range(maxi(0, x - 1), mini(image.get_width(), x + 2)):
							inside = inside or reference.get_pixel(column, row).a > 0.08
					if not inside: overflow += 1
			var label := "HP %.1f at %.5fs" % [current, elapsed]
			if current == 100.0:
				var center := image.get_pixel(280, 48)
				check(center.a > 0.99 and center.r > 0.7, "Source stencil preserves opaque red fill")
			check(colored > 200, label + " keeps visible HP or damage trail")
			check(overflow == 0, label + " keeps all colored fill inside the source silhouette")
			samples.append({"health": current, "elapsed": elapsed, "scale": filled.scale.x, "colored_pixels": colored, "overflow_pixels": overflow})
			if current == 100.0 or current == 1.0:
				image.save_png("res://reports/boss-health-bounds-%.0f-%.5f.png" % [current, elapsed])
	filled_view.queue_free()
	empty_view.queue_free()
	await process_frame
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "samples": samples}
	FileAccess.open("res://reports/boss-health-bounds-test.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("BOSS_HEALTH_BOUNDS ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
