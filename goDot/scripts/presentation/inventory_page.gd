class_name DungeonInventoryPage
extends Control

signal command(kind: String, id: Variant, extra: Variant)
signal closed
signal back_requested

const INK := Color("3d3430")
const GOLD := Color("f0ce70")
const ITEM_ART = preload("res://scripts/presentation/item_art.gd")
const ROLE_NAVIGATION = preload("res://scripts/presentation/role_navigation.gd")
const SOURCE_RICH_TEXT = preload("res://scripts/presentation/source_rich_text.gd")
const SELECTION_HIGHLIGHT = preload("res://scripts/presentation/selection_highlight.gd")

var owner_page: DungeonMenuPage
var rows: Array = []
var context: Dictionary = {}
var selected := -1
var selected_inventory_key := ""
var navigation: Array[Button] = []
var selections: Array[Button] = []
var resource_bar: HBoxContainer
var item_scroll: ScrollContainer
var _grid_padding: MarginContainer
var grid: GridContainer
var detail_scroll: ScrollContainer
var detail: VBoxContainer
var detail_icon: TextureRect
var title_label: Label
var name_label: Label
var description_label: SourceRichText
var action_bar: HBoxContainer
var empty_label: Label
var _catalog: DungeonCatalog
var _systems: RefCounted
var _art: Dictionary = {}
var _nav_icons: Array[TextureRect] = []
var _nav_labels: Array[Label] = []
var _nav_backgrounds: Array[TextureRect] = []
var _selection_frames: Array[TextureRect] = []
var _count_labels: Array[Label] = []
var _item_icons: Array[TextureRect] = []
var _paper: NinePatchRect
var _paper_frame: NinePatchRect
var _emblem: TextureRect
var _back: Button
var _title_art: TextureRect
var _compact := false
var filter_bar: HBoxContainer
var filter_buttons: Array[Button] = []
var inventory_filter := "all"
var _spirit_skills: RefCounted
var _ability_descriptions: RefCounted

func configure(host: DungeonMenuPage, data: Array, page_context: Dictionary = {}) -> void:
	owner_page = host
	rows = data.filter(func(row): return row is Dictionary and (int(row.get("material_id", 0)) > 0 or int(row.get("loot_id", 0)) > 0))
	context = page_context
	_catalog = context.get("catalog") as DungeonCatalog
	_systems = context.get("systems")
	if _systems != null:
		_spirit_skills = preload("res://scripts/domain/spirit_skills.gd").new(_systems)
		_ability_descriptions = preload("res://scripts/domain/ability_descriptions.gd").new(_systems)
	for path in ["res://assets/ui/role_character/resource_map.json", "res://assets/ui/role_inventory/resource_map.json"]:
		if FileAccess.file_exists(path):
			var mapping = JSON.parse_string(FileAccess.get_file_as_string(path))
			if mapping is Dictionary: _art.merge(mapping, true)
	theme = DungeonStyle.theme()
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	clip_contents = true
	var background := _picture("charamenumask_1")
	background.stretch_mode = TextureRect.STRETCH_SCALE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	_build_header()
	_build_navigation()
	_build_items()
	_build_detail()
	resized.connect(_adapt)
	var requested_item := str(context.get("selected_inventory_key", ""))
	set_filter(str(context.get("inventory_filter", "all")))
	select_item(requested_item)
	_adapt.call_deferred()

func _build_header() -> void:
	_back = ROLE_NAVIGATION.create_back_button()
	_back.pressed.connect(func(): back_requested.emit())
	add_child(_back)
	_title_art = _picture("角色详情")
	add_child(_title_art)
	title_label = DungeonStyle.localize_artwork_title(_title_art, "角色详情", 36)
	resource_bar = HBoxContainer.new()
	resource_bar.add_theme_constant_override("separation", 14)
	add_child(resource_bar)
	for resource in context.get("resources", []):
		var key := ""
		var value := ""
		if resource is Dictionary:
			key = str(resource.get("icon", resource.get("key", "")))
			value = str(resource.get("value", resource.get("amount", "")))
		elif resource is Array and resource.size() >= 2:
			key = str(resource[0])
			value = str(resource[1])
		var counter := Control.new()
		counter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		resource_bar.add_child(counter)
		var frame := _picture("货币_底")
		frame.stretch_mode = TextureRect.STRETCH_SCALE
		frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		counter.add_child(frame)
		var icon := _picture(key)
		icon.name = "Icon"
		if key.begins_with("material:"): icon.texture = ITEM_ART.source_texture(int(key.get_slice(":", 1)), true)
		elif key.begins_with("loot:"): icon.texture = ITEM_ART.source_texture(int(key.get_slice(":", 1)))
		counter.add_child(icon)
		var caption := _label(value, 25)
		caption.name = "Value"
		caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		counter.add_child(caption)

