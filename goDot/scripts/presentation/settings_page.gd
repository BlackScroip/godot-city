extends Control

signal command(kind: String, id: Variant, extra: Variant)

const PAPER := Color("fcfcfa")
const INK := Color("65491d")
const SELECTED := Color("444f5f")
const TRACK := Color("b0adaa")
const SECTIONS := ["游戏性", "画面", "声音", "账户", "指南"]
const ICONS := {"游戏性": "menu_settings", "画面": "设置显示", "声音": "设置音量", "账户": "账户", "指南": "指南"}
const ACTIVE_ICONS := {"游戏性": "设置(激活)", "画面": "设置显示（激活）", "声音": "设置音量（激活）", "账户": "账户h", "指南": "指南h"}
const SOURCE_BORDERS := {
	"几何形状-白色粉边椭圆": Vector4(30, 0, 30, 0),
	"几何ui-暗圆角矩形": Vector4(38, 39, 38, 39),
	"几何ui-椭圆白色按钮": Vector4(71.4, 0, 75.75, 0),
	"几何ui-白椭圆": Vector4(47.76, 28.61, 45.09, 29.2),
}
var host: DungeonMenuPage
var rows: Array
var canvas: Control
var rail: VBoxContainer
var rail_scroll: ScrollContainer
var detail: VBoxContainer
var scroll: ScrollContainer
var title: Label
var back: Button
var footer: HBoxContainer
var version: Label
var section := "游戏性"
var previous_section := "游戏性"
var guide_category := "战斗"
var guide_article := ""
var guide_data: Array = []
var guide_page_index := 0
var _guide_pages: Array = []
var _guide_title := ""
var controls: Dictionary = {}
var dialog: Control
var dialog_body: VBoxContainer
var dialog_status: Label
var dialog_input: Control
var _dialog_panel: PanelContainer
var _dialog_kind := ""
var _logical_size := Vector2(2048, 900)
var _art: Dictionary = {}
var _buttons: Array[Button] = []
var _slider_thumb: Texture2D
var _dark_pill: Texture2D

