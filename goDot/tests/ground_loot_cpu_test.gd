extends SceneTree

class CountingLoot extends "res://scripts/ground_loot.gd":
	var preference_queries := 0

	func preferred_pickup(_entry: Dictionary, _systems: RefCounted) -> bool:
		preference_queries += 1
		return true

class FakeSystems extends RefCounted:
	var granted := 0

	func add_loot(_id: int) -> Dictionary:
		granted += 1
		return {"success": true}

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _run() -> void:
	var drops := CountingLoot.new()
	root.add_child(drops)
	var visual := Node3D.new()
	drops.add_child(visual)
	drops.entries.append({"id": 1, "amount": 1, "material": false, "position": Vector3(10, 0, 0), "visual": visual, "age": 0.0})
	var systems := FakeSystems.new()
	check(drops.advance_collection(1.1, Vector3.ZERO, systems).is_empty() and drops.preference_queries == 0, "Distant drops do not query pickup preferences")
	check(is_equal_approx(float(drops.entries[0].age), 1.1), "Distant drops still advance their pickup delay")
	check(drops.advance_collection(0.01, Vector3(7.6, 0, 0), systems).is_empty() and drops.preference_queries == 0, "The pickup range remains exclusive at its boundary")
	var collected := drops.advance_collection(0.01, Vector3(7.61, 0, 0), systems)
	check(collected.size() == 1 and drops.preference_queries == 1 and systems.granted == 1, "A nearby eligible drop is still collected exactly once")
	check(drops.entries.is_empty(), "Collected drop leaves the ground")
	print("GROUND_LOOT_CPU ", JSON.stringify({"checks": checks, "failures": failures}))
	drops.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
