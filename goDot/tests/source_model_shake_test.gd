extends SceneTree

const SourceImpact = preload("res://scripts/presentation/source_heavy_impact.gd")
const Feedback = preload("res://scripts/presentation/hit_feedback.gd")

class Recorder extends Node:
	var spawned := 0
	var active: Array = []
	func _summon_style(_actor: Node3D, _name: String, _point: Vector3, _scale: Vector3, _source_only: bool) -> void:
		pass
	func play_sound(_name: String, _point: Vector3, _actor: Node3D, _sequence: int, _gain: float, _pitch: float, _priority: bool) -> void:
		pass

var checks := 0
var failures: Array[String] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var actor := DungeonActor.new()
	root.add_child(actor)
	actor.set_process(false)
	actor.set_visual("")
	_clock_and_samples(actor)
	_isolation(actor)
	_admission(actor)
	_lifecycle(actor)
	actor.free()
	var result := {"apk_sha256": "ee8c917ab487ddeab4109d400d6d8b2036ef80f35fef952b78895819d1551505", "checks": checks, "failures": failures, "scope": "Source HitAction model shake: authored gate, local XZ offsets, native strict render-clock steps and visual lifecycle isolation."}
	FileAccess.open("res://reports/source-model-shake-tests.json", FileAccess.WRITE).store_string(JSON.stringify(result, "\t") + "\n")
	print("SOURCE_MODEL_SHAKE ", JSON.stringify(result))
	for failure in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)

func _clock_and_samples(actor: DungeonActor) -> void:
	actor._model_shake_rng.seed = 104
	actor.simulation_scale = 0.12
	actor.start_source_model_shake()
	check(actor._model_shake_root.position == Vector3.ZERO and actor._model_shake_count == 0, "The hit arms feedback without inventing an immediate native sample")
	actor._process(0.02)
	check(actor._model_shake_count == 0, "Exactly 0.02 seconds does not cross the native strict interval")
	actor._process(0.0001)
	check(actor._model_shake_count == 1, "The first render frame beyond 0.02 seconds samples even during 0.12 battle hit stop")
	for index in 4:
		var offset := actor._model_shake_root.position
		check((is_equal_approx(offset.x, -0.05) or is_zero_approx(offset.x)) and (is_equal_approx(offset.z, -0.05) or is_zero_approx(offset.z)) and is_zero_approx(offset.y), "Source sample %d retains integer -1/0 XZ offsets at intensity 0.05" % index)
		actor._process(0.021)
	check(actor._model_shake_active and actor._model_shake_count == 5, "Five native samples remain active until the next interval")
	actor._process(0.021)
	check(not actor._model_shake_active and actor._model_shake_root.position == Vector3.ZERO, "The sixth interval restores the original model position")
	actor.start_source_model_shake()
	actor._process(0.2)
	check(actor._model_shake_count == 1 and is_zero_approx(actor._model_shake_elapsed), "A slow frame samples once and drops the excess elapsed time as the APK does")
	var offset := actor._model_shake_root.position
	actor.start_source_model_shake()
	check(actor._model_shake_count == 0 and actor._model_shake_root.position == offset, "Repeated hit restarts the count while retaining the current sample until the next update")
	actor._process(0.02)
	check(actor._model_shake_count == 0, "Restarted feedback observes the full strict interval")
	actor.clear_impact_state()
	actor.simulation_scale = 1.0

func _isolation(actor: DungeonActor) -> void:
	actor.position = Vector3(4, 2, 6)
	actor.velocity = Vector3(2, 0, 3)
	actor.visual.position = Vector3(0.3, 0.4, 0.5)
	actor.visual.rotation = Vector3(0.1, 0.2, 0.3)
	actor.action_cursor = 0.4
	var body_transform := actor.transform
	var visual_transform := actor.visual.transform
	var layers := Vector2i(actor.collision_layer, actor.collision_mask)
	seed(772)
	var expected_random := randi()
	seed(772)
	actor.start_source_model_shake()
	actor._advance_source_model_shake(0.03)
	check(randi() == expected_random, "Visual feedback consumes no values from the shared gameplay random sequence")
	check(actor.transform == body_transform and actor.velocity == Vector3(2, 0, 3) and Vector2i(actor.collision_layer, actor.collision_mask) == layers, "Feedback leaves physics transform, velocity and collision untouched")
	check(actor.visual.transform == visual_transform and is_equal_approx(actor.action_cursor, 0.4), "Feedback leaves the animated model transform and attack timeline untouched")
	var animated_position := Vector3(0.7, 1.2, 0.9)
	actor.visual.position = animated_position
	actor._advance_source_model_shake(0.03)
	check(actor.visual.position == animated_position, "A new animated or transfer position survives the next shake sample")
	actor.clear_impact_state()
	check(actor.visual.position == animated_position and actor._model_shake_root.position == Vector3.ZERO, "Clearing feedback restores only its own offset and preserves the animated pose")

func _admission(actor: DungeonActor) -> void:
	var source := DungeonActor.new()
	var recorder := Recorder.new()
	var feedback := Feedback.normalize({"FeedbackList": [{"FeedbackType": "EHT_HitAction", "IsApplyModelShakeEffect": true}]})
	var hit := {"profile": {"source_feedback": feedback}, "definition": {"raw": "invalid, unused raw payload"}, "resolved_accepted": true}
	var before := JSON.stringify(feedback)
	SourceImpact.present(recorder, source, actor, hit, Vector3.ZERO)
	check(actor._model_shake_active, "An accepted authored model-shake flag reaches the actor through source presentation")
	check(JSON.stringify(feedback) == before, "Presentation reuses normalized source feedback without changing the cached payload")
	actor.clear_impact_state()
	hit.resolved_accepted = false
	SourceImpact.present(recorder, source, actor, hit, Vector3.ZERO)
	check(not actor._model_shake_active, "A rejected hit cannot start model shake")
	hit.resolved_accepted = true
	hit.profile.source_feedback = Feedback.normalize({"FeedbackList": [{"FeedbackType": "EHT_HitAction", "IsApplyModelShakeEffect": false}]})
	SourceImpact.present(recorder, source, actor, hit, Vector3.ZERO)
	check(not actor._model_shake_active, "An explicit disabled source flag creates no substitute model shake")
	SourceImpact.present(recorder, source, actor, {"definition": {}}, Vector3.ZERO)
	check(not actor._model_shake_active, "Missing authored feedback creates no model shake")
	source.free()
	recorder.free()

func _lifecycle(actor: DungeonActor) -> void:
	actor.start_source_model_shake()
	actor._process(0.03)
	actor.suspended = true
	check(not actor._model_shake_active and actor._model_shake_root.position == Vector3.ZERO, "Suspending an actor clears the offset immediately before the next render")
	actor.start_source_model_shake()
	actor._process(0.2)
	check(not actor._model_shake_active and actor._model_shake_root.position == Vector3.ZERO, "Suspended actors do not start or advance model shake")
	actor.suspended = false
	actor.start_source_model_shake()
	actor._process(0.03)
	actor.begin_death()
	check(not actor._model_shake_active and actor._model_shake_root.position == Vector3.ZERO, "Death restores the unshifted model before playing its death animation")
	actor.start_source_model_shake()
	check(not actor._model_shake_active, "Dead actors reject model-shake starts")
	actor.dead = false
	actor.start_source_model_shake()
	actor._process(0.03)
	actor.set_visual("")
	check(not actor._model_shake_active and actor._model_shake_root.position == Vector3.ZERO and actor.visual.position == Vector3.ZERO, "Changing the model cannot carry the previous model's visual displacement")
