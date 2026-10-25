extends Control

var hits := DungeonStyle.label("0", 52)
var total := DungeonStyle.label("0", 30)
var rate := DungeonStyle.label("0", 30)
var boss_name := DungeonStyle.label("", 22)
var stats := Control.new()
var boss := Control.new()
var bar := ProgressBar.new()
var boss_health := DungeonStyle.label("", 15)
var enemy_health = preload("res://scripts/presentation/enemy_health_overlay.gd").new()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(enemy_health)
	for group in [stats, boss]:
		group.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(group)
	stats.add_child(hits)
	hits.position = Vector2(54, 0)
	var caption = DungeonStyle.label("HITS", 17)
	caption.position = Vector2(112, 38)
	stats.add_child(caption)
	var separator := HSeparator.new()
	separator.position = Vector2(24, 68)
	separator.size.x = 126
	stats.add_child(separator)
	for entry in [["总伤害", 88, total], ["秒伤", 168, rate]]:
		var title = DungeonStyle.label(str(entry[0]), 23)
		title.position = Vector2(14, entry[1])
		stats.add_child(title)
		var value: Label = entry[2]
		value.position = Vector2(12, int(entry[1]) + 32)
		value.size = Vector2(150, 42)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		stats.add_child(value)
	boss.add_child(boss_name)
	boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_name.size = Vector2(440, 32)
	boss_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	boss.add_child(bar)
	bar.position = Vector2(0, 36)
	bar.size = Vector2(440, 22)
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("background", DungeonStyle.box(Color("262521"), Color("fff4c2"), 2))
	bar.add_theme_stylebox_override("fill", DungeonStyle.box(Color("ff1607"), Color("ffb642"), 1))
	boss.add_child(boss_health)
	boss_health.position = Vector2(0, 59)
	boss_health.size = Vector2(440, 22)
	boss_health.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_health.add_theme_color_override("font_outline_color", Color("101820"))
	boss_health.add_theme_constant_override("outline_size", 4)
	boss.hide()
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	var factor := minf(1.0, minf(size.x / 1280.0, size.y / 720.0))
	stats.scale = Vector2.ONE * factor
	stats.position = Vector2(58 * factor, size.y * 0.24)
	boss.scale = Vector2.ONE * factor
	boss.position = Vector2(size.x * 0.5 - 220 * factor, 32 * factor)

func update_values(tally: RefCounted, target: DungeonActor, title: String) -> void:
	hits.text = str(tally.hits)
	total.text = str(roundi(tally.damage))
	rate.text = str(roundi(tally.dps()))
	boss.visible = is_instance_valid(target) and not target.dead and target.combat != null and target.combat.health > 0 and target.is_visible_in_tree()
	if boss.visible:
		boss_name.text = title
		bar.max_value = target.combat.max_health
		bar.value = target.combat.health
		boss_health.text = "%d / %d" % [ceili(target.combat.health), ceili(target.combat.max_health)]

func update_enemies(actors: Array, camera: Camera3D, delta: float) -> void:
	enemy_health.update_actors(actors, camera, delta)
