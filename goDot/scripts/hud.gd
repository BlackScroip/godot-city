class_name DungeonHud
extends CanvasLayer

signal action(kind: String, id: Variant, extra: Variant)
signal skill(slot: int, pressed: bool)
signal skill_canceled(slot: int)
const SKILL_CLUSTER_SIZE := Vector2(520, 392)
const SKILL_CLUSTER_MARGIN := Vector2(24, 24)
const INTERACTION_OFFSET := Vector2(-192, 56)
const SKILL_POSITIONS := [Vector2(272, 184), Vector2(118, 236), Vector2(172, 48), Vector2(384, 44), Vector2(28, 172)]
const SKILL_SIZES := [192, 120, 128, 112, 72]
const RESOURCE_IDS := [101, 102, 103, 12101, 90002, 108]
const NAVIGATION_ENTRIES := [
	["开始冒险", "quick_start", "menu_adventure"],
	["分享评价", "go_comment", "menu_comment"],
	["云存档", "cloud_save", "menu_cloud"],
	["餐品", "page:meal_buffs", "menu_meal_buffs"],
	["难度", "page:difficulty", "menu_difficulty"],
	["商城", "page:mall", "menu_store"],
	["角色", "page:characters", "menu_character"],
	["设置", "settings", "menu_settings"],
]
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
var region_notice: Control
var readiness_suspended := false
var low_effects := false
var adventure_mode := false
var _adventure_mode_applied := false
var adventure_button: Button
var adventure_caption: Label
var battle_readout: Control
var adventure_icon: TextureRect
var navigation_buttons: Dictionary = {}
var _navigation_badges: Dictionary = {}
var _navigation_state: Dictionary = {}
var _navigation_visibility: Dictionary = {}
var _seen_navigation_hints: Dictionary = {}

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
	for id in RESOURCE_IDS:
		var panel = preload("res://scripts/presentation/resource_counter.gd").new()
		panel.set_meta("resource_id", id)
		panel.pressed.connect(func(): action.emit("page:resource", int(panel.get_meta("resource_id")), 0))
		counter_buttons.append(panel)
		counters.add_child(panel)
		panel.resource_icon.texture = DungeonStyle.texture(("loot:" if id == 12101 else "material:") + str(id))
		counter_icons.append(panel.resource_icon)
		counter_values.append(panel.value_label)
	camp_button = button("营地", "camp")
	camp_button.icon = DungeonStyle.texture("menu_portal")
	camp_button.expand_icon = true
	camp_button.add_theme_constant_override("icon_max_width", 28)
	camp_button.tooltip_text = "营地设施与资源"
	root.add_child(camp_button)
	counters.minimum_size_changed.connect(func(): _layout_camp_button.call_deferred())
	pickup_panel = preload("res://scripts/presentation/pickup_card.gd").new()
	root.add_child(pickup_panel)
	pickup_icon = pickup_panel.icon
	pickup_name = pickup_panel.name_label
	pickup_description = pickup_panel.description_label
	navigation = HBoxContainer.new()
	navigation.add_theme_constant_override("separation", 25)
	root.add_child(navigation)
	for entry in NAVIGATION_ENTRIES:
		var key = button("", entry[1])
		key.name = entry[2]
		key.custom_minimum_size = Vector2(90, 112)
		key.tooltip_text = entry[0]
		for state in ["normal", "hover", "pressed", "disabled"]:
			key.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		key.add_theme_stylebox_override("focus", DungeonStyle.box(Color.TRANSPARENT, Color(1, 1, 1, 0.6)))
		navigation.add_child(key)
		navigation_buttons[entry[2]] = key
		var icon = DungeonStyle.picture(entry[2], Vector2.ZERO)
		icon.position = Vector2(5, 0)
		icon.size = Vector2(80, 80)
		if entry[2] == "menu_adventure":
			var white_icon = ShaderMaterial.new()
			white_icon.shader = preload("res://scripts/presentation/white_menu_icon.gdshader")
			icon.material = white_icon
		key.add_child(icon)
		var caption = label(entry[0], 20 if str(entry[0]).length() > 3 else 22)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.position = Vector2(0, 80)
		caption.size = Vector2(90, 32)
		caption.add_theme_color_override("font_color", Color.WHITE)
		caption.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
		caption.add_theme_constant_override("outline_size", 4)
		key.add_child(caption)
		key.button_down.connect(func(): icon.modulate = Color(0.7, 0.8, 0.85))
		key.button_up.connect(func(): icon.modulate = Color.WHITE)
		if entry[1] in ["quick_start", "go_comment", "cloud_save"]:
			var badge = DungeonStyle.picture("menu_red_dot", Vector2.ZERO)
			badge.position = Vector2(70, 0)
			badge.size = Vector2(18, 18)
			key.add_child(badge)
			_navigation_badges[entry[2]] = badge
	message_label = label("", 22)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(message_label)
	region_notice = preload("res://scripts/presentation/region_notice.gd").new()
	region_notice.z_index = 10
	root.add_child(region_notice)
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
		key.touch_canceled.connect(func(): skill_canceled.emit(slot))
		skill_cluster.add_child(key)
		skill_buttons.append(key)
		skill_by_slot[slot] = key
	attack_mode_button = DungeonTouchButton.new()
	attack_mode_button.position = SKILL_POSITIONS[4]
	attack_mode_button.size = Vector2.ONE * SKILL_SIZES[4]
	attack_mode_button.custom_minimum_size = attack_mode_button.size
	attack_mode_button.ring = DungeonStyle.texture("skill_circle_small")
	attack_mode_button.art = DungeonStyle.texture("skill_swap")
	attack_mode_button.pressed.connect(func():
		var modes = ["normal", "heavy", "off"]
		action.emit("auto_attack_mode", modes[(modes.find(attack_mode) + 1) % modes.size()], 0))
	skill_cluster.add_child(attack_mode_button)
	attack_mode_label = label("", 20)
	attack_mode_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	attack_mode_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	attack_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	attack_mode_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	attack_mode_label.offset_top = SKILL_SIZES[4]
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
	primary.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	primary.alignment = HORIZONTAL_ALIGNMENT_LEFT
	primary.add_theme_color_override("font_color", Color.WHITE)
	primary.add_theme_font_size_override("font_size", 22)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var prompt_frame = StyleBoxTexture.new()
		prompt_frame.texture = DungeonStyle.texture("interaction_frame")
		prompt_frame.content_margin_left = 28
		prompt_frame.content_margin_right = 24
		prompt_frame.content_margin_top = 8
		prompt_frame.content_margin_bottom = 8
		prompt_frame.modulate_color = Color(1.15, 1.12, 1.0) if state == "hover" else Color(0.9, 0.85, 0.7) if state == "pressed" else Color(1, 1, 1, 0.45) if state == "disabled" else Color.WHITE
		primary.add_theme_stylebox_override(state, prompt_frame)
	primary.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
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
	if _adventure_mode_applied and adventure_mode == active: return
	adventure_mode = active
	if not is_instance_valid(navigation): return
	_adventure_mode_applied = true
	_refresh_navigation()

