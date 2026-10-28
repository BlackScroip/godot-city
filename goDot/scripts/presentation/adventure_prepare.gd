extends Control

signal command(kind: String, id: Variant, extra: Variant)
signal closed
const ROLE_NAVIGATION = preload("res://scripts/presentation/role_navigation.gd")
var context: Dictionary
var rows: Array
var assets: Dictionary
var systems
var catalog
var selected := 0
var left: PanelContainer
var right: VBoxContainer
var reward_bar: HBoxContainer
var choices: VBoxContainer
var list: ScrollContainer
var start: Button
var reason: Label
var header: HBoxContainer
var chaos: HBoxContainer
var equipment: HBoxContainer
var token_title: Label
var row_buttons: Array[Button] = []
var token_slots: HBoxContainer
var help_overlay: Control
var help_page := 0
var selection_tween: Tween
var scroll_velocity := 0.0
var scroll_position := 0.0
var pointer_down := false
var dragging := false
var pointer_start := Vector2.ZERO
var pointer_index := -1
var motion_time := 0
const INK = Color("535966")
const PAPER = Color("eee9cc")

func configure(_host, data: Array, details: Dictionary) -> void:
	context = details
	rows = data
	systems = context.systems
	catalog = context.catalog
	selected = int(context.get("difficulty", 0))
	assets = JSON.parse_string(FileAccess.get_file_as_string("res://assets/ui/prepare/resource_map.json"))
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL
	var backdrop = _picture("传送门背景")
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(backdrop)
	var shade = ColorRect.new()
	shade.color = Color(0.03, 0.08, 0.07, 0.24)
	shade.mouse_filter = MOUSE_FILTER_IGNORE
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(shade)
	header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	add_child(header)
	var back = ROLE_NAVIGATION.create_header_back_button(size, "返回主城")
	back.pressed.connect(func(): closed.emit())
	header.add_child(back)
	var title = _picture("冒险准备", Vector2(230, 60))
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(title)
	DungeonStyle.localize_artwork_title(title, "冒险准备", 36)
	var help = _button("", "须知", _show_help)
	help.tooltip_text = "冒险须知"
	help.custom_minimum_size = Vector2(40, 40)
	header.add_child(help)
	var filler = Control.new()
	filler.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(filler)
	for resource in context.get("resources", []):
		var counter = HBoxContainer.new()
		counter.custom_minimum_size.x = 112
		counter.add_child(DungeonStyle.picture(str(resource[0]), Vector2(30, 30)))
		counter.add_child(DungeonStyle.label(str(resource[1]), 20))
		header.add_child(counter)
	left = PanelContainer.new()
	left.add_theme_stylebox_override("panel", _paper("石头元素底框", 26))
	add_child(left)
	var summary = VBoxContainer.new()
	summary.add_theme_constant_override("separation", 16)
	left.add_child(summary)
	equipment = HBoxContainer.new()
	equipment.add_theme_constant_override("separation", 16)
	equipment.custom_minimum_size.y = 225
	summary.add_child(equipment)
	var character = catalog.find("CharData", int(systems.profile.data.selected_character))
	var weapon = catalog.find("WeaponData", int(systems.profile.data.selected_weapon))
	_equipment(equipment, character, "page:characters", str(character.get("square_icon_name", "")), "Lv.%d" % systems.rank(systems.profile.data.character_levels, int(systems.profile.data.selected_character)))
	_equipment(equipment, weapon, "page:weapons", str(weapon.get("square_icon_name", "interaction_weapon")), "")
	token_title = _label("角色装备信物", 21)
	token_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	token_title.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY if DungeonLocale.current_locale() == "th" else TextServer.AUTOWRAP_WORD_SMART
	token_title.clip_text = true
	summary.add_child(token_title)
	var prep: Dictionary = context.preparation
	token_slots = HBoxContainer.new()
	token_slots.add_theme_constant_override("separation", 8)
	summary.add_child(token_slots)
	var equipped: Array = systems.relationship_tokens.equipped()
	for index in maxi(4, systems.token_slots()):
		var token_id = int(equipped[index]) if index < equipped.size() else 0
		var state: Dictionary = systems.token_status(token_id) if token_id > 0 else {}
		var slot = _button("", str(state.get("icon", "icon_addnum" if index < systems.token_slots() else "锁")), func(): command.emit("page:tokens", token_id, 0))
		slot.size_flags_horizontal = SIZE_EXPAND_FILL
		slot.tooltip_text = str(state.get("name", "添加信物" if index < systems.token_slots() else "扩展信物槽"))
		for style_state in ["normal", "hover", "pressed"]:
			slot.add_theme_stylebox_override(style_state, DungeonStyle.box(Color("495957"), Color("c4bc96"), 2))
		token_slots.add_child(slot)
	summary.add_child(HSeparator.new())
	var tasks = _button("悬赏委托" if prep.extra_challenge_unlocked else "未建造营地任务栏", "", func(): command.emit("page:extra_challenges" if prep.extra_challenge_unlocked else "page:buildings", 0 if prep.extra_challenge_unlocked else 5, 0))
	tasks.tooltip_text = str(prep.extra_challenge_reason)
	tasks.custom_minimum_size.y = 44
	tasks.size_flags_vertical = SIZE_EXPAND_FILL
	summary.add_child(tasks)
	right = VBoxContainer.new()
	right.add_theme_constant_override("separation", 16)
	add_child(right)
	var rewards = PanelContainer.new()
	rewards.add_theme_stylebox_override("panel", _paper("底框_木元素", 18))
	right.add_child(rewards)
	reward_bar = HBoxContainer.new()
	reward_bar.custom_minimum_size.y = 62
	reward_bar.add_theme_constant_override("separation", 24)
	rewards.add_child(reward_bar)
	list = ScrollContainer.new()
	list.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list.size_flags_vertical = SIZE_EXPAND_FILL
	right.add_child(list)
	choices = VBoxContainer.new()
	choices.size_flags_horizontal = SIZE_EXPAND_FILL
	choices.add_theme_constant_override("separation", 18)
	list.add_child(choices)
	for row in rows:
		var status: Dictionary = row.get("difficulty_status", {})
		if status.is_empty(): continue
		var level = int(status.difficulty)
		var key = _button("", "", func(): _select(level))
		key.mouse_filter = MOUSE_FILTER_PASS
		key.custom_minimum_size.y = 116
		key.size_flags_horizontal = SIZE_EXPAND_FILL
		key.tooltip_text = str(status.reason)
		choices.add_child(key)
		var line = HBoxContainer.new()
		line.mouse_filter = MOUSE_FILTER_IGNORE
		line.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		line.offset_left = 18
		line.offset_right = -18
		line.add_theme_constant_override("separation", 16)
		key.add_child(line)
		var name_label = DungeonStyle.label("混沌" if level == 10 else "等级%d" % level, 27)
		name_label.custom_minimum_size.x = 108
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.add_child(name_label)
		line.add_child(VSeparator.new())
		var text = DungeonStyle.label(_tier_description(level), 20)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.max_lines_visible = 3
		text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		text.size_flags_horizontal = SIZE_EXPAND_FILL
		text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		text.mouse_filter = MOUSE_FILTER_IGNORE
		line.add_child(text)
		if not status.unlocked: line.add_child(_picture("锁头", Vector2(42, 52)))
		row_buttons.append(key)
	chaos = HBoxContainer.new()
	chaos.add_theme_constant_override("separation", 14)
	right.add_child(chaos)
	reason = DungeonStyle.label("", 18)
	reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(reason)
	start = _button("进入迷宫", "冒险图标", func(): command.emit("primary", 0, 0))
	start.custom_minimum_size = Vector2(240, 52)
	start.size_flags_horizontal = SIZE_SHRINK_END
	for state in ["normal", "hover", "pressed"]: start.add_theme_stylebox_override(state, _paper("主城建造离开按钮", 12))
	right.add_child(start)
	resized.connect(_adapt)
	_refresh()
	_adapt.call_deferred()
	_reveal_selected.call_deferred()

