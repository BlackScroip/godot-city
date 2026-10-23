extends SceneTree

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _run() -> void:
	var canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	root.add_child(canvas)
	var game = load("res://scenes/main.tscn").instantiate()
	game.save_store = DungeonSaveStore.new("/private/tmp/pickup-input-test-%d.json" % Time.get_ticks_usec())
	canvas.add_child(game)
	await process_frame
	game.set_process(false)
	game.world.set_physics_process(false)
	game.hud.close_page()
	game.systems.begin_run(51943, game.selected_character, 100, 0)
	game.campaign.state["phase"] = "combat"
	var drops = game.world.ground_loot
	var point = game.world.player.position
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390)]:
		canvas.size = dimensions
		await process_frame
		drops.clear()
		drops.spawn(20103, point + Vector3(1, 0, 0))
		game._process(0.016)
		await process_frame
		var before = int(game.profile.data.run.inventory.get("20103", 0))
		var click = game.hud.primary.get_global_rect().get_center()
		var motion = InputEventMouseMotion.new()
		motion.position = click
		canvas.push_input(motion, true)
		var press = InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.position = click
		press.pressed = true
		canvas.push_input(press, true)
		# A physical click is held across HUD updates, unlike emitting pressed.
		for frame in 4:
			game._process(0.016)
			await process_frame
		var release = InputEventMouseButton.new()
		release.button_index = MOUSE_BUTTON_LEFT
		release.position = click
		release.pressed = false
		canvas.push_input(release, true)
		await process_frame
		check(drops.entries.is_empty(), "Mouse click picks up ground item at %s" % dimensions)
		check(int(game.profile.data.run.inventory.get("20103", 0)) == before + 1, "GUI click grants exactly one item")
	drops.clear()
	var gold_before = game.systems.material(101)
	drops.spawn(101, point + Vector3(5, 0, 0), 12, true)
	check(drops.nearest(point + Vector3(5, 0, 0)).is_empty(), "Automatic coins never occupy manual pickup prompt")
	check(game.systems.material(101) == gold_before, "Coins wait for attraction arrival")
	var origin: Vector3 = drops.entries[0].position
	for frame in 15: drops.advance_collection(1.0 / 60.0, point, game.systems)
	check(drops.entries.size() == 1 and drops.entries[0].position.distance_to(point) < origin.distance_to(point), "Coin moves visibly toward player")
	check(drops.entries[0].trail.size() == 3, "Attraction has visible trail")
	var saved = JSON.parse_string(JSON.stringify(drops.snapshot()))
	drops.restore(saved)
	var arrived := 0
	for frame in 120: arrived += drops.advance_collection(1.0 / 60.0, point + Vector3(1, 0, 0), game.systems).size()
	check(arrived == 1 and drops.entries.is_empty(), "Restored in-flight coin follows moving target and arrives once")
	check(game.systems.material(101) == gold_before + 12, "Automatic coin grants exact amount once")
	drops.spawn(20103, point)
	for frame in 120: drops.advance_collection(1.0 / 60.0, point, game.systems)
	check(drops.entries.size() == 1, "Relics remain manual pickups")
	drops.spawn(101, point + Vector3(20, 0, 0), 7, true)
	check(drops.settle_automatic(game.systems) == 7, "Transition settles coins still flying")
	check(drops.settle_automatic(game.systems) == 0 and drops.entries.size() == 1, "Transition settlement is idempotent and leaves manual items")
	check(game.systems.material(101) == gold_before + 19, "Transition coin grant is exact")
	print("PICKUP_INPUT_TEST ", JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
