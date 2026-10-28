extends SceneTree

const RichSource = preload("res://scripts/presentation/source_rich_text.gd")
const RoomChoices = preload("res://scripts/domain/room_choices.gd")
const AbilityDescriptions = preload("res://scripts/domain/ability_descriptions.gd")

var game: Node
var canvas: SubViewport
var checks := 0
var failures: Array[String] = []
var observations: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func _run() -> void:
	create_timer(150).timeout.connect(func(): quit(2))
	DungeonLocale.set_locale("zh_CN", false)
	canvas = SubViewport.new()
	canvas.size = Vector2i(1600, 900)
	root.add_child(canvas)
	await _fixture()
	if not is_instance_valid(game.world.player):
		await _finish()
		return
	_seed_loot([20119, 20405, 20432, 20584, 22012])
	_message_bridge()
	_kill_bridge()
	_destroyable_bridge()
	_partner_bridge()
	_automatic_pickup_bridge()
	await _description_bridges()
	await _finish()

func _fixture() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	game.save_store = DungeonSaveStore.new("/private/tmp/city-backpack-main-bridge-%d.json" % Time.get_ticks_usec())
	canvas.add_child(game)
	game.set_process(false)
	game.world.set_physics_process(false)
	game.world.presentation.audio_enabled = false
	game.world.auto_attack_enabled = false
	game.audio.stop()
	var rooms: Array = game.campaign.database.Nodes.filter(func(row): return str(row.Flow) == "Battle" and str(row.SceneName) == "LevelMap_1010101")
	check(not rooms.is_empty(), "Actual APK battle-room fixture exists")
	if rooms.is_empty(): return
	game.profile.data.buildings["4"] = 3
	game.profile.data.partners["12003"] = 1
	game.profile.data.partners["13001"] = 1
	check(game.systems.begin_run(20261028, game.selected_character, 100, 0).success, "Actual main systems start the fixture adventure")
	check(game.campaign.start_practice(int(rooms[0].Id), 20261028).success, "Actual source battle room starts")
	game._load_room()
	game.world.set_process(true)
	var deadline := Time.get_ticks_msec() + 60000
	while game._transitioning and Time.get_ticks_msec() < deadline: await process_frame
	check(not game._transitioning and is_instance_valid(game.world.player), "Actual main/world player finishes room loading")
	game.world.set_process(false)
	game.world.set_physics_process(false)
	for actor in game.world.actors:
		if is_instance_valid(actor):
			actor.set_process(false)
			actor.set_physics_process(false)
	game.world.paused = false
	game.world._background = false
	game.world.boss_show_active = false
	game.hud.close_page()
	observations["room_id"] = int(rooms[0].Id)

func _seed_loot(ids: Array) -> void:
	game._sync_live_combat()
	for id in ids: game.profile.data.run.inventory[str(id)] = 1
	game._apply_growth()

func _unsaved_damage() -> Dictionary:
	var combat: DungeonCombat = game.world.player.combat
	combat.health = minf(37.25, combat.max_health * 0.37)
	combat.armor = 7.5
	game.profile.data.run.health = combat.max_health
	game.profile.data.run.max_health = combat.max_health - 1.0
	game.profile.data.run.armor = 99.0
	return {"health": combat.health, "armor": combat.armor}

func _preserved(state: Dictionary, bridge: String) -> void:
	var combat: DungeonCombat = game.world.player.combat
	check(is_equal_approx(combat.health, state.health) and is_equal_approx(combat.armor, state.armor), bridge + " preserves unsaved live HP and armor")
	check(is_equal_approx(float(game.profile.data.run.health), combat.health) and is_equal_approx(float(game.profile.data.run.armor), combat.armor), bridge + " synchronizes current HP and armor into the run")

