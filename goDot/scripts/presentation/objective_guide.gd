extends Control

var center := Vector2.ZERO
var direction := Vector2.RIGHT
var tint := Color("74dbff")
var clock := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hide()

func update_target(world: Node3D, blocked: bool) -> void:
	if blocked or not world.interactions or not is_instance_valid(world.player):
		hide()
		return
	var target: Dictionary = {}
	var best := INF
	for item in world.interactions._items.values():
		var kind := str(item.marker.get("Type", ""))
		if kind not in ["EEUT_AbilityItemTreasureBox", "EEUT_StageChangeDoor", "EEUT_Protal"]: continue
		if not item.state.enabled or item.state.broken or item.state.opened or item.state.used: continue
		if not is_instance_valid(item.visual) or not item.visual.is_visible_in_tree(): continue
		var distance: float = world.player.global_position.distance_to(world.environment_root.to_global(item.position))
		var score := distance + (0.0 if kind == "EEUT_AbilityItemTreasureBox" else 10000.0)
		if score < best:
			best = score
			target = item
	if target.is_empty():
		hide()
		return
	var point: Vector3 = world.environment_root.to_global(target.position)
	if world.player.global_position.distance_to(point) < 3.0:
		hide()
		return
	var camera: Camera3D = world.camera
	var player_screen := camera.unproject_position(world.player.global_position)
	var target_screen := camera.unproject_position(point + Vector3.UP)
	var viewport_size := get_viewport_rect().size
	var ui_scale := size / viewport_size
	var offset := target_screen - player_screen
	if camera.is_position_behind(point): offset = -offset
	direction = offset.normalized()
	var desired := player_screen * ui_scale + direction * minf(145.0, offset.length() * 0.65)
	center = desired.clamp(Vector2(64, 142), (size - Vector2(290, 150)).max(Vector2(64, 142)))
	tint = Color("74dbff")
	clock = Time.get_ticks_msec() * 0.001
	show()
	queue_redraw()

func _draw() -> void:
	var radius := 23.0 + sin(clock * 2.4) * 1.2
	draw_circle(center, radius + 7, Color(0.03, 0.35, 0.65, 0.17))
	draw_circle(center, radius - 4, Color(0.03, 0.62, 0.95, 0.6))
	draw_arc(center, radius, 0, TAU, 64, tint, 2, true)
	draw_arc(center, radius + 5, 0, TAU, 64, Color(0.82, 0.96, 1, 0.9), 1.5, true)
	for index in 4:
		var axis := Vector2.from_angle(index * PI * 0.5)
		draw_line(center + axis * (radius + 3), center + axis * (radius + 9), Color.WHITE, 2, true)
	var tip := center + direction * (radius + 31)
	var base := center + direction * (radius + 12)
	var side := direction.orthogonal() * 6
	draw_polyline(PackedVector2Array([base + side, tip, base - side, base + side]), Color.WHITE, 2.5, true)
