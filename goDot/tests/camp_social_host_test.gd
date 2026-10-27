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
	root.add_child(canvas)
	var game = load("res://scripts/main.gd").new()
	game.save_store = DungeonSaveStore.new("/private/tmp/camp-social-host-%d.json" % Time.get_ticks_usec())
	canvas.add_child(game)
	game.set_process(false)
	game.world.set_physics_process(false)
	game.audio.stop()
	game.profile.data.buildings["2"] = 3
	game.systems.set_record("talk:100201", 1)
	game.systems.grant_material(106, 2)
	game._action("op:give_npc_gift", 1000, 0)
	check(game.hud.page._layout == "dialogue" and not game.profile.data.dialogue_state.is_empty(), "resident list gift enters source story")
	check(game.systems.material(106) == 2 and game.systems.stat("relationship:1000") == 0, "story entry does not commit gift")
	game._close_page()
	check(game.systems.material(106) == 2, "cancelling story preserves apple")
	game._action("op:give_npc_gift", 1000, 0)
	game._skip_dialogue()
	check(game.systems.material(106) == 1 and game.systems.stat("relationship:1000") == 1, "completing source story commits one gift")
	game._next_dialogue()
	check(game.systems.material(106) == 1, "extra taps do not repeat gift")
	game._close_page()
	game.systems.begin_run(81818, 1, 100)
	game._room_key = "81818:1:100"
	var context := {"config_id": "70003", "marker_id": "apple-source-1", "position": Vector3.ZERO}
	game._claim_destroyable(context)
	game._claim_destroyable(context)
	check(game.systems.material(106) == 2, "golden apple immediately enters stable wallet exactly once")
	check(int(game.profile.data.run.counters.get("EatGoldAppleCount", 0)) == 1, "golden apple run total exactly once")
	check(game.world.ground_loot.entries.is_empty(), "golden apple does not spawn a physical pickup")
	game._finish_run(false, "retreat")
	game._finish_run(false, "retreat")
	check(game.systems.history.records().size() == 1, "terminal host calls append one record")
	check(game.systems.history.detail(1).reason == "retreat", "history retains terminal reason")
	check(game.systems.material(106) == 2, "settlement does not regrant golden apple")
	game._result_next()
	check(game.systems.material(106) == 2, "reward presentation does not regrant golden apple")
	game.profile.data.run.erase("outcome")
	game._camp()
	game._show_history_record(1)
	check(game.hud.page._layout == "outcome" and game.hud.page.page_context.action == "page:history", "history reuses settlement read-only view")
	game._action("page:history", 0, 0)
	check(game.menus.current_page == "history" and game.systems.material(106) == 2, "archive return preserves wallet")
	var restored := DungeonProfile.new()
	check(restored.restore(game.save_store.load_profile()) and restored.data.run_history.size() == 1, "terminal history persisted to save store")
	game.queue_free()
	await process_frame
	canvas.queue_free()
	await process_frame
	var report := {"checks": checks, "failures": failures, "passed": failures.is_empty()}
	FileAccess.open("res://reports/camp-social-host-test.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("CAMP_SOCIAL_HOST_TEST ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