func configure(owner_page: DungeonMenuPage, data: Array) -> void:
	host = owner_page
	rows = data
	if FileAccess.file_exists("res://assets/ui/settings/resource_map.json"):
		_art = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/settings/resource_map.json"))
	var source_thumb := _texture("滑动按钮_白")
	if source_thumb:
		var pixels := source_thumb.get_image()
		pixels.resize(34, 34, Image.INTERPOLATE_LANCZOS)
		_slider_thumb = ImageTexture.create_from_image(pixels)
	var source_pill := _texture("几何ui-暗圆角矩形")
	if source_pill:
		var pixels := source_pill.get_image()
		pixels.resize(48, 48, Image.INTERPOLATE_LANCZOS)
		_dark_pill = ImageTexture.create_from_image(pixels)
	if FileAccess.file_exists("res://assets/ui/settings/guides.json"):
		var source: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/settings/guides.json"))
		guide_data = source if source is Array else source.get("articles", [])
		guide_data.sort_custom(func(a, b):
			var categories := ["战斗", "系统", "冒险"]
			var left := categories.find(str(a.get("category", "")))
			var right := categories.find(str(b.get("category", "")))
			return int(a.get("order", 0)) < int(b.get("order", 0)) if left == right else left < right)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var blur := ColorRect.new()
	blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blur.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var material := ShaderMaterial.new()
	material.shader = preload("res://scripts/presentation/settings_backdrop.gdshader")
	blur.material = material
	add_child(blur)
	canvas = Control.new()
	add_child(canvas)
	back = _art_button("退出按钮", "返回", "")
	back.pressed.connect(go_back)
	canvas.add_child(back)
	title = _text("设置", 52, Color("725124"))
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.add_theme_color_override("font_outline_color", Color("fff8d8"))
	title.add_theme_constant_override("outline_size", 6)
	canvas.add_child(title)
	var underline := ColorRect.new()
	underline.name = "TitleUnderline"
	underline.color = Color("dfca87")
	underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(underline)
	rail_scroll = ScrollContainer.new()
	rail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rail_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	canvas.add_child(rail_scroll)
	rail = VBoxContainer.new()
	rail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rail.add_theme_constant_override("separation", 0)
	rail_scroll.add_child(rail)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scrollbar := scroll.get_v_scroll_bar()
	var grabber := _pill(Color("eee7d4"), Color.TRANSPARENT, 0)
	grabber.set_content_margin_all(0)
	for state in ["grabber", "grabber_highlight", "grabber_pressed"]: scrollbar.add_theme_stylebox_override(state, grabber)
	var scroll_track := _pill(Color(0.30, 0.29, 0.35, 0.45), Color.TRANSPARENT, 0)
	scroll_track.set_content_margin_all(0)
	scrollbar.add_theme_stylebox_override("scroll", scroll_track)
	scrollbar.custom_minimum_size.x = 14
	canvas.add_child(scroll)
	detail = VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 10)
	scroll.add_child(detail)
	footer = HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 46)
	canvas.add_child(footer)
	for entry in [["论坛抽奖活动", "sprite_cardicon_square_npchulinv", "settings_forum"], ["一键加群", "R-C", "settings_group"]]:
		var button := Button.new()
		button.text = str(entry[0])
		button.tooltip_text = str(entry[0])
		button.icon = _texture(str(entry[1]))
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 62)
		button.add_theme_constant_override("h_separation", 18)
		button.custom_minimum_size = Vector2(358, 62)
		button.add_theme_font_size_override("font_size", 30)
		button.add_theme_color_override("font_color", Color("262831"))
		button.add_theme_color_override("font_outline_color", PAPER)
		button.add_theme_constant_override("outline_size", 4)
		button.add_theme_stylebox_override("normal", _source_box("几何ui-椭圆白色按钮", 24, _pill(Color("efedeb"), Color("989a8b"), 3)))
		button.pressed.connect(func(): command.emit(entry[2], 0, 0))
		footer.add_child(button)
	version = _text("v" + str(ProjectSettings.get_setting("application/config/version", "0.1.0")), 22, Color(0.7, 0.72, 0.75, 0.5))
	canvas.add_child(version)
	resized.connect(_layout)
	show_section(str(host.page_context.get("settings_section", "游戏性")))
	_layout.call_deferred()

func _texture(key: String) -> Texture2D:
	var path := str(_art.get(key, ""))
	return load(path) as Texture2D if not path.is_empty() and ResourceLoader.exists(path) else DungeonStyle.texture(key)

