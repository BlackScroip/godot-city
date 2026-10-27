class_name DungeonStyle
extends RefCounted

const GOLD = Color("d9bb72")
const INK = Color("101e23")
const TEXT = Color("f3f1e5")
static var _textures: Dictionary = {}
static var _map: Dictionary = {}
static var missing: Dictionary = {}
static var _last_render_settings := ""
static var _font: Font
const SETTINGS_EFFECTS = preload("res://scripts/presentation/settings_effects.gd")
const AUDIO_BUSES = {"volume_master": "Master", "volume_music": "Music", "volume_effects": "Effects", "volume_voice": "Voice"}

static func read_options() -> Dictionary:
	return DungeonSettings.read_options()

static func set_option(key: String, value: Variant) -> void:
	DungeonSettings.set_option(key, value)

static func apply_audio_options(settings: Dictionary) -> void:
	for key in AUDIO_BUSES:
		var bus_name: String = AUDIO_BUSES[key]
		var index := AudioServer.get_bus_index(bus_name)
		if index < 0:
			AudioServer.add_bus()
			index = AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.set_bus_send(index, "Master")
		var gain := clampf(float(settings.get(key, 100)) / 100.0, 0.0, 1.0)
		AudioServer.set_bus_mute(index, gain <= 0.0)
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(0.0001, gain)))

static func audio_bus(name: String, layer: Dictionary = {}, category := "") -> StringName:
	if category == "voice": return &"Voice"
	if category == "music": return &"Music"
	var recovered := str(layer.get("bus", layer.get("category", layer.get("mixer", "")))).to_lower()
	if "voice" in recovered or "voice" in name.to_lower(): return &"Voice"
	if "music" in recovered or name.to_lower().begins_with("audio_music_"): return &"Music"
	return &"Effects"

static func apply_options(world: Node3D) -> void:
	var settings = read_options()
	apply_audio_options(settings)
	Engine.max_fps = clampi(int(settings.fps), 0, 120)
	var viewport := world.get_viewport()
	viewport.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X][clampi(int(settings.quality), 0, 3)]
	var dimensions := Vector2i(viewport.get_visible_rect().size)
	var base_scale := render_scale(dimensions, int(settings.quality), OS.has_feature("mobile"))
	viewport.scaling_3d_scale = base_scale
	viewport.mesh_lod_threshold = [4.0, 2.0, 1.0][clampi(int(settings.get("scene_detail", 2)), 0, 2)]
	for node in world.find_children("*", "DirectionalLight3D", true, false):
		node.shadow_enabled = bool(settings.shadows)
	var runtime := world.get_node_or_null("SettingsEffects")
	if runtime == null:
		runtime = SETTINGS_EFFECTS.new()
		runtime.name = "SettingsEffects"
		world.add_child(runtime)
	runtime.apply_settings(settings, world, base_scale)
	if OS.is_debug_build():
		var applied := JSON.stringify({"renderer": RenderingServer.get_current_rendering_method(),
			"window": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
			"scale_3d": viewport.scaling_3d_scale, "msaa_3d": viewport.msaa_3d,
			"quality": settings.quality, "shadows": settings.shadows, "fps_cap": Engine.max_fps})
		if applied != _last_render_settings:
			_last_render_settings = applied
			print("DUNGEON_RENDER_SETTINGS ", applied)

static func render_scale(dimensions: Vector2i, quality: int, mobile: bool) -> float:
	if not mobile or quality >= 2: return 1.0
	# Limit only 3D fill cost on high-resolution phones; the HUD stays native.
	var limit := 1280.0 if quality == 0 else 1600.0
	return clampf(limit / maxf(1.0, maxf(dimensions.x, dimensions.y)), 0.5, 1.0)

