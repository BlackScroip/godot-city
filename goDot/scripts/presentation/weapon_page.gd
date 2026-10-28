class_name DungeonWeaponPage
extends Control

signal command(kind: String, id: Variant, extra: Variant)
signal closed
signal back_requested

const PAPER := Color("eee3d1")
const GOLD := Color("edbd53")
const INK := Color("413b3a")
const DESIGN := Vector2(2048, 900)
const ROLE_NAVIGATION = preload("res://scripts/presentation/role_navigation.gd")
const SELECTION_HIGHLIGHT = preload("res://scripts/presentation/selection_highlight.gd")

class WeaponPreview extends SubViewportContainer:

	const EFFECT_MATERIAL = preload("res://scripts/presentation/recovered_effect_material.gd")
	const SOURCE_MATERIALS := "res://assets/ui/role_weapon/source_materials.json"
	var viewport: SubViewport
	var pivot: Node3D
	var camera: Camera3D
	var model_path := ""
	var has_model := false
	var bounds := AABB()
	var _source_materials: Dictionary = {}
	var _effect_textures: Dictionary = {}
	var _effects: Array[ShaderMaterial] = []
	var _elapsed := 0.0

	func _ready() -> void:
		var source = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_MATERIALS))
		if source is Dictionary: _source_materials = source.get("materials", {})
		stretch = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		viewport = SubViewport.new()
		viewport.transparent_bg = true
		viewport.own_world_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
		add_child(viewport)
		pivot = Node3D.new()
		pivot.rotation_degrees.z = -36
		viewport.add_child(pivot)
		var environment = WorldEnvironment.new()
		environment.environment = Environment.new()
		environment.environment.background_mode = Environment.BG_CLEAR_COLOR
		environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.environment.ambient_light_color = Color.WHITE
		environment.environment.ambient_light_energy = 0.7
		viewport.add_child(environment)
		for rotation in [Vector3(-35, -25, 0), Vector3(25, 145, 0)]:
			var light = DirectionalLight3D.new()
			light.rotation_degrees = rotation
			light.light_energy = 1.2 if rotation.y < 0 else 0.7
			viewport.add_child(light)
		camera = Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.current = true
		viewport.add_child(camera)
		resized.connect(_fit)
		_fit.call_deferred()

	func show_model(path: String) -> void:
		model_path = path
		_effects.clear()
		_elapsed = 0.0
		for child in pivot.get_children():
			pivot.remove_child(child)
			child.queue_free()
		has_model = false
		if path.is_empty() or not ResourceLoader.exists(path): return
		var packed = load(path)
		if not packed is PackedScene: return
		var model = packed.instantiate()
		pivot.add_child(model)
		model.rotation_degrees = Vector3(90, 0, 0)
		var first := true
		for mesh in model.find_children("*", "MeshInstance3D", true, false):
			for surface in mesh.mesh.get_surface_count():
				var material: Material = mesh.get_active_material(surface)
				if material == null or not _source_materials.has(material.resource_name): continue
				var definition: Dictionary = _source_materials[material.resource_name]
				var effect: ShaderMaterial = EFFECT_MATERIAL.create(definition, _effect_textures)
				effect.set_shader_parameter("source_fade_vertex_alpha", bool(definition.get("fade_vertex_alpha", false)))
				mesh.set_surface_override_material(surface, effect)
				_effects.append(effect)
			var box: AABB = mesh.global_transform * mesh.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
		has_model = not first
		_fit()

	func _process(delta: float) -> void:
		if _effects.is_empty() or not is_visible_in_tree(): return
		_elapsed += delta
		for material in _effects: material.set_shader_parameter("clock", _elapsed)

	func _fit() -> void:
		if not is_inside_tree() or not is_instance_valid(viewport) or not is_instance_valid(camera) or not camera.is_inside_tree(): return
		if not has_model: return
		var aspect = maxf(0.01, size.x / maxf(1, size.y))
		camera.size = maxf(bounds.size.y, bounds.size.x / aspect) * 1.13
		camera.position = bounds.get_center() + Vector3(0, 0, maxf(8, bounds.size.length() * 2))
		camera.look_at(bounds.get_center())