func _text(value: String, font_size: int, color: Color = INK) -> Label:
	var label := DungeonStyle.label(value, font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _pill(color: Color, border := Color("d3d0c8"), width := 2) -> StyleBoxFlat:
	var style := DungeonStyle.box(color, border, width)
	style.set_corner_radius_all(30)
	style.content_margin_left = 24
	style.content_margin_right = 18
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style

func _source_box(key: String, margin: int, fallback: StyleBox) -> StyleBox:
	var art := _texture(key)
	if not art: return fallback
	var style := StyleBoxTexture.new()
	style.texture = _dark_pill if key == "几何ui-暗圆角矩形" and _dark_pill else art
	var border: Vector4 = SOURCE_BORDERS.get(key, Vector4.ONE * margin)
	if key == "几何ui-暗圆角矩形" and _dark_pill: border = Vector4.ONE * 17
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_texture_margin(side, border[side])
		style.set_content_margin(side, 4 if side in [SIDE_TOP, SIDE_BOTTOM] else 24)
	return style

func _art_button(key: String, tooltip: String, fallback: String) -> Button:
	var button := Button.new()
	button.tooltip_text = tooltip
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.clip_text = true
	button.expand_icon = true
	var texture := _texture(key)
	if texture:
		var picture := TextureRect.new()
		picture.texture = texture
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		button.add_child(picture)
	else:
		button.text = fallback if not fallback.is_empty() else "<"
	for state in ["normal", "hover", "pressed", "focus", "disabled"]: button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", Color("292b31"))
	button.add_theme_color_override("font_outline_color", PAPER)
	button.add_theme_constant_override("outline_size", 4)
	return button

func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

func show_section(value: String) -> void:
	close_dialog()
	if value == "存档": value = "账户"
	if value != "指南" and section != "指南": previous_section = value
	section = value
	host.page_context["settings_section"] = section
	title.text = "指南" if section == "指南" else "设置"
	guide_article = ""
	_refresh_rail()
	_rebuild_rows()
	_layout()

func _refresh_rail() -> void:
	_clear(rail)
	var sections: Array = ["战斗", "系统", "冒险"] if section == "指南" else SECTIONS
	for name in sections:
		var key := Button.new()
		key.name = "Section_" + name
		key.text = name
		key.tooltip_text = name
		key.set_meta("section", name)
		key.custom_minimum_size = Vector2(0, 102)
		var active: bool = name == (guide_category if section == "指南" else section)
		key.icon = _texture(("高亮星标" if active else "白星标") if section == "指南" else str((ACTIVE_ICONS if active else ICONS).get(name, "")))
		key.expand_icon = true
		key.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		key.add_theme_constant_override("icon_max_width", 68)
		key.add_theme_constant_override("h_separation", 18)
		key.add_theme_font_size_override("font_size", 30)
		key.alignment = HORIZONTAL_ALIGNMENT_CENTER
		key.autowrap_mode = TextServer.AUTOWRAP_OFF
		key.clip_text = true
		key.resized.connect(func(): _fit_button(key, 30))
		var style := DungeonStyle.box(Color(0.9, 0.75, 0.32, 0.28) if active else Color.TRANSPARENT)
		style.border_width_top = 2
		style.border_width_bottom = 2
		style.border_width_left = 0
		style.border_width_right = 0
		style.set_corner_radius_all(0)
		style.border_color = Color("c6aa5b") if active else Color(0.8, 0.8, 0.65, 0.25)
		style.content_margin_left = 32
		style.content_margin_right = 24
		for state in ["normal", "hover", "pressed"]: key.add_theme_stylebox_override(state, style)
		key.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		key.add_theme_color_override("font_color", Color("fff2bb") if active else Color("d3d4d3"))
		key.add_theme_color_override("icon_normal_color", Color("ffd77c") if active else Color("e4e2d6"))
		key.pressed.connect(func():
			if section == "指南":
				guide_category = name
				guide_article = ""
				_refresh_rail()
				_rebuild_rows()
			else: show_section(name))
		rail.add_child(key)

func _rebuild_rows() -> void:
	_clear(detail)
	controls.clear()
	_buttons.clear()
	scroll.scroll_vertical = 0
	footer.visible = section != "指南"
	detail.add_theme_constant_override("separation", 28 if section == "指南" else 10)
	if section == "指南":
		_build_guides()
		return
	var has_rows := false
	for row in rows:
		if str(row.get("section", "")) != section: continue
		_build_row(row)
		has_rows = true
	if not has_rows: _build_row({"title": "暂无可用项目"})
	refresh_values()
	_layout.call_deferred()

func _build_row(row: Dictionary) -> void:
	var panel := PanelContainer.new()
	panel.name = "Setting_" + str(row.get("key", row.title))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size.y = 60
	panel.add_theme_stylebox_override("panel", _source_box("几何形状-白色粉边椭圆", 30, _pill(PAPER)))
	detail.add_child(panel)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 20)
	panel.add_child(line)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.size_flags_stretch_ratio = 1.25
	copy.alignment = BoxContainer.ALIGNMENT_CENTER
	copy.add_theme_constant_override("separation", 0)
	line.add_child(copy)
	var label := _text(str(row.title), 28)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_child(label)
	var description := str(row.get("description", ""))
	if not description.is_empty():
		var help := _text(description, 19, Color("8c8a82"))
		for text_label in [label, help]:
			var compact_font := FontVariation.new()
			compact_font.base_font = text_label.get_theme_font("font")
			compact_font.spacing_top = -4
			compact_font.spacing_bottom = -4
			text_label.add_theme_font_override("font", compact_font)
		copy.add_child(help)
	var options: Array = row.get("options", [])
	if not options.is_empty():
		var group := HBoxContainer.new()
		group.alignment = BoxContainer.ALIGNMENT_END
		group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		group.size_flags_stretch_ratio = 1.0
		group.add_theme_constant_override("separation", 0)
		line.add_child(group)
		var track := PanelContainer.new()
		track.custom_minimum_size.x = options.size() * 166
		track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		track.add_theme_stylebox_override("panel", _pill(TRACK, Color.TRANSPARENT, 0))
		group.add_child(track)
		var segments := HBoxContainer.new()
		segments.add_theme_constant_override("separation", 0)
		track.add_child(segments)
		for option in options:
			var button := Button.new()
			button.text = str(option.text)
			button.clip_text = true
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.custom_minimum_size = Vector2(0, 42)
			button.set_meta("entry", option)
			button.add_theme_font_size_override("font_size", 27)
			button.resized.connect(func(): _fit_button(button, 27))
			button.add_theme_color_override("font_color", PAPER)
			button.add_theme_color_override("font_focus_color", PAPER)
			button.pressed.connect(func():
				command.emit(str(option.action), option.get("id", 0), option.get("extra", 0))
				refresh_values())
			segments.add_child(button)
			_buttons.append(button)
			_segment_style(button, bool(option.get("selected", false)))
		if row.has("key"): controls[str(row.key)] = segments
		return
	for entry in row.get("controls", []):
		if entry.get("type") == "toggle":
			var toggle := CheckBox.new()
			toggle.text = str(entry.get("text", ""))
			toggle.button_pressed = bool(entry.get("value", false))
			toggle.add_theme_font_size_override("font_size", 25)
			toggle.add_theme_color_override("font_color", INK)
			toggle.add_theme_icon_override("checked", _texture("勾选"))
			toggle.add_theme_icon_override("unchecked", _texture("勾选框"))
			toggle.add_theme_constant_override("check_v_offset", 0)
			toggle.toggled.connect(func(value):
				command.emit("setting:" + str(entry.key), value, 0)
				toggle.set_pressed_no_signal(bool(DungeonSettings.read_options().get(entry.key, false))))
			line.add_child(toggle)
			controls[str(entry.key)] = toggle
		elif entry.get("type") == "language":
			var selector := _language_control(entry)
			selector.custom_minimum_size.x = 490
			line.add_child(selector)
		elif entry.get("type") == "slider":
			var range_line := HBoxContainer.new()
			range_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			range_line.add_theme_constant_override("separation", 16)
			line.add_child(range_line)
			var slider := HSlider.new()
			slider.name = str(row.get("key", "Volume"))
			slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			slider.custom_minimum_size.y = 40
			slider.min_value = float(entry.get("min", 0))
			slider.max_value = float(entry.get("max", 1))
			slider.step = float(entry.get("step", 0.01))
			slider.value = float(entry.get("value", 0))
			slider.scrollable = false
			slider.add_theme_stylebox_override("slider", _pill(Color("c3bdb7"), Color("99938e"), 2))
			slider.add_theme_stylebox_override("grabber_area", StyleBoxEmpty.new())
			slider.add_theme_stylebox_override("grabber_area_highlight", StyleBoxEmpty.new())
			var handle := GradientTexture2D.new()
			handle.width = 34
			handle.height = 34
			handle.fill = GradientTexture2D.FILL_RADIAL
			handle.fill_from = Vector2(0.5, 0.5)
			handle.fill_to = Vector2(1, 0.5)
			var gradient := Gradient.new()
			gradient.offsets = PackedFloat32Array([0, 0.85, 0.9, 0.99, 1])
			gradient.colors = PackedColorArray([PAPER, PAPER, Color("999895"), Color("999895"), Color.TRANSPARENT])
			handle.gradient = gradient
			for state in ["grabber", "grabber_highlight", "grabber_disabled"]: slider.add_theme_icon_override(state, _slider_thumb if _slider_thumb else handle)
			range_line.add_child(slider)
			var number := _text(str(roundi(slider.value)), 28, Color("436796"))
			number.custom_minimum_size.x = 60
			number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			range_line.add_child(number)
			slider.value_changed.connect(func(value: float):
				number.text = str(roundi(value))
				command.emit(str(entry.action), value, 0)
				refresh_values())
			if row.has("key"): controls[str(row.key)] = {"slider": slider, "label": number}
	var buttons: Array = row.get("buttons", [])
	if not buttons.is_empty():
		var actions := HFlowContainer.new()
		actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.alignment = FlowContainer.ALIGNMENT_END
		line.add_child(actions)
		for entry in buttons:
			var button := _button(str(entry.text), str(entry.action), entry.get("id", 0), entry.get("extra", 0))
			button.disabled = bool(entry.get("disabled", false))
			button.custom_minimum_size = Vector2(225, 46)
			actions.add_child(button)