func _build_navigation() -> void:
	var entries: Array = context.get("role_navigation", [])
	if entries.is_empty():
		entries = [{"label": "角色", "page": "characters"}, {"label": "武器", "page": "weapons"}]
		if bool(context.get("in_run", false)): entries.append({"label": "背包", "page": "inventory"})
		entries.append({"label": "仓库", "page": "storage"})
	var icons := {"characters": "角色详情", "weapons": "武器", "inventory": "道具", "storage": "仓库", "partners": "怪物伙伴"}
	for entry in entries:
		var destination := str(entry.get("page", ""))
		var current := destination == str(context.get("page", "inventory"))
		var button := Button.new()
		button.text = str(entry.get("label", ""))
		button.add_theme_color_override("font_color", Color.TRANSPARENT)
		button.add_theme_color_override("font_hover_color", Color.TRANSPARENT)
		button.add_theme_color_override("font_pressed_color", Color.TRANSPARENT)
		button.add_theme_color_override("font_focus_color", Color.TRANSPARENT)
		button.focus_mode = Control.FOCUS_NONE
		button.tooltip_text = button.text
		button.set_meta("page", destination)
		_clear_button(button)
		button.pressed.connect(func():
			if destination != str(context.get("page", "inventory")): command.emit("page:" + destination, int(context.get("character_id", 0)) if destination == "weapons" else 0, 0))
		add_child(button)
		navigation.append(button)
		var backdrop := _picture("分类选中" if current else "侧边按钮暗")
		if not current: backdrop.modulate.a = 0.13
		backdrop.stretch_mode = TextureRect.STRETCH_SCALE
		backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		button.add_child(backdrop)
		_nav_backgrounds.append(backdrop)
		var icon := _picture(str(icons.get(destination, "仓库")) + ("(选择)" if current else "(未选择)"))
		button.add_child(icon)
		_nav_icons.append(icon)
		var text := _label(button.text, 32)
		text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		text.add_theme_color_override("font_color", Color.WHITE if current else Color("d2c5bf"))
		button.add_child(text)
		_nav_labels.append(text)

