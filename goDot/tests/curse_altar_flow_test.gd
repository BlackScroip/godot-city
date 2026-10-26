extends SceneTree

var game: Node
var checks := 0
var failures: Array[String] = []
var save_path := ""

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr(message)

func _initialize() -> void:
	_run.call_deferred()

func _new_game() -> Node:
	var instance = load("res://scenes/main.tscn").instantiate()
	instance.save_store = DungeonSaveStore.new(save_path)
	root.add_child(instance)
	instance.set_process(false)
	instance.world.set_process(false)
	instance.world.set_physics_process(false)
	instance.world.presentation.audio_enabled = false
	instance.world.auto_attack_enabled = false
	instance.audio.stop()
	return instance

func _wait_loading() -> void:
	game.world.set_physics_process(false)
	game.world.set_process(true)
	var deadline := Time.get_ticks_msec() + 60000
	while game._transitioning and Time.get_ticks_msec() < deadline: await process_frame
	check(not game._transitioning, "Authored entrance finishes loading")
	game.set_process(false)
	game.world.set_process(false)
	game.world.set_physics_process(false)
	game.world.paused = false
	game.hud.close_page()

func _altar() -> Dictionary:
	for item in game.world.interactions._items.values():
		if DungeonWorldInteractions._is_curse_altar(item): return item
	return {}

func _reward(key: String) -> Dictionary:
	for reward in game.profile.data.run.rewards:
		if str(reward.key) == key: return reward
	return {}

func _parts_hidden(item: Dictionary) -> bool:
	return not item.get("curse_parts", []).is_empty() and item.curse_parts.all(func(part): return not part.node.visible)

func _resume() -> void:
	game.queue_free()
	await process_frame
	game = _new_game()
	await _wait_loading()

