extends SceneTree

const SettingsEffects = preload("res://scripts/presentation/settings_effects.gd")
const ResourceAudio = preload("res://scripts/presentation/resource_audio.gd")
const Combat = preload("res://scripts/domain/combat.gd")
var checks := 0
var failures: Array[String] = []
var canvas: SubViewport
var world: DungeonWorld

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func actor(player_owned: bool, point: Vector3) -> DungeonActor:
	var result := DungeonActor.new()
	result.is_player = player_owned
	result.combat = Combat.new()
	if player_owned: result.combat.configure()
	else: result.combat.configure_enemy(11001)
	result.combat.actor_key = "player" if player_owned else "enemy:" + str(world.actors.size())
	world.add_child(result)
	result.position = point
	result.set_process(false)
	result.set_physics_process(false)
	world.actors.append(result)
	return result

func _run() -> void:
	canvas = SubViewport.new()
	canvas.size = Vector2i(640, 360)
	canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(canvas)
	world = DungeonWorld.new()
	canvas.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.presentation.set_process(false)
	world.player = actor(true, Vector3.ZERO)
	world.snap_camera()
	var settings: Dictionary = DungeonSettings.DEFAULTS.duplicate()
	settings.dodge_priority = 1
	settings.motion_blur = false
	world.apply_settings(settings)
	_number_cases(settings)
	_battle_cases(settings)
	_target_cases(settings)
	_dodge_cases(settings)
	_joystick_cases()
	_audio_cases(settings)
	_effect_cases(settings)
	_pickup_cases(settings)
	var effects = SettingsEffects.new()
	effects.name = "SettingsEffects"
	world.add_child(effects)
	effects.set_process(false)
	effects.apply_settings(settings, world, 1.0)
	_flash_command_cases(effects, settings)
	_graphics_cases(effects, settings)
	if DisplayServer.get_name() != "headless": await _render_cases(effects, settings)
	var report := {"passed": failures.is_empty(), "assertions": checks, "failures": failures, "rendering": effects.runtime_status()}
	FileAccess.open("res://reports/settings-runtime-test.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("SETTINGS_RUNTIME_TEST ", JSON.stringify(report))
	canvas.free()
	quit(0 if failures.is_empty() else 1)

func _number_cases(settings: Dictionary) -> void:
	world._damage_number(Vector3.ZERO, 12500, false)
	check(world._numbers.size() == 1 and world._numbers[0].node.text == "12500", "Full damage numbers preserve integer amount")
	settings.damage_numbers = 1
	world.apply_settings(settings)
	check(world._numbers[0].node.text == "12.5K", "Abbreviation updates existing numbers immediately")
	settings.damage_numbers = 2
	world.apply_settings(settings)
	world._damage_number(Vector3.ZERO, 25, true)
	check(world._numbers.is_empty(), "Damage disabled recycles existing labels and suppresses new ones")
	settings.healing_numbers = 1
	world.apply_settings(settings)
	world._consume(world.player, {"type": "heal", "amount": 1500})
	check(world._numbers.size() == 1 and world._numbers[0].node.text == "+1.5K", "Real heal event uses independent healing-number setting")
	settings.healing_numbers = 2
	world.apply_settings(settings)
	check(world._numbers.is_empty(), "Healing disabled suppresses and recycles healing labels")
	check(DungeonWorld.number_text(1000000, 1) == "1M", "Abbreviated whole units omit a redundant decimal")

func _battle_cases(settings: Dictionary) -> void:
	world._battle_scales = {"actor": {"scale": 0.3, "remaining": 1.0}, "UnitStopFrame": {"scale": 0.12, "remaining": 0.1}}
	settings.slow_motion = false
	world.apply_settings(settings)
	check(is_equal_approx(world.simulation_scale, 0.12), "Slow-motion toggle leaves independent hit stop active")
	settings.hit_stop = 0
	world.apply_settings(settings)
	check(world.simulation_scale == 1.0 and not world._battle_scales.has("UnitStopFrame"), "Disabling hit stop clears active source stop immediately")
	settings.slow_motion = true
	settings.hit_stop = 50
	world.apply_settings(settings)
	check(world.simulation_scale == 0.3 and world.source_hit_stop_percent == 50, "Slow motion and weak source stop remain separate options")
	settings.camera_shake = 50
	world.apply_settings(settings)
	check(world.camera_shake_percent == 50, "Weak camera mode halves shared camera impulse gain")
	world._battle_scales.clear()
	world._refresh_battle_scale()

func _target_cases(settings: Dictionary) -> void:
	var near := actor(false, Vector3(0, 0, -1))
	var directed := actor(false, Vector3(2, 0, 0))
	world.player.desired_velocity = Vector3.RIGHT
	settings.target_mode = 0
	world.apply_settings(settings)
	check(world._attack_target(2) == directed, "Joystick mode favors the enemy along the movement direction")
	settings.target_mode = 1
	world.apply_settings(settings)
	world._auto_target = null
	check(world._attack_target(2) == near, "Nearest mode chooses closest visible enemy")
	settings.target_mode = 2
	world.apply_settings(settings)
	check(world._find_motion_target({}, world.player) == null, "No-lock mode prevents source action target acquisition")
	settings.attack_priority = 1
	world.apply_settings(settings)
	check(not world._movement_allows_auto_attack(directed), "Movement priority suppresses automatic attacks during movement")
	settings.attack_priority = 0
	world.apply_settings(settings)
	check(world._movement_allows_auto_attack(directed), "Attack priority admits automatic attacks toward a target")
	world.player.desired_velocity = Vector3.ZERO

func _dodge_cases(settings: Dictionary) -> void:
	settings.dodge_priority = 2
	world.apply_settings(settings)
	check(world.player.combat.statuses.has("26080801") and not world.player.combat.statuses.has("26081001"), "Blocked dodge mode applies the recovered disable flag")
	settings.dodge_priority = 1
	world.apply_settings(settings)
	check(not world.player.combat.statuses.has("26080801") and not world.player.combat.statuses.has("26081001"), "Default dodge mode clears both settings flags")
	settings.dodge_priority = 0
	world.apply_settings(settings)
	check(world.player.combat.statuses.has("26081001"), "Auto dodge mode enables source chain flag with an attackable target")
	var imported: Dictionary = world.player.combat._buff_index.duplicate()
	for character in range(1, 9):
		var combat = Combat.new()
		combat.configure(null, null, character)
		combat._buff_index = imported
		var dodge := combat._action("ActGroup_playerchara", str(combat.fighter.skills[1].action))
		var windows: Array = dodge.get("events", []).filter(func(command): return command.get("target", "") == "sys_checkdodgeatk")
		if windows.is_empty():
			check(character == 4, "Only the source wand dodge has an intrinsic attack instead of a dodge-attack dispatcher")
			continue
		var raw: Dictionary = JSON.parse_string(windows[0].raw)
		combat.custom_properties.InputAttack = false
		check(not combat._try_dodge_attack_interrupt(raw), "Character %d default dodge does not chain without attack input" % character)
		combat.add_buff("26081001")
		check(combat._try_dodge_attack_interrupt(raw) and ("dodge" in combat.current_action or "doge" in combat.current_action), "Character %d source dispatcher selects its own dodge attack in auto mode" % character)
		combat.add_buff("26080801")
		combat.custom_properties.InputAttack = true
		check(not combat._try_dodge_attack_interrupt(raw), "Character %d blocked mode suppresses dodge attack despite manual and automatic flags" % character)
	var timed = Combat.new()
	timed.configure()
	timed._buff_index = imported
	timed.add_buff("26081001")
	check(timed.request_attack(1).success, "Timed dodge test enters the real action engine")
	for tick in 14: timed.tick(1.0 / 60.0)
	check(timed.current_action == "sword_dodgeatk", "Real dodge timeline enters the source sword attack window automatically")
	settings.dodge_priority = 1
	world.apply_settings(settings)

func _joystick_cases() -> void:
	var stick := DungeonJoystick.new()
	root.add_child(stick)
	stick.size = Vector2(400, 300)
	stick.home = Vector2(100, 200)
	stick.apply_settings({"joystick_fixed": true})
	stick._begin_pointer(1, Vector2(120, 200))
	check(stick.center == stick.home and stick.value.x > 0.0, "Fixed joystick retains its authored center and evaluates displacement from it")
	stick.apply_settings({"joystick_fixed": false})
	check(stick.finger == -1 and stick.value == Vector2.ZERO, "Changing joystick mode cancels an active pointer")
	stick._begin_pointer(1, Vector2(250, 150))
	check(stick.value == Vector2.ZERO and stick.drag_origin == Vector2(250, 150), "Dynamic joystick starts neutral at touch origin")
	stick.free()

func _audio_cases(settings: Dictionary) -> void:
	settings.volume_master = 50
	settings.volume_music = 25
	settings.volume_effects = 0
	settings.volume_voice = 75
	DungeonStyle.apply_audio_options(settings)
	check(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")), linear_to_db(0.25)), "Music gain is independent of master gain")
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Effects")) and not AudioServer.is_bus_mute(AudioServer.get_bus_index("Voice")), "Effects mute preserves the voice bus")
	for name in ["Music", "Effects", "Voice"]:
		check(AudioServer.get_bus_send(AudioServer.get_bus_index(name)) == &"Master", name + " routes through Master exactly once")
	check(DungeonStyle.audio_bus("opaque-name", {}, "voice") == &"Voice", "Source PlayVoice category controls routing without filename inference")
	var audio = ResourceAudio.new()
	root.add_child(audio)
	audio.configure({"audio": {"audio_voice_fixture": [{"clips": ["res://assets/audio/missing.ogg"]}]}}, world)
	audio.play_named("audio_voice_fixture")
	check(audio.pending[0].layer._bus == &"Voice" and audio.music.bus == &"Music", "Resource event voices and music use independent buses")
	audio.free()

func _pickup_cases(settings: Dictionary) -> void:
	var source = preload("res://scripts/domain/catalog.gd").new()
	check(source.load_all(), "Pickup classification loads canonical tables")
	var profile = preload("res://scripts/domain/profile.gd").new()
	var systems := DungeonSystems.new(source, profile)
	settings.auto_pickup_relic = true
	settings.auto_pickup_ornament = true
	settings.auto_pickup_consumable = true
	world.ground_loot.apply_settings(settings)
	var relic: int = source.rows("LootData").filter(func(row): return row.loot_type == "普通遗物")[0].id
	var ornament: int = source.rows("RelationshipAmplifyData")[0].id
	check(world.ground_loot.preferred_pickup({"id": relic, "material": false}, systems), "Relic preference uses actual LootData classification")
	check(world.ground_loot.preferred_pickup({"id": ornament, "material": true}, systems), "Ornament preference recognizes RelationshipAmplifyData")
	check(world.ground_loot.preferred_pickup({"id": 10100, "material": false}, systems), "Consumable preference recognizes healing potions")
	check(not world.ground_loot.preferred_pickup({"id": relic, "material": false, "altar": "test"}, systems), "Auto pickup cannot bypass an altar choice")
	check(systems.begin_run(7, 1, 500).success, "Auto pickup fixture enters a valid adventure")
	var available: Array = source.rows("LootData").filter(func(row): return str(row.loot_type).ends_with("遗物") and systems.can_add_loot(int(row.id)))
	check(not available.is_empty(), "Auto pickup fixture finds an unlocked source relic")
	if not available.is_empty():
		var available_id := int(available[0].id)
		world.ground_loot.spawn(available_id, Vector3(8, 0, 0), 1, false, false)
		check(world.ground_loot.advance_collection(1.1, Vector3.ZERO, systems).is_empty(), "Relics outside the pickup radius remain on the ground")
		var collected: Array = world.ground_loot.advance_collection(0.01, Vector3(8, 0, 0), systems)
		check(collected.size() == 1 and systems.rank(profile.data.run.inventory, available_id) == 1, "Nearby automatic relic pickup grants through the normal inventory rules")
	world.ground_loot.spawn(ornament, Vector3.ZERO, 2, true, false)
	var before := int(systems.material(ornament))
	var collected: Array = world.ground_loot.advance_collection(1.1, Vector3.ZERO, systems)
	check(collected.size() == 1 and systems.material(ornament) == before + 2, "Ornament auto pickup grants the entire material stack once")
	check(world.ground_loot.advance_collection(1.1, Vector3.ZERO, systems).is_empty() and systems.material(ornament) == before + 2, "Collected ornaments cannot be granted twice")

func _effect_cases(settings: Dictionary) -> void:
	var presentation = world.presentation
	var effect: Dictionary = presentation.pool.back()
	effect.actor = weakref(world.player)
	effect.important = false
	settings.effects_opacity = 40
	settings.reduce_player_effects = false
	presentation.apply_settings(settings)
	presentation._apply_effect_opacity(effect)
	check(is_equal_approx(effect.sparks.color.a, 0.4), "Particle opacity follows the independent effects slider")
	settings.reduce_player_effects = true
	presentation.apply_settings(settings)
	presentation._apply_effect_opacity(effect)
	check(is_equal_approx(effect.sparks.color.a, 0.14), "Player effect reduction combines with effects opacity")
	effect.important = true
	presentation._apply_effect_opacity(effect)
	check(is_equal_approx(effect.sparks.color.a, 1.0), "Cosmetic reductions preserve enemy attack warning visibility")
	var particles: int = int(presentation.FEEL.particle_budget * 0.6)
	settings.effects_density = 0
	presentation.apply_settings(settings)
	check(not presentation._reserve_effect(particles, 0, false, false), "Low effects density enforces a lower particle budget")
	settings.effects_density = 2
	presentation.apply_settings(settings)
	check(presentation._reserve_effect(particles, 0, false, false), "Full effects density admits effects within the full source budget")
	settings.effects_opacity = 100
	settings.reduce_player_effects = false
	presentation.apply_settings(settings)

func _flash_command_cases(effects: Node, settings: Dictionary) -> void:
	settings.flash_strength = 5
	effects.apply_settings(settings, world, 1.0)
	var raw := {"EffectType": "ECET_FlashLight", "EffectData": {"Intensity": 0.8, "UseOverrideColor": true, "FlashLightColor": {"r": 0.2, "g": 0.4, "b": 0.6}}}
	var event := {"type": "command", "sequence": world.player.combat._cast_sequence, "command": {"type": "EET_CameraEffect", "duration": 1.0, "raw": JSON.stringify(raw)}}
	world._consume(world.player, event)
	effects._process(0)
	check(is_equal_approx(effects._material.get_shader_parameter("flash"), 0.4), "Real flash events multiply source intensity by the APK slider divided by ten")
	check(effects._material.get_shader_parameter("flash_color").is_equal_approx(Color(0.2, 0.4, 0.6)), "Real flash events retain an explicit authored flash color")
	world.player.combat._cast_sequence += 1
	effects._process(0)
	check(is_zero_approx(effects._material.get_shader_parameter("flash")), "Changing the source action cancels its screen flash")
	event.sequence = world.player.combat._cast_sequence
	event.command = {"type": "EET_CameraFade", "duration": 1.0, "raw": JSON.stringify({"TargetFade": 0.8})}
	world._consume(world.player, event)
	effects._process(0)
	check(is_zero_approx(effects._material.get_shader_parameter("flash")), "Source camera zoom offsets cannot trigger a screen flash")

func _graphics_cases(effects: Node, settings: Dictionary) -> void:
	settings.dynamic_resolution = true
	effects.apply_settings(settings, world, 1.0)
	for index in 30: effects.sample_performance(12.0, 1.0)
	check(is_equal_approx(effects.current_scale, 0.5), "Sustained low fps reduces resolution to a bounded minimum")
	for index in 12: effects.sample_performance(60.0, 4.0)
	check(is_equal_approx(effects.current_scale, 1.0), "Stable recovered frame rate restores configured resolution")
	settings.dof = true
	settings.bloom = true
	effects.apply_settings(settings, world, 1.0)
	check(effects.runtime_status().dof in ["native", "depth_screen_blur"], "DOF uses a declared native or depth-based renderer route")
	check(effects._depth != null or world.camera.attributes != null, "DOF route creates actual render resources")
	settings.flash_strength = 0
	effects.apply_settings(settings, world, 1.0)
	effects.screen_flash(1.0, 1.0)
	effects._process(0.01)
	check(is_zero_approx(effects._material.get_shader_parameter("flash")), "Zero flash strength suppresses authored screen flash")
	settings.flash_strength = 10
	effects.apply_settings(settings, world, 1.0)
	effects.screen_flash(1.0, 1.0)
	effects._process(0.01)
	check(effects._material.get_shader_parameter("flash") > 0.9, "Maximum flash strength preserves the reconstructed authored flash")

func _render_cases(effects: Node, settings: Dictionary) -> void:
	for point in [Vector3(-3, 0, 3), Vector3(3, 0, -3) - world.camera.global_basis.z * 20.0, Vector3(-2, 0, -7)]:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(3, 3, 3)
		mesh.mesh = box
		mesh.position = point
		var material := StandardMaterial3D.new()
		material.albedo_color = Color.WHITE
		mesh.material_override = material
		world.add_child(mesh)
	settings.bloom = false
	settings.dof = false
	settings.brightness = 0
	settings.flash_strength = 0
	effects.apply_settings(settings, world, 1.0)
	await process_frame
	await RenderingServer.frame_post_draw
	var original := canvas.get_texture().get_image()
	original.save_png("res://reports/settings-runtime-original.png")
	settings.brightness = 100
	effects.apply_settings(settings, world, 1.0)
	await process_frame
	await RenderingServer.frame_post_draw
	var bright := canvas.get_texture().get_image()
	var before := original.get_pixel(10, 10)
	var after := bright.get_pixel(10, 10)
	check(after.get_luminance() > before.get_luminance() + 0.03, "Brightness changes actual rendered world pixels")
	bright.save_png("res://reports/settings-runtime-brightness.png")
	settings.brightness = 0
	settings.dof = true
	effects.apply_settings(settings, world, 1.0)
	effects._process(0.01)
	await process_frame
	await RenderingServer.frame_post_draw
	var depth := canvas.get_texture().get_image()
	check(_changed_pixels(original, depth) > 20, "Depth-aware compatibility DOF changes rendered geometry pixels")
	check(absf(depth.get_pixel(10, 10).get_luminance() - original.get_pixel(10, 10).get_luminance()) < 0.01, "DOF preserves a uniform background without a second gamma conversion")
	depth.save_png("res://reports/settings-runtime-dof.png")
	if effects._depth:
		var far_focus := -(world.camera.global_transform.affine_inverse() * (Vector3(3, 0, -3) - world.camera.global_basis.z * 20.0)).z
		effects._depth.material_override.set_shader_parameter("focus_distance", far_focus)
		await process_frame
		await RenderingServer.frame_post_draw
		check(_changed_pixels(depth, canvas.get_texture().get_image()) > 10, "Moving the DOF focus plane changes depth-selected geometry rather than applying a uniform screen blur")
	settings.dof = false
	settings.bloom = true
	effects.apply_settings(settings, world, 1.0)
	await process_frame
	await RenderingServer.frame_post_draw
	var bloom := canvas.get_texture().get_image()
	check(_changed_pixels(original, bloom) > 100, "Compatibility bloom changes actual scene pixels")
	bloom.save_png("res://reports/settings-runtime-bloom.png")
	settings.bloom = false
	settings.motion_blur = true
	effects.apply_settings(settings, world, 1.0)
	effects._process(0.01)
	world.camera.position.x += 0.6
	effects._process(0.01)
	check(effects._motion_active, "Camera motion produces a nonzero directional motion blur vector")
	await process_frame
	await RenderingServer.frame_post_draw
	var motion := canvas.get_texture().get_image()
	check(not motion.is_empty() and motion.get_pixel(10, 10).get_luminance() > 0.01, "Motion-blurred scene remains nonblank")
	motion.save_png("res://reports/settings-runtime-motion.png")

func _changed_pixels(before: Image, after: Image) -> int:
	var changed := 0
	for y in range(0, before.get_height(), 3):
		for x in range(0, before.get_width(), 3):
			var a := before.get_pixel(x, y)
			var b := after.get_pixel(x, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.03: changed += 1
	return changed
