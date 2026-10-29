extends SceneTree

const Projectile = preload("res://scripts/domain/projectile.gd")
const Reference = preload("res://tests/fixtures/projectile_motion_reference.gd")

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _make_shot(definition: Dictionary):
	var shot = Projectile.new()
	shot.configure({"definition": definition}, Vector3.ZERO, Vector3.BACK, Vector3(2, 0, 6))
	return shot

func _run() -> void:
	var raw := {
		"EntityProperty": {"ColliderType": "Sphere", "ModelBoxColliderSize": {"x": 2.0}, "Nested": {"value": 1}},
		"MotionAnimatorType": "EMAT_Line",
		"MotionAnimatorProperty": {"Speed": 7.0, "Nested": {"value": 2}},
		"EffectActiveIntervalToEachUnit": 0.25,
		"EffectActiveTotalCountToEachUnit": 3
	}
	var encoded := JSON.stringify(raw)
	var event := {"definition": {"raw": encoded}}
	var reference = Reference.new()
	var shot = Projectile.new()
	reference.configure(event, Vector3.ZERO, Vector3.BACK, Vector3(2, 0, 6))
	shot.configure(event, Vector3.ZERO, Vector3.BACK, Vector3(2, 0, 6))
	check(reference.snapshot() == shot.snapshot(), "Cached string definition matches fresh JSON parsing")
	var other = _make_shot(event.definition)
	shot.entity.Nested.value = 100
	shot.motion.Nested.value = 200
	check(other.entity.Nested.value == 1 and other.motion.Nested.value == 2, "Projectile definition copies are independently mutable")
	check(DungeonWorld._read_definition(event.definition).EntityProperty.Nested.value == 1, "Mutable projectile state cannot contaminate the shared cache")
	var restored = Projectile.new()
	restored.restore(shot.snapshot())
	check(restored.entity.Nested.value == 100 and restored.motion.Nested.value == 200, "Restoring preserves the saved mutable projectile definition")
	check(is_equal_approx(restored.hit_interval, 0.25) and restored.hit_limit == 3, "Restoring preserves collision limits from the source definition")
	var dictionary_definition := {"raw": raw}
	var first = _make_shot(dictionary_definition)
	raw.EntityProperty.Nested.value = 9
	raw.MotionAnimatorProperty.Speed = 11.0
	var second = _make_shot(dictionary_definition)
	check(first.entity.Nested.value == 1 and is_equal_approx(first.speed, 7.0), "Dictionary definitions are copied at configuration time")
	check(second.entity.Nested.value == 9 and is_equal_approx(second.speed, 11.0), "Later dictionary edits are observed by new projectiles")
	first.entity.Nested.value = 99
	check(raw.EntityProperty.Nested.value == 9 and second.entity.Nested.value == 9, "Dictionary input and other projectiles remain independent")
	var non_object_json = _make_shot({"raw": "null"})
	var non_dictionary = _make_shot({"raw": [1, 2, 3]})
	check(non_object_json.entity.is_empty() and non_object_json.motion.is_empty(), "Non-object JSON uses empty defaults")
	check(non_dictionary.entity.is_empty() and non_dictionary.motion.is_empty(), "Non-dictionary input uses empty defaults")
	print("PROJECTILE_DEFINITION_CACHE ", JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
