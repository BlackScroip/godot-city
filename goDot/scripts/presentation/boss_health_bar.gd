extends Control

const StateBar = preload("res://scripts/presentation/health_state_bar.gd")
const BAR_SIZE := Vector2(479.1588, 35.9008)
const LOCK_HORIZONTAL_INSET := 10.0
const LOCK_SIZE := Vector2(BAR_SIZE.x - LOCK_HORIZONTAL_INSET * 2.0, BAR_SIZE.y * 44.0 / 64.0)

var bar = StateBar.new()
var name_label := DungeonStyle.label("", 25)
var health_label := DungeonStyle.label("", 25)
var shield_text := DungeonStyle.label("", 18)
var shield_fraction := 0.0
var shield_overcap := 0.0
var shield_overlay := Control.new()
var lock_overlay := Control.new()
var lock_active := false
var special_bar = StateBar.new()
var special_text := DungeonStyle.label("", 16)
var _lock_image: NinePatchRect
var _lock_icon: TextureRect
var _target_id := 0
var _lock_time := 0.0
var _lock_clip := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(550, 150)
	_picture("Container_Name/Image_Name", Vector2(30, 0), Vector2(490, 64))
	add_child(name_label)
	_label(name_label, Vector2(50, 14), Vector2(450, 35))
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(bar)
	bar.configure("boss", "HpStateBar")
	bar.position = Vector2(35, 54.44)
	bar.size = BAR_SIZE
	for edge in [false, true]:
		var picture := _picture("HpStateBar/Image_LeftDotLeft" if edge else "HpStateBar/Image_LeftDot",
			bar.position + Vector2(BAR_SIZE.x - 10.9 if edge else -29.57, -2.05), Vector2(40, 40))
		picture.flip_h = edge
	add_child(shield_overlay)
	shield_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shield_overlay.position = bar.position
	shield_overlay.size = BAR_SIZE
	shield_overlay.draw.connect(_draw_shield)
	add_child(health_label)
	var text_inset := 44.0 + LOCK_HORIZONTAL_INSET
	_label(health_label, bar.position + Vector2(text_inset, 4), Vector2(BAR_SIZE.x - text_inset * 2.0, 27))
	health_label.z_index = 1
	add_child(shield_text)
	_label(shield_text, bar.position + Vector2(0, BAR_SIZE.y + 4), Vector2(BAR_SIZE.x, 24))
	shield_text.add_theme_color_override("font_color", Color(0.6531, 0.467, 1.0))
	shield_text.hide()
	add_child(lock_overlay)
	lock_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lock_overlay.size = LOCK_SIZE
	lock_overlay.pivot_offset = lock_overlay.size * 0.5
	lock_overlay.position = bar.position + BAR_SIZE * 0.5 - lock_overlay.pivot_offset
	var lock_art: Dictionary = StateBar.source("boss").images["HpStateBar/Invincible"]
	_lock_image = NinePatchRect.new()
	_lock_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lock_image.texture = DungeonStyle.texture(str(lock_art.resource))
	_lock_image.size = LOCK_SIZE
	for pair in [[SIDE_LEFT, "x"], [SIDE_BOTTOM, "y"], [SIDE_RIGHT, "z"], [SIDE_TOP, "w"]]:
		_lock_image.set_patch_margin(pair[0], roundi(float(lock_art.border[pair[1]])))
	_lock_image.modulate.a = float(lock_art.color.a)
	lock_overlay.add_child(_lock_image)
	_lock_icon = _picture("HpStateBar/Invincible/LockHp", Vector2(12, (LOCK_SIZE.y - 30.0) * 0.5), Vector2(24, 30), lock_overlay)
	lock_overlay.hide()
	add_child(special_bar)
	special_bar.configure("boss", "SpecialStateBar")
	special_bar.position = Vector2(35, 123)
	special_bar.size = Vector2(BAR_SIZE.x, 15.6158)
	special_bar.hide()
	add_child(special_text)
	_label(special_text, Vector2(35, 120), Vector2(BAR_SIZE.x, 21))
	special_text.hide()
	hide()

static func is_displayable(actor: DungeonActor) -> bool:
	return is_instance_valid(actor) and not actor.is_player and not actor.dead and actor.combat != null and actor.combat.health > 0.0 and actor.combat.enemy.get("rank", "") == "Boss" and actor.is_visible_in_tree() and (not is_instance_valid(actor.visual) or actor.visual.visible)

static func select_target(actors: Array) -> DungeonActor:
	for actor in actors:
		if is_displayable(actor): return actor
	return null

func update_actor(actor: DungeonActor, title: String, delta: float) -> void:
	if not is_displayable(actor):
		hide()
		_target_id = 0
		return
	if _target_id != actor.get_instance_id():
		_target_id = actor.get_instance_id()
		bar.reset()
		lock_active = false
		_lock_clip = ""
		lock_overlay.hide()
		special_bar.reset()
		special_bar.hide()
		special_text.hide()
	show()
	name_label.text = title
	_fit(name_label, 25)
	bar.update_health(actor.combat.health, actor.combat.max_health, delta)
	health_label.text = "%.0f/%.0f" % [actor.combat.health, actor.combat.max_health]
	_fit(health_label, 25)
	var shield := maxi(0, int(actor.combat.shield))
	var ratio := float(shield) / maxf(1.0, actor.combat.max_health)
	if ratio >= 0.01 and ratio <= 0.05: ratio = 0.05
	shield_fraction = clampf(ratio, 0.0, 1.0)
	shield_overcap = clampf(ratio - 1.0, 0.0, 1.0)
	shield_text.text = str(shield) if shield > 0 else ""
	shield_text.visible = shield > 0
	_fit(shield_text, 18)
	shield_overlay.queue_redraw()
	_update_lock(actor.combat.enemy_health_locked(), maxf(0.0, delta))

