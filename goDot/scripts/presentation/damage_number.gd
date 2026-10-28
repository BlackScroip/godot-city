extends Node3D

const ROOT := "res://assets/ui/damage_numbers/"
static var textures: Dictionary = {}
var glyphs: Array[Sprite3D] = []
var glyph_names: Array[String] = []
var caption: Label3D
var punctuation: Dictionary = {}
var critical := false
var kind := "normal"
var text := "":
	set(value):
		text = value
		_rebuild()
var modulate := Color.WHITE:
	set(value):
		modulate = value
		for glyph in glyphs: glyph.modulate = value
		if is_instance_valid(caption): caption.modulate = Color(0, 1, 0, value.a)
		for label in punctuation.values(): label.modulate = value

func configure(value: String, style: String, is_critical: bool) -> void:
	kind = style
	critical = is_critical
	modulate = Color.WHITE
	text = value

static func texture_for(key: String) -> Texture2D:
	if not textures.has(key):
		var path := ROOT + key + ".png"
		textures[key] = load(path) if ResourceLoader.exists(path) else null
	return textures[key]

func _rebuild() -> void:
	glyph_names.clear()
	for label in punctuation.values(): label.hide()
	if kind == "dodge":
		if not is_instance_valid(caption):
			caption = Label3D.new()
			caption.font = preload("res://assets/ui/boss_intro/font_a8fb15c8685836d5.ttf")
			caption.font_size = 32
			caption.pixel_size = 0.007 * 68.0 / 20.0
			caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			caption.no_depth_test = true
			caption.outline_size = 4
			add_child(caption)
		caption.text = DungeonLocale.text(text)
		caption.modulate = Color(0, 1, 0, modulate.a)
	if is_instance_valid(caption): caption.visible = kind == "dodge"
	if kind != "dodge":
		if critical: glyph_names.append("bgcrit")
		for character in text:
			if character in "0123456789KM": glyph_names.append(kind + character)
			elif character in ".+": glyph_names.append(character)
	# Keep sprite nodes in the label pool, including when a shorter number replaces a critical.
	while glyphs.size() < glyph_names.size():
		var glyph := Sprite3D.new()
		glyph.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		glyph.no_depth_test = true
		glyph.shaded = false
		glyph.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		add_child(glyph)
		glyphs.append(glyph)
	var widths: Array[float] = []
	var total := 0.0
	for key in glyph_names:
		var width := 56.0
		if key == "bgcrit": width = 88.0
		elif key == "buff_shanbi": width = 150.0
		elif key == ".": width = 16.0
		elif key == "+": width = 40.0
		widths.append(width)
		total += width
	var cursor := -total * 0.5
	for index in glyphs.size():
		var glyph := glyphs[index]
		glyph.visible = index < glyph_names.size()
		if not glyph.visible: continue
		var key := glyph_names[index]
		if key in [".", "+"]:
			glyph.hide()
			if not punctuation.has(index):
				var label := Label3D.new()
				label.font_size = 68
				label.pixel_size = 0.007
				label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				label.no_depth_test = true
				add_child(label)
				punctuation[index] = label
			var label: Label3D = punctuation[index]
			label.text = key
			label.offset = Vector2(cursor + widths[index] * 0.5, 0)
			label.modulate = modulate
			label.show()
			cursor += widths[index]
			continue
		var texture := texture_for(key)
		glyph.texture = texture
		glyph.modulate = modulate
		var desired_height := 68.0
		if key == "bgcrit": desired_height = 115.6
		elif key == "buff_shanbi": desired_height = 58.0
		var ratio := desired_height / maxf(1.0, texture.get_height() if texture else 68.0)
		glyph.pixel_size = 0.007 * ratio
		glyph.offset = Vector2((cursor + widths[index] * 0.5) / ratio, 0.0)
		cursor += widths[index]
