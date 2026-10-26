extends Control

const HIDE_SECONDS := 0.3
const DPS_UPDATE_INTERVAL := 0.2
const STAGE_COLORS := [Color("fff0b9"), Color("ffcb86"), Color("ff9ead"), Color("d6c5ff")]

var hits := DungeonStyle.label("0", 52)
var total := DungeonStyle.label("0", 30)
var rate := DungeonStyle.label("0", 30)
var boss_name := DungeonStyle.label("", 22)
var stats := Control.new()
var boss := Control.new()
var bar := ProgressBar.new()
var boss_health := DungeonStyle.label("", 15)
var enemy_health = preload("res://scripts/presentation/enemy_health_overlay.gd").new()
var combo_bar := TextureProgressBar.new()
var hit_tail := TextureRect.new()
var description := TextureRect.new()
var stage := -1
var _resources: Dictionary = {}
var _last_hits := 0
var _last_sequence := -1
var _hiding := false
var _hide_elapsed := 0.0
var _pulse_remaining := 0.0
var _dps_remaining := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(enemy_health)
	for group in [stats, boss]:
		group.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(group)
	_resources = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/battle_readout/resource_map.json"))
	stats.size = Vector2(184, 270)
	stats.add_child(hits)
	hits.position = Vector2(4, -8)
	hits.size = Vector2(116, 72)
	hits.clip_text = true
	hits.pivot_offset = Vector2(110, 56)
	hits.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hits.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_picture(hit_tail, Vector2(128, 38), Vector2(46, 18))
	_picture(description, Vector2(10, 86), Vector2(145, 24))
	stats.add_child(combo_bar)
	combo_bar.position = Vector2(10, 66)
	combo_bar.size = Vector2(154, 12)
	combo_bar.max_value = 1.0
	combo_bar.step = 0.0
	combo_bar.nine_patch_stretch = true
	combo_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	combo_bar.texture_under = DungeonStyle.texture("res://assets/ui/battle_readout/6eb56aabe391a64d.png")
	for entry in [["总伤害", 122, total, "da335108756127be"], ["秒伤", 198, rate, "8b81fd8bcf1de4a3"]]:
		var icon := TextureRect.new()
		_picture(icon, Vector2(10, int(entry[1]) + 3), Vector2(22, 20))
		icon.texture = DungeonStyle.texture("res://assets/ui/battle_readout/" + str(entry[3]) + ".png")
		var title = DungeonStyle.label(str(entry[0]), 21)
		title.position = Vector2(38, entry[1])
		stats.add_child(title)
		var value: Label = entry[2]
		value.position = Vector2(12, int(entry[1]) + 32)
		value.size = Vector2(164, 40)
		value.clip_text = true
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		stats.add_child(value)
	stats.hide()
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

func update_values(tally: RefCounted, target: DungeonActor, title: String, delta: float = 0.0) -> void:
	_update_stats(tally, maxf(0.0, delta))
	boss.visible = is_instance_valid(target) and not target.dead and target.combat != null and target.combat.health > 0 and target.is_visible_in_tree()
	if boss.visible:
		boss_name.text = title
		bar.max_value = target.combat.max_health
		bar.value = target.combat.health
		boss_health.text = "%d / %d" % [ceili(target.combat.health), ceili(target.combat.max_health)]

func _update_stats(tally: RefCounted, delta: float) -> void:
	if tally.hits == 0:
		stats.hide()
		_hiding = false
		_last_hits = 0
		_last_sequence = -1
		return
	if tally.combo_hits > 0 and tally.combo_remaining > 0.0:
		var fresh: bool = not stats.visible or _hiding or _last_sequence != tally.combo_sequence
		var changed: bool = fresh or _last_hits != tally.combo_hits
		stats.show()
		stats.modulate.a = 1.0
		_hiding = false
		var next_stage := mini(3, int(tally.combo_hits / 10))
		if next_stage != stage:
			stage = next_stage
			hit_tail.texture = _art("tail_hits_%d" % (stage + 1))
			description.texture = _art("word_hits_%d" % (stage + 1))
			combo_bar.texture_progress = _art("bar_hits_%d" % (stage + 1))
			hits.add_theme_color_override("font_color", STAGE_COLORS[stage])
		if changed:
			hits.text = str(tally.combo_hits)
			_fit_value(hits, 52)
			total.text = str(roundi(tally.combo_damage))
			_fit_value(total)
			_pulse_remaining = 0.1
			_last_hits = tally.combo_hits
			_last_sequence = tally.combo_sequence
		_dps_remaining -= delta
		if fresh or _dps_remaining <= 0.0:
			rate.text = str(roundi(tally.combo_dps()))
			_fit_value(rate)
			_dps_remaining = DPS_UPDATE_INTERVAL
		var fraction: float = clampf(tally.combo_remaining / tally.COMBO_KEEP_SECONDS, 0.0, 1.0)
		combo_bar.value = fraction if fresh or combo_bar.value > fraction else move_toward(combo_bar.value, fraction, 4.5 * delta)
	elif stats.visible:
		# Preserve the final numbers throughout the source prefab's fade-out.
		if not _hiding:
			_hiding = true
			_hide_elapsed = 0.0
			combo_bar.value = 0.0
		_hide_elapsed = minf(HIDE_SECONDS, _hide_elapsed + delta)
		stats.modulate.a = pow(1.0 - _hide_elapsed / HIDE_SECONDS, 2.0)
		if _hide_elapsed >= HIDE_SECONDS: stats.hide()
	_pulse_remaining = maxf(0.0, _pulse_remaining - delta)
	hits.scale = Vector2.ONE * (1.0 + 0.39 * pow(_pulse_remaining / 0.1, 2.0))

func _fit_value(value: Label, maximum_size: int = 30) -> void:
	var font := value.get_theme_font("font")
	var font_size := maximum_size
	while font_size > 8 and font.get_string_size(value.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > value.size.x:
		font_size -= 1
	value.add_theme_font_size_override("font_size", font_size)

func _picture(picture: TextureRect, origin: Vector2, dimensions: Vector2) -> void:
	picture.position = origin
	picture.size = dimensions
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats.add_child(picture)

func _art(key: String) -> Texture2D:
	return DungeonStyle.texture(str(_resources.get(key, "")))

func update_enemies(actors: Array, camera: Camera3D, delta: float) -> void:
	enemy_health.update_actors(actors, camera, delta)