func _segment_style(button: Button, selected: bool) -> void:
	for state in ["normal", "hover", "pressed", "focus"]:
		var style: StyleBox = _pill(SELECTED if selected else Color.TRANSPARENT, Color("c6a763") if selected else Color.TRANSPARENT, 2 if selected else 0)
		if selected: style = _source_box("几何ui-暗圆角矩形", 24, style)
		style.set_content_margin_all(4)
		button.add_theme_stylebox_override(state, style)

func _button(label: String, action: String, id: Variant = 0, extra: Variant = 0) -> Button:
	var button := Button.new()
	button.text = label
	button.clip_text = true
	button.add_theme_font_size_override("font_size", 25)
	button.resized.connect(func(): _fit_button(button, 25))
	button.add_theme_color_override("font_color", PAPER)
	button.add_theme_stylebox_override("normal", _source_box("几何ui-暗圆角矩形", 24, _pill(SELECTED, Color("bca162"))))
	button.add_theme_stylebox_override("hover", _pill(Color("596373"), Color("e4c478")))
	button.add_theme_stylebox_override("pressed", _pill(Color("363d4c"), Color("e4c478")))
	button.pressed.connect(func():
		if action.begins_with("dialog:"): open_dialog(action.trim_prefix("dialog:"))
		elif action == "section": show_section(str(id))
		elif not action.is_empty(): command.emit(action, id, extra))
	return button

