extends SceneTree

const Intent = preload("res://scripts/player_intent.gd")
const Combat = preload("res://scripts/domain/combat.gd")
const FEEL = preload("res://assets/feel_settings.tres")
var assertions := 0
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var stick = DungeonJoystick.new()
	root.add_child(stick)
	stick.size = Vector2(180, 180)
	stick._set_point(stick.size / 2 + Vector2(6.4, 0))
	check(stick.value.length() < 0.00001, "10 percent deadzone is stationary")
	stick._set_point(stick.size / 2 + Vector2(35.2, 0))
	check(is_equal_approx(stick.value.x, 0.5), "Outside deadzone maps continuously")
	stick._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(stick.value == Vector2.ZERO, "Focus loss clears joystick")
	var button = DungeonTouchButton.new()
	root.add_child(button)
	button.position = Vector2(300, 0)
	button.size = Vector2(100, 100)
	var touch = InputEventScreenTouch.new()
	touch.index = 2
	touch.position = Vector2(140, 90)
	touch.pressed = true
	stick._input(touch)
	var drag = InputEventScreenDrag.new()
	drag.index = 2
	drag.position = touch.position + Vector2(40, 0)
	stick._input(drag)
	touch = InputEventScreenTouch.new()
	touch.index = 7
	touch.position = Vector2(350, 50)
	touch.pressed = true
	button._input(touch)
	check(stick.finger == 2 and button.finger == 7 and stick.value.x > 0 and button.button_pressed, "Independent fingers hold movement and skill simultaneously")
	touch.position = Vector2(900, 700)
	touch.pressed = false
	button._input(touch)
	check(button.finger == -1 and not button.button_pressed and stick.finger == 2, "Outside release only clears captured skill finger")
	stick._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	check(stick.finger == -1 and stick.value == Vector2.ZERO, "Background pause releases movement")
	button.free()
	stick.queue_free()
	var gradient = preload("res://scripts/presentation/authored_effect.gd").gradient({"maxGradient": {"m_NumColorKeys": 1, "m_NumAlphaKeys": 2, "key0": {"r": 1, "g": 1, "b": 1, "a": 1}, "key1": {"a": 0}, "ctime0": 0, "atime0": 0, "atime1": 65535}})
	check(gradient.sample(1).a == 0 and is_equal_approx(gradient.sample(0.5).a, 0.5), "Independent original alpha keys fade single-color effects")
	for fps in [30, 60, 120]:
		var combat = Combat.new()
		combat.configure()
		var intent = Intent.new()
		combat.busy = 0.1
		check(intent.request(combat, 2, true).status == "buffered", "Buffer accepted at %d Hz" % fps)
		var consumed := 0
		for i in fps:
			combat.tick(1.0 / fps)
			if intent.take_ready(combat, 1.0 / fps) == 2: consumed += 1
		check(consumed == 1, "Buffered request executes exactly once at %d Hz" % fps)
		combat.busy = 0.1
		intent.request(combat, 2, true)
		intent.take_ready(combat, 0)
		check(intent.take_ready(combat, 0.2) == -1 and intent.pending.is_empty(), "Expired input is discarded")
		combat.busy = 0
		combat.energy[2] = 0
		check(not intent.request(combat, 2, true).success and intent.pending.is_empty(), "Insufficient energy never queues")
		combat.energy[2] = combat.fighter.skills[2].maxSp
		combat.busy = 0.12
		intent.request(combat, 4, true)
		intent.request(combat, 4, false)
		check(intent.pending.is_empty() and not intent.heavy_held, "Release cancels buffered heavy")
		intent.request(combat, 1, true)
		check(intent.take_ready(combat, 0) == 1, "Dodge bypasses busy")
		intent.last_move = Vector3.LEFT
		check(intent.dodge_direction(Vector3.RIGHT, Vector3.FORWARD) == Vector3.RIGHT, "Dodge follows current movement")
		check(intent.dodge_direction(Vector3.ZERO, Vector3.FORWARD) == Vector3.LEFT, "Idle dodge uses last movement")
		var travelled := 0.0
		var elapsed := 0.0
		while elapsed < FEEL.dodge_duration:
			var next = elapsed + 1.0 / fps
			travelled += FEEL.dodge_distance * (DungeonActor.dodge_progress(next / FEEL.dodge_duration) - DungeonActor.dodge_progress(elapsed / FEEL.dodge_duration))
			elapsed = next
		check(absf(travelled - FEEL.dodge_distance) < 0.00001, "Dodge curve integrates to same distance at %d Hz" % fps)
	var world = DungeonWorld.new()
	var reference = Combat.new()
	reference.configure()
	reference.request_attack(0)
	check(absf(reference.busy - 0.367) < 0.001, "Sword follows authored combo window")
	reference.tick(0.367)
	reference.request_attack(0)
	check(reference.current_action == "sword_atk3", "Sword follows authored combo target")
	var original_hit: Dictionary = reference._action("ActGroup_playerchara", "sword_atk1").hits[0]
	var normalized = preload("res://scripts/presentation/hit_feedback.gd").normalize(original_hit)
	check(is_equal_approx(float(normalized.hit_stops[0].weight), 0.05), "Original light sword stop weight retained")
	check(normalized.camera_shakes[0].times == 2 and is_equal_approx(float(normalized.camera_shakes[0].duration), 0.1), "Original shake count and duration retained")
	check(preload("res://scripts/presentation/hit_feedback.gd").normalize({}).hit_stops.is_empty(), "Missing stop feedback does not invent a freeze")
	reference.drain_events()
	root.add_child(world)
	world.set_physics_process(false)
	world.set_process(false)
	world.presentation.set_process(false)
	for character in range(1, 8):
		for slot in range(5):
			var combat = Combat.new()
			combat.configure(null, null, character)
			if character == 3: combat.add_buff(str(combat.fighter.jp), 5)
			if character == 4: combat.add_buff(str(combat.fighter.jp), 30)
			var actor = DungeonActor.new()
			actor.is_player = true
			actor.actor_id = character
			actor.combat = combat
			world.add_child(actor)
			actor.set_visual(world.asset_path("characters", character), world.catalog.characters[str(character)])
			world.player = actor
			world.actors.append(actor)
			var result = combat.request_attack(slot)
			check(result.success, "Character %d slot %d starts" % [character, slot])
			var emitted_before: int = world.presentation.spawned
			var animation_found := false
			for step in range(240):
				if step == 45 and slot == 4: combat.request_attack(4, false)
				combat.tick(1.0 / 60)
				for event in combat.drain_events():
					world._consume(actor, event)
					if event.type == "command" and event.command.type == "EET_PlayAnim":
						var source_name = str(event.command.anim)
						var name = str(actor.animation_aliases.get(source_name.to_lower(), source_name.replace("@", "_")))
						animation_found = animation_found or actor.animation.current_animation == name
				world._tick_projectiles(1.0 / 60)
				world._tick_summons(1.0 / 60)
				world.presentation._process(1.0 / 60)
			check(animation_found, "Character %d slot %d resolves authored animation" % [character, slot])
			check(world.presentation.spawned > emitted_before, "Character %d slot %d has presentation" % [character, slot])
			for unit in world.summon_units.duplicate(): world._dispose_summon(unit, false)
			for projectile in world.projectiles:
				if is_instance_valid(projectile.get("visual")): projectile.visual.free()
			world.projectiles.clear()
			world.presentation.cancel_actor(actor)
			check(world.presentation.active.is_empty(), "Character %d slot %d effects clear after payload disposal and actor cancellation" % [character, slot])
			world.actors.erase(actor)
			world.player = null
			actor.free()
	var lance = Combat.new()
	lance.configure(null, null, 7)
	lance.request_attack(4)
	lance.cancel_held_input()
	lance.drain_events()
	check(not lance.charging and not lance.custom_properties.InputAttack_LongPress and lance.busy == 0, "Pause cancels active charge without releasing it")
	var report = {"assertions": assertions, "failures": failures, "passed": failures.is_empty(), "missing_presentation_references": world.presentation.missing.keys(), "scope": "Input and presentation integration, seven characters; no device or visual equivalence claim"}
	world.presentation.clear()
	world.free()
	FileAccess.open("res://reports/feel-tests.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("FEEL_TESTS ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
