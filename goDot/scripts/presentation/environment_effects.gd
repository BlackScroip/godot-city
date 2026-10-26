extends Node3D

const AUTHORED = preload("res://scripts/presentation/authored_effect.gd")
const WATER = preload("res://scripts/presentation/recovered_environment.gd")
const CATALOG = "res://assets/environment_effects/catalog.json"
const CAMP_HANDLED = ["24111405_fx_env_campfire", "23042001_fx_env_forestleafatmosphere", "23051502_fx_env_firefly", "25050801_fx_env_steam", "24061801_fx_env_waterfall"]
const PRIORITY_REFRESH_INTERVAL := 0.2
const PRIORITY_FOCUS_DISTANCE_SQUARED := 1.0
var bindings: Array[Dictionary] = []
var effects: Dictionary = {}
var texture_cache: Dictionary = {}
var clock := 0.0
var active_particle_count := 0
var _world: Node3D
var _low_quality := false
var _quality_refresh := 0.0
var _event_effects: Dictionary = {}
var _priority_refresh := 0.0
var _priority_focus := Vector3.INF

func configure(world: Node3D, camp := false) -> void:
	_world = world
	_low_quality = world.low_effects or int(DungeonStyle.read_options().quality) == 0
	if FileAccess.file_exists(CATALOG):
		var catalog = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
		if catalog is Dictionary: effects = catalog.get("effects", {})
	if is_instance_valid(world.get("interactions")) and world.interactions.has_signal("effect_requested"):
		world.interactions.effect_requested.connect(_on_effect_requested)
		world.interactions.presentation_requested.connect(_on_presentation_requested)
	var event_data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/environment_feedback.json"))
	if event_data is Dictionary: _event_effects = event_data.get("events", {})
	for anchor in world.environment_root.find_children("*", "Node3D", true, false):
		var address := resolve_address(str(anchor.name))
		if not effects.has(address): continue
		var handled := false
		if camp:
			for prefix in CAMP_HANDLED:
				if address.begins_with(prefix): handled = true
		if not handled: register_anchor(anchor, address)

static func source_address(node_name: String) -> String:
	var normalized := node_name.to_lower()
	var suffix := normalized.rfind("_u")
	if suffix >= 0 and normalized.substr(suffix + 2).is_valid_int():
		normalized = normalized.left(suffix)
	return normalized

func resolve_address(node_name: String) -> String:
	var normalized := node_name.to_lower()
	var found := ""
	for address: String in effects:
		if address.length() > found.length() and (normalized == address or normalized.begins_with(address + "_")):
			found = address
	return found

func _on_effect_requested(context: Dictionary) -> void:
	trigger_at(str(context.get("address", "")), context.get("position", Vector3.ZERO))

func _on_presentation_requested(kind: String, context: Dictionary) -> void:
	var event: Dictionary = _event_effects.get(kind, {})
	var address := str(event.get("effect", ""))
	if event.has("variants"):
		address = str(event.variants.get(str(context.get("data", {}).get("TreasureType", "")), ""))
	if address.is_empty(): return
	var item: Dictionary = _world.interactions._items.get(str(context.get("marker_id", "")), {})
	# An exported source particle anchor already follows its container's activation.
	if is_instance_valid(item.get("visual")):
		for anchor in item.visual.find_children("*", "Node3D", true, false):
			if resolve_address(str(anchor.name)) == address: return
	trigger_at(address, context.get("position", Vector3.ZERO))

func cache_textures(definition: Dictionary) -> void:
	for layer in definition.get("layers", []):
		for material in layer.get("materials", []):
			var path := str(material.get("texture", ""))
			if path.is_empty() or texture_cache.has(path): continue
			if ResourceLoader.exists(path):
				var texture = load(path)
				if texture is Texture2D: texture_cache[path] = texture

func register_anchor(anchor: Node3D, address: String, autoplay := true) -> Dictionary:
	if not effects.has(address): return {}
	for entry in bindings:
		if entry.anchor == anchor and entry.address == address: return entry
	var definition: Dictionary = effects[address].duplicate(true)
	if autoplay:
		definition.layers = definition.get("layers", []).filter(func(layer): return bool(layer.get("play_on_awake", true)))
	if definition.get("layers", []).is_empty(): return {}
	var entry := {"anchor": anchor, "address": address, "definition": definition, "effect": null, "active": false, "finished": false, "transient": false, "loop": false}
	for layer in definition.layers:
		if bool(layer.get("active", true)) and bool(layer.get("looping", false)): entry.loop = true
	bindings.append(entry)
	_priority_refresh = 0.0
	return entry

func trigger_at(address: String, point: Vector3, parent: Node3D = null) -> Dictionary:
	if not effects.has(address): return {}
	var anchor := Node3D.new()
	(parent if is_instance_valid(parent) else self).add_child(anchor)
	anchor.global_position = point
	var entry := register_anchor(anchor, address, false)
	if entry.is_empty():
		anchor.queue_free()
		return {}
	entry.transient = true
	# Explicit events are finite even when a source effect contains looping layers.
	entry.loop = false
	return entry