func _fit_button(button: Button, maximum: int) -> void:
	if not is_instance_valid(button) or button.size.x <= 1: return
	var font := button.get_theme_font("font")
	var label := tr(button.text)
	var style := button.get_theme_stylebox("normal")
	var available := button.size.x - style.get_content_margin(SIDE_LEFT) - style.get_content_margin(SIDE_RIGHT)
	if button.icon:
		var icon_width := float(button.icon.get_width())
		var limit := button.get_theme_constant("icon_max_width")
		if limit > 0: icon_width = minf(icon_width, limit)
		available -= icon_width + button.get_theme_constant("h_separation")
	available = maxf(1, available - 4)
	var chosen := maximum
	while chosen > 12 and font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, chosen).x > available: chosen -= 1
	if button.get_theme_font_size("font_size") != chosen:
		button.add_theme_font_size_override("font_size", chosen)

func _language_control(entry: Dictionary) -> OptionButton:
	var selector := OptionButton.new()
	selector.name = "LanguageSelect"
	selector.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	selector.get_popup().auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	selector.fit_to_longest_item = false
	selector.clip_text = true
	selector.custom_minimum_size = Vector2(0, 46)
	selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selector.add_theme_font_size_override("font_size", 24)
	for language in DungeonLocale.language_options():
		selector.add_item(str(language.name))
		var index := selector.item_count - 1
		selector.set_item_metadata(index, str(language.code))
		if str(language.code) == str(entry.get("value", DungeonLocale.current_locale())): selector.select(index)
	selector.item_selected.connect(func(index: int): command.emit("language", selector.get_item_metadata(index), 0))
	return selector

