extends SceneTree

const Effect = preload("res://scripts/presentation/authored_effect.gd")
const SourceMaterial = preload("res://scripts/presentation/recovered_effect_material.gd")
const MATERIAL_ID := "CAB-e355e6b0d05ab47d2012d0e8ccc2b413:6028709936780744974"
const EFFECT_ID := "26071801_fx_enemy_mojiehua_attack3_duyejidang"
const LAYER_ID := "26070901_shoubuxuli_xingxing"
const SRP_SHADER := "AllIn1Vfx/AllIn1VfxSRPBatch"

var checks := 0
var failures: Array[String] = []
var layer_counts := {}

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)

func _uses_additive_shader(material: ShaderMaterial) -> bool:
	return material.shader != null and "blend_add" in material.shader.code and not "blend_mix" in material.shader.code

func _check_blend_selection() -> void:
	var cases := [
		{"shader": SRP_SHADER, "floats": {"_SrcMode": 1, "_DstMode": 1}, "blend": "unknown", "expected": "add"},
		{"shader": SRP_SHADER, "floats": {"_SrcMode": 1.0, "_DstMode": 1.0}, "blend": "alpha", "expected": "add"},
		{"shader": SRP_SHADER, "floats": {"_SrcMode": 1, "_DstMode": 0}, "blend": "alpha", "expected": "alpha"},
		{"shader": SRP_SHADER, "floats": {"_SrcMode": 0, "_DstMode": 1}, "blend": "alpha", "expected": "alpha"},
		{"shader": SRP_SHADER, "floats": {"_SrcMode": 1, "_DstMode": 1.01}, "blend": "unknown", "expected": "unknown"},
		{"shader": SRP_SHADER, "floats": {"_SrcMode": 1}, "blend": "alpha", "expected": "alpha"},
		{"shader": SRP_SHADER, "floats": {"_DstMode": 1}, "blend": "add", "expected": "add"},
		{"shader": "AllIn1Vfx/Particle", "floats": {"_SrcMode": 1, "_DstMode": 1}, "blend": "alpha", "expected": "alpha"},
		{"shader": "Other/Shader", "floats": {"_SrcMode": 1, "_DstMode": 1}, "blend": "unknown", "expected": "unknown"},
		{"shader": "Other/Shader", "floats": {"_SrcMode": 1, "_DstMode": 0}, "blend": "add", "expected": "add"},
	]
	for index in cases.size():
		var item: Dictionary = cases[index]
		var source := {"shader": item.shader, "source_floats": item.floats, "blend": item.blend}
		check(SourceMaterial.blend_mode(source) == item.expected, "Case %d selects only the expected blend" % index)
		var material: ShaderMaterial = SourceMaterial.create(source, {})
		check(_uses_additive_shader(material) == (item.expected == "add"), "Case %d creates the expected shader variant" % index)
	check(SourceMaterial.blend_mode({"shader": SRP_SHADER, "blend": "alpha"}) == "alpha", "Missing blend inputs preserve authored blend")
	check(SourceMaterial.blend_mode({}) == "", "Missing blend metadata preserves the original empty default")

func _check_authored_effect() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/combat_presentation/catalog.json"))
	check(parsed is Dictionary, "Effect catalog is readable")
	if not parsed is Dictionary: return
	var definition: Dictionary = parsed.get("effects", {}).get(EFFECT_ID, {})
	check(not definition.is_empty(), "Flower boss poison effect exists")
	if definition.is_empty(): return
	var library: Dictionary = Effect.material_library(definition)
	var source: Dictionary = library.get(MATERIAL_ID, {})
	check(not source.is_empty(), "The actual effect resolves the confirmed APK material")
	if source.is_empty(): return
	check(str(source.get("shader", "")) == SRP_SHADER, "Confirmed material uses the SRP batch shader")
	check(source.get("source_floats", {}).get("_SrcMode") == 1 and source.get("source_floats", {}).get("_DstMode") == 1, "Confirmed material has One/One mode values")
	check(source.get("source_floats", {}).get("_DstBlend") == 0, "Saved destination blend differs from the source pass mode")
	check(SourceMaterial.blend_mode(source) == "add", "Confirmed APK material is additive despite its legacy blend marker")
	var found_layer := false
	for layer in Effect.resolved_layers(definition):
		if str(layer.get("name", "")) != LAYER_ID: continue
		found_layer = true
		var materials: Array = layer.get("materials", [])
		check(not materials.is_empty() and str(materials[0].get("source", "")) == MATERIAL_ID, "Actual flare layer resolves the confirmed material")
	check(found_layer, "Actual flare layer exists in the effect")
	for low in [false, true]:
		var effect := Effect.new()
		root.add_child(effect)
		effect.configure(definition, low, {})
		var matching := 0
		for emitter in effect.emitters:
			var node: Node3D = emitter.node
			if str(node.get_parent().get_meta("source_layer", "")) != LAYER_ID: continue
			matching += 1
			var shader_material := node.material_override as ShaderMaterial
			check(shader_material != null and _uses_additive_shader(shader_material), "Authored flare uses additive shader in %s quality" % ("low" if low else "full"))
			check(shader_material != null and shader_material.get_shader_parameter("source_shapes") == true, "Authored flare keeps source-shape texture path")
		layer_counts["low" if low else "full"] = matching
		if not low: check(matching > 0, "Authored flare layer is emitted in full quality")
		effect.free()

func _run() -> void:
	_check_blend_selection()
	_check_authored_effect()
	print("BOSS_SRP_ADDITIVE ", JSON.stringify({"passed": failures.is_empty(), "checks": checks, "failures": failures, "authored_flare_emitters": layer_counts, "scope": "APK-derived blend selection and the configured flower boss flare layer; rendering equivalence is tested separately. The reduced-quality layer count may be zero under its budget."}))
	quit(0 if failures.is_empty() else 1)
