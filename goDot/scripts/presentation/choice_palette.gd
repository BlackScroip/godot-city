extends RefCounted

static var _data: Dictionary = {}
static var _textures: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/choice/palette.json"))
	return _data

static func color(key: String) -> Color:
	var channels: Array = data().colors[key]
	return Color(channels[0], channels[1], channels[2], channels[3])

static func texture(key: String) -> Texture2D:
	if not _textures.has(key):
		_textures[key] = load(str(data().resources.get(key, ""))) as Texture2D
	return _textures[key]

static func rarity(level: int) -> int:
	return 1 if level == 0 else clampi(level + 2, 1, 5)

static func is_curse(loot_type: Variant) -> bool:
	return str(loot_type) in ["诅咒遗物", "旧日遗物", "4194304", "67108864"]

static func sprite_key(kind: String, rare: int, loot_type: Variant = "") -> String:
	return "%s_%s_v2" % [kind, "curse" if is_curse(loot_type) else str(clampi(rare, 1, 5))]

static func outline(material: String) -> Color:
	for entry in data().text_materials[material].m_Colors:
		if entry[0] == "_OutlineColor":
			var value: Dictionary = entry[1]
			return Color(value.r, value.g, value.b, value.a)
	return Color.BLACK

static func button_color(state: String) -> Color:
	var value: Dictionary = data().button_colors[state]
	return Color(value.r, value.g, value.b, value.a)
