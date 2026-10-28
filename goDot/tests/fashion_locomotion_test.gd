extends SceneTree

const Models = preload("res://scripts/presentation/character_fashion_models.gd")

class SourcePlacementActor extends DungeonActor:
	func _align_player_prefab_origin() -> void:
		pass

var failures: Array[String] = []
var checks := 0
var cases: Array = []
var source_placement: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr(message)

func _run() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/catalog.json"))
	var source: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/role_character/CharaFashionConfigData.json"))
	_source_placement_case(catalog)
	for row in source:
		var actor := DungeonActor.new()
		actor.is_player = true
		root.add_child(actor)
		actor.set_process(false)
		actor.set_visual(Models.path_for(int(row.id)), catalog.characters[str(int(row.chara_id))])
		check(actor.animation != null, "%d: equipped model has an animation player" % int(row.id))
		if actor.animation == null:
			actor.free()
			continue
		actor.play_animation("run", true)
		actor.animation.advance(0)
		var anchors := _anchors(actor)
		check(not anchors.is_empty(), "%d: imported model exposes its animated root" % int(row.id))
		var clip := actor.animation.get_animation(actor.animation.assigned_animation)
		check(clip.loop_mode == Animation.LOOP_LINEAR, "%d: equipped run animation loops" % int(row.id))
		var start := _positions(actor, anchors)
		for point in start:
			check(Vector2(point.x, point.z).length() < 0.001, "%d: the model begins centered on its body" % int(row.id))
		var turns := _turning_offsets(actor, anchors)
		for turn in turns:
			check(float(turn.maximum_offset) < 0.001, "%d: facing %d keeps model centered (offset %.6f)" % [int(row.id), int(turn.yaw), float(turn.maximum_offset)])
		var maximum := 0.0
		for frame in 120:
			actor.animation.advance(clip.length / 60.0)
			var positions := _positions(actor, anchors)
			for index in positions.size():
				maximum = maxf(maximum, Vector2(positions[index].x - start[index].x, positions[index].z - start[index].z).length())
		check(maximum < 0.001, "%d: run cycle keeps model on body (drift %.6f)" % [int(row.id), maximum])
		var paths: Array = []
		for anchor in anchors: paths.append(str(anchor.node.get_path()) + ":" + str(anchor.get("bone", -1)))
		cases.append({"fashion": int(row.id), "animation": actor.animation.assigned_animation, "root_anchors": paths, "turns": turns, "maximum_run_drift": maximum})
		if int(row.id) == int(row.chara_id) * 1000 + 1:
			await _moving_body(actor, int(row.id), anchors)
		actor.free()
	var report := {"passed": failures.is_empty(), "checks": checks, "fashions": cases, "source_placement": source_placement, "failures": failures}
	FileAccess.open("res://reports/fashion-locomotion-test.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("FASHION_LOCOMOTION ", JSON.stringify({"passed": failures.is_empty(), "checks": checks, "fashions": cases.size(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func _source_placement_case(catalog: Dictionary) -> void:
	var original := SourcePlacementActor.new()
	original.is_player = true
	root.add_child(original)
	original.set_process(false)
	original.set_visual(Models.path_for(1001), catalog.characters["1"])
	original.animation.advance(0)
	var anchors := _anchors(original)
	var before := _turning_offsets(original, anchors)
	var first: Array = before[0].positions[0]
	var reversed: Array = before[2].positions[0]
	var turn_jump := Vector2(float(reversed[0]) - float(first[0]), float(reversed[2]) - float(first[2])).length()
	check(turn_jump > 1.96, "Source placement fixture reproduces the turn-induced visual jump")
	var prefab_position := Vector3.ZERO
	for child in original.visual.get_children():
		if child is Node3D and str(child.name).begins_with("myplayer_"): prefab_position = child.position
	original.free()
	var aligned := DungeonActor.new()
	aligned.is_player = true
	root.add_child(aligned)
	aligned.set_process(false)
	aligned.set_visual(Models.path_for(1001), catalog.characters["1"])
	aligned.animation.advance(0)
	var after := _turning_offsets(aligned, _anchors(aligned))
	for turn in after: check(float(turn.maximum_offset) < 0.001, "The actual default player stays centered while turning")
	source_placement = {"fashion": 1001, "prefab_position": [prefab_position.x, prefab_position.y, prefab_position.z], "before": before, "after": after, "original_half_turn_visual_jump": turn_jump}
	aligned.free()

func _turning_offsets(actor: DungeonActor, anchors: Array) -> Array:
	var result: Array = []
	var rotation := actor.visual.rotation
	for yaw in [0, 90, 180, 270]:
		actor.visual.rotation.y = deg_to_rad(float(yaw))
		var maximum := 0.0
		var points: Array = []
		for point in _positions(actor, anchors):
			maximum = maxf(maximum, Vector2(point.x, point.z).length())
			points.append([point.x, point.y, point.z])
		result.append({"yaw": yaw, "maximum_offset": maximum, "positions": points})
	actor.visual.rotation = rotation
	return result

func _anchors(actor: DungeonActor) -> Array:
	var result: Array = []
	for node in actor.visual.find_children("*", "Node3D", true, false):
		if str(node.name).to_lower() == "root": result.append({"node": node, "bone": -1})
		if node is Skeleton3D:
			for bone in node.get_bone_count():
				if node.get_bone_name(bone).to_lower() == "root": result.append({"node": node, "bone": bone})
	return result

func _positions(actor: DungeonActor, anchors: Array) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for anchor in anchors:
		var point: Vector3 = anchor.node.global_position
		if int(anchor.bone) >= 0: point = anchor.node.global_transform * anchor.node.get_bone_global_pose(int(anchor.bone)).origin
		result.append(actor.to_local(point))
	return result

func _moving_body(actor: DungeonActor, id: int, anchors: Array) -> void:
	actor.play_animation("idle", true)
	actor.animation.advance(0)
	var origin := _positions(actor, anchors)
	actor.desired_velocity = Vector3.FORWARD * 5.0
	var start := actor.position
	var maximum := 0.0
	for frame in 90:
		await physics_frame
		actor._physics_process(1.0 / 60.0)
		var positions := _positions(actor, anchors)
		for index in positions.size(): maximum = maxf(maximum, Vector2(positions[index].x - origin[index].x, positions[index].z - origin[index].z).length())
	check(actor.position.z < start.z - 7.0, "%d: held input moves the body" % id)
	actor.desired_velocity = Vector3.ZERO
	for frame in 20:
		await physics_frame
		actor._physics_process(1.0 / 60.0)
		var positions := _positions(actor, anchors)
		for index in positions.size(): maximum = maxf(maximum, Vector2(positions[index].x - origin[index].x, positions[index].z - origin[index].z).length())
	check(actor.velocity.length_squared() == actor.velocity.y * actor.velocity.y, "%d: released input stops planar travel" % id)
	check(maximum < 0.001, "%d: moving and stopping preserve model/body alignment (drift %.6f)" % [id, maximum])
	actor.start_dodge(Vector3.FORWARD)
	actor.play_animation("dodge", true)
	start = actor.position
	for frame in 50:
		await physics_frame
		actor._physics_process(1.0 / 60.0)
	check(absf(actor.position.z - start.z + DungeonActor.FEEL.dodge_distance) < 0.02, "%d: dodge retains physical distance" % id)
	var positions := _positions(actor, anchors)
	for index in positions.size():
		check(Vector2(positions[index].x - origin[index].x, positions[index].z - origin[index].z).length() < 0.001, "%d: dodge returns the model to its body" % id)