var owner_page: DungeonMenuPage
var rows: Array = []
var context: Dictionary = {}
var selected_weapon := 0
var selector_open := false
var canvas: Control
var preview: WeaponPreview
var model_preview: WeaponPreview
var selector_preview: WeaponPreview
var artwork: TextureRect
var selector_artwork: TextureRect
var selector_entry: Button
var navigation: Array[Button] = []
var weapon_buttons: Dictionary = {}
var action_buttons: Array[Button] = []
var name_label: Label
var rank_label: Label
var effect_label: SourceRichText
var biography: SourceRichText
var detail_scroll: ScrollContainer
var selector: Control
var selector_name: Label
var selector_effect: SourceRichText
var selector_description: SourceRichText
var selector_status: Label
var selector_actions: BoxContainer
var _catalog: DungeonCatalog
var _resources: HBoxContainer
var _selector_resources: HBoxContainer
var _selector_background: TextureRect
var _selector_base: ColorRect
var _selector_top: TextureRect
var _selector_strip: BoxContainer
var _selector_scroll: ScrollContainer
var _selector_inside: MarginContainer
var _paper_parts: Array[Control] = []
var _map: Dictionary = {}
var _selector_map: Dictionary = {}
var _main_effect_stack: VBoxContainer

func configure(host: DungeonMenuPage, data: Array, page_context: Dictionary = {}) -> void:
	owner_page = host
	rows = data
	context = page_context
	_catalog = context.get("catalog") as DungeonCatalog
	theme = DungeonStyle.theme()
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	clip_contents = true
	for pair in [["res://assets/ui/role_character/resource_map.json", _map], ["res://assets/ui/role_weapon/resource_map.json", _selector_map], ["res://assets/ui/role_weapon/weapon_icon_resource_map.json", _selector_map]]:
		if FileAccess.file_exists(pair[0]):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(pair[0]))
			if parsed is Dictionary: pair[1].merge(parsed)
	var background = _picture("charamenumask_1")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(background)
	canvas = Control.new()
	canvas.name = "OriginalWeaponPage"
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	_build_header(canvas, false)
	_build_navigation()
	preview = WeaponPreview.new()
	preview.name = "WeaponModel"
	_place(canvas, preview, Rect2(453, 155, 1000, 588))
	model_preview = preview
	artwork = _picture("")
	_place(canvas, artwork, Rect2(453, 155, 1000, 588))
	_build_detail()
	selector_entry = _icon_button("", "武器", Vector2(110, 115))
	_place(canvas, selector_entry, Rect2(390, 756, 110, 115))
	_place(selector_entry, _picture("武器(未选择)"), Rect2(7, 0, 75, 75))
	var switch_label = _label("武器", 25)
	switch_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	switch_label.clip_text = true
	switch_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(selector_entry, switch_label, Rect2(10, 85, 90, 35))
	DungeonStyle.fit_label_text(switch_label, 25)
	var switch_icon = _picture("sprite_conversation_switch")
	_place(selector_entry, switch_icon, Rect2(64, 35, 40, 45))
	selector_entry.pressed.connect(func(): open_selector())
	_build_selector()
	var requested = int(context.get("selected_weapon", context.get("equipped_weapon", 0)))
	if _row(requested).is_empty() and not rows.is_empty(): requested = _id(rows[0])
	select_weapon(requested)
	set_selector_open(bool(context.get("weapon_selector_open", false)))
	resized.connect(_adapt)
	_adapt.call_deferred()

