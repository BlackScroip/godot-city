extends SceneTree

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _run() -> void:
	var world := DungeonWorld.new()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.presentation.set_process(false)
	world.presentation.audio_enabled = false
	var combat := DungeonCombat.new()
	combat.configure()
	world.create_player(combat, 1, Vector3.ZERO)
	world.spawn_wave([{"enemy_id": 11001, "position": Vector3(1, 0, 1)}], 0, 481)
	var target := world.actors[1]
	target.combat.defense = 0
	target.combat.armor = 0
	target.combat.shield = 0
	target.combat.invincible = 0
	target.invulnerability = 0
	target.combat.health = 10000
	target.combat.max_health = 10000
	var hit := {"damage": 107.0, "uncritical_damage": 107.0, "critical_rate": 1.0, "critical_roll": 0.0, "critical_multi": 2.0, "emission": 1, "definition": {"critical": true, "element": "Fire"}, "attack_collision": false}
	world._apply_hit(world.player, target, hit)
	check(world._numbers.size() == 1, "Confirmed hit emits one number")
	var number = world._numbers.back().node
	check(number.text == "214" and number.critical, "Final critical damage and flag reach display")
	check(number.glyph_names == ["bgcrit", "fire2", "fire1", "fire4"], "Uses APK critical and elemental sprites")
	for glyph in number.glyphs: check(glyph.texture != null, "Recovered glyph texture loads")
	world._damage_number(Vector3.UP * 1.8, 107, false)
	check(world._numbers[0].origin != world._numbers[1].origin, "Consecutive hits separate")
	world._tick_damage_numbers(0.3)
	check(number.modulate.a == 1.0, "Number remains readable before fade")
	var original_size := world.camera.size
	var screen_scale := world._number_screen_scale(Vector3.ZERO)
	world.camera.size = original_size * 2.0
	check(is_equal_approx(world._number_screen_scale(Vector3.ZERO), screen_scale * 2.0), "Camera zoom preserves APK screen font size")
	world.camera.size = original_size
	world._tick_damage_numbers(0.7)
	check(world._numbers.is_empty(), "Completed numbers recycle")
	world._damage_number(Vector3.ZERO, 9, true)
	check(not world._numbers[0].node.critical and world._numbers[0].node.kind == "hurt", "Pool reuse clears critical and sets received damage")
	world._tick_damage_numbers(1.0)
	world.player.invulnerability = 0.35
	world.player.dodge_elapsed = 0.1
	var health := combat.health
	world._apply_hit(target, world.player, {"damage": 50.0, "definition": {}})
	check(combat.health == health and world._numbers.size() == 1, "Actual player dodge avoids damage and shows caption")
	check(world._numbers.back().node.caption.text == "闪避" and world._numbers.back().node.caption.font_size == 32, "Dodge uses APK tips text size")
	check(world._numbers.back().node.caption.font.resource_path == "res://assets/ui/boss_intro/font_a8fb15c8685836d5.ttf", "Dodge uses the APK Alibaba ExtraBold font")
	check(world._numbers.back().node.caption.modulate == Color.GREEN, "Dodge uses native green text")
	world._apply_hit(target, world.player, {"damage": 50.0, "definition": {}})
	check(world._numbers.size() == 1, "Same-frame dodge contacts do not stack captions")
	world.apply_settings({"damage_numbers": 2})
	check(world._numbers.size() == 1, "Dodge caption remains independent of damage setting")
	world._tick_damage_numbers(1.0)
	world.player.invulnerability = 0
	world.player.dodge_elapsed = -1
	combat.invincible = 0
	combat._dodge_time = 0.3
	combat.events.clear()
	combat.receive({"damage": 50.0, "definition": {}, "attack_collision": false})
	check(combat.events.any(func(event): return event.type == "evaded_hit"), "Automatic dodge emits presentation event")
	world._impact_clock += 1.0
	for event in combat.events: world._consume(world.player, event)
	check(world._numbers.size() == 1, "Automatic dodge reaches world display")
	check(world._numbers.back().node.text == "自动闪避", "Automatic dodge uses its distinct APK localization key")
	world._tick_damage_numbers(1.0)
	combat._dodge_time = 0
	combat._block_time = 0.3
	combat.events.clear()
	combat.receive({"damage": 50.0, "definition": {}, "attack_collision": false})
	for event in combat.events: world._consume(world.player, event)
	check(world._numbers.is_empty(), "Block does not claim a dodge")
	if DisplayServer.get_name() != "headless":
		for actor in world.actors: actor.suspended = true
		world.camera.position = Vector3(0, 10, 12)
		world.camera.look_at(Vector3.ZERO)
		world.camera.size = 12
		world.apply_settings({"damage_numbers": 0})
		for viewport_size in [Vector2i(1600, 900), Vector2i(844, 390)]:
			root.size = viewport_size
			world._numbers.clear()
			world._damage_number(Vector3(-3, 1.8, 0), 107, false, false, "Fire")
			world._damage_number(Vector3(0, 1.8, 0), 214, false, true, "Fire")
			world._impact_clock += 1
			world._dodge_number(world.player)
			world._numbers.back().origin = Vector3(3, 1.8, 0)
			world._tick_damage_numbers(0.2)
			for frame in 4: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("/private/tmp/damage-numbers-%dx%d.png" % [viewport_size.x, viewport_size.y])
			world._tick_damage_numbers(1.0)
	print("DAMAGE_NUMBER_DISPLAY_TEST ", JSON.stringify({"checks": checks, "failures": failures}))
	world.free()
	quit(0 if failures.is_empty() else 1)
