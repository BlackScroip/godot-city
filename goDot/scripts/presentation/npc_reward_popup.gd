extends Control

signal closed

var _panel: PanelContainer
var _grid: GridContainer
var _closed := false

func configure(rewards: Variant) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.65)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", DungeonStyle.box(Color("23252b")))
	add_child(_panel)
	var margins := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: margins.add_theme_constant_override("margin_" + side, 20)
	_panel.add_child(margins)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 16)
	margins.add_child(stack)
	var title := DungeonStyle.label("获得奖励", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stack.add_child(scroll)
	_grid = GridContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(_grid)
	var rows: Array = []
	if rewards is Dictionary:
		for id in rewards: rows.append({"id": int(id), "count": int(rewards[id]), "icon": "material:" + str(id)})
	elif rewards is Array: rows = rewards
	for row in rows:
		if not row is Dictionary: continue
		var item := VBoxContainer.new()
		item.custom_minimum_size.x = 88
		_grid.add_child(item)
		item.add_child(DungeonStyle.picture(str(row.get("icon", "material:" + str(row.get("id", 0)))), Vector2(72, 72)))
		var name := DungeonStyle.label(str(row.get("name", "")), 16)
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		item.add_child(name)
		var count := DungeonStyle.label("× %d" % int(row.get("count", row.get("amount", 1))), 20)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		item.add_child(count)
	var button := Button.new()
	button.text = "确定"
	button.custom_minimum_size.y = 44
	button.pressed.connect(func():
		if _closed: return
		_closed = true
		closed.emit())
	stack.add_child(button)
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	if not is_instance_valid(_panel): return
	_panel.size = Vector2(minf(600, maxf(220, size.x - 48)), minf(340, maxf(180, size.y - 40)))
	_panel.position = (size - _panel.size) * 0.5
	_grid.columns = maxi(1, int((_panel.size.x - 40) / 100))