func _run() -> void:
	create_timer(100).timeout.connect(func(): quit(2))
	save_path = "/private/tmp/city-curse-altar-flow-%d.json" % Time.get_ticks_usec()
	game = _new_game()
	await process_frame
	game.systems.set_record("difficulty:win:5", 1)
	check(game.systems.begin_run(61793, game.selected_character, 1000, 6).success, "Difficulty six run starts")
	check(game.campaign.generate(61793, 6).success, "World map generates")
	var regions: Array = game.campaign.region_choices().filter(func(row): return int(row.region) == 1)
	check(not regions.is_empty() and game.campaign.select_region(int(regions[0].node_id)).success, "World map enters the first authored region")
	if regions.is_empty() or game.campaign.choices().is_empty():
		_finish()
		return
	var entrance: Dictionary = game.campaign.choices()[0]
	check(game.campaign.enter(int(entrance.node_id)).success, "Authored entrance node can be entered")
	game._load_room()
	await _wait_loading()
	var altar = _altar()
	check(not altar.is_empty(), "Actual entrance contains imported curse altar")
	if altar.is_empty():
		_finish()
		return
	var marker = str(altar.id)
	var key = "curse_altar:" + game._room_key + ":" + marker
	check(game.campaign.current_room().flow == "Entrance" and game.campaign.state.phase == "room", "Fixture is an unfinished entrance room")
	check(altar.state.enabled and altar.visual.is_visible_in_tree(), "Difficulty attribute activates the actual curse altar")
	check(altar.curse_parts.size() == 3, "Imported curse altar resolves native BillBoard, Effect and Trigger sections")
	check(not game.world.interactions.diagnostics.any(func(row): return row.marker_id == marker and row.code == "missing_message_binding"), "Curse altar has a recognized interaction binding")
	var before_inventory: Dictionary = game.profile.data.run.inventory.duplicate(true)
	check(game.world.interactions.interact(marker).success, "World interaction routes marker context through main to curse selection")
	var reward = _reward(key)
	check(not reward.is_empty(), "Activation queues a persistent reward identified by room and source marker")
	if reward.is_empty():
		_finish()
		return
	var choices: Array = reward.choices.duplicate()
	check(choices.size() == 3 and int(reward.pool_id) == int(game.catalog.config.AbilityItemLootPoolId_Curse), "Existing Curse selection path supplies three source pool choices")
	check(choices.all(func(id): return game.catalog.find("LootData", id).get("loot_type", "") == "诅咒遗物"), "All source candidates are curse relics")
	check(game.hud.modal_open and game.profile.data.run.inventory == before_inventory, "Activation opens selection without auto granting a relic")
	check(int(game.profile.data.run.counters.get("SelectLootRemainCount_Curse", 0)) == 1 and game.profile.data.run.counters.get(key, false), "Native pending count and per instance consumed record are stored")
	check(altar.state.used and _parts_hidden(altar) and altar.visual.is_visible_in_tree(), "Consumption hides only native interaction sections and retains altar platform")
	check(game.campaign.state.phase == "room" and not game.campaign.state.action_resolved, "Altar activation does not complete the entrance")
	game.hud.close_page()
	var random_step := int(game.profile.data.run.random_step)
	check(not game.world.interactions.interact(marker).success, "Consumed marker rejects repeat interaction")
	game._request_curse_altar({"marker_id": marker})
	check(game.profile.data.run.rewards.size() == 1 and int(game.profile.data.run.random_step) == random_step, "Repeated message cannot duplicate or reroll pending choices")
	check(game._save(true), "Pending altar choice and marker state save")
	await _resume()
	altar = _altar()
	check(_reward(key).get("choices", []) == choices and int(game.profile.data.run.counters.get("SelectLootRemainCount_Curse", 0)) == 1, "Full game restore retains exact pending curse choices and count")
	check(altar.state.used and _parts_hidden(altar) and not game.world.interactions.interact(marker).success, "Full game restore keeps altar consumed")
	check(game.campaign.state.phase == "room", "Restoring pending altar keeps entrance unfinished")
	game._load_room(false)
	await _wait_loading()
	altar = _altar()
	check(altar.state.used and _parts_hidden(altar), "Reentering without a battle snapshot reapplies per instance consumption")
	check(_reward(key).get("choices", []) == choices and not game.world.interactions.interact(marker).success, "Reentry preserves choices and cannot replenish the altar")
	game._rewards(key)
	check(game.hud.modal_open, "Pending reward remains reopenable from reward UI")
	var selected := int(choices[0])
	var ability: Dictionary = game.catalog.find("AbilityItems", int(game.catalog.find("LootData", selected).ability_item_id))
	var cap := maxi(1, int(ability.get("MaxHaveCount", 1)))
	game.profile.data.run.inventory[str(selected)] = cap
	game._action("choose_loot", selected, key)
	check(not _reward(key).is_empty() and int(game.profile.data.run.counters.get("SelectLootRemainCount_Curse", 0)) == 1, "Failed capped grant retains pending reward and count")
	game.profile.data.run.inventory.erase(str(selected))
	game._action("choose_loot", selected, key)
	check(_reward(key).is_empty() and int(game.profile.data.run.inventory.get(str(selected), 0)) == 1, "Choosing one curse grants it exactly once")
	check(int(game.profile.data.run.counters.get("SelectLootRemainCount_Curse", 0)) == 0 and not game.hud.modal_open, "Successful selection consumes one pending count and closes reward page")
	check(game.campaign.state.phase == "room" and not game.campaign.state.action_resolved, "Choosing curse does not resolve the entrance or advance maps")
	game._action("choose_loot", selected, key)
	check(int(game.profile.data.run.inventory.get(str(selected), 0)) == 1 and _reward(key).is_empty(), "Repeated choice cannot overgrant or recreate the reward")
	check(game._save(true), "Claimed altar state saves")
	await _resume()
	altar = _altar()
	check(altar.state.used and _parts_hidden(altar) and _reward(key).is_empty(), "Claimed altar remains consumed after full restore")
	check(int(game.profile.data.run.inventory.get(str(selected), 0)) == 1 and int(game.profile.data.run.counters.get("SelectLootRemainCount_Curse", 0)) == 0, "Claimed inventory and zero pending count survive restore")
	check(not game.world.interactions.interact(marker).success and game.campaign.state.phase == "room", "Restored altar cannot restart selection or auto complete entrance")
	var reward_count: int = game.profile.data.run.rewards.size()
	game._request_curse_altar({"marker_id": "missing"})
	check(game.profile.data.run.rewards.size() == reward_count, "Missing source marker cannot grant a curse opportunity")
	_finish()

func _finish() -> void:
	print("CURSE_ALTAR_FLOW_TEST ", JSON.stringify({"checks": checks, "passed": failures.is_empty(), "failures": failures}))
	if is_instance_valid(game): game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
