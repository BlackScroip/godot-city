extends RefCounted

const SOURCE := "res://assets/environment_effects/doors/materials.json"
const RECOVERED = preload("res://scripts/presentation/recovered_effect_material.gd")
var materials: Array[ShaderMaterial] = []
var textures: Dictionary = {}

func configure(environment: Node3D) -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SOURCE)).materials
	for mesh in environment.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null: continue
		for surface in mesh.mesh.get_surface_count():
			var original: Material = mesh.get_active_material(surface)
			if original == null or not source.has(original.resource_name): continue
			var material := RECOVERED.create(source[original.resource_name], textures)
			material.resource_name = original.resource_name
			mesh.set_surface_override_material(surface, material)
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			materials.append(material)

func tick(clock: float) -> void:
	for material in materials: material.set_shader_parameter("clock", clock)
