extends SceneTree

const ROOM_ID := 1040101
const SEED := 731
const WARMUP_FRAMES := 120
const SAMPLE_FRAMES := 360
const ENEMIES := [41001, 41002, 41003, 41004]

var world: DungeonWorld
class PhysicsProbe extends Node:
	var world: DungeonWorld
	var durations: Array[float] = []
	var actor_counts: Array[int] = []
	var hit_counts: Array[int] = []
	var world_render_durations: Array[float] = []
	var presentation_durations: Array[float] = []
	var effect_counts: Array[int] = []
	var timeline: Array[String] = []
	var capture := false
	var frame_count := 0
	signal stepped

	func _physics_process(delta: float) -> void:
		var started := Time.get_ticks_usec()
		world._physics_process(delta)
		var elapsed := float(Time.get_ticks_usec() - started) / 1000.0
		frame_count += 1
		if capture:
			durations.append(elapsed)
			actor_counts.append(world.actors.size())
			hit_counts.append(world.received_hits)
			var state: Array = [world.received_hits, world.projectiles.size(), world.active_attack_entities.size()]
			for actor in world.actors:
				state.append([actor.actor_id, actor.combat.current_action, roundi(actor.combat.health),
					roundi(actor.position.x * 100.0), roundi(actor.position.z * 100.0)])
			timeline.append(JSON.stringify(state))
		stepped.emit()

	func _process(delta: float) -> void:
		var started := Time.get_ticks_usec()
		world._process(delta)
		var world_ms := float(Time.get_ticks_usec() - started) / 1000.0
		started = Time.get_ticks_usec()
		world.presentation._process(delta)
		var presentation_ms := float(Time.get_ticks_usec() - started) / 1000.0
		if capture:
			world_render_durations.append(world_ms)
			presentation_durations.append(presentation_ms)
			effect_counts.append(world.presentation.active.size())


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(120.0).timeout.connect(func(): quit(2))
	var source_before := _source_hashes()
	for action in ["move_left", "move_right", "move_up", "move_down"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	Engine.max_fps = 0
	Engine.physics_ticks_per_second = 60
	world = DungeonWorld.new()
	root.add_child(world)
	world.set_physics_process(false)
	world.set_process(false)
	world.load_environment(ROOM_ID)
	Engine.max_fps = 60
	var settings_effects := world.get_node_or_null("SettingsEffects")
	if settings_effects: settings_effects.settings["fps"] = 60
	world.presentation.audio_enabled = false
	world.presentation.set_process(false)
	world.test_driver = true
	var player_combat := DungeonCombat.new()
	player_combat.configure(null, null, 1, 0, SEED)
	player_combat.max_health = 1000000.0
	player_combat.health = 1000000.0
	player_combat.attack = 1.0
	world.create_player(player_combat, 1, Vector3(58, 0, 65))
	var campaign: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/campaign.json"))
	var room: Dictionary = {}
	for node in campaign.Nodes:
		if int(node.Id) == ROOM_ID:
			room = node
			break
	var spawns: Array = []
	for index in room.get("SpawnPoints", []).size():
		var point: Dictionary = room.SpawnPoints[index]
		spawns.append({"enemy_id": ENEMIES[index % ENEMIES.size()], "position": point.Position,
			"rotation": point.Rotation, "health_override": 1000000.0})
	world.spawn_wave(spawns, 1, SEED)
	while world.presentation.has_pending_preparation():
		world.presentation.prepare_step()
		await process_frame
	var probe := PhysicsProbe.new()
	probe.world = world
	root.add_child(probe)
	for frame in WARMUP_FRAMES: await probe.stepped
	Engine.max_fps = 60
	var sample_started := Time.get_ticks_usec()
	var effect_start: int = world.presentation.spawned
	probe.capture = true
	for frame in SAMPLE_FRAMES: await probe.stepped
	probe.capture = false
	probe.set_physics_process(false)
	var sample_elapsed := float(Time.get_ticks_usec() - sample_started) / 1000000.0
	var source_after := _source_hashes()
	var failures: Array[String] = []
	if probe.durations.size() != SAMPLE_FRAMES: failures.append("Incomplete physics samples")
	if probe.actor_counts.min() != 11 or probe.actor_counts.max() != 11: failures.append("Fixture did not retain all ten enemies")
	if probe.hit_counts.back() <= probe.hit_counts.front(): failures.append("No enemy hits during the sample")
	if probe.presentation_durations.is_empty() or probe.effect_counts.max() <= 0: failures.append("No presentation samples or active effects")
	if Engine.max_fps != 60: failures.append("Render cap changed during the sample")
	if source_before != source_after: failures.append("Source files changed during the measurement")
	var log_path := _argument("check-log", "")
	if log_path.is_empty(): failures.append("Pass --check-log matching Godot's --log-file to detect script errors")
	else:
		if not FileAccess.file_exists(log_path): failures.append("Engine log is unavailable: " + log_path)
		else:
			var log := FileAccess.get_file_as_string(log_path)
			if log.contains("SCRIPT ERROR:") or log.contains("ERROR:"): failures.append("Engine log contains errors: " + log_path)
	var report := {
		"scope": "Headless desktop CPU: actual 1040101 mine environment, navigation and collision, 10 authored spawn positions with mine enemy IDs 41001-41004, player auto-attacking and enemies pursuing/attacking. Script timings separately wrap DungeonWorld._physics_process, DungeonWorld._process, and combat presentation _process; actor visual updates, engine frame scheduling, rendering and GPU cost are excluded. Not Android frame rate, total CPU or thermal data.",
		"room": ROOM_ID, "seed": SEED, "warmup_ticks": WARMUP_FRAMES, "sample_ticks": probe.durations.size(),
		"physics_ms": _timings(probe.durations), "actor_count_min": probe.actor_counts.min(), "actor_count_max": probe.actor_counts.max(),
		"world_process_ms": _timings(probe.world_render_durations), "presentation_ms": _timings(probe.presentation_durations),
		"render_process_samples": probe.presentation_durations.size(), "elapsed_seconds": sample_elapsed,
		"render_fps": probe.presentation_durations.size() / sample_elapsed, "render_cap": Engine.max_fps,
		"peak_active_effects": probe.effect_counts.max(), "checked_engine_log": log_path,
		"effect_spawns": world.presentation.spawned - effect_start, "timeline_sha256": "\n".join(probe.timeline).sha256_text(),
		"hits_during_sample": probe.hit_counts.back() - probe.hit_counts.front(), "projectiles_at_end": world.projectiles.size(),
		"source_sha256_before": source_before, "source_sha256_after": source_after, "failures": failures, "passed": failures.is_empty()}
	var output := _argument("output", "/private/tmp/mine-combat-cpu-benchmark.json")
	FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("MINE_COMBAT_CPU ", JSON.stringify(report))
	probe.queue_free()
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)


