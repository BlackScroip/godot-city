extends RefCounted

var hits := 0
var damage := 0.0
var elapsed := 0.0

func reset() -> void:
	hits = 0
	damage = 0.0
	elapsed = 0.0

func record(impact: Dictionary, player_key: String) -> void:
	if player_key.is_empty() or str(impact.get("source_key", "")) != player_key: return
	if not str(impact.get("receiver_key", "")).begins_with("enemy:"): return
	var settled := maxf(0.0, float(impact.get("resolved_damage", 0.0)))
	if not bool(impact.get("resolved_accepted", false)) or settled <= 0.0: return
	hits += 1
	damage += settled

func advance(delta: float, fighting: bool) -> void:
	if fighting and hits > 0: elapsed += maxf(0.0, delta)

func dps() -> float:
	return damage / maxf(1.0, elapsed)

func snapshot() -> Dictionary:
	return {"hits": hits, "damage": damage, "elapsed": elapsed}

func restore(saved: Dictionary) -> void:
	hits = maxi(0, int(saved.get("hits", 0)))
	damage = maxf(0.0, float(saved.get("damage", 0.0)))
	elapsed = maxf(0.0, float(saved.get("elapsed", 0.0)))
