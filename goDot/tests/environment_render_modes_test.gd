extends SceneTree

var checks := 0
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for action in ["move_left", "move_right", "move_up", "move_down"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	var evidence: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/environment_recovered/render_modes/1010107.json"))
	check(evidence.source_apk_sha256 == "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505", "Renderer evidence is bound to the supplied APK")
	check(evidence.bindings.size() == 1366 and evidence.unknown.is_empty(), "The current forest scene has complete unique hierarchy and TRS bindings")
	var world := DungeonWorld.new()
	root.add_child(world)
	world.load_environment(1010107)
	world.set_process(false)
	world.set_physics_process(false)
	var source_root: Node3D = world.environment_root.get_child(0)
	var actual: Dictionary = {}
	var shadow_materials := 0
	for source: MeshInstance3D in source_root.find_children("*", "MeshInstance3D", true, false):
		if not evidence.bindings.has(str(source.name)): continue
		actual[str(source.cast_shadow)] = int(actual.get(str(source.cast_shadow), 0)) + 1
		if source.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			for surface in source.mesh.get_surface_count():
				var active := source.get_active_material(surface)
				check(not active.resource_name.begins_with("UnityHidden/"), "Source shadow-only geometry supplies an unclipped depth material")
				if "FakeShadow" in active.resource_name: shadow_materials += 1
	check(actual == {"0": 1000, "1": 80, "3": 286}, "Forest renderer modes retain the APK's exact Off, On and ShadowsOnly distribution")
	check(shadow_materials == 286, "All authored forest shadow meshes retain their source material or source texture cutout")
	var report: Dictionary = world.environment_root.get_meta("source_renderer_modes", {})
	check(report.get("matched", 0) == 1366 and report.get("unknown", []).is_empty(), "Runtime resolves every offline binding without guessing from a name")
	var batch := world.environment_root.get_node("StaticEnvironmentBatch")
	check(batch.sources.size() > 400 and batch.batches.size() < batch.sources.size() / 2, "The real forest contains a useful reduction in static render instances")
	for source: MeshInstance3D in batch.sources:
		for item: Dictionary in world.interactions._items.values():
			var visual: Variant = item.get("visual")
			if visual is Node:
				check(source != visual and not visual.is_ancestor_of(source) and not source.is_ancestor_of(visual), "Batching leaves authored interactive object hierarchies independently visible")
	world.queue_free()
	await process_frame
	print("ENVIRONMENT_RENDER_MODES ", JSON.stringify({"checks": checks, "failures": failures, "modes": actual, "shadow_materials": shadow_materials}))
	quit(0 if failures.is_empty() else 1)
