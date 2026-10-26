extends SceneTree

const Drops = preload("res://scripts/ground_loot.gd")

class DropWorld extends Node3D:
	var systems: RefCounted
	var environment_root: Node3D

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func near(value: float, expected: float) -> bool:
	return absf(value - expected) < 0.0001

func same_snapshot(actual: Array, expected: Array) -> bool:
	if actual.size() != expected.size(): return false
	for index in actual.size():
		for key in ["id", "amount", "material", "altar"]:
			if actual[index].get(key) != expected[index].get(key): return false
		for component in 3:
			if not near(actual[index].position[component], expected[index].position[component]): return false
		if actual[index].flight.phase != expected[index].flight.phase: return false
		for key in ["age", "jump_height", "attract_age"]:
			if not near(actual[index].flight[key], expected[index].flight[key]): return false
		for key in ["origin", "destination"]:
			for component in 3:
				if not near(actual[index].flight[key][component], expected[index].flight[key][component]): return false
	return true

func _run() -> void:
	var catalog := DungeonCatalog.new()
	check(catalog.load_all(), "Catalog loads")
	var systems := DungeonSystems.new(catalog, DungeonProfile.new())
	systems.begin_run(1061664, 1, 100)
	var world := DropWorld.new()
	world.systems = systems
	root.add_child(world)
	var drops := Drops.new()
	world.add_child(drops)
	drops._flight_random.seed = 401060
	var random_step: int = systems.profile.data.run.random_step
	var origin := Vector3(12, 2, -6)
	var split_cases: Array[Dictionary] = [
		{"id": 101, "amount": 1, "parts": [1]},
		{"id": 101, "amount": 9, "parts": [9]},
		{"id": 101, "amount": 10, "parts": [10]},
		{"id": 101, "amount": 20, "parts": [10, 10]},
		{"id": 101, "amount": 51, "parts": [10, 10, 10, 10, 10, 1]},
		{"id": 101, "amount": 99, "parts": [19, 19, 19, 19, 19, 4]},
		{"id": 102, "amount": 1, "parts": [1]},
		{"id": 102, "amount": 2, "parts": [2]},
		{"id": 102, "amount": 3, "parts": [3]},
		{"id": 102, "amount": 9, "parts": [3, 3, 3]},
		{"id": 102, "amount": 12, "parts": [3, 3, 3, 3]},
		{"id": 102, "amount": 13, "parts": [3, 3, 3, 3, 1]},
	]
	var shortest_throw := INF
	for sample in split_cases:
		drops.clear()
		drops.spawn(sample.id, origin, sample.amount, true)
		var values: Array[int] = []
		var total := 0
		var destinations: Array[Vector3] = []
		for entry in drops.entries:
			values.append(entry.amount)
			total += int(entry.amount)
			check(entry.position == origin and entry.flight.origin == origin, "%d/%d fragments start at the supplied source position" % [sample.id, sample.amount])
			var offset: Vector3 = entry.flight.destination - origin
			var radius := Vector2(offset.x, offset.z).length()
			shortest_throw = minf(shortest_throw, radius)
			check(radius <= 5.0001 and near(offset.y, 0.1), "%d/%d fragment scatter uses source extent and landing height" % [sample.id, sample.amount])
			check(float(entry.flight.jump_height) >= 0.8 and float(entry.flight.jump_height) <= 1.2, "%d/%d fragment uses source jump power range" % [sample.id, sample.amount])
			check(entry.flight.phase == "scatter" and drops.is_automatic(entry), "%d/%d fragment begins with automatic scatter" % [sample.id, sample.amount])
			check(not entry.has("rarity_glow") and entry.trail.size() == 3, "%d/%d currency uses automatic pickup presentation" % [sample.id, sample.amount])
			destinations.append(entry.flight.destination)
		check(values == sample.parts and total == sample.amount, "%d/%d matches APK chunk values without losing a remainder" % [sample.id, sample.amount])
		check(drops.nearest(origin).is_empty(), "%d/%d never claims the manual pickup prompt" % [sample.id, sample.amount])
		if destinations.size() > 1:
			check(not destinations.all(func(point: Vector3) -> bool: return point == destinations[0]), "%d/%d fragments scatter independently" % [sample.id, sample.amount])
		var saved: Array = JSON.parse_string(JSON.stringify(drops.snapshot()))
		var flight_rng_state: int = drops._flight_random.state
		drops.restore(saved)
		check(same_snapshot(drops.snapshot(), saved), "%d/%d restores all flight parameters and values" % [sample.id, sample.amount])
		check(drops._flight_random.state == flight_rng_state, "%d/%d restore does not reroll or resplit source fragments" % [sample.id, sample.amount])
	check(shortest_throw < 2.0, "Projected sphere scatter preserves short horizontal throws")
	check(int(systems.profile.data.run.random_step) == random_step, "Scatter randomness does not advance the gameplay random sequence")

	drops.clear()
	drops.spawn(101, origin, 7, true)
	var entry: Dictionary = drops.entries[0]
	entry.flight.destination = origin + Vector3(4, 0.1, 0)
	entry.flight.jump_height = 1.0
	var far_target := origin + Vector3(1000, 0, 0)
	drops.advance_collection(0.05, far_target, systems)
	check(entry.position.is_equal_approx(origin) and entry.flight.phase == "scatter", "Fresh currency remains at its origin before the 0.1-second animation ticker")
	drops.advance_collection(0.05, far_target, systems)
	check(entry.position.is_equal_approx(origin), "Scatter starts at the delayed animation boundary")
	drops.advance_collection(0.175, far_target, systems)
	check(entry.position.y > origin.y + 0.8 and entry.position.x > origin.x, "First jump visibly rises and travels horizontally")
	drops.advance_collection(0.175, far_target, systems)
	check(entry.position.y < origin.y + 0.15 and entry.position.x > origin.x + 1.5, "First jump returns near the floor before the second jump")
	var halfway: Array = JSON.parse_string(JSON.stringify(drops.snapshot()))
	drops.restore(halfway)
	entry = drops.entries[0]
	check(same_snapshot(drops.snapshot(), halfway), "Saving between jumps restores the current position and timer")
	drops.advance_collection(0.175, far_target, systems)
	check(entry.position.y > origin.y + 0.8 and entry.position.x > origin.x + 2.5, "A restored scatter completes its second jump")
	drops.advance_collection(0.17501, far_target, systems)
	check((entry.position as Vector3).is_equal_approx(entry.flight.destination) and entry.flight.phase == "waiting", "The two jumps land after the source 0.7-second scatter duration")
	drops.advance_collection(0.18999, far_target, systems)
	check(near(entry.age, 0.99) and entry.flight.phase == "waiting" and near(entry.speed, 0), "Landed currency waits before the 1-second follow threshold")
	var landed: Vector3 = entry.position
	var frozen := JSON.stringify(drops.snapshot())
	drops.advance_collection(0, landed, systems)
	check(JSON.stringify(drops.snapshot()) == frozen, "Zero simulation delta freezes flight and grants")
	drops.advance_collection(0.1, landed + Vector3(99.1, 0, 0), systems)
	check(entry.flight.phase == "waiting" and entry.position == landed, "Currency outside the source 99-unit range waits after the delay")
	drops.advance_collection(0.1, landed + Vector3(99, 0, 0), systems)
	check(entry.flight.phase == "attract" and near(entry.speed, 4.0), "Range boundary starts following with source acceleration")
	check(near((entry.position as Vector3).distance_to(landed), 0.4), "First follow step advances by its current speed and elapsed time")
	var following_position: Vector3 = entry.position
	drops.advance_collection(0.1, landed + Vector3(300, 0, 0), systems)
	check(entry.flight.phase == "attract" and near(entry.speed, 7.0), "Following stays latched when the player leaves the activation range")
	check(near((entry.position as Vector3).distance_to(following_position), 0.7), "Latched pickup continues accelerating toward the moving player")
	var following: Array = JSON.parse_string(JSON.stringify(drops.snapshot()))
	drops.restore(following)
	entry = drops.entries[0]
	check(entry.flight.phase == "attract" and near(entry.speed, 7.0) and near(entry.flight.attract_age, 0.2), "An attracted pickup resumes saved acceleration without replaying scatter")
	entry.flight.attract_age = 4.9
	drops.advance_collection(0.2, far_target, systems)
	check(near(entry.speed, 151.0), "Source acceleration caps at 151 units per second after five seconds")

	drops.clear()
	drops.spawn(102, Vector3.ZERO, 2, true, false)
	entry = drops.entries[0]
	entry.age = 0.5
	drops.advance_collection(0.5, Vector3(10, 0, 0), systems)
	check(entry.flight.phase == "waiting", "Follow activation requires strictly more than one second")
	drops.advance_collection(0.01, Vector3(10, 0, 0), systems)
	check(entry.flight.phase == "attract" and near(entry.speed, 1.3), "A positive tick beyond the source delay activates following")

	drops.clear()
	var magic_before := systems.material(102)
	drops.spawn(102, Vector3.ZERO, 2, true, false)
	entry = drops.entries[0]
	entry.flight.phase = "attract"
	check(drops.advance_collection(0.2, Vector3(0.6, 0, 0), systems).is_empty() and systems.material(102) == magic_before, "Pickup checks arrival before moving and does not grant mid-step")
	check((entry.position as Vector3).is_equal_approx(Vector3(0.6, 0, 0)), "Clamped follow movement prevents frame-rate overshoot")
	var result: Array[Dictionary] = drops.advance_collection(0.01, Vector3(0.6, 0, 0), systems)
	check(result.size() == 1 and int(result[0].amount) == 2 and drops.entries.is_empty(), "Next tick collects the arrived shop orb exactly once")
	check(systems.material(102) == magic_before + 2 and drops.advance_collection(1.0, Vector3.ZERO, systems).is_empty(), "Collected currency cannot grant twice")

	var gold_before := systems.material(101)
	drops.restore([{"id": 101, "amount": 99, "material": true, "position": [0, 0, 0]}])
	check(drops.entries.size() == 1 and drops.entries[0].amount == 99 and drops.entries[0].flight.phase == "waiting", "Legacy ground saves retain one existing object without replaying or resplitting it")
	drops.advance_collection(0.01, Vector3.ZERO, systems)
	check(systems.material(101) == gold_before + 99 and drops.entries.is_empty(), "Legacy currency resumes pickup with its full original value")

	gold_before = systems.material(101)
	magic_before = systems.material(102)
	drops.spawn(101, origin, 51, true)
	drops.spawn(102, origin, 13, true)
	drops.spawn(103, origin, 4, true)
	drops.spawn(20105, origin)
	check(drops.entries.size() == 13 and not drops.is_automatic(drops.entries[-1]) and not drops.is_automatic(drops.entries[-2]), "Only gold and shop orbs use automatic scatter; minerals and relics stay manual")
	check(drops.settle_automatic(systems) == 64 and drops.entries.size() == 2, "Room transition settles every gold and orb fragment while retaining manual drops")
	check(systems.material(101) == gold_before + 51 and systems.material(102) == magic_before + 13, "Room settlement preserves separate source resource totals")
	check(drops.settle_automatic(systems) == 0 and drops.entries.size() == 2, "Repeated transition settlement cannot duplicate currency")
	check(drops.nearest(origin).id == 103, "Manual mineral prompt remains available beside automatic currency")
	check(int(systems.profile.data.run.random_step) == random_step, "Complete scatter, attraction, restore, and settlement leave gameplay randomness unchanged")

	drops.clear()
	world.queue_free()
	await process_frame
	var report := {"checks": checks, "passed": failures.is_empty(), "failures": failures}
	var output := FileAccess.open("res://reports/currency-flight-rules-tests.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t") + "\n")
	output.close()
	print("CURRENCY_FLIGHT_RULES_TEST ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
