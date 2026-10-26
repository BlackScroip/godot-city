extends RefCounted

const COMBO_KEEP_SECONDS := 2.0

var hits := 0
var damage := 0.0
var elapsed := 0.0
var combo_hits := 0
var combo_damage := 0.0
var combo_elapsed := 0.0
var combo_remaining := 0.0
var combo_sequence := 0

func reset() -> void:
	hits = 0
	damage = 0.0
	elapsed = 0.0
	combo_sequence = 0
	clear_combo()

func record(impact: Dictionary, player_key: String) -> void:
	if player_key.is_empty() or str(impact.get("source_key", "")) != player_key: return
	if not str(impact.get("receiver_key", "")).begins_with("enemy:"): return
	var settled := maxf(0.0, float(impact.get("resolved_damage", 0.0)))
	if not bool(impact.get("resolved_accepted", false)) or settled <= 0.0: return
	hits += 1
	damage += settled
	if combo_hits == 0:
		combo_sequence += 1
	combo_hits += 1
	combo_damage += settled
	combo_remaining = COMBO_KEEP_SECONDS

func advance(delta: float, fighting: bool, running: bool = true) -> void:
	if not running: return
	var step := maxf(0.0, delta)
	if fighting and hits > 0: elapsed += step
	if combo_hits == 0: return
	combo_elapsed += minf(step, combo_remaining)
	combo_remaining = maxf(0.0, combo_remaining - step)
	if combo_remaining <= 0.0: clear_combo()

func clear_combo() -> void:
	combo_hits = 0
	combo_damage = 0.0
	combo_elapsed = 0.0
	combo_remaining = 0.0

func combo_dps() -> float:
	return combo_damage / maxf(1.0, combo_elapsed)

func dps() -> float:
	return damage / maxf(1.0, elapsed)

func snapshot() -> Dictionary:
	var saved := {"hits": hits, "damage": damage, "elapsed": elapsed}
	if combo_hits > 0:
		saved["combo"] = {"hits": combo_hits, "damage": combo_damage, "elapsed": combo_elapsed,
			"remaining": combo_remaining, "sequence": combo_sequence}
	return saved

func restore(saved: Dictionary) -> void:
	hits = maxi(0, int(saved.get("hits", 0)))
	damage = maxf(0.0, float(saved.get("damage", 0.0)))
	elapsed = maxf(0.0, float(saved.get("elapsed", 0.0)))
	clear_combo()
	combo_sequence = 0
	var combo: Dictionary = saved.get("combo", {}) if saved.get("combo", {}) is Dictionary else {}
	combo_remaining = clampf(float(combo.get("remaining", 0.0)), 0.0, COMBO_KEEP_SECONDS)
	combo_hits = clampi(int(combo.get("hits", 0)), 0, hits)
	combo_damage = clampf(float(combo.get("damage", 0.0)), 0.0, damage)
	combo_elapsed = maxf(0.0, float(combo.get("elapsed", 0.0)))
	combo_sequence = maxi(0, int(combo.get("sequence", 0)))
	if combo_hits == 0 or combo_damage <= 0.0 or combo_remaining <= 0.0: clear_combo()