func refresh_values() -> void:
	var values := DungeonSettings.read_options()
	for button in _buttons:
		var entry: Dictionary = button.get_meta("entry")
		var key := str(entry.action).trim_prefix("setting:")
		if values.has(key): _segment_style(button, values[key] == entry.id)
	for key in controls:
		var control: Variant = controls[key]
		if control is Dictionary and control.has("slider") and values.has(key):
			control.slider.set_value_no_signal(float(values[key]))
			control.label.text = str(values[key])
		elif control is CheckBox and values.has(key): control.set_pressed_no_signal(bool(values[key]))

func _build_guides() -> void:
	for article in guide_data:
		if str(article.get("category", "战斗")) != guide_category: continue
		var button := Button.new()
		button.text = str(article.get("title", ""))
		button.custom_minimum_size.y = 154
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.add_theme_font_size_override("font_size", 32)
		button.add_theme_color_override("font_color", Color("152039"))
		button.add_theme_stylebox_override("normal", _source_box("几何ui-白椭圆", 64, _pill(Color("e3dfd5"), Color("c5c1b7"), 4)))
		button.add_theme_stylebox_override("hover", _pill(Color("f2eee4"), Color("d8bb77"), 4))
		button.pressed.connect(func():
			open_guide(str(article.get("id", article.get("title", "")))))
		detail.add_child(button)
	if detail.get_child_count() == 0: detail.add_child(_text("暂无可用项目", 28, PAPER))

func open_guide(id: String) -> void:
	for article in guide_data:
		if not id.is_valid_float() or float(article.id) != float(id): continue
		_guide_title = str(article.title)
		_guide_pages = article.get("pages", [])
		guide_page_index = 0
		open_dialog("guide")
		guide_article = id
		_render_guide_page()
		return

func change_guide_page(direction: int) -> void:
	guide_page_index = clampi(guide_page_index + direction, 0, maxi(0, _guide_pages.size() - 1))
	_render_guide_page()

func _render_guide_page() -> void:
	if not is_instance_valid(dialog_body) or _guide_pages.is_empty(): return
	_clear(dialog_body)
	dialog_body.add_theme_constant_override("separation", 12)
	var page_data: Dictionary = _guide_pages[guide_page_index]
	var heading := HBoxContainer.new()
	dialog_body.add_child(heading)
	var caption := _text(_guide_title, 34)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(caption)
	var close := _art_button("滑动按钮_close", "关闭", "X")
	close.custom_minimum_size = Vector2(50, 50)
	close.pressed.connect(close_dialog)
	heading.add_child(close)
	var page_title := _text(str(page_data.get("head", "")), 30, Color("314152"))
	page_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dialog_body.add_child(page_title)
	var image := DungeonStyle.picture(str(page_data.get("image", "")), Vector2(0, 390))
	image.name = "GuideImage"
	image.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dialog_body.add_child(image)
	var body_scroll := ScrollContainer.new()
	body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body_scroll.custom_minimum_size.y = 130
	body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dialog_body.add_child(body_scroll)
	var body := RichTextLabel.new()
	body.name = "GuideBody"
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = false
	body.add_theme_font_size_override("normal_font_size", 27)
	body.add_theme_color_override("default_color", Color("314152"))
	var source_text := DungeonLocale.text(str(page_data.get("body", "")))
	var colors := RegEx.new()
	colors.compile("<color=(#[A-Fa-f0-9]+)>")
	source_text = colors.sub(source_text, "[color=$1]", true).replace("</color>", "[/color]")
	body.text = DungeonCatalog.clean(source_text)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_scroll.add_child(body)
	var navigation := HBoxContainer.new()
	navigation.alignment = BoxContainer.ALIGNMENT_CENTER
	navigation.add_theme_constant_override("separation", 24)
	dialog_body.add_child(navigation)
	var previous := _art_button("左右箭头按钮", "上一页", "<")
	previous.name = "GuidePrevious"
	previous.custom_minimum_size = Vector2(60, 60)
	previous.disabled = guide_page_index <= 0
	if previous.get_child_count() > 0: previous.get_child(0).modulate = Color(0.36, 0.30, 0.22, 0.3 if previous.disabled else 1.0)
	previous.pressed.connect(func(): change_guide_page(-1))
	navigation.add_child(previous)
	var counter := _text("%d / %d" % [guide_page_index + 1, _guide_pages.size()], 26, Color("314152"))
	counter.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	counter.custom_minimum_size.x = 130
	counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	navigation.add_child(counter)
	var next := _art_button("左右箭头按钮", "下一页", ">")
	next.name = "GuideNext"
	if next.get_child_count() > 0 and next.get_child(0) is TextureRect: next.get_child(0).flip_h = true
	next.custom_minimum_size = Vector2(60, 60)
	next.disabled = guide_page_index >= _guide_pages.size() - 1
	if next.get_child_count() > 0: next.get_child(0).modulate = Color(0.36, 0.30, 0.22, 0.3 if next.disabled else 1.0)
	next.pressed.connect(func(): change_guide_page(1))
	navigation.add_child(next)
	_layout_dialog.call_deferred()

