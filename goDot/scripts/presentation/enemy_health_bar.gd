extends Control

const StateBar = preload("res://scripts/presentation/health_state_bar.gd")

var elite := false
var hp_bar = StateBar.new()
var armor_bar = StateBar.new()
var value_label: Label
var icon: TextureRect
var fraction: float:
	get: return hp_bar.fraction
var follow_fraction: float:
	get: return hp_bar.follow_fraction
var shield_fraction: float:
	get: return armor_bar.fraction
var shield_overcap: float:
	get: return armor_bar.overcap_fraction

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(armor_bar)
	add_child(hp_bar)
	icon = DungeonStyle.picture(str(StateBar.source("elite").images["SheildStateBar/Box_Elite/Image"].resource), Vector2.ZERO)
	add_child(icon)
	value_label = DungeonStyle.label("", 14)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.clip_text = true
	value_label.add_theme_color_override("font_color", Color("ffffdf"))
	value_label.add_theme_color_override("font_outline_color", Color("131820"))
	value_label.add_theme_constant_override("outline_size", 3)
	add_child(value_label)
	configure(elite)

func configure(is_elite: bool) -> void:
	elite = is_elite
	size = Vector2(256, 48) if elite else Vector2(110, 30)
	if not is_instance_valid(icon): return
	var kind := "elite" if elite else "normal"
	armor_bar.configure(kind, "SheildStateBar")
	hp_bar.configure(kind, "SheildStateBar/HpStateBar")
	armor_bar.position = Vector2(24, 28) if elite else Vector2(7, 16)
	armor_bar.size = Vector2(228, 12) if elite else Vector2(96, 10)
	hp_bar.position = armor_bar.position + Vector2(2.5, 1.5)
	hp_bar.size = armor_bar.size - Vector2(5, 3)
	icon.visible = elite
	icon.position = Vector2(0, 18)
	icon.size = Vector2(34, 31)
	value_label.position = Vector2(0, 0)
	value_label.size = Vector2(size.x, 24)
	value_label.visible = not value_label.text.is_empty()

func update_actor(combat: DungeonCombat, delta: float) -> void:
	set_caption(combat.enemy_health_title())
	update_health(combat.health, combat.max_health, combat.armor, delta)

func set_caption(title: String) -> void:
	value_label.text = title
	value_label.visible = not title.is_empty()
	var font_size := 14
	var font := value_label.get_theme_font("font")
	while font_size > 8 and font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > value_label.size.x:
		font_size -= 1
	value_label.add_theme_font_size_override("font_size", font_size)

func update_health(current: float, maximum: float, armor: float, delta: float) -> void:
	hp_bar.update_health(current, maximum, delta)
	armor_bar.update_health(armor, maximum, delta)
