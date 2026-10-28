class_name DungeonCharacterPage
extends Control

signal command(kind: String, id: Variant, extra: Variant)
signal closed
signal back_requested

const PAPER := Color("fff9ee")
const MUTED := Color("d9c7b7")
const GOLD := Color("ffe08a")
const INK := Color("59433b")
const SOURCE_MAP := "res://assets/ui/role_character/resource_map.json"
const FASHION_DATA := "res://assets/ui/role_character/CharaFashionConfigData.json"
const STAT_ICONS := ["icon_hp_white", "icon_atk_white", "icon_def_white", "icon_criticalrate_white", "icon_criticalmulti_white"]
const ROLE_NAVIGATION = preload("res://scripts/presentation/role_navigation.gd")
const FASHION_MODELS = preload("res://scripts/presentation/character_fashion_models.gd")

var owner_page: DungeonMenuPage
var rows: Array = []
var context: Dictionary = {}
var selected := 0
var use_model := false
var active_tab := "details"
var showcase: VBoxContainer
var detail: VBoxContainer
var category_tabs: VBoxContainer
var selections: Array[Button] = []
var resource_bar: HBoxContainer
var navigation: Array[Button] = []
var detail_scroll: ScrollContainer
var roster_scroll: ScrollContainer
var roster: GridContainer
var title_label: Label
var name_label: Label
var level_label: Label
var biography: Label
var attributes_button: Button
var style_button: Button
var details_button: Button
var model_button: Button
var fashion_button: Button
var awakening_button: Button
var talent_button: Button
var picker_button: Button
var action_bar: HBoxContainer
var art_commands: VBoxContainer
var content: Control
var right_column: Control
var identity: Control
var portrait: TextureRect
var heading: Control
var _attribute_overlay: Control
var _roster_overlay: Control
var _fashion_overlay: Control
var talent_view: Control
var _stage: Control
var _background: TextureRect
var _title_art: TextureRect
var _back_button: Button
var _tabs: HBoxContainer
var _portrait_base: TextureRect
var _level_badge: TextureRect
var _awakening_glow: TextureRect
var _catalog: DungeonCatalog
var _combat_characters: Array = []
var _fashions: Array = []
var _source_map: Dictionary = {}
var _preview_fashion := 0
var _upgrade_overlay: Control
var _recruit_overlay: Control

func configure(host: DungeonMenuPage, data: Array, page_context: Dictionary = {}) -> void:
	owner_page = host
	rows = data
	context = page_context
	_catalog = context.get("catalog") as DungeonCatalog
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	theme = DungeonStyle.theme()
	clip_contents = true
	_source_map = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_MAP))
	_fashions = JSON.parse_string(FileAccess.get_file_as_string(FASHION_DATA))
	var recovered = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/combat.json"))
	if recovered is Dictionary: _combat_characters = recovered.get("characters", [])
	_background = _picture("charamenumask_1", Vector2.ZERO)
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(_background)
	_stage = Control.new()
	_stage.name = "SourcePlayerStateComposition"
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)
	_build_heading()
	_build_content()
	use_model = bool(context.get("use_model", false))
	active_tab = str(context.get("character_mode", "details"))
	var requested = int(context.get("selected_character", context.get("character_id", 0)))
	for index in rows.size():
		if (requested > 0 and int(rows[index].get("config_id", 0)) == requested) or (requested <= 0 and rows[index].get("active_character", false)):
			selected = index
	resized.connect(_adapt)
	if not rows.is_empty(): _select_showcase(selected)
	_preview_fashion = int(context.get("selected_fashion", 0))
	if _preview_fashion > 0 and not rows.is_empty(): _select_showcase(selected)
	if bool(context.get("fashion_open", false)): _show_fashions.call_deferred()
	_adapt.call_deferred()

