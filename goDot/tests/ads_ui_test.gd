extends SceneTree

class FakeBridge extends RefCounted:
	var shown := 0
	func configure(_app, _key, _placement): pass
	func load_rewarded(): pass
	func show_rewarded(_id, _scene): shown += 1
	func poll_events(): return "[]"

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	scene.save_store = DungeonSaveStore.new("/private/tmp/city-ads-ui-%d.json" % Time.get_ticks_usec())
	root.add_child(scene)
	await process_frame
	scene.menus.open("mall")
	var skips := 0
	for row in scene.hud.page._rows:
		for button in row.get("buttons", []):
			if button.action == "ad_skip:mall": skips += 1
	assert(skips > 0)
	scene.ads.bridge = FakeBridge.new()
	scene.ads.configuration = {"app_id": "test", "app_key": "test", "rewarded_placement_id": "test"}
	scene._action("ad:mall", 1002, 0)
	assert(scene.ads.busy() and scene.hud.modal_open)
	var escape = InputEventAction.new()
	escape.action = "pause_game"
	escape.pressed = true
	scene._unhandled_input(escape)
	assert(not scene.ads.busy() and scene.hud.modal_open)
	scene.ads.handle_event({"type": "initialized"})
	scene.ads.handle_event({"type": "ready"})
	assert(scene.ads.bridge.shown == 0)
	scene.ads.ad_ready = false
	scene._action("ad:mall", 1002, 0)
	scene.hud.page.closed.emit()
	assert(not scene.ads.busy())
	scene.ads.handle_event({"type": "ready"})
	assert(scene.ads.bridge.shown == 0)
	scene._action("ad:mall", 1002, 0)
	assert(scene.ads.pending.showing and scene.ads.bridge.shown == 1)
	scene.hud.page.closed.emit()
	scene._unhandled_input(escape)
	assert(scene.ads.busy() and scene.hud.modal_open)
	scene.ads.handle_event({"type": "closed", "id": scene.ads.pending.id})
	assert(not scene.ads.busy())
	scene.queue_free()
	await process_frame
	print("ADS UI PASS: free skips without SDK, Escape and close cancel preparation, active playback stays modal")
	quit(0)
