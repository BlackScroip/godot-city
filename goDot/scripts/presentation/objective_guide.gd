extends Control

const FRAME = preload("res://assets/ui/battle_guide/a41506fc3ce34bb6.png")
const DISK = preload("res://assets/ui/battle_guide/8fa4213008a292a6.png")
const NEEDLE = preload("res://assets/ui/battle_guide/efda071a81a2db5e.png")
const FADE_SECONDS := 0.3
const DISK_TINT := Color(1.5, 1.5, 1.5, 1.0)

var center := Vector2.ZERO
var direction := Vector2.UP
var art_scale := 1.0
var fade := 0.0
var target_id := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hide()

func _process(delta: float) -> void:
	if not visible: return
	fade = minf(1.0, fade + maxf(0, delta) / FADE_SECONDS)
	modulate.a = fade

func clear_target() -> void:
	target_id = ""
	fade = 0.0
	hide()

func update_target(world: Node3D, blocked: bool) -> void:
	if blocked or not world.interactions or not is_instance_valid(world.player) or not is_instance_valid(world.camera):
		clear_target()
		return
	var target: Dictionary = {}
	var best := INF
	for item in world.interactions._items.values():
		if str(item.marker.get("Type", "")) not in ["EEUT_StageChangeDoor", "EEUT_Protal"]: continue
		if not item.state.enabled or item.state.broken or item.state.opened or item.state.used: continue
		if not is_instance_valid(item.visual) or not item.visual.is_visible_in_tree(): continue
		var point: Vector3 = world.environment_root.to_global(item.position)
		var distance: float = world.player.global_position.distance_squared_to(point)
		if distance < best:
			best = distance
			target = item
	if target.is_empty():
		clear_target()
		return
	var point: Vector3 = world.environment_root.to_global(target.position)
	if point.length_squared() < 0.0000000001:
		clear_target()
		return
	var camera: Camera3D = world.camera
	var viewport_size := get_viewport_rect().size
	var screen_point := camera.unproject_position(point)
	var behind := camera.is_position_behind(point)
	if str(target.id) != target_id: clear_target()
	update_screen_target(screen_point * size / viewport_size, size, behind)
	if visible: target_id = str(target.id)

func update_screen_target(point: Vector2, screen: Vector2, behind := false) -> void:
	if screen.x <= 0 or screen.y <= 0 or not point.is_finite():
		clear_target()
		return
	var normalized := point / screen
	# The original guide appears only outside the central 80% of the viewport.
	if not behind and normalized.x >= 0.1 and normalized.x <= 0.9 and normalized.y >= 0.1 and normalized.y <= 0.9:
		clear_target()
		return
	var offset := point - screen * 0.5
	if behind: offset = -offset
	if offset.length_squared() < 0.0001: offset = Vector2.DOWN
	direction = offset.normalized()
	art_scale = minf(1.0, minf(screen.x / 1280.0, screen.y / 720.0))
	center = screen * 0.5 + offset.limit_length(screen.y * 0.35)
	var margin := Vector2.ONE * 110.0 * art_scale
	center = center.clamp(margin, (screen - margin).max(margin))
	if not visible:
		fade = 0.0
		modulate.a = 0.0
	show()
	queue_redraw()

func _draw() -> void:
	draw_texture_rect(DISK, Rect2(center - Vector2.ONE * 40 * art_scale, Vector2.ONE * 80 * art_scale), false, DISK_TINT)
	draw_texture_rect(FRAME, Rect2(center - Vector2.ONE * 54.4 * art_scale, Vector2.ONE * 108.8 * art_scale), false)
	draw_set_transform(center, direction.angle() + PI * 0.5, Vector2.ONE * art_scale)
	draw_texture_rect(NEEDLE, Rect2(Vector2(-17.2, -107), Vector2(34.4, 64)), false)
	draw_set_transform(Vector2.ZERO)
