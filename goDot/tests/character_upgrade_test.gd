extends SceneTree

var failures: Array[String] = []
var submitted: Array = []

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var catalog = DungeonCatalog.new()
	check(catalog.load_all(), "Recovered catalog loads")
	var profile = DungeonProfile.new()
	var systems = DungeonSystems.new(catalog, profile)
	profile.data.materials["501"] = 20
	var quote = systems.character_upgrade_status(1)
	check(quote.stats.map(func(stat): return [stat.current, stat.next]) == [[100, 120], [85, 102], [70, 84]], "Preview uses base stats and recovered 20 percent growth")
	check(quote.price["501"] == 1 and quote.max_level == 15, "APK cost and maximum level are respected")
	var dialog = _dialog(systems)
	check(dialog.material_labels.size() == 1 and dialog.material_labels[0].text == "20/1", "Only positive required materials are visible")
	for dimensions in [Vector2i(2048, 900), Vector2i(1600, 900), Vector2i(844, 390)]:
		root.size = dimensions
		for frame in 3: await process_frame
		var bounds = dialog.panel.get_global_rect()
		check(Rect2(Vector2.ZERO, dialog.size).encloses(bounds), "Upgrade modal fits %s" % dimensions)
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://reports/character-upgrade-%dx%d.png" % [dimensions.x, dimensions.y])
	dialog.cancel_button.pressed.emit()
	await process_frame
	check(systems.material(501) == 20 and systems.rank(profile.data.character_levels, 1) == 1, "Cancel never changes inventory or level")
	dialog = _dialog(systems)
	profile.data.materials["501"] = 0
	dialog.confirm_button.pressed.emit()
	check(submitted.is_empty() and dialog.confirm_button.disabled, "Confirmation revalidates insufficient inventory")
	check(not dialog.reason_label.text.is_empty(), "Unavailable action explains the missing resource")
	dialog.queue_free()
	await process_frame
	profile.data.materials["501"] = 20
	dialog = _dialog(systems)
	dialog.confirm_button.pressed.emit()
	dialog._confirm()
	check(submitted == [1], "Confirmation forwards one operation even on repeat input")
	check(systems.material(501) == 19 and systems.rank(profile.data.character_levels, 1) == 2, "Confirmed operation spends exact cost and advances one level")
	await process_frame
	dialog = _dialog(systems)
	profile.data.character_levels["1"] = 3
	dialog.confirm_button.pressed.emit()
	check(submitted.size() == 1 and dialog.quote.level == 3, "Changed level refreshes quote before further confirmation")
	dialog.queue_free()
	await process_frame
	profile.data.character_levels["1"] = 6
	profile.data.materials["501"] = 50
	profile.data.materials["503"] = 1
	dialog = _dialog(systems)
	check(dialog.material_labels.size() == 2, "Breakthrough previews both required materials")
	dialog.confirm_button.pressed.emit()
	check(systems.material(501) == 0 and systems.material(503) == 0 and systems.rank(profile.data.character_levels, 1) == 7, "Breakthrough consumes both costs atomically")
	await process_frame
	profile.data.character_levels["1"] = 15
	dialog = _dialog(systems)
	check(dialog.confirm_button.disabled and dialog.quote.next_level == 15 and dialog.material_labels.is_empty(), "Maximum level has no further target or costs")
	dialog.queue_free()
	await process_frame
	print("Character upgrade: ", "PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)

func _dialog(systems: DungeonSystems) -> DungeonCharacterUpgradeDialog:
	var dialog = preload("res://scripts/presentation/character_upgrade_dialog.gd").new()
	root.add_child(dialog)
	dialog.configure(systems, 1)
	dialog.confirmed.connect(func(id): submitted.append(id); systems.upgrade_character(id))
	return dialog
