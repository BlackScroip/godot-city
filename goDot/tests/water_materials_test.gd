extends SceneTree

const RECOVERED = preload("res://scripts/presentation/recovered_environment.gd")
var failures: Array[String] = []
var checks := 0

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/environment_recovered/water_materials.json"))
	var scene := Node3D.new()
	root.add_child(scene)
	check(data.size() == 7, "All seven source water materials covered")
	for label: String in data:
		var source := StandardMaterial3D.new()
		source.resource_name = label
		var recovered: Material = RECOVERED.material(source)
		check(recovered is ShaderMaterial, label + " uses animated shader")
		var mesh := MeshInstance3D.new()
		mesh.mesh = PlaneMesh.new()
		mesh.material_override = recovered
		scene.add_child(mesh)
		var flow: Dictionary = data[label].colors.get("_FlowSpeed", data[label].colors.get("_GlobalSpeed", {}))
		check(recovered.get_shader_parameter("flow_speed").is_equal_approx(Vector2(flow.r, flow.g)), label + " retains source flow vector")
		if "WaterFall" in label:
			check(recovered.get_shader_parameter("foam_mask") is Texture2D, "Source waterfall foam texture loaded")
	RECOVERED.advance_water(scene, 0.25)
	check(scene.get_meta("water_materials").size() == 7, "Clock discovers every active material")
	for mesh in scene.get_children():
		check(is_equal_approx(mesh.material_override.get_shader_parameter("elapsed"), 0.25), "Explicit clock advances water")
	RECOVERED.advance_water(scene, 0.0)
	check(is_equal_approx(scene.get_meta("water_elapsed"), 0.25), "Paused clock preserves animation position")
	scene.free()
	print(JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
