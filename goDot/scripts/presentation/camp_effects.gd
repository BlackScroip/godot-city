extends Node3D

const PARTICLE_SHADER = preload("res://scripts/presentation/recovered_particle.gdshader")
const TEXTURES = {
	"fire": "res://assets/combat_presentation/39315fe1084bc454dc32.png",
	"smoke": "res://assets/combat_presentation/13d0a7bd7a7ea64ff611.png",
	"glow": "res://assets/combat_presentation/83c9587925e284f60074.png",
	"leaf": "res://assets/combat_presentation/62d0b4f1670c4b1f8828.png",
	"runes": "res://assets/combat_presentation/e56db449574d756c5ee3.png"
}
var emitters: Array[CPUParticles3D] = []
var circles: Array[ShaderMaterial] = []
var north_portal_surfaces: Array[ShaderMaterial] = []
var lights: Array[OmniLight3D] = []
var bindings: Dictionary = {}
var clock := 0.0
var _world: Node3D
var _low_quality := false
var _materials: Dictionary = {}
var _refresh := 0.0
var portal_surface_count := 0
var _portal_materials: Dictionary = {}
var _portal_textures: Dictionary = {}

func configure(world: Node3D) -> void:
	_world = world
	_low_quality = world.low_effects or int(DungeonStyle.read_options().quality) == 0
	var source = world.environment_root
	for anchor in source.find_children("*", "Node3D", true, false):
		if not _source_active(anchor): continue
		var key = str(anchor.name).to_lower()
		if key.begins_with("24102301_fx_env_maincityprotal"):
			_portal(anchor)
		elif key.begins_with("23121601_fx_env_portalblue"):
			_north_portal(anchor)
		elif key.begins_with("24111405_fx_env_campfire"):
			_campfire(anchor)
		elif key.begins_with("23042001_fx_env_forestleafatmosphere"):
			_leaves(anchor)
		elif key.begins_with("23051502_fx_env_firefly"):
			_fireflies(anchor)
		elif key.begins_with("25050801_fx_env_steam"):
			_steam(anchor)
		elif key.begins_with("24061801_fx_env_waterfall"):
			_waterfall(anchor, "spray" in key)
	_update_visibility()

func _source_active(node: Node3D) -> bool:
	var ancestor: Node = node
	while ancestor != _world.environment_root:
		var extras: Dictionary = ancestor.get_meta("extras", {})
		if not bool(ancestor.get_meta("unityActive", extras.get("unityActive", true))): return false
		ancestor = ancestor.get_parent()
	return true

func _anchor(source: Node3D, kind: String) -> Node3D:
	var result = Node3D.new()
	result.name = kind + "_" + str(bindings.get(kind, 0))
	add_child(result)
	result.global_position = source.global_position
	bindings[kind] = int(bindings.get(kind, 0)) + 1
	return result

func _material(texture: String, tint: Color, additive := true, sheet := Vector2.ONE) -> ShaderMaterial:
	var key = str([texture, tint, additive, sheet])
	if _materials.has(key): return _materials[key]
	var material = ShaderMaterial.new()
	if additive:
		var shader = Shader.new()
		shader.code = PARTICLE_SHADER.code.replace("blend_mix", "blend_add")
		material.shader = shader
	else: material.shader = PARTICLE_SHADER
	material.set_shader_parameter("main_texture", load(TEXTURES[texture]))
	material.set_shader_parameter("tint", tint)
	material.set_shader_parameter("luminance_alpha", true)
	material.set_shader_parameter("billboard", true)
	material.set_shader_parameter("sheet", sheet)
	_materials[key] = material
	return material

func _ramp(colors: Array[Color], offsets := PackedFloat32Array([0.0, 0.15, 0.7, 1.0])) -> Gradient:
	var ramp = Gradient.new()
	ramp.offsets = offsets
	ramp.colors = PackedColorArray(colors)
	return ramp

func _particles(parent: Node3D, kind: String, count: int, lifetime: float, material: ShaderMaterial, dimensions: Vector2) -> CPUParticles3D:
	var particle = CPUParticles3D.new()
	particle.name = kind
	particle.set_meta("full_amount", count)
	particle.amount = maxi(2, count / 2) if _low_quality else count
	particle.lifetime = lifetime
	particle.preprocess = lifetime
	particle.local_coords = false
	particle.gravity = Vector3.ZERO
	particle.direction = Vector3.UP
	particle.spread = 18
	particle.randomness = 0.65
	particle.use_fixed_seed = true
	particle.seed = 173 + emitters.size() * 31
	particle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var quad = QuadMesh.new()
	quad.size = dimensions
	particle.mesh = quad
	particle.material_override = material
	parent.add_child(particle)
	emitters.append(particle)
	return particle

