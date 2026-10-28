extends "res://scripts/presentation/talent_selection.gd"

const ALTAR_PATH := "res://assets/ui/altar/"

var help_button: Button
var finish_button: Button
var help_dialog: AcceptDialog
static var _tag_data: Dictionary = {}
static var _loot_tags: Dictionary = {}

func configure(page: DungeonMenuPage, rows: Array) -> void:
	super.configure(page, rows)
	heading.autowrap_mode = TextServer.AUTOWRAP_OFF
	# Collection choices share the source talent card, with their own action bar.
	for child in toolbar.get_children():
		if child == character_button: continue
		toolbar.remove_child(child)
		child.queue_free()
	refresh_button = null
	for row in rows:
		if row.get("presentation_role", "") != "refresh": continue
		for entry in row.get("buttons", []):
			var finish := str(entry.get("action", "")) == "finish_sacrifice"
			var button := _tool_button(str(entry.get("text", "刷新")), "退出按钮" if finish else "Button_Refresh", str(entry.get("tooltip", entry.get("text", "刷新候选"))))
			button.icon = Palette.texture("退出按钮" if finish else "Button_Refresh")
			button.disabled = bool(entry.get("disabled", false))
			button.pressed.connect(func(): command.emit(str(entry.action), entry.get("id", ""), entry.get("extra", "")))
			toolbar.add_child(button)
			if finish: finish_button = button
			else: refresh_button = button
	character_button.icon = Palette.texture("角色详情按钮")
	help_button = _tool_button("", "须知", "须知")
	help_button.icon = Palette.texture("须知")
	help_button.pressed.connect(_show_help)
	add_child(help_button)
	_adapt.call_deferred()

func _build_card(row: Dictionary) -> void:
	super._build_card(row)
	var part: Dictionary = parts.back()
	part.tag.hide()
	part.level_description.hide()
	part.panel.tooltip_text = str(row.get("spirit_skill", {}).get("transition", ""))
	var tags := HBoxContainer.new()
	tags.alignment = BoxContainer.ALIGNMENT_CENTER
	tags.mouse_filter = Control.MOUSE_FILTER_PASS
	part.stack.add_child(tags)
	part.stack.move_child(tags, part.tag.get_index())
	var tag_ids: Variant = row.get("effect_tags", _tags_for_loot(int(row.get("loot_id", 0))))
	if tag_ids is String: tag_ids = DungeonCatalog.ids(tag_ids)
	for id in tag_ids:
		var data: Dictionary = _tags().get(str(int(id)), {})
		if data.is_empty(): continue
		var badge := PanelContainer.new()
		badge.mouse_filter = Control.MOUSE_FILTER_PASS
		badge.tooltip_text = DungeonLocale.text(str(data.name))
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.12549, 0.12549, 0.12549, 0.51)
		style.set_corner_radius_all(64)
		style.set_content_margin_all(5)
		badge.add_theme_stylebox_override("panel", style)
		tags.add_child(badge)
		badge.add_child(DungeonStyle.picture(str(data.get("resource", "")), Vector2(38, 38)))
	var description := RichSource.new()
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	description.add_theme_color_override("default_color", Palette.color("curse_desc_color" if Palette.is_curse(row.get("loot_type", "")) else "effect"))
	description.add_theme_color_override("font_outline_color", Palette.outline("Text_EffectDescription"))
	description.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	description.add_theme_constant_override("outline_size", 4)
	description.add_theme_font_size_override("normal_font_size", 28)
	description.set_source(str(row.get("source_description", row.get("description", ""))))
	var text_stack: VBoxContainer = part.description.get_parent()
	text_stack.remove_child(part.description)
	part.description.queue_free()
	text_stack.add_child(description)
	text_stack.move_child(description, 0)
	part.description = description
	var footer: CenterContainer = part.footer
	part.choose.text = str(row.get("buttons", [{}])[0].get("text", "选择")) if not row.get("buttons", []).is_empty() else "选择"
	part.choose.visible = false
	part["footer"] = footer
	part["tags"] = tags
	if row.has("hp_cost"):
		var health := HBoxContainer.new()
		health.alignment = BoxContainer.ALIGNMENT_CENTER
		health.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		health.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var health_icon := DungeonStyle.picture(str(Palette.data().resources["生命值降低"]), Vector2(28, 28))
		health.add_child(health_icon)
		var price := _label("-%d" % int(row.hp_cost), 24, Color("c91630"), true)
		price.autowrap_mode = TextServer.AUTOWRAP_OFF
		health.add_child(price)
		var health_slot := MarginContainer.new()
		health_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		health_slot.add_theme_constant_override("margin_top", 2)
		health_slot.add_theme_constant_override("margin_bottom", 6)
		health_slot.add_child(health)
		part.stack.add_child(health_slot)
		part.stack.move_child(health_slot, part.title.get_index())
		part["health"] = health
	if row.has("lock_command") and bool(row.get("lock_visible", true)):
		var entry: Dictionary = row.lock_command
		var lock := _tool_button("", "锁", "解锁候选物" if bool(row.get("locked", false)) else "锁定候选物，重选时保留")
		lock.name = "SacrificeLock_%d" % (parts.size() - 1)
		lock.icon = Palette.texture("lock_1" if bool(row.get("locked", false)) else "unlock_1")
		lock.toggle_mode = true
		lock.button_pressed = bool(row.get("locked", false))
		lock.pressed.connect(func(): command.emit(str(entry.action), entry.get("id", 0), entry.get("extra", 0)))
		add_child(lock)
		part["lock"] = lock
	if bool(row.get("show_collection_badge", false)):
		var book := _tool_button("", "Button_tujian", "查看图鉴")
		book.icon = Palette.texture("Button_tujian")
		book.add_theme_color_override("icon_normal_color", Color(1.0, 0.82795, 0.262745))
		book.add_theme_color_override("icon_hover_color", Color(1.0, 0.82795, 0.262745))
		book.pressed.connect(func(): command.emit("page:archive", int(row.get("loot_id", 0)), 0))
		add_child(book)
		part["book"] = book
	parts[parts.size() - 1] = part