func _reveal_selected() -> void:
	if not is_inside_tree(): return
	await get_tree().process_frame
	if is_inside_tree() and selected >= 0 and selected < row_buttons.size(): list.ensure_control_visible(row_buttons[selected])

func _tier_description(level: int) -> String:
	var texts: Array[String] = []
	for row in catalog.rows("RogueLevelDifficultyInfluencerData"):
		if bool(row.get("IsDisable", false)) or not bool(row.get("EnableShowUI", false)) or str(row.get("DifficultyType", "")) == "Reward": continue
		if str(row.get("DifficultyCategory", "")) != ("Chaos" if level == 10 else "Normal") or int(row.get("Tier", -1)) != (1 if level == 10 else level): continue
		var text = DungeonCatalog.clean(row.get("Description", ""))
		if not text.is_empty() and not text.begins_with("RogueLevelDifficulty_"): texts.append(text)
	return "\n".join(texts) if not texts.is_empty() else "迷宫的力量相对平静。"

func _picture(name: String, minimum := Vector2.ZERO) -> TextureRect:
	return DungeonStyle.picture(str(assets.get(name, name)), minimum)

func _paper(name: String, margin: float) -> StyleBoxTexture:
	var style = StyleBoxTexture.new()
	style.texture = DungeonStyle.texture(str(assets.get(name, "")))
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_texture_margin(side, margin)
		style.set_content_margin(side, margin)
	return style

