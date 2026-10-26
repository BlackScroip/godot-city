extends Control

signal command(kind: String, id: Variant, extra: Variant)
signal closed
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
var row_buttons: Array[Button] = []
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
	var back = _button("", "退出按钮", func(): closed.emit())
	back.tooltip_text = "返回主城"
	back.custom_minimum_size = Vector2(64, 48)
	header.add_child(back)
	var title = _picture("冒险准备", Vector2(230, 60))
	header.add_child(title)
	var help = _button("", "须知", func():
		reason.text = "通关前一难度后解锁下一难度；混沌首通奖励按角色领取。")
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
	var token_title = _label("角色装备信物", 21)
	token_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary.add_child(token_title)
	var prep: Dictionary = context.preparation
	var tokens = _button("已装备信物 %d" % int(prep.token_count) if prep.tokens_unlocked else "未解锁信物功能", "", func(): command.emit("page:tokens", 0, 0))
	tokens.disabled = not prep.tokens_unlocked
	tokens.tooltip_text = str(prep.tokens_reason)
	tokens.size_flags_vertical = SIZE_EXPAND_FILL
	summary.add_child(tokens)
	summary.add_child(HSeparator.new())
	var tasks = _button("悬赏委托" if prep.extra_challenge_unlocked else "未建造营地任务栏", "", func(): command.emit("page:tasks" if prep.extra_challenge_unlocked else "page:buildings", 5, 0))
	tasks.tooltip_text = str(prep.extra_challenge_reason)
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
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(caption)
	var art = DungeonStyle.picture(icon, Vector2(64, 64))
	art.size_flags_vertical = SIZE_EXPAND_FILL
	stack.add_child(art)
	var rank_label = _label(level, 17)
	rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(rank_label)

func _select(level: int) -> void:
	selected = level
	var status = systems.difficulty_status(level)
	if status.can_start: command.emit("difficulty", level, 0)
	else: _refresh()

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

func _adapt() -> void:
	var compact = size.y < 600
	header.position = Vector2(18, 12)
	header.size = Vector2(size.x - 36, 46 if compact else 66)
	var top = 68 if compact else 98
	var margin = 18 if compact else 34
	var gap = 24 if compact else 54
	var left_width = size.x * 0.34
	left.position = Vector2(margin, top)
	left.size = Vector2(left_width, size.y - top - margin)
	var paper_style = left.get_theme_stylebox("panel").duplicate()
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]: paper_style.set_content_margin(side, 12 if compact else 26)
	left.add_theme_stylebox_override("panel", paper_style)
	left.get_child(0).add_theme_constant_override("separation", 6 if compact else 16)
	equipment.custom_minimum_size.y = 122 if compact else 225
	for key in equipment.get_children():
		var item = key.get_child(0)
		item.offset_left = 8 if compact else 14
		item.offset_top = 8 if compact else 14
		item.offset_right = -8 if compact else -14
		item.offset_bottom = -8 if compact else -14
		item.get_child(0).add_theme_font_size_override("font_size", 18 if compact else 22)
		item.get_child(1).custom_minimum_size = Vector2(40, 40) if compact else Vector2(64, 64)
		item.get_child(2).add_theme_font_size_override("font_size", 14 if compact else 17)
	for key in left.get_child(0).get_children():
		if key is Button: key.add_theme_font_size_override("font_size", 17 if compact else 22)
	right.position = Vector2(margin + left_width + gap, top)
	right.size = Vector2(size.x - margin * 2 - left_width - gap, size.y - top - margin)
	header.get_child(1).custom_minimum_size = Vector2(150, 42) if compact else Vector2(230, 60)
	for counter in header.get_children():
		if counter is HBoxContainer: counter.custom_minimum_size.x = 72 if compact else 112
	reward_bar.custom_minimum_size.y = 32 if compact else 62
	reward_bar.get_parent().add_theme_stylebox_override("panel", _paper("底框_木元素", 10 if compact else 18))
	for child in reward_bar.get_children():
		if child is Label: child.add_theme_font_size_override("font_size", 16 if compact else 20)
		if child is VBoxContainer:
			child.get_child(0).custom_minimum_size = Vector2(24, 24) if compact else Vector2(42, 42)
			child.get_child(1).add_theme_font_size_override("font_size", 16 if compact else 20)
	reason.add_theme_font_size_override("font_size", 16 if compact else 18)
	right.add_theme_constant_override("separation", 6 if compact else 16)
	choices.add_theme_constant_override("separation", 10 if compact else 18)
	for key in row_buttons:
		key.custom_minimum_size.y = 82 if compact else 116
		var line = key.get_child(0)
		line.get_child(0).custom_minimum_size.x = 66 if compact else 108
		line.get_child(0).add_theme_font_size_override("font_size", 20 if compact else 27)
		line.get_child(2).add_theme_font_size_override("font_size", 15 if compact else 20)
	start.custom_minimum_size = Vector2(160, 38) if compact else Vector2(240, 52)
	left.set_deferred("size", Vector2(left_width, size.y - top - margin))
	_reveal_selected.call_deferred()
