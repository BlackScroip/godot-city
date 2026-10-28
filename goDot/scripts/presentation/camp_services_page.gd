class_name DungeonCampServicesPage
extends Control

signal command(kind: String, id: Variant, extra: Variant)
signal closed
signal back_requested

const ROLE_NAVIGATION = preload("res://scripts/presentation/role_navigation.gd")
const INK := Color("333c3d")
const MUTED := Color("69716e")
const PAPER := Color("eeeae0")
const TITLES := {"partners": "伙伴", "work": "伙伴派遣", "dispatch": "派遣详情", "meals": "篝火餐厅", "npcs": "营地居民", "npc": "居民交谈", "decorations": "主城装饰", "archive": "战利品图鉴", "history": "冒险档案", "extra_challenges": "悬赏委托", "tokens": "冒险徽章", "amplifiers": "冒险徽章", "resources": "资源与凭证", "resource": "资源详情", "training": "训练场"}
var rows: Array = []
var context: Dictionary = {}
var owner_page: DungeonMenuPage
var selected := 0
var page_id := ""
var compact := false
var collection: GridContainer
var collection_scroll: ScrollContainer
var details: VBoxContainer
var detail_scroll: ScrollContainer
var toolbar: HBoxContainer
var heading: HBoxContainer
var body: HBoxContainer
var root_box: VBoxContainer
var choice_buttons: Array[Button] = []
var action_buttons: Array[Button] = []
var search: LineEdit
var filter: OptionButton
var _query := ""
var _filter := 0
var _category := "全部分类"
var _built := false
var summary_bar: HBoxContainer
var _source_sprites: Dictionary = {}

func configure(host: DungeonMenuPage, data: Array, page_context: Dictionary = {}) -> void:
	owner_page = host
	rows = data
	context = page_context
	page_id = str(context.get("page", ""))
	var folder = {"tokens": "relationship_tokens", "amplifiers": "relationship_tokens", "token_compose_preview": "relationship_tokens", "token_reroll_preview": "relationship_tokens", "extra_challenges": "extra_challenges", "meals": "cat_meals", "work": "work_space", "partners": "partner_select", "decorations": "decoration_menu", "history": "rogue_records"}.get(page_id, "")
	var evidence_path = "res://assets/ui/camp/%s/prefab-layout.json" % str(folder)
	if not str(folder).is_empty() and FileAccess.file_exists(evidence_path):
		var evidence = JSON.parse_string(FileAccess.get_file_as_string(evidence_path))
		for sprite in evidence.get("sprites", []): _source_sprites[str(sprite.name)] = str(sprite.path)
	selected = clampi(int(context.get("service_selection", 0)), 0, maxi(0, rows.size() - 1))
	_query = str(context.get("service_query", ""))
	_filter = clampi(int(context.get("service_filter", 0)), 0, 2)
	_category = str(context.get("service_category", "全部分类"))
	var selected_key = str(context.get("service_selected_key", ""))
	if not selected_key.is_empty():
		for index in rows.size():
			if _row_key(index) == selected_key:
				selected = index
				break
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	clip_contents = true
	theme = DungeonStyle.theme()
	resized.connect(_adapt)
	_build()