func _build_heading() -> void:
	heading = Control.new()
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(heading)
	_back_button = ROLE_NAVIGATION.create_back_button()
	_back_button.pressed.connect(func(): back_requested.emit())
	heading.add_child(_back_button)
	_title_art = _picture("角色详情", Vector2.ZERO)
	heading.add_child(_title_art)
	title_label = DungeonStyle.localize_artwork_title(_title_art, "角色详情", 44, PAPER)
	resource_bar = HBoxContainer.new()
	resource_bar.add_theme_constant_override("separation", 16)
	heading.add_child(resource_bar)
	for resource in context.get("resources", []):
		var holder = PanelContainer.new()
		holder.custom_minimum_size = Vector2(210, 47)
		holder.add_theme_stylebox_override("panel", _source_style("货币_底", 18))
		resource_bar.add_child(holder)
		var line = HBoxContainer.new()
		line.add_theme_constant_override("separation", 9)
		holder.add_child(line)
		var icon_key = str(resource[0])
		if icon_key == "loot:12101": icon_key = "sprite_abilityitemicon_15101"
		if icon_key.begins_with("material:"): icon_key = "sprite_materialicon_" + icon_key.get_slice(":", 1)
		line.add_child(_picture(icon_key, Vector2(49, 49)))
		var value = _label(str(resource[1]), 28)
		value.autowrap_mode = TextServer.AUTOWRAP_OFF
		value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.add_child(value)

