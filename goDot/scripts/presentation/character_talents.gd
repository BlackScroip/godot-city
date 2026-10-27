extends Control

signal marks_changed

const DESIGN := Vector2(2048, 900)
const GOLD := Color("f5e6a1")
const HOLD_SECONDS := 0.5
const Palette = preload("res://scripts/presentation/choice_palette.gd")

var catalog: DungeonCatalog
var systems: DungeonSystems
var character_id := 1
var stage: Control
var panel: Panel
var detail_overlay: Control
var detail_panel: Panel
var detail_text: RichTextLabel
var buttons: Dictionary = {}
var groups: Dictionary = {}
var clear_button: Button
var _art: Dictionary = {}
var _types: Dictionary = {}
var _terms: Dictionary = {}
var _holding := 0
var _hold_time := 0.0
var _long_pressed := false

func configure(source: DungeonCatalog, domain: DungeonSystems, id: int) -> void:
	catalog = source
	systems = domain
	character_id = id
	name = "CharacterTalentInspector"
	theme = DungeonStyle.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	if FileAccess.file_exists("res://assets/ui/talent_view/resource_map.json"):
		_art = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/talent_view/resource_map.json"))
	if FileAccess.file_exists("res://assets/ui/talent_view/inline_map.json"):
		_art.merge(JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/talent_view/inline_map.json")), true)
	if FileAccess.file_exists("res://assets/ui/talent_view/CharTalentTypeData.json"):
		var types = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/talent_view/CharTalentTypeData.json"))
		if types is Array:
			for row in types: _types[int(row.id)] = row
	if FileAccess.file_exists("res://assets/ui/talent_view/specinfo.json"):
		var terms = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/talent_view/specinfo.json"))
		if terms is Array:
			for row in terms: _terms[str(row.key)] = row
	var shade = ColorRect.new()
	shade.color = Color(0, 0, 0, 0.72)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage = Control.new()
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)
	stage.size = DESIGN
	panel = Panel.new()
	panel.name = "TalentGroups"
	panel.add_theme_stylebox_override("panel", _panel_style(false))
	stage.add_child(panel)
	_place(panel, Rect2(320, 40, 1440, 770))
	var inner = Panel.new()
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_theme_stylebox_override("panel", _panel_style(false))
	panel.add_child(inner)
	_place(inner, Rect2(8, 8, 1424, 754))
	for row in catalog.rows("CharTalentData"):
		if int(row.get("chara_id", 0)) != character_id: continue
		var group = int(row.get("talent_type_id", 0))
		if not groups.has(group): groups[group] = []
		groups[group].append(row)
	var keys = groups.keys()
	keys.sort()
	for index in keys.size(): _build_group(groups[keys[index]], index, keys.size())
	var hint = _label("*长按可标记天赋，被标记的天赋会在选择界面高亮显示", 24)
	stage.add_child(hint)
	_place(hint, Rect2(105, 828, 790, 50))
	var close_hint = _label("点击空白处关闭", 27)
	close_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stage.add_child(close_hint)
	_place(close_hint, Rect2(895, 825, 300, 55))
	clear_button = Button.new()
	clear_button.name = "ClearTalentMarks"
	clear_button.tooltip_text = "清除当前角色的天赋标记"
	clear_button.add_theme_font_size_override("font_size", 24)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		clear_button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	stage.add_child(clear_button)
	_place(clear_button, Rect2(1885, 756, 140, 125))
	var clear_bg = _picture(stage, "38_2", Rect2(1912, 756, 86, 86))
	stage.move_child(clear_bg, clear_button.get_index())
	_picture(clear_button, "删除", Rect2(44, 21, 52, 52), Color("28313c"))
	var clear_label = _label("清除标记", 24)
	clear_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clear_button.add_child(clear_label)
	_place(clear_label, Rect2(0, 88, 140, 37))
	clear_button.pressed.connect(clear_marks)
	resized.connect(_adapt)
	_adapt()
	refresh_marks()

