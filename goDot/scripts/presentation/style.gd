class_name DungeonStyle
extends RefCounted

const GOLD = Color("d9bb72")
const INK = Color("101e23")
const TEXT = Color("f3f1e5")
static var _textures: Dictionary = {}
static var _map: Dictionary = {}
static var missing: Dictionary = {}
static var options: Dictionary = {"quality": 1, "shadows": true, "fps": 60}
static var _options_loaded := false

static func read_options() -> Dictionary:
	if not _options_loaded:
		var config = ConfigFile.new()
		if config.load("user://presentation.cfg") == OK:
			for key in options: options[key] = config.get_value("visual", key, options[key])
		_options_loaded = true
	return options

static func set_option(key: String, value: Variant) -> void:
	read_options()
	if not options.has(key): return
	options[key] = value
	var config = ConfigFile.new()
	for name in options: config.set_value("visual", name, options[name])
	config.save("user://presentation.cfg")

static func apply_options(world: Node3D) -> void:
	var settings = read_options()
	Engine.max_fps = clampi(int(settings.fps), 0, 120)
	world.get_viewport().msaa_3d = Viewport.MSAA_DISABLED if int(settings.quality) == 0 else Viewport.MSAA_2X if int(settings.quality) == 1 else Viewport.MSAA_4X
	for node in world.get_children():
		if node is DirectionalLight3D: node.shadow_enabled = bool(settings.shadows)

static func texture(key: String) -> Texture2D:
	if key.is_empty(): return null
	if key.begins_with("loot:") or key.begins_with("material:"):
		return preload("res://scripts/presentation/item_art.gd").texture(int(key.get_slice(":", 1)), key.begins_with("material:"))
	if _textures.has(key): return _textures[key]
	if _map.is_empty() and FileAccess.file_exists("res://assets/ui/resource_map.json"):
		_map = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/resource_map.json"))
	var path = str(_map.get(key, "res://assets/ui/" + key + ".png"))
	if key.begins_with("res://"): path = key
	if not ResourceLoader.exists(path):
		missing[key] = true
		return null
	var result = load(path) as Texture2D
	_textures[key] = result
	return result

static func box(color: Color, border := Color.TRANSPARENT, width := 1) -> StyleBoxFlat:
	var result = StyleBoxFlat.new()
	result.bg_color = color
	result.border_color = border
	result.set_border_width_all(width)
	result.set_corner_radius_all(3)
	result.set_content_margin_all(12)
	return result

static func theme() -> Theme:
	var result = Theme.new()
	result.default_font_size = 19
	for path in ["res://assets/fonts/default.otf", "res://assets/fonts/default.ttf"]:
		if ResourceLoader.exists(path):
			result.default_font = load(path)
			break
	result.set_color("font_color", "Label", TEXT)
	result.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.8))
	result.set_constant("shadow_offset_x", "Label", 1)
	result.set_constant("shadow_offset_y", "Label", 2)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var fill = Color("24343a")
		var line = Color("766b4e")
		if state == "hover": fill = Color("39494a"); line = GOLD
		if state == "pressed": fill = Color("514b34"); line = GOLD
		if state == "disabled": fill = Color("20272a"); line = Color("424b4b")
		if state == "focus": fill = Color.TRANSPARENT; line = GOLD
		result.set_stylebox(state, "Button", box(fill, line))
	result.set_color("font_color", "Button", TEXT)
	result.set_color("font_disabled_color", "Button", Color("798482"))
	result.set_stylebox("panel", "PanelContainer", box(INK, Color("81734f")))
	result.set_stylebox("background", "ProgressBar", box(Color("1c2925")))
	result.set_stylebox("fill", "ProgressBar", box(Color("77ba44")))
	return result

static func label(text: String, font_size := 19) -> Label:
	var result = Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", font_size)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result

static func picture(key: String, dimensions: Vector2) -> TextureRect:
	var result = TextureRect.new()
	result.texture = texture(key)
	result.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	result.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	result.custom_minimum_size = dimensions
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result

static func panel() -> StyleBox:
	var art = texture("res://assets/art_generated/panel-v1.png")
	if not art: return box(INK, GOLD)
	var result = StyleBoxTexture.new()
	result.texture = art
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		result.set_texture_margin(side, 112)
		result.set_content_margin(side, 62)
	result.modulate_color = Color(1, 1, 1, 0.98)
	return result
