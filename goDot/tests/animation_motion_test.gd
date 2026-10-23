extends SceneTree

var failures: Array[String] = []
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/catalog.json"))
	for id in range(1, 8):
		var actor := DungeonActor.new()
		actor.is_player = true
		root.add_child(actor)
		var metadata: Dictionary = catalog.characters[str(id)]
		var untouched: Node3D = load(metadata.path).instantiate()
		root.add_child(untouched)
		var source: AnimationPlayer = untouched.find_children("*", "AnimationPlayer", true, false)[0]
		var source_clips: Dictionary = {}
		for name in source.get_animation_list(): source_clips[name] = source.get_animation(name).duplicate()
		actor.set_visual(metadata.path, metadata)
		actor.set_process(false)
		actor.animation.set_process(false)
		actor.animation.set_physics_process(false)
		for clip in metadata.get("animations", []):
			var source_name = str(clip.get("source_name", ""))
			if "satk" not in source_name.to_lower(): continue
			actor.play_animation(source_name, true)
			check(actor.animation.assigned_animation == str(clip.name), "%d %s: source heavy animation resolves exactly" % [id, source_name])
			var normalized = source_name.replace("@", "_")
			if not metadata.animations.any(func(other): return other.source_name == normalized and other.name != clip.name):
				actor.play_animation(normalized, true)
				check(actor.animation.assigned_animation == str(clip.name), "%d %s: unambiguous converted alias resolves exactly" % [id, source_name])
		actor.play_animation("idle", true)
		var targets: Array[Dictionary] = []
		for name in actor.animation.get_animation_list():
			var clip := actor.animation.get_animation(name)
			var original := source.get_animation(name)
			var animation_root := actor.animation.get_node(actor.animation.root_node)
			for track in clip.get_track_count():
				if clip.track_get_type(track) != Animation.TYPE_POSITION_3D: continue
				var path := clip.track_get_path(track)
				var node := animation_root.get_node_or_null(NodePath(path.get_concatenated_names()))
				var bone := -1
				var origin: Vector3
				if path.get_subname_count() == 1 and str(path.get_subname(0)) == "root" and node is Skeleton3D:
					bone = node.find_bone("root")
					origin = node.get_bone_rest(bone).origin
				elif path.get_subname_count() == 0 and node is Node3D and str(node.name) == "root":
					origin = node.position
				else: continue
				if targets.is_empty(): targets.append({"node": node, "bone": bone, "origin": origin})
				for key in clip.track_get_key_count(track):
					var point: Vector3 = clip.track_get_key_value(track, key)
					var source_point: Vector3 = original.track_get_key_value(track, key)
					check(Vector2(point.x, point.z).distance_to(Vector2(origin.x, origin.z)) < 0.0001, "%d %s: visual stays on body" % [id, name])
					check(is_equal_approx(point.y, source_point.y), "%d %s: animated height preserved" % [id, name])
					check(source_point.is_equal_approx(source_clips[name].track_get_key_value(track, key)), "%d %s: shared source remains unchanged" % [id, name])
		check(not targets.is_empty(), "%d: root motion target covered" % id)
		actor.desired_velocity = Vector3.FORWARD * 5
		var previous_visual := Vector3.INF
		for step in 100:
			await physics_frame
			actor._physics_process(1.0 / 60)
			actor.animation.advance(1.0 / 60)
			var point := visual_root_position(actor, targets[0])
			if previous_visual.is_finite(): check(point.z <= previous_visual.z + 0.001, "%d: run cycle never pulls model backwards" % id)
			previous_visual = point
		actor.desired_velocity = Vector3.ZERO
		for step in 20:
			await physics_frame
			actor._physics_process(1.0 / 60)
			actor.animation.advance(1.0 / 60)
		var stopped := visual_root_position(actor, targets[0])
		check(stopped.z <= previous_visual.z + 0.001, "%d: stopping does not reset travel" % id)
		actor.action_time = 1
		actor.start_dodge(Vector3.FORWARD)
		actor.play_animation("dodge", true)
		var start := actor.position
		for step in 70:
			await physics_frame
			actor._physics_process(1.0 / 60)
			actor.animation.advance(1.0 / 60)
		var landed := visual_root_position(actor, targets[0])
		check(absf(actor.position.z - start.z + DungeonActor.FEEL.dodge_distance) < 0.02, "%d: physical dodge retains distance" % id)
		check(absf(landed.z - actor.position.z) < 0.001, "%d: dodge ending keeps model at landing" % id)
		actor.free()
		untouched.free()
	print("ANIMATION_MOTION: %d checks, %d failures" % [checks, failures.size()])
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func visual_root_position(actor: DungeonActor, target: Dictionary) -> Vector3:
	var point: Vector3 = target.node.get_bone_pose_position(target.bone) if target.bone >= 0 else target.node.position
	return actor.position + point - target.origin