func _build_group(data: Array, index: int, count: int) -> void:
	var width = 1380.0 / maxi(1, count)
	var x = 350.0 + width * index
	var center = x + width * 0.5
	var regular: Array = []
	var core: Dictionary = {}
	for row in data:
		if bool(row.get("is_core_talent", false)): core = row
		else: regular.append(row)
	regular.sort_custom(func(a, b): return int(a.id) < int(b.id))
	var title = _label(_group_name(data, core), 34, GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stage.add_child(title)
	_place(title, Rect2(x, 76, width, 48))
	if not core.is_empty():
		_picture(stage, "bg装饰", Rect2(center - 94, 120, 188, 188), Color(0.6, 0.6, 0.61, 0.7))
		_picture(stage, "白星标", Rect2(x - 8, 191, 42, 42), GOLD)
		if index == count - 1: _picture(stage, "白星标", Rect2(x + width - 34, 191, 42, 42), GOLD)
		var left_arrow = _picture(stage, "箭头白", Rect2(center - 147, 191, 44, 44), GOLD)
		left_arrow.flip_h = true
		_picture(stage, "箭头白", Rect2(center + 103, 191, 44, 44), GOLD)
		for corner in 4:
			var decoration = _picture(stage, "装饰花纹 1", Rect2(center - 166 if corner % 2 == 0 else center + 122, 134 if corner < 2 else 244, 44, 44), GOLD)
			decoration.flip_h = corner % 2 == 0
			decoration.flip_v = corner >= 2
		_make_button(core, Rect2(center - 69, 145, 138, 138))
	for position in regular.size():
		_make_button(regular[position], Rect2(center - 168 + (position % 2) * 195, 317 + (position / 2) * 152, 138, 138))

func _group_name(data: Array, core: Dictionary) -> String:
	var type_id = int(data[0].get("talent_type_id", 0))
	if _types.has(type_id): return DungeonCatalog.clean(DungeonCatalog.row_name(_types[type_id]))
	var description = DungeonCatalog.clean(core.get("description", ""))
	var start = description.find("【")
	var end = description.find("】", start + 1)
	if start >= 0 and end > start: return description.substr(start + 1, end - start - 1)
	return DungeonCatalog.clean(core.get("name", str(type_id)))

func _make_button(row: Dictionary, area: Rect2) -> void:
	var id = int(row.id)
	var button = Button.new()
	button.name = "Talent_%d" % id
	var rank = 0
	if systems and systems.profile.data.run.active and int(systems.profile.data.run.character_id) == character_id:
		rank = systems.rank(systems.profile.data.run.talents, id)
	button.set_meta("rarity", Palette.rarity(rank))
	button.tooltip_text = DungeonCatalog.clean(row.get("name", ""))
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	stage.add_child(button)
	_place(button, area)
	var icon = TextureRect.new()
	icon.texture = _texture(str(row.get("icon_name", "")))
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(icon)
	_place(icon, Rect2(7, 7, 124, 124))
	var locked = systems and systems.rank(systems.profile.data.character_levels, character_id) < int(row.get("unlock_chara_level", 0))
	if locked:
		icon.modulate = Color(0.03, 0.03, 0.03)
		var level = int(row.get("unlock_chara_level", 0))
		var badge_key = "Adventure_Level_%d" % clampi(level - 3, 2, 5)
		_picture(button, "res://assets/ui/role_character/" + badge_key + ".png", Rect2(20, 20, 98, 98))
		var badge = _label(str(int(row.get("unlock_chara_level", 0))), 36, Color("e7dff4"))
		badge.name = "UnlockLevel"
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		button.add_child(badge)
		_place(badge, Rect2(25, 25, 88, 88))
	if rank > 0:
		var stars = Control.new()
		stars.name = "TalentLevelStars"
		stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(stars)
		var star_size = 36.0 * 138.0 / 144.0
		var spacing = 25.5 * 138.0 / 144.0
		var width = star_size + spacing * (rank - 1)
		_place(stars, Rect2((138 - width) * 0.5, 138 - star_size * 0.5 + 2.5, width, star_size))
		for index in rank: _picture(stars, "星星大", Rect2(index * spacing, 0, star_size, star_size))
	var mark = _picture(button, "AwakenSkillBg_1", Rect2(-4, -4, 67, 67))
	mark.name = "MarkFrame"
	_picture(mark, "白星标", Rect2(-5, -5, 77, 77), Color(1, 0.9055, 0.5236))
	mark.visible = false
	button.button_down.connect(func():
		_holding = id
		_hold_time = 0
		_long_pressed = false)
	button.button_up.connect(func(): _holding = 0)
	button.mouse_exited.connect(func(): _holding = 0)
	button.pressed.connect(func():
		if not _long_pressed: show_detail(id))
	buttons[id] = button

func _process(delta: float) -> void:
	if _holding <= 0: return
	_hold_time += delta
	if _hold_time > HOLD_SECONDS:
		_long_pressed = true
		toggle_mark(_holding)
		_holding = 0

func toggle_mark(id: int) -> void:
	if not systems: return
	var result = systems.toggle_character_talent_mark(id, character_id)
	if result.get("success", false):
		refresh_marks()
		marks_changed.emit()

func clear_marks() -> void:
	if not systems: return
	var result = systems.clear_character_talent_marks(character_id)
	if result.get("success", false):
		refresh_marks()
		marks_changed.emit()

func refresh_marks() -> void:
	for id in buttons:
		var button: Button = buttons[id]
		var marked = systems and systems.is_character_talent_marked(id)
		button.set_meta("marked", marked)
		button.get_node("MarkFrame").visible = marked
		for state in ["normal", "hover", "pressed", "focus"]:
			var style = _source_style("slotfg_rare_square_1_v2", 0)
			style.texture = Palette.texture(Palette.sprite_key("slotfg_rare_square", int(button.get_meta("rarity", 1))))
			style.modulate_color = Color("ffe3a3") if state == "focus" else Color.WHITE
			button.add_theme_stylebox_override(state, style)

func show_detail(id: int) -> void:
	var row = catalog.find("CharTalentData", id)
	if row.is_empty() or int(row.get("chara_id", 0)) != character_id: return
	close_detail()
	_holding = 0
	detail_overlay = Control.new()
	detail_overlay.name = "TalentDetail"
	add_child(detail_overlay)
	detail_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade = ColorRect.new()
	shade.color = Color(0, 0, 0, 0.78)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_overlay.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	detail_overlay.gui_input.connect(func(event):
		if _is_click(event):
			close_detail()
			accept_event())
	var content = Control.new()
	content.name = "DetailStage"
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_overlay.add_child(content)
	content.size = DESIGN
	detail_panel = Panel.new()
	detail_panel.add_theme_stylebox_override("panel", _panel_style(false))
	content.add_child(detail_panel)
	_place(detail_panel, Rect2(585, 125, 895, 640))
	var paper = Panel.new()
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper.add_theme_stylebox_override("panel", _panel_style(true))
	detail_panel.add_child(paper)
	_place(paper, Rect2(15, 13, 865, 614))
	var frame = Panel.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", _source_style("slotfg_rare_square_1_v2", 0))
	detail_panel.add_child(frame)
	_place(frame, Rect2(95, 77, 140, 140))
	var icon = TextureRect.new()
	icon.texture = _texture(str(row.get("icon_name", "")))
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_panel.add_child(icon)
	_place(icon, Rect2(103, 85, 124, 124))
	var title = _label(DungeonCatalog.clean(row.get("name", "")), 28, Color("ffd362"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_panel.add_child(title)
	_place(title, Rect2(35, 227, 260, 120))
	var column = VBoxContainer.new()
	detail_panel.add_child(column)
	_place(column, Rect2(300, 78, 520, 500))
	column.add_theme_constant_override("separation", 10)
	var summary = RichTextLabel.new()
	summary.bbcode_enabled = true
	summary.fit_content = true
	summary.scroll_active = false
	_text_style(summary)
	summary.text = "[color=#f4d78e]" + _rich(str(row.get("description", ""))) + "[/color]"
	column.add_child(summary)
	var divider = _picture(column, "ArtLineDown_white", Rect2(0, 0, 520, 3))
	divider.custom_minimum_size.y = 3
	detail_text = RichTextLabel.new()
	detail_text.name = "AllTalentLevels"
	detail_text.bbcode_enabled = true
	detail_text.scroll_active = true
	detail_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text_style(detail_text)
	var text = ""
	var levels = DungeonCatalog.ids(row.get("level_data_id_list", ""))
	for index in levels.size():
		var level = catalog.find("CharTalentLevelData", int(levels[index]))
		text += DungeonLocale.text("等级%d：") % (index + 1) + _rich(str(level.get("effect_description", ""))) + "\n\n"
	detail_text.text = text
	column.add_child(detail_text)
	var hint = _label("点击空白处关闭", 29)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(hint)
	_place(hint, Rect2(850, 828, 350, 55))
	_adapt()

func _text_style(label: RichTextLabel) -> void:
	label.add_theme_font_size_override("normal_font_size", 27)
	label.add_theme_color_override("default_color", Color("faf8ef"))
	label.add_theme_color_override("font_outline_color", Color("403d36"))
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_constant_override("line_separation", -6)

func _rich(value: String) -> String:
	var text = DungeonLocale.text(value)
	var regex = RegEx.new()
	regex.compile("<color=(#[A-Fa-f0-9]+)>")
	text = regex.sub(text, "[color=$1]", true).replace("</color>", "[/color]")
	regex.compile("<#specinfo=[^>]+>")
	for match in regex.search_all(text):
		text = text.replace(match.get_string(), _term(match.get_string()))
	return DungeonCatalog.clean(text)

func _term(key: String) -> String:
	var row: Dictionary = _terms.get(key, {})
	var field = {"zh_CN": "text_cn", "zh_TW": "text_cht", "en": "text_en", "ja": "text_jp"}.get(DungeonLocale.current_locale(), "text_cn")
	var source = str(row.get(field, ""))
	if source.is_empty(): source = str(row.get("text_cn", ""))
	var regex = RegEx.new()
	regex.compile("<color=(#[A-Fa-f0-9]+)>")
	var color_match = regex.search(source)
	var color = color_match.get_string(1) if color_match else "#f29a37"
	regex.compile("<sprite name=\"([^\"]+)\">")
	var icon_match = regex.search(source)
	var icon = ""
	if icon_match and _art.has(icon_match.get_string(1)):
		icon = "[img=32x32]" + str(_art[icon_match.get_string(1)]) + "[/img]"
	var label = "[color=" + color + "]" + DungeonCatalog.clean(key) + "[/color]"
	if source.contains("<u>"): label = "[u]" + label + "[/u]"
	return icon + label

func close_detail() -> void:
	if is_instance_valid(detail_overlay):
		detail_overlay.hide()
		detail_overlay.queue_free()
	detail_overlay = null

func _gui_input(event: InputEvent) -> void:
	if _is_click(event):
		queue_free()
		accept_event()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if is_instance_valid(detail_overlay): close_detail()
		else: queue_free()
		get_viewport().set_input_as_handled()

func _is_click(event: InputEvent) -> bool:
	return event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed

func _adapt() -> void:
	if not is_instance_valid(stage): return
	var factor = minf(size.x / DESIGN.x, size.y / DESIGN.y)
	stage.scale = Vector2.ONE * factor
	stage.position = (size - DESIGN * factor) * 0.5
	if is_instance_valid(detail_overlay):
		var content = detail_overlay.get_node("DetailStage")
		content.scale = stage.scale
		content.position = stage.position

func _texture(key: String) -> Texture2D:
	if _art.has(key): return load(str(_art[key])) as Texture2D
	return DungeonStyle.texture(key)

func _panel_style(paper: bool) -> StyleBoxTexture:
	var style = _source_style("几何ui-白圆角矩形" if paper else "几何ui-暗圆角矩形", 38)
	if paper: style.modulate_color = Color("eeebe4")
	return style

func _source_style(key: String, margin: float) -> StyleBoxTexture:
	var style = StyleBoxTexture.new()
	style.texture = _texture(key)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]: style.set_texture_margin(side, margin)
	style.set_content_margin_all(0)
	return style

func _picture(parent: Control, key: String, area: Rect2, tint := Color.WHITE) -> TextureRect:
	var picture = TextureRect.new()
	picture.texture = _texture(key)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_SCALE
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.modulate = tint
	parent.add_child(picture)
	_place(picture, area)
	return picture

func _label(value: String, font_size: int, color := Color.WHITE) -> Label:
	var label = DungeonStyle.label(value, font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color("48443b"))
	label.add_theme_constant_override("outline_size", 2)
	return label

func _place(control: Control, area: Rect2) -> void:
	control.position = area.position
	control.size = area.size