func _campfire(source: Node3D) -> void:
	var anchor = _anchor(source, "campfire")
	var scale_value = clampf(source.global_basis.get_scale().x, 0.45, 1.5)
	var fire = _particles(anchor, "Flames", 18, 0.85, _material("fire", Color(1.0, 0.53, 0.09), true, Vector2(2, 2)), Vector2(0.65, 1.2) * scale_value)
	fire.position.y = 0.25 * scale_value
	fire.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	fire.emission_sphere_radius = 0.24 * scale_value
	fire.initial_velocity_min = 0.65 * scale_value
	fire.initial_velocity_max = 1.7 * scale_value
	fire.scale_amount_min = 0.55
	fire.scale_amount_max = 1.15
	fire.anim_speed_min = 0.65
	fire.anim_speed_max = 1.2
	fire.anim_offset_max = 1
	fire.color_ramp = _ramp([Color(1, 0.9, 0.5, 0), Color(1, 0.95, 0.6, 1), Color(1, 0.35, 0.08, 0.8), Color(0.5, 0.05, 0.01, 0)])
	var sparks = _particles(anchor, "Embers", 14, 2.0, _material("glow", Color(1.0, 0.45, 0.08)), Vector2(0.045, 0.11))
	sparks.position.y = 0.45
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparks.emission_sphere_radius = 0.22
	sparks.initial_velocity_min = 0.9
	sparks.initial_velocity_max = 2.0
	sparks.gravity = Vector3(0.12, -0.15, 0.08)
	sparks.color_ramp = _ramp([Color(1, 1, 0.6, 0), Color(1, 1, 0.7, 1), Color(1, 0.4, 0.06, 0.75), Color(1, 0.1, 0, 0)])
	var smoke = _particles(anchor, "Smoke", 6, 3.2, _material("smoke", Color(0.15, 0.18, 0.21, 0.22), false), Vector2(0.8, 0.8))
	smoke.position.y = 0.85
	smoke.initial_velocity_min = 0.35
	smoke.initial_velocity_max = 0.65
	smoke.gravity = Vector3(0.1, 0.04, 0.03)
	smoke.scale_amount_min = 0.65
	smoke.scale_amount_max = 1.5
	smoke.color_ramp = _ramp([Color(1, 1, 1, 0), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0.3), Color(1, 1, 1, 0)])
	_light(anchor, Color(1, 0.38, 0.08), 4.5 * scale_value, 1.6)

func _portal(source: Node3D) -> void:
	# EnvironmentEffects renders the APK prefab at this source transform.
	# Keep camp inventory bookkeeping without overriding surrounding scenery.
	_anchor(source, "portal")
	if _portal_materials.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://assets/environment_effects/camp_portal_materials.json"))
		if parsed is Dictionary: _portal_materials = parsed.get("materials", {})
	for mesh in source.get_parent().find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null: continue
		for surface in mesh.mesh.get_surface_count():
			var original: Material = mesh.get_active_material(surface)
			if original == null or not _portal_materials.has(original.resource_name): continue
			var material_path := "res://scripts/presentation/recovered_effect_material.gd"
			if not ResourceLoader.exists(material_path): continue
			var material: ShaderMaterial = load(material_path).create(_portal_materials[original.resource_name], _portal_textures)
			material.set_shader_parameter("visual_gain", 0.65)
			material.set_shader_parameter("source_alpha", float(material.get_shader_parameter("source_alpha")) * 0.7)
			material.resource_name = original.resource_name
			mesh.set_surface_override_material(surface, material)
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			circles.append(material)
			portal_surface_count += 1

func _north_portal(source: Node3D) -> void:
	var definitions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/environment_effects/camp_north_portal_materials.json")).materials
	var factory = preload("res://scripts/presentation/recovered_effect_material.gd")
	for mesh in source.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null: continue
		for surface in mesh.mesh.get_surface_count():
			var original: Material = mesh.get_active_material(surface)
			if original == null or not definitions.has(original.resource_name): continue
			var material: ShaderMaterial = factory.create(definitions[original.resource_name], _portal_textures)
			material.resource_name = original.resource_name
			mesh.set_surface_override_material(surface, material)
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			north_portal_surfaces.append(material)