func _label(text: String, font_size: int) -> Label:
	var label = DungeonStyle.label(text, font_size)
	label.add_theme_color_override("font_color", INK)
	label.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	return label

func _button(text: String, icon: String, callback: Callable) -> Button:
	var button = Button.new()
	button.text = text
	button.clip_text = true
	button.resized.connect(func(): DungeonStyle.fit_button_text(button, 17 if size.y < 600 else 22))
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_disabled_color", INK.lightened(0.12))
	for state in ["normal", "hover", "pressed", "disabled", "focus"]: button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	if not icon.is_empty():
		button.icon = DungeonStyle.texture(str(assets.get(icon, icon)))
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 54)
	button.pressed.connect(callback)
	return button

func _equipment(parent: Control, source: Dictionary, action: String, icon: String, level: String) -> void:
	var key = _button("", "", func(): command.emit(action, 0, 0))
	key.size_flags_horizontal = SIZE_EXPAND_FILL
	for state in ["normal", "hover", "pressed"]: key.add_theme_stylebox_override(state, _paper("内容纸", 14))
	parent.add_child(key)
	var stack = VBoxContainer.new()
	stack.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	stack.offset_left = 14
	stack.offset_top = 14
	stack.offset_right = -14
	stack.offset_bottom = -14
	stack.mouse_filter = MOUSE_FILTER_IGNORE
	key.add_child(stack)
	var caption = _label(DungeonCatalog.row_name(source), 22)
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.clip_text = true
	caption.max_lines_visible = 2
	caption.size_flags_vertical = SIZE_EXPAND_FILL
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.resized.connect(func(): _fit_equipment_caption(caption))
	stack.add_child(caption)
	var art = DungeonStyle.picture(icon, Vector2(64, 64))
	stack.add_child(art)
	var rank_label = _label(level, 17)
	rank_label.visible = not level.is_empty()
	rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(rank_label)
	key.tooltip_text = DungeonCatalog.row_name(source)