func _label(text: String, font_size := 18, color := INK) -> Label:
	var label = DungeonStyle.label(DungeonCatalog.clean(text), font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _skin(key: String, fallback := PAPER) -> StyleBox:
	var texture = DungeonStyle.texture(str(_source_sprites.get(key, key)))
	if texture == null: return DungeonStyle.box(fallback)
	var box = StyleBoxTexture.new()
	box.texture = texture
	box.texture_margin_left = 12
	box.texture_margin_right = 12
	box.texture_margin_top = 12
	box.texture_margin_bottom = 12
	box.set_content_margin_all(12)
	return box

func _button(text: String, callback: Callable, disabled := false) -> Button:
	var button = Button.new()
	button.text = text
	button.disabled = disabled
	button.custom_minimum_size = Vector2(44, 42 if compact else 48)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_disabled_color", MUTED)
	button.add_theme_font_size_override("font_size", 16 if compact else 18)
	button.add_theme_stylebox_override("normal", _skin("几何ui-白圆角矩形"))
	button.add_theme_stylebox_override("hover", _skin("商店按钮_底"))
	button.add_theme_stylebox_override("pressed", _skin("几何ui-暗圆角矩形"))
	button.add_theme_stylebox_override("disabled", DungeonStyle.box(Color("c5c8c2")))
	button.pressed.connect(callback)
	return button

func _build() -> void:
	var collection_y = int(context.get("service_collection_scroll", 0))
	var detail_y = int(context.get("service_detail_scroll", 0))
	for child in get_children(): remove_child(child); child.queue_free()
	choice_buttons.clear()
	action_buttons.clear()
	compact = size.y > 0 and (size.y < 600 or size.x < 1000)
	var background = ColorRect.new()
	background.color = Color("d5dcd7")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin = MarginContainer.new()
	margin.name = "PageMargin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + edge, 12 if compact else 24)
	var header_margin = ROLE_NAVIGATION.header_margin(size)
	margin.add_theme_constant_override("margin_left", int(header_margin.x))
	margin.add_theme_constant_override("margin_top", int(header_margin.y))
	add_child(margin)
	root_box = VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 8 if compact else 16)
	margin.add_child(root_box)
	heading = HBoxContainer.new()
	heading.add_theme_constant_override("separation", 12)
	root_box.add_child(heading)
	var back = ROLE_NAVIGATION.create_header_back_button(size, "返回" if context.has("back_action") else "关闭")
	back.pressed.connect(func(): back_requested.emit())
	heading.add_child(back)
	var title = _label(owner_page.title_label.text if page_id == "archive" else str(TITLES.get(page_id, owner_page.title_label.text)), 22 if compact else 28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	heading.add_child(title)
	for resource in context.get("resources", []):
		var line = HBoxContainer.new()
		heading.add_child(line)
		line.add_child(DungeonStyle.picture(str(resource[0]), Vector2(24, 24) if compact else Vector2(32, 32)))
		var amount = _label(str(resource[1]), 16 if compact else 20)
		amount.autowrap_mode = TextServer.AUTOWRAP_OFF
		amount.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.add_child(amount)
	var close = _button("×", func(): closed.emit())
	close.tooltip_text = "关闭"
	close.custom_minimum_size = Vector2(44, 44)
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	heading.add_child(close)
	toolbar = HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 8)
	root_box.add_child(toolbar)
	_build_toolbar()
	toolbar.visible = not _detail_only()
	_build_summary()
	body = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12 if compact else 24)
	root_box.add_child(body)
	collection_scroll = ScrollContainer.new()
	collection_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	collection_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	collection_scroll.size_flags_stretch_ratio = 1.2
	collection_scroll.visible = not _detail_only()
	body.add_child(collection_scroll)
	collection_scroll.get_v_scroll_bar().value_changed.connect(func(value): context.service_collection_scroll = int(value))
	collection = GridContainer.new()
	collection.columns = _columns()
	collection.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	collection.add_theme_constant_override("h_separation", 8)
	collection.add_theme_constant_override("v_separation", 8)
	collection_scroll.add_child(collection)
	detail_scroll = ScrollContainer.new()
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var detail_skin = {"tokens": "信物详情底", "amplifiers": "信物详情底", "meals": "new点菜表底框_2", "work": "物品详情_底", "extra_challenges": "详情_底框_2"}.get(page_id, "")
	if not str(detail_skin).is_empty(): detail_scroll.add_theme_stylebox_override("panel", _skin(str(detail_skin)))
	body.add_child(detail_scroll)
	detail_scroll.get_v_scroll_bar().value_changed.connect(func(value): context.service_detail_scroll = int(value))
	details = VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 10 if compact else 16)
	detail_scroll.add_child(details)
	_populate()
	collection_scroll.set_deferred("scroll_vertical", collection_y)
	detail_scroll.set_deferred("scroll_vertical", detail_y)
	_built = true

func _columns() -> int:
	if page_id in ["work", "npcs", "npc", "history", "extra_challenges", "resources"]: return 1
	return 2 if compact else 3

func _detail_only() -> bool:
	return page_id in ["resource", "training", "dispatch", "token_compose_preview", "token_reroll_preview", "extra_challenges_receive", "extra_challenge_delete"]

func _build_toolbar() -> void:
	search = LineEdit.new()
	search.placeholder_text = "搜索"
	search.text = _query
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.custom_minimum_size = Vector2(80, 40)
	search.text_changed.connect(func(value): _query = value; _filter_changed())
	toolbar.add_child(search)
	filter = OptionButton.new()
	filter.add_item("全部")
	filter.add_item({"archive": "已发现", "history": "胜利", "work": "派遣中", "meals": "已研究", "decorations": "使用中", "extra_challenges": "可领取", "partners": "已解锁", "resources": "持有"}.get(page_id, "可操作"))
	filter.add_item({"archive": "未发现", "history": "其他结局", "work": "待派遣", "meals": "待研究", "decorations": "其他外观", "extra_challenges": "进行中", "partners": "待解锁", "resources": "未持有"}.get(page_id, "待解锁"))
	filter.selected = _filter
	filter.custom_minimum_size = Vector2(112, 40)
	filter.item_selected.connect(func(value): _filter = value; _filter_changed())
	toolbar.add_child(filter)
	var categories: Array[String] = ["全部分类"]
	for row in rows:
		var value = str(row.get("category", ""))
		if not value.is_empty() and not categories.has(value): categories.append(value)
	if not categories.has(_category): _category = categories[0]
	if categories.size() > 1:
		var category = OptionButton.new()
		category.custom_minimum_size = Vector2(110, 40)
		for value in categories: category.add_item(value)
		category.selected = maxi(0, categories.find(_category))
		category.item_selected.connect(func(index): _category = categories[index]; _filter_changed())
		toolbar.add_child(category)