func _build_items() -> void:
	filter_bar = HBoxContainer.new()
	filter_bar.add_theme_constant_override("separation", 8)
	filter_bar.visible = str(context.get("page", "")) == "inventory" and bool(context.get("in_run", false))
	add_child(filter_bar)
	var group := ButtonGroup.new()
	for entry in [["all", "全部"], ["spirits", "精灵"]]:
		var button := Button.new()
		button.text = str(entry[1])
		button.toggle_mode = true
		button.button_group = group
		button.pressed.connect(func(): set_filter(str(entry[0])))
		for state in ["normal", "hover", "pressed", "focus"]:
			var style := DungeonStyle.box(Color("6c5037") if state == "pressed" else Color("352d2b"), GOLD if state == "pressed" else Color("938477"), 1)
			style.set_content_margin_all(6)
			button.add_theme_stylebox_override(state, style)
		filter_bar.add_child(button)
		filter_buttons.append(button)
	item_scroll = ScrollContainer.new()
	item_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	item_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	item_scroll.follow_focus = true
	add_child(item_scroll)
	_grid_padding = MarginContainer.new()
	_grid_padding.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_scroll.add_child(_grid_padding)
	grid = GridContainer.new()
	grid.columns = 6
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid_padding.add_child(grid)
	for index in rows.size():
		var row: Dictionary = rows[index]
		var button := Button.new()
		button.tooltip_text = _item_name(row)
		button.focus_mode = Control.FOCUS_ALL
		_clear_button(button)
		button.pressed.connect(func():
			select_item(index)
			item_scroll.call_deferred("ensure_control_visible", _selection_frames[index]))
		grid.add_child(button)
		selections.append(button)
		var rare := clampi(int(row.get("star_num", 1)), 1, 5)
		var frame := _picture("slotfg_rare_square_%d_v2" % rare)
		if frame.texture == null: frame.texture = _texture("slotfg_rare_square_1_v2")
		frame.stretch_mode = TextureRect.STRETCH_SCALE
		frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		button.add_child(frame)
		var icon := TextureRect.new()
		icon.texture = _item_texture(row)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(icon)
		_item_icons.append(icon)
		var count_background := _picture("24")
		count_background.name = "CountBackground"
		count_background.stretch_mode = TextureRect.STRETCH_SCALE
		button.add_child(count_background)
		var count := _label(str(_item_count(row)), 24)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		button.add_child(count)
		_count_labels.append(count)
		var selection := _picture("选择高亮")
		selection.stretch_mode = TextureRect.STRETCH_SCALE
		selection.z_index = 1
		button.add_child(selection)
		_selection_frames.append(selection)
		button.resized.connect(func(): SELECTION_HIGHLIGHT.place(selection, button.size))
	empty_label = _label("暂无物品", 25)
	empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	empty_label.visible = rows.is_empty()
	add_child(empty_label)
	_style_scrollbar(item_scroll)

func set_filter(mode: String) -> void:
	inventory_filter = "spirits" if mode == "spirits" and filter_bar.visible else "all"
	context["inventory_filter"] = inventory_filter
	if is_instance_valid(owner_page): owner_page.page_context["inventory_filter"] = inventory_filter
	for index in filter_buttons.size(): filter_buttons[index].set_pressed_no_signal(index == (1 if inventory_filter == "spirits" else 0))
	var visible_count := 0
	var spirit_count := 0
	for index in selections.size():
		var spirit := _is_spirit(rows[index])
		if spirit: spirit_count += 1
		selections[index].visible = inventory_filter == "all" or spirit
		if selections[index].visible: visible_count += 1
	filter_buttons[0].text = "全部 %d" % rows.size()
	filter_buttons[1].text = "精灵 %d" % spirit_count
	empty_label.visible = visible_count == 0
	empty_label.text = "暂无精灵" if inventory_filter == "spirits" else "暂无物品"
	if selected < 0 or not selections[selected].visible: select_item(-1)
	if is_instance_valid(detail_scroll): detail_scroll.scroll_vertical = 0
	_adapt.call_deferred()

func _is_spirit(row: Dictionary) -> bool:
	return _spirit_skills != null and not _spirit_skills.definition(int(row.get("loot_id", 0))).is_empty()

func _build_detail() -> void:
	_paper_frame = _sliced("几何ui-暗圆角矩形", 30)
	add_child(_paper_frame)
	_paper = _sliced("物品详情_底", 52)
	_paper.self_modulate = Color("f9f8f2")
	add_child(_paper)
	_emblem = _picture("bg装饰")
	_emblem.modulate.a = 0.45
	add_child(_emblem)
	detail_icon = TextureRect.new()
	detail_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	detail_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	detail_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(detail_icon)
	detail_scroll = ScrollContainer.new()
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(detail_scroll)
	detail = VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 14)
	detail_scroll.add_child(detail)
	name_label = _label("", 29)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_color_override("font_color", Color("e4ae28"))
	name_label.add_theme_color_override("font_outline_color", Color("392e24"))
	name_label.add_theme_constant_override("outline_size", 5)
	detail.add_child(name_label)
	var line := HSeparator.new()
	var rule := StyleBoxLine.new()
	rule.color = Color("c3b6a9")
	rule.thickness = 1
	line.add_theme_stylebox_override("separator", rule)
	line.custom_minimum_size.y = 1
	detail.add_child(line)
	description_label = SOURCE_RICH_TEXT.new()
	description_label.add_theme_color_override("default_color", INK)
	description_label.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	description_label.add_theme_color_override("font_outline_color", Color("f5f2ea"))
	description_label.add_theme_constant_override("outline_size", 1)
	detail.add_child(description_label)
	action_bar = HBoxContainer.new()
	action_bar.add_theme_constant_override("separation", 8)
	detail.add_child(action_bar)
	_style_scrollbar(detail_scroll)

