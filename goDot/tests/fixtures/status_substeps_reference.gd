extends DungeonCombat

# Original segment interpreter, including empty 0.01-second status substeps.
func _tick_segment(delta: float) -> void:
	action_tick_delta = delta
	if health <= 0:
		_emit_death()
		return
	var action_delta = maxf(0.0, delta - frozen)
	if not enemy.is_empty(): EnemyHitReaction.tick(self, delta)
	var held = minf(action_delta, maxf(impact_pause, stagger_remaining))
	action_step = maxf(0.0, action_delta - held)
	if FEEL.impact_enabled and not _using_heavy_graph() and bool(custom_properties.get("_rhythm_enabled", false)) and busy > 0:
		var phase = action_phase()
		var rate = 0.92 if phase == "windup" else 1.08 if phase == "impact" else 1.0
		var before = action_step
		action_step *= rate
		_recovery_credit += before - action_step
	if _compensate_pause and stagger_remaining <= 0 and not _using_heavy_graph(): _recovery_credit += minf(action_delta, impact_pause)
	if _using_heavy_graph() and busy > 0: action_step *= _player_action_rate()
	if not enemy.is_empty(): action_step = _enemy_action_advance(action_step)
	impact_pause = maxf(0.0, impact_pause - delta)
	stagger_remaining = maxf(0.0, stagger_remaining - delta)
	_impact_gate = maxf(0.0, _impact_gate - delta)
	_stagger_grace = maxf(0.0, _stagger_grace - delta)
	action_elapsed += action_step
	# Shift only the current action. Spawned payloads and status clocks stay live.
	var timeline_delay = action_delta - action_step
	if not is_zero_approx(timeline_delay):
		for scheduled in _pending:
			if _action_event(scheduled): scheduled.at += timeline_delay
	var was_busy = busy > 0
	frozen = maxf(0.0, frozen - delta)
	_slow_time = maxf(0.0, _slow_time - delta)
	_clock += action_delta
	if enemy_id == 23001 and enemy_phase() > 0 and not enemy_ai_enabled:
		var flight_timer = float(custom_properties.get("_flight_timer", 0)) + action_delta
		if flight_timer >= 60.0:
			flight_timer -= 60.0
			custom_properties["BB_IsFlyState"] = not bool(custom_properties.get("BB_IsFlyState", false))
			var phase_actions: Array = custom_properties.get("_enemy_phase_actions", [])
			phase_actions.append("attack3" if bool(custom_properties.BB_IsFlyState) else "attack6")
			custom_properties["_enemy_phase_actions"] = phase_actions
		custom_properties["_flight_timer"] = flight_timer
	busy = maxf(0.0, busy - action_step)
	var remaining_hit = false
	for scheduled in _pending:
		if _action_event(scheduled) and scheduled.has("hit") and float(scheduled.at) > _clock:
			remaining_hit = true
			break
	if not _using_heavy_graph() and not remaining_hit and not is_zero_approx(_recovery_credit):
		var compensation = minf(_recovery_credit, busy)
		busy -= compensation
		_recovery_credit -= compensation
	if was_busy and busy <= 0:
		notify_gameplay("action_end", {"slot": _current_slot, "action": current_action})
		if enemy_ai != null:
			enemy_ai.notify_action_ended(current_action)
			custom_properties["_enemy_ended_sequence"] = _cast_sequence
	invincible = maxf(0.0, invincible - delta)
	_dodge_time = maxf(0.0, _dodge_time - delta)
	_block_time = maxf(0.0, _block_time - delta)
	_anti_heal_time = maxf(0.0, _anti_heal_time - delta)
	if not fighter.is_empty():
		_dodge_recharge_elapsed += delta
		for slot in range(mini(5, fighter.skills.size())):
			cooldowns[slot] = maxf(0.0, float(cooldowns[slot]) - delta)
			var recovered = delta * 2.0 if slot == 2 else 0.0
			# APK grants the original max_sp per update after the last-use delay.
			if slot == 1 and delta > 0 and _dodge_recharge_elapsed + 0.000001 >= dodge_recharge_duration():
				recovered = float(fighter.skills[slot].maxSp)
			energy[slot] = minf(skill_capacity(slot), float(energy[slot]) + recovered)
	var remaining = delta
	while remaining > 0.000001:
		var step = minf(0.01, remaining)
		_tick_statuses(step)
		remaining -= step
	if charging:
		charge_elapsed += action_step
	_pending.sort_custom(_event_before)
	var guard = 0
	while not _pending.is_empty() and float(_pending[0].at) <= _clock + 0.0000001 and guard < 4096:
		guard += 1
		var event: Dictionary = _pending.pop_front()
		if health <= 0:
			continue
		if event.has("condition_effect"):
			_apply_condition_effect(event.condition_effect)
		elif event.has("funnel_trigger"):
			_trigger_funnel(event)
		elif event.has("funnel_emit"):
			_emit_funnel(event)
		elif event.has("hit"):
			_emit_hit(event)
		else:
			_execute(event)
		_pending.sort_custom(_event_before)
	if guard >= 4096:
		_report("Timeline event budget exceeded")
	_tick_attack_collision_gate()
	_expire_battle_time_scale_windows()
	if was_busy and _using_heavy_graph():
		_tick_heavy_interrupts()
	elif enemy.is_empty():
		_tick_movement_interrupts()
	if health <= 0:
		_emit_death()