func _filter_changed() -> void:
	_store_service_state()
	_populate()
	collection_scroll.scroll_vertical = 0
	detail_scroll.scroll_vertical = 0

func _row_key(index: int) -> String:
	if index < 0 or index >= rows.size(): return ""
	var row: Dictionary = rows[index]
	if row.has("service_key"): return str(row.service_key)
	for field in ["token_id", "loot_id", "config_id", "id"]:
		if int(row.get(field, 0)) > 0: return field + ":" + str(row[field])
	return "row:" + str(index)

func _store_service_state() -> void:
	context.service_selection = selected
	context.service_query = _query
	context.service_filter = _filter
	context.service_category = _category
	if selected >= 0: context.service_selected_key = _row_key(selected)

func _matches(row: Dictionary) -> bool:
	if _category != "全部分类" and str(row.get("category", "")) != _category: return false
	if not _query.is_empty() and not (str(row.get("title", "")) + str(row.get("description", ""))).containsn(_query): return false
	if _filter != 0 and not bool(row.get("service_filterable", true)): return false
	var actionable = false
	for entry in row.get("buttons", []):
		if not bool(entry.get("disabled", false)): actionable = true
	var systems = context.get("systems")
	var row_id = int(row.get("config_id", row.get("id", 0)))
	if row.has("filter_primary"): actionable = bool(row.filter_primary)
	elif page_id == "archive" and systems != null: actionable = int(row.get("loot_id", 0)) in systems.profile.data.discovered_loot
	elif page_id == "work": actionable = str(row.get("description", "")).contains("已储存")
	elif page_id == "decorations": actionable = str(row.get("description", "")).contains("使用中")
	elif page_id == "meals" and systems != null and row_id > 0: actionable = int(systems.meal_status(row_id).get("researched_level", 0)) > 0
	elif page_id == "partners" and systems != null: actionable = int(systems.profile.data.partners.get(str(row_id), 0)) > 0
	elif page_id == "history": actionable = str(row.get("outcome", "")) == "victory" or str(row.get("title", "")).contains("胜利")
	elif page_id == "extra_challenges":
		actionable = false
		for entry in row.get("buttons", []):
			if str(entry.get("text", "")).contains("领取") and not bool(entry.get("disabled", false)): actionable = true
	if _filter == 1 and not actionable: return false
	if _filter == 2 and actionable: return false
	return true

func _build_summary() -> void:
	if page_id != "meals" or rows.is_empty(): return
	summary_bar = HBoxContainer.new()
	summary_bar.add_theme_constant_override("separation", 10)
	root_box.add_child(summary_bar)
	var summary = _label(str(rows[0].get("title", "本次餐单")), 18)
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary_bar.add_child(summary)
	for entry in rows[0].get("buttons", []): summary_bar.add_child(_command_button(entry))

func _populate() -> void:
	for child in collection.get_children(): collection.remove_child(child); child.queue_free()
	choice_buttons.clear()
	var visible: Array[int] = []
	for index in rows.size():
		if _matches(rows[index]): visible.append(index)
	if not visible.has(selected):
		selected = -1 if visible.is_empty() else visible[0]
		var selected_key = str(context.get("service_selected_key", ""))
		for index in visible:
			if _row_key(index) == selected_key:
				selected = index
				break
	_store_service_state()
	for index in visible:
		var row: Dictionary = rows[index]
		var button = _button(str(row.get("card_title", row.get("title", ""))), func(): select_row(index))
		button.custom_minimum_size = Vector2(0, 72 if _columns() == 1 else 110 if compact else 148)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.clip_text = true
		button.expand_icon = true
		button.icon = DungeonStyle.texture(_icon(row))
		button.add_theme_constant_override("icon_max_width", 38 if compact else 62)
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER if _columns() == 1 else VERTICAL_ALIGNMENT_TOP
		button.tooltip_text = DungeonCatalog.clean(str(row.get("description", "")))
		button.set_meta("row_index", index)
		button.set_meta("row_id", row.get("token_id", row.get("id", index)))
		if index == selected: button.add_theme_stylebox_override("normal", DungeonStyle.box(Color("fff4c5"), Color("b49951"), 2))
		collection.add_child(button)
		choice_buttons.append(button)
	if choice_buttons.is_empty(): collection.add_child(_label("暂无符合条件的项目", 18, MUTED))
	_show_detail()