func _message_bridge() -> void:
	game.hud.toast("bridge-message-sentinel")
	var health := _unsaved_damage()
	for index in 49: game.world.world_message.emit("MonsterTrigger_20581", {})
	check(int(game.profile.data.run.counters.get("FreePurchaseAttempts", 0)) == 0, "Actual main message bridge waits for the fiftieth hunter trigger")
	game.world.world_message.emit("MonsterTrigger_20581", {})
	check(int(game.profile.data.run.counters.get("FreePurchaseAttempts", 0)) == 1 and int(game.profile.data.run.counters.get("effect:20584:0:used", 0)) == 1, "Fifty real world_message emissions produce one free purchase and one execution")
	check(game.hud.message_label.text == "bridge-message-sentinel", "Handled ability messages do not leak internal names into the HUD toast")
	_preserved(health, "Main message bridge")
	game.world.world_message.emit("bridge-unhandled-message", {})
	check(game.hud.message_label.text == "bridge-unhandled-message", "Unrelated unhandled messages retain their existing toast route")
	observations["hunter_messages"] = 50
	observations["free_purchases"] = int(game.profile.data.run.counters.get("FreePurchaseAttempts", 0))

func _kill_bridge() -> void:
	var enemy_id := 0
	for row in game.catalog.rows("EnemyData"):
		if str(row.get("enemy_rate", "")) == "Normal": enemy_id = DungeonCatalog.row_id(row); break
	check(enemy_id > 0, "Kill fixture selects an actual normal enemy definition")
	var combat: DungeonCombat = game.world.player.combat
	var before := combat.attribute("HpAddRate")
	var before_max := combat.max_health
	var health := _unsaved_damage()
	for index in 24: game.world.enemy_defeated.emit(enemy_id)
	check(is_equal_approx(combat.attribute("HpAddRate"), before), "Main kill adapter does not apply a partial forest-bow threshold")
	game.world.enemy_defeated.emit(enemy_id)
	check(is_equal_approx(combat.attribute("HpAddRate"), before + 50) and combat.buff_layers("50201190") == 1, "Twenty-fifth actual enemy signal immediately binds the authored forest-bow effect")
	check(combat.max_health > before_max, "Kill-triggered max-health growth reaches the live combat object immediately")
	_preserved(health, "Kill growth bridge")
	observations["kill_enemy_id"] = enemy_id
	observations["forest_bow_layers"] = combat.buff_layers("50201190")

func _destroyable_bridge() -> void:
	var combat: DungeonCombat = game.world.player.combat
	var before_attack := combat.attribute("AtkAddRate")
	var before_speed := combat.attribute("MoveSpeedRate")
	var health := _unsaved_damage()
	var wrong := {"destroyable_reward": true, "marker_id": "bridge-other-object", "config_id": "10004", "position": Vector3(10000, 0, 10000)}
	game.world.environment_action.emit("reward", wrong)
	check(int(game.profile.data.run.counters.get("effect:20405:1:record", 0)) == 0, "Main destroyable adapter passes the actual config and excludes non-pottery objects")
	for index in 20:
		game.world.environment_action.emit("reward", {"destroyable_reward": true, "marker_id": "bridge-pottery-%d" % index, "config_id": "10003", "position": Vector3(10000, 0, 10000)})
	check(int(game.profile.data.run.counters.get("effect:20405:1:record", 0)) == 20 and combat.buff_layers("50204051") == 1, "Twenty actual pottery reward signals reach one source effect layer")
	check(is_equal_approx(combat.attribute("AtkAddRate"), before_attack + 10) and is_equal_approx(combat.attribute("MoveSpeedRate"), before_speed + 10), "Pottery attack and movement bonuses update in live combat during the same handler")
	game.world.environment_action.emit("reward", {"destroyable_reward": true, "marker_id": "bridge-pottery-19", "config_id": "10003"})
	check(int(game.profile.data.run.counters.get("effect:20405:1:record", 0)) == 20, "A repeated source marker does not count twice")
	_preserved(health, "Destroyable growth bridge")
	observations["pottery_layers"] = combat.buff_layers("50204051")

