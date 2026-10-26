extends PanelContainer

var icon: TextureRect
var name_label: Label
var description_label: Label
var close_button: Button
var current_key := ""
var _dismissed_key := ""
var _content: Control
var _separator: HSeparator
var _scroll: ScrollContainer

func _init() -> void:
	name = "GroundItemDescription"
	mouse_filter = Control.MOUSE_FILTER_PASS
	var frame := DungeonStyle.box(Color(0.025, 0.075, 0.065, 0.82), Color("a99d71"), 2)
	frame.set_corner_radius_all(18)
	frame.set_content_margin_all(12)
	add_theme_stylebox_override("panel", frame)
	_content = Control.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_content)
	name_label = DungeonStyle.label("", 20)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_content.add_child(name_label)
	_separator = HSeparator.new()
	var line := StyleBoxLine.new()
	line.color = Color("b9aa70")
	line.thickness = 1
	_separator.add_theme_stylebox_override("separator", line)
	_separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_separator)
	icon = DungeonStyle.picture("", Vector2.ZERO)
	_content.add_child(icon)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_content.add_child(_scroll)
	description_label = DungeonStyle.label("", 18)
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(description_label)
	close_button = Button.new()
	close_button.name = "CloseGroundItemDescription"
	close_button.text = "×"
	close_button.tooltip_text = "关闭物品说明"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close_button.add_theme_font_size_override("font_size", 26)
	close_button.add_theme_color_override("font_color", Color("f36b63"))
	for state in ["normal", "hover", "pressed", "focus"]:
		var badge := DungeonStyle.box(Color("4e4734") if state != "pressed" else Color("302b21"), Color("b6a578"), 1)
		badge.set_corner_radius_all(18)
		badge.set_content_margin_all(0)
		close_button.add_theme_stylebox_override(state, badge)
	close_button.pressed.connect(dismiss)
	_content.add_child(close_button)
	hide()

func bind(entry: Dictionary, systems: RefCounted, blocked := false) -> void:
	var key := _entry_key(entry)
	if key != current_key:
		current_key = key
		_dismissed_key = ""
		_scroll.scroll_vertical = 0
	visible = not blocked and not key.is_empty() and key != _dismissed_key
	if not visible: return
	var material := bool(entry.get("material", false))
	icon.texture = DungeonItemArt.ground_texture(int(entry.id), material)
	name_label.text = DungeonCatalog.clean(systems.material_name(entry.id) if material else systems.loot_name(entry.id))
	description_label.text = "数量：%d" % int(entry.get("amount", 1)) if material else DungeonCatalog.clean(systems.loot_description(entry.id))
	if entry.has("altar"):
		name_label.text = "精灵祭坛"
		description_label.text = "选择一位同行的精灵"

func dismiss() -> void:
	_dismissed_key = current_key
	hide()

func _entry_key(entry: Dictionary) -> String:
	if entry.is_empty(): return ""
	var visual: Variant = entry.get("visual")
	if is_instance_valid(visual): return str(visual.get_instance_id())
	return "%s:%s:%s" % [entry.get("material", false), entry.get("id", 0), entry.get("position", Vector3.ZERO)]

func layout(viewport: Vector2) -> void:
	var compact := viewport.y < 560.0
	var dimensions := Vector2(224, 146) if compact else Vector2(300, 196)
	dimensions.x = minf(dimensions.x, maxf(160.0, viewport.x - 32.0))
	size = dimensions
	position = Vector2(minf(viewport.x * 0.675, viewport.x - dimensions.x - 20.0), viewport.y * 0.245)
	position.y = clampf(position.y, 24.0, maxf(24.0, viewport.y - dimensions.y - 20.0))
	var inner := dimensions - Vector2(24, 24)
	_content.custom_minimum_size = Vector2.ZERO
	name_label.position = Vector2(0, 2)
	name_label.size = Vector2(inner.x, 28)
	name_label.add_theme_font_size_override("font_size", 16 if compact else 20)
	_separator.position = Vector2(0, 34)
	_separator.size = Vector2(inner.x, 3)
	icon.position = Vector2(0, 45)
	icon.size = Vector2(22, 22)
	_scroll.position = Vector2(28, 43)
	description_label.custom_minimum_size.x = inner.x - 38
	description_label.add_theme_font_size_override("font_size", 15 if compact else 18)
	_scroll.size = Vector2(inner.x - 28, inner.y - 45)
	close_button.position = Vector2(inner.x - 13, -22)
	close_button.size = Vector2(34, 34)
