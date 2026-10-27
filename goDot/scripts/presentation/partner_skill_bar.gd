extends Control

signal skill_pressed(index: int)

const DIMENSIONS := Vector2(154, 118)
const BUTTON_SIZE := Vector2(68, 68)
const ICON_PATH := "res://assets/ui/partner_skills/"
var buttons: Array[DungeonTouchButton] = []
var energy_label: Label
var _cost_labels: Array[Label] = []

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = DIMENSIONS
	size = DIMENSIONS
	energy_label = DungeonStyle.label("", 16)
	energy_label.position = Vector2(0, 1)
	energy_label.size = Vector2(146, 23)
	energy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	energy_label.add_theme_color_override("font_color", Color("a4edff"))
	energy_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	energy_label.add_theme_constant_override("outline_size", 3)
	add_child(energy_label)
	for index in 2:
		var key := DungeonTouchButton.new()
		key.position = Vector2(index * 78, 28)
		key.size = BUTTON_SIZE
		key.custom_minimum_size = BUTTON_SIZE
		key.ring = DungeonStyle.texture("skill_circle_small")
		key.resource_color = Color("a4edff")
		key.pressed.connect(func(): skill_pressed.emit(index))
		add_child(key)
		buttons.append(key)
		var cost := DungeonStyle.label("", 14)
		cost.position = Vector2(index * 78, 98)
		cost.size = Vector2(68, 20)
		cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cost.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		cost.add_theme_constant_override("outline_size", 3)
		add_child(cost)
		_cost_labels.append(cost)
	hide()

func _ready() -> void:
	for key in buttons: key.mouse_filter = Control.MOUSE_FILTER_PASS

func update_state(state: Dictionary, suspended: bool = false, low_effects: bool = false) -> void:
	var slots: Array = state.get("slots", [])
	visible = not slots.is_empty()
	var maximum := maxf(0, float(state.get("max_sp", 0)))
	var energy := clampf(float(state.get("sp", 0)), 0, maximum)
	energy_label.text = "SP %d / %d" % [floori(energy), floori(maximum)]
	for index in buttons.size():
		var key := buttons[index]
		var equipped := index < slots.size() and slots[index] is Dictionary
		key.visible = equipped
		_cost_labels[index].visible = equipped
		key.readiness_suspended = suspended
		key.low_effects = low_effects
		if not equipped:
			key.disabled = true
			key.ready_full = false
			key.release(true)
			continue
		var slot: Dictionary = slots[index]
		var cost := maxf(0, float(slot.get("cost", 0)))
		key.art = _icon(str(slot.get("icon", "")))
		key.cooldown = maxf(0, float(slot.get("remaining", 0)))
		key.cooldown_total = maxf(0.001, float(slot.get("cooldown", 0)))
		key.resource_fraction = energy / maximum if maximum > 0 else 0.0
		key.unavailable = not bool(slot.get("ready", false))
		key.disabled = suspended or key.unavailable
		key.ready_full = not key.unavailable
		key.tooltip_text = "%s\nSP %d\n%s" % [DungeonCatalog.clean(slot.get("name", "")), ceili(cost), DungeonCatalog.clean(slot.get("description", ""))]
		_cost_labels[index].text = "SP %d" % ceili(cost)
		_cost_labels[index].modulate = Color.WHITE if energy >= cost else Color("e59a8a")
		if key.disabled: key.release(true)
		key.queue_redraw()

func _icon(source: String) -> Texture2D:
	var path := ICON_PATH + source + ".png"
	if ResourceLoader.exists(path): return DungeonStyle.texture(path)
	path = "res://assets/ui/role_character/panel/" + source + ".png"
	if ResourceLoader.exists(path): return DungeonStyle.texture(path)
	var texture := DungeonStyle.texture(source)
	return texture if texture else DungeonStyle.texture("sprite_conversation_monstersupport")