func _icon(row: Dictionary) -> String:
	if row.has("icon"): return str(row.icon)
	if row.has("loot_id"): return "loot:" + str(row.loot_id)
	if row.has("token_id"): return "material:" + str(row.token_id)
	return {"work": "icon_maincitybulid_work", "extra_challenges": "icon_maincitybulid_Extra challenges", "history": "menu_adventure", "npcs": "信物", "npc": "信物"}.get(page_id, "")

func select_row(index: int) -> void:
	if index < 0 or index >= rows.size() or not _matches(rows[index]): return
	selected = index
	_store_service_state()
	_populate()
	detail_scroll.scroll_vertical = 0

func _show_detail() -> void:
	for child in details.get_children(): details.remove_child(child); child.queue_free()
	action_buttons.clear()
	if rows.is_empty() or selected < 0 or selected >= rows.size():
		details.add_child(_label("暂无记录" if rows.is_empty() else "暂无符合条件的项目", 22))
		return
	var row: Dictionary = rows[selected]
	_build_detail_header(row)
	_build_metrics(row)
	if page_id == "partners" and not str(row.get("model", "")).is_empty():
		var preview = preload("res://scripts/presentation/model_preview.gd").new()
		details.add_child(preview)
		preview.custom_minimum_size = Vector2(0, 160 if compact else 280)
		preview.show_model(str(row.model))
	if not str(row.get("source_description", "")).strip_edges().is_empty():
		var description = preload("res://scripts/presentation/source_rich_text.gd").new()
		description.name = "SourceDescription"
		description.add_theme_font_size_override("normal_font_size", 16 if compact else 20)
		description.add_theme_color_override("default_color", INK)
		description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		description.set_source(str(row.source_description).strip_edges())
		details.add_child(description)
	elif not str(row.get("description", "")).strip_edges().is_empty():
		details.add_child(_label(str(row.description).strip_edges(), 16 if compact else 20))
	if row.has("progress") and row.has("required"):
		var bar = ProgressBar.new()
		bar.max_value = maxf(1.0, float(row.required))
		bar.value = float(row.progress)
		bar.custom_minimum_size.y = 24
		details.add_child(bar)
	_build_row_actions(row)

func _build_metrics(row: Dictionary) -> void:
	var metrics: Array = row.get("metrics", [])
	if metrics.is_empty(): return
	var values = GridContainer.new()
	values.columns = mini(3, metrics.size())
	values.add_theme_constant_override("h_separation", 12 if compact else 24)
	values.add_theme_constant_override("v_separation", 10)
	details.add_child(values)
	for metric in metrics:
		var column = VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 4)
		values.add_child(column)
		column.add_child(_label(str(metric[0]), 14 if compact else 16, MUTED))
		column.add_child(_label(str(metric[1]), 20 if compact else 26))

func _build_detail_header(row: Dictionary) -> void:
	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	details.add_child(header)
	var icon = DungeonStyle.picture(_icon(row), Vector2(56, 56) if compact else Vector2(96, 96))
	if icon.texture: header.add_child(icon)
	else: icon.free()
	var name_label = _label(str(row.get("title", "")), 22 if compact else 26)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_label)
	if page_id == "archive" and context.get("systems") != null:
		var found = int(row.get("loot_id", 0)) in context.systems.profile.data.discovered_loot
		details.add_child(_label("已发现" if found else "尚未发现", 16, MUTED))

func _build_row_actions(row: Dictionary) -> void:
	var actions = HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 8)
	actions.add_theme_constant_override("v_separation", 8)
	details.add_child(actions)
	for entry in row.get("buttons", []):
		var button = _command_button(entry)
		actions.add_child(button)
		action_buttons.append(button)

func _command_button(entry: Dictionary) -> Button:
	var button = _button(str(entry.get("text", "")), func():
		command.emit(str(entry.get("action", "")), entry.get("args", entry.get("id", 0)), entry.get("extra", 0)), bool(entry.get("disabled", false)))
	button.set_meta("command", entry.duplicate(true))
	button.tooltip_text = str(entry.get("reason", ""))
	return button

func _adapt() -> void:
	if not _built: return
	var next_compact = size.y < 600 or size.x < 1000
	if next_compact != compact: _build()
	elif is_instance_valid(collection): collection.columns = _columns()
	ROLE_NAVIGATION.configure_header_back_button(heading.get_child(0), size, "返回" if context.has("back_action") else "关闭")
	var margin = get_node("PageMargin")
	var header_margin = ROLE_NAVIGATION.header_margin(size)
	margin.add_theme_constant_override("margin_left", int(header_margin.x))
	margin.add_theme_constant_override("margin_top", int(header_margin.y))
