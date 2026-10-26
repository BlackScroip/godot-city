extends SceneTree

var checks := 0
var failures: Array[String] = []
var events: Array = []
var canvas: SubViewport
var game: Node

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func touch(key: DungeonTouchButton, index: int, pressed: bool, inside := false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = key.get_global_transform_with_canvas() * (key.size * 0.5) if pressed or inside else Vector2.ZERO
	canvas.push_input(event, true)

func run() -> void:
	create_timer(90).timeout.connect(func(): quit(2))
	canvas = SubViewport.new()
	canvas.size = Vector2i(844, 390)
	root.add_child(canvas)
	game = load("res://scripts/main.gd").new()
	game.save_store = DungeonSaveStore.new("/private/tmp/city-skill-live-%d.json" % Time.get_ticks_usec())
	canvas.add_child(game)
	game.world.set_attack_mode("off")
	game.hud.set_attack_mode("off")
	game.hud.close_page()
	game.hud.skill.connect(func(slot, pressed): events.append([slot, pressed]))
	await create_timer(0.1).timeout
	await check_holds("camp")
	check(game.systems.begin_run(20261026, 1, 100, 0).success, "Adventure fixture starts")
	game.campaign.start_practice(1010101, 20261026)
	game._load_room()
	while game._transitioning: await process_frame
	game.hud.close_page()
	await create_timer(0.1).timeout
	await check_holds("adventure")
	var held_attack: DungeonTouchButton = game.hud.skill_buttons[0]
	var dodge: DungeonTouchButton = game.hud.skill_buttons[1]
	game.world.player.combat.energy[1] = game.world.player.combat.skill_capacity(1)
	game.world.player.combat.cooldowns[1] = 0.0
	touch(held_attack, 7, true)
	touch(dodge, 8, true)
	await create_timer(0.1).timeout
	check(game.world.player.combat._current_slot == 1, "Second finger executes an actual dodge")
	check(held_attack.finger == 7 and game.world.intent.attack_held, "Dodge does not erase the first finger's captured attack gesture")
	touch(dodge, 8, false)
	touch(held_attack, 7, false)
	await create_timer(0.3).timeout
	var mode_key: DungeonTouchButton = game.hud.attack_mode_button
	for expected in ["normal", "heavy", "off"]:
		var previous: String = game.hud.attack_mode
		touch(mode_key, 9, true)
		check(game.hud.attack_mode == previous, "Auto mode waits for a completed click")
		await create_timer(0.1).timeout
		check(mode_key.finger == 9 and game.hud.attack_mode == previous, "Held auto key survives game refresh without cycling")
		touch(mode_key, 9, false, true)
		check(game.hud.attack_mode == expected and game.world.auto_attack_mode == expected, "Auto click advances once to " + expected)
	touch(mode_key, 9, true)
	touch(mode_key, 9, false)
	check(game.hud.attack_mode == "off", "Outside auto release cancels its click")
	var attack: DungeonTouchButton = game.hud.skill_buttons[0]
	touch(attack, 6, true)
	await create_timer(0.1).timeout
	game.hud.show_page("Pause", [])
	check(attack.finger == -1 and not game.world.intent.attack_held and attack.visual_scale == 1.0, "Live modal cancels held gameplay input and icon feedback")
	game.hud.close_page()
	check(game.is_processing() and game.world.is_physics_processing(), "Main update and world physics remained enabled throughout")
	var report = {"checks": checks, "failures": failures, "passed": failures.is_empty(), "main_processing": game.is_processing(), "world_physics": game.world.is_physics_processing()}
	FileAccess.open("res://reports/skill-controls-live.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("SKILL_CONTROLS_LIVE ", JSON.stringify(report))
	game.systems.decorations = null
	game.queue_free()
	await process_frame
	canvas.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func check_holds(context: String) -> void:
	for slot in 4:
		var key: DungeonTouchButton = game.hud.skill_buttons[slot]
		events.clear()
		touch(key, slot + 1, true)
		await create_timer(0.15).timeout
		check(key.finger == slot + 1 and key.button_pressed, "%s slot %d stays held across normal game frames" % [context, slot])
		check(is_equal_approx(key.visual_scale, key.PRESSED_SCALE), "%s slot %d reaches visible icon compression" % [context, slot])
		check(events == [[slot, true]], "%s slot %d has no synthesized release during HUD refresh" % [context, slot])
		if slot == 0:
			check(game.world.intent.attack_held, context + " attack hold reaches the gameplay controller")
			await create_timer(0.45).timeout
			check(key.finger == slot + 1 and game.world.intent.attack_hold_elapsed >= game.world.intent.FEEL.attack_hold_threshold, context + " hold survives through the heavy attack threshold")
		touch(key, slot + 1, false)
		check(events == [[slot, true], [slot, false]], "%s slot %d emits exactly one down/up pair" % [context, slot])
		await create_timer(0.22).timeout
		check(key.finger == -1 and is_equal_approx(key.visual_scale, 1.0), "%s slot %d release animation finishes in the live game" % [context, slot])
