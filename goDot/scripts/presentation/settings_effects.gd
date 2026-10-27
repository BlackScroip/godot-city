extends Node

const SCREEN_SHADER = """
shader_type canvas_item;
render_mode unshaded;
uniform sampler2D scene : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float exposure = 1.0;
uniform float bloom = 0.0;
uniform float flash = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0);
uniform vec2 motion = vec2(0.0);
void fragment() {
	vec3 color = textureLod(scene, SCREEN_UV, 0.0).rgb;
	if (length(motion) > 0.00001) {
		color = (color + textureLod(scene, SCREEN_UV - motion, 0.0).rgb
			+ textureLod(scene, SCREEN_UV + motion, 0.0).rgb
			+ textureLod(scene, SCREEN_UV - motion * 0.5, 0.0).rgb
			+ textureLod(scene, SCREEN_UV + motion * 0.5, 0.0).rgb) / 5.0;
	}
	if (bloom > 0.0) {
		vec3 glow = textureLod(scene, SCREEN_UV, 3.0).rgb;
		color += max(glow - vec3(0.62), vec3(0.0)) * bloom;
	}
	COLOR = vec4(mix(clamp(color * exposure, vec3(0.0), vec3(1.0)), flash_color.rgb, flash), 1.0);
}
"""
const DEPTH_SHADER = """
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_test_disabled, depth_draw_never;
uniform sampler2D scene : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform sampler2D depth_map : hint_depth_texture, repeat_disable, filter_nearest;
uniform float focus_distance = 24.0;
uniform int tone_mapper = 2;
uniform float tone_white = 1.0;
uniform float tone_exposure = 1.0;
vec3 to_linear(vec3 color) {
	return mix(color / 12.92, pow((color + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), color));
}
vec3 to_srgb(vec3 color) {
	return mix(color * 12.92, 1.055 * pow(max(color, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), color));
}
float filmic(float value) {
	return ((value * (0.88 * value + 0.06) + 0.002) / (value * (0.88 * value + 0.6) + 0.06)) - 0.01 / 0.3;
}
vec3 undo_filmic(vec3 color) {
	vec3 value = to_linear(color) * filmic(tone_white) + 0.01 / 0.3;
	vec3 a = 0.88 * (value - 1.0);
	vec3 b = 0.6 * value - 0.06;
	vec3 c = 0.06 * value - 0.002;
	vec3 linear = (-b - sqrt(max(b * b - 4.0 * a * c, vec3(0.0)))) / (2.0 * a);
	return to_srgb(linear / max(tone_exposure, 0.0001));
}
void vertex() { POSITION = vec4(VERTEX.xy, 1.0, 1.0); }
void fragment() {
	float depth = texture(depth_map, SCREEN_UV).r;
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		vec3 ndc = vec3(SCREEN_UV, depth) * 2.0 - 1.0;
	#else
		vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
	#endif
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float distance_from_focus = abs(-view.z / view.w - focus_distance);
	vec2 radius = vec2(smoothstep(3.0, 15.0, distance_from_focus) * 3.0) / VIEWPORT_SIZE;
	vec3 color = textureLod(scene, SCREEN_UV, 0.0).rgb * 4.0;
	color += (textureLod(scene, SCREEN_UV + vec2(radius.x, 0.0), 0.0).rgb
		+ textureLod(scene, SCREEN_UV - vec2(radius.x, 0.0), 0.0).rgb
		+ textureLod(scene, SCREEN_UV + vec2(0.0, radius.y), 0.0).rgb
		+ textureLod(scene, SCREEN_UV - vec2(0.0, radius.y), 0.0).rgb) * 2.0;
	color += textureLod(scene, SCREEN_UV + radius, 0.0).rgb
		+ textureLod(scene, SCREEN_UV - radius, 0.0).rgb
		+ textureLod(scene, SCREEN_UV + vec2(radius.x, -radius.y), 0.0).rgb
		+ textureLod(scene, SCREEN_UV + vec2(-radius.x, radius.y), 0.0).rgb;
	color /= 16.0;
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		// Compatibility screen samples already include the scene's Filmic tone map.
		if (tone_mapper == 2) color = undo_filmic(color);
	#endif
	ALBEDO = color;
	ALPHA = 1.0;
}
"""