func _partner_bridge() -> void:
	game.hud.close_page()
	game._sync_live_combat()
	var choices := RoomChoices.new(game.systems)
	var state: Dictionary = choices.open_partner("bridge-partner-choice")
	check(state.get("success", false), "Real unlocked partner definitions produce an actual choice set")
	if not state.get("success", false): return
	var selected := -1
	for index in state.options.size():
		if state.options[index].mode == "new": selected = index; break
	check(selected >= 0 and choices.choose_partner("bridge-partner-choice", selected).success, "Fixture equips a real partner through the production choice transaction")
	game.world.advance_partner_skills(60.0)
	game.profile.data.run.counters["MonsterPartnerSp"] = 75.0
	game.world.paused = false
	game.world._background = false
	var combat: DungeonCombat = game.world.player.combat
	var before := combat.attribute("MonsterPartnerDamageRate")
	var health := _unsaved_damage()
	var pressed: Dictionary = game.world.use_skill(5, true)
	check(pressed.get("success", false), "Actual world partner skill accepts a ready pressed input")
	check(int(game.profile.data.run.counters.get("effect:20432:0:record", 0)) == 1 and combat.buff_layers("50204320") == 1, "A successful partner press immediately records and binds its source relic trigger")
	check(is_equal_approx(combat.attribute("MonsterPartnerDamageRate"), before + 100), "Partner damage growth reaches live combat in the successful request")
	check(game.world.use_skill(5, false).get("success", false), "Partner release retains the production successful release contract")
	check(int(game.profile.data.run.counters.get("effect:20432:0:record", 0)) == 1, "Partner release does not duplicate its pressed trigger")
	check(not game.world.use_skill(5, true).get("success", false) and int(game.profile.data.run.counters.get("effect:20432:0:record", 0)) == 1, "Rejected cooldown input does not emit another partner trigger")
	_preserved(health, "Partner skill bridge")
	observations["partner_id"] = int(pressed.get("id", 0))

func _automatic_pickup_bridge() -> void:
	game.hud.close_page()
	game.world.ground_loot.clear()
	game.world.paused = false
	game.world._background = false
	game.world.fighting = false
	game.world.room_stage = "open"
	var combat: DungeonCombat = game.world.player.combat
	var before: int = game.systems.material(102)
	var health := _unsaved_damage()
	game.world.ground_loot.spawn(102, game.world.player.position, 125, true, false)
	for step in 90:
		game.world._physics_process(0.05)
		if game.systems.material(102) >= before + 125: break
	check(game.systems.material(102) == before + 125, "Actual world collection ticks grant the source essence pickup")
	var rule: Dictionary = game.catalog.find("AbilityItems", 22012).CombineDataList[1].Data
	var buff_id: String = str(DungeonCatalog.ids(rule.ModifyBuff)[0])
	check(int(game.profile.data.run.counters.get("effect:22012:1:layers", 0)) >= 2 and combat.buff_layers(buff_id) == int(game.profile.data.run.counters.get("effect:22012:1:layers", 0)), "Auto-loot callback binds the actual gained-resource relic layers immediately")
	_preserved(health, "Automatic pickup bridge")
	observations["pickup_essence"] = 125
	observations["pickup_buff_id"] = buff_id

func _description_bridges() -> void:
	game.world.set_physics_process(false)
	_seed_loot([20193, 20406, 20407, 20426])
	game.profile.data.run.counters["purify:20406:0"] = 2501
	var ids: Array = [20119, 20406, 20584, 20426]
	game.profile.data.run.rewards = [{"key": "bridge-reward", "choices": ids.duplicate(), "locked_ids": []}]
	game._rewards("bridge-reward")
	await process_frame
	_assert_choice_descriptions(ids, "Actual reward")
	var choices := RoomChoices.new(game.systems)
	choices._records()["bridge-sacrifice"] = {"kind": "sacrifice", "options": ids.map(func(id): return {"id": id, "hp_cost": 30, "locked": false}), "taken": 0, "closed": false, "selected": [], "first_node": false}
	game._show_sacrifice("bridge-sacrifice")
	await process_frame
	_assert_choice_descriptions(ids, "Actual sacrifice")
	game.profile.data.run.shops.append({"key": "npc-support:1000", "offers": [{"loot_id": 20407, "price": 0, "sold": false}], "refreshes": 0})
	game._show_npc_support(101001)
	await process_frame
	_assert_choice_descriptions([20407], "Actual NPC support")
	var shop: Dictionary = game.systems.get_room_shop(game._room_key, 1)
	shop.offers = ids.map(func(id): return {"loot_id": id, "price": 50, "sold": false})
	game._show_room_shop({"region": 1})
	await process_frame
	check(game.hud.page._rows.size() == ids.size(), "Actual shop producer supplies all selected source offers")
	for row in game.hud.page._rows:
		_assert_source(str(row.get("source_description", "")), "Actual shop offer " + str(row.loot_id), int(row.loot_id))
		game.hud.page.room_shop_view._show_item(row)
		var rich := game.hud.page.room_shop_view.modal.find_child("SourceDescription", true, false) as SourceRichText
		check(rich != null and rich.source_text == row.source_description, "Shop producer source reaches the actual inspect modal for " + str(row.loot_id))
	var seal_rows: Array = game.hud.page.page_context.get("seal_rows", [])
	for id in [20119, 20193, 20406, 20426, 20584]:
		check(seal_rows.any(func(row): return int(row.loot_id) == id), "Actual shop seal producer includes expected owned item " + str(id))
	for row in seal_rows:
		_assert_source(str(row.get("source_description", "")), "Actual shop seal " + str(row.loot_id), int(row.loot_id))
		game.hud.page.room_shop_view._show_item(row)
		var rich := game.hud.page.room_shop_view.modal.find_child("SourceDescription", true, false) as SourceRichText
		check(rich != null and rich.source_text == row.source_description, "Seal producer source reaches the actual inspect modal for " + str(row.loot_id))
	observations["description_routes"] = ["reward", "sacrifice", "npc_support", "room_shop_offer", "room_shop_seal"]
	observations["seal_ids"] = seal_rows.map(func(row): return int(row.loot_id))