func _build_header(parent: Control, is_selector: bool) -> void:
	var back = ROLE_NAVIGATION.create_back_button()
	_place(parent, back, ROLE_NAVIGATION.BACK_RECT)
	back.pressed.connect(func():
		if is_selector: _leave_selector()
		else: back_requested.emit())
	var title = _picture("武器" if is_selector else "角色详情", is_selector)
	var title_width := (230 if not is_selector else 140) if DungeonLocale.current_locale() == "zh_CN" else 650
	_place(parent, title, Rect2(154, 30, title_width, 75))
	DungeonStyle.localize_artwork_title(title, "武器" if is_selector else "角色详情", 44, PAPER)
	var bar = HBoxContainer.new()
	bar.add_theme_constant_override("separation", 16)
	_place(parent, bar, Rect2(979, 25, 1015, 55))
	bar.alignment = BoxContainer.ALIGNMENT_END
	for resource in context.get("resources", []):
		var line = Control.new()
		line.custom_minimum_size = Vector2(210, 49)
		bar.add_child(line)
		_place(line, _picture("货币_底"), Rect2(0, 1, 210, 47))
		var icon_key = str(resource[0])
		if icon_key == "loot:12101": icon_key = "sprite_abilityitemicon_15101"
		if icon_key.begins_with("material:"): icon_key = "sprite_materialicon_" + icon_key.get_slice(":", 1)
		var icon = _picture(icon_key)
		_place(line, icon, Rect2(-4, 0, 49, 49))
		var value = _label(str(resource[1]), 28)
		value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		value.autowrap_mode = TextServer.AUTOWRAP_OFF
		_place(line, value, Rect2(54, 0, 153, 49))
	if is_selector: _selector_resources = bar
	else: _resources = bar

func _build_navigation() -> void:
	var entries: Array = context.get("role_navigation", [])
	if entries.is_empty():
		entries = [{"label": "角色", "page": "characters"}, {"label": "武器", "page": "weapons"}]
		if context.get("in_run", false): entries.append({"label": "背包", "page": "inventory"})
		entries.append({"label": "仓库", "page": "storage"})
		if context.get("in_run", false) and context.get("partner_navigation", false): entries.append({"label": "伙伴", "page": "partners"})
	var names = {"characters": "角色详情(未选择)", "weapons": "武器(选择)", "inventory": "道具(未选择)", "storage": "仓库(未选择)", "partners": "怪物伙伴(未选择)"}
	for index in entries.size():
		var entry: Dictionary = entries[index]
		var page = str(entry.get("page", ""))
		var active = page == "weapons"
		var button = _icon_button(str(names.get(page, entry.get("icon", ""))), str(entry.get("label", "")), Vector2(420, 111))
		button.text = str(entry.get("label", ""))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 36)
		button.add_theme_color_override("font_color", PAPER if active else Color("cbbca7"))
		button.add_theme_color_override("font_hover_color", PAPER)
		button.add_theme_constant_override("icon_max_width", 57)
		button.add_theme_constant_override("h_separation", 10)
		for state in ["normal", "hover", "pressed", "focus"]:
			var shape = StyleBoxTexture.new()
			shape.texture = _texture("分类选中" if active or state == "hover" else "侧边按钮暗")
			shape.content_margin_left = 92
			if not active and state != "hover": shape.modulate_color = Color(1, 1, 1, 0.06)
			button.add_theme_stylebox_override(state, shape)
		_place(canvas, button, Rect2(0, 137 + index * 111, 420, 111))
		var divider = _picture("分割线1")
		divider.stretch_mode = TextureRect.STRETCH_SCALE
		divider.modulate = Color(1, 0.86, 0.61, 0.38)
		_place(button, divider, Rect2(0, 108, 420, 3))
		button.pressed.connect(func():
			if page != "weapons": command.emit("page:" + page, int(context.get("character_id", 0)) if page == "characters" else 0, 0))
		navigation.append(button)

func _build_detail() -> void:
	detail_scroll = ScrollContainer.new()
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_place(canvas, detail_scroll, Rect2(1565, 192, 425, 572))
	var stack = VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 18)
	detail_scroll.add_child(stack)
	name_label = _label("", 34)
	stack.add_child(name_label)
	_main_effect_stack = VBoxContainer.new()
	_main_effect_stack.add_theme_constant_override("separation", 2)
	stack.add_child(_main_effect_stack)
	rank_label = _label("", 25)
	_main_effect_stack.add_child(rank_label)
	effect_label = _rich_label("", 26)
	effect_label.add_theme_color_override("default_color", Color("d45335"))
	effect_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_main_effect_stack.add_child(effect_label)
	var divider = _picture("18")
	divider.custom_minimum_size.y = 3
	divider.stretch_mode = TextureRect.STRETCH_SCALE
	stack.add_child(divider)
	biography = _rich_label("", 25)
	biography.add_theme_constant_override("line_separation", 2)
	stack.add_child(biography)

