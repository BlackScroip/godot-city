extends SceneTree

var failures: Array[String] = []
var checks := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var presentation = load("res://scripts/presentation/combat_presentation.gd").new()
	root.add_child(presentation)
	presentation.configure({})
	check(presentation.texture_cache.is_empty(), "Startup does not decode all combat textures")
	var effect_key := ""
	for key in presentation.media.effects:
		var definition: Dictionary = presentation.media.effects[key]
		if not definition.get("layers", []).is_empty() and not definition.get("textures", []).is_empty():
			effect_key = key
			break
	check(not effect_key.is_empty(), "Real recovered effect selected")
	if not effect_key.is_empty():
		var effect: Node3D = presentation._take_authored(effect_key, effect_key, false)
		check(not presentation.texture_cache.is_empty(), "Effect loads its required textures on demand")
		check(presentation.texture_cache.size() < presentation.media.texture_sources.size(), "Other effect textures remain unloaded")
		presentation._store_authored(effect_key, effect)
		presentation.release_room_resources()
		check(presentation.texture_cache.is_empty() and presentation.sound_cache.is_empty(), "Room release drops decoded media caches")
		check(presentation.authored_pool.is_empty() and presentation._authored_templates.is_empty(), "Room release drops effect nodes and templates")
		var next: Node3D = presentation._take_authored(effect_key, effect_key, false)
		check(not next.emitters.is_empty() and not presentation.texture_cache.is_empty(), "Effect reloads after room release")
		presentation._store_authored(effect_key, next)
	presentation.free()
	print("LOADING_RESOURCES_TEST ", JSON.stringify({"checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
