extends Control

const HealthBar = preload("res://scripts/presentation/enemy_health_bar.gd")
var bars: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func update_actors(actors: Array, camera: Camera3D, delta: float) -> void:
	var active: Dictionary = {}
	if not is_instance_valid(camera):
		clear()
		return
	var factor := clampf(minf(size.x / 1280.0, size.y / 720.0), 0.72, 1.2)
	var screen := camera.get_viewport().get_visible_rect().size
	for actor in actors:
		if not is_instance_valid(actor) or actor.is_player or actor.dead or actor.combat == null: continue
		if actor.combat.health <= 0 or not actor.is_visible_in_tree(): continue
		if is_instance_valid(actor.visual) and not actor.visual.visible: continue
		# Bosses retain their separate top-of-screen readout.
		if actor.combat.enemy.get("rank", "") == "Boss": continue
		var key: int = actor.get_instance_id()
		active[key] = true
		if not bars.has(key):
			var health_bar = HealthBar.new()
			health_bar.elite = actor.combat.enemy.get("rank", "") == "Elite"
			add_child(health_bar)
			bars[key] = health_bar
		var bar: Control = bars[key]
		bar.update_health(actor.combat.health, actor.combat.max_health, actor.combat.shield, delta)
		var bounds: AABB = actor.impact_bounds
		var head: Vector3 = actor.get_global_transform_interpolated() * Vector3(bounds.get_center().x, bounds.end.y + 0.2, bounds.get_center().z)
		bar.visible = not camera.is_position_behind(head)
		if not bar.visible: continue
		var projected := camera.unproject_position(head) * size / screen
		bar.scale = Vector2.ONE * factor
		bar.position = projected - Vector2(bar.size.x * 0.5, bar.size.y) * factor
		bar.visible = Rect2(Vector2.ZERO, size).intersects(Rect2(bar.position, bar.size * factor))
	for key in bars.keys():
		if not active.has(key):
			bars[key].queue_free()
			bars.erase(key)

func clear() -> void:
	for bar in bars.values(): bar.queue_free()
	bars.clear()
