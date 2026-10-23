extends SceneTree

const Combat = preload("res://scripts/domain/combat.gd")
const SEED := 731
const SECONDS := 30.0
const HZ := 60
var failures: Array[String] = []
var profiles: GDScript

func _initialize() -> void:
	if FileAccess.file_exists("res://scripts/presentation/impact_profiles.gd"):
		profiles = load("res://scripts/presentation/impact_profiles.gd")
	_run.call_deferred()

func _arg(name: String, fallback: String) -> String:
	for value in OS.get_cmdline_user_args():
		if value.begins_with("--%s=" % name): return value.get_slice("=", 1)
	return fallback

func _run() -> void:
	var rows: Array[Dictionary] = []
	for character in range(1, 8):
		for policy in ["normal_combo", "heavy", "skills"]:
			rows.append(_measure(character, policy))
	var comparison: Array[Dictionary] = []
	var baseline_path := _arg("baseline", "")
	if not baseline_path.is_empty():
		var previous: Variant = JSON.parse_string(FileAccess.get_file_as_string(baseline_path))
		if not previous is Dictionary or not previous.get("rows") is Array:
			failures.append("Invalid baseline report: " + baseline_path)
		else:
			for row in rows:
				var matches: Array = previous.rows.filter(func(item): return item.character == row.character and item.policy == row.policy)
				if matches.size() != 1:
					failures.append("Missing baseline character %s %s" % [row.character, row.policy])
					continue
				var before: Dictionary = matches[0]
				var ratio := (float(row.damage) / float(before.damage) - 1.0) if float(before.damage) > 0 else 0.0
				var passed: bool = absf(ratio) <= 0.05 and row.source_stats == before.source_stats
				comparison.append({"character": row.character, "policy": row.policy, "before_damage": before.damage, "after_damage": row.damage, "change_percent": ratio * 100.0, "stats_unchanged": row.source_stats == before.source_stats, "passed": passed})
				if not passed: failures.append("Character %s %s throughput changed %.2f%%" % [row.character, row.policy, ratio * 100.0])
	var report := {
		"schema": 1, "label": _arg("label", "current"), "seed": SEED, "seconds": SECONDS, "hz": HZ,
		"rows": rows, "comparison": comparison, "failures": failures, "passed": failures.is_empty(),
		"scope": "Deterministic domain throughput: every emitted damage event contacts one immortal stationary enemy. Real damage, cooldown, energy, resources and hit confirmations are retained. Attacker hit stop follows the production impact profile's ranged flag and compensation, with current-sequence gating. This isolates attack cadence from target displacement, aim, AI and rendering; projectile travel, repeated spatial contacts and enemy incoming attacks are not simulated."
	}
	var path := _arg("output", "res://reports/impact-throughput.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "\t"))
	else: failures.append("Cannot write " + path)
	print("IMPACT_THROUGHPUT ", JSON.stringify({"label": report.label, "cases": rows.size(), "comparison": comparison, "failures": failures}))
	quit(0 if failures.is_empty() else 1)

func _measure(character: int, policy: String) -> Dictionary:
	var source := Combat.new()
	source.configure(null, null, character, 0, SEED)
	source.actor_key = "player"
	source.custom_properties["EnemyDistances"] = [1.6]
	var target := Combat.new()
	target.configure_enemy(11001, SEED)
	target.actor_key = "throughput_dummy"
	target.max_health = 1000000000.0
	target.health = target.max_health
	var source_stats := {"attack": source.attack, "defense": source.defense, "max_health": source.max_health, "skills": source.fighter.skills.duplicate(true)}
	var damage := 0.0
	var hits := 0
	var accepted := 0
	var action_counts: Dictionary = {}
	var stop_count := 0
	for frame in int(SECONDS * HZ):
		if source.charging and source.charge_elapsed >= 0.75: source.request_attack(4, false)
		if not source.is_busy():
			var choices: Array = [0] if policy == "normal_combo" else [4, 0] if policy == "heavy" else [3, 2, 0]
			for slot in choices:
				if source.request_attack(slot).success:
					accepted += 1
					break
		source.tick(1.0 / HZ)
		for event in source.drain_events():
			if event.type == "action_started":
				var name := str(event.get("action", ""))
				action_counts[name] = int(action_counts.get(name, 0)) + 1
			elif event.type == "hit":
				event["source"] = source
				event["distance"] = 1.6
				damage += target.receive(event, source.effective_attack_power())
				source.confirm_hit(event)
				hits += 1
				if profiles != null and source.has_method("apply_hit_stop"):
					var profile: Dictionary = profiles.resolve(event, source)
					if not profile.ranged and int(event.get("sequence", -1)) == source._cast_sequence:
						if source.apply_hit_stop(float(profile.stop), true): stop_count += 1
			elif event.type == "area":
				var before: float = target.health
				event["source"] = source
				if target.apply_area(event, false, 0):
					damage += before - target.health
					hits += 1
		var before_tick: float = target.health
		target.tick(1.0 / HZ)
		damage += before_tick - target.health
		target.drain_events()
	if hits == 0: failures.append("No damage contacts for character %d %s" % [character, policy])
	return {"character": character, "policy": policy, "damage": damage, "dps": damage / SECONDS, "contacts": hits, "accepted_inputs": accepted, "attacker_stops": stop_count, "actions": action_counts, "source_stats": source_stats, "remaining_energy": source.energy.duplicate(), "special_resource": source.special_resource(), "diagnostics": source.diagnostics.duplicate()}
