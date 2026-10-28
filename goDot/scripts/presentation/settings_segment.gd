extends HBoxContainer

const SOURCE_SELECTION_HEIGHT_RATIO := 62.3224983215332 / 54.43000030517578
var selection_style: StyleBox
var selected_index := -1
var _motion: Tween
var _selection_rect := Rect2():
	set(value):
		_selection_rect = value
		queue_redraw()

func _ready() -> void:
	add_theme_constant_override("separation", 0)
	sort_children.connect(_snap_selection)

func select_index(index: int, animate := true) -> void:
	if index < 0 or index >= get_child_count(): return
	if selected_index == index: return
	var initial := selected_index < 0
	selected_index = index
	for child in get_children():
		child.set_meta("selected", child.get_index() == index)
	if is_instance_valid(_motion): _motion.kill()
	var target: Rect2 = get_child(index).get_rect()
	if initial or not animate or target.size.x <= 0:
		_selection_rect = target
		return
	_motion = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_motion.tween_property(self, "_selection_rect", target, 0.3 / float(DungeonSettings.read_options().ui_speed))

func _snap_selection() -> void:
	if selected_index < 0 or selected_index >= get_child_count(): return
	if is_instance_valid(_motion): _motion.kill()
	_selection_rect = get_child(selected_index).get_rect()

func _draw() -> void:
	if selection_style and _selection_rect.has_area():
		var padding := _selection_rect.size.y * (SOURCE_SELECTION_HEIGHT_RATIO - 1.0) * 0.5
		selection_style.draw(get_canvas_item(), _selection_rect.grow_individual(0, padding, 0, padding))