func _build_content() -> void:
	content = Control.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(content)
	category_tabs = VBoxContainer.new()
	category_tabs.add_theme_constant_override("separation", 0)
	content.add_child(category_tabs)
	var entries: Array = context.get("role_navigation", [])
	if entries.is_empty():
		entries = [{"label": "角色", "page": "characters"}, {"label": "武器", "page": "weapons"}]
		if bool(context.get("in_run", not bool(context.get("camp", true)))): entries.append({"label": "背包", "page": "inventory"})
		entries.append({"label": "仓库", "page": "storage"})
		if bool(context.get("partner_navigation", false)): entries.append({"label": "怪物伙伴", "page": "partners"})
	var icons = {"characters": "角色详情分类(选择)", "weapons": "武器(未选择)", "inventory": "道具(未选择)", "storage": "仓库(未选择)", "monster_partners": "怪物伙伴(未选择)", "partners": "怪物伙伴(未选择)"}
	for entry in entries:
		var page = str(entry.get("page", "characters"))
		var key = Button.new()
		key.text = str(entry.get("label", ""))
		key.icon = _texture(str(icons.get(page, entry.get("icon", "怪物伙伴(未选择)"))))
		key.expand_icon = true
		key.add_theme_constant_override("icon_max_width", 57)
		key.add_theme_constant_override("h_separation", 10)
		key.custom_minimum_size = Vector2(420, 111)
		key.add_theme_font_size_override("font_size", 36)
		key.alignment = HORIZONTAL_ALIGNMENT_LEFT
		key.add_theme_color_override("font_color", PAPER if page == "characters" else MUTED)
		for state in ["normal", "hover", "pressed", "focus"]:
			var shape = _source_style("分类选中" if page == "characters" or state == "hover" else "侧边按钮暗", 0)
			if page != "characters" and state != "hover": shape.modulate_color = Color(1, 1, 1, 0.06)
			shape.content_margin_left = 92
			key.add_theme_stylebox_override(state, shape)
		var divider = _picture("分割线1", Vector2.ZERO)
		key.add_child(divider)
		divider.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		divider.offset_top = -3
		divider.modulate = Color(1, 0.86, 0.61, 0.38)
		key.pressed.connect(func():
			if page != "characters": command.emit("page:" + page, _character_id() if page == "weapons" else 0, 0))
		category_tabs.add_child(key)
		navigation.append(key)
	showcase = VBoxContainer.new()
	showcase.name = "CharacterArtwork"
	showcase.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(showcase)
	art_commands = VBoxContainer.new()
	art_commands.add_theme_constant_override("separation", 13)
	content.add_child(art_commands)
	attributes_button = _vertical_button("Btn_attributedetail", "属性详情", "查看完整属性")
	attributes_button.pressed.connect(_show_attributes)
	art_commands.add_child(attributes_button)
	fashion_button = _vertical_button("Btn_fashion_1", "时装", "角色时装")
	fashion_button.pressed.connect(_show_fashions)
	art_commands.add_child(fashion_button)
	model_button = _vertical_button("角色详情(未选择3D)", "3D", "查看角色模型")
	model_button.pressed.connect(func():
		use_model = not use_model
		_store_context("use_model", use_model)
		_select_showcase(selected))
	art_commands.add_child(model_button)
	right_column = Control.new()
	content.add_child(right_column)
	identity = Control.new()
	right_column.add_child(identity)
	_portrait_base = _picture("sprite_circle_128x128", Vector2.ZERO)
	_portrait_base.modulate = Color("e3c585")
	identity.add_child(_portrait_base)
	portrait = _picture("", Vector2.ZERO)
	var material = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = "shader_type canvas_item; void fragment(){ vec2 p=UV-vec2(0.5); if(length(p)>0.5){discard;} COLOR=texture(TEXTURE,UV); }"
	material.shader = shader
	portrait.material = material
	identity.add_child(portrait)
	picker_button = _icon_button("sprite_conversation_switch", "选择角色", Vector2(120, 120))
	picker_button.modulate.a = 0.01
	picker_button.pressed.connect(_show_character_picker)
	identity.add_child(picker_button)
	_level_badge = _picture("Adventure_Level_5", Vector2.ZERO)
	identity.add_child(_level_badge)
	level_label = _label("1", 27)
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	identity.add_child(level_label)
	name_label = _label("", 40)
	name_label.add_theme_color_override("font_color", GOLD)
	identity.add_child(name_label)
	_awakening_glow = _picture("选中外发光", Vector2.ZERO)
	_awakening_glow.modulate = Color(1.0, 0.05, 0.015, 0.75)
	var glow_material = ShaderMaterial.new()
	var glow_shader = Shader.new()
	glow_shader.code = "shader_type canvas_item; void fragment(){ float a=0.0; for(int x=-3;x<=3;x++){ for(int y=-3;y<=3;y++){ a+=texture(TEXTURE,UV+vec2(float(x),float(y))*TEXTURE_PIXEL_SIZE*2.0).a; }} COLOR=vec4(1.0,0.04,0.01,a/49.0*0.85); }"
	glow_material.shader = glow_shader
	_awakening_glow.material = glow_material
	identity.add_child(_awakening_glow)
	awakening_button = _icon_button("觉醒", "查看觉醒", Vector2(108, 124))
	awakening_button.add_theme_constant_override("icon_max_width", 98)
	awakening_button.modulate = Color("ffda35")
	awakening_button.pressed.connect(func(): command.emit("page:awakening", _character_id(), 0))
	identity.add_child(awakening_button)
	var awaken_text = _label("觉醒", 23)
	awaken_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	awaken_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	awaken_text.add_theme_color_override("font_color", Color("ffe84f"))
	awaken_text.add_theme_color_override("font_outline_color", Color("9c351b"))
	awaken_text.add_theme_constant_override("outline_size", 6)
	awakening_button.add_child(awaken_text)
	_rect(awaken_text, 23, 44, 62, 37)
	if DungeonLocale.current_locale() != "zh_CN":
		awaken_text.autowrap_mode = TextServer.AUTOWRAP_OFF
		awaken_text.clip_text = true
		_rect(awaken_text, 0, 98, 108, 32)
		DungeonStyle.fit_label_text(awaken_text, 23)
	talent_button = _paper_button("查看天赋", "查看角色天赋", "几何ui-异形白色按钮")
	talent_button.pressed.connect(show_talents)
	right_column.add_child(talent_button)
	detail_scroll = ScrollContainer.new()
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_column.add_child(detail_scroll)
	detail = VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 6)
	detail_scroll.add_child(detail)
	action_bar = HBoxContainer.new()
	action_bar.add_theme_constant_override("separation", 8)
	right_column.add_child(action_bar)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 16)
	right_column.add_child(_tabs)
	details_button = _paper_button("角色详情", "角色详情")
	details_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_button.pressed.connect(func(): set_detail_tab("details"))
	_tabs.add_child(details_button)
	style_button = _paper_button("战斗风格", "查看战斗技能")
	style_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	style_button.pressed.connect(func(): set_detail_tab("style"))
	_tabs.add_child(style_button)
	_build_character_roster()