func go_back() -> void:
	if is_instance_valid(dialog): close_dialog()
	elif section == "指南" and not guide_article.is_empty():
		guide_article = ""
		_rebuild_rows()
	elif section == "指南": show_section(previous_section if previous_section in SECTIONS and previous_section != "指南" else "游戏性")
	elif section in ["语言", "操作配置"]: show_section("账户")
	else: command.emit("close_page", 0, 0)

func open_dialog(kind: String) -> void:
	close_dialog()
	_dialog_kind = kind
	dialog = Control.new()
	dialog.name = "SettingsDialog"
	dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(dialog)
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.025, 0.04, 0.7)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dialog.add_child(shade)
	_dialog_panel = PanelContainer.new()
	_dialog_panel.minimum_size_changed.connect(func(): _layout_dialog.call_deferred())
	_dialog_panel.add_theme_stylebox_override("panel", _pill(PAPER, Color("cdb679"), 3))
	dialog.add_child(_dialog_panel)
	dialog_body = VBoxContainer.new()
	dialog_body.add_theme_constant_override("separation", 20)
	_dialog_panel.add_child(dialog_body)
	var names := {"feedback": "联系客服", "redeem": "兑换码", "cloud": "云存档", "logout": "退出账号"}
	dialog_body.add_child(_text(str(names.get(kind, kind)), 34))
	if kind in ["feedback", "redeem"]:
		if kind == "redeem":
			var field := LineEdit.new()
			field.max_length = 128
			field.placeholder_text = tr("请输入您的兑换码")
			field.custom_minimum_size.y = 64
			field.add_theme_font_size_override("font_size", 28)
			field.text_submitted.connect(func(_value): _submit_dialog())
			dialog_input = field
		else:
			var field := TextEdit.new()
			field.placeholder_text = tr("请输入反馈内容")
			field.custom_minimum_size.y = 170
			field.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
			field.add_theme_font_size_override("font_size", 26)
			dialog_input = field
		dialog_body.add_child(dialog_input)
	var message := ""
	if kind == "cloud":
		message = "战斗中无法打开云存档" if bool(host.page_context.get("in_run", false)) else "当前版本尚未接入账号与云存档服务。"
		_build_cloud_content(message)
	elif kind == "logout": message = "确认退出当前游戏并返回标题？本地进度将自动保存。"
	dialog_status = _text(message, 25)
	dialog_status.custom_minimum_size.y = 56
	dialog_body.add_child(dialog_status)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 18)
	dialog_body.add_child(actions)
	var cancel := _button("取消" if kind != "cloud" else "关闭", "")
	cancel.custom_minimum_size = Vector2(190, 54)
	cancel.pressed.connect(close_dialog)
	actions.add_child(cancel)
	if kind != "cloud":
		var submit := _button("确定" if kind == "redeem" else "退出" if kind == "logout" else "提交反馈", "")
		submit.custom_minimum_size = Vector2(230, 54)
		submit.pressed.connect(_submit_dialog)
		actions.add_child(submit)
	_layout_dialog()
	_focus_dialog_input.call_deferred()

func _focus_dialog_input() -> void:
	if is_instance_valid(dialog_input) and dialog_input.is_inside_tree(): dialog_input.grab_focus()

