extends SceneTree

const Campaign = preload("res://scripts/domain/campaign.gd")
var assertions := 0
var failures: Array = []

func _initialize() -> void:
	var campaign = Campaign.new()
	_check(campaign.configure(), "Campaign config loads")
	var rooms := 0
	var waves := 0
	var spawns := 0
	var old_count := 0
	var counts: Array = []
	for room in campaign.database.Nodes + campaign.database.SpecialStages:
		if room.Flow not in ["Battle", "Boss"]: continue
		for seed_value in [1, 17, 389]:
			campaign.start_practice(int(room.Id), seed_value)
			rooms += 1
			if bool(room.ManualEnemies) and not bool(room.RandomEnemies):
				var maximum := 0
				for spawn in room.ForcedSpawns:
					if int(spawn.EnemyId) > 0 and (int(spawn.Group) == 0 or int(spawn.Group) == int(campaign.state.spawn_group)):
						maximum = maxi(maximum, int(spawn.Wave))
				_check(int(campaign.state.wave_count) == maximum, "Manual rooms use actual scripted wave count %s" % room.Id)
				old_count += maxi(0, int(room.WaveMin) - maximum)
			var before = campaign.snapshot()
			var total := 0
			var species: Array = []
			for wave in range(1, int(campaign.state.wave_count) + 1):
				var enemies = campaign.wave_spawns(wave)
				waves += 1
				spawns += enemies.size()
				total += enemies.size()
				_check(not enemies.is_empty(), "Playable authored wave %s:%s" % [room.Id, wave])
				_check(enemies.size() <= room.SpawnPoints.size(), "No enemies beyond authored point capacity %s:%s" % [room.Id, wave])
				_check(enemies == campaign.wave_spawns(wave), "Wave query does not reroll %s:%s" % [room.Id, wave])
				var used: Array = []
				var current_species: Array = []
				for enemy in enemies:
					_check(not used.has(int(enemy.spawn_index)), "No shared spawn point %s:%s:%s" % [room.Id, wave, enemy.spawn_index])
					used.append(int(enemy.spawn_index))
					var point: Array = room.SpawnPoints.filter(func(p): return int(p.Id) == int(enemy.spawn_index))
					_check(not point.is_empty(), "Spawn point ID exists")
					if point.is_empty(): continue
					_check(enemy.position == point[0].Position and enemy.rotation == point[0].Rotation, "Position and facing retain APK values")
					if not enemy.forced and not current_species.has(int(enemy.enemy_id)):
						current_species.append(int(enemy.enemy_id))
					if enemy.forced:
						_check(room.ForcedSpawns.any(func(s): return int(s.EnemyId) == int(enemy.enemy_id) and int(s.SpawnIndex) == int(enemy.spawn_index) and campaign._matches_wave(int(s.Wave), wave, int(campaign.state.wave_count)) and (int(s.Group) == 0 or int(s.Group) == int(campaign.state.spawn_group))), "Forced composition preserves selected group")
				if species.is_empty(): species = current_species
				elif enemies.size() < room.SpawnPoints.size():
					_check(current_species.all(func(id): return species.has(id)), "Random room species remain stable across waves")
			_check(before == campaign.snapshot(), "Wave inspection does not mutate saved plan")
			var restored = Campaign.new()
			restored.configure(campaign.database)
			restored.start_practice(int(room.Id), seed_value)
			_check(JSON.parse_string(JSON.stringify(restored.state.spawn_plan)) == JSON.parse_string(JSON.stringify(before.spawn_plan)), "Same room seed reproduces the complete spawn plan")
			_check(restored.restore(JSON.parse_string(JSON.stringify(before))), "Spawn plan JSON roundtrip restores")
			for wave in range(1, int(campaign.state.wave_count) + 1):
				_check(JSON.parse_string(JSON.stringify(restored.wave_spawns(wave))) == JSON.parse_string(JSON.stringify(campaign.wave_spawns(wave))), "Restored wave retains sampled composition and placement")
			if seed_value == 17: counts.append({"node": int(room.Id), "waves": int(campaign.state.wave_count), "enemies": total})
	_synthetic_budget(campaign)
	campaign.start_practice(10101111, 17)
	var legacy = campaign.snapshot()
	legacy.erase("spawn_plan")
	legacy.erase("spawn_plan_version")
	legacy.wave_count = 2
	legacy.waves_cleared = 1
	_check(campaign.restore(legacy) and int(campaign.state.wave_count) == 1 and campaign.room_ready(), "Legacy manual save drops fabricated repeat wave and keeps completed progress")
	var report = {"schema": 1, "assertions": assertions, "failures": failures, "room_seed_cases": rooms, "waves": waves, "spawns": spawns, "removed_minimum_repeat_waves": old_count, "seed_17_counts": counts, "evidence": "APK native wave allocator and packaged NodeData/EnvCfg/EnemyData; deterministic RNG differs from Unity."}
	var file = FileAccess.open("res://reports/monster-spawns.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("MONSTER SPAWNS: %s assertions, %s failures, %s room-seed cases, %s waves, %s spawns" % [assertions, failures.size(), rooms, waves, spawns])
	for failure in failures: printerr(failure)
	quit(0 if failures.is_empty() else 1)

func _synthetic_budget(campaign) -> void:
	var room: Dictionary = campaign.database.Nodes.filter(func(n): return int(n.Id) == 1010101)[0].duplicate(true)
	room.EnemyIds = [11001]
	room.EnemyTypeMin = 1
	room.EnemyTypeMax = 1
	room.MaxEnemyDifficulty = 8
	room.ForcedSpawns = []
	campaign.state = {"seed": 1, "wave_count": 1, "spawn_group": 0}
	var plan = campaign._build_spawn_plan(room)
	_check(plan["1"].size() == 8, "One species difficulty 1 consumes budget 8, not species count 1")
	var nearby: Array = room.SpawnPoints.filter(func(point):
		var distance = campaign._point_distance(point.Position, room.PlayerStart)
		return distance > 10 and distance < 25)
	for index in mini(nearby.size(), plan["1"].size()):
		_check(nearby.any(func(point): return int(point.Id) == int(plan["1"][index].spawn_index)), "Random placement consumes preferred distance band before distant fallback")
	room.ForcedSpawns = [{"EnemyId": 12001, "SpawnIndex": 1, "Wave": 1, "Group": 0}]
	plan = campaign._build_spawn_plan(room)
	_check(plan["1"].size() == 9 and plan["1"][0].forced and int(plan["1"][0].spawn_index) == 1, "Forced enemies are added separately without reducing random difficulty budget")
	_check(plan["1"].filter(func(enemy): return int(enemy.spawn_index) == 1).size() == 1, "Random placement reserves the forced point")
	room.ForcedSpawns = []
	room.EnemyIds = [11002]
	room.MaxEnemyDifficulty = 3
	plan = campaign._build_spawn_plan(room)
	_check(plan["1"].size() == 6, "Difficulty 0.5 yields twice the budget in enemies")
	room.MaxEnemyDifficulty = 100
	plan = campaign._build_spawn_plan(room)
	_check(plan["1"].size() == room.SpawnPoints.size(), "Budget overflow respects point capacity")
	room.RandomEnemies = false
	room.ForcedSpawns = [{"EnemyId": 11001, "SpawnIndex": 999, "Wave": 1, "Group": 0}]
	plan = campaign._build_spawn_plan(room)
	_check(plan["1"].is_empty(), "Invalid forced point does not stack enemies near player")
	_check(campaign._matches_wave(-1, 3, 3) and campaign._matches_wave(-2, 2, 3) and not campaign._matches_wave(0, 3, 3), "APK negative wave offsets count back from final wave")

func _check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message)