func _build_character_roster() -> void:
	_roster_overlay = _overlay("CharacterSelection", "选择角色", Vector2(1060, 590))
	var stack: VBoxContainer = _roster_overlay.get_node("Center/Panel/Stack")
	roster_scroll = ScrollContainer.new()
	roster_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	roster_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(roster_scroll)
	roster = GridContainer.new()
	roster.columns = 4
	roster.add_theme_constant_override("h_separation", 18)
	roster.add_theme_constant_override("v_separation", 16)
	roster.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster_scroll.add_child(roster)
	for index in rows.size():
		var key = _paper_button(str(rows[index].get("title", "")).get_slice("  ", 0), "查看角色", "几何ui-白圆角矩形")
		key.custom_minimum_size = Vector2(227, 198)
		key.icon = _texture(str(rows[index].get("icon", "")))
		key.expand_icon = true
		key.add_theme_constant_override("icon_max_width", 115)
		key.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		key.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key.pressed.connect(func():
			_select_showcase(index)
			_roster_overlay.hide()
			for action in rows[index].get("buttons", []):
				if action.get("action") == "select_character" and not action.get("disabled", false) and not rows[index].get("active_character", false): command.emit("select_character", _character_id(), 0))
		roster.add_child(key)
		selections.append(key)
	_roster_overlay.hide()

func _show_character_picker() -> void:
	if rows.size() <= 1: return
	_roster_overlay.show()
	_roster_overlay.move_to_front()

func _select_showcase(index: int) -> void:
	if index < 0 or index >= rows.size(): return
	if index != selected:
		_preview_fashion = 0
		_store_context("selected_fashion", 0)
	selected = index
	for key in ["selected_id", "character_id", "selected_character"]: _store_context(key, _character_id())
	var row: Dictionary = rows[index]
	for i in selections.size():
		selections[i].modulate = Color.WHITE if _owned(rows[i]) else Color("a69a98")
	_clear(showcase)
	var fashion = _selected_fashion()
	var art_key = str(fashion.get("illustration_path", row.get("artwork", "")))
	var model_path := _fashion_model_path(fashion)
	var has_model := not model_path.is_empty()
	if not has_model:
		use_model = false
		_store_context("use_model", false)
	model_button.disabled = not has_model
	if use_model:
		var preview = DungeonModelPreview.new()
		preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
		preview.custom_minimum_size = Vector2(100, 90)
		showcase.add_child(preview)
		preview.show_model(model_path)
	else:
		var image = _picture(art_key, Vector2(100, 90))
		image.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		image.size_flags_vertical = Control.SIZE_EXPAND_FILL
		showcase.add_child(image)
	_background.texture = _texture("charamenumask_%d" % _character_id())
	model_button.icon = _texture("角色详情(已选择3D)" if use_model else "角色详情(未选择3D)")
	model_button.text = "2D" if use_model else "3D"
	model_button.tooltip_text = "此时装尚未恢复3D模型" if not has_model else "查看角色立绘" if use_model else "查看角色模型"
	var source = _source()
	portrait.texture = _texture(str(source.get("chara_icon", row.get("icon", ""))))
	name_label.text = DungeonCatalog.clean(DungeonCatalog.row_name(source)) if not source.is_empty() else str(row.get("title", "")).get_slice("  ", 0)
	var level_text = str(row.get("title", "")).get_slice("  ", 1).trim_prefix("Lv.")
	level_label.text = level_text if not level_text.is_empty() else "1"
	_level_badge.texture = _texture("Adventure_Level_5")
	picker_button.visible = rows.size() > 1
	_clear(action_bar)
	for entry in row.get("buttons", []):
		var action = str(entry.get("action", ""))
		if action in ["page:character_talents", "select_character"]: continue
		var key = _command_button(entry)
		key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		action_bar.add_child(key)
	action_bar.visible = action_bar.get_child_count() > 0
	_refresh_detail()
	_adapt.call_deferred()

func _fashion_model_path(fashion: Dictionary) -> String:
	var id := int(fashion.get("id", _character_id() * 1000 + 1))
	var path := FASHION_MODELS.path_for(id)
	if path.is_empty() and id == _character_id() * 1000 + 1:
		path = str(rows[selected].get("model", ""))
	return path

func set_detail_tab(tab: String) -> void:
	active_tab = tab
	_store_context("character_mode", tab)
	_refresh_detail()
	_adapt.call_deferred()

