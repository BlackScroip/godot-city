extends SceneTree

const INTERACTIONS = preload("res://scripts/world_interactions.gd")
var checks := 0
var failures: Array[String] = []
var rows: Array = []
var transitions: Array = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func _run() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://reports/region-environment-recovery.json"))
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/catalog.json"))
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/environment_rules.json"))
	var world := DungeonWorld.new()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	check(source.scenes.size() == 22, "All twenty lava and two updated island scenes exported")
	for id: String in source.scenes:
		var entry: Dictionary = catalog.environments[id]
		var packed = load(str(entry.path))
		check(packed is PackedScene, id + " GLB imports as scene")
		if not packed is PackedScene: continue
		var environment := Node3D.new()
		world.environment_root = environment
		world.add_child(environment)
		environment.add_child(packed.instantiate())
		world._load_collisions(str(entry.path))
		check(world.collision_report.loaded > 0, id + " source solid colliders load")
		check(world.collision_report.missing_mesh.is_empty(), id + " no missing collision mesh")
		var interactions := INTERACTIONS.new()
		interactions.transition_requested.connect(func(context): transitions.append(context))
		interactions.setup(environment, world.semantic_markers, {"rules": rules, "colliders": world.markers})
		var doors := 0
		for marker in world.semantic_markers:
			var visual = environment.find_child(str(marker.exported_node_name), true, false)
			check(is_instance_valid(visual), id + " exact source node binds " + str(marker.SourceGameObjectId))
			if is_instance_valid(visual):
				check(visual.global_position.distance_to(world.vector(marker.world_position)) < 0.01, id + " source marker position matches imported hierarchy")
			if marker.Type != "EEUT_StageChangeDoor": continue
			doors += 1
			var marker_id := str(marker.SourceGameObjectId)
			interactions.set_exit_enabled(false)
			check(not interactions.interact(marker_id).success, id + " locked exit rejects transition")
			interactions.set_exit_enabled(true)
			var before := transitions.size()
			check(interactions.interact(marker_id).success, id + " unlocked source exit permits transition")
			check(transitions.size() == before + 1, id + " source exit emits exactly one transition")
			if transitions.size() > before:
				var data: Dictionary = JSON.parse_string(str(marker.DataJson))
				check(int(transitions.back().data.get("DoorIndex", 0)) == int(data.get("DoorIndex", 0)), id + " source DoorIndex retained")
		check(doors > 0, id + " has original stage exit marker")
		await physics_frame
		await physics_frame
		var spawn := world.vector(entry.player_start)
		var ray := PhysicsRayQueryParameters3D.create(spawn + Vector3.UP, spawn + Vector3.DOWN * 3.0, 1)
		var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(ray)
		check(not hit.is_empty(), id + " exact EnvCfg spawn has source floor")
		rows.append({"id": id, "source_spawn": entry.player_start, "floor_hit": not hit.is_empty(),
			"floor_y": hit.position.y if not hit.is_empty() else null, "solid_colliders": world.collision_report.loaded,
			"semantic_markers": world.semantic_markers.size(), "doors": doors})
		environment.free()
		world.environment_root = null
	world.free()
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "scenes": rows}
	FileAccess.open("res://reports/region-environment-recovery-test.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("REGION ENVIRONMENT RECOVERY ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
