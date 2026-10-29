extends RefCounted

const SourceMaterial = preload("res://scripts/presentation/recovered_effect_material.gd")
const TrailShader = preload("res://scripts/presentation/recovered_particle.gdshader")
const CURVE_SAMPLES := 64
const DRAGON_TRAIL_MATERIAL := "CAB-e355e6b0d05ab47d2012d0e8ccc2b413:-7520495672365228611"

var node: MeshInstance3D
var _mesh: ImmediateMesh
var _material: ShaderMaterial
var _owner: Node3D
var _source_transform := Transform3D.IDENTITY
var _points: Array[Dictionary] = []
var _widths := PackedFloat32Array()
var _colors := PackedColorArray()
var _duration := 0.2
var _minimum_distance_sq := 0.0625
var _width_multiplier := 1.0
var _max_points := 24
var _time := 0.0
var _last_head := Vector3.INF
var _last_camera_basis := Basis.IDENTITY
var _source_id := ""

func configure(owner: Node3D, source: Dictionary, material: Dictionary, textures: Dictionary, low_quality: bool) -> void:
	_owner = owner
	if node == null:
		node = MeshInstance3D.new()
		node.name = "SourceBossTrail"
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_mesh = ImmediateMesh.new()
		node.mesh = _mesh
		owner.add_child(node)
		node.top_level = true
		node.global_transform = Transform3D.IDENTITY
	var ident := str(source.get("source_file_id", ""))
	if _material == null or ident != _source_id:
		_source_id = ident
		_source_transform = Transform3D.IDENTITY
		for item in source.get("transform_chain", []):
			var q: Dictionary = item.get("rotation", {})
			var rotation_value := Quaternion(float(q.get("x", 0)), float(q.get("y", 0)), float(q.get("z", 0)), float(q.get("w", 1))).normalized()
			_source_transform *= Transform3D(Basis(rotation_value).scaled(_vector(item.get("scale", {}), Vector3.ONE)), _vector(item.get("position", {}), Vector3.ZERO))
		_duration = maxf(0.001, float(source.get("duration", 0.2)))
		_minimum_distance_sq = pow(maxf(0.0, float(source.get("min_vertex_distance", 0.25))), 2)
		_width_multiplier = maxf(0.0, float(source.get("width_multiplier", 1.0)))
		_bake_curves(source.get("width_curve", {}), source.get("color_gradient", {}))
		_material = ShaderMaterial.new()
		_material.shader = TrailShader
		_material.set_shader_parameter("main_texture", textures.get(str(material.get("texture", ""))))
		_material.set_shader_parameter("tint", _color(material.get("shape_color", {})) * _color(material.get("color", {})))
		_material.set_shader_parameter("luminance_alpha", bool(material.get("alpha_from_luminance", false)))
		_material.set_shader_parameter("shape_alpha_weight", clampf(float(material.get("shape_alpha_weight", 1)), 0, 2))
		_material.set_shader_parameter("shape_brightness", float(material.get("shape_brightness", 0)))
		SourceMaterial.apply_source(_material, material, textures)
		if str(material.get("source", "")) == DRAGON_TRAIL_MATERIAL:
			# This APK shader variant uses vertex alpha for erosion, not opacity.
			_material.set_shader_parameter("source_fade_vertex_alpha", true)
			_material.set_shader_parameter("source_fade_vertex_alpha_only", true)
	_max_points = 16 if low_quality else 24
	restart()

func restart() -> void:
	_points.clear()
	_time = 0.0
	_last_head = Vector3.INF
	_last_camera_basis = Basis.IDENTITY
	_mesh.clear_surfaces()
	node.hide()

func stop() -> void:
	restart()

func set_opacity(value: float) -> void:
	node.transparency = 1.0 - clampf(value, 0.0, 1.0)

