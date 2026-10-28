extends "res://tests/room_activity_flow_test.gd"

func _wait() -> void:
	# Offscreen scene fixtures must not pause their loading animation when another app gains focus.
	var foreground := func(): game.world._background = false
	process_frame.connect(foreground)
	await super._wait()
	process_frame.disconnect(foreground)

func _run() -> void:
	create_timer(240).timeout.connect(func(): quit(2))
	canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	await _test_gem_offering()
	await _test_event_outcome()
	await _test_special_event()
	await _test_spring_restore()
	var report := {"checks": checks, "failures": failures, "passed": failures.is_empty(), "captures": captures}
	var file := FileAccess.open("res://reports/adventure-complete-flow-20261028.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t") + "\n")
	print("ADVENTURE_COMPLETE_FLOW ", JSON.stringify(report))
	canvas.free()
	quit(0 if failures.is_empty() else 1)

func _gem_marker() -> Dictionary:
	for item in game.world.interactions._items.values():
		if str(item.marker.get("Type", "")) == "EEUT_Special_GemShopMan": return item
	return {}

func _test_gem_offering() -> void:
	await _fixture("Shop", "LevelMap_1010201")
	var marker := _gem_marker()
	check(not marker.is_empty() and marker.data.is_empty(), "Actual APK gem merchant has the empty NPC payload")
	if marker.is_empty(): return
	var marker_id := str(marker.id)
	var key: String = game._room_key + ":" + marker_id
	game.systems.grant_material(102, 1000)
	var rng_before: int = game.profile.data.run.random_step
	var magic_before: int = game.systems.material(102)
	check(game.world.interactions.interact(marker_id).success, "Empty-payload merchant resolves native NPC 2100")
	check(game.hud.modal_open and game.hud.page.adventure_event_view._context.get("gem_offering", false), "Merchant opens the actual offering page")
	check(game.profile.data.run.random_step == rng_before, "Opening the merchant leaves reward RNG untouched")
	var status: Dictionary = game.systems.gem_offering_status(key)
	var view = game.hud.page.adventure_event_view
	check(not view.choice_buttons[0].disabled, "Funded offering is selectable")
	for frame in 6: await process_frame
	check(not view.title_label.get_global_rect().intersects(view.story_scroll.get_global_rect()), "Actual offering title clears its story")
	await _capture("gem-offering")
	var inventory: Dictionary = game.profile.data.run.inventory.duplicate(true)
	var drop_count: int = game.world.ground_loot.entries.size()
	view.choice_buttons[0].pressed.emit()
	check(not game.hud.modal_open and game.systems.material(102) == magic_before - int(status.price), "Offering button deducts the shown price and returns to the room")
	check(game.world.ground_loot.entries.size() == drop_count + 1, "Offering spawns its actual gem in the world")
	check(game.profile.data.run.inventory == inventory, "Offering does not grant the ground gem before pickup")
	game._action("gem_offering_buy", status.key, {"marker_id": marker_id})
	check(game.systems.material(102) == magic_before - int(status.price) and game.world.ground_loot.entries.size() == drop_count + 1, "Repeated offering command cannot charge or spawn twice")
	game.hud.close_page()
	check(game._save(true), "Offering and unclaimed gem save together")
	game._load_room(true)
	await _wait()
	check(game.systems.gem_offering_status(key).used and game.world.ground_loot.entries.size() == drop_count + 1, "Saved merchant and unclaimed gem restore together")
	game.world.interactions.interact(marker_id)
	check(game.hud.page.adventure_event_view.choice_buttons[0].disabled, "Used merchant remains visibly unavailable after reload")
	game.hud.close_page()
	if game.world.ground_loot.entries.size() > drop_count:
		var drop: Dictionary = game.world.ground_loot.entries.back()
		check(game.catalog.find("LootData", int(drop.id)).loot_type in ["攻击宝石", "防御宝石", "生命宝石"], "Source pool returns a supported gem type")
		game.world.player.position = drop.position
		game._interact()
		check(game.world.ground_loot.entries.size() == drop_count, "Normal room pickup acquires and removes the offered gem")
	game._save(true)
	game._load_room(true)
	await _wait()
	check(game.world.ground_loot.entries.size() == drop_count, "Collected gem never respawns on reload")
	await _fixture("Shop", "LevelMap_1010201")
	marker = _gem_marker()
	if marker.is_empty(): return
	marker_id = str(marker.id)
	key = game._room_key + ":" + marker_id
	game.profile.data.materials["102"] = 0
	game.world.interactions.interact(marker_id)
	check(game.hud.page.adventure_event_view.choice_buttons[0].disabled, "Insufficient magic disables actual offering option")
	status = game.systems.gem_offering_status(key)
	game._action("gem_offering_buy", status.key, {"marker_id": marker_id})
	check(not game.systems.gem_offering_status(key).used and game.world.ground_loot.entries.is_empty(), "Rejected offering consumes neither merchant nor reward")
	game.profile.data.run.counters["GemShopFreeCostCount"] = 1
	game._show_gem_offering({"marker_id": marker_id})
	view = game.hud.page.adventure_event_view
	check(not view.choice_buttons[0].disabled and view.choice_buttons[0].get_node("ChoiceText").get_parsed_text() == "免费供奉", "Free-use allowance is reflected in the real option")
	view.choice_buttons[0].pressed.emit()
	check(game.systems.material(102) == 0 and int(game.profile.data.run.counters.GemShopFreeCostCount) == 0 and game.world.ground_loot.entries.size() == 1, "Free offering consumes one allowance and spawns one gem")