func _refresh_detail() -> void:
	_clear(detail)
	if rows.is_empty(): return
	var row: Dictionary = rows[selected]
	if active_tab == "style":
		_build_battle_style()
	else:
		var caption = HBoxContainer.new()
		caption.add_theme_constant_override("separation", 9)
		caption.add_child(_picture("白星标", Vector2(35, 35)))
		var caption_label = _label("角色详情", 28)
		caption_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		caption.add_child(caption_label)
		detail.add_child(caption)
		var source = _source()
		biography = _label(DungeonCatalog.clean(DungeonCatalog.description(source)) if not source.is_empty() else str(row.get("description", "")).get_slice("\n金币", 0), 20)
		biography.visible = not biography.text.begins_with("CharaData_Description_")
		biography.add_theme_constant_override("line_spacing", -6)
		biography.add_theme_color_override("font_color", PAPER)
		detail.add_child(biography)
		var stats = VBoxContainer.new()
		stats.name = "SourceAttributes"
		stats.add_theme_constant_override("separation", 4)
		detail.add_child(stats)
		for index in row.get("stats", []).size():
			var stat: Array = row.stats[index]
			var holder = PanelContainer.new()
			holder.custom_minimum_size.y = 45
			holder.add_theme_stylebox_override("panel", _source_style("17_1", 6, Color(0.18, 0.08, 0.06, 0.45)))
			stats.add_child(holder)
			var line = HBoxContainer.new()
			line.add_theme_constant_override("separation", 12)
			holder.add_child(line)
			line.add_child(_picture(STAT_ICONS[index % 5], Vector2(37, 37)))
			var stat_name = _label(str(stat[0]), 26)
			stat_name.autowrap_mode = TextServer.AUTOWRAP_OFF
			stat_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.add_child(stat_name)
			var value = _label(str(stat[1]), 25)
			value.autowrap_mode = TextServer.AUTOWRAP_OFF
			line.add_child(value)
			var bonuses: Array = row.get("stats_bonus", [])
			if index < bonuses.size() and str(bonuses[index]) not in ["", "0", "0.0", "0%", "0.0%"]:
				var bonus = _label("(" + str(bonuses[index]) + ")", 24)
				bonus.autowrap_mode = TextServer.AUTOWRAP_OFF
				bonus.add_theme_color_override("font_color", Color("ff857b") if index == 1 else Color("8fd5f4"))
				line.add_child(bonus)
	for pair in [[details_button, "details"], [style_button, "style"]]:
		pair[0].add_theme_stylebox_override("normal", _source_style("几何ui-椭圆白色按钮", 25, Color.WHITE if active_tab == pair[1] else Color("aa9186")))
	_build_spirit_skills()
	detail_scroll.scroll_vertical = 0

func _build_spirit_skills() -> void:
	if not bool(context.get("in_run", false)): return
	var spirits: Array = context.get("spirit_skills", [])
	detail.add_child(HSeparator.new())
	var title := _label("精灵技能  %d" % spirits.size(), 26)
	title.add_theme_color_override("font_color", GOLD)
	detail.add_child(title)
	if spirits.is_empty():
		detail.add_child(_label("暂无精灵", 22))
		return
	var icons := GridContainer.new()
	icons.name = "AttachedSpiritSkills"
	icons.columns = 5
	icons.add_theme_constant_override("h_separation", 10)
	icons.add_theme_constant_override("v_separation", 10)
	detail.add_child(icons)
	for spirit in spirits:
		var key := Button.new()
		key.custom_minimum_size = Vector2(68, 68)
		key.icon = DungeonStyle.texture(str(spirit.icon))
		key.expand_icon = true
		key.add_theme_constant_override("icon_max_width", 58)
		key.tooltip_text = "%s · %s\n%s" % [spirit.name, spirit.grade, spirit.description]
		key.add_theme_stylebox_override("normal", _flat(Color("352e32"), Color("e3bd62"), 1))
		key.add_theme_stylebox_override("hover", _flat(Color("564336"), GOLD, 2))
		key.pressed.connect(func(): command.emit("page:inventory", int(spirit.id), 0))
		icons.add_child(key)

