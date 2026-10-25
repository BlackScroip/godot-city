class_name DungeonHud
extends CanvasLayer

signal action(kind: String, id: Variant, extra: Variant)
signal skill(slot: int, pressed: bool)
var root: Control
var joystick: DungeonJoystick
var title_label: Label
var status_label: Label
var resources_label: Label
var health: TextureProgressBar
var armor: TextureProgressBar
var hp_label: Label
var charge: TextureProgressBar
var charge_segments: Array[TextureRect] = []
var message_label: Label
var page: DungeonMenuPage
var page_title: Label
var page_rows: VBoxContainer
var primary: Button
var skill_buttons: Array[Button] = []
var skill_by_slot: Dictionary = {}
var attack_mode_button: DungeonTouchButton
var attack_mode_label: Label
var attack_mode := "normal"
var modal_open := false
var _toast_time := 0.0
var skill_cluster: Control
var vitals: Control
var navigation: HBoxContainer
var shade: ColorRect
var counters: VBoxContainer
var counter_values: Array[Label] = []
var pickup_panel: PanelContainer
var pickup_name: Label
var pickup_description: Label
var pickup_icon: TextureRect
var reference_vitals: Control
var objective_guide: Control
var readiness_suspended := false
var low_effects := false
var adventure_mode := false
var adventure_button: Button
var adventure_caption: Label
var battle_readout: Control
var adventure_icon: TextureRect