func _select(index: int) -> void:
	super._select(index)
	for i in parts.size(): parts[i].choose.visible = i == index

func _adapt() -> void:
	super._adapt()
	if not is_inside_tree() or not is_instance_valid(host) or size.y < 1: return
	var factor := clampf(size.y / 1080.0, 0.3, 1.5)
	for part in parts:
		part.stack.add_theme_constant_override("separation", maxi(3, int(6 * factor)))
		part.tags.custom_minimum_size.y = maxf(18, 48 * factor)
		part.tags.add_theme_constant_override("separation", maxi(2, int(4 * factor)))
		for badge in part.tags.get_children():
			badge.get_child(0).custom_minimum_size = Vector2.ONE * maxf(18, 38 * factor)
			var style: StyleBoxFlat = badge.get_theme_stylebox("panel").duplicate()
			style.set_content_margin_all(maxf(2, 5 * factor))
			badge.add_theme_stylebox_override("panel", style)
		part.description.add_theme_font_size_override("normal_font_size", maxi(14, int(28 * factor)))
		part.description.set_source(part.description.source_text)
		part.scroll.custom_minimum_size.y = 40
		part.footer.custom_minimum_size.y = maxf(26, 84 * factor)
		part.choose.custom_minimum_size = Vector2(0, maxf(26, 60 * factor))
		if part.has("health"):
			part.health.get_child(0).custom_minimum_size = Vector2.ONE * maxf(16, 28 * factor)
			part.health.get_child(1).add_theme_font_size_override("font_size", maxi(13, int(24 * factor)))
		for key in ["lock", "book"]:
			if not part.has(key): continue
			var button: Button = part[key]
			button.size = Vector2.ONE * maxf(26, 56 * factor)
			button.add_theme_constant_override("icon_max_width", int(button.size.x * (0.625 if key == "book" else 0.85)))
	if is_instance_valid(help_button):
		help_button.position = Vector2(28 * factor, size.y - maxf(36, 66 * factor))
		help_button.size = Vector2.ONE * maxf(30, 56 * factor)
		help_button.add_theme_constant_override("icon_max_width", int(help_button.size.x))
	_update_separators.call_deferred()

func _fit_toolbar() -> void:
	super._fit_toolbar()
	if is_instance_valid(heading):
		heading.size = Vector2(maxf(0, toolbar.position.x - heading.position.x - 16), back_button.size.y)

func _fit_cards() -> void:
	super._fit_cards()
	if not is_instance_valid(cards) or size.y >= 600: return
	if not parts.any(func(part): return part.has("health")): return
	cards.position.y = size.y * 0.15
	cards.size.y = size.y * 0.80

func _update_separators() -> void:
	super._update_separators()
	var factor := clampf(size.y / 1080.0, 0.3, 1.5)
	for part in parts:
		if part.has("book"):
			var icon_rect: Rect2 = part.icon_frame.get_global_rect()
			part.book.position = Vector2(icon_rect.end.x - global_position.x - part.book.size.x * 0.5, icon_rect.position.y - global_position.y - part.book.size.y * 0.3)
		if part.has("lock"): part.lock.position = part.panel.global_position - global_position + Vector2(10, 30) * factor

func _show_help() -> void:
	if is_instance_valid(help_dialog):
		help_dialog.popup_centered()
		return
	help_dialog = AcceptDialog.new()
	var guide: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ALTAR_PATH + "guide.json"))
	help_dialog.title = DungeonLocale.text(str(guide.get("title", "须知")))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(minf(840, size.x * 0.8), minf(440, size.y * 0.65))
	help_dialog.add_child(scroll)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(columns)
	for item in guide.get("parts", []):
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		columns.add_child(column)
		var title := _label(DungeonLocale.text(str(item.heading)), 20, DungeonStyle.GOLD, true)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(title)
		column.add_child(DungeonStyle.picture(str(item.resource), Vector2(0, 100 if size.y < 600 else 150)))
		var body := _label(DungeonLocale.text(str(item.body)), 15 if size.y < 600 else 18, Color.WHITE)
		column.add_child(body)
	add_child(help_dialog)
	help_dialog.popup_centered()

static func _tags() -> Dictionary:
	if _tag_data.is_empty():
		var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(ALTAR_PATH + "loot_effect_tags.json"))
		if value is Dictionary: _tag_data = value
	return _tag_data

static func _tags_for_loot(id: int) -> Array:
	if _loot_tags.is_empty() and FileAccess.file_exists(ALTAR_PATH + "loot_tags.json"):
		var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(ALTAR_PATH + "loot_tags.json"))
		if value is Dictionary: _loot_tags = value
	return _loot_tags.get(str(id), {}).get("effect_tags", [])

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.1490196, 0.0980392, 0.0745098, 0.9019608))
