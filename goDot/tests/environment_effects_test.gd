extends SceneTree

const CONTROLLER = preload("res://scripts/presentation/environment_effects.gd")
class TestWorld extends Node3D:
	var low_effects := false
	var paused := false
	var _background := false
	var hud: Node
	var player: Node3D
	var environment_root: Node3D
var failures: Array[String] = []
var checks := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var world := TestWorld.new()
	root.add_child(world)
	world.environment_root = Node3D.new()
	world.add_child(world.environment_root)
	world.player = Node3D.new()
	world.add_child(world.player)
	var controller = CONTROLLER.new()
	world.environment_root.add_child(controller)
	controller.configure(world)
	controller.set_process(false)
	controller.effects = {"test": {"layers": [{"name": "test", "active": true, "looping": true, "duration": 1, "materials": [{"color": {"r": 1, "g": 1, "b": 1, "a": 1}}], "initial": {"startLifetime": {"scalar": 1}}, "emission": {"rateOverTime": {"scalar": 4}}}]}}
	var original_texture := "res://assets/environment_effects/texture_d00fa6198cd9f832b06a.png"
	controller.effects.test.layers[0].materials[0].texture = original_texture
	check(CONTROLLER.source_address("Test_u123") == "test", "Exporter node suffix resolves")
	check(CONTROLLER.source_address("Test_unit") == "test_unit", "Non-numeric suffix retained")
	check(controller.resolve_address("test_1__u123") == "test", "Numbered exported duplicate resolves")
	check(controller.resolve_address("test_clone_2__u123") == "test", "Clone exported duplicate resolves")
	check(controller.resolve_address("testdestroy__u123").is_empty(), "Address prefix cannot consume a different effect")
	var anchor := Node3D.new()
	world.environment_root.add_child(anchor)
	var entry: Dictionary = controller.register_anchor(anchor, "test")
	check(not entry.is_empty(), "Known effect registers")
	check(controller.register_anchor(anchor, "test") == entry and controller.bindings.size() == 1, "Registration deduplicates")
	controller._process(0.2)
	check(is_instance_valid(entry.effect) and entry.effect.particle_count > 0, "Nearby source creates particles")
	check(entry.effect.emitters[0].node.material_override.get_shader_parameter("main_texture") is Texture2D, "Runtime loads and binds original particle texture")
	check(is_equal_approx(entry.effect.age, 0.2), "Active clock advances")
	world.paused = true
	controller._process(0.5)
	check(is_equal_approx(entry.effect.age, 0.2), "Pause freezes particles")
	check(is_equal_approx(controller.clock, 0.2), "Pause freezes water clock")
	world.paused = false
	world._background = true
	controller._process(0.5)
	check(is_equal_approx(entry.effect.age, 0.2), "Background freezes particles")
	world._background = false
	anchor.hide()
	controller._process(0.1)
	check(not entry.active and not entry.effect.visible, "Hidden source stops effect")
	anchor.show()
	controller._process(0.1)
	check(entry.active and is_equal_approx(entry.effect.age, 0.1), "Reactivation restarts source")
	anchor.position.x = 100
	controller._process(0.1)
	check(not is_instance_valid(entry.effect), "Distant looping source releases particle nodes")
	anchor.position.x = 0
	anchor.set_meta("unityActive", false)
	controller._process(0.1)
	check(not entry.active, "Source inactive flag respected")
	anchor.set_meta("unityActive", true)
	var one_shot: Dictionary = controller.trigger_at("test", Vector3.ZERO)
	var second_shot: Dictionary = controller.trigger_at("test", Vector3.ZERO)
	var third_shot: Dictionary = controller.trigger_at("test", Vector3.ZERO)
	controller._process(3.0)
	check(not controller.bindings.has(one_shot) and not controller.bindings.has(second_shot) and not controller.bindings.has(third_shot), "Adjacent triggered effects all expire without skipping bindings")
	var invalid_anchor := Node3D.new()
	world.environment_root.add_child(invalid_anchor)
	controller.register_anchor(invalid_anchor, "test")
	anchor.free()
	invalid_anchor.free()
	controller._process(0.1)
	check(controller.bindings.is_empty(), "Adjacent deleted external anchors release all bindings")
	controller.effects.test.layers[0].emission.rateOverTime.scalar = 96
	world.low_effects = true
	controller.set_low_quality(true)
	for i in 40:
		var budget_anchor := Node3D.new()
		world.environment_root.add_child(budget_anchor)
		budget_anchor.position.x = i * 0.5
		controller.register_anchor(budget_anchor, "test")
	controller._process(0.1)
	check(controller.active_particle_count <= 720 and controller.active_particle_count > 0, "Low quality scene budget enforced")
	var nearest: Node3D = controller.bindings[0].anchor
	world.player.position.x = 0.4
	controller._process(0.01)
	check(controller.bindings[0].anchor == nearest, "Small focus movement reuses priorities within the refresh interval")
	controller._process(0.2)
	check(is_equal_approx(controller.bindings[0].anchor.position.x, 0.5), "Priority refresh selects the new nearest source within a bounded interval")
	world.player.position.x = 19.5
	controller._process(0.01)
	check(is_equal_approx(controller.bindings[0].anchor.position.x, 19.5), "Large focus movement refreshes priorities immediately")
	check(controller.bindings[0].effect.visible and not controller.bindings.back().effect.visible and controller.active_particle_count <= 720, "Nearest sources retain the particle budget after reprioritizing")
	world.player.position.x = 19.9
	var new_anchor := Node3D.new()
	world.environment_root.add_child(new_anchor)
	new_anchor.position = world.player.position
	var new_entry: Dictionary = controller.register_anchor(new_anchor, "test")
	controller._process(0.001)
	check(controller.bindings[0] == new_entry and new_entry.effect.visible, "New sources receive an immediate priority and budget check")
	new_anchor.hide()
	controller._process(0.001)
	check(not new_entry.active and not new_entry.effect.visible, "Hidden sources stop immediately between priority refreshes")
	new_anchor.show()
	controller._process(0.001)
	var age: float = new_entry.effect.age
	world.paused = true
	controller._process(0.001)
	check(is_equal_approx(new_entry.effect.age, age) and new_entry.effect.emitters[0].node.speed_scale == 0, "Pause freezes active emitters immediately between priority refreshes")
	world.paused = false
	var existing = controller.bindings[0].effect
	controller.set_low_quality(false)
	check(controller.bindings[0].effect == null and existing.is_queued_for_deletion(), "Quality change rebuilds looping effect budgets")
	world.low_effects = false
	controller._process(0.1)
	check(controller.active_particle_count <= 2304, "Full quality scene budget enforced")
	world.free()
	print(JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