func _build_selector() -> void:
	var direct: bool = context.get("weapon_selector_direct", false)
	selector = Control.new()
	selector.name = "OriginalWeaponSelector"
	_place(canvas, selector, Rect2(Vector2.ZERO, DESIGN))
	var base = ColorRect.new()
	base.color = Color.BLACK
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(selector, base, Rect2(Vector2.ZERO, DESIGN))
	_selector_base = base
	var background = _picture("charamenumask_1" if direct else "通用背景", not direct)
	_place(selector, background, Rect2(Vector2.ZERO, DESIGN))
	background.stretch_mode = TextureRect.STRETCH_SCALE
	_selector_background = background
	var top = _picture("顶部", true)
	top.stretch_mode = TextureRect.STRETCH_SCALE
	_place(selector, top, Rect2(0, 0, 2048, 110))
	_selector_top = top
	top.visible = not direct
	_build_header(selector, true)
	selector_preview = WeaponPreview.new()
	selector_preview.name = "SelectorWeaponModel"
	_place(selector, selector_preview, Rect2(200, 115, 1065, 570))
	selector_artwork = _picture("")
	_place(selector, selector_artwork, Rect2(200, 115, 1065, 570))
	var strip: BoxContainer = VBoxContainer.new() if direct else HBoxContainer.new()
	strip.add_theme_constant_override("separation", 20)
	strip.alignment = BoxContainer.ALIGNMENT_CENTER
	_place(selector, strip, Rect2(290, 695, 975, 155))
	_selector_strip = strip
	if direct:
		_selector_scroll = ScrollContainer.new()
		_selector_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_place(selector, _selector_scroll, Rect2(40, 140, 175, 700))
		var padding = MarginContainer.new()
		padding.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]: padding.add_theme_constant_override(side, 26)
		_selector_scroll.add_child(padding)
		strip.reparent(padding)
		strip.alignment = BoxContainer.ALIGNMENT_BEGIN
	for row in rows:
		var id = _id(row)
		var button = Button.new()
		button.custom_minimum_size = Vector2(145, 145)
		button.tooltip_text = _title(row)
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		strip.add_child(button)
		var slot_frame = _picture("slotfg_rare_square_1_v2", true)
		slot_frame.name = "SlotFrame"
		_place(button, slot_frame, Rect2(0, 0, 145, 145))
		var source = _catalog.find("WeaponData", id) if _catalog else {}
		var icon = _picture(str(source.get("square_icon_name", row.get("icon", "sprite_weaponicon_square_" + str(id)))), true)
		_place(button, icon, Rect2(8, 5, 129, 129))
		var highlight = _picture("选择高亮", true)
		highlight.name = "Selected"
		highlight.stretch_mode = TextureRect.STRETCH_SCALE
		highlight.z_index = 1
		button.add_child(highlight)
		SELECTION_HIGHLIGHT.place(highlight, slot_frame.size)
		if int(row.get("rank", 0)) == 0:
			var mask = _picture("锁定遮罩", true)
			mask.modulate = Color(0, 0, 0, 0.349)
			_place(button, mask, Rect2(0, 0, 145, 145))
			_place(button, _picture("锁", true), Rect2(55, 45, 35, 46))
		else:
			var stars = HBoxContainer.new()
			stars.alignment = BoxContainer.ALIGNMENT_CENTER
			stars.add_theme_constant_override("separation", 0)
			_place(button, stars, Rect2(5, 121, 135, 23))
			for star_index in 5:
				var star = _picture("星星大" if star_index < int(row.get("rank", 0)) else "星星底", true)
				star.custom_minimum_size = Vector2(23, 23)
				stars.add_child(star)
		button.pressed.connect(func(): select_weapon(id))
		weapon_buttons[id] = button
	var left_paper = _patch("详情_底框_0", Vector4(69, 73, 3, 70))
	_place(selector, left_paper, Rect2(1350, 135, 300, 615))
	var right_paper = _patch("详情_底框_0", Vector4(69, 73, 3, 70))
	_place(selector, right_paper, Rect2(1950, 135, 300, 615))
	right_paper.scale.x = -1
	var middle_paper = _patch("详情_底框_2", Vector4(0, 72, 0, 70))
	_place(selector, middle_paper, Rect2(1569, 135, 162, 615))
	_paper_parts.assign([left_paper, right_paper, middle_paper])
	for part in _paper_parts: part.visible = not direct
	var inside = MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]: inside.add_theme_constant_override(side, 35)
	_place(selector, inside, Rect2(1360, 143, 580, 595))
	_selector_inside = inside
	var stack = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 17)
	inside.add_child(stack)
	selector_name = _label("", 36)
	selector_name.add_theme_color_override("font_color", INK)
	selector_name.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	stack.add_child(selector_name)
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stack.add_child(scroll)
	var information = VBoxContainer.new()
	information.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	information.add_theme_constant_override("separation", 18)
	scroll.add_child(information)
	selector_effect = _rich_label("", 27)
	selector_effect.add_theme_color_override("default_color", INK)
	selector_effect.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	information.add_child(selector_effect)
	var divider = _picture("18", true)
	divider.custom_minimum_size.y = 3
	divider.stretch_mode = TextureRect.STRETCH_SCALE
	divider.modulate = INK
	information.add_child(divider)
	selector_description = _rich_label("", 25)
	selector_description.add_theme_color_override("default_color", INK)
	selector_description.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	information.add_child(selector_description)
	selector_status = _label("", 22)
	selector_status.add_theme_color_override("font_color", Color("7a5044"))
	selector_status.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	information.add_child(selector_status)
	selector_actions = HBoxContainer.new() if direct else VBoxContainer.new()
	selector_actions.add_theme_constant_override("separation", 10)
	stack.add_child(selector_actions)
	if direct:
		selector_actions.reparent(selector)
		selector_actions.alignment = BoxContainer.ALIGNMENT_CENTER
		selector_description.hide()
		divider.hide()
		selector_name.add_theme_color_override("font_color", PAPER)
		selector_effect.add_theme_color_override("default_color", Color("edbca5"))
		selector_status.add_theme_color_override("font_color", PAPER)