func _test_event_outcome() -> void:
	await _fixture("Battle", "LevelMap_1010101")
	var marker := _item(DungeonWorldInteractions.ADVENTURE_EVENT)
	check(not marker.is_empty(), "Actual combat room includes an event altar")
	if marker.is_empty(): return
	game.systems.grant_material(102, 1000)
	game.world.interactions.interact(str(marker.id))
	var encounter: Dictionary = game.profile.data.run.events[0]
	encounter.event_id = 3
	game._show_adventure_event({"marker_id": str(marker.id)}, str(encounter.key))
	var room_stage: String = game.world.room_stage
	var magic_before: int = game.systems.material(102)
	game._action("event_choice", 31, {"key": encounter.key, "marker_id": str(marker.id)})
	for frame in 3: await process_frame
	check(encounter.finished and not encounter.get("acknowledged", false), "Choosing a source option persists a pending outcome")
	check(game.systems.material(102) == magic_before - 200, "Real event option pays its authored cost exactly once")
	check(game.hud.page.adventure_event_view._context.finished and not marker.state.used, "Outcome is shown before consuming the event altar")
	var source: Dictionary = game.catalog.find("AdvantureEventData", 3).TypeData.OptionList[0]
	check(game.hud.page.adventure_event_view.story.source_text == source.OptionSelectFinishText, "Outcome displays the authored rich result story")
	check(game.hud.page.adventure_event_view.choice_buttons[0].get_node("ChoiceText").source_text == source.ResponseText, "Outcome uses the authored colored acknowledgement")
	check(not game.systems.pending_character_talent_reward().is_empty(), "Event actually awards its talent scroll")
	var reward: Dictionary = game.systems.pending_character_talent_reward().duplicate(true)
	game._save(true)
	game._load_room(true)
	await _wait()
	marker = _item(DungeonWorldInteractions.ADVENTURE_EVENT)
	check(game._pending_room_activity().get("kind", "") == "event", "Unconfirmed event restores a usable continuation")
	game._interact()
	check(game.hud.modal_open and game.hud.page.adventure_event_view._context.finished, "Normal interaction reopens the saved result")
	check(game.systems.pending_character_talent_reward() == reward, "Reopening result neither rerolls nor grants a second talent")
	game.systems.add_loot(14102)
	check(not game.profile.data.run.rewards.is_empty(), "Relic reward fixture is queued behind the event talent")
	game._action("event_continue", 0, {"key": encounter.key, "marker_id": str(marker.id)})
	check(marker.state.used and game.campaign.state.phase == "room" and game.world.room_stage == room_stage, "Optional event confirmation preserves combat progression and gates")
	check(game.hud.modal_open and game.hud.page._layout == "talent", "Outcome confirmation opens the pending talent selection")
	if not reward.is_empty(): game._action("choose_talent", int(reward.choices[0]), str(reward.key))
	check(game.systems.pending_character_talent_reward().is_empty() and game.hud.modal_open, "Talent selection continues to queued relic rewards")
	game.hud.close_page()
	var reward_count: int = game.profile.data.run.rewards.size()
	game._action("event_continue", 0, {"key": encounter.key, "marker_id": str(marker.id)})
	check(not game.hud.modal_open and game.profile.data.run.rewards.size() == reward_count, "Repeated outcome confirmation does not reopen or regrant rewards")
	encounter.erase("acknowledged")
	encounter.erase("result_story")
	check(game._pending_room_activity().is_empty(), "Legacy completed event with a consumed marker creates no stale continuation")

func _test_special_event() -> void:
	await _fixture("Event", "LevelMap_1010801")
	var marker := _item(DungeonWorldInteractions.SPECIAL_EVENT)
	check(not marker.is_empty(), "Special room includes its source event altar")
	if marker.is_empty(): return
	game.world.interactions.interact(str(marker.id))
	var encounter: Dictionary = game.profile.data.run.events[0]
	encounter.event_id = 4
	game._show_adventure_event({"marker_id": str(marker.id)}, str(encounter.key))
	var before: int = game.systems.material(102)
	game._action("event_choice", 42, {"key": encounter.key, "marker_id": str(marker.id)})
	check(game.systems.material(102) == before + 100 and game.campaign.state.phase == "room", "Special event grants authored resource reward while awaiting confirmation")
	game._action("event_continue", 0, {"key": encounter.key, "marker_id": str(marker.id)})
	check(marker.state.used and game.campaign.state.phase == "reward" and game.world.room_stage == "open", "Confirmed special event opens the room exit")
	game._action("event_choice", 42, {"key": encounter.key, "marker_id": str(marker.id)})
	check(game.systems.material(102) == before + 100, "Resolved special option cannot grant duplicate resources")

func _test_spring_restore() -> void:
	await _fixture("Rest", "LevelMap_1010301")
	var spring := _item(DungeonWorldInteractions.SPRING)
	check(not spring.is_empty(), "Actual rest room contains the source spring")
	if spring.is_empty(): return
	game.profile.data.run.counters["rest:" + game._room_key] = true
	game._restore_room_actions()
	check(spring.state.used and not game.world.interactions.interact(str(spring.id)).success, "Legacy spring counters restore a consumed interaction")
	game._save(true)
	game._load_room(true)
	await _wait()
	spring = _item(DungeonWorldInteractions.SPRING)
	check(spring.state.used and spring.visual.visible, "Consumed legacy spring stays visible and unavailable after reload")
