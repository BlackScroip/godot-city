extends Control

const SOURCE := "res://assets/ui/boss_intro/catalog.json"

var catalog: Dictionary = {}
var nodes: Dictionary = {}
var _drawables: Dictionary = {}
var _values: Dictionary = {}
var _paths: Array = []
var elapsed := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	catalog = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
	_paths = catalog.nodes.keys()
	_paths.sort_custom(func(a, b):
		var depth_a := 0 if str(a).is_empty() else str(a).count("/") + 1
		var depth_b := 0 if str(b).is_empty() else str(b).count("/") + 1
		return depth_a < depth_b if depth_a != depth_b else int(catalog.nodes[a].get("sibling_index", 0)) < int(catalog.nodes[b].get("sibling_index", 0)))
	for path in _paths:
		var record: Dictionary = catalog.nodes[path]
		var node := Control.new()
		node.name = str(path).get_file() if not str(path).is_empty() else "Banner"
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var parent: Control = nodes.get(str(record.get("parent", "")), self)
		parent.add_child(node)
		nodes[path] = node
		if record.has("image"):
			var image: Dictionary = record.image
			var picture: Control
			if str(image.get("texture", "")).is_empty():
				picture = ColorRect.new()
			elif int(image.get("type", 0)) == 3:
				var progress := TextureProgressBar.new()
				progress.texture_progress = load(str(image.texture))
				progress.nine_patch_stretch = true
				progress.max_value = 1.0
				progress.step = 0.0
				picture = progress
			elif int(image.get("type", 0)) == 1:
				var sliced := NinePatchRect.new()
				sliced.texture = load(str(image.texture))
				for sprite in catalog.sprites.values():
					if str(sprite.texture) != str(image.texture): continue
					var border: Dictionary = sprite.border
					var multiplier := maxf(0.001, float(image.get("pixels_per_unit_multiplier", 1)))
					sliced.patch_margin_left = int(float(border.x) / multiplier)
					sliced.patch_margin_right = int(float(border.z) / multiplier)
					sliced.patch_margin_top = int(float(border.w) / multiplier)
					sliced.patch_margin_bottom = int(float(border.y) / multiplier)
				picture = sliced
			else:
				var texture := TextureRect.new()
				texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				texture.texture = load(str(image.texture))
				if bool(image.get("preserve_aspect", false)): texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				picture = texture
			picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
			picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			picture.self_modulate = _color(image.get("color", [1, 1, 1, 1]))
			node.add_child(picture)
			_drawables[path] = picture
		elif record.has("text"):
			var label := Label.new()
			label.text = str(record.text.get("text", ""))
			var font_path := str(record.text.get("font", {}).get("resource", ""))
			if not font_path.is_empty(): label.add_theme_font_override("font", load(font_path))
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if int(record.text.get("horizontal_alignment", 2)) == 1 else HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			label.add_theme_color_override("font_color", _color(record.text.get("color", [1, 1, 1, 1])))
			label.add_theme_constant_override("outline_size", 0)
			label.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
			var style: Dictionary = record.text.get("style", {})
			if "UNDERLAY_ON" in style.get("valid_keywords", []):
				label.add_theme_color_override("font_shadow_color", _color(style.get("underlay_color", [0, 0, 0, 0])))
				label.add_theme_constant_override("shadow_offset_x", 2)
				label.add_theme_constant_override("shadow_offset_y", 2)
			node.add_child(label)
			_drawables[path] = label
	resized.connect(_layout)
	sample(0.0)

func set_boss_name(value: String) -> void:
	for path in _drawables:
		var drawable = _drawables[path]
		if drawable is Label and str(path).get_file() in ["Image_Title", "Text_EnemyName"]:
			drawable.text = value
	_layout()

func sample(time: float) -> void:
	if catalog.is_empty(): return
	elapsed = clampf(time, 0.0, float(catalog.duration))
	_values.clear()
	for track in catalog.tracks:
		var path := str(track.path)
		if not _values.has(path): _values[path] = {}
		if str(track.property) == "m_LocalScale":
			for axis in ["x", "y"]:
				var scalar: Dictionary = track.duplicate(true)
				for key in scalar.keys:
					for field in ["value", "inSlope", "outSlope"]: key[field] = key[field][axis]
				_values[path]["m_LocalScale." + axis] = _sample_track(scalar, elapsed)
		else: _values[path][str(track.property)] = _sample_track(track, elapsed)
	_layout()

