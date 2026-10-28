extends SceneTree

const BANNER = preload("res://scripts/presentation/battle_complete.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr(message)

func _run() -> void:
	for sample in [[0.0, "00:00.00"], [59.999, "00:59.99"], [60.0, "01:00.00"], [3600.0, "60:00.00"], [-1.0, "00:00.00"], [INF, "00:00.00"], [NAN, "00:00.00"]]:
		check(BANNER.format_time(sample[0]) == sample[1], "Completion time formats without rounding into the next minute")
	var canvas := SubViewport.new()
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	canvas.size = Vector2i(1600, 900)
	root.add_child(canvas)
	var banner = BANNER.new()
	banner.theme = DungeonStyle.theme()
	canvas.add_child(banner)
	banner.present("room:1", 73.456)
	banner.set_process(false)
	check(banner.visible and banner.clock.text.ends_with("01:13.45"), "Completed room shows its frozen elapsed time")
	check(banner.clock.modulate.a == 0, "Time waits for the APK victory-title lead-in")
	banner.advance(1.799)
	check(banner.clock.modulate.a == 0, "Time is not shown before the native 1.8 second delay")
	banner.advance(0.002)
	check(banner.clock.modulate.a == 1, "Time appears after the native 1.8 second delay")
	banner.present("room:1", 120)
	check(is_equal_approx(banner.battle_seconds, 73.456), "Repeated completion cannot replace or restart the displayed result")
	for dimensions in [Vector2i(2460, 1080), Vector2i(1600, 900), Vector2i(844, 390)]:
		canvas.size = dimensions
		banner.size = Vector2(dimensions)
		for frame in 3: await process_frame
		var bounds := Rect2(Vector2.ZERO, Vector2(dimensions))
		check(bounds.encloses(banner.banner.get_global_rect()), "Completion banner fits %s" % dimensions)
		check(not banner.title.get_global_rect().intersects(banner.clock.get_global_rect()), "Title and time do not overlap")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			canvas.get_texture().get_image().save_png("/private/tmp/battle-complete-%dx%d.png" % [dimensions.x, dimensions.y])
	banner.advance(2.1)
	check(banner.visible and banner.modulate.a < 1, "Completion fades out without advancing the frozen battle clock")
	banner.advance(1.0)
	check(not banner.visible, "Completion dismisses automatically")
	banner.present("room:2", 90)
	banner.clear()
	check(not banner.visible and banner.room_key.is_empty(), "Room change clears prior completion")
	var hud := DungeonHud.new()
	root.add_child(hud)
	hud.apply_settings({"show_timer": false})
	hud.battle_complete.present("boss:1", 23.5)
	check(hud.battle_complete.visible and not hud.room_timer.visible, "Completion time remains available when the running timer setting is disabled")
	hud.show_page("结算", [], "list", {})
	check(not hud.battle_complete.visible, "Modal pages dismiss completion banner")
	hud.queue_free()
	canvas.queue_free()
	await process_frame
	print("BATTLE_COMPLETE_TEST ", JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
