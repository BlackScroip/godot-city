class_name DungeonModelPreview
extends SubViewportContainer

var viewport: SubViewport
var pivot: Node3D
var camera: Camera3D

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

func show_model(path: String) -> void:
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
	var center = bounds.get_center()
	camera.size = maxf(1.5, maxf(bounds.size.y, bounds.size.x) * 1.3)
	camera.position = center + Vector3(2, 1, 4).normalized() * maxf(8, bounds.size.length() * 2)
	camera.look_at(center)
	for animator in model.find_children("*", "AnimationPlayer", true, false):
		for clip in animator.get_animation_list():
			if "idle" in clip.to_lower():
				animator.play(clip)
				break
