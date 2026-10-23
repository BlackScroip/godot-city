class_name DungeonPlayerIndicator
extends Node3D

func _ready() -> void:
	position.y = 0.08
	var arrow = MeshInstance3D.new()
	arrow.name = "FacingArrow"
	arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var vertices = PackedVector3Array([Vector3(-0.23, 0.005, 0.73), Vector3(0, 0.005, 1.12), Vector3(0.23, 0.005, 0.73), Vector3(0, 0.005, 0.85)])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 3, 1, 2, 3])
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	arrow.mesh = mesh
	var arrow_material = StandardMaterial3D.new()
	arrow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	arrow_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	arrow_material.albedo_color = Color("a8ffe4")
	arrow.material_override = arrow_material
	add_child(arrow)