func advance(delta: float) -> void:
	if not is_instance_valid(_owner) or delta <= 0.0: return
	_time += delta
	var head: Vector3 = (_owner.global_transform * _source_transform).origin
	var changed := not head.is_equal_approx(_last_head)
	while not _points.is_empty() and _time - float(_points[0].time) > _duration:
		_points.pop_front()
		changed = true
	if _points.is_empty() or _points.back().position.distance_squared_to(head) >= _minimum_distance_sq:
		_points.append({"position": head, "time": _time})
		if _points.size() > _max_points: _points.pop_front()
		changed = true
	var camera := node.get_viewport().get_camera_3d()
	var camera_basis := camera.global_basis if camera else Basis.IDENTITY
	if not camera_basis.is_equal_approx(_last_camera_basis): changed = true
	_last_camera_basis = camera_basis
	_last_head = head
	if not changed:
		if node.visible: _material.set_shader_parameter("clock", _time)
		return
	var positions := PackedVector3Array()
	for point in _points: positions.append(point.position)
	if not positions.is_empty() and positions[-1].distance_squared_to(head) > 0.000001: positions.append(head)
	_draw(positions, camera_basis)

func _draw(positions: PackedVector3Array, camera_basis: Basis) -> void:
	_mesh.clear_surfaces()
	if positions.size() < 2:
		node.hide()
		return
	# Preserve the source gradient when sparse movement supplies only two points.
	if positions.size() == 2: positions.insert(1, positions[0].lerp(positions[1], 0.5))
	var distances := PackedFloat32Array([0.0])
	for index in range(1, positions.size()): distances.append(distances[-1] + positions[index].distance_to(positions[index - 1]))
	var length := distances[-1]
	if length < 0.001:
		node.hide()
		return
	_material.set_shader_parameter("clock", _time)
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _material)
	for index in positions.size():
		var phase := 1.0 - distances[index] / length
		var sample := clampi(int(round(phase * (CURVE_SAMPLES - 1))), 0, CURVE_SAMPLES - 1)
		var direction := positions[mini(index + 1, positions.size() - 1)] - positions[maxi(index - 1, 0)]
		var side := direction.cross(camera_basis.z).normalized()
		if side.is_zero_approx(): side = camera_basis.x.normalized()
		var offset := side * _widths[sample] * _width_multiplier * 0.5
		_mesh.surface_set_color(_colors[sample])
		_mesh.surface_set_uv(Vector2(phase, 0))
		_mesh.surface_add_vertex(positions[index] - offset)
		_mesh.surface_set_uv(Vector2(phase, 1))
		_mesh.surface_add_vertex(positions[index] + offset)
	_mesh.surface_end()
	node.show()

func _bake_curves(width: Dictionary, gradient: Dictionary) -> void:
	var curve := Curve.new()
	curve.min_value = -1024
	curve.max_value = 1024
	for key in width.get("m_Curve", []):
		curve.add_point(Vector2(float(key.get("time", 0)), float(key.get("value", 1))), float(key.get("inSlope", 0)), float(key.get("outSlope", 0)))
	_widths.clear()
	_colors.clear()
	for index in CURVE_SAMPLES:
		var phase := float(index) / float(CURVE_SAMPLES - 1)
		_widths.append(curve.sample(phase) if curve.point_count > 0 else 1.0)
		var rgb := _gradient_value(gradient, phase, false)
		_colors.append(Color(rgb.r, rgb.g, rgb.b, _gradient_value(gradient, phase, true).a))

func _gradient_value(gradient: Dictionary, phase: float, alpha: bool) -> Color:
	var count := int(gradient.get("m_NumAlphaKeys" if alpha else "m_NumColorKeys", 0))
	if count <= 0: return Color.WHITE
	var prefix := "atime" if alpha else "ctime"
	for index in range(1, count):
		var end := float(gradient.get(prefix + str(index), 65535)) / 65535.0
		if phase <= end:
			var start := float(gradient.get(prefix + str(index - 1), 0)) / 65535.0
			var first := _color(gradient.get("key" + str(index - 1), {}))
			var second := _color(gradient.get("key" + str(index), {}))
			return first.lerp(second, clampf((phase - start) / maxf(0.00001, end - start), 0.0, 1.0))
	return _color(gradient.get("key" + str(count - 1), {}))

func _vector(value: Dictionary, fallback: Vector3) -> Vector3:
	return Vector3(float(value.get("x", fallback.x)), float(value.get("y", fallback.y)), float(value.get("z", fallback.z)))

func _color(value: Dictionary) -> Color:
	return Color(float(value.get("r", 1)), float(value.get("g", 1)), float(value.get("b", 1)), float(value.get("a", 1)))