func select_weapon(id: int) -> void:
	var row = _row(id)
	if row.is_empty(): return
	selected_weapon = id
	context["selected_weapon"] = id
	if is_instance_valid(owner_page): owner_page.page_context["selected_weapon"] = id
	name_label.text = _title(row)
	var rank = int(row.get("rank", 0))
	rank_label.text = "等级%d：" % maxi(1, rank)
	effect_label.set_source(_effect(row))
	biography.set_source(SourceRichText.source_field("WeaponData", id, "description", str(row.get("source_description", row.get("description", "")))).strip_edges())
	preview.show_model(str(row.get("model", "")))
	selector_preview.show_model(str(row.get("model", "")))
	artwork.texture = _fallback_art(row)
	selector_artwork.texture = artwork.texture
	artwork.visible = not selector_open and not preview.has_model and artwork.texture != null
	selector_artwork.visible = not selector_preview.has_model and selector_artwork.texture != null
	selector_name.text = _title(row)
	selector_effect.set_source(("等级%d：\n" % maxi(1, rank)) + _effect(row))
	selector_description.set_source(biography.source_text)
	var all_effects = DungeonCatalog.clean(str(row.get("effect_description", ""))).replace("|", "\n").strip_edges()
	if context.get("weapon_selector_direct", false):
		var source = _catalog.find("WeaponData", id) if _catalog else {}
		var levels = SourceRichText.source_field("WeaponData", id, "effect_description", str(source.get("effect_description", row.get("effect_description", "")))).split("|")
		var descriptions: PackedStringArray = []
		for index in levels.size(): descriptions.append("等级%d：\n%s" % [index + 1, levels[index].strip_edges()])
		selector_effect.set_source("\n".join(descriptions))
	var details = str(row.get("description", "")).strip_edges()
	if not all_effects.is_empty(): details = details.trim_suffix(all_effects).strip_edges()
	var catalog_description = str(row.get("source_description", biography.source_text))
	selector_status.text = details.trim_prefix(DungeonCatalog.clean(catalog_description)).strip_edges()
	if selector_status.text.is_empty() and rank == 0: selector_status.text = "未解锁"
	if int(context.get("equipped_weapon", 0)) == id:
		selector_status.text = "已装备" + ("\n" + selector_status.text if not selector_status.text.is_empty() else "")
	action_buttons.clear()
	for child in selector_actions.get_children():
		selector_actions.remove_child(child)
		child.queue_free()
	for entry in row.get("buttons", []):
		var button = Button.new()
		button.text = str(entry.get("text", ""))
		button.tooltip_text = selector_status.text
		button.custom_minimum_size = Vector2(0, 55)
		if context.get("weapon_selector_direct", false): button.custom_minimum_size = Vector2(250, 70)
		button.add_theme_font_size_override("font_size", 27)
		if context.get("weapon_selector_direct", false): button.add_theme_font_size_override("font_size", 40)
		button.add_theme_color_override("font_color", INK)
		button.add_theme_color_override("font_hover_color", INK)
		button.add_theme_color_override("font_pressed_color", INK)
		button.add_theme_color_override("font_disabled_color", Color("8e8580"))
		for state in ["normal", "hover", "pressed", "disabled"]:
			var style = StyleBoxTexture.new()
			style.texture = _texture("几何ui-椭圆白色按钮", true)
			style.texture_margin_left = 70
			style.texture_margin_right = 70
			button.add_theme_stylebox_override(state, style)
		button.disabled = bool(entry.get("disabled", false))
		button.pressed.connect(func(): _emit_entry(entry))
		selector_actions.add_child(button)
		action_buttons.append(button)
	for weapon_id in weapon_buttons:
		weapon_buttons[weapon_id].get_node("Selected").visible = int(weapon_id) == id
	if is_instance_valid(_selector_scroll) and weapon_buttons.has(id):
		_selector_scroll.call_deferred("ensure_control_visible", weapon_buttons[id].get_node("Selected"))
	detail_scroll.scroll_vertical = 0