func _ready() -> void:
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = DungeonStyle.theme()
	add_child(root)
	objective_guide = preload("res://scripts/presentation/objective_guide.gd").new()
	root.add_child(objective_guide)
	title_label = label("冒险者营地", 24)
	title_label.position = Vector2(28, 24)
	root.add_child(title_label)
	status_label = label("", 16)
	status_label.position = Vector2(28, 58)
	root.add_child(status_label)
	resources_label = label("", 17)
	resources_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	resources_label.offset_left = -600
	resources_label.offset_right = -28
	resources_label.offset_top = 114
	resources_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(resources_label)
	counters = VBoxContainer.new()
	counters.position = Vector2(28, 45)
	counters.add_theme_constant_override("separation", 8)
	root.add_child(counters)
	for id in [101, 102]:
		var panel = PanelContainer.new()
		var style = DungeonStyle.box(Color(0.08, 0.07, 0.05, 0.85), DungeonStyle.GOLD, 2)
		style.set_corner_radius_all(20)
		style.content_margin_top = 0
		style.content_margin_bottom = 0
		panel.add_theme_stylebox_override("panel", style)
		panel.custom_minimum_size = Vector2(186, 36)
		counters.add_child(panel)
		var line = HBoxContainer.new()
		panel.add_child(line)
		line.add_child(DungeonStyle.picture("material:" + str(id), Vector2(36, 36)))
		var value = label("0", 20)
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(value)
		counter_values.append(value)
	pickup_panel = PanelContainer.new()
	pickup_panel.add_theme_stylebox_override("panel", DungeonStyle.box(Color(0.02, 0.04, 0.08, 0.88), DungeonStyle.GOLD, 2))
	root.add_child(pickup_panel)
	var pickup_stack = VBoxContainer.new()
	pickup_panel.add_child(pickup_stack)
	pickup_icon = DungeonStyle.picture("", Vector2(72, 72))
	pickup_stack.add_child(pickup_icon)
	pickup_name = label("", 22)
	pickup_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pickup_name.modulate = DungeonStyle.GOLD
	pickup_stack.add_child(pickup_name)
	pickup_stack.add_child(HSeparator.new())
	pickup_description = label("", 18)
	pickup_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pickup_description.max_lines_visible = 5
	pickup_stack.add_child(pickup_description)
	pickup_panel.hide()
	navigation = HBoxContainer.new()
	navigation.add_theme_constant_override("separation", 4)
	root.add_child(navigation)
	for entry in [["开始冒险", "primary", "menu_adventure"], ["云存档", "save", "menu_cloud"], ["商城", "page:mall", "menu_store"], ["角色", "page:characters", "menu_character"], ["设置", "settings", "menu_settings"]]:
		var key = Button.new() if entry[1] == "primary" else button("", entry[1])
		if entry[1] == "primary":
			adventure_button = key
			key.pressed.connect(func(): action.emit("page:difficulty" if adventure_mode else "primary", 0, 0))
		key.name = entry[2]
		key.custom_minimum_size = Vector2(88, 100)
		key.tooltip_text = entry[0]
		if entry[1] == "save": key.tooltip_text = "离线版本：保存进度到本机"
		for state in ["normal", "hover", "pressed", "disabled"]:
			key.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		key.add_theme_stylebox_override("focus", DungeonStyle.box(Color.TRANSPARENT, Color(1, 1, 1, 0.6)))
		navigation.add_child(key)
		var icon = DungeonStyle.picture(entry[2], Vector2.ZERO)
		icon.position = Vector2(12, 0)
		icon.size = Vector2(64, 64)
		if entry[2] == "menu_adventure":
			adventure_icon = icon
			var white_icon = ShaderMaterial.new()
			white_icon.shader = preload("res://scripts/presentation/white_menu_icon.gdshader")
			icon.material = white_icon
		key.add_child(icon)
		var caption = label(entry[0], 22)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.position = Vector2(0, 66)
		caption.size = Vector2(88, 32)
		caption.add_theme_color_override("font_color", Color.WHITE)
		caption.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
		caption.add_theme_constant_override("outline_size", 4)
		key.add_child(caption)
		if entry[1] == "primary": adventure_caption = caption
		key.button_down.connect(func(): icon.modulate = Color(0.7, 0.8, 0.85))
		key.button_up.connect(func(): icon.modulate = Color.WHITE)
		if entry[1] in ["save", "page:mall"]:
			var badge = DungeonStyle.picture("menu_red_dot", Vector2.ZERO)
			badge.position = Vector2(63, 0)
			badge.size = Vector2(18, 18)
			key.add_child(badge)
			key.pressed.connect(badge.hide)
	message_label = label("", 22)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(message_label)
	joystick = DungeonJoystick.new()
	root.add_child(joystick)
	skill_cluster = Control.new()
	skill_cluster.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(skill_cluster)
	# Combat slots stay stable; the former heavy button now selects automation.
	var positions = [Vector2(222, 164), Vector2(106, 220), Vector2(128, 38), Vector2(300, 40), Vector2(42, 172)]
	var sizes = [156, 116, 112, 104, 72]
	var icons = ["skill_attack", "skill_dodge", "skill_sword_whirl", "skill_sword_slash", "res://assets/art_generated/heavy-v1.png"]
	var names = ["攻击", "闪避", "战技", "爆发", "重击 / 蓄力"]
	for slot in range(4):
		var key = DungeonTouchButton.new()
		key.position = positions[slot]
		key.size = Vector2.ONE * sizes[slot]
		key.custom_minimum_size = key.size
		key.tooltip_text = names[slot]
		key.art = DungeonStyle.texture(icons[slot])
		key.ring = DungeonStyle.texture("skill_circle")
		key.button_down.connect(func(): skill.emit(slot, true))
		key.button_up.connect(func(): skill.emit(slot, false))
		skill_cluster.add_child(key)
		skill_buttons.append(key)
		skill_by_slot[slot] = key
	attack_mode_button = DungeonTouchButton.new()
	attack_mode_button.position = positions[4]
	attack_mode_button.size = Vector2.ONE * sizes[4]
	attack_mode_button.custom_minimum_size = attack_mode_button.size
	attack_mode_button.ring = DungeonStyle.texture("skill_circle")
	attack_mode_button.button_down.connect(func():
		var modes = ["normal", "heavy", "off"]
		action.emit("auto_attack_mode", modes[(modes.find(attack_mode) + 1) % modes.size()], 0))
	skill_cluster.add_child(attack_mode_button)
	attack_mode_label = label("", 20)
	attack_mode_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	attack_mode_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	attack_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	attack_mode_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	attack_mode_button.add_child(attack_mode_label)
	set_attack_mode(attack_mode)
	vitals = Control.new()
	vitals.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vitals)
	reference_vitals = preload("res://scripts/presentation/reference_vitals.gd").new()
	reference_vitals.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vitals.add_child(reference_vitals)
	var frame = NinePatchRect.new()
	frame.texture = DungeonStyle.texture("hud_hp_frame")
	frame.position = Vector2(0, 50)
	frame.size = Vector2(244, 24)
	frame.patch_margin_left = 24
	frame.patch_margin_right = 24
	frame.patch_margin_top = 10
	frame.patch_margin_bottom = 10
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vitals.add_child(frame)
	frame.hide()
	health = _bar("hud_hp_fill", Vector2(14, 56), Vector2(216, 12))
	health.hide()
	hp_label = label("", 18)
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_label.position = Vector2(0, 49)
	hp_label.size = Vector2(244, 26)
	vitals.add_child(hp_label)
	armor = _bar("hud_armor_fill", Vector2(8, 44), Vector2(228, 5))
	charge = _bar("hud_charge_line", Vector2(0, 30), Vector2(244, 8))
	charge.hide()
	for index in range(5):
		var segment = DungeonStyle.picture("hud_charge_segment", Vector2(36, 8))
		segment.position = Vector2(13 + index * 45, 17)
		segment.size = Vector2(36, 8)
		vitals.add_child(segment)
		charge_segments.append(segment)
		segment.hide()
	primary = button("", "interact")
	primary.icon = DungeonStyle.texture("interaction_weapon")
	primary.expand_icon = true
	primary.add_theme_constant_override("icon_max_width", 30)
	primary.add_theme_color_override("font_color", DungeonStyle.GOLD)
	primary.add_theme_stylebox_override("normal", DungeonStyle.box(Color(0.06, 0.11, 0.15, 0.7), DungeonStyle.GOLD))
	root.add_child(primary)
	joystick.excluded_controls.assign([navigation, primary, skill_cluster])
	battle_readout = preload("res://scripts/presentation/battle_readout.gd").new()
	root.add_child(battle_readout)
	battle_readout.hide()
	shade = ColorRect.new()
	shade.color = Color(0.01, 0.025, 0.035, 0.66)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(shade)
	page = DungeonMenuPage.new()
	root.add_child(page)
	page.command.connect(func(kind, id, extra): action.emit(kind, id, extra))
	page.closed.connect(func(): action.emit("close_page", 0, 0))
	page.back_requested.connect(func(): action.emit("camp", 0, 0))
	page_title = page.title_label
	page_rows = page.rows_host
	close_page()
	root.resized.connect(_layout)
	_layout.call_deferred()
	set_adventure_mode(adventure_mode)

