extends SceneTree

class AltarWorld extends Node3D:
	var environment_root: Node3D

class SourceInteractions extends RefCounted:
	var _items: Dictionary = {}

var failures: Array[String] = []
var checks := 0
var requested: Array = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _click(canvas: SubViewport, point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	canvas.push_input(motion, true)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = point
	press.pressed = true
	canvas.push_input(press, true)
	await process_frame
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = point
	canvas.push_input(release, true)
	await process_frame

func _run() -> void:
	var canvas := SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	root.add_child(canvas)
	var world := AltarWorld.new()
	canvas.add_child(world)
	world.environment_root = Node3D.new()
	world.add_child(world.environment_root)
	var drops = preload("res://scripts/ground_loot.gd").new()
	world.add_child(drops)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0, 10, 10)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var hud := DungeonHud.new()
	canvas.add_child(hud)
	await process_frame
	hud.close_page()
	hud.primary.hide()
	drops.configure_altar_pointer(hud)
	drops.altar_requested.connect(func(key, marker):
		requested.append([key, marker])
		hud.modal_open = true)
	drops.spawn_altar(Vector3(-1.0, 0, 0), "altar:test")
	drops.spawn_altar(Vector3(-1.0, 0, 0), "altar:test")
	check(drops.entries.size() == 1, "One room altar key cannot duplicate its egg")
	check(drops.entries[0].visual.texture.resource_path.ends_with("spirit_altar_egg.png"), "Runtime altar uses the APK egg image")
	for dimensions in [Vector2i(1600, 900), Vector2i(844, 390)]:
		canvas.size = dimensions
		hud.modal_open = false
		await process_frame
		drops.update_altar_pointer(camera, Vector3.ZERO, true)
		await process_frame
		var entry: Dictionary = drops.entries[0]
		var target: Button = entry.pointer
		check(target.visible and target.size.x >= 44, "World egg has a stable pointer target at %s" % dimensions)
		check(hud.joystick.excluded_controls.has(target), "World egg is excluded from movement joystick")
		var before := requested.size()
		await _click(canvas, target.get_global_rect().get_center())
		check(requested.size() == before + 1 and requested.back() == ["altar:test", ""], "Physical egg click requests its exact altar once at %s" % dimensions)
		check(not drops.request_altar(entry), "Opening a selection modal blocks repeated egg requests")
		hud.modal_open = false
		drops.update_altar_pointer(camera, Vector3(30, 0, 0), true)
		check(not target.visible and not drops.request_altar(entry), "Distant altar cannot grant a selection")
		drops.update_altar_pointer(camera, Vector3.ZERO, false)
		check(not target.visible and not drops.request_altar(entry), "Paused or transitioning world cannot activate egg")
	var old_button: Button = drops.entries[0].pointer
	drops.restore(JSON.parse_string(JSON.stringify(drops.snapshot())))
	check(drops.entries.size() == 1 and old_button.is_queued_for_deletion(), "Runtime altar survives JSON resume and frees the old click target")
	check(not hud.joystick.excluded_controls.has(old_button), "Restoring drops releases old joystick exclusion")
	var source := SourceInteractions.new()
	var source_visual := Node3D.new()
	source_visual.name = "EnvUnit_Interactable_SpritesAltar"
	world.environment_root.add_child(source_visual)
	var source_egg := Node3D.new()
	source_egg.name = "sprite_abilityitemicon_14104__u103"
	source_visual.add_child(source_egg)
	source_egg.position = Vector3(0, 1.2, 0)
	source._items["103"] = {"id": "103", "visual": source_visual,
		"data": {"UIBtnName": drops.ALTAR_BUTTON_KEY},
		"state": {"enabled": true, "used": false, "broken": false}}
	drops.sync_source_altars(source, "room-2")
	check(drops.source_altars.size() == 1 and drops.source_altars[0].visual == source_egg, "Source scene resolves the original egg rather than a duplicate icon")
	var source_entry: Dictionary = drops.source_altars[0]
	check(drops.altar_reachable(source_entry, Vector3(1.8, 0, 0)), "APK enter box includes the player capsule at its edge")
	check(not drops.altar_reachable(source_entry, Vector3(1.9, 0, 0)), "APK enter box rejects players beyond its horizontal edge")
	hud.modal_open = false
	drops.update_altar_pointer(camera, Vector3.ZERO, true)
	check(drops.request_altar(source_entry), "Source scene egg is directly requestable")
	check(requested.back() == ["altar:room-2:103", "103"], "Source egg carries stable room and marker identities")
	hud.modal_open = false
	source._items["103"].state.used = true
	drops.update_altar_pointer(camera, Vector3.ZERO, true)
	check(not source_entry.pointer.visible and not drops.request_altar(source_entry), "Consumed source egg cannot be requested again")
	source._items["103"].state.used = false
	source._items["103"].state.enabled = false
	check(not drops.altar_reachable(source_entry, Vector3.ZERO), "Disabled scene altar is unavailable")
	drops.clear()
	check(drops.source_altars.is_empty() and drops.entries.is_empty(), "Changing room clears source and runtime pointer targets")
	check(not drops.request_altar(source_entry), "A queued click from a cleared room cannot activate a stale altar")
	check(hud.joystick.excluded_controls.size() == 3, "Room cleanup leaves only the HUD's fixed joystick exclusions")
	print("SPIRIT_ALTAR_POINTER_TEST ", JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	canvas.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
