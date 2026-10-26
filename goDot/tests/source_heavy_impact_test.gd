extends SceneTree

const Combat = preload("res://scripts/domain/combat.gd")
const Profiles = preload("res://scripts/presentation/impact_profiles.gd")
const SourceImpact = preload("res://scripts/presentation/source_heavy_impact.gd")
const Feedback = preload("res://scripts/presentation/hit_feedback.gd")

class ActorStub extends Node3D:
	var combat: RefCounted
	func impact_anchor(point: Vector3) -> Vector3:
		return point

class Recorder extends Node:
	var spawned := 0
	var active: Array = []
	var effects: Array = []
	var sounds: Array = []
	func _summon_style(_actor: Node3D, name: String, point: Vector3, dimensions: Vector3, source_only: bool) -> void:
		var effect := Node3D.new()
		add_child(effect)
		active.append({"root": effect})
		effects.append({"name": name, "point": point, "scale": Vector3.ONE if dimensions.is_zero_approx() else dimensions, "source_only": source_only})
		spawned += 1
	func play_sound(name: String, point: Vector3, _actor: Node3D, _sequence: int, gain: float, pitch: float, priority: bool) -> void:
		sounds.append({"name": name, "point": point, "gain": gain, "pitch": pitch, "priority": priority})

var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _initialize() -> void:
	_classification()
	_source_payloads()
	_presentation()
	var result := {"apk_sha256": "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505", "checks": checks, "failures": failures, "scope": "Source-heavy provenance, neutral FEEL profile and original presentation payloads; no native hit-stop/push conversion asserted."}
	var report := FileAccess.open("res://reports/source-heavy-impact-tests.json", FileAccess.WRITE)
	if report: report.store_string(JSON.stringify(result, "\t") + "\n")
	print("SOURCE_HEAVY_IMPACT ", JSON.stringify(result))
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _classification() -> void:
	var source := Combat.new()
	source.configure()
	check(source.get("_heavy_catalog") is Dictionary and source.get("_heavy_catalog").get("actions", {}).size() == 30, "Source-heavy lookup reuses the configured combat catalog without hit-time file I/O")
	var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/heavy_attacks.json"))
	source._current_slot = 0
	source.current_action = "sword_atk1"
	for action in metadata.actions:
		var hit := {"action": action, "slot": 0, "sequence": source._cast_sequence - 1, "definition": {}}
		check(Profiles.is_source_heavy(hit, source), "%s delayed record retains source-heavy identity after owner action changes" % action)
	check(Profiles.is_source_heavy({"slot": 4, "action": "", "ranged": true}, source), "A delayed slot-four projectile retains its source identity")
	check(Profiles.is_source_heavy({"slot": 0, "action": "summon_attack", "source_heavy": true, "summon_id": "6000111"}, source), "A derived summon retains explicit source-heavy lineage")
	check(Profiles.is_source_heavy({"slot": 0, "action": "sword_atk1", "origin": {"_source_heavy": true}, "summon_id": "6000111"}, source), "A delayed child retains heavy provenance in its original emission origin")
	check(Profiles.is_source_heavy({"source": source, "source_heavy": true}), "Captured owner is usable without a live world actor lookup")
	check(Profiles.is_source_heavy({"source_key": "player", "source_heavy": true}), "Detached player lineage is usable without consulting a current action")
	source._current_slot = 4
	source.current_action = "sword_satk_normal_ready"
	check(not Profiles.is_source_heavy({"slot": 0, "action": "sword_atk1"}, source), "An earlier normal hit does not inherit the owner's later heavy input")
	check(not Profiles.is_source_heavy({"slot": 0, "summon_id": "6000111"}, source), "An unrelated summon does not inherit the owner's current heavy input")
	check(not Profiles.is_source_heavy({"source_heavy": true}), "Heavy lineage without player ownership does not classify an enemy hit")
	var enemy := Combat.new()
	enemy.configure_enemy(int(source.catalog.enemies[0].id))
	check(not Profiles.is_source_heavy({"slot": 4, "action": "axe_satk_end", "source_heavy": true, "source_key": "player"}, enemy), "An enemy owner cannot be classified as a player heavy by slot, name or stale lineage")
	var raw_hit: Dictionary = source._action("ActGroup_playerchara", "axe_satk_end").hits[0]
	var hit := {"slot": 4, "action": "axe_satk_end", "definition": raw_hit, "summon_id": "6000111", "resolved_critical": true}
	var original := JSON.stringify(hit)
	var profile := Profiles.resolve(hit, source)
	check(profile.get("source_only", false) and profile.get("source_heavy", false), "Source heavy profile provides an explicit integration guard")
	for field in ["stop", "shake", "amplitude", "distance", "travel", "stagger", "flash"]:
		check(is_zero_approx(float(profile[field])), "Source heavy %s has no custom FEEL contribution" % field)
	check(profile.scale == 1.0 and profile.gain == 1.0 and profile.category == "source", "Critical and explosion overrides cannot recolor or enlarge a source heavy")
	check(profile.source_feedback == Feedback.normalize(raw_hit), "Source weights, forces and ratios remain unchanged in the resolved profile")
	check(JSON.stringify(hit) == original, "Source heavy profile resolution does not rewrite the emitted hit")
	var normal := Profiles.resolve({"slot": 0, "action": "sword_atk1"}, source)
	check(not normal.get("source_only", false) and normal.stop > 0, "Existing normal-hit behavior is outside this scoped correction")

