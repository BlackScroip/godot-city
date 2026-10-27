extends RefCounted

# Source dispatch and integer bounds: reports/APK_BREAKABLE_RULES.md.
const MATERIALS := {"10017": 10101, "10018": 10102, "10027": 10201, "10028": 10202,
	"10037": 10301, "10038": 10302, "10047": 10401, "10048": 10402, "10057": 10501}
var systems
var random: Callable

func _init(owner, random_source: Callable = Callable()) -> void:
	systems = owner
	random = random_source if random_source.is_valid() else owner.next_random

func _roll(limit: int) -> int:
	return clampi(int(random.call(maxi(1, limit))), 0, maxi(0, limit - 1))

func _entry(result: Array, id: int, amount: int, direct := false, material := true) -> void:
	if id > 0 and amount > 0:
		result.append({"id": id, "amount": amount, "material": material, "direct": direct})

func _lode_amount(base: float, factor: float, spread: float) -> int:
	return int(base * (1.0 + int(factor) / 1000.0) * (1.0 + _roll(maxi(0, int(spread)) + 1) / 1000.0))

func destroyable(config_id: String, attrs: Dictionary = {}, source_flags: Dictionary = {}) -> Array:
	var result: Array = []
	if not config_id.is_valid_int(): return result
	var double_roll := 1 + _roll(1000)
	if MATERIALS.has(config_id):
		var count := 2 if source_flags.get("collecting_materials_double", false) else 1
		if double_roll <= float(attrs.get("CollectingMaterialsDoubleProbability", 0)): count *= 2
		_entry(result, int(MATERIALS[config_id]), count, true)
		return result
	match config_id:
		"70001":
			var base := float(systems.catalog.config.get("GoldLodeDropBaseAmount", 0)) + float(attrs.get("GoldLodeDropBaseAmount", 0))
			var count := _lode_amount(base, float(attrs.get("GoldLodeDropFactor", 0)), 500.0 + float(attrs.get("GoldLodeDropRandomFactor", 0)))
			# This handler explicitly adds one to attribute1002, whose native baseline is1000.
			count = int(count * (2.0 + float(attrs.get("DropGoldFactor", 0)) / 1000.0))
			if source_flags.get("gold_lode_quadruple", false): count *= 4
			_entry(result, 101, count)
		"70002":
			var base := float(systems.catalog.config.get("MagicPointLodeDropBaseAmount", 0)) + float(attrs.get("MagicPointLodeDropBaseAmount", 0))
			_entry(result, 102, _lode_amount(base, float(attrs.get("MagicPointLodeDropFactor", 0)), 500.0 + float(attrs.get("MagicPointLodeDropRandomFactor", 0))))
		"10003":
			_entry(result, 101, 1 + _roll(3))
			if _roll(1001) < float(attrs.get("DestroyableDropMagicPointChance", 0)):
				_entry(result, 102, _lode_amount(20.0 + float(attrs.get("DestroyableDropMagicPointBaseAmount", 0)), float(attrs.get("DestroyableDropMagicPointFactor", 0)), 500.0 + float(attrs.get("DestroyableDropMagicPointRandomFactor", 0))))
			if 1 + _roll(1000) <= float(attrs.get("DestroyableDropRecoverRate", 0)):
				for id in systems.roll_pool(int(systems.catalog.config.get("DefaultRecoverItemLootPoolId", 0)), 1):
					_entry(result, int(id), 1, false, false)
		"70003":
			# Attribute 1300 updates the persistent wallet immediately; no pickup is spawned.
			_entry(result, 106, 1, true)
			result.append({"counter": "EatGoldAppleCount", "amount": 1, "direct": true})
		_:
			if _roll(1001) <= 100: _entry(result, 101, 1 + _roll(3))
	return result