func _fit_equipment_caption(caption: Label) -> void:
	if caption.size.x <= 1 or caption.size.y <= 1: return
	var font := caption.get_theme_font("font")
	var text := DungeonLocale.text(caption.text)
	var font_size := 18 if size.y < 600 else 22
	while font_size > 10:
		var measured := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, caption.size.x, font_size, -1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE)
		if measured.x <= caption.size.x + 1 and measured.y <= caption.size.y + 1: break
		font_size -= 1
	if caption.get_theme_font_size("font_size") != font_size:
		caption.add_theme_font_size_override("font_size", font_size)

func _select(level: int) -> void:
	if dragging: return
	selected = level
	var status = systems.difficulty_status(level)
	if status.can_start: command.emit("difficulty", level, {"prepare_in_place": true})
	_refresh()
	if selection_tween: selection_tween.kill()
	for key in row_buttons: key.modulate = Color.WHITE
	reward_bar.modulate.a = 0.35
	row_buttons[level].modulate = Color(1.35, 1.35, 1.12)
	selection_tween = create_tween().set_parallel(true)
	selection_tween.tween_property(row_buttons[level], "modulate", Color.WHITE, 0.3)
	selection_tween.tween_property(reward_bar, "modulate:a", 1.0, 0.24)

func _refresh() -> void:
	var status: Dictionary = systems.difficulty_status(selected)
	for child in reward_bar.get_children():
		reward_bar.remove_child(child)
		child.queue_free()
	for reward in status.rewards:
		if int(reward.value) == 0: continue
		var group = VBoxContainer.new()
		group.size_flags_horizontal = SIZE_EXPAND_FILL
		group.tooltip_text = str(reward.description)
		reward_bar.add_child(group)
		var icon = {"DropGoldFactor": "sprite_abilityitemicon_11003", "DropFreeCoinFactor": "sprite_materialicon_90002", "DropMineralMatFactor": "sprite_materialicon_103", "DropMagicPointFactor": "sprite_materialicon_102", "Star5ItemExtraWeightAddPercent": "星星大", "CollectingMaterialsAppearChance": "sprite_materialicon_107"}.get(str(reward.attribute), "")
		var picture = _picture(icon, Vector2(42, 42))
		picture.size_flags_horizontal = SIZE_SHRINK_CENTER
		group.add_child(picture)
		var value = float(reward.value) / (1000.0 if reward.attribute == "DropMineralMatFactor" else 10.0)
		var amount = str(int(value)) if value == int(value) else String.num(value, 1)
		var label = _label("+%s%s" % [amount, "" if reward.attribute == "DropMineralMatFactor" else "%"], 20)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		group.add_child(label)
	if reward_bar.get_child_count() == 0: reward_bar.add_child(_label("无额外掉落加成", 20))
	for index in row_buttons.size():
		var color = [Color("7a8591"), Color("86c941"), Color("448bdc"), Color("ab62c7"), Color("d3a737")][mini(index, 4)]
		for state in ["normal", "hover", "pressed", "focus"]:
			var style = DungeonStyle.box(Color(color, 0.65 if index == selected else 0.35), Color("e5edc7") if index == selected else Color(color, 0.7), 3 if index == selected else 1)
			style.set_corner_radius_all(6)
			row_buttons[index].add_theme_stylebox_override(state, style)
	for child in chaos.get_children():
		chaos.remove_child(child)
		child.queue_free()
	chaos.visible = selected == 10
	if selected == 10:
		chaos.add_child(DungeonStyle.label("混沌层数", 20))
		var layer = SpinBox.new()
		layer.min_value = 1
		layer.max_value = mini(int(status.chaos_max), int(status.chaos_cleared) + 1)
		layer.value = int(status.chaos_level)
		layer.editable = status.can_start
		layer.custom_minimum_size.x = 110
		layer.value_changed.connect(func(value): command.emit("chaos_level", int(value), 0))
		chaos.add_child(layer)
		var claim = _button("领取首通奖励", "Button_ClaimReward", func(): command.emit("claim_chaos_rewards", 0, 0))
		claim.disabled = status.unclaimed_chaos_rewards.is_empty() or context.get("in_run", false)
		claim.add_theme_color_override("font_color", Color.WHITE)
		chaos.add_child(claim)
	start.disabled = not status.can_start
	reason.text = str(status.reason)
	if selected == 10: reason.text += "  已通关 %d 层" % int(status.chaos_cleared)
	_fit_rewards()

