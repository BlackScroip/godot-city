extends RefCounted

static func handles(layer: Dictionary) -> bool:
	if int(layer.get("ring_buffer_mode", 0)) != 1: return false
	if bool(layer.get("looping", false)) or int(layer.get("simulation_space", 0)) != 0: return false
	if int(layer.get("start_delay", {}).get("minMaxState", 0)) != 0: return false
	var initial: Dictionary = layer.get("initial", {})
	var emission: Dictionary = layer.get("emission", {})
	var bursts: Array = emission.get("m_Bursts", [])
	if int(initial.get("maxNumParticles", 0)) != 1 or bursts.size() != 1: return false
	if bool(layer.get("shape", {}).get("enabled", false)) or not layer.get("modules", {}).is_empty(): return false
	if float(initial.get("startSpeed", {}).get("scalar", 0.0)) != 0.0 or float(initial.get("gravityModifier", {}).get("scalar", 0.0)) != 0.0: return false
	for key in ["rateOverTime", "rateOverDistance"]:
		if int(emission.get(key, {}).get("minMaxState", 0)) != 0 or float(emission.get(key, {}).get("scalar", 0.0)) != 0.0: return false
	if float(bursts[0].get("countCurve", {}).get("scalar", 0.0)) != 1.0 or int(bursts[0].get("cycleCount", 1)) != 1: return false
	if int(bursts[0].get("countCurve", {}).get("minMaxState", 0)) != 0: return false
	if float(bursts[0].get("probability", 1.0)) != 1.0: return false
	for key in ["startLifetime", "startSpeed", "gravityModifier", "startSize", "startSizeY", "startSizeZ", "startRotationX", "startRotationY", "startRotation", "startColor"]:
		if int(initial.get(key, {}).get("minMaxState", 0)) != 0: return false
	return true

static func create(particle: CPUParticles3D, layer: Dictionary) -> MultiMeshInstance3D:
	var initial: Dictionary = layer.initial
	var size := float(initial.startSize.scalar)
	var scale_value := Vector3.ONE * size
	if bool(initial.get("size3D", false)):
		scale_value.y = float(initial.get("startSizeY", {}).get("scalar", size))
		scale_value.z = float(initial.get("startSizeZ", {}).get("scalar", size))
	var result := MultiMeshInstance3D.new()
	result.name = "RetainedParticle"
	result.set_meta("source_layer", str(layer.name))
	result.multimesh = MultiMesh.new()
	result.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	result.multimesh.use_colors = true
	result.multimesh.use_custom_data = true
	result.multimesh.mesh = particle.mesh
	result.multimesh.instance_count = 1
	result.multimesh.set_instance_transform(0, Transform3D(Basis.from_scale(scale_value), Vector3.ZERO))
	result.multimesh.set_instance_color(0, particle.color)
	result.multimesh.set_instance_custom_data(0, Color(deg_to_rad(particle.angle_min), 0.0, 0.0, 0.0))
	result.material_override = particle.material_override
	result.transform = particle.transform
	result.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	result.extra_cull_margin = particle.extra_cull_margin
	result.hide()
	return result

static func duplicate_mesh(source: MultiMesh) -> MultiMesh:
	var result := MultiMesh.new()
	result.transform_format = source.transform_format
	result.use_colors = source.use_colors
	result.use_custom_data = source.use_custom_data
	result.mesh = source.mesh
	result.instance_count = source.instance_count
	# A headless dummy renderer has no instance buffer to copy.
	var buffer := source.buffer
	if not buffer.is_empty(): result.buffer = buffer
	return result
