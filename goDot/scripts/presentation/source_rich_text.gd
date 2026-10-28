class_name SourceRichText
extends RichTextLabel

const TERMS_PATH := "res://assets/ui/talent_view/specinfo.json"
const INLINE_PATH := "res://assets/ui/talent_view/inline_map.json"
const DESCRIPTIONS_PATH := "res://assets/ui/talent_view/description_sources.json"

static var _terms: Dictionary = {}
static var _sprites: Dictionary = {}
static var _descriptions: Dictionary = {}
static var _tokens: RegEx
static var _semantic: RegEx
static var _localization: RegEx
static var _attributes: RegEx
static var _loaded := false

var source_text := ""

static func source_field(table: String, row_id: int, field: String, fallback := "") -> String:
	_load_source()
	return str(_descriptions.get(table, {}).get(str(row_id), {}).get(field, fallback))

func _init() -> void:
	bbcode_enabled = true
	fit_content = true
	scroll_active = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func set_source(value: String) -> void:
	source_text = value
	text = source_to_bbcode(value, get_theme_font_size("normal_font_size"))

static func source_to_bbcode(value: String, icon_size := 28) -> String:
	_load_source()
	var source := _expand(DungeonLocale.text(value))
	var result := ""
	var offset := 0
	var opened: Array[String] = []
	for matched in _tokens.search_all(source):
		result += _escape(source.substr(offset, matched.get_start() - offset))
		var token := matched.get_string()
		var inner := token.substr(1, token.length() - 2).strip_edges()
		var lower := inner.to_lower()
		if lower in ["br", "br/", "br /"]:
			result += "\n"
		elif lower.begins_with("color=") or lower.begins_with("#") and not lower.contains("="):
			var color := _unquote(inner.substr(6).strip_edges()) if lower.begins_with("color=") else inner
			if Color.html_is_valid(color):
				result += "[color=" + color + "]"
				opened.append("color")
		elif lower in ["b", "i", "u", "s"]:
			result += "[" + lower + "]"
			opened.append(lower)
		elif lower in ["/color", "/b", "/i", "/u", "/s"]:
			var tag := lower.trim_prefix("/")
			if not opened.is_empty() and opened.back() == tag:
				result += "[/" + tag + "]"
				opened.pop_back()
		elif lower.begins_with("sprite"):
			var attributes := _read_attributes(inner)
			var sprite_name := str(attributes.get("name", attributes.get("index", "")))
			if sprite_name.is_empty() and inner.contains("="):
				sprite_name = _unquote(inner.get_slice("=", 1).strip_edges())
			var path := sprite_path(sprite_name)
			if not path.is_empty():
				result += "[img=%dx%d]" % [maxi(1, icon_size), maxi(1, icon_size)] + path + "[/img]"
			else:
				result += _escape("【图标：" + sprite_name + "】")
		elif lower.begins_with("#"):
			result += _escape("【" + inner.trim_prefix("#") + "】")
		elif not _is_metadata_tag(lower):
			result += _escape("【" + inner + "】")
		offset = matched.get_end()
	result += _escape(source.substr(offset))
	while not opened.is_empty(): result += "[/" + opened.pop_back() + "]"
	return result

static func sprite_path(sprite_name: String) -> String:
	_load_source()
	var path := str(_sprites.get(sprite_name, ""))
	# Exported textures resolve through import remaps without the original PNG file.
	return path if path.begins_with("res://") and ResourceLoader.exists(path, "Texture2D") else ""

static func _expand(value: String, depth := 0) -> String:
	if depth >= 8: return value
	var expanded := value
	for matched in _localization.search_all(expanded):
		var fallback := matched.get_string(2)
		if fallback.is_empty(): fallback = DungeonCatalog.clean(matched.get_string())
		expanded = expanded.replace(matched.get_string(), DungeonLocale.keyed(matched.get_string(1), fallback))
	for matched in _semantic.search_all(expanded):
		var key := matched.get_string(1)
		if matched.get_string(0).to_lower().begins_with("<#localizationid"):
			expanded = expanded.replace(matched.get_string(), DungeonCatalog.clean(matched.get_string()))
			continue
		var row: Dictionary = _terms.get("<#specinfo=" + key + ">", {})
		var field: String = {"zh_CN": "text_cn", "zh_TW": "text_cht", "en": "text_en", "ja": "text_jp"}.get(DungeonLocale.current_locale(), "text_cn")
		var term := str(row.get(field, ""))
		if term.is_empty(): term = str(row.get("text_cn", ""))
		if term.is_empty(): term = DungeonCatalog.clean("<#specinfo=" + key + ">")
		expanded = expanded.replace(matched.get_string(), DungeonLocale.text(term))
	return _expand(expanded, depth + 1) if expanded != value and _semantic.search(expanded) else expanded

static func _read_attributes(value: String) -> Dictionary:
	var result := {}
	for matched in _attributes.search_all(value):
		result[matched.get_string(1).to_lower()] = _unquote(matched.get_string(2))
	return result

static func _unquote(value: String) -> String:
	if value.length() >= 2 and value.left(1) == value.right(1) and value.left(1) in ["\"", "'"]:
		return value.substr(1, value.length() - 2)
	return value

static func _is_metadata_tag(value: String) -> bool:
	for prefix in ["ui_msgtype", "link=", "/link", "font=", "/font", "size=", "/size", "align=", "/align", "nobr", "/nobr"]:
		if value.begins_with(prefix): return true
	return false

static func _escape(value: String) -> String:
	return value.replace("[", "[lb]")

static func _load_source() -> void:
	if _loaded: return
	_loaded = true
	var terms: Variant = JSON.parse_string(FileAccess.get_file_as_string(TERMS_PATH))
	if terms is Array:
		for row in terms:
			if row is Dictionary: _terms[str(row.get("key", ""))] = row
	var sprites: Variant = JSON.parse_string(FileAccess.get_file_as_string(INLINE_PATH))
	if sprites is Dictionary: _sprites = sprites
	var descriptions: Variant = JSON.parse_string(FileAccess.get_file_as_string(DESCRIPTIONS_PATH))
	if descriptions is Dictionary: _descriptions = descriptions
	_tokens = RegEx.create_from_string("</?(?:#[A-Za-z0-9]|[A-Za-z])[^>]*>")
	_semantic = RegEx.create_from_string("(?i)<#(?:specinfo|LocalizationId)=[\"']?([^>\"']+)[\"']?>")
	_localization = RegEx.create_from_string("(?is)<#LocalizationId=[\"']?([^>\"']+)[\"']?>((?:(?!<#LocalizationId=).)*?)</LocalizationId>")
	_attributes = RegEx.create_from_string("([A-Za-z_]+)\\s*=\\s*(\"[^\"]*\"|'[^']*'|[^\\s>]+)")
