extends RefCounted

var samples: Array[Dictionary] = []
var events: Array[Dictionary] = []
var started := Time.get_ticks_usec()
var previous := started

func mark(kind: String, details: Dictionary = {}) -> void:
	events.append({"frame": samples.size(), "kind": kind, "details": details})

func sample(world: Node, phase: String) -> void:
	var now := Time.get_ticks_usec()
	samples.append({"phase": phase, "frame_ms": (now - previous) / 1000.0,
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000,
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000,
		"memory_bytes": OS.get_static_memory_usage(), "objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"bodies": Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
		"actors": world.actors.size(), "projectiles": world.projectiles.size(),
		"particles": world.presentation._active_particles, "emitters": world.presentation._active_emitters})
	previous = now

static func summarize(rows: Array) -> Dictionary:
	if rows.is_empty(): return {}
	var times: Array[float] = []
	var sum := 0.0
	var peaks := {}
	var slow := {"33": 0, "50": 0, "100": 0}
	for row in rows:
		times.append(float(row.frame_ms))
		sum += float(row.frame_ms)
		for limit in slow:
			if float(row.frame_ms) > float(limit): slow[limit] += 1
		for key in ["process_ms", "physics_ms", "memory_bytes", "objects", "bodies", "actors", "projectiles", "particles", "emitters"]:
			peaks[key] = maxf(float(peaks.get(key, 0)), float(row.get(key, 0)))
	times.sort()
	var worst_count := maxi(1, ceili(times.size() * 0.01))
	var worst_sum := 0.0
	for index in range(times.size() - worst_count, times.size()): worst_sum += times[index]
	return {"frames": times.size(), "average_fps": times.size() * 1000.0 / maxf(sum, 0.001),
		"one_percent_low_fps": worst_count * 1000.0 / maxf(worst_sum, 0.001),
		"p95_ms": times[ceili(times.size() * 0.95) - 1], "p99_ms": times[ceili(times.size() * 0.99) - 1],
		"max_ms": times.back(), "slow_frames": slow, "peaks": peaks,
		"memory_start_bytes": rows.front().memory_bytes, "memory_end_bytes": rows.back().memory_bytes}

func report() -> Dictionary:
	return {"engine": Engine.get_version_info(), "platform": OS.get_name(), "os_version": OS.get_version(),
		"device": OS.get_model_name(), "renderer": RenderingServer.get_video_adapter_name(),
		"headless": DisplayServer.get_name() == "headless", "debug": OS.is_debug_build(),
		"physics_hz": Engine.physics_ticks_per_second, "elapsed_seconds": (Time.get_ticks_usec() - started) / 1000000.0,
		"all": summarize(samples), "cold": summarize(samples.filter(func(row): return row.phase == "cold")),
		"warm": summarize(samples.filter(func(row): return row.phase == "warm")), "samples": samples, "events": events}