func set_adventure_mode(active: bool) -> void:
	adventure_mode = active
	if is_instance_valid(adventure_button): adventure_button.tooltip_text = "难度" if active else "开始冒险"
	if is_instance_valid(adventure_caption): adventure_caption.text = "难度" if active else "开始冒险"
	if is_instance_valid(adventure_icon): adventure_icon.texture = DungeonStyle.texture("menu_difficulty" if active else "menu_adventure")
	if is_instance_valid(navigation):
		for key in navigation.get_children():
			key.visible = not active or key.name not in ["menu_cloud", "menu_store"]
		_layout()

func set_attack_mode(mode: String) -> void:
	attack_mode = mode if mode in ["normal", "heavy", "off"] else "normal"
	if not is_instance_valid(attack_mode_label): return
	attack_mode_label.text = {"normal": "普攻", "heavy": "重击", "off": "关闭"}[attack_mode]
	attack_mode_button.tooltip_text = "自动攻击：" + attack_mode_label.text
	attack_mode_label.modulate = Color("ffdc78") if attack_mode != "off" else Color("a7b2b8")

func update_intent(intent: RefCounted) -> void:
	for slot in skill_by_slot:
		var queued = int(intent.pending.get("slot", -1)) == slot or (slot == 0 and (int(intent.pending.get("slot", -1)) == 4 or (intent.attack_held and intent.attack_hold_elapsed >= intent.FEEL.attack_hold_threshold and not intent.hold_consumed)))
		if skill_by_slot[slot].queued != queued:
			skill_by_slot[slot].queued = queued
			skill_by_slot[slot].queue_redraw()