func update_navigation(systems: RefCounted) -> void:
	var has_win: bool = systems.stat("wins") > 0
	for level in range(11):
		if systems.stat("difficulty:win:" + str(level)) > 0:
			has_win = true
			break
	var next := {
		"guide_ready": int(systems.profile.data.get("guide_index", 10)) >= 10,
		"has_win": has_win,
		"meal_buffs": not systems.purchased_meals().is_empty(),
		"dialogue": not systems.profile.data.get("dialogue_state", {}).is_empty(),
		"quick_read": systems.profile.data.stats.has("ui:read:Btn_QuickStart"),
		"comment_read": systems.profile.data.stats.has("ui:read:Btn_GoComment"),
		"cloud_read": systems.profile.data.stats.has("ui:read:Btn_CloudSave"),
	}
	if next == _navigation_state: return
	_navigation_state = next
	_refresh_navigation()

func _refresh_navigation() -> void:
	var ready := bool(_navigation_state.get("guide_ready", true))
	var available := not bool(_navigation_state.get("dialogue", false))
	var completed := available and ready and bool(_navigation_state.get("has_win", false)) and not adventure_mode
	var flags := {
		"menu_adventure": completed,
		"menu_comment": completed and not _navigation_state.get("comment_read", false),
		"menu_cloud": completed and not _navigation_state.get("cloud_read", false),
		"menu_meal_buffs": available and adventure_mode and bool(_navigation_state.get("meal_buffs", false)),
		"menu_difficulty": available and adventure_mode and ready,
		"menu_store": available and not adventure_mode and ready,
		"menu_character": available,
		"menu_settings": available,
	}
	for key in flags: navigation_buttons[key].visible = flags[key]
	for key in _navigation_badges:
		_navigation_badges[key].visible = not _navigation_state.get("quick_read", false) if key == "menu_adventure" else not _seen_navigation_hints.get(key, false)
	adventure_button = navigation_buttons["menu_difficulty" if adventure_mode else "menu_adventure"]
	adventure_icon = adventure_button.get_child(0)
	adventure_caption = adventure_button.get_child(1)
	if flags != _navigation_visibility:
		_navigation_visibility = flags
		_layout()