static func _sample_track(track: Dictionary, time: float) -> float:
	var keys: Array = track.keys
	if keys.is_empty(): return 0.0
	if time <= float(keys[0].time): return float(keys[0].value)
	for index in range(1, keys.size()):
		var right: Dictionary = keys[index]
		if time >= float(right.time): continue
		var left: Dictionary = keys[index - 1]
		if str(track.get("property", "")) == "m_IsActive" or str(track.get("kind", "")) in ["discrete", "step"]: return float(left.value)
		var span := float(right.time) - float(left.time)
		var fraction := (time - float(left.time)) / span
		var outgoing := float(left.get("outSlope", 0))
		var incoming := float(right.get("inSlope", 0))
		if not is_finite(outgoing) or not is_finite(incoming): return float(left.value)
		var squared := fraction * fraction
		var cubed := squared * fraction
		return (2 * cubed - 3 * squared + 1) * float(left.value) + (cubed - 2 * squared + fraction) * span * outgoing + (-2 * cubed + 3 * squared) * float(right.value) + (cubed - squared) * span * incoming
	return float(keys.back().value)

func _layout() -> void:
	var vertical_offsets: Dictionary = {}
	for path in _paths:
		var record: Dictionary = catalog.nodes[path]
		var node: Control = nodes[path]
		var parent := node.get_parent() as Control
		var rect: Dictionary = record.rect
		var values: Dictionary = _values.get(path, {})
		var low := _vector(rect.get("anchor_min", [0.5, 0.5]))
		var high := _vector(rect.get("anchor_max", [0.5, 0.5]))
		var pivot := _vector(rect.get("pivot", [0.5, 0.5]))
		var extent := _vector(rect.get("size_delta", [0, 0]))
		var anchored := _vector(rect.get("anchored_position", [0, 0]))
		anchored.x = float(values.get("m_AnchoredPosition.x", anchored.x))
		anchored.y = float(values.get("m_AnchoredPosition.y", anchored.y))
		extent.x = float(values.get("m_SizeDelta.x", extent.x))
		extent.y = float(values.get("m_SizeDelta.y", extent.y))
		node.size = (parent.size * (high - low) + extent).max(Vector2.ZERO)
		node.pivot_offset = node.size * Vector2(pivot.x, 1.0 - pivot.y)
		var anchor := low + (high - low) * pivot
		node.position = parent.size * Vector2(anchor.x, 1.0 - anchor.y) + Vector2(anchored.x, -anchored.y) - node.pivot_offset
		var parent_path := str(record.get("parent", ""))
		if not str(path).is_empty():
			for layout in catalog.nodes.get(parent_path, {}).get("layouts", []):
				if layout.script != "VerticalLayoutGroup" or not record.get("active", true): continue
				node.size.x = parent.size.x
				node.position = Vector2(0, float(vertical_offsets.get(parent_path, 0)))
				vertical_offsets[parent_path] = node.position.y + node.size.y + float(layout.fields.get("m_Spacing", 0))
		var authored_scale := _vector(rect.get("scale", [1, 1]))
		node.scale = Vector2(float(values.get("m_LocalScale.x", authored_scale.x)), float(values.get("m_LocalScale.y", authored_scale.y)))
		var rotation_value: Variant = rect.get("rotation_degrees", 0)
		var angle := float(rotation_value[2]) if rotation_value is Array else float(rotation_value)
		node.rotation_degrees = -float(values.get("localEulerAnglesRaw.z", angle))
		node.visible = float(values.get("m_IsActive", 1.0 if record.get("active", true) else 0.0)) >= 0.5
		node.modulate.a = clampf(float(values.get("m_Alpha", record.get("canvas_group", {}).get("alpha", 1.0))), 0.0, 1.0)
		if _drawables.get(path) is Label:
			var label: Label = _drawables[path]
			if str(path).get_file() == "Text_EnemyName":
				node.size = parent.size
				node.position = Vector2.ZERO
			var font_size := int(record.text.get("font_size", 40))
			var font := label.get_theme_font("font")
			while font_size > 14 and font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > node.size.x:
				font_size -= 1
			label.add_theme_font_size_override("font_size", font_size)
		if _drawables.has(path) and values.has("m_Color.a"):
			_drawables[path].self_modulate.a = clampf(float(values["m_Color.a"]), 0.0, 1.0)
		if _drawables.get(path) is TextureProgressBar:
			_drawables[path].value = clampf(float(values.get("m_FillAmount", record.image.get("fill_amount", 1))), 0.0, 1.0)

static func _vector(value: Variant) -> Vector2:
	if value is Dictionary: return Vector2(float(value.get("x", 0)), float(value.get("y", 0)))
	return Vector2(float(value[0]), float(value[1]))

static func _color(value: Variant) -> Color:
	if value is Dictionary: return Color(float(value.get("r", 1)), float(value.get("g", 1)), float(value.get("b", 1)), float(value.get("a", 1)))
	return Color(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
