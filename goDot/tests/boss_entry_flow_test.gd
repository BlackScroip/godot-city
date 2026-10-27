extends SceneTree

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _wait_loading(game: Node) -> void:
	var deadline := Time.get_ticks_msec() + 30000
	while game._transitioning and Time.get_ticks_msec() < deadline: await process_frame
	check(not game._transitioning, "Boss room preparation completes")
	game.world.set_physics_process(false)
	game.world.set_process(false)

func _run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	game.save_store = DungeonSaveStore.new("/private/tmp/city-boss-entry-%d.json" % Time.get_ticks_usec())
	root.add_child(game)
	game.set_process(false)
	game.systems.begin_run(42, 1, 100, 0)
	game.campaign.start_practice(1019101, 42)
	game._load_room()
	await _wait_loading(game)
	for item in game.world.interactions._items.values():
		if item.marker.Type == "EEUT_PlayerTrigger" and int(item.data.get("TriggerId", -1)) == 1:
			var collider: Dictionary = item.colliders[0]
			var point: Vector3 = game.world.interactions._matrix(collider.world_matrix) * game.world.interactions._vector(collider.properties.get("m_Center", {}))
			game.world.player.position = game.world.interactions._world_position(point) - Vector3.UP * 0.8
			game.world.interactions.tick(0.02, game.world.player.position)
			break
	game._update_battle_presentation(0)
	check(game.boss_intro.active and game.world.boss_show_active and not game.world.paused, "First boss encounter starts entry and locks player controls")
	game._action("page:characters", 0, 0)
	check(not game.hud.modal_open, "Entry blocks underlying menu commands")
	var key: String = game.world.actors.back().combat.actor_key
	var boss: DungeonActor = game.world.actors.back()
	check(boss.combat.current_action == "bosspose", "Encounter starts the actual authored BossAct")
	var sequence: int = boss.combat._cast_sequence
	check(game._introduced_bosses.has(key), "Entry is recorded once for this actor")
	game.boss_intro.skip.button_pressed = true
	check(game.world.simulation_scale == 3.0 and game.profile.data.get("boss_show_skip", false), "Source skip toggle accelerates the live world and updates its persistent preference")
	game._process(0.3)
	check(game.save_store.flush() and game.save_store.load_profile().get("boss_show_skip", false), "Skip preference survives profile serialization")
	game.boss_intro.skip.button_pressed = false
	game.boss_intro.finish()
	check(not game.world.paused, "Cancelling entry releases the control lock")
	boss.combat.tick(0.0)
	for event in boss.combat.drain_events(): game.world._consume(boss, event)
	check(boss.combat.buff_layers("41300103") == 1, "Skipping cinematic still executes source BossAct lock initialization")
	check(boss.combat._cast_sequence == sequence, "Skipping cinematic does not restart the gameplay action")
	game._update_battle_presentation(0)
	check(not game.boss_intro.active, "Next frame cannot replay the same boss entry")
	game.boss_intro.begin(game.world, boss, str(boss.combat.enemy.name))
	game.boss_intro._process(game.boss_intro.duration + 1.1)
	game._update_battle_presentation(0)
	check(not game.boss_intro.active and game.boss_intro.visible and not game.hud.battle_readout.boss.visible, "Temporary source HP animation owns the final banner tail without duplicate health bars")
	game.boss_intro._process(0.6)
	game._update_battle_presentation(0)
	check(game.hud.battle_readout.boss.visible, "Normal boss health display appears after the source banner ends")
	game.battle_tally.restore({"hits": 4, "damage": 72, "elapsed": 3})
	game._build_save_snapshot()
	check(game.profile.data.run.battle.tally.hits == 4, "Battle checkpoint includes hit statistics")
	game._load_room(true)
	await _wait_loading(game)
	game._update_battle_presentation(0)
	check(not game.boss_intro.active, "Restored ongoing fight does not replay entrance")
	var restored_boss: DungeonActor = game.world.actors.back()
	check(restored_boss.combat.buff_layers("41300103") == 1 and restored_boss.combat._cast_sequence == sequence, "Restored fight retains its existing BossAct and HP lock")
	check(game.battle_tally.hits == 4 and game.battle_tally.damage == 72, "Restored fight retains totals")
	game._action("page:characters", 0, 0)
	check(game.hud.modal_open and game.menus.current_page == "characters", "Character details remain usable after entry")
	game.queue_free()
	await process_frame
	print("BOSS_ENTRY_FLOW ", JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
