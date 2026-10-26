extends DungeonCombat

# Original interpreter retained independently for stepwise differential tests.
func _cache_enemy_timing(definition: Dictionary) -> void:
	_enemy_speed_windows.clear()
	_enemy_interrupts.clear()
	if enemy.is_empty(): return
	for command in definition.get("events", []):
		if not command.get("enabled", false): continue
		if command.get("type", "") == "EET_Interrupt":
			_enemy_interrupts.append(command)
		elif command.get("type", "") == "EET_ActionSpeedScale" and float(command.get("duration", 0)) > 0:
			var raw = _read_raw_json(str(command.get("raw", "{}")))
			if raw is Dictionary:
				_enemy_speed_windows.append({"start": float(command.time), "end": float(command.time) + float(command.duration), "rate": maxf(0.01, float(raw.get("ScaleSpeed", 1)))})

func _tick_enemy_interrupts() -> void:
	if not enemy_ai_enabled or frozen > 0 or impact_pause > 0 or stagger_remaining > 0: return
	var visited: Dictionary = {current_action: true}
	for transition in range(12):
		var changed = false
		var elapsed = action_elapsed * maxf(0.01, float(custom_properties.get("_feel_action_speed", 1)))
		for command in _enemy_interrupts:
			var start = float(command.get("time", 0))
			var duration = float(command.get("duration", 0))
			if elapsed + 0.000001 < start or (duration > 0 and elapsed > start + duration): continue
			if not _conditions(command.get("conditions", []), bool(command.get("all", true))): continue
			var raw = _read_raw_json(str(command.get("raw", "{}")))
			if not raw is Dictionary or not _interrupt_conditions(raw): continue
			var next = _action(str(enemy.group), str(command.get("target", "")))
			if next.is_empty(): continue
			_start(next, 0)
			if visited.has(current_action): return
			visited[current_action] = true
			changed = true
			break
		if not changed: return
	_report("Enemy action transition budget exceeded: %s" % enemy_id)
