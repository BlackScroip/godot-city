extends SceneTree

var checks := 0
var failures: Array[String] = []
var cases: Array[Dictionary] = []
var coverage := {"default_models": 0, "fashion_models": 0, "animation_clips": 0, "preserved_tracks": 0, "motion_samples": 0}

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _run() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/catalog.json"))
	var fashions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/fashions/catalog.json"))
	for id in catalog.characters:
		_add_case(str(id), int(id), catalog.characters[id].path, catalog.characters[id], false)
	for id in fashions.models:
		var entry: Dictionary = fashions.models[id]
		_add_case(str(id), int(entry.character_id), entry.path, catalog.characters[str(int(entry.character_id))], true)
	check(coverage.default_models == 8 and coverage.fashion_models == 45, "Every default character and recovered fashion is exercised")
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(12000, 1, 12000)
	shape.shape = floor_shape
	shape.position.y = -0.5
	floor_body.add_child(shape)
	root.add_child(floor_body)
	for direction in [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT, Vector3.ZERO]:
		for item in cases:
			item.start = item.actor.global_position
			item.actor.desired_velocity = direction * 5.0
		for step in 75:
			await physics_frame
			for item in cases:
				item.actor._physics_process(1.0 / 60.0)
				item.actor._process(1.0 / 60.0)
				_record_alignment(item)
		for item in cases:
			var moved: Vector3 = item.actor.global_position - item.start
			if direction.is_zero_approx():
				check(item.actor.locomotion.is_zero_approx(), item.label + " stops without carrying hidden movement")
			else:
				check(moved.dot(direction) > 4.5, item.label + " still travels through CharacterBody3D")
			check(str(item.actor.animation.assigned_animation).contains("idle") if direction.is_zero_approx() else str(item.actor.animation.assigned_animation).contains("run"), item.label + " uses its source locomotion animation")
	for item in cases:
		item.start = item.actor.global_position
		item.actor.action_time = 1.0
		item.actor.start_dodge(Vector3.FORWARD)
		item.actor.play_animation("dodge", true)
	for step in 70:
		await physics_frame
		for item in cases:
			item.actor._physics_process(1.0 / 60.0)
			item.actor._process(1.0 / 60.0)
			_record_alignment(item)
	var rows: Array[Dictionary] = []
	for item in cases:
		var actor: DungeonActor = item.actor
		check(absf(actor.global_position.z - item.start.z + DungeonActor.FEEL.dodge_distance) < 0.02, item.label + " retains its physical dodge distance")
		check(item.max_offset < 0.0001, item.label + " stays on its collision body through run loops, turns, stops and dodge")
		check(item.leg_changed, item.label + " preserves animated leg rotation")
		rows.append({"id": item.label, "path": item.path, "source_prefab_position": var_to_str(item.prefab_position), "maximum_horizontal_offset": item.max_offset, "leg_animation_changed": item.leg_changed})
		actor.free()
	floor_body.free()
	var report := {"checks": checks, "failures": failures, "coverage": coverage, "models": rows}
	FileAccess.open("res://reports/player-model-alignment-20261028.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("PLAYER_MODEL_ALIGNMENT: %d checks, %d failures; %s" % [checks, failures.size(), JSON.stringify(coverage)])
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _add_case(label: String, character_id: int, path: String, metadata: Dictionary, fashion: bool) -> void:
	var original: Node3D = load(path).instantiate()
	root.add_child(original)
	var original_player: AnimationPlayer = original.find_children("*", "AnimationPlayer", true, false)[0]
	var prefab: Node3D
	for child in original.get_children():
		if child is Node3D and str(child.name).begins_with("myplayer_"):
			prefab = child
			break
	check(prefab != null, label + " retains its APK player prefab hierarchy")
	var actor := DungeonActor.new()
	actor.actor_id = character_id
	actor.is_player = true
	root.add_child(actor)
	actor.position.x = cases.size() * 100.0
	actor.set_visual(path, metadata)
	actor.set_process(false)
	actor.set_physics_process(false)
	actor.animation.set_process(false)
	actor.animation.set_physics_process(false)
	var target := _root_target(actor.visual)
	check(not target.is_empty(), label + " has an actual source animation root")
	var leg := _leg_target(actor.visual)
	check(not leg.is_empty(), label + " contains source leg bones")
	for clip_name in original_player.get_animation_list():
		var source := original_player.get_animation(clip_name)
		var runtime := actor.animation.get_animation(clip_name)
		coverage.animation_clips += 1
		check(source.get_track_count() == runtime.get_track_count(), label + ": " + clip_name + " retains every animation track")
		for track in source.get_track_count():
			var path_name := str(source.track_get_path(track))
			if source.track_get_type(track) == Animation.TYPE_POSITION_3D and (path_name.ends_with(":root") or path_name.ends_with("/root")):
				var height_preserved := true
				for key in source.track_get_key_count(track):
					height_preserved = height_preserved and is_equal_approx(source.track_get_key_value(track, key).y, runtime.track_get_key_value(track, key).y)
				check(height_preserved, label + ": " + clip_name + " keeps root height")
			else:
				var unchanged := source.track_get_key_count(track) == runtime.track_get_key_count(track)
				for key in source.track_get_key_count(track):
					unchanged = unchanged and source.track_get_key_value(track, key) == runtime.track_get_key_value(track, key)
				check(unchanged, label + ": " + clip_name + " keeps authored " + path_name)
				coverage.preserved_tracks += 1
	var item := {"label": label, "actor": actor, "path": path, "target": target, "leg": leg, "leg_rotation": _leg_rotation(leg), "leg_changed": false, "max_offset": 0.0, "prefab_position": prefab.position if prefab != null else Vector3.ZERO}
	cases.append(item)
	if fashion: coverage.fashion_models += 1
	else: coverage.default_models += 1
	original.free()

func _root_target(model: Node3D) -> Dictionary:
	for node in model.find_children("*", "Skeleton3D", true, false):
		var bone: int = node.find_bone("root")
		if bone >= 0: return {"node": node, "bone": bone}
	var node := model.find_child("root", true, false) as Node3D
	return {"node": node, "bone": -1} if node else {}

func _leg_target(model: Node3D) -> Dictionary:
	for node in model.find_children("*", "Skeleton3D", true, false):
		var bone: int = node.find_bone("Bip001 L Calf")
		if bone >= 0: return {"node": node, "bone": bone}
	return {}

func _leg_rotation(target: Dictionary) -> Quaternion:
	return target.node.get_bone_pose_rotation(target.bone) if not target.is_empty() else Quaternion.IDENTITY

func _record_alignment(item: Dictionary) -> void:
	var target: Dictionary = item.target
	if target.is_empty(): return
	var point: Vector3 = target.node.global_position
	if target.bone >= 0: point = target.node.global_transform * target.node.get_bone_global_pose(target.bone).origin
	var offset: Vector3 = point - item.actor.global_position
	item.max_offset = maxf(item.max_offset, Vector2(offset.x, offset.z).length())
	item.leg_changed = item.leg_changed or not _leg_rotation(item.leg).is_equal_approx(item.leg_rotation)
	coverage.motion_samples += 1
