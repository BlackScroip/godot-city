extends SceneTree

var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _run() -> void:
	var catalog := DungeonCatalog.new()
	check(catalog.load_all(), "Catalog loads")
	var profile := DungeonProfile.new()
	var systems := DungeonSystems.new(catalog, profile)
	profile.data.run.active = true
	profile.data.run.inventory = {"20250": 1, "20260": 1, "20103": 1}
	var player := DungeonActor.new()
	player.set_physics_process(false)
	var followers = load("res://scripts/presentation/spirit_followers.gd").new()
	root.add_child(followers)
	followers.sync_from_run(systems, player)
	check(followers.entries.size() == 2, "Only owned spirits become followers")
	for entry in followers.entries.values():
		check(entry.visual.texture == DungeonStyle.texture("loot:" + str(entry.id)), "Follower uses its own identity artwork")
	var old = followers.entries[20250].visual
	followers.sync_from_run(systems, player)
	check(followers.entries[20250].visual == old, "Repeated sync does not duplicate followers")
	var start: Vector3 = followers.entries[20250].position
	player.position += Vector3(4, 0, 0)
	followers.advance(1.0 / 60.0, player)
	var intermediate: Vector3 = followers.entries[20250].position
	check(intermediate.x > start.x and intermediate.x < player.position.x, "Follower smoothly catches up")
	for frame in 120: followers.advance(1.0 / 60.0, player)
	check((followers.entries[20250].position as Vector3).distance_to(player.position) < 2.5, "Follower catches moving owner")
	player.position += Vector3(100, 0, 0)
	followers.advance(1.0 / 60.0, player)
	check((followers.entries[20250].position as Vector3).distance_to(player.position) < 2.5, "Teleport rebases follower")
	profile.data.run.inventory.erase("20250")
	profile.data.run.inventory["20251"] = 1
	followers.sync_from_run(systems, player)
	check(not followers.entries.has(20250) and followers.entries.has(20251), "Upgraded spirit replaces old presentation")
	var snapshot: Dictionary = JSON.parse_string(JSON.stringify(profile.data))
	followers.clear()
	check(profile.restore(snapshot), "Profile restores")
	followers.sync_from_run(systems, player)
	check(followers.entries.size() == 2 and followers.entries.has(20251), "Saved inventory restores exact companions")
	profile.data.run.active = false
	followers.sync_from_run(systems, player)
	check(followers.entries.is_empty(), "End of run removes companions")
	profile.data.run = DungeonProfile.new_run()
	profile.data.run.active = true
	followers.sync_from_run(systems, player)
	check(followers.entries.is_empty(), "New run cannot retain old companions")
	var all_loot: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/LootData.json"))
	var spirit_count := 0
	for row in all_loot:
		if row.get("loot_type", "") not in ["随从", "高级随从"]: continue
		spirit_count += 1
		profile.data.run.inventory = {str(row.id): 1}
		followers.sync_from_run(systems, player)
		var entry: Dictionary = followers.entries[int(row.id)]
		var initial: Vector3 = entry.visual.position
		followers.advance(0.05, player)
		check(entry.visual.texture != null and entry.visual.position != initial, "Every spirit animates with its own art: %s" % row.id)
		var paused: Vector3 = entry.visual.position
		followers.advance(0.0, player)
		check(entry.visual.position == paused, "Zero step freezes spirit: %s" % row.id)
		player.facing = -entry.direction
		followers.advance(0.05, player)
		check((entry.direction as Vector3).is_normalized(), "Opposite facing keeps continuous unit direction: %s" % row.id)
		followers.advance(20.0, player)
		check(entry.visual.position.is_finite(), "Resume remains finite: %s" % row.id)
	check(spirit_count > 10, "All normal and upgraded spirit entries covered")
	player.free()
	followers.queue_free()
	print(JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
