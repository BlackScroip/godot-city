extends "res://scripts/presentation/character_upgrade_dialog.gd"

func configure(source: DungeonSystems, id: int) -> void:
	super.configure(source, id)
	name = "CharacterRecruitDialog"

func refresh() -> void:
	quote = systems.character_recruit_status(character_id)
	for child in panel.get_children():
		if child.name == "Quote":
			panel.remove_child(child)
			child.queue_free()
	material_labels.clear()
	var content := Control.new()
	content.name = "Quote"
	content.size = DESIGN_SIZE
	panel.add_child(content)
	var character: Dictionary = systems.catalog.find("CharData", character_id)
	_label(content, "招募" + DungeonCatalog.clean(DungeonCatalog.row_name(character)), Rect2(70, 42, 710, 65), 38, GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	var portrait := _picture(content, str(character.get("chara_icon", "")), Rect2(115, 140, 165, 165))
	portrait.name = "RecruitPortrait"
	var description := DungeonCatalog.clean(DungeonCatalog.description(character))
	if description.begins_with("CharaData_Description_"):
		description = "生命值 %d\n攻击力 %d\n防御力 %d" % [int(character.get("hp", 0)), int(character.get("atk", 0)), int(character.get("def", 0))]
	var biography := _label(content, description, Rect2(315, 125, 435, 200), 26)
	biography.name = "RecruitDescription"
	biography.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(content, "所需材料", Rect2(300, 345, 250, 36), 24, Color("e0cea0"), HORIZONTAL_ALIGNMENT_CENTER)
	var materials: Array = []
	for key in quote.price:
		if int(quote.price[key]) > 0: materials.append(key)
	for index in materials.size():
		var key = materials[index]
		var x := 425.0 - materials.size() * 68.0 + index * 136.0 + 10.0
		var icon := DungeonStyle.picture("sprite_materialicon_%s" % key, Vector2(90, 90))
		content.add_child(icon)
		icon.position = Vector2(x + 8, 395)
		var owned := systems.material(int(key))
		var amount := _label(content, "%d/%d" % [owned, int(quote.price[key])], Rect2(x - 20, 480, 155, 32), 24, Color("b5e45b") if owned >= int(quote.price[key]) else Color("ff8f80"), HORIZONTAL_ALIGNMENT_CENTER)
		amount.tooltip_text = DungeonCatalog.clean(systems.material_name(int(key)))
		amount.mouse_filter = Control.MOUSE_FILTER_PASS
		material_labels.append(amount)
	reason_label = _label(content, str(quote.reason), Rect2(65, 520, 720, 52), 23, Color("ffb4a3"), HORIZONTAL_ALIGNMENT_CENTER)
	reason_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cancel_button = _button(content, "取消", Rect2(70, 581, 280, 65), Color("dfdcd6"))
	cancel_button.pressed.connect(func(): canceled.emit(); queue_free())
	confirm_button = _button(content, "招募", Rect2(495, 581, 280, 65), Color("ffda7b"))
	confirm_button.disabled = not bool(quote.can_recruit)
	confirm_button.pressed.connect(_confirm)

func _confirm() -> void:
	if _submitted: return
	var current := systems.character_recruit_status(character_id)
	if not bool(current.can_recruit) or current.price != quote.price:
		refresh()
		if bool(current.can_recruit): reason_label.text = "招募条件已变化，请确认新的招募信息"
		return
	_submitted = true
	confirm_button.disabled = true
	confirmed.emit(character_id)
	queue_free()