func _argument(name: String, fallback: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--" + name + "="): return argument.get_slice("=", 1)
	return fallback


func _source_hashes() -> Dictionary:
	return {"world": FileAccess.get_sha256("res://scripts/world.gd"), "combat": FileAccess.get_sha256("res://scripts/domain/combat.gd"),
		"actor": FileAccess.get_sha256("res://scripts/actor.gd"), "enemy_ai": FileAccess.get_sha256("res://scripts/domain/enemy_ai.gd"),
		"projectile": FileAccess.get_sha256("res://scripts/domain/projectile.gd"), "interactions": FileAccess.get_sha256("res://scripts/world_interactions.gd"),
		"ground_loot": FileAccess.get_sha256("res://scripts/ground_loot.gd"),
		"presentation": FileAccess.get_sha256("res://scripts/presentation/combat_presentation.gd"),
		"authored_effect": FileAccess.get_sha256("res://scripts/presentation/authored_effect.gd")}


func _timings(values: Array[float]) -> Dictionary:
	var ordered := values.duplicate()
	if ordered.is_empty(): return {"mean": null, "p50": null, "p95": null, "max": null}
	ordered.sort()
	var total := 0.0
	for value in ordered: total += value
	return {"mean": total / ordered.size(), "p50": ordered[ordered.size() / 2],
		"p95": ordered[ceili(ordered.size() * 0.95) - 1], "max": ordered.back()}