func _bar(art: String, point: Vector2, dimensions: Vector2) -> TextureProgressBar:
	var result = TextureProgressBar.new()
	result.texture_progress = DungeonStyle.texture(art)
	result.nine_patch_stretch = true
	result.position = point
	result.size = dimensions
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vitals.add_child(result)
	return result

func label(text: String, font_size := 19) -> Label:
	return DungeonStyle.label(text, font_size)

func button(text: String, kind: String, id: Variant = 0, extra: Variant = 0) -> Button:
	var result = Button.new()
	result.text = text
	result.pressed.connect(func(): action.emit(kind, id, extra))
	return result

func show_page(title: String, rows: Array, layout := "list", context: Dictionary = {}) -> void:
	message_label.visible = layout != "outcome"
	page.display(title, rows, layout, context)
	page.show()
	shade.visible = layout != "route"
	_set_navigation_visible(false)
	modal_open = true
	_layout()
	joystick._reset()
	joystick.hide()
	for key in skill_buttons: key.release()
	attack_mode_button.release()
	skill_cluster.hide()
	vitals.hide()
	primary.hide()

func close_page() -> void:
	if message_label: message_label.show()
	if page: page.hide()
	if shade: shade.hide()
	modal_open = false
	_set_navigation_visible(true)
	_layout()
	if joystick: joystick.show()
	if skill_cluster: skill_cluster.show()
	if vitals: vitals.show()
	if primary: primary.hide()

func _set_navigation_visible(value: bool) -> void:
	for control in [navigation, title_label, status_label, resources_label]:
		if is_instance_valid(control): control.visible = value
	if counters: counters.visible = value
	if pickup_panel and not value: pickup_panel.hide()

func _layout() -> void:
	if not is_instance_valid(page): return
	var screen = root.size
	var ui_scale = minf(1.0, minf(screen.x / 1280.0, screen.y / 720.0))
	var s = screen / maxf(0.1, ui_scale)
	counters.position = Vector2(28, 45)
	title_label.position = Vector2(235, 25)
	var navigation_width = 272.0 if adventure_mode else 456.0
	navigation.position = Vector2(s.x - navigation_width - 28, 28)
	navigation.size = Vector2(navigation_width, 100)
	message_label.position = Vector2(s.x * 0.25, 140)
	message_label.size = Vector2(s.x * 0.5, 64)
	skill_cluster.position = Vector2(s.x - 440, s.y - 340)
	skill_cluster.size = Vector2(420, 330)
	vitals.position = Vector2(s.x * 0.5 - 122, s.y - 145)
	vitals.size = Vector2(244, 80)
	joystick.position = Vector2(0, s.y * 0.42)
	joystick.size = Vector2(s.x * 0.4, s.y * 0.58)
	joystick.home = Vector2(128, joystick.size.y - 140)
	joystick.queue_redraw()
	primary.position = Vector2(s.x - 620, s.y - 308)
	primary.size = Vector2(200, 48)
	pickup_panel.position = Vector2(s.x - 490, maxf(145, s.y - 600))
	pickup_panel.size = Vector2(300, 230)
	for control in [navigation, message_label, skill_cluster, vitals, joystick, primary, pickup_panel, counters, title_label]:
		control.scale = Vector2.ONE * ui_scale
		control.position *= ui_scale
	var full_page = page._layout in ["inventory", "altar", "talent", "route", "outcome", "character", "weapon", "settings", "tree", "awakening", "buildings", "prepare", "shop"]
	var page_margin = Vector2.ZERO if OS.has_feature("mobile") or (modal_open and full_page) else Vector2(40, 40)
	page.position = page_margin
	page.size = screen - page_margin * 2
	page.scale = Vector2.ONE
	if modal_open and page._layout == "inventory":
		var factor = minf(1.0, minf(screen.x / 1280.0, screen.y / 720.0))
		page.scale = Vector2.ONE * factor
		page.size = screen / factor

func toast(text: String) -> void:
	message_label.text = text
	_toast_time = 4.0

func _process(delta: float) -> void:
	_toast_time = maxf(0, _toast_time - delta)
	if _toast_time <= 0: message_label.text = ""

