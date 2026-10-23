extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.save_store = DungeonSaveStore.new("res://reports/camp-interaction-test.json")
	root.add_child(game)
	await process_frame
	game.world.player.position = Vector3(100, 0, 100)
	await process_frame
	assert(not game.hud.primary.visible, "Far away hides interaction")
	var target: Dictionary = {}
	for item in game.world.interactions._items.values():
		if str(item.data.get("UIBtnName", "")).ends_with("SelectWeapon"): target = item
	assert(not target.is_empty())
	game.world.player.position = target.position
	await process_frame
	assert(game.hud.primary.visible and game.hud.primary.text == "选择武器")
	game._interact()
	assert(game.hud.modal_open and game.menus.current_page == "weapons")
	await process_frame
	assert(not game.hud.primary.visible)
	game.hud.close_page()
	game.world._event_refresh_at = 0
	game.world.update_event_markers(true)
	assert(not game.world._event_markers.is_empty(), "New NPC events show world markers")
	for row in game.catalog.rows("NPCFunctionData"):
		if row.get("is_onetime_option", false): game.systems.set_record("npc:finished:" + str(int(row.id)), 1)
	game.world._event_refresh_at = 0
	game.world.update_event_markers(true)
	for item in game.world.interactions._items.values():
		if int(item.data.get("NpcId", 0)) > 0 and game.world._event_markers.has(item.id):
			assert(not game.world._event_markers[item.id].visible, "Completed events clear markers")
	print("Camp interaction checks passed")
	game.queue_free()
	await process_frame
	quit()
