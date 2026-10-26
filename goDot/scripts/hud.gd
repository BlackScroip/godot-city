class_name DungeonHud
extends CanvasLayer

signal action(kind: String, id: Variant, extra: Variant)
signal skill(slot: int, pressed: bool)
const SKILL_CLUSTER_SIZE := Vector2(400, 344)
const SKILL_CLUSTER_MARGIN := Vector2(24, 24)
const SKILL_POSITIONS := [Vector2(208, 152), Vector2(80, 212), Vector2(84, 52), Vector2(252, 12), Vector2(8, 148)]
const SKILL_SIZES := [168, 112, 112, 112, 64]
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
var counter_icons: Array[TextureRect] = []
var counter_buttons: Array[Button] = []
var camp_button: Button
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
	for id in [101, 501, 90002]:
		var panel = Button.new()
		var style = DungeonStyle.box(Color(0.08, 0.07, 0.05, 0.85), DungeonStyle.GOLD, 2)
		style.set_corner_radius_all(20)
		style.content_margin_top = 0
		style.content_margin_bottom = 0
		for state in ["normal", "hover", "pressed", "disabled"]: panel.add_theme_stylebox_override(state, style)
		panel.custom_minimum_size = Vector2(212, 40)
		panel.set_meta("resource_id", id)
		panel.pressed.connect(func(): action.emit("page:resource", int(panel.get_meta("resource_id")), 0))
		counter_buttons.append(panel)
		counters.add_child(panel)
		var line = HBoxContainer.new()
		line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		line.offset_left = 8
		line.offset_right = -8
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(line)
		var icon = DungeonStyle.picture("material:" + str(id), Vector2(36, 36))
		line.add_child(icon)
		counter_icons.append(icon)
		var value = label("0", 20)
		value.mouse_filter = Control.MOUSE_FILTER_IGNORE
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.add_child(value)
		counter_values.append(value)
	camp_button = button("营地", "camp")
	camp_button.icon = DungeonStyle.texture("menu_portal")
	camp_button.expand_icon = true
	camp_button.add_theme_constant_override("icon_max_width", 28)
	camp_button.tooltip_text = "营地设施与资源"
	root.add_child(camp_button)
	pickup_panel = preload("res://scripts/presentation/pickup_card.gd").new()
	root.add_child(pickup_panel)
	pickup_icon = pickup_panel.icon
	pickup_name = pickup_panel.name_label
	pickup_description = pickup_panel.description_label
	navigation = HBoxContainer.new()
	navigation.add_theme_constant_override("separation", 4)
	root.add_child(navigation)
	for entry in [["开始冒险", "primary", "menu_adventure"], ["云存档", "save", "menu_cloud"], ["商城", "page:mall", "menu_store"], ["角色", "page:characters", "menu_character"], ["设置", "settings", "menu_settings"]]:
		var key = Button.new() if entry[1] == "primary" else button("", entry[1])
		if entry[1] == "primary":
			adventure_button = key
			key.pressed.connect(func(): action.emit("page:difficulty", 0, 0))
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
	var icons = ["skill_attack", "skill_dodge", "skill_sword_whirl", "skill_sword_slash"]
	var names = ["攻击", "闪避", "战技", "爆发"]
	for slot in range(4):
		var key = DungeonTouchButton.new()
		key.position = SKILL_POSITIONS[slot]
		key.size = Vector2.ONE * SKILL_SIZES[slot]
		key.custom_minimum_size = key.size
		key.tooltip_text = names[slot]
		key.art = DungeonStyle.texture(icons[slot])
		key.ring = DungeonStyle.texture("skill_ring" if slot == 0 else "skill_circle")
		key.button_down.connect(func(): skill.emit(slot, true))
		key.button_up.connect(func(): skill.emit(slot, false))
		skill_cluster.add_child(key)
		skill_buttons.append(key)
		skill_by_slot[slot] = key
	attack_mode_button = DungeonTouchButton.new()
	attack_mode_button.position = SKILL_POSITIONS[4]
	attack_mode_button.size = Vector2.ONE * SKILL_SIZES[4]
	attack_mode_button.custom_minimum_size = attack_mode_button.size
	attack_mode_button.ring = DungeonStyle.texture("skill_circle_small")
	attack_mode_button.art = DungeonStyle.texture("skill_swap")
	attack_mode_button.button_down.connect(func():
		var modes = ["normal", "heavy", "off"]
		action.emit("auto_attack_mode", modes[(modes.find(attack_mode) + 1) % modes.size()], 0))
	skill_cluster.add_child(attack_mode_button)
	attack_mode_label = label("", 20)
	attack_mode_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	attack_mode_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	attack_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	attack_mode_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	attack_mode_label.offset_top = 64
	attack_mode_label.offset_bottom = 26
	attack_mode_label.add_theme_font_size_override("font_size", 18)
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
	primary.add_theme_constant_override("h_separation", 12)
	primary.add_theme_color_override("font_color", Color.WHITE)
	primary.add_theme_font_size_override("font_size", 22)
	for state in ["normal", "hover", "pressed"]:
		var prompt_frame = StyleBoxTexture.new()
		prompt_frame.texture = DungeonStyle.texture("对话按钮_底")
		prompt_frame.texture_margin_left = 78
		prompt_frame.texture_margin_right = 198
		prompt_frame.texture_margin_top = 12
		prompt_frame.texture_margin_bottom = 12
		prompt_frame.set_content_margin_all(6)
		prompt_frame.content_margin_left = 20
		prompt_frame.content_margin_right = 24
		prompt_frame.modulate_color = Color.WHITE if state == "normal" else Color(1.2, 1.15, 0.9)
		primary.add_theme_stylebox_override(state, prompt_frame)
	root.add_child(primary)
	joystick.excluded_controls.assign([navigation, primary, skill_cluster])
	joystick.excluded_controls.append(pickup_panel)
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
			if key.name == "menu_settings":
				key.get_child(0).texture = DungeonStyle.texture("menu_pause" if active else "menu_settings")
				key.get_child(1).text = "暂停" if active else "设置"
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
	result.step = 0.0
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
	message_label.visible = layout not in ["outcome", "dialogue", "unclaimed"]
	page.display(title, rows, layout, context)
	page.show()
	shade.visible = layout not in ["route", "dialogue"]
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
	for control in [navigation, title_label, status_label, resources_label, camp_button]:
		if is_instance_valid(control): control.visible = value
	if counters: counters.visible = value
	if pickup_panel and not value: pickup_panel.hide()

