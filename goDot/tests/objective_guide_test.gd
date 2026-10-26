extends SceneTree

const Guide = preload("res://scripts/presentation/objective_guide.gd")

class Interactions extends RefCounted:
	var _items: Dictionary = {}

class GuideWorld extends Node3D:
	var interactions := Interactions.new()
	var camera: Camera3D
	var player: Node3D
	var environment_root: Node3D

var checks := 0
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var canvas := SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	root.add_child(canvas)
	var guide := Guide.new()
	canvas.add_child(guide)
	await process_frame
	guide.set_process(false)
	for screen in [Vector2(1600, 900), Vector2(844, 390), Vector2(2460, 1080)]:
		for point in [screen * Vector2(-2, 0.5), screen * Vector2(3, 0.5), screen * Vector2(0.5, -2), screen * Vector2(0.5, 3)]:
			guide.clear_target()
			guide.update_screen_target(point, screen)
			check(guide.visible and guide.fade == 0, "Offscreen exit begins a fade at %s" % screen)
			guide._process(0.15)
			check(is_equal_approx(guide.modulate.a, 0.5), "Guide reaches half opacity after 0.15 seconds")
			guide._process(0.15)
			check(guide.modulate.a == 1, "Guide fades in over source 0.3 seconds")
			check(guide.direction.dot((point - screen * 0.5).normalized()) > 0.999, "Needle follows the screen direction")
			check(guide.center.distance_to(screen * 0.5) <= screen.y * 0.35 + 0.01, "Guide respects source radial limit")
			var reach := Vector2.ONE * 107 * guide.art_scale
			check(Rect2(Vector2.ZERO, screen).encloses(Rect2(guide.center - reach, reach * 2)), "Guide and needle fit the viewport")
		for normalized in [Vector2(0.1, 0.1), Vector2(0.9, 0.9), Vector2(0.5, 0.5)]:
			guide.update_screen_target(normalized * screen, screen)
			check(not guide.visible, "Exit within source central 80 percent needs no indicator")
	guide.update_screen_target(Vector2(2000, 450), Vector2(1600, 900), true)
	check(guide.visible and guide.direction.x < -0.99, "Behind-camera exit reverses projected direction")
	guide.update_screen_target(Vector2.ZERO, Vector2.ZERO)
	check(not guide.visible, "Invalid viewport hides the guide")
	var world := GuideWorld.new()
	canvas.add_child(world)
	world.environment_root = Node3D.new()
	world.add_child(world.environment_root)
	world.environment_root.position = Vector3(11, 0, 7)
	world.environment_root.rotation.y = 0.4
	world.player = Node3D.new()
	world.add_child(world.player)
	world.player.position = world.environment_root.position
	world.camera = Camera3D.new()
	world.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	world.camera.size = 20
	world.add_child(world.camera)
	world.camera.position = world.player.position + Vector3(0, 10, 10)
	world.camera.look_at(world.player.position)
	world.camera.make_current()
	var visual := Node3D.new()
	world.environment_root.add_child(visual)
	var exit := {"id": "exit", "position": Vector3(100, 0, 0), "visual": visual, "marker": {"Type": "EEUT_StageChangeDoor"}, "state": {"enabled": true, "broken": false, "opened": false, "used": false}}
	world.interactions._items["exit"] = exit
	var chest: Dictionary = exit.duplicate()
	chest.id = "chest"
	chest.position = Vector3(0.5, 0, 0)
	chest.marker = {"Type": "EEUT_AbilityItemTreasureBox"}
	world.interactions._items["chest"] = chest
	await process_frame
	guide.update_target(world, false)
	check(guide.visible and guide.target_id == "exit", "Nearby chest cannot replace the next-exit target")
	var expected: Vector2 = world.camera.unproject_position(world.environment_root.to_global(exit.position)) - Vector2(canvas.size) * 0.5
	check(guide.direction.dot(expected.normalized()) > 0.999, "Projection uses the environment transform")
	for field in ["opened", "broken", "used"]:
		exit.state[field] = true
		guide.update_target(world, false)
		check(not guide.visible, "Ineligible exit hides when %s" % field)
		exit.state[field] = false
	exit.state.enabled = false
	guide.update_target(world, false)
	check(not guide.visible, "Locked exit has no guide")
	exit.state.enabled = true
	guide.update_target(world, true)
	check(not guide.visible, "Modal, background and transition blocker hides guide")
	exit.position = Vector3.ZERO
	world.environment_root.position = Vector3.ZERO
	guide.update_target(world, false)
	check(not guide.visible, "Unset zero exit position has no guide")
	canvas.free()
	var report := {"checks": checks, "failures": failures, "passed": failures.is_empty()}
	FileAccess.open("res://reports/objective-guide-test.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("OBJECTIVE_GUIDE_TEST ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