func _fit_rewards() -> void:
	var compact = size.y < 600
	for child in reward_bar.get_children():
		if child is Label: child.add_theme_font_size_override("font_size", 16 if compact else 20)
		if child is VBoxContainer:
			child.get_child(0).custom_minimum_size = Vector2(24, 24) if compact else Vector2(42, 42)
			child.get_child(1).add_theme_font_size_override("font_size", 16 if compact else 20)

func _adapt() -> void:
	var compact = size.y < 600
	var header_margin = ROLE_NAVIGATION.header_margin(size)
	ROLE_NAVIGATION.configure_header_back_button(header.get_child(0), size, "返回主城")
	header.position = header_margin
	header.size = Vector2(size.x - header_margin.x * 2, ROLE_NAVIGATION.header_button_size(size).y)
	var top = maxf(68 if compact else 98, header.position.y + header.size.y + 12)
	var margin = 18 if compact else 34
	var gap = 24 if compact else 54
	var left_width = size.x * 0.34
	left.position = Vector2(margin, top)
	left.size = Vector2(left_width, size.y - top - margin)
	var paper_style = left.get_theme_stylebox("panel").duplicate()
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]: paper_style.set_content_margin(side, 12 if compact else 26)
	left.add_theme_stylebox_override("panel", paper_style)
	left.get_child(0).add_theme_constant_override("separation", 6 if compact else 16)
	token_title.add_theme_font_size_override("font_size", 18 if compact else 21)
	token_title.custom_minimum_size.y = 30 if compact else 64
	equipment.custom_minimum_size.y = 122 if compact else 225
	token_slots.custom_minimum_size.y = 48 if compact else 82
	for key in equipment.get_children():
		var item = key.get_child(0)
		item.offset_left = 8 if compact else 14
		item.offset_top = 8 if compact else 14
		item.offset_right = -8 if compact else -14
		item.offset_bottom = -8 if compact else -14
		item.get_child(1).custom_minimum_size = Vector2(40, 40) if compact else Vector2(64, 64)
		item.get_child(2).add_theme_font_size_override("font_size", 14 if compact else 17)
		_fit_equipment_caption(item.get_child(0))
	for key in left.get_child(0).get_children():
		if key is Button: DungeonStyle.fit_button_text(key, 17 if compact else 22)
	right.position = Vector2(margin + left_width + gap, top)
	right.size = Vector2(size.x - margin * 2 - left_width - gap, size.y - top - margin)
	var title_width := (150 if compact else 230) if DungeonLocale.current_locale() == "zh_CN" else (300 if compact else 400)
	header.get_child(1).custom_minimum_size = Vector2(title_width, 42 if compact else 60)
	for counter in header.get_children():
		if counter is HBoxContainer: counter.custom_minimum_size.x = 72 if compact else 112
	reward_bar.custom_minimum_size.y = 32 if compact else 62
	reward_bar.get_parent().add_theme_stylebox_override("panel", _paper("底框_木元素", 10 if compact else 18))
	_fit_rewards()
	reason.add_theme_font_size_override("font_size", 16 if compact else 18)
	right.add_theme_constant_override("separation", 6 if compact else 16)
	choices.add_theme_constant_override("separation", 10 if compact else 18)
	for key in row_buttons:
		key.custom_minimum_size.y = 82 if compact else 116
		var line = key.get_child(0)
		line.get_child(0).custom_minimum_size.x = 66 if compact else 108
		line.get_child(0).add_theme_font_size_override("font_size", 20 if compact else 27)
		line.get_child(2).add_theme_font_size_override("font_size", 15 if compact else 20)
	var start_width := (160 if compact else 240) if DungeonLocale.current_locale().begins_with("zh") else (280 if compact else 340)
	start.custom_minimum_size = Vector2(start_width, 38 if compact else 52)
	DungeonStyle.fit_button_text(start, 17 if compact else 22)
	left.set_deferred("size", Vector2(left_width, size.y - top - margin))
	_reveal_selected.call_deferred()
	if is_instance_valid(help_overlay): _layout_help()

