extends SceneTree

const Intent = preload("res://scripts/player_intent.gd")
const Metrics = preload("res://scripts/combat_metrics.gd")
var failures: Array[String] = []
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for hz in [30, 60, 120]:
		for character in range(1, 8): _input_cases(character, hz)
	await _hud_and_pool_cases()
	await _save_cases()
	check(DungeonProfile.attack_mode({"auto_attack": false}) == "off", "Legacy disabled migration")
	check(DungeonProfile.attack_mode({"auto_attack": true}) == "normal", "Legacy enabled migration")
	check(DungeonProfile.attack_mode({"auto_attack_mode": "heavy", "auto_attack": false}) == "heavy", "Mode takes precedence")
	check(DungeonProfile.attack_mode({"auto_attack_mode": 99}) == "normal", "Invalid mode fallback")
	var samples: Array = []
	for index in 100: samples.append({"frame_ms": 50.0 if index == 99 else 10.0, "memory_bytes": 100})
	var summary = Metrics.summarize(samples)
	check(summary.one_percent_low_fps == 20 and summary.p99_ms == 10 and summary.max_ms == 50, "1 percent low and percentile definitions")
	print("COMBAT_OPTIMIZATION ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func _fighter(character: int) -> DungeonCombat:
	var combat := DungeonCombat.new()
	combat.configure(null, null, character, 0, 731)
	var resource := str(combat.fighter.get("jp", ""))
	if not resource.is_empty(): combat.add_buff(resource, 300)
	return combat

func _input_cases(character: int, hz: int) -> void:
	var combat = _fighter(character)
	var intent = Intent.new()
	intent.attack_button(combat, true)
	check(intent.take_ready(combat, 0) == -1, "Normal waits for release %d/%d" % [character, hz])
	intent.attack_button(combat, false)
	check(intent.take_ready(combat, 0) == 0, "Short release requests normal %d/%d" % [character, hz])
	combat.request_attack(0)
	for frame in hz:
		intent.advance_hold(combat, 1.0 / hz)
		combat.tick(1.0 / hz)
		combat.drain_events()
	check(not intent.heavy_held and intent.pending.is_empty(), "Tap has no delayed heavy %d/%d" % [character, hz])
	combat = _fighter(character)
	intent = Intent.new()
	intent.attack_button(combat, true)
	var heavy_started := false
	for frame in hz * 5:
		intent.advance_hold(combat, 1.0 / hz)
		var slot: int = intent.take_ready(combat, 1.0 / hz)
		if slot >= 0:
			if slot == 4:
				heavy_started = combat.request_attack(slot).success
				check(float(frame + 1) / hz >= 0.3 - 0.00001, "Heavy threshold %d/%d" % [character, hz])
				break
		combat.tick(1.0 / hz)
		combat.drain_events()
	check(heavy_started, "Held request survives normal recovery %d/%d" % [character, hz])
	intent.attack_button(combat, false)
	check(not intent.heavy_held and not combat.custom_properties.InputAttack_LongPress, "Release heavy %d/%d" % [character, hz])
	intent.attack_button(combat, true)
	intent.request(combat, 1, true)
	check(intent.attack_held and not intent.heavy_held, "Dodge preserves independent attack touch while releasing the current heavy %d/%d" % [character, hz])
	intent.clear(combat)
	combat.drain_events()
	check(not intent.manual_attack_active() and not combat.charging, "Focus/reset clears gesture %d/%d" % [character, hz])

func _hud_and_pool_cases() -> void:
	var world := DungeonWorld.new()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	var hud := DungeonHud.new()
	root.add_child(hud)
	world.hud = hud
	await process_frame
	check(hud.skill_buttons.size() == 6 and hud.skill_by_slot.keys() == [0, 1, 2, 3] and hud.partner_skill_bar.buttons.size() == 2, "Four character controls and two independent partner controls")
	var changes: Array = []
	hud.action.connect(func(kind, mode, _extra):
		if kind == "auto_attack_mode":
			changes.append(mode)
			hud.set_attack_mode(mode)
			world.set_attack_mode(mode))
	for index in 3: hud.attack_mode_button.pressed.emit()
	check(changes == ["heavy", "off", "normal"], "Mode cycle")
	var player := DungeonActor.new()
	player.is_player = true
	player.combat = _fighter(1)
	world.add_child(player)
	world.player = player
	world.actors.append(player)
	world._automatic_heavy_held = true
	player.combat.request_attack(4)
	var sequence: int = player.combat._cast_sequence
	world.set_attack_mode("off")
	check(not world._automatic_heavy_held and not player.combat.custom_properties.InputAttack_LongPress and sequence == player.combat._cast_sequence, "Mode off releases without cancelling current action")
	var state := DungeonProjectile.new()
	var event = {"definition": {"raw": JSON.stringify({"MotionAnimatorProperty": {"Speed": 600}, "EntityProperty": {"MaxPassNum": 99}})}}
	state.configure(event, Vector3.ZERO, Vector3.FORWARD, Vector3.ZERO)
	state.advance(1.0 / 60, Vector3.ZERO, Vector3.FORWARD)
	check(state.intersects(Vector3(0, 0, -5)), "Fast projectile swept segment")
	state.record_hit("old_target")
	world._add_projectile_visual(state, player)
	var old_mesh = world.projectiles[0].visual
	world._recycle_projectile(world.projectiles.pop_back())
	check(not old_mesh.visible and state.hits.is_empty() and state.hit.is_empty() and state.source_key.is_empty(), "Pool reset releases gameplay references")
	var reused: DungeonProjectile = world._projectile_state_pool.pop_back()
	reused.configure(event, Vector3.ONE, Vector3.BACK, Vector3.ZERO)
	world._add_projectile_visual(reused, player)
	check(world.projectiles[0].visual == old_mesh and reused.can_hit("old_target") and reused.age == 0, "Reused shot has fresh collision history")
	world._recycle_projectile(world.projectiles.pop_back())
	for index in 200: world._damage_number(Vector3.ZERO, index, false)
	check(world._numbers.size() == world.FEEL.damage_number_budget, "Damage number budget")
	world._tick_damage_numbers(1)
	check(world._numbers.is_empty() and world._number_pool.size() == world.FEEL.damage_number_budget, "Damage labels return to pool")
	var enemy := DungeonActor.new()
	enemy.combat = DungeonCombat.new()
	enemy.combat.configure_enemy(11001)
	world.add_child(enemy)
	enemy.position = Vector3(0, 0, 1.5)
	world.actors.append(enemy)
	world.fighting = true
	await physics_frame
	var terminal := DungeonProjectile.new()
	terminal.configure({"damage": 20.0, "definition": {"raw": JSON.stringify({"MotionAnimatorProperty": {"Speed": 600, "MaxLifetime": 0.01}, "EntityProperty": {"MaxPassNum": 0}})}}, Vector3(0, 0.75, 5), Vector3.FORWARD, Vector3.ZERO)
	terminal.source_player = false
	terminal.source_key = str(enemy.combat.actor_key)
	world._add_projectile_visual(terminal, enemy)
	var before_health: float = player.combat.health
	world._tick_projectiles(1.0 / 60)
	check(player.combat.health < before_health and world.projectiles.is_empty(), "Expired fast shot hits final swept segment then recycles")
	var limited := DungeonProjectile.new()
	limited.configure({"definition": {"raw": JSON.stringify({"MotionAnimatorProperty": {"Speed": 600, "Distance": 2, "MaxLifetime": 1}})}}, Vector3.ZERO, Vector3.BACK, Vector3.ZERO)
	limited.advance(1.0 / 60, Vector3.ZERO, Vector3.BACK)
	check(limited.finished and is_equal_approx(limited.position.z, 2.0), "Distance-limited projectile does not sweep beyond range")
	for hz in [30, 60, 120]:
		for character in range(1, 8):
			world.clear_input()
			player.combat = _fighter(character)
			world.set_attack_mode("heavy")
			var hits := 0
			var normal_starts := 0
			for frame in hz * 10:
				world._tick_player_input(1.0 / hz)
				player.combat.tick(1.0 / hz)
				for emitted in player.combat.drain_events():
					if emitted.type == "hit": hits += 1
					if emitted.type == "action_started" and int(emitted.slot) == 0: normal_starts += 1
			check(hits > 0, "Automatic heavy emits damage %d/%d" % [character, hz])
			check(normal_starts == 0, "Heavy never falls back to normal %d/%d" % [character, hz])
			world.set_attack_mode("off")
			player.combat.busy = 0
			var previous_sequence: int = player.combat._cast_sequence
			world._tick_player_input(1.0 / hz)
			check(player.combat._cast_sequence == previous_sequence, "Off starts no action %d/%d" % [character, hz])
	for character in [3, 4]:
		player.combat = DungeonCombat.new()
		player.combat.configure(null, null, character)
		world.set_attack_mode("heavy")
		check(not player.combat.input_block_reason(4).is_empty(), "Automatic heavy waits on character resource %d" % character)
		var old_sequence: int = player.combat._cast_sequence
		for frame in 60: world._tick_player_input(1.0 / 60)
		check(player.combat._cast_sequence == old_sequence, "Resource shortage does not auto normal %d" % character)
	hud.queue_free()
	world.queue_free()
	await process_frame

func _save_cases() -> void:
	var path := "user://async-save-test-%d.json" % Time.get_ticks_usec()
	var store := DungeonSaveStore.new(path)
	var profile := DungeonProfile.new()
	for index in 20:
		profile.data.materials["101"] = index
		store.request_save(profile.data)
	profile.data.materials["101"] = 9999
	check(store.flush(), "Async saves flush")
	check(store.committed_version == 20 and store.load_profile().materials["101"] == 19, "Newest immutable snapshot wins")
	var invalid = profile.data.duplicate(true)
	invalid.materials["101"] = -1
	store.request_save(invalid)
	check(not store.flush(), "Async invalid save reports failure")
	check(store.load_profile().materials["101"] == 19, "Failure preserves last save")
	profile.data.materials["101"] = 27
	store.request_save(profile.data)
	check(store.save(profile.data), "Explicit save drains background writer")
	check(store.load_profile().materials["101"] == 27, "Explicit save is latest")
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	await process_frame
