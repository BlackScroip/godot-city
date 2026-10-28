class_name DungeonModelPreview
extends SubViewportContainer

var viewport: SubViewport
var pivot: Node3D
var camera: Camera3D
var _bounds := AABB()
var _has_bounds := false
static var _posed_bounds: Dictionary = {}

func _ready() -> void:
	stretch = true
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(220, 270)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport = SubViewport.new()
	viewport.size = Vector2i(300, 320)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(viewport)
	pivot = Node3D.new()
	viewport.add_child(pivot)
	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -35, 0)
	light.light_energy = 0.8
	viewport.add_child(light)
	var fill = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 130, 0)
	fill.light_color = Color("80b8cc")
	fill.light_energy = 0.6
	viewport.add_child(fill)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.current = true
	viewport.add_child(camera)
	resized.connect(_frame_bounds)

func show_model(path: String) -> void:
	_has_bounds = false
	for child in pivot.get_children():
		pivot.remove_child(child)
		child.queue_free()
	if not ResourceLoader.exists(path): return
	var packed = load(path)
	if not packed is PackedScene: return
	var model = packed.instantiate()
	pivot.add_child(model)
	var bounds = AABB()
	var first := true
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	for animator in model.find_children("*", "AnimationPlayer", true, false):
		for clip in animator.get_animation_list():
			if "idle" in clip.to_lower():
				animator.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
				animator.play(clip)
				animator.advance(0.0)
				break
	_bounds = _posed_bounds.get(path, bounds)
	_has_bounds = not first
	_frame_bounds()
	if not _posed_bounds.has(path) and DisplayServer.get_name() != "headless": _fit_animated_model(model, path)

func _fit_animated_model(model: Node3D, path: String) -> void:
	# Imported mesh bounds describe the bind pose, not the visible idle pose.
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(model) or model.get_parent() != pivot: return
	var bounds := AABB()
	var first := true
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null: continue
		var posed: Mesh = mesh.bake_mesh_from_current_skeleton_pose() if mesh.get_skin_reference() else mesh.mesh
		if posed == null: continue
		var box: AABB = mesh.global_transform * posed.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	if first: return
	_posed_bounds[path] = bounds
	_bounds = bounds
	_has_bounds = true
	_frame_bounds()

func _frame_bounds() -> void:
	if not _has_bounds or not is_instance_valid(camera): return
	var center := _bounds.get_center()
	camera.position = center + Vector3(2, 1, 4).normalized() * maxf(8, _bounds.size.length() * 2)
	camera.look_at(center)
	var view_bounds := camera.global_transform.affine_inverse() * _bounds
	var aspect := maxf(0.1, size.x / maxf(1.0, size.y))
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = maxf(1.5, maxf(view_bounds.size.y, view_bounds.size.x / aspect) * 1.3)