func select_item(index_or_key: Variant) -> void:
	var next := int(index_or_key) if index_or_key is int else -1
	if index_or_key is String:
		for index in rows.size():
			if _item_key(rows[index]) == index_or_key:
				next = index
				break
	if next < 0 or next >= rows.size() or not selections[next].visible:
		next = -1
		for index in selections.size():
			if selections[index].visible:
				next = index
				break
	selected = next
	selected_inventory_key = _item_key(rows[selected]) if selected >= 0 else ""
	context["selected_inventory_key"] = selected_inventory_key
	if is_instance_valid(owner_page): owner_page.page_context["selected_inventory_key"] = selected_inventory_key
	for index in _selection_frames.size(): _selection_frames[index].visible = index == selected
	if not is_instance_valid(name_label): return
	for child in action_bar.get_children():
		action_bar.remove_child(child)
		child.queue_free()
	if selected < 0:
		name_label.text = "暂无精灵" if inventory_filter == "spirits" else "暂无物品"
		description_label.set_source("")
		detail_icon.texture = null
		return
	var row: Dictionary = rows[selected]
	name_label.text = _item_name(row)
	detail_icon.texture = _item_texture(row)
	description_label.set_source(_item_description(row))
	for action in row.get("buttons", []):
		var button := Button.new()
		button.text = str(action.get("text", action.get("label", "开启")))
		button.disabled = bool(action.get("disabled", false))
		button.custom_minimum_size = Vector2(88, 40)
		button.add_theme_stylebox_override("normal", DungeonStyle.artwork_box(_art.get("几何ui-白圆角矩形", ""), 12))
		button.add_theme_color_override("font_color", INK)
		button.pressed.connect(func(): command.emit(str(action.get("action", action.get("kind", ""))), action.get("id", 0), action.get("extra", 0)))
		action_bar.add_child(button)
	detail_scroll.scroll_vertical = 0
	_adapt.call_deferred()

func _item_key(row: Dictionary) -> String:
	return ("material:" + str(int(row.material_id))) if row.has("material_id") else ("loot:" + str(int(row.get("loot_id", row.get("config_id", 0)))))

func _item_count(row: Dictionary) -> int:
	if row.has("count"): return int(row.count)
	if _systems != null:
		if row.has("material_id"): return int(_systems.material(int(row.material_id)))
		return int(_systems.profile.data.run.inventory.get(str(int(row.get("loot_id", 0))), 0))
	return 0

func _item_name(row: Dictionary) -> String:
	var result := str(row.get("title", ""))
	if "  ×" in result: result = result.get_slice("  ×", 0)
	return result

func _item_texture(row: Dictionary) -> Texture2D:
	var material := row.has("material_id")
	var id := int(row.get("material_id", row.get("loot_id", row.get("config_id", 0))))
	var original: Texture2D = ITEM_ART.source_texture(id, material)
	if original: return original
	var key := str(row.get("icon", ""))
	if key.begins_with("material:") or key.begins_with("loot:"): return null
	return _texture(key)