func _process(delta: float) -> void:
	if not is_instance_valid(list) or pointer_down or absf(scroll_velocity) < 1.0: return
	var before = scroll_position
	_set_scroll(scroll_position + scroll_velocity * delta)
	scroll_velocity *= exp(-8.0 * delta)
	if is_equal_approx(before, scroll_position): scroll_velocity = 0.0

func _set_scroll(value: float) -> void:
	var bar = list.get_v_scroll_bar()
	scroll_position = clampf(value, 0.0, maxf(0.0, bar.max_value - bar.page))
	list.scroll_vertical = roundi(scroll_position)

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree(): return
	if is_instance_valid(help_overlay):
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause_game"):
			_close_help()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and list.get_global_rect().has_point(event.position):
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if event.pressed:
				scroll_position = list.scroll_vertical
				scroll_velocity += (-1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0) * 700.0 * event.factor
			get_viewport().set_input_as_handled()
			return
	if event is InputEventPanGesture and list.get_global_rect().has_point(event.position):
		scroll_velocity = 0
		_set_scroll(list.scroll_vertical + event.delta.y * 28.0)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		var touch = event is InputEventScreenTouch
		if event.pressed:
			if pointer_down or not list.get_global_rect().has_point(event.position): return
			# Leave the scrollbar available for native thumb dragging.
			if list.get_v_scroll_bar().get_global_rect().has_point(event.position): return
			pointer_down = true
			pointer_index = event.index if touch else -1
			pointer_start = event.position
			dragging = false
			scroll_velocity = 0
			scroll_position = list.scroll_vertical
			motion_time = Time.get_ticks_msec()
		elif pointer_down and pointer_index == (event.index if touch else -1):
			pointer_down = false
			if Time.get_ticks_msec() - motion_time > 100: scroll_velocity = 0
			if touch and not dragging:
				for index in row_buttons.size():
					if list.get_global_rect().has_point(event.position) and row_buttons[index].get_global_rect().has_point(event.position):
						_select(index)
			if dragging or touch:
				for key in row_buttons: key.set_pressed_no_signal(false)
				get_viewport().set_input_as_handled()
			dragging = false
		if touch: get_viewport().set_input_as_handled()
	elif pointer_down and (event is InputEventMouseMotion and pointer_index == -1 or event is InputEventScreenDrag and event.index == pointer_index):
		if event.position.distance_to(pointer_start) > 8: dragging = true
		if dragging:
			var now = Time.get_ticks_msec()
			var elapsed = maxf(float(now - motion_time) / 1000.0, 0.008)
			_set_scroll(scroll_position - event.relative.y)
			scroll_velocity = clampf(-event.relative.y / elapsed, -2200, 2200)
			motion_time = now
			get_viewport().set_input_as_handled()

func _close_help() -> void:
	if is_instance_valid(help_overlay):
		remove_child(help_overlay)
		help_overlay.queue_free()
		help_overlay = null
	header.get_child(2).grab_focus()