func _source_payloads() -> void:
	var source := Combat.new()
	source.configure()
	var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/heavy_attacks.json"))
	var checked_hits := 0
	for action in metadata.actions:
		for definition in source._action("ActGroup_playerchara", action).hits:
			if not definition.enabled: continue
			checked_hits += 1
			var original := Feedback.normalize(definition)
			var plan := SourceImpact.collect({"definition": definition}, source)
			var names: Array = []
			for effect in original.hit_effects:
				if not str(effect.get("Effect", "")).is_empty(): names.append(effect.Effect)
			check(plan.effects.map(func(effect): return effect.name) == names, "%s emits exactly the nonempty source hit effects" % action)
			for effect in plan.effects:
				var raw: Dictionary = effect.raw
				check(raw.Effect is String and raw.EffectScale is Dictionary and raw.EffectOffsetRotate is Dictionary and raw.IsSpeedScaleByOwnerStopTick is bool, "%s source effect retains all serialized field types" % action)
				var scale := Vector3(float(raw.EffectScale.x), float(raw.EffectScale.y), float(raw.EffectScale.z))
				check(effect.scale.is_equal_approx(Vector3.ONE if scale.is_zero_approx() else scale), "%s zero scale keeps the prefab default while explicit scale remains authored" % action)
				check(effect.rotation.is_equal_approx(Vector3(float(raw.EffectOffsetRotate.x), float(raw.EffectOffsetRotate.y), float(raw.EffectOffsetRotate.z))), "%s source effect keeps its complete rotation payload" % action)
			var sounds: Array = []
			for sound in original.hit_sounds:
				var name := str(sound.get("HitSoundDef", {}).get("SoundName", ""))
				if not name.is_empty(): sounds.append(name)
			check(plan.sounds == sounds, "%s emits exactly the source sound definitions without fallback" % action)
			check(plan.hit_stops == original.hit_stops and plan.hit_actions == original.hit_actions and plan.material_flashes == original.material_flashes, "%s retains unconverted source feedback fields" % action)
			check(plan.camera_shakes == original.camera_shakes, "%s retains source hit-camera parameters independently of FEEL" % action)
	check(checked_hits == 26, "All 26 enabled source heavy hit definitions were checked")
	var summon: Dictionary = source._summon_index["6000111"]
	var plan := SourceImpact.collect({"summon_id": "6000111", "definition": summon.hit}, source)
	var original := Feedback.normalize(summon.hit)
	check(plan.effects.size() == original.hit_effects.filter(func(effect): return not str(effect.get("Effect", "")).is_empty()).size(), "Delayed summon uses its own serialized hit feedback")
	for id in source._summon_index:
		var raw: Dictionary = source._summon_index[id].get("raw_data", {})
		if str(raw.get("HitEffect", "")).is_empty() and str(raw.get("HitEffect_UnitCenter", "")).is_empty() and str(raw.get("HitSound", "")).is_empty(): continue
		var summon_plan := SourceImpact.collect({"summon_id": id, "definition": {}}, source)
		var expected_effects: Array = []
		for field in ["HitEffect", "HitEffect_UnitCenter"]:
			if not str(raw.get(field, "")).is_empty(): expected_effects.append(raw[field])
		check(summon_plan.effects.map(func(effect): return effect.name) == expected_effects, "Summon %s retains only its authored contact and center effects" % id)
		var expected_sounds: Array = []
		if not str(raw.get("HitSound", "")).is_empty(): expected_sounds.append(raw.HitSound)
		check(summon_plan.sounds == expected_sounds, "Summon %s retains only its authored hit sound" % id)
	check(SourceImpact.collect({"definition": {}}, source).effects.is_empty() and SourceImpact.collect({"definition": {}}, source).sounds.is_empty(), "Empty source payload produces no substitute effect or sound")

func _presentation() -> void:
	var source := Combat.new()
	source.configure(null, null, 2)
	var definition: Dictionary = {}
	for hit in source._action("ActGroup_playerchara", "sickle_satk").hits:
		for effect in Feedback.normalize(hit).hit_effects:
			if float(effect.get("EffectScale", {}).get("x", 0)) > 1.0:
				definition = hit
				break
		if not definition.is_empty(): break
	check(not definition.is_empty(), "Presentation regression uses a real source effect with explicit scale and rotation")
	if definition.is_empty(): return
	var actor := ActorStub.new()
	actor.combat = source
	var target := ActorStub.new()
	var recorder := Recorder.new()
	var hit := {"slot": 4, "action": "sickle_satk", "definition": definition}
	var plan := SourceImpact.collect(hit, source)
	var point := Vector3(2, 3, 4)
	SourceImpact.present(recorder, actor, target, hit, point)
	check(recorder.effects.size() == plan.effects.size() and recorder.sounds.size() == plan.sounds.size(), "Runtime source presentation emits only its collected source entries")
	for index in plan.effects.size():
		check(recorder.effects[index].source_only, "Runtime source effect bypasses fallback graphics and material gain overrides")
		check(recorder.effects[index].name == plan.effects[index].name and recorder.effects[index].scale.is_equal_approx(plan.effects[index].scale), "Runtime source effect retains serialized name and scale")
		check(recorder.active[index].root.rotation.is_equal_approx(plan.effects[index].rotation * PI / 180.0), "Runtime source effect retains serialized rotation")
	for sound in recorder.sounds:
		check(sound.gain == 1.0 and sound.pitch == 1.0, "Source audio does not inherit custom heavy gain or pitch")
	recorder.free()
	actor.free()
	target.free()