func _layout() -> void:
	if not is_instance_valid(page): return
	var screen = root.size
	var ui_scale = minf(1.0, minf(screen.x / 1280.0, screen.y / 720.0))
	var s = screen / maxf(0.1, ui_scale)
	counters.position = Vector2(28, 45)
	camp_button.position = Vector2(28, 198)
	camp_button.size = Vector2(212, 46)
	title_label.position = Vector2(235, 25)
	var navigation_width = 272.0 if adventure_mode else 456.0
	navigation.position = Vector2(s.x - navigation_width - 28, 28)
	navigation.size = Vector2(navigation_width, 100)
	message_label.position = Vector2(s.x * 0.25, 140)
	message_label.size = Vector2(s.x * 0.5, 64)
	skill_cluster.position = s - SKILL_CLUSTER_SIZE - SKILL_CLUSTER_MARGIN
	skill_cluster.size = SKILL_CLUSTER_SIZE
	for key in skill_buttons: key.release(true)
	attack_mode_button.release(true)
	attack_mode_button.hit_padding = maxf(8.0, (48.0 / ui_scale - attack_mode_button.size.x) * 0.5)
	vitals.position = Vector2(s.x * 0.5 - 122, s.y - 145)
	vitals.size = Vector2(244, 80)
	joystick.position = Vector2(0, s.y * 0.42)
	joystick.size = Vector2(s.x * 0.4, s.y * 0.58)
	joystick.home = Vector2(128, joystick.size.y - 140)
	joystick.queue_redraw()
	primary.position = Vector2(s.x - 680, s.y - 308)
	primary.size = Vector2(260, 48)
	pickup_panel.layout(s)
	for control in [navigation, message_label, skill_cluster, vitals, joystick, primary, pickup_panel, counters, title_label, camp_button]:
		control.scale = Vector2.ONE * ui_scale
		control.position *= ui_scale
	var full_page = page._layout in ["inventory", "altar", "talent", "support", "route", "outcome", "character", "weapon", "settings", "tree", "awakening", "buildings", "prepare", "shop", "commission", "guild", "dialogue"]
	full_page = full_page or (modal_open and page.page_context.get("camp", false))
	full_page = full_page or page._layout == "unclaimed"
	full_page = full_page or page._layout == "room_shop"
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
	camp_button.visible = camp and not modal_open
	armor.max_value = maxf(1, combat.max_health)
	armor.value = combat.armor
	armor.visible = combat.armor > 0
	if combat.fighter.is_empty(): return
	var skills: Array = combat.fighter.skills
	for slot in skill_by_slot:
		var key = skill_by_slot[slot]
		var before = [key.cooldown, key.stock, key.charging, key.charge_fraction, key.unavailable, key.recharge_remaining, key.resource_fraction, key.resource_color]
		var capacity: float = combat.skill_capacity(slot)
		var cost: float = combat.skill_cost(slot)
		key.cooldown = float(combat.cooldowns[slot])
		key.cooldown_total = maxf(0.01, float(skills[slot].cooldown))
		key.unavailable = combat.health <= 0 or float(combat.energy[slot]) + 0.001 < cost
		key.stock = int((float(combat.energy[slot]) + 0.001) / cost) if cost > 0 and capacity > cost else -1
		key.recharge_remaining = combat.dodge_recharge_remaining() if slot == 1 else 0.0
		key.recharge_total = combat.dodge_recharge_duration() if slot == 1 else 1.0
		key.charging = slot == 0 and combat.charging
		key.charge_fraction = clampf(combat.charge_elapsed / 1.5, 0, 1) if key.charging else 0.0
		key.resource_fraction = combat.skill_charge_fraction(slot, true) if slot == 3 else -1.0
		key.resource_color = DungeonTouchButton.skill_resource_color(int(skills[slot].get("element", 0)))
		key.readiness_suspended = readiness_suspended or modal_open
		key.low_effects = low_effects
		key.ready_full = DungeonTouchButton.has_full_skill_resource(slot, float(combat.energy[slot]), capacity, cost, key.cooldown, combat.health > 0)
		if before != [key.cooldown, key.stock, key.charging, key.charge_fraction, key.unavailable, key.recharge_remaining, key.resource_fraction, key.resource_color]: key.queue_redraw()
	charge.max_value = maxf(1, combat.skill_capacity(3))
	charge.value = float(combat.energy[3])
	var fraction: float = combat.special_resource_fraction()
	reference_vitals.bind_resource(str(combat.fighter.get("jp", "")), fraction)
	for i in charge_segments.size():
		charge_segments[i].texture = DungeonStyle.texture("hud_charge_segment_full" if fraction >= (i + 1) / 5.0 else "hud_charge_segment")
		charge_segments[i].modulate = Color.WHITE