func update_special_state(display: bool, current: float, maximum: float, delta: float = 0.0) -> void:
	# The source exposes this API, but its normal Boss update does not call it.
	special_bar.visible = display
	special_text.visible = display
	if not display: return
	special_bar.update_health(current, maximum, delta)
	special_text.text = "%.0f/%.0f" % [current, maximum]
	_fit(special_text, 16)

func _draw_shield() -> void:
	var frame := Rect2(Vector2(-5.35, -1.28), BAR_SIZE + Vector2(10.7, 2.56))
	StateBar.draw_part(shield_overlay, "boss", "HpStateBar/Image_SheidlBar", frame, shield_fraction)
	StateBar.draw_part(shield_overlay, "boss", "HpStateBar/Image_SheidlBar/Image_SheidlBarBg", frame, shield_fraction)
	StateBar.draw_part(shield_overlay, "boss", "HpStateBar/Image_SheidlBar_Double", frame.grow(1.5), shield_overcap)
	for second in [false, true]:
		var amount := shield_overcap if second else shield_fraction
		if amount <= 0.0: continue
		var prefix := "HpStateBar/Image_SheidlBar_Double/" if second else "HpStateBar/Image_SheidlBar/"
		StateBar.draw_part(shield_overlay, "boss", prefix + ("Image_LeftDot (1)" if second else "Image_LeftDot"), Rect2(-29, -2, 40, 40))
		StateBar.draw_part(shield_overlay, "boss", prefix + ("Image_LeftDotLeft (1)" if second else "Image_LeftDotLeft"), Rect2(frame.position.x + frame.size.x * amount - 16, -2, 40, 40))

func _update_lock(active: bool, delta: float) -> void:
	if active != lock_active:
		lock_active = active
		_lock_time = 0.0
		_lock_clip = "BattlePlayerCtrl_BossInvincible" + ("" if active else "_Close")
		lock_overlay.show()
	if _lock_clip.is_empty(): return
	_lock_time += delta
	var clip: Dictionary = StateBar.source("boss").lock_animations[_lock_clip]
	var scale_keys: Array = clip.scale
	lock_overlay.scale = Vector2(_sample(scale_keys, _lock_time, "x"), _sample(scale_keys, _lock_time, "y"))
	for curve in clip.floats:
		var alpha := _sample(curve["keys"], _lock_time)
		if curve.path == "LockHp":
			_lock_icon.modulate.a = alpha
		elif curve.attribute == "m_Color.a":
			_lock_image.modulate.a = alpha
		else:
			lock_overlay.modulate.a = alpha
	if not lock_active and _lock_time >= 1.0 / 6.0: lock_overlay.hide()

func _sample(keys: Array, time: float, axis: String = "") -> float:
	var index := 0
	while index + 1 < keys.size() and time >= float(keys[index + 1].time): index += 1
	var left: Dictionary = keys[index]
	var start := float(left.value) if axis.is_empty() else float(left.value[axis])
	if index + 1 == keys.size(): return start
	var right: Dictionary = keys[index + 1]
	var span := float(right.time) - float(left.time)
	if span <= 0.0: return start
	var end := float(right.value) if axis.is_empty() else float(right.value[axis])
	var out_slope := float(left.outSlope) if axis.is_empty() else float(left.outSlope[axis])
	var in_slope := float(right.inSlope) if axis.is_empty() else float(right.inSlope[axis])
	var t := clampf((time - float(left.time)) / span, 0.0, 1.0)
	return (2 * t * t * t - 3 * t * t + 1) * start + (t * t * t - 2 * t * t + t) * span * out_slope + (-2 * t * t * t + 3 * t * t) * end + (t * t * t - t * t) * span * in_slope

func _picture(path: String, origin: Vector2, dimensions: Vector2, parent: Control = null) -> TextureRect:
	var part: Dictionary = StateBar.source("boss").images[path]
	var result := DungeonStyle.picture(str(part.resource), Vector2.ZERO)
	result.position = origin
	result.size = dimensions
	result.stretch_mode = TextureRect.STRETCH_SCALE
	var tint: Dictionary = part.color
	result.modulate = Color(tint.r, tint.g, tint.b, tint.a)
	(parent if parent != null else self).add_child(result)
	return result

func _label(value: Label, origin: Vector2, dimensions: Vector2) -> void:
	value.position = origin
	value.size = dimensions
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value.clip_text = true
	value.add_theme_color_override("font_outline_color", Color("101820"))
	value.add_theme_constant_override("outline_size", 3)

func _fit(label: Label, maximum: int) -> void:
	var font := label.get_theme_font("font")
	var font_size := maximum
	while font_size > 8 and font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > label.size.x:
		font_size -= 1
	label.add_theme_font_size_override("font_size", font_size)