func _show_help() -> void:
	if is_instance_valid(help_overlay): return
	scroll_velocity = 0
	pointer_down = false
	dragging = false
	help_overlay = Control.new()
	help_overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(help_overlay)
	var shade = ColorRect.new()
	shade.color = Color(0, 0, 0, 0.72)
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	help_overlay.add_child(shade)
	shade.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT: _close_help())
	var panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", DungeonStyle.box(Color("444e5b"), Color("d0b675"), 2))
	help_overlay.add_child(panel)
	var stack = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 12)
	panel.add_child(stack)
	var top = HBoxContainer.new()
	stack.add_child(top)
	var title = DungeonStyle.label("迷宫难度", 26)
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	top.add_child(title)
	var close = _button("×", "", _close_help)
	close.add_theme_color_override("font_color", Color.WHITE)
	close.tooltip_text = "关闭"
	close.custom_minimum_size = Vector2(48, 40)
	top.add_child(close)
	stack.add_child(HSeparator.new())
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stack.add_child(scroll)
	var content = VBoxContainer.new()
	content.size_flags_horizontal = SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10 if size.y < 600 else 18)
	scroll.add_child(content)
	content.add_child(DungeonStyle.label("解锁难度" if help_page == 0 else "奖励与冒险准备", 23))
	if help_page == 0:
		for level in 2:
			var preview = PanelContainer.new()
			preview.add_theme_stylebox_override("panel", DungeonStyle.box(Color("667480") if level == 0 else Color("649338"), Color("d6dfb8"), 1))
			content.add_child(preview)
			var preview_row = HBoxContainer.new()
			preview_row.add_theme_constant_override("separation", 16)
			preview.add_child(preview_row)
			preview_row.add_child(DungeonStyle.label("等级%d" % level, 20))
			var caption = DungeonStyle.label("迷宫的力量相对平静。" if level == 0 else "通关等级0后解锁", 17)
			caption.size_flags_horizontal = SIZE_EXPAND_FILL
			caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			preview_row.add_child(caption)
			if level == 1: preview_row.add_child(_picture("锁头", Vector2(24, 28)))
	else:
		var rewards = HBoxContainer.new()
		rewards.alignment = BoxContainer.ALIGNMENT_CENTER
		rewards.add_theme_constant_override("separation", 32)
		content.add_child(rewards)
		for icon in ["sprite_abilityitemicon_11003", "sprite_materialicon_90002", "sprite_materialicon_108"]:
			rewards.add_child(_picture(icon, Vector2(44, 44)))
	var description = DungeonStyle.label("迷宫拥有多个难度等级。通关当前难度后，即可解锁下一难度。\n\n难度提升后，领主和怪物会获得新的强化。点击等级可查看强化内容；未解锁的等级可以预览，但无法进入。" if help_page == 0 else "选择难度时，上方会显示该难度的额外掉落加成。\n\n出发前可以更换角色、武器与信物。点击信物槽可查看、装备或卸下信物。\n\n混沌层数逐层解锁，首通奖励按角色领取。", 17 if size.y < 600 else 20)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(description)
	content.move_child(description, 1)
	var pages = HBoxContainer.new()
	pages.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_child(pages)
	for index in 2:
		var dot = _button("●" if index == help_page else "○", "", func():
			help_page = index
			_close_help()
			_show_help())
		dot.custom_minimum_size = Vector2(48, 40)
		dot.add_theme_color_override("font_color", Color("f5d875"))
		dot.tooltip_text = "第%d页" % (index + 1)
		pages.add_child(dot)
	close.focus_next = close.get_path_to(pages.get_child(0))
	close.focus_previous = close.get_path_to(pages.get_child(1))
	pages.get_child(0).focus_previous = pages.get_child(0).get_path_to(close)
	pages.get_child(1).focus_next = pages.get_child(1).get_path_to(close)
	_layout_help()
	close.grab_focus()
	help_overlay.modulate.a = 0
	create_tween().tween_property(help_overlay, "modulate:a", 1.0, 0.16)

func _layout_help() -> void:
	var panel = help_overlay.get_child(1)
	var width = size.x * (0.76 if size.y < 600 else 0.6)
	panel.position = Vector2((size.x - width) * 0.5, 24)
	panel.size = Vector2(width, size.y - 48)