func _build_battle_style() -> void:
	var fighter: Dictionary = {}
	for entry in _combat_characters:
		if int(entry.get("id", 0)) == _character_id(): fighter = entry; break
	var skills: Array = fighter.get("skills", [])
	var categories = ["普通攻击", "闪避", "战技", "爆发技"]
	for index in mini(4, skills.size()):
		var skill: Dictionary = skills[index]
		var title = _label(categories[index] + "  " + DungeonCatalog.clean(skill.get("name", "")), 27)
		title.add_theme_color_override("font_color", GOLD)
		detail.add_child(title)
		var description = SourceRichText.new()
		description.name = "SkillDescription"
		description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for font in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size"]:
			description.add_theme_font_size_override(font, 22)
		description.add_theme_color_override("default_color", PAPER)
		description.add_theme_color_override("font_shadow_color", Color("422c23"))
		description.set_source(SourceRichText.source_field("AttackData", int(skill.get("id", 0)), "description", str(skill.get("description", ""))))
		detail.add_child(description)
		if float(skill.get("cooldown", 0)) >= 1: detail.add_child(_label("冷却  %.1f 秒" % float(skill.cooldown), 20))
		detail.add_child(HSeparator.new())
	if skills.is_empty(): detail.add_child(_label("暂无技能信息", 24))

func show_talents() -> void:
	if rows.is_empty() or not _catalog: return
	if is_instance_valid(talent_view): return
	talent_view = preload("res://scripts/presentation/character_talents.gd").new()
	add_child(talent_view)
	talent_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	talent_view.configure(_catalog, context.get("systems"), _character_id())
	talent_view.marks_changed.connect(func(): command.emit("talent_marks_changed", _character_id(), 0))

func _show_attributes() -> void:
	if rows.is_empty(): return
	if is_instance_valid(_attribute_overlay): _attribute_overlay.queue_free()
	_attribute_overlay = preload("res://scripts/presentation/character_attributes_page.gd").new()
	_stage.add_child(_attribute_overlay)
	_attribute_overlay.configure(self)

func _show_fashions() -> void:
	if rows.is_empty(): return
	_store_context("fashion_open", true)
	if is_instance_valid(_fashion_overlay): _fashion_overlay.queue_free()
	_fashion_overlay = preload("res://scripts/presentation/character_fashion_page.gd").new()
	_stage.add_child(_fashion_overlay)
	_fashion_overlay.configure(self)

func _selected_equipped_fashion() -> int:
	var equipped: Dictionary = context.get("fashion_equipped", {})
	return int(equipped.get(str(_character_id()), equipped.get(_character_id(), _character_id() * 1000 + 1)))

func _selected_fashion() -> Dictionary:
	var id = _preview_fashion if _preview_fashion > 0 else _selected_equipped_fashion()
	for fashion in _fashions:
		if int(fashion.id) == id and int(fashion.chara_id) == _character_id(): return fashion
	return {}

func _fashion_owned(fashion: Dictionary) -> bool:
	if bool(fashion.get("default_unlock", false)): return true
	for id in context.get("fashion_owned", []):
		if int(id) == int(fashion.id): return true
	return false

func _overlay(node_name: String, caption: String, dimensions: Vector2) -> Control:
	var overlay = Control.new()
	overlay.name = node_name
	_stage.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade = ColorRect.new()
	shade.color = Color(0, 0, 0, 0.72)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed: _dismiss_overlay(overlay))
	overlay.add_child(shade)
	var center = CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	var panel = PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = dimensions
	panel.add_theme_stylebox_override("panel", _flat(Color("3b251e"), Color("b39b72"), 2))
	center.add_child(panel)
	var stack = VBoxContainer.new()
	stack.name = "Stack"
	stack.add_theme_constant_override("separation", 15)
	panel.add_child(stack)
	var title = HBoxContainer.new()
	stack.add_child(title)
	var label = _label(caption, 33)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_child(label)
	var close = _icon_button("退出按钮", "返回角色详情", Vector2(55, 45))
	close.pressed.connect(func(): _dismiss_overlay(overlay))
	title.add_child(close)
	return overlay

func _dismiss_overlay(overlay: Control) -> void:
	if overlay.has_method("close"):
		overlay.close()
		return
	overlay.hide()
	if overlay == _fashion_overlay: _store_context("fashion_open", false)