static func texture(key: String) -> Texture2D:
	if key.is_empty(): return null
	if key.begins_with("loot:") or key.begins_with("material:"):
		return preload("res://scripts/presentation/item_art.gd").texture(int(key.get_slice(":", 1)), key.begins_with("material:"))
	if _textures.has(key): return _textures[key]
	if _map.is_empty() and FileAccess.file_exists("res://assets/ui/resource_map.json"):
		_map = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/resource_map.json"))
		if FileAccess.file_exists("res://assets/ui/camp/resource_map.json"):
			var camp_icons = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/camp/resource_map.json"))
			if camp_icons is Dictionary: _map.merge(camp_icons, true)
		if FileAccess.file_exists("res://assets/ui/hud_navigation/resource_map.json"):
			var navigation_icons = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/hud_navigation/resource_map.json"))
			if navigation_icons is Dictionary: _map.merge(navigation_icons, true)
		if FileAccess.file_exists("res://assets/ui/talent_view/resource_map.json"):
			var talent_icons = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/talent_view/resource_map.json"))
			if talent_icons is Dictionary: _map.merge(talent_icons, false)
		_map["menu_comment"] = _map.get("Button_GoComment", "")
		_map["menu_meal_buffs"] = _map.get("猫饭", "")
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

static func artwork_box(key: String, margin: int, tint := Color.WHITE) -> StyleBox:
	var art := texture(key)
	if not art: return box(INK, GOLD)
	var result = StyleBoxTexture.new()
	result.texture = art
	result.modulate_color = tint
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		result.set_texture_margin(side, margin)
		result.set_content_margin(side, 10)
	return result

static func theme() -> Theme:
	var result = Theme.new()
	result.default_font_size = 19
	result.default_font = multilingual_font()
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

static func multilingual_font() -> Font:
	if _font: return _font
	var primary := load("res://assets/fonts/default.otf").duplicate() as FontFile
	var korean := FontVariation.new()
	korean.base_font = preload("res://assets/fonts/NotoSansKR.ttf")
	korean.variation_opentype = {"wght": 400.0}
	primary.fallbacks = [korean, preload("res://assets/fonts/NotoSansThai.ttf")]
	_font = primary
	return _font

static func label(text: String, font_size := 19) -> Label:
	var result = Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", font_size)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result

static func fit_label_text(value: Label, maximum: int, minimum := 12) -> void:
	if value.size.x <= 1: return
	var font := value.get_theme_font("font")
	var translated := DungeonLocale.text(value.text)
	var chosen := maximum
	while chosen > minimum and font.get_string_size(translated, HORIZONTAL_ALIGNMENT_LEFT, -1, chosen).x > value.size.x - 4:
		chosen -= 1
	if value.get_theme_font_size("font_size") != chosen:
		value.add_theme_font_size_override("font_size", chosen)

static func fit_button_text(value: Button, maximum: int, minimum := 12) -> void:
	if value.size.x <= 1: return
	var style := value.get_theme_stylebox("normal")
	var available := value.size.x - style.get_content_margin(SIDE_LEFT) - style.get_content_margin(SIDE_RIGHT) - 4
	if value.icon and value.vertical_icon_alignment == VERTICAL_ALIGNMENT_CENTER:
		var icon_width := float(value.icon.get_width())
		var limit := value.get_theme_constant("icon_max_width")
		if limit > 0: icon_width = minf(icon_width, limit)
		available -= icon_width + value.get_theme_constant("h_separation")
	var font := value.get_theme_font("font")
	var translated := DungeonLocale.text(value.text)
	var chosen := maximum
	while chosen > minimum and font.get_string_size(translated, HORIZONTAL_ALIGNMENT_LEFT, -1, chosen).x > available:
		chosen -= 1
	if value.get_theme_font_size("font_size") != chosen:
		value.add_theme_font_size_override("font_size", chosen)

static func localize_artwork_title(art: TextureRect, source: String, font_size := 44, color := TEXT) -> Label:
	var caption := label(source, font_size)
	caption.name = "LocalizedArtworkText"
	caption.add_theme_font_override("font", multilingual_font())
	caption.add_theme_color_override("font_color", color)
	caption.add_theme_color_override("font_outline_color", Color("423a2a"))
	caption.add_theme_constant_override("outline_size", 2)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.clip_text = true
	caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.add_child(caption)
	caption.resized.connect(func(): fit_label_text(caption, font_size))
	if DungeonLocale.current_locale() != "zh_CN" or art.texture == null:
		art.texture = null
	else:
		caption.hide()
	fit_label_text(caption, font_size)
	return caption

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
