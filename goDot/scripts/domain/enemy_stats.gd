class_name DungeonEnemyStats
extends RefCounted

const DATA_PATH = "res://assets/data/EnemyNumericalConfigData.json"
static var _entries: Array = []

static func hp(base_hp: float, rank: String, difficulty: int, stage: int = 1, chaos: int = 0) -> float:
	# APK uses single-precision multiplication followed by Mathf.CeilToInt.
	var source_base = PackedFloat32Array([base_hp])[0]
	var multiplier = PackedFloat32Array([hp_multiplier(rank, difficulty, stage, chaos)])[0]
	return maxf(1.0, ceilf(PackedFloat32Array([source_base * multiplier])[0]))

static func hp_multiplier(rank: String, difficulty: int, stage: int = 1, chaos: int = 0) -> float:
	if _entries.is_empty():
		var data = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if data is Array and data.size() == 1: data = data[0]
		if data is Dictionary: _entries = data.get("entries", [])
	var key = 100 + chaos if difficulty == 10 and chaos > 0 else difficulty
	var index = clampi(stage, 1, 5) - 1
	var fallback: Dictionary = {}
	for entry in _entries:
		if str(entry.get("enemy_type", "")) != rank or str(entry.get("attr_type", "")) != "HP": continue
		var entry_key = int(entry.get("difficulty", -1))
		var values: Array = entry.get("stage_multipliers", [])
		if entry_key == key and values.size() > index: return maxf(0.01, float(values[index]))
		if entry_key < key and (fallback.is_empty() or entry_key > int(fallback.difficulty)): fallback = entry
	if not fallback.is_empty() and fallback.stage_multipliers.size() > index:
		return maxf(0.01, float(fallback.stage_multipliers[index]))
	return 1.0