func dismiss_navigation_hint(key: String) -> void:
	_seen_navigation_hints[key] = true
	if _navigation_badges.has(key): _navigation_badges[key].hide()

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
	region_notice.clear()
	message_label.visible = layout not in ["outcome", "dialogue", "unclaimed"]
	page.display(title, rows, layout, context)
	page.show()
	shade.visible = layout not in ["route", "dialogue"]
	_set_navigation_visible(false)
	modal_open = true
	_layout()
	joystick._reset()
	joystick.hide()
	for key in skill_buttons: key.release(true)
	attack_mode_button.release(true)
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
	var previous_skill_transform = skill_cluster.get_global_transform_with_canvas()
	var screen = root.size
	var ui_scale = minf(1.0, minf(screen.x / 1280.0, screen.y / 720.0))
	var s = screen / maxf(0.1, ui_scale)
	counters.position = Vector2(28, 45)
	camp_button.position = Vector2(28, 198)
	camp_button.size = Vector2(212, 46)
	title_label.position = Vector2(235, 25)
	var visible_navigation = navigation.get_children().filter(func(key): return key.visible).size()
	var navigation_width = visible_navigation * 90.0 + maxi(0, visible_navigation - 1) * 25.0
	navigation.position = Vector2(s.x - navigation_width - 28, 28)
	navigation.size = Vector2(navigation_width, 112)
	message_label.position = Vector2(s.x * 0.25, 140)
	message_label.size = Vector2(s.x * 0.5, 64)
	skill_cluster.position = s - SKILL_CLUSTER_SIZE - SKILL_CLUSTER_MARGIN
	skill_cluster.size = SKILL_CLUSTER_SIZE
	attack_mode_button.hit_padding = maxf(8.0, (48.0 / ui_scale - attack_mode_button.size.x) * 0.5)
	vitals.position = Vector2(s.x * 0.5 - 122, s.y - 145)
	vitals.size = Vector2(244, 80)
	joystick.position = Vector2(0, s.y * 0.42)
	joystick.size = Vector2(s.x * 0.4, s.y * 0.58)
	joystick.home = Vector2(128, joystick.size.y - 140)
	joystick.queue_redraw()
	# Match the complete 402 x 82 sprite instead of squeezing its nine-slice caps.
	primary.size = Vector2(260, 260.0 * 82.0 / 402.0)
	pickup_panel.layout(s)
	for control in [navigation, message_label, skill_cluster, vitals, joystick, primary, pickup_panel, counters, title_label, camp_button]:
		control.scale = Vector2.ONE * ui_scale
		control.position *= ui_scale
	if OS.has_feature("mobile"):
		skill_cluster.position -= skill_safe_insets(screen, Vector2(DisplayServer.window_get_size()), Rect2(DisplayServer.get_display_safe_area()))
	_layout_interaction(ui_scale)
	_layout_camp_button()
	for key in skill_buttons:
		var pickup_bounds = pickup_panel.get_global_rect()
		var skill_bounds = key.get_global_rect()
		if pickup_bounds.intersects(skill_bounds):
			pickup_panel.position.y -= pickup_bounds.end.y - skill_bounds.position.y + 12 * ui_scale
	# State refreshes must not cancel a held skill; only changed geometry does.
	if previous_skill_transform != skill_cluster.get_global_transform_with_canvas():
		for key in skill_buttons: key.release(true)
		attack_mode_button.release(true)
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

func _layout_interaction(ui_scale: float) -> void:
	# Share the skill anchor so mobile safe-area shifts keep the gap intact.
	primary.position = skill_cluster.position + INTERACTION_OFFSET * ui_scale
	var margin := 16.0 * ui_scale
	primary.position.x = clampf(primary.position.x, margin, root.size.x - primary.size.x * ui_scale - margin)
	primary.position.y = clampf(primary.position.y, margin, root.size.y - primary.size.y * ui_scale - margin)

func _layout_camp_button() -> void:
	if not is_instance_valid(camp_button): return
	var ui_scale := counters.scale.y
	camp_button.position.y = maxf(198.0 * ui_scale, counters.position.y + (counters.get_combined_minimum_size().y + 14.0) * ui_scale)

static func skill_safe_insets(viewport_size: Vector2, window_size: Vector2, safe_area: Rect2) -> Vector2:
	if window_size.x <= 0 or window_size.y <= 0 or not safe_area.has_area(): return Vector2.ZERO
	return (window_size - safe_area.end).max(Vector2.ZERO) * viewport_size / window_size

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
	for index in counter_values.size():
		var id = int(RESOURCE_IDS[index])
		counter_buttons[index].disabled = adventure_mode
		counter_buttons[index].tooltip_text = "探索点" if id == 12101 else DungeonCatalog.clean(systems.material_name(id))
		var amount: int = systems.search_point_count() if id == 12101 else systems.material(id)
		var caption := "%d/%d" % [amount, systems.search_point_max()] if id == 12101 else ""
		# Search uses the source's first-display string path, without numeric popups.
		counter_buttons[index].update_amount(amount, caption, id != 12101)
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
