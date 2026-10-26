extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.save_store = DungeonSaveStore.new("/private/tmp/camp-page-integration-%d.json" % Time.get_ticks_usec())
	root.add_child(game)
	while not game.initialized: await process_frame
	game.set_process(false)
	game.world.set_physics_process(false)
	game.world._background = false
	for id in range(1, 8): game.profile.data.buildings[str(id)] = 3
	game.world.refresh_camp_progression()
	game.profile.data.character_levels["2"] = 1
	game.systems.set_record("weapon:201", 1)
	game.systems.set_record("weapon:202", 1)
	game.menus.open("characters", 2)
	game._action("select_character", 2, 0)
	check(game.selected_character == 2 and game.world.player.actor_id == 2, "Character page selection updates the actual camp actor")
	check(game.hud.modal_open and game.hud.page.character_view != null, "Selection returns to the character detail")
	check(int(game.save_store.load_profile().selected_character) == 2, "Character selection persists immediately")
	game._action("equip_weapon", 202, 0)
	check(game.selected_weapon == 202 and game.profile.data.selected_weapons.get("2") == 202, "Weapon command equips and remembers the selected character weapon")
	var restored: Dictionary = game.save_store.load_profile()
	check(int(restored.selected_weapon) == 202 and int(restored.selected_weapons.get("2", 0)) == 202, "Equipped weapon and per-character choice persist together")
	game._action("select_character", 1, 0)
	game._action("select_character", 2, 0)
	check(game.selected_weapon == 202, "Switching away and back restores the character weapon")
	game._action("equip_weapon", 101, 0)
	check(game.selected_weapon == 202, "Direct incompatible weapon command cannot change the equipped weapon")
	game.menus.open("mall")
	check(game.hud.page.shop_view != null, "Mall uses the implemented shop page")
	var mall = game.hud.page.shop_view
	mall.select_category("rainbow")
	check(not mall.visible_offer_ids.is_empty(), "Rainbow category contains actual enabled offers")
	if not mall.visible_offer_ids.is_empty():
		var offer := 20001
		check(offer in mall.visible_offer_ids, "Source crystal exchange is present in its category")
		mall.select_offer(offer)
		game.systems.grant_material(90002, 10000)
		var before: int = game.systems.material(90002)
		game._action("op:buy_mall", offer, 0)
		check(game.systems.material(90002) < before, "Shop exchange command reaches the real wallet transaction")
		check(game.hud.page.shop_view.selected_category == "rainbow" and game.hud.page.shop_view.selected_offer == offer, "Shop refresh keeps category and selected offer after exchange")
	game.hud.page.shop_view.select_category("treasure")
	game.hud.page.shop_view.selected_box_count = 50
	game.hud.page.shop_view._store_selection()
	game.menus.open("mall")
	check(game.hud.page.shop_view.selected_box_count == 50 and game.hud.page.shop_view.selected_category == "treasure", "Mall refresh preserves the selected chest batch")
	var wallet: Dictionary = game.profile.data.materials.duplicate(true)
	game._action("op:buy_mall", 30001, 0)
	check(game.profile.data.materials == wallet and game.systems.stat("purchase:30001:never") == 0, "Unverified money purchase cannot spend or grant entitlement")
	var original_combat = game.world.player.combat
	game.world.player.position = game.world.camp_training_status().position
	game.menus.open("training")
	check(game.hud.page._rows[0].buttons.any(func(entry): return entry.action == "start_training" and not entry.disabled), "Nearby unlocked training page enables start")
	game._action("start_training", 0, 0)
	game._process(0)
	check(game.world.camp_training.active and not game.profile.data.run.active, "Training command starts without creating an adventure")
	check(game.camp_training_readout.visible and game.hud.skill_cluster.visible and not game.hud.title_label.visible, "Training exposes combat controls and live statistics without adventure difficulty")
	var damage_before: float = game.battle_tally.damage
	game._record_run_impact({"source_key": "player", "resolved_damage": 123.0})
	check(game.battle_tally.damage == damage_before, "Training impacts cannot enter the campaign battle tally")
	game.camp_training_readout.reset_button.pressed.emit()
	check(game.world.camp_training.hits == 0 and game.world.camp_training.elapsed == 0, "Training reset command reaches the world session")
	game.camp_training_readout.end_button.pressed.emit()
	game._process(0)
	check(not game.world.camp_training.active and game.world.player.combat == original_combat and not game.camp_training_readout.visible, "Training end restores the original combat and hides the readout")
	check(game.profile.data.materials == wallet, "Training UI never changes permanent resources")
	game._close_page()
	game.world.paused = false
	var point := Vector3.INF
	var candidates: Array = []
	var items: Array = game.world.interactions._items.values()
	for first in items:
		for second in items:
			if first.id == second.id: continue
			var midpoint: Vector3 = (first.position + second.position) * 0.5
			midpoint.y = 0.05
			var nearby: Array = game.world.interactions.available_interactions(midpoint)
			if nearby.size() > 1:
				point = midpoint
				candidates = nearby
				break
		if not candidates.is_empty(): break
	check(candidates.size() > 1, "Authored camp contains reachable overlapping interaction volumes")
	if candidates.size() > 1:
		game.world.player.position = point
		game._interact()
		check(game.hud.page.page_context.get("page") == "nearby" and game.hud.page._rows.size() == candidates.size(), "Nearby selection exposes every overlapping facility")
		game.world.player.position = Vector3(100, 0, 100)
		game._action("camp_interact", str(candidates.back().id), 0)
		check(not game.hud.modal_open and game.hud.message_label.text == "请靠近该设施后再交互", "Stale nearby choice is range-checked again before opening")
	game.queue_free()
	await process_frame
	print("CAMP_PAGE_INTEGRATION ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