func _item_description(row: Dictionary) -> String:
	var text := str(row.get("source_description", ""))
	if text.is_empty() and _catalog != null:
		if row.has("material_id"):
			text = DungeonCatalog.description(_catalog.find("MaterialData", int(row.material_id)))
		else:
			var loot_id := int(row.get("loot_id", 0))
			var ability_id := int(_catalog.find("LootData", loot_id).get("ability_item_id", loot_id))
			text = _ability_descriptions.source(ability_id, loot_id, context.get("combat")) if _ability_descriptions != null else DungeonCatalog.description(_catalog.find("AbilityItems", ability_id))
	if text.is_empty(): text = str(row.get("description", ""))
	var acquisition := str(row.get("acquisition", ""))
	if not acquisition.is_empty(): text += "\n<color=#af810e>获取途径：</color>" + acquisition
	if _is_spirit(row):
		var spirit: Dictionary = _spirit_skills.definition(int(row.loot_id))
		text = "<color=#886115>已附加 · %s</color>\n\n%s" % [spirit.grade, text]
		var options: Array = _spirit_skills.upgrade_options(int(row.loot_id))
		if not options.is_empty():
			text += "\n\n<color=#886115>进阶与融合</color>"
			for option in options:
				text += "\n%s · %s" % [option.name, "可获取" if option.available else "未满足条件"]
				if not option.available and not str(option.requirement).is_empty(): text += "\n" + str(option.requirement)
	return text.replace("|", "\n")

func _adapt() -> void:
	if not is_instance_valid(grid) or size.x <= 0 or size.y <= 0: return
	_compact = size.y < 600
	var unit := size.y / 1080.0
	var top := size.y * 0.145
	var nav_width := size.x * 0.205
	var detail_left := size.x * 0.76
	var detail_width := size.x * 0.22
	var grid_left := size.x * 0.25
	var grid_width := size.x * 0.435
	var slot := grid_width / 6.8
	var gap := slot * 0.08
	var padding := ceili(slot * 0.18)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]: _grid_padding.add_theme_constant_override(side, padding)
	ROLE_NAVIGATION.place_back_button(_back, ROLE_NAVIGATION.scale_factor(size))
	_place(_title_art, Vector2(_back.get_rect().end.x + 12, _back.position.y), Vector2(300 * unit, _back.size.y))
	if DungeonLocale.current_locale() != "zh_CN":
		_title_art.size.x = size.x * 0.4
		DungeonStyle.fit_label_text(title_label, roundi(54 * unit), 10)
	var resource_count := maxi(1, resource_bar.get_child_count())
	var resource_width := minf(220 * unit, size.x * 0.47 / resource_count)
	_place(resource_bar, Vector2(size.x - size.x * 0.025 - resource_width * resource_count - maxf(0, resource_count - 1) * 10 * unit, size.y * 0.025), Vector2(resource_width * resource_count + maxf(0, resource_count - 1) * 10 * unit, 55 * unit))
	resource_bar.add_theme_constant_override("separation", roundi(10 * unit))
	for counter in resource_bar.get_children():
		counter.custom_minimum_size = Vector2(resource_width, 55 * unit)
		_place(counter.get_node("Icon"), Vector2(-12 * unit, -8 * unit), Vector2(72, 72) * unit)
		_place(counter.get_node("Value"), Vector2(58 * unit, 0), Vector2(resource_width - 60 * unit, 55 * unit))
		counter.get_node("Value").add_theme_font_size_override("font_size", 14 if _compact else 25)
	var nav_height := minf(size.y * 0.125, (size.y - top - 12 * unit) / maxi(1, navigation.size()))
	for index in navigation.size():
		_place(navigation[index], Vector2(0, top + index * nav_height), Vector2(nav_width, nav_height))
		_place(_nav_icons[index], Vector2(nav_width * 0.22, nav_height * 0.18), Vector2(nav_height * 0.56, nav_height * 0.56))
		_place(_nav_labels[index], Vector2(nav_width * 0.43, 0), Vector2(nav_width * 0.56, nav_height))
		_nav_labels[index].add_theme_font_size_override("font_size", 18 if _compact else 32)
	var filter_height := (40.0 if _compact else 48.0) if filter_bar.visible else 0.0
	_place(filter_bar, Vector2(grid_left, top), Vector2(grid_width, filter_height))
	for button in filter_buttons:
		button.custom_minimum_size = Vector2(92, filter_height)
		button.add_theme_font_size_override("font_size", 15 if _compact else 21)
	_place(item_scroll, Vector2(grid_left, top + filter_height + 8 * unit), Vector2(grid_width + 12 * unit, size.y - top - filter_height - 30 * unit))
	grid.add_theme_constant_override("h_separation", roundi(gap))
	grid.add_theme_constant_override("v_separation", roundi(gap))
	for index in selections.size():
		selections[index].custom_minimum_size = Vector2(slot, slot)
		_place(_item_icons[index], Vector2(slot * 0.075, slot * 0.04), Vector2(slot * 0.85, slot * 0.88))
		_count_labels[index].add_theme_font_size_override("font_size", 14 if _compact else 26)
		var count_height := maxf(_count_labels[index].get_combined_minimum_size().y, maxf(24.0 if _compact else 35.0, slot * 0.27))
		var count_y := slot - count_height - 3 * unit
		_place(selections[index].get_node("CountBackground"), Vector2(slot * 0.025, count_y), Vector2(slot * 0.95, count_height))
		_place(_count_labels[index], Vector2(slot * 0.025, count_y), Vector2(slot * 0.95, count_height))
		var tile_size := selections[index].size if selections[index].size.x > 0 else Vector2(slot, slot)
		SELECTION_HIGHLIGHT.place(_selection_frames[index], tile_size)
	_place(empty_label, item_scroll.position, item_scroll.size)
	_place_slice(_paper_frame, Vector2(detail_left, size.y * 0.116), Vector2(detail_width, size.y * 0.86), unit / 2.0)
	_place_slice(_paper, Vector2(detail_left + 7 * unit, size.y * 0.116 + 7 * unit), Vector2(detail_width - 14 * unit, size.y * 0.86 - 14 * unit), unit / 2.0)
	_place(_emblem, Vector2(detail_left + detail_width * 0.10, size.y * 0.15), Vector2(detail_width * 0.80, detail_width * 0.80))
	_place(detail_icon, Vector2(detail_left + detail_width * 0.24, size.y * 0.20), Vector2(detail_width * 0.52, size.y * 0.20))
	_place(detail_scroll, Vector2(detail_left + detail_width * 0.09, size.y * 0.453), Vector2(detail_width * 0.82, size.y * 0.49))
	name_label.add_theme_font_size_override("font_size", 18 if _compact else 30)
	name_label.add_theme_constant_override("outline_size", 3 if _compact else 5)
	description_label.add_theme_font_size_override("normal_font_size", 13 if _compact else 23)
	description_label.add_theme_font_size_override("bold_font_size", 13 if _compact else 23)
	description_label.set_source(description_label.source_text)
	detail.add_theme_constant_override("separation", 8 if _compact else 14)
	for button in action_bar.get_children():
		button.custom_minimum_size = Vector2(64, 30) if _compact else Vector2(100, 48)
		button.add_theme_font_size_override("font_size", 14 if _compact else 23)

