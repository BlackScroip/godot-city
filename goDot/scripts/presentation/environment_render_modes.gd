extends RefCounted

static func apply(world: Node3D, source_root: Node3D) -> void:
	var scene := str(world.environment_entry.get("scene_name", ""))
	var identity := "10000" if scene == "EnvDesignMap_MainCity" else scene.trim_prefix("LevelMap_")
	var path := "res://assets/environment_recovered/render_modes/" + identity + ".json"
	if not FileAccess.file_exists(path):
		for key in world.catalog.get("environments", {}):
			if str(world.catalog.environments[key].get("scene_name", "")) == scene:
				path = "res://assets/environment_recovered/render_modes/" + str(key) + ".json"
				break
	if not FileAccess.file_exists(path): return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or str(data.get("scene", "")) != scene: return
	var bindings: Dictionary = data.get("bindings", {})
	var matched := 0
	var unknown: Array[String] = []
	var modes: Dictionary = {}
	for node: MeshInstance3D in source_root.find_children("*", "MeshInstance3D", true, false):
		var binding: Array = bindings.get(str(node.name), [])
		if binding.is_empty():
			unknown.append(str(node.name))
			continue
		var mode := int(binding[0])
		if mode < 0 or mode > 3: continue
		node.cast_shadow = mode
		if mode == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
			_restore_shadow_material(node)
		matched += 1
		modes[str(mode)] = int(modes.get(str(mode), 0)) + 1
	world.environment_root.set_meta("source_renderer_modes", {"matched": matched, "unknown": unknown, "modes": modes})

static func _restore_shadow_material(node: MeshInstance3D) -> void:
	for surface in node.mesh.get_surface_count():
		var active := node.get_active_material(surface)
		if not active or not active.resource_name.begins_with("UnityHidden/"): continue
		var original := node.mesh.surface_get_material(surface)
		# ShadowsOnly supplies the source invisibility without clipping its depth pass.
		if original and original.resource_name == active.resource_name.trim_prefix("UnityHidden/"):
			node.set_surface_override_material(surface, original)