func _build_cloud_content(reason: String) -> void:
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 36)
	dialog_body.add_child(columns)
	for index in 2:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 18)
		columns.add_child(column)
		column.add_child(_text("本地存档" if index == 0 else "云端存档", 30))
		var stamp := int(host.page_context.get("local_save_time", 0))
		var summary := "无云存档"
		if index == 0: summary = Time.get_datetime_string_from_unix_time(stamp).replace("T", " ") + " UTC" if stamp > 0 else "尚无本地存档"
		var status := _text(summary, 24, Color("626776"))
		status.custom_minimum_size.y = 90
		column.add_child(status)
		var transfer := _button("本地存档上传至云端" if index == 0 else "云端存档下载至本地", "")
		transfer.custom_minimum_size.y = 56
		transfer.disabled = true
		transfer.tooltip_text = reason
		column.add_child(transfer)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 24)
	dialog_body.add_child(actions)
	for text_value in ["查看全部云端存档列表", "拉取云存档数据"]:
		var action := _button(text_value, "")
		action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		action.custom_minimum_size.y = 56
		action.disabled = true
		action.tooltip_text = reason
		actions.add_child(action)

func _submit_dialog() -> void:
	if _dialog_kind == "logout":
		command.emit("settings_logout", 0, 0)
		return
	var value := str(dialog_input.get("text")).strip_edges() if is_instance_valid(dialog_input) else ""
	if value.is_empty():
		set_dialog_status("请输入兑换码" if _dialog_kind == "redeem" else "请输入反馈内容")
		return
	command.emit("settings_redeem" if _dialog_kind == "redeem" else "settings_feedback", value, 0)

func set_dialog_status(message: String) -> void:
	if is_instance_valid(dialog_status): dialog_status.text = message
	_layout_dialog.call_deferred()

func close_dialog() -> void:
	if is_instance_valid(dialog):
		dialog.get_parent().remove_child(dialog)
		dialog.queue_free()
	dialog = null
	dialog_input = null
	_dialog_panel = null
	if _dialog_kind == "guide": guide_article = ""
	_dialog_kind = ""

func _layout_dialog() -> void:
	if not is_instance_valid(_dialog_panel): return
	var width := minf(1350 if _dialog_kind in ["guide", "cloud"] else 900, _logical_size.x - 120)
	_dialog_panel.size = Vector2(width, 0)
	_dialog_panel.position = (_logical_size - Vector2(width, _dialog_panel.get_combined_minimum_size().y)) * 0.5

func _layout() -> void:
	if not is_instance_valid(canvas) or size.x <= 0 or size.y <= 0: return
	var factor := minf(size.y / 900.0, size.x / 1280.0)
	_logical_size = size / maxf(factor, 0.01)
	canvas.size = _logical_size
	canvas.scale = Vector2.ONE * factor
	var width := _logical_size.x
	back.position = Vector2(24, 16)
	back.size = Vector2(116, 96)
	title.position = Vector2(152, 20)
	var title_width := title.get_theme_font("font").get_string_size(tr(title.text), HORIZONTAL_ALIGNMENT_LEFT, -1, title.get_theme_font_size("font_size")).x + 8
	title.size = Vector2(minf(maxf(210, title_width), width - 190), 70)
	var underline := canvas.get_node("TitleUnderline") as ColorRect
	underline.position = Vector2(150, 98)
	underline.size = Vector2(maxf(165, title.size.x - 45), 4)
	rail_scroll.position = Vector2(0, 194 if section != "指南" else 125)
	rail_scroll.size = Vector2(width * 0.153, 515 if section != "指南" else 600)
	var guide := section == "指南"
	scroll.position = Vector2(width * (0.247 if guide else 0.192), 122 if guide else 170)
	scroll.size = Vector2(width * (0.743 if guide else 0.745), 738 if guide else 588)
	footer.position = Vector2(width * 0.315, 780)
	footer.size = Vector2(width * 0.58, 62)
	version.position = Vector2(0, 866)
	version.size = Vector2(width * 0.6, 32)
	_layout_dialog()