func _source_active(anchor: Node3D) -> bool:
	if not anchor.is_visible_in_tree(): return false
	var node: Node = anchor
	while is_instance_valid(node) and node != _world.environment_root:
		var extras = node.get_meta("extras", {})
		if not extras is Dictionary: extras = {}
		if not bool(node.get_meta("unityActive", extras.get("unityActive", true))): return false
		node = node.get_parent()
	return true

func _focus() -> Vector3:
	if is_instance_valid(_world.player): return _world.player.global_position
	var camera := get_viewport().get_camera_3d()
	return camera.global_position if camera else _world.global_position

func _refresh_priorities(focus: Vector3) -> void:
	if _priority_refresh > 0.0 and focus.distance_squared_to(_priority_focus) < PRIORITY_FOCUS_DISTANCE_SQUARED: return
	_priority_refresh = PRIORITY_REFRESH_INTERVAL
	_priority_focus = focus
	for entry in bindings:
		entry["priority_distance"] = entry.anchor.global_position.distance_squared_to(focus) if is_instance_valid(entry.anchor) else INF
	bindings.sort_custom(func(a, b): return a.priority_distance < b.priority_distance)

func _process(delta: float) -> void:
	if not is_instance_valid(_world): return
	_quality_refresh -= delta
	if _quality_refresh <= 0:
		_quality_refresh = 0.5
		set_low_quality(_world.low_effects or int(DungeonStyle.read_options().quality) == 0)
	var paused: bool = _world.paused or _world._background or (is_instance_valid(_world.hud) and _world.hud.modal_open)
	if not paused:
		clock += delta
		WATER.advance_water(_world.environment_root, delta)
	var focus := _focus()
	var budget := 720 if _low_quality else 2304
	var distance_limit := 26.0 if _low_quality else 38.0
	active_particle_count = 0
	_priority_refresh -= delta
	if not paused: _refresh_priorities(focus)
	var index := 0
	while index < bindings.size():
		var entry := bindings[index]
		index += 1
		if not is_instance_valid(entry.anchor):
			bindings.remove_at(index - 1)
			index -= 1
			continue
		var source_active := _source_active(entry.anchor)
		if not source_active:
			if is_instance_valid(entry.effect): entry.effect.stop()
			entry.active = false
			entry.finished = false
			continue
		if paused:
			if is_instance_valid(entry.effect): entry.effect.advance(0, true)
			continue
		if entry.finished: continue
		var nearby: bool = entry.anchor.global_position.distance_squared_to(focus) <= distance_limit * distance_limit
		if not nearby or active_particle_count >= budget:
			if is_instance_valid(entry.effect):
				if not nearby and entry.loop:
					entry.effect.queue_free()
					entry.effect = null
					entry.active = false
				else:
					entry.effect.hide()
					entry.effect.advance(0, true)
			if entry.transient:
				_remove(entry)
				index -= 1
			continue
		if not is_instance_valid(entry.effect):
			var visual = AUTHORED.new()
			visual.name = "RecoveredEnvironmentEffect"
			entry.anchor.add_child(visual)
			cache_textures(entry.definition)
			visual.configure(entry.definition, _low_quality, texture_cache)
			entry.effect = visual
		if active_particle_count + entry.effect.particle_count > budget:
			entry.effect.hide()
			entry.effect.advance(0, true)
			continue
		if not entry.active:
			entry.effect.restart()
			entry.active = true
		entry.effect.show()
		active_particle_count += entry.effect.particle_count
		entry.effect.advance(delta, false)
		if not entry.loop and entry.effect.age >= entry.effect.lifetime:
			entry.effect.stop()
			entry.finished = true
			if entry.transient:
				_remove(entry)
				index -= 1

func _remove(entry: Dictionary) -> void:
	bindings.erase(entry)
	if is_instance_valid(entry.effect): entry.effect.queue_free()
	if entry.transient and is_instance_valid(entry.anchor): entry.anchor.queue_free()

func remove_binding(entry: Dictionary) -> void:
	_remove(entry)

func set_low_quality(value: bool) -> void:
	if value == _low_quality: return
	_low_quality = value
	for entry in bindings:
		if entry.loop and is_instance_valid(entry.effect):
			entry.effect.queue_free()
			entry.effect = null
			entry.active = false

func _exit_tree() -> void:
	# Most visuals are children of imported anchors, outside this controller.
	for entry in bindings:
		if is_instance_valid(entry.effect): entry.effect.queue_free()
		if entry.transient and is_instance_valid(entry.anchor): entry.anchor.queue_free()
	bindings.clear()
	texture_cache.clear()