func open_selector() -> void:
	set_selector_open(true)

func _leave_selector() -> void:
	if context.get("weapon_selector_direct", false): back_requested.emit()
	else: set_selector_open(false)

func set_selector_open(value: bool) -> void:
	selector_open = value
	for child in canvas.get_children():
		if child != selector: child.visible = not value
	artwork.visible = not value and not preview.has_model and artwork.texture != null
	selector.visible = value
	context["weapon_selector_open"] = value
	if is_instance_valid(owner_page): owner_page.page_context["weapon_selector_open"] = value

func _emit_entry(entry: Dictionary) -> void:
	if bool(entry.get("disabled", false)): return
	command.emit(str(entry.get("action", "")), entry.get("id", 0), entry.get("extra", 0))

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and selector_open:
		_leave_selector()
		get_viewport().set_input_as_handled()

func _adapt() -> void:
	if not is_inside_tree(): return
	var ratio = minf(size.x / DESIGN.x, size.y / DESIGN.y)
	if ratio <= 0: return
	canvas.size = size / ratio
	canvas.scale = Vector2.ONE * ratio
	canvas.position = Vector2.ZERO
	ROLE_NAVIGATION.place_back_button(canvas.get_node("RoleBackButton"))
	ROLE_NAVIGATION.place_back_button(selector.get_node("RoleBackButton"))
	var width = canvas.size.x
	var height = canvas.size.y
	_resources.position.x = width - 1069
	_selector_resources.position.x = width - 1069
	preview.position = Vector2(453 + (width - DESIGN.x) * 0.5, (height - preview.size.y) * 0.5)
	artwork.position = preview.position
	selector_entry.position.y = height - 144
	detail_scroll.position.x = width - 483
	detail_scroll.size.y = height - 328
	selector.size = canvas.size
	_selector_base.size = canvas.size
	_selector_background.size = canvas.size
	_selector_top.size.x = width
	selector_preview.size = Vector2(width - 983, height - 330)
	selector_artwork.position = selector_preview.position
	selector_artwork.size = selector_preview.size
	if not context.get("weapon_selector_direct", false):
		_selector_strip.position.y = height - 205
		_selector_strip.size.x = width - 1073
	_paper_parts[0].position.x = width - 698
	_paper_parts[1].position.x = width - 98
	_paper_parts[2].position.x = width - 479
	for part in _paper_parts: part.size.y = height - 285
	_selector_inside.position.x = width - 688
	_selector_inside.size.y = height - 305
	if context.get("weapon_selector_direct", false):
		_selector_scroll.position = Vector2(14, 114)
		_selector_scroll.size = Vector2(220, height - 164)
		_selector_strip.custom_minimum_size = Vector2(145, 0)
		selector_preview.position = Vector2(250, 150)
		selector_preview.size = Vector2(width - 850, height - 330)
		selector_artwork.position = selector_preview.position
		selector_artwork.size = selector_preview.size
		_selector_inside.position = Vector2(width - 550, 150)
		_selector_inside.size = Vector2(510, height - 200)
		var action_height = maxf(80, 44 / ratio)
		selector_actions.position = Vector2(260, height - action_height - 35)
		selector_actions.size = Vector2(width - 890, action_height)
		for button in action_buttons: button.custom_minimum_size.y = action_height

