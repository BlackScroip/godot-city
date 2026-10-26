extends DungeonCombat

func enemy_navigation_requested() -> bool:
	if enemy.is_empty() or health <= 0: return false
	var elapsed = action_elapsed * maxf(0.01, float(custom_properties.get("_feel_action_speed", 1)))
	var definition = _action(str(enemy.group), current_action)
	for command in definition.get("events", []):
		if not command.get("enabled", false) or command.get("type", "") != "EET_Navigation": continue
		var start = float(command.get("time", 0))
		if elapsed >= start and elapsed < start + float(command.get("duration", 0)): return true
	return current_action.to_lower() in ["run", "forward", "dash", "running", "meaninglessrun"]