func update_state(title: String, hp: float, max_hp: float, status: String, resources: String, primary_text: String) -> void:
	title_label.text = title
	health.max_value = maxf(1, max_hp)
	health.value = hp
	var fraction = hp / maxf(1, max_hp)
	if reference_vitals.hp_fraction != fraction:
		reference_vitals.hp_fraction = fraction
		reference_vitals.queue_redraw()
	hp_label.text = "%d/%d" % [hp, max_hp]
	status_label.text = status
	resources_label.text = resources
	primary.text = primary_text

func update_combat(combat: RefCounted, camp: bool) -> void:
	title_label.visible = not modal_open and not camp
	status_label.visible = false
	resources_label.visible = false
	counters.visible = not modal_open
	armor.max_value = maxf(1, combat.max_health)
	armor.value = combat.armor
	armor.visible = combat.armor > 0
	if combat.fighter.is_empty(): return
	var skills: Array = combat.fighter.skills
	for slot in skill_by_slot:
		var key = skill_by_slot[slot]
		var before = [key.cooldown, key.stock, key.charging, key.charge_fraction, key.unavailable, key.recharge_remaining]
		key.cooldown = float(combat.cooldowns[slot])
		key.cooldown_total = maxf(0.01, float(skills[slot].cooldown))
		key.unavailable = combat.health <= 0 or float(combat.energy[slot]) + 0.001 < float(skills[slot].sp)
		key.stock = int((float(combat.energy[slot]) + 0.001) / float(skills[slot].sp)) if float(skills[slot].sp) > 0 and combat.skill_capacity(slot) > float(skills[slot].sp) else -1
		key.recharge_remaining = combat.dodge_recharge_remaining() if slot == 1 else 0.0
		key.recharge_total = combat.dodge_recharge_duration() if slot == 1 else 1.0
		key.charging = slot == 0 and combat.charging
		key.charge_fraction = clampf(combat.charge_elapsed / 1.5, 0, 1) if key.charging else 0.0
		key.readiness_suspended = readiness_suspended or modal_open
		key.low_effects = low_effects
		key.ready_full = DungeonTouchButton.has_full_skill_resource(slot, float(combat.energy[slot]), float(skills[slot].maxSp), float(skills[slot].sp), key.cooldown, combat.health > 0)
		if before != [key.cooldown, key.stock, key.charging, key.charge_fraction, key.unavailable, key.recharge_remaining]: key.queue_redraw()
	charge.max_value = maxf(1, float(skills[3].maxSp))
	charge.value = float(combat.energy[3])
	var fraction = charge.value / charge.max_value
	if reference_vitals.charge_fraction != fraction:
		reference_vitals.charge_fraction = fraction
		reference_vitals.queue_redraw()
	for i in charge_segments.size():
		charge_segments[i].texture = DungeonStyle.texture("hud_charge_segment_full" if fraction >= (i + 1) / 5.0 else "hud_charge_segment")
		charge_segments[i].modulate = Color.WHITE

func update_counters(systems: RefCounted, difficulty: int) -> void:
	for index in 2:
		var id = 101 + index
		counter_values[index].text = "%d   +%d" % [systems.material(id), int(systems.profile.data.run.materials.get(str(id), 0))]
	title_label.text = "难度 %d" % difficulty

func show_pickup(entry: Dictionary, systems: RefCounted, modal: bool) -> void:
	pickup_panel.visible = not modal and not entry.is_empty()
	if not pickup_panel.visible: return
	primary.visible = true
	primary.text = "拾取"
	primary.icon = DungeonStyle.texture("interaction_quest")
	pickup_icon.texture = DungeonStyle.texture(("material:" if entry.material else "loot:") + str(entry.id))
	pickup_name.text = DungeonCatalog.clean(systems.material_name(entry.id) if entry.material else systems.loot_name(entry.id))
	pickup_description.text = "数量：%d" % entry.amount if entry.material else DungeonCatalog.clean(systems.loot_description(entry.id))
	if entry.has("altar"):
		primary.text = "精灵祭坛"
		pickup_name.text = "精灵祭坛"
		pickup_description.text = "选择一位同行的精灵"