func _effect(row: Dictionary) -> String:
	var source = _catalog.find("WeaponData", _id(row)) if _catalog else {}
	var text = SourceRichText.source_field("WeaponData", _id(row), "effect_description", str(source.get("effect_description", row.get("effect_description", ""))))
	var ranks = text.split("|")
	if ranks.size() > 1:
		text = ranks[clampi(int(row.get("rank", 1)) - 1, 0, ranks.size() - 1)]
	return text.strip_edges()

func _title(row: Dictionary) -> String:
	var source = _catalog.find("WeaponData", _id(row)) if _catalog else {}
	var fallback = DungeonCatalog.row_name(source) if not source.is_empty() else str(row.get("title", "")).split("  ")[0]
	return DungeonCatalog.clean(SourceRichText.source_field("WeaponData", _id(row), "name", fallback))

func _fallback_art(row: Dictionary) -> Texture2D:
	var source = _catalog.find("WeaponData", _id(row)) if _catalog else {}
	for key in [source.get("full_icon_name", ""), source.get("square_icon_name", ""), row.get("icon", "")]:
		if not str(key).begins_with("sprite_weaponicon_"): continue
		var image = _texture(str(key), true)
		if image: return image
	return null

func _id(row: Dictionary) -> int:
	return int(row.get("weapon_id", row.get("config_id", 0)))

func _row(id: int) -> Dictionary:
	for row in rows:
		if _id(row) == id: return row
	return {}

func _texture(key: String, from_selector := false) -> Texture2D:
	var path = str(_selector_map.get(key, _map.get(key, key))) if from_selector else str(_map.get(key, _selector_map.get(key, key)))
	return DungeonStyle.texture(path)

func _picture(key: String, from_selector := false) -> TextureRect:
	var result = TextureRect.new()
	result.texture = _texture(key, from_selector)
	result.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	result.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result

func _patch(key: String, borders: Vector4) -> NinePatchRect:
	var result = NinePatchRect.new()
	result.texture = _texture(key, true)
	result.patch_margin_left = int(borders.x)
	result.patch_margin_top = int(borders.y)
	result.patch_margin_right = int(borders.z)
	result.patch_margin_bottom = int(borders.w)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result

func _label(text: String, font_size: int) -> Label:
	var result = DungeonStyle.label(text, font_size)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.add_theme_color_override("font_color", PAPER)
	result.add_theme_color_override("font_shadow_color", Color(0.1, 0.05, 0.03, 0.65))
	return result

func _rich_label(text: String, font_size: int) -> SourceRichText:
	var result = SourceRichText.new()
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for font in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size"]:
		result.add_theme_font_size_override(font, font_size)
	result.add_theme_color_override("default_color", PAPER)
	result.add_theme_color_override("font_shadow_color", Color(0.1, 0.05, 0.03, 0.65))
	result.set_source(text)
	return result

func _icon_button(key: String, hint: String, minimum: Vector2) -> Button:
	var result = Button.new()
	result.icon = _texture(key)
	result.expand_icon = true
	result.add_theme_constant_override("icon_max_width", int(minimum.x))
	result.custom_minimum_size = minimum
	result.tooltip_text = hint
	for state in ["normal", "hover", "pressed", "focus"]: result.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	return result

func _place(parent: Node, control: Control, rectangle: Rect2) -> void:
	parent.add_child(control)
	control.position = rectangle.position
	control.size = rectangle.size