func _adapt() -> void:
	if not is_inside_tree() or not is_instance_valid(content): return
	# Source UI uses a landscape canvas; expand vertical room for 16:9 screens.
	var factor = minf(size.x / 2048.0, size.y / 900.0)
	if factor <= 0: return
	_stage.scale = Vector2.ONE * factor
	_stage.size = size / factor
	var width = _stage.size.x
	var height = _stage.size.y
	_rect(heading, 0, 0, width, 120)
	ROLE_NAVIGATION.place_back_button(_back_button)
	_rect(_title_art, 154, 30, 230 if DungeonLocale.current_locale() == "zh_CN" else 650, 75)
	resource_bar.position = Vector2(width - resource_bar.get_combined_minimum_size().x - 54, 25)
	_rect(content, 0, 0, width, height)
	_rect(category_tabs, 0, 137, 420, 111 * navigation.size())
	var right_x = width - 480
	_rect(showcase, 455, 67, maxf(460, right_x - 650), height - 80)
	_rect(art_commands, right_x - 150, height - 385, 110, 350)
	for button in [attributes_button, fashion_button, model_button]: button.custom_minimum_size = Vector2(110, 108)
	_rect(right_column, right_x, 145, 420, height - 162)
	_rect(identity, 0, 0, 420, 135)
	_rect(_portrait_base, 5, 5, 128, 128)
	_rect(portrait, 11, 11, 116, 116)
	_rect(picker_button, 7, 7, 126, 126)
	_rect(_level_badge, -33, -3, 67, 67)
	_rect(level_label, -30, 1, 61, 58)
	_rect(name_label, 143, 45, 155, 60)
	_rect(_awakening_glow, 275, -13, 170, 170)
	_rect(awakening_button, 307, 3, 108, 124)
	_rect(talent_button, 0, 146, 420, 58)
	_rect(_tabs, 0, right_column.size.y - 48, 420, 48)
	_rect(action_bar, 0, right_column.size.y - 121, 420, 59)
	for action in action_bar.get_children(): action.custom_minimum_size.y = 58
	var lower_space = 135 if action_bar.visible else 65
	_rect(detail_scroll, 0, 214, 420, right_column.size.y - 214 - lower_space)

func _rect(node: Control, x: float, y: float, width: float, height: float) -> void:
	node.position = Vector2(x, y)
	node.size = Vector2(width, maxf(0, height))

func _character_id() -> int:
	return int(rows[selected].get("config_id", 0)) if not rows.is_empty() else 0

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"): return
	if is_instance_valid(_recruit_overlay) and _recruit_overlay.visible:
		_recruit_overlay.queue_free()
		get_viewport().set_input_as_handled()
		return
	if is_instance_valid(_upgrade_overlay) and _upgrade_overlay.visible:
		_upgrade_overlay.queue_free()
		get_viewport().set_input_as_handled()
		return
	for overlay in [_fashion_overlay, _attribute_overlay, _roster_overlay]:
		if is_instance_valid(overlay) and overlay.visible:
			if overlay.has_method("dismiss_help") and overlay.dismiss_help():
				get_viewport().set_input_as_handled()
				return
			_dismiss_overlay(overlay)
			get_viewport().set_input_as_handled()
			return

func _store_context(key: String, value: Variant) -> void:
	context[key] = value
	if is_instance_valid(owner_page): owner_page.page_context[key] = value

func _source() -> Dictionary:
	return _catalog.find("CharData", _character_id()) if _catalog else {}

func _owned(row: Dictionary) -> bool:
	for entry in row.get("buttons", []):
		if str(entry.get("action", "")) == "select_character": return not bool(entry.get("disabled", false))
	return bool(row.get("in_run", false))

func _texture(key: String) -> Texture2D:
	return DungeonStyle.texture(str(_source_map.get(key, key)))

func _picture(key: String, dimensions: Vector2) -> TextureRect:
	var result = TextureRect.new()
	result.texture = _texture(key)
	result.custom_minimum_size = dimensions
	result.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	result.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result

func _label(text: String, font_size: int) -> Label:
	var result = DungeonStyle.label(text, font_size)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.add_theme_color_override("font_color", PAPER)
	result.add_theme_color_override("font_shadow_color", Color("422c23"))
	result.add_theme_constant_override("shadow_offset_x", 1)
	result.add_theme_constant_override("shadow_offset_y", 2)
	return result

