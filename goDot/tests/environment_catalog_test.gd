extends SceneTree

const AUTHORED = preload("res://scripts/presentation/authored_effect.gd")
const CONTROLLER = preload("res://scripts/presentation/environment_effects.gd")
var failures: Array[String] = []
var checks := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(CONTROLLER.CATALOG))
	check(parsed is Dictionary, "Strict JSON catalog parses")
	if not parsed is Dictionary:
		quit(1)
		return
	var controller = CONTROLLER.new()
	root.add_child(controller)
	controller.effects = parsed.effects
	check(controller.effects.size() >= 113, "Original environmental directory fully exported")
	var visible_effects := 0
	var particles := 0
	for address: String in controller.effects:
		var definition: Dictionary = controller.effects[address]
		controller.cache_textures(definition)
		for layer in definition.layers:
			for material in layer.get("materials", []):
				var path := str(material.get("texture", ""))
				if not path.is_empty(): check(ResourceLoader.exists(path), address + " texture resolves")
			var mesh := str(layer.get("mesh", ""))
			if not mesh.is_empty(): check(ResourceLoader.exists(mesh), address + " mesh resolves")
		for low_quality in [false, true]:
			var effect = AUTHORED.new()
			root.add_child(effect)
			effect.configure(definition, low_quality, controller.texture_cache)
			effect.restart()
			effect.advance(0.2, false)
			check(effect.particle_count <= (144 if low_quality else 384), address + " respects particle budget")
			check(is_finite(effect.lifetime), address + " lifetime finite")
			for emitter in effect.emitters:
				var material = emitter.node.material_override
				var source_name: String = emitter.node.get_parent().get_meta("source_layer", "")
				for layer in definition.layers:
					if str(layer.name) != source_name or layer.get("materials", []).is_empty(): continue
					var texture_path := str(layer.materials[0].get("texture", ""))
					if not texture_path.is_empty():
						check(material is ShaderMaterial and material.get_shader_parameter("main_texture") is Texture2D and material.get_shader_parameter("main_texture") == controller.texture_cache.get(texture_path), address + "/" + source_name + " binds actual source texture")
			if not low_quality:
				if effect.particle_count > 0: visible_effects += 1
				particles += effect.particle_count
			effect.advance(0.5, true)
			check(is_equal_approx(effect.age, 0.2), address + " paused clock")
			effect.stop()
			effect.free()
	var coverage = JSON.parse_string(FileAccess.get_file_as_string("res://reports/environment-effects-coverage.json"))
	var matched := 0
	for scene in coverage.scenes:
		for binding in scene.bindings:
			check(controller.resolve_address(binding.node) == binding.effect, scene.scene + "/" + binding.node)
			matched += 1
	check(matched == int(coverage.matched_anchors), "Every scene binding matches runtime resolver")
	controller.free()
	print(JSON.stringify({"checks": checks, "effects": parsed.effects.size(), "visible_effects": visible_effects, "particles": particles, "scene_bindings": matched, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