var settings: Dictionary = {}
var base_scale := 1.0
var current_scale := 1.0
var _world: Node3D
var _screen: ColorRect
var _depth: MeshInstance3D
var _material: ShaderMaterial
var _flash_age := 0.0
var _flash_duration := 0.0
var _flash_value := 0.0
var _flash_owner: WeakRef
var _flash_sequence := -1
var _frame_time := 0.0
var _sample_time := 0.0
var _recovery_time := 0.0
var _idle_time := 0.0
var _last_camera := Vector3.INF
var _motion_active := false

func apply_settings(value: Dictionary, world: Node3D, scale_3d: float) -> void:
	settings = value.duplicate()
	_world = world
	base_scale = scale_3d
	current_scale = base_scale
	_world.get_viewport().scaling_3d_scale = base_scale
	_sample_time = 0.0
	_recovery_time = 0.0
	if _screen == null:
		var layer := CanvasLayer.new()
		layer.layer = -1
		add_child(layer)
		_screen = ColorRect.new()
		_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		layer.add_child(_screen)
		var shader := Shader.new()
		shader.code = SCREEN_SHADER
		_material = ShaderMaterial.new()
		_material.shader = shader
		_screen.material = _material
	_material.set_shader_parameter("exposure", pow(2.0, float(settings.get("brightness", 0)) / 100.0))
	_material.set_shader_parameter("bloom", 0.7 if bool(settings.get("bloom", false)) else 0.0)
	_material.set_shader_parameter("motion", Vector2.ZERO)
	_motion_active = false
	_configure_depth()
	_update_visibility()

func _configure_depth() -> void:
	var camera: Camera3D = _world.get("camera")
	if camera == null: return
	var renderer := RenderingServer.get_current_rendering_method()
	if renderer == "forward_plus":
		if not camera.attributes is CameraAttributesPractical: camera.attributes = CameraAttributesPractical.new()
		camera.attributes.dof_blur_far_enabled = bool(settings.get("dof", false))
		camera.attributes.dof_blur_far_transition = 12.0
		camera.attributes.dof_blur_amount = 0.12
		if is_instance_valid(_depth): _depth.hide()
		return
	if _depth == null and bool(settings.get("dof", false)):
		_depth = MeshInstance3D.new()
		_depth.name = "DepthOfFieldFallback"
		var quad := QuadMesh.new()
		quad.size = Vector2(2, 2)
		_depth.mesh = quad
		_depth.extra_cull_margin = 16384.0
		_depth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var shader := Shader.new()
		shader.code = DEPTH_SHADER
		var material := ShaderMaterial.new()
		material.shader = shader
		material.render_priority = 120
		_depth.material_override = material
		camera.add_child(_depth)
		_depth.position.z = -1.0
	if is_instance_valid(_depth):
		_depth.visible = bool(settings.get("dof", false))
		var environment := _world.get_world_3d().environment
		if environment:
			_depth.material_override.set_shader_parameter("tone_mapper", environment.tonemap_mode)
			_depth.material_override.set_shader_parameter("tone_white", environment.tonemap_white)
			_depth.material_override.set_shader_parameter("tone_exposure", environment.tonemap_exposure)

func screen_flash(intensity: float, duration: float, color := Color.WHITE, owner: Node = null, sequence := -1) -> void:
	_flash_age = 0.0
	_flash_duration = maxf(0.01, duration)
	_flash_value = clampf(intensity, 0.0, 1.0)
	_flash_owner = weakref(owner) if owner else null
	_flash_sequence = sequence
	_material.set_shader_parameter("flash_color", color)
	_update_visibility()

