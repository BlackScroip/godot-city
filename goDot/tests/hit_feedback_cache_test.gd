extends SceneTree

const Feedback = preload("res://scripts/presentation/hit_feedback.gd")
const Profiles = preload("res://scripts/presentation/impact_profiles.gd")
var checks := 0
var failures: Array[String] = []
var definitions: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func _reset_cache() -> void:
	Feedback._cache.clear()
	Feedback._cache_keys.clear()
	Feedback._cache_cursor = 0

func _collect(value: Variant) -> void:
	if value is Dictionary:
		if value.get("raw") is String: definitions.append(value)
		for child in value.values(): _collect(child)
	elif value is Array:
		for child in value: _collect(child)

func _run() -> void:
	_reset_cache()
	for path in ["res://assets/data/combat.json", "res://assets/data/heavy_attacks.json"]:
		_collect(JSON.parse_string(FileAccess.get_file_as_string(path)))
	check(not definitions.is_empty(), "Parity checks cover packaged combat and heavy definitions")
	var with_feedback := 0
	for definition in definitions:
		var parsed: Variant = JSON.parse_string(definition.raw)
		var original: Dictionary = parsed if parsed is Dictionary else {}
		# A dictionary input follows the uncached normalization path retained by the API.
		var expected := Feedback.normalize({"raw": original})
		check(Feedback.read(definition) == expected, "Cached feedback preserves source definition " + str(definition.get("id", definition.get("type", ""))))
		check(DungeonWorld._raw_definition(definition) == original, "Cached world payload preserves every raw field")
		if original.get("FeedbackList", []).size() > 0: with_feedback += 1
	check(with_feedback > 0, "Parity checks include authored hit feedback")
	_check_ownership()
	_check_changes()
	_check_capacity()
	var benchmark: Dictionary = _benchmark() if "--benchmark" in OS.get_cmdline_user_args() else {}
	var report := {"checks": checks, "failures": failures, "passed": failures.is_empty(), "definitions": definitions.size(), "with_feedback": with_feedback, "benchmark": benchmark, "scope": "Cached and uncached source payload parity, independent mutable API results, recursive read-only sharing, dynamic dictionary inputs, FIFO eviction; optional CPU-only microbenchmark."}
	FileAccess.open("res://reports/hit-feedback-cache-tests.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("HIT_FEEDBACK_CACHE ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func _sample() -> Dictionary:
	return {"FeedbackList": [{"FeedbackType": "EHT_HitStopFrame", "StopFrameWeight": 0.3, "SelfAffectedRatio": 0.5}, {"FeedbackType": "EHT_HitEffect", "Effect": "source.prefab", "EffectScale": {"x": 1.0, "y": 2.0, "z": 3.0}}, {"FeedbackType": "EHT_Unknown", "Values": [{"value": 9}]}], "MotionAnimatorType": "EMAT_Line", "Nested": {"values": [1, {"value": 2}]}}

func _check_ownership() -> void:
	var source := _sample()
	var definition := {"raw": JSON.stringify(source)}
	var shared := Feedback.read(definition)
	check(shared.is_read_only() and shared.hit_effects.is_read_only() and shared.hit_effects[0].EffectScale.is_read_only(), "Shared feedback is recursively read-only")
	check(shared.unknown[0].Values[0].is_read_only(), "Unknown source fields are protected inside shared payloads")
	check(is_same(shared, Feedback.read(definition)), "Repeated reads reuse the normalized payload")
	var copied := Feedback.normalize(definition)
	check(not copied.is_read_only() and not copied.hit_effects.is_read_only() and not copied.hit_effects[0].EffectScale.is_read_only(), "Legacy normalize returns mutable nested values")
	copied.hit_effects[0].EffectScale.x = 20.0
	copied.hit_stops.clear()
	check(Feedback.read(definition).hit_effects[0].EffectScale.x == 1.0 and Feedback.read(definition).hit_stops.size() == 1, "Legacy callers cannot contaminate cached feedback")
	var raw := Feedback.raw(definition)
	check(raw.is_read_only() and raw.Nested.values.is_read_only() and raw.Nested.values[1].is_read_only(), "Raw shared JSON is recursively read-only")
	var world_raw := DungeonWorld._raw_definition(definition)
	world_raw["FeedbackType"] = "EHT_CameraShake"
	world_raw.Nested.values[1].value = 400
	check(not DungeonWorld._raw_definition(definition).has("FeedbackType") and Feedback.raw(definition).Nested.values[1].value == 2, "World command edits keep both top-level and nested state private")
	check(Profiles.raw({"definition": definition}) == raw and Profiles.ranged({"definition": definition}), "Impact classification uses the same complete source payload")

func _check_changes() -> void:
	var mutable := _sample()
	var definition := {"raw": mutable}
	var before := Feedback.read(definition)
	mutable.FeedbackList[0].StopFrameWeight = 0.7
	mutable.Nested.values[1].value = 8
	check(not mutable.is_read_only() and not mutable.FeedbackList.is_read_only(), "Dictionary inputs remain writable by their owner")
	check(before.hit_stops[0].weight == 0.3 and Feedback.read(definition).hit_stops[0].weight == 0.7, "Dictionary feedback changes are visible on the next read without changing an earlier snapshot")
	check(Feedback.raw(definition).Nested.values[1].value == 8, "Dynamic raw dictionaries are never cached by identity")
	definition.raw = JSON.stringify(mutable)
	check(Feedback.read(definition).hit_stops[0].weight == 0.7, "Replacing a serialized definition selects its new cache entry")
	mutable.FeedbackList[0].StopFrameWeight = 0.9
	definition.raw = JSON.stringify(mutable)
	check(Feedback.read(definition).hit_stops[0].weight == 0.9, "A changed serialized value cannot reuse stale feedback")
	for value in ["{}", "null", "[]", "2", "\"text\"", "{\"FeedbackList\":null}", "{\"FeedbackList\":[null,3]}"]:
		var empty := Feedback.read({"raw": value})
		check(empty.hit_stops.is_empty() and empty.hit_effects.is_empty(), "Missing and non-dictionary source payloads remain empty")
	check(Feedback.read({}) == Feedback.normalize({}), "Absent raw payload preserves the rawless API")
	check(Feedback.read(_sample()).hit_stops[0].weight == 0.3, "Rawless feedback dictionaries keep their source fields")
	check(DungeonWorld._raw_definition({}).is_empty(), "Missing world raw payload remains empty")

func _check_capacity() -> void:
	_reset_cache()
	var first := JSON.stringify({"FeedbackList": [{"FeedbackType": "EHT_HitStopFrame", "StopFrameWeight": 0.4}]})
	var retained := Feedback.read({"raw": first})
	for index in Feedback.CACHE_CAPACITY:
		Feedback.read({"raw": JSON.stringify({"cache_test": index})})
	check(Feedback._cache.size() == Feedback.CACHE_CAPACITY and Feedback._cache_keys.size() == Feedback.CACHE_CAPACITY, "Both payload cache and FIFO metadata stay bounded")
	check(not Feedback._cache.has(first), "The oldest entry is evicted at capacity")
	check(retained.hit_stops[0].weight == 0.4, "Eviction preserves payloads still referenced by active hits")
	var rebuilt := Feedback.read({"raw": first})
	check(rebuilt == retained and not is_same(rebuilt, retained), "An evicted feedback definition is rebuilt without changing its content")
	check(Feedback._cache.size() == Feedback.CACHE_CAPACITY, "Rebuilding an entry cannot exceed the capacity")

func _benchmark() -> Dictionary:
	var samples: Array[Dictionary] = []
	var seen: Dictionary = {}
	for definition in definitions:
		if seen.has(definition.raw): continue
		seen[definition.raw] = true
		var parsed: Variant = JSON.parse_string(definition.raw)
		if not parsed is Dictionary or parsed.get("FeedbackList", []).is_empty(): continue
		samples.append(definition)
		if samples.size() == 24: break
	var rows: Array[Dictionary] = []
	for pass_index in 3:
		for definition in samples: Feedback.read(definition)
		var began := Time.get_ticks_usec()
		for repeat in 100:
			for definition in samples: Feedback.normalize({"raw": JSON.parse_string(definition.raw)})
		var uncached_ms := (Time.get_ticks_usec() - began) / 1000.0
		began = Time.get_ticks_usec()
		for repeat in 100:
			for definition in samples: Feedback.read(definition)
		var cached_ms := (Time.get_ticks_usec() - began) / 1000.0
		began = Time.get_ticks_usec()
		for repeat in 100:
			for definition in samples: JSON.parse_string(definition.raw)
		var raw_uncached_ms := (Time.get_ticks_usec() - began) / 1000.0
		began = Time.get_ticks_usec()
		for repeat in 100:
			for definition in samples: DungeonWorld._raw_definition(definition)
		var raw_cached_ms := (Time.get_ticks_usec() - began) / 1000.0
		rows.append({"pass": pass_index + 1, "calls": samples.size() * 100, "normalize_before_ms": uncached_ms, "read_cached_ms": cached_ms, "raw_parse_before_ms": raw_uncached_ms, "raw_copy_cached_ms": raw_cached_ms})
	return {"rows": rows, "samples": samples.size(), "scope": "Same 24 packaged attack feedback payloads, 100 repetitions per pass after cache warmup; CPU function cost only, not frame rate or device latency."}
