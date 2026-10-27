extends RefCounted

const CATALOG := "res://assets/environment_effects/altar_catalog.json"
static var _billboards: Dictionary = {}

static func restore(anchor: Node3D, button_key: String) -> Sprite3D:
	if not is_instance_valid(anchor): return null
	for node in anchor.find_children("SourceAltarPickup", "Sprite3D", false, false): return node
	if anchor is GeometryInstance3D or not anchor.find_children("*", "GeometryInstance3D", true, false).is_empty(): return null
	if _billboards.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
		if parsed is Dictionary: _billboards = parsed.get("billboards", {})
	var definition: Dictionary = _billboards.get(button_key, {})
	if definition.is_empty(): return null
	var texture := DungeonStyle.texture(str(definition.get("texture", "")))
	if texture == null: return null
	# Unity sprites may have zero depth; Godot billboards require an invertible basis.
	if is_zero_approx(anchor.basis.determinant()):
		var planar := anchor.basis
		planar.z = planar.x.cross(planar.y).normalized() * maxf(planar.x.length(), planar.y.length())
		anchor.basis = planar
	var sprite := Sprite3D.new()
	sprite.name = "SourceAltarPickup"
	sprite.texture = texture
	sprite.pixel_size = 1.0 / maxf(1.0, float(definition.get("pixels_per_unit", 100)))
	var tint: Dictionary = definition.get("color", {})
	sprite.modulate = Color(float(tint.get("r", 1)), float(tint.get("g", 1)), float(tint.get("b", 1)), float(tint.get("a", 1)))
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded = false
	sprite.render_priority = 5
	sprite.set_meta("source_sprite", str(definition.get("sprite", {}).get("name", "")))
	anchor.add_child(sprite)
	return sprite
