extends MeshInstance3D

var material: ShaderMaterial
var dimensions := Vector2.ONE
var shape := 0
static var _shader: Shader

const CODE = """shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
uniform vec2 dimensions = vec2(1.0);
uniform int shape = 0;
uniform float half_angle = 3.141593;
uniform float progress = 0.0;
void fragment() {
 vec2 p = (UV - 0.5) * dimensions;
 float border = 0.045;
 float aa = max(fwidth(p.x), fwidth(p.y));
 float distance_to_edge;
 float sweep;
 if (shape == 0) {
  vec2 inside = dimensions * 0.5 - abs(p);
  distance_to_edge = min(inside.x, inside.y);
  sweep = UV.y;
 } else {
  float radius = dimensions.x * 0.5;
  float r = length(p);
  distance_to_edge = radius - r;
  if (shape == 2) {
   float angle = abs(atan(p.x, p.y));
   distance_to_edge = min(distance_to_edge, (half_angle - angle) * r);
  }
  sweep = r / max(radius, 0.001);
 }
 float mask = smoothstep(-aa, aa, distance_to_edge);
 float edge = 1.0 - smoothstep(border, border + aa, distance_to_edge);
 float fill = 1.0 - smoothstep(progress - 0.015, progress + 0.015, sweep);
 ALBEDO = vec3(1.0, 0.025, 0.055);
 ALPHA = mask * max(edge * 0.92, 0.14 + fill * 0.22);
}"""

func configure(size: Vector2, shape_kind := 0, degrees := 360.0) -> void:
	dimensions = size.max(Vector2.ONE * 0.05)
	shape = shape_kind
	var plane = PlaneMesh.new()
	plane.size = dimensions
	mesh = plane
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material = ShaderMaterial.new()
	if _shader == null:
		_shader = Shader.new()
		_shader.code = CODE
	material.shader = _shader
	material.set_shader_parameter("dimensions", dimensions)
	material.set_shader_parameter("shape", shape)
	material.set_shader_parameter("half_angle", deg_to_rad(degrees * 0.5))
	material_override = material

func set_progress(value: float) -> void:
	material.set_shader_parameter("progress", clampf(value, 0.0, 1.0))