func _assert_choice_descriptions(ids: Array, title: String) -> void:
	var sources: Array = game.hud.page._rows.filter(func(row): return row.has("source_description"))
	check(sources.size() == ids.size(), title + " supplies the expected source description rows")
	var rich_nodes: Array = game.hud.page.find_children("*", "RichTextLabel", true, false).filter(func(node): return node is SourceRichText)
	for index in sources.size():
		var source: String = str(sources[index].source_description)
		_assert_source(source, title + " " + str(ids[index]), int(ids[index]))
		check(rich_nodes.any(func(node): return node.source_text == source and not node.text.contains("backpack_")), title + " source reaches an actual rich-text control for " + str(ids[index]))

func _assert_source(source: String, title: String, loot_id: int) -> void:
	var ability_id := int(game.catalog.find("LootData", loot_id).get("ability_item_id", loot_id))
	var expected: String = AbilityDescriptions.new(game.systems).source(ability_id, loot_id, game.world.player.combat)
	check(source == expected, title + " supplies the resolved description of the expected item and live state")
	check(not source.is_empty() and not source.contains("<#backpack_") and not source.contains("【backpack_"), title + " resolves dynamic placeholders")
	var rendered: String = RichSource.source_to_bbcode(source)
	check(not rendered.contains("<#") and rendered.contains("[color="), title + " preserves source styling without raw TMP markup")
	var expected_rendered: String = RichSource.source_to_bbcode(expected)
	check(rendered.count("[img=") == expected_rendered.count("[img="), title + " retains the actual source icon count, including text-only terms")
	match loot_id:
		20119: check(source.contains("（当前1层）"), title + " reports the real forest-bow layer")
		20193: check(source.contains("<#specinfo=keyinshengdian>") and not rendered.contains("[img="), title + " preserves the source text-only shrine term")
		20406: check(source.contains("（当前进度：2501/10000）"), title + " reports the injected unfinished upgrade progress")
		20407: check(source.contains("（当前%d层）" % int(game.systems.material(102) / 500)), title + " reports the actual held-essence factor")
		20426: check(source.contains("（当前%d层）" % game.world.player.combat.buff_layers("50204261")), title + " reports the current combat buff layer")
		20584: check(source.contains("（已触发1/10次）"), title + " reports the real hunter execution count")

func _finish() -> void:
	var report := {"passed": failures.is_empty(), "checks": checks, "failures": failures, "observations": observations,
		"scope": "Headless Godot reconstruction integration through the actual main scene, world signals, partner skill request, ground collection tick, and HUD producers. Inventory and choice records are seeded deterministic fixtures; enemy death and object-destruction signals are injected without combat/collision simulation. Original APK runtime and GPU appearance are not exercised."}
	FileAccess.open("res://reports/backpack-main-bridge-20261028.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("BACKPACK_MAIN_BRIDGE ", JSON.stringify(report))
	if is_instance_valid(game): game.queue_free()
	canvas.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
