extends SceneTree

var failures: Array[String] = []
var game: Node

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)

func sweep(start: Vector3, motion: Vector3, label: String) -> void:
	var player = game.world.player
	player.position = start
	var hit := KinematicCollision3D.new()
	check(player.test_move(player.global_transform, motion, hit), label)
	if hit.get_collision_count() > 0:
		check(hit.get_travel().length() < motion.length(), label + " stops before the far side")

func _run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.save_store = DungeonSaveStore.new("/private/tmp/camp-boundary-%d.json" % Time.get_ticks_usec())
	root.add_child(game)
	await process_frame
	game.set_process(false)
	game.world.set_physics_process(false)
	await physics_frame
	await process_frame
	for x in [28.85, 30.5]:
		sweep(Vector3(x, 0.05, 81.5), Vector3(0, 0, 5), "Portal rear blocks walk/dash at x=%s" % x)
	for direction in [-1.0, 1.0]:
		sweep(Vector3(28.85 if direction < 0 else 30.5, 0.05, 82.5), Vector3(direction * 3, 0, 4), "Portal rear corner blocks diagonal movement %s" % direction)
	for x in [26.0, 27.7, 31.6, 33.0]:
		sweep(Vector3(x, 0.05, 68.0), Vector3(0, 0, 6), "Riverbank blocks crossing at x=%s" % x)
	var bank = game.world.environment_root.get_node("Collider_65000000000011932")
	check(bank.position.distance_to(Vector3(35.35, 0, 68.74)) < 0.001, "Riverbank wall uses the supplied APK position")
	var bank_normal := Vector3(0.860919, 0, 0.508743).normalized()
	for offset in [-2.2, 0.0, 2.2]:
		var bank_point: Vector3 = bank.position + Vector3(-bank_normal.z, 0, bank_normal.x) * offset
		sweep(bank_point + bank_normal * 1.5 + Vector3.UP * 0.05, -bank_normal * 3.0, "Updated riverbank blocks movement at offset=%s" % offset)
	for z in [71.0, 77.0, 82.0]:
		for direction in [-1.0, 1.0]:
			sweep(Vector3(29.65, 0.05, z), Vector3(direction * 5, 0, 0), "Bridge side blocks crossing at z=%s direction=%s" % [z, direction])
	var player = game.world.player
	for speed in [5.0, 60.0]:
		for direction in [-0.3, 0.0, 0.3]:
			player.position = Vector3(28.85, 0.05, 81.0)
			for frame in 30:
				await physics_frame
				player.velocity = Vector3(direction, 0, 1).normalized() * speed
				player.move_and_slide()
			check(player.position.z < 82.85 and player.position.x > 28.5 and player.position.x < 30.8, "Repeated movement stays inside bridge: speed=%s direction=%s position=%s" % [speed, direction, player.position])
	player.position = Vector3(29.65, 0.05, 79.0)
	check(not player.test_move(player.global_transform, Vector3(0, 0, 2.0)), "Bridge approach remains open")
	var portals: Array = game.world.interactions._items.values().filter(func(item): return str(item.data.get("UIBtnName", "")).ends_with("StartNewRun"))
	check(portals.size() == 1, "Departure portal identity resolves")
	if not portals.is_empty():
		check(game.world.interactions.can_interact_at(str(portals[0].id), Vector3(29.65, 0.05, 81.0)), "Portal remains interactable before the rear boundary")
	game.hud.update_combat(player.combat, true)
	check(not game.hud.camp_button.visible and not game.hud.title_label.visible, "Camp badge and title stay hidden")
	game.hud._set_navigation_visible(true)
	check(not game.hud.camp_button.visible, "Closing a menu does not restore the camp badge")
	print("CAMP BOUNDARY: failures=", failures)
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