func sample_performance(fps: float, elapsed: float) -> void:
	if not bool(settings.get("dynamic_resolution", false)):
		current_scale = base_scale
		if is_instance_valid(_world): _world.get_viewport().scaling_3d_scale = current_scale
		return
	var target := float(settings.get("fps", 60))
	if target <= 0.0: target = 60.0
	_sample_time += elapsed
	if fps < target * 0.8:
		_recovery_time = 0.0
		if _sample_time >= 1.0:
			current_scale = maxf(minf(0.5, base_scale), current_scale - 0.05)
			_sample_time = 0.0
	elif fps >= target * 0.95:
		_recovery_time += elapsed
		if _recovery_time >= 4.0:
			current_scale = minf(base_scale, current_scale + 0.05)
			_recovery_time = 0.0
	else:
		_recovery_time = 0.0
	if is_instance_valid(_world): _world.get_viewport().scaling_3d_scale = current_scale

func _process(delta: float) -> void:
	if not is_instance_valid(_world) or _material == null: return
	var stopped := bool(_world.get("paused")) or bool(_world.get("_background"))
	var player: Node3D = _world.get("player")
	var camera: Camera3D = _world.get("camera")
	var modal := _world.get("hud") != null and bool(_world.get("hud").modal_open)
	if not stopped and not modal and not (bool(settings.get("idle_power_saving", false)) and _idle_time >= 30.0):
		_frame_time = lerpf(_frame_time, delta, 0.08) if _frame_time > 0.0 else delta
		sample_performance(1.0 / maxf(0.001, _frame_time), delta)
	else:
		_sample_time = 0.0
		_recovery_time = 0.0
	var idle: bool = stopped or modal or (is_instance_valid(player) and player.get("desired_velocity") == Vector3.ZERO and player.get("combat").busy <= 0.0 and not bool(_world.get("fighting")))
	_idle_time = _idle_time + delta if idle else 0.0
	var cap := int(settings.get("fps", 60))
	Engine.max_fps = mini(30, cap) if bool(settings.get("idle_power_saving", false)) and _idle_time >= 30.0 and cap > 0 else 30 if bool(settings.get("idle_power_saving", false)) and _idle_time >= 30.0 else cap
	if not stopped:
		_flash_age += delta * float(_world.get("simulation_scale"))
	if _flash_owner:
		var owner = _flash_owner.get_ref()
		if not is_instance_valid(owner) or (_flash_sequence >= 0 and owner.get("combat")._cast_sequence != _flash_sequence): _flash_age = _flash_duration
	var flash := _flash_value * maxf(0.0, 1.0 - _flash_age / maxf(0.01, _flash_duration)) * float(settings.get("flash_strength", 10)) / 10.0
	_material.set_shader_parameter("flash", flash)
	var motion := Vector2.ZERO
	if camera:
		if bool(settings.get("motion_blur", false)) and not stopped and not modal and _last_camera.is_finite():
			var velocity := camera.global_basis.inverse() * (camera.global_position - _last_camera)
			motion = Vector2(velocity.x, -velocity.y).limit_length(1.0) * 0.012
		_last_camera = camera.global_position
		if is_instance_valid(player):
			var focus := -(camera.global_transform.affine_inverse() * player.global_position).z
			if camera.attributes is CameraAttributesPractical: camera.attributes.dof_blur_far_distance = focus + 5.0
			if is_instance_valid(_depth): _depth.material_override.set_shader_parameter("focus_distance", focus)
	_material.set_shader_parameter("motion", motion)
	_motion_active = motion.length_squared() > 0.000000001
	_update_visibility()

func _update_visibility() -> void:
	if _screen:
		_screen.visible = int(settings.get("brightness", 0)) != 0 or bool(settings.get("bloom", false)) or _motion_active or (_flash_age < _flash_duration and int(settings.get("flash_strength", 10)) > 0)

func runtime_status() -> Dictionary:
	return {"renderer": RenderingServer.get_current_rendering_method(), "resolution_scale": current_scale,
		"bloom": "screen_bloom" if settings.get("bloom", false) else "off",
		"dof": ("native" if RenderingServer.get_current_rendering_method() == "forward_plus" else "depth_screen_blur") if settings.get("dof", false) else "off",
		"motion_blur": "camera_directional_blur" if settings.get("motion_blur", false) else "off",
		"limitations": ["Compatibility bloom uses the LDR scene; depth blur reads opaque geometry depth.", "Motion blur follows camera movement; per-object temporal motion vectors are unavailable."]}