func update_counters(systems: RefCounted, difficulty: int) -> void:
	var ids = [101, 102] if adventure_mode else [101, 501, 90002]
	for index in counter_values.size():
		counter_buttons[index].visible = index < ids.size()
		if index >= ids.size(): continue
		var id = int(ids[index])
		if int(counter_buttons[index].get_meta("resource_id")) != id:
			counter_buttons[index].set_meta("resource_id", id)
			counter_icons[index].texture = DungeonStyle.texture("material:" + str(id))
		counter_buttons[index].disabled = adventure_mode
		counter_buttons[index].tooltip_text = DungeonCatalog.clean(systems.material_name(id))
		counter_values[index].text = "%d   +%d" % [systems.material(id), int(systems.profile.data.run.materials.get(str(id), 0))] if adventure_mode else "%s  %d" % [DungeonCatalog.clean(systems.material_name(id)), systems.material(id)]
	title_label.text = "难度 %d" % difficulty

func show_pickup(entry: Dictionary, systems: RefCounted, modal: bool) -> void:
	pickup_panel.bind(entry, systems, modal)
	if modal or entry.is_empty(): return
	primary.visible = true
	primary.text = "拾取"
	primary.icon = DungeonStyle.texture("sprite_conversation_get")
	primary.add_theme_color_override("font_color", Color("ffdb68"))
	if entry.has("altar"):
		primary.text = "精灵祭坛"
