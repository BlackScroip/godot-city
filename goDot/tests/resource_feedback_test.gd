extends SceneTree

const INTERACTIONS = preload("res://scripts/world_interactions.gd")
const EFFECTS = preload("res://scripts/presentation/environment_effects.gd")
const LOOT = preload("res://scripts/ground_loot.gd")
class TestSystems extends RefCounted:
	var material_total := 0
	func grant_material(_id: int, amount: int) -> void: material_total += amount
	func material_name(_id: int) -> String: return "Mineral"
	func add_loot(_id: int) -> Dictionary: return {"success": true}
class TestWorld extends Node3D:
	var low_effects := false
	var paused := false
	var _background := false
	var hud: Node
	var player: Node3D
	var environment_root: Node3D
	var interactions: RefCounted
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _run() -> void:
	var world := TestWorld.new()
	root.add_child(world)
	world.environment_root = Node3D.new()
	world.add_child(world.environment_root)
	world.player = Node3D.new()
	world.add_child(world.player)
	world.interactions = INTERACTIONS.new()
	var markers: Array = []
	for quality in ["Normal", "Unusual", "Luxury", "Curse", "Unknown", "Protect"]:
		var visual := Node3D.new()
		visual.name = quality
		world.environment_root.add_child(visual)
		if quality == "Protect":
			for name in ["Container_UnActive", "Container_Active", "Container_Destory"]:
				var container := Node3D.new()
				container.name = name
				visual.add_child(container)
		markers.append({"SceneName": "Feedback", "SourceGameObjectId": quality, "Type": "EEUT_ProtectTarget" if quality == "Protect" else "EEUT_AbilityItemTreasureBox", "Path": [quality], "exported_node_name": quality, "DataJson": JSON.stringify({"TreasureId": 1, "TreasureType": quality}), "world_position": [0, 0, 0]})
	world.interactions.setup(world.environment_root, markers, {"rules": {"Definitions": [], "Bindings": []}, "colliders": []})
	var controller = EFFECTS.new()
	controller.name = "EnvironmentEffects"
	world.environment_root.add_child(controller)
	controller.configure(world)
	controller.set_process(false)
	for quality in ["Normal", "Unusual", "Luxury", "Curse"]:
		var count: int = controller.bindings.size()
		check(world.interactions.interact(quality).success, "Chest interaction succeeds: " + quality)
		check(controller.bindings.size() == count + 1 and controller.bindings.back().transient, "Chest starts one transient recovered effect: " + quality)
		controller._process(0.01)
		check(is_instance_valid(controller.bindings.back().effect) and controller.bindings.back().effect.particle_count > 0, "Chest quality effect contains rendered particle layers: " + quality)
		world.interactions.interact(quality)
		check(controller.bindings.size() == count + 1, "Repeated chest input cannot duplicate effect: " + quality)
	var count: int = controller.bindings.size()
	world.interactions.interact("Unknown")
	check(controller.bindings.size() == count, "Unknown quality does not guess an effect")
	world.interactions.set_protection_enabled(true)
	check(world.interactions.interact("Protect").success, "Protection target activates once")
	check(controller.bindings.back().address == "24061701_fx_env_protecttarget_activation", "Protection uses recovered activation prefab")
	check(world.environment_root.get_node("Protect/Container_Active").visible and not world.environment_root.get_node("Protect/Container_UnActive").visible, "Protection switches source containers")
	world.interactions.complete_protection()
	check(controller.bindings.back().address == "24061701_fx_env_protecttarget_destruction", "Protection completion starts recovered destruction prefab")
	check(world.environment_root.get_node("Protect/Container_Destory").visible and not world.environment_root.get_node("Protect/Container_Active").visible, "Protection completion switches source destruction container")
	count = controller.bindings.size()
	world.interactions.complete_protection()
	check(controller.bindings.size() == count, "Repeated completion cannot repeat destruction")
	check(world.interactions.restore(world.interactions.snapshot()) and controller.bindings.size() == count, "Restoring an opened chest or completed target does not replay effects")
	var loot = LOOT.new()
	world.add_child(loot)
	loot.set_process(false)
	loot.spawn(103, Vector3.ZERO, 2, true)
	check(controller.bindings.size() == count + 1 and loot.entries.back().effect_binding.address == "23051501_fx_env_star", "Mineral material 103 uses EnvUnit 10105's exact embedded star")
	loot.spawn(10002, Vector3.RIGHT)
	check(controller.bindings.size() == count + 2 and loot.entries.back().effect_binding.address == "23121501_fx_other_proppurpleappear", "Ability item 10002 uses EnvUnit 50004's init effect")
	check(not loot.entries.back().effect_binding.loop, "Pickup appearance is finite")
	loot.spawn(10001, Vector3.LEFT)
	check(controller.bindings.size() == count + 2 and not loot.entries.back().has("effect_binding"), "An unconfirmed item never receives a guessed source effect")
	loot._process(0.01)
	check(controller.bindings.size() == count + 2, "Repeated ground updates do not replay appearances")
	controller._process(0.01)
	for entry in loot.entries:
		if entry.has("effect_binding"):
			check(is_instance_valid(entry.effect_binding.effect) and entry.effect_binding.effect.particle_count > 0, "Confirmed pickup effect instantiates source particles")
	var saved: Array = loot.snapshot()
	loot.restore(saved)
	check(controller.bindings.size() == count + 1 and loot.entries[0].has("effect_binding"), "Restore reconstructs the persistent mineral star")
	check(not loot.entries[1].has("effect_binding"), "Restore does not replay item appearance")
	var systems := TestSystems.new()
	check(loot.pickup(Vector3.ZERO, systems).success and systems.material_total == 2, "Mineral pickup grants its material once")
	check(controller.bindings.size() == count, "Picking up a mineral releases its particle binding")
	loot.clear()
	loot.spawn(10002, Vector3.ZERO)
	check(loot.pickup(Vector3.ZERO, systems).success and controller.bindings.size() == count, "Early pickup releases an unfinished appearance")
	loot.spawn(103, Vector3.ZERO, 1, true)
	loot.clear()
	check(controller.bindings.size() == count and loot.entries.is_empty(), "Room cleanup releases all pickup effects")
	world.free()
	print("RESOURCE_FEEDBACK_TEST ", JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