func _light(parent: Node3D, color: Color, radius: float, energy: float) -> void:
	var light = OmniLight3D.new()
	light.position.y = 0.9
	light.light_color = color
	light.omni_range = radius
	light.light_energy = energy
	light.shadow_enabled = false
	light.set_meta("energy", energy)
	parent.add_child(light)
	lights.append(light)

func _leaves(source: Node3D) -> void:
	var anchor = _anchor(source, "leaves")
	var leaves = _particles(anchor, "DriftingLeaves", 16, 7, _material("leaf", Color(0.3, 0.8, 0.22, 0.8), false, Vector2(2, 2)), Vector2(0.24, 0.24))
	leaves.position.y = 4.0
	leaves.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	leaves.emission_box_extents = Vector3(9, 1.6, 8)
	leaves.direction = Vector3(0.7, -0.45, 0.25).normalized()
	leaves.spread = 25
	leaves.initial_velocity_min = 0.45
	leaves.initial_velocity_max = 0.95
	leaves.gravity = Vector3(0.02, -0.035, 0.01)
	leaves.angle_min = -180
	leaves.angle_max = 180
	leaves.angular_velocity_min = -65
	leaves.angular_velocity_max = 65
	leaves.anim_offset_max = 1
	leaves.color_ramp = _ramp([Color(1, 1, 1, 0), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0)])

func _fireflies(source: Node3D) -> void:
	var anchor = _anchor(source, "fireflies")
	var particles = _particles(anchor, "Fireflies", 5, 4, _material("glow", Color(0.5, 0.95, 0.16, 0.75)), Vector2(0.045, 0.045))
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 1.1
	particles.spread = 180
	particles.initial_velocity_min = 0.03
	particles.initial_velocity_max = 0.16
	particles.color_ramp = _ramp([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.4), Color(1, 1, 1, 0)])

func _steam(source: Node3D) -> void:
	var anchor = _anchor(source, "steam")
	var steam = _particles(anchor, "RisingSteam", 6, 2.6, _material("smoke", Color(0.65, 0.8, 0.85, 0.17), false), Vector2(0.5, 0.7))
	steam.initial_velocity_min = 0.25
	steam.initial_velocity_max = 0.5
	steam.gravity = Vector3(0.06, 0.04, 0.02)
	steam.color_ramp = _ramp([Color(1, 1, 1, 0), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0.25), Color(1, 1, 1, 0)])

func _waterfall(source: Node3D, spray: bool) -> void:
	var anchor = _anchor(source, "waterfall")
	var water = _particles(anchor, "WaterMist" if spray else "FallingWater", 12, 1.7, _material("smoke", Color(0.4, 0.75, 0.95, 0.2), false), Vector2(0.5, 0.35 if spray else 1.7))
	water.direction = Vector3.UP if spray else Vector3.DOWN
	water.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	water.emission_box_extents = Vector3(0.7, 0.1, 0.3)
	water.initial_velocity_min = 0.3 if spray else 1.4
	water.initial_velocity_max = 0.6 if spray else 2.4
	water.gravity = Vector3(0, -0.15 if spray else -1.0, 0)
	water.color_ramp = _ramp([Color(1, 1, 1, 0), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0)])

func _update_visibility() -> void:
	_low_quality = _world.low_effects or int(DungeonStyle.read_options().quality) == 0
	var focus = _world.player.global_position if is_instance_valid(_world.player) else _world.camera.global_position - Vector3.UP * 20
	for particle in emitters:
		var full_amount = int(particle.get_meta("full_amount"))
		var amount = maxi(2, full_amount / 2) if _low_quality else full_amount
		if particle.amount != amount: particle.amount = amount
		var active = particle.global_position.distance_squared_to(focus) < 32.0 * 32.0
		particle.visible = active
		particle.emitting = active
	for light in lights:
		light.visible = not _low_quality and light.global_position.distance_squared_to(focus) < 28.0 * 28.0

func _process(delta: float) -> void:
	if not is_instance_valid(_world): return
	var paused = _world.paused or _world._background
	for particle in emitters: particle.speed_scale = 0.0 if paused or not particle.visible else 1.0
	if paused: return
	clock += delta
	for material in circles: material.set_shader_parameter("clock", clock)
	for material in north_portal_surfaces: material.set_shader_parameter("clock", clock)
	for i in lights.size():
		lights[i].light_energy = float(lights[i].get_meta("energy")) * (0.93 + 0.07 * sin(clock * 8.7 + i) + 0.035 * sin(clock * 17.3))
	_refresh -= delta
	if _refresh <= 0:
		_refresh = 0.25
		_update_visibility()