func _source_style(key: String, border: int, tint := Color.WHITE) -> StyleBoxTexture:
	var result = StyleBoxTexture.new()
	result.texture = _texture(key)
	result.modulate_color = tint
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		result.set_texture_margin(side, border)
		result.set_content_margin(side, 3)
	if key in ["几何ui-椭圆白色按钮", "几何ui-异形白色按钮"]:
		result.set_texture_margin(SIDE_TOP, 0)
		result.set_texture_margin(SIDE_BOTTOM, 0)
		result.set_texture_margin(SIDE_LEFT, 45 if key == "几何ui-椭圆白色按钮" else 64)
		result.set_texture_margin(SIDE_RIGHT, 45 if key == "几何ui-椭圆白色按钮" else 64)
	return result

func _paper_button(text: String, hint: String, shape := "几何ui-椭圆白色按钮") -> Button:
	var result = Button.new()
	result.text = text
	result.clip_text = true
	result.tooltip_text = hint
	result.custom_minimum_size.y = 48
	result.add_theme_font_size_override("font_size", 28)
	result.resized.connect(func(): DungeonStyle.fit_button_text(result, 28))
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		result.add_theme_stylebox_override(state, _source_style(shape, 24, Color("d7c1ab") if state == "pressed" else Color("93857c") if state == "disabled" else Color.WHITE))
	result.add_theme_color_override("font_color", INK)
	result.add_theme_color_override("font_hover_color", INK)
	result.add_theme_color_override("font_pressed_color", INK)
	result.add_theme_color_override("font_disabled_color", Color("d4c6bb"))
	return result

func _icon_button(icon: String, hint: String, dimensions: Vector2) -> Button:
	var result = Button.new()
	result.icon = _texture(icon)
	result.expand_icon = true
	result.custom_minimum_size = dimensions
	result.add_theme_constant_override("icon_max_width", int(dimensions.x))
	result.tooltip_text = hint
	for state in ["normal", "hover", "pressed", "focus", "disabled"]: result.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	return result

func _vertical_button(icon: String, text: String, hint: String) -> Button:
	var result = _icon_button(icon, hint, Vector2(110, 108))
	result.text = text
	result.clip_text = true
	result.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	result.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result.add_theme_constant_override("icon_max_width", 78)
	result.add_theme_color_override("font_color", GOLD)
	result.add_theme_font_size_override("font_size", 26)
	result.resized.connect(func(): DungeonStyle.fit_button_text(result, 26))
	return result

func _command_button(entry: Dictionary) -> Button:
	var result = _paper_button(str(entry.get("text", "")), str(entry.get("text", "")))
	result.disabled = bool(entry.get("disabled", false))
	if str(entry.get("action", "")) == "op:upgrade_character" and context.get("systems"):
		result.disabled = bool(context.get("in_run", false))
		result.pressed.connect(func(): _show_upgrade(int(entry.get("id", _character_id()))))
		return result
	if str(entry.get("action", "")) == "op:unlock_character" and context.get("systems"):
		result.disabled = bool(context.get("in_run", false))
		result.pressed.connect(func(): _show_recruit(int(entry.get("id", _character_id()))))
		return result
	result.pressed.connect(func(): command.emit(str(entry.get("action", "")), entry.get("id", 0), entry.get("extra", 0)))
	return result

func _show_upgrade(id: int) -> void:
	if is_instance_valid(_upgrade_overlay): _upgrade_overlay.queue_free()
	_upgrade_overlay = preload("res://scripts/presentation/character_upgrade_dialog.gd").new()
	_stage.add_child(_upgrade_overlay)
	_upgrade_overlay.configure(context.systems, id)
	_upgrade_overlay.confirmed.connect(func(character_id): command.emit("op:upgrade_character", character_id, 0))
	_upgrade_overlay.canceled.connect(func(): _upgrade_overlay.hide())

func _show_recruit(id: int) -> void:
	if is_instance_valid(_recruit_overlay): _recruit_overlay.queue_free()
	_recruit_overlay = preload("res://scripts/presentation/character_recruit_dialog.gd").new()
	_stage.add_child(_recruit_overlay)
	_recruit_overlay.configure(context.systems, id)
	_recruit_overlay.confirmed.connect(func(character_id): command.emit("op:unlock_character", character_id, 0))
	_recruit_overlay.canceled.connect(func(): _recruit_overlay.hide())

func _flat(fill: Color, border := Color.TRANSPARENT, width := 1) -> StyleBoxFlat:
	var result = DungeonStyle.box(fill, border, width)
	result.set_corner_radius_all(3)
	result.set_content_margin_all(20)
	return result

func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