func _place(node: Control, at: Vector2, dimensions: Vector2) -> void:
	node.position = at
	node.size = dimensions

func _place_slice(node: NinePatchRect, at: Vector2, dimensions: Vector2, source_scale: float) -> void:
	# The source Image is sliced and has PixelsPerUnitMultiplier = 2.
	node.position = at
	node.scale = Vector2.ONE * source_scale
	node.size = dimensions / source_scale

func _sliced(key: String, border: int) -> NinePatchRect:
	var image := NinePatchRect.new()
	image.texture = _texture(key)
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]: image.set_patch_margin(side, border)
	return image

func _texture(key: String) -> Texture2D:
	var path := str(_art.get(key, ""))
	if not path.is_empty() and ResourceLoader.exists(path): return load(path) as Texture2D
	if key.begins_with("res://") and ResourceLoader.exists(key): return load(key) as Texture2D
	return DungeonStyle.texture(key)

func _picture(key: String) -> TextureRect:
	var image := TextureRect.new()
	image.texture = _texture(key)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return image

func _label(text: String, font_size: int) -> Label:
	var label := DungeonStyle.label(text, font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _clear_button(button: Button) -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())

func _style_scrollbar(scroll: ScrollContainer) -> void:
	var bar := scroll.get_v_scroll_bar()
	bar.custom_minimum_size.x = 6
	bar.add_theme_stylebox_override("scroll", DungeonStyle.artwork_box(_art.get("bg_slider_bottom_01", ""), 2))
	for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
		bar.add_theme_stylebox_override(state, DungeonStyle.artwork_box(_art.get("下拉条", ""), 2))
