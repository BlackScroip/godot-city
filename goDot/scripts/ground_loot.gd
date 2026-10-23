extends Node3D

var entries: Array[Dictionary] = []

func is_automatic(entry: Dictionary) -> bool:
	return bool(entry.get("material", false)) and int(entry.id) == 101

func spawn(id: int, point: Vector3, amount := 1, material := false) -> void:
	if id <= 0 or amount <= 0: return
	var sprite = Sprite3D.new()
	sprite.texture = DungeonStyle.texture(("material:" if material else "loot:") + str(id))
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded = false
	# Keep pickup size stable across source icons with different resolutions.
	sprite.pixel_size = (0.38 if material else 0.56) / maxf(1.0, sprite.texture.get_width() if sprite.texture else 128.0)
	add_child(sprite)
	sprite.position = point + Vector3.UP * 0.42
	var entry = {"id": id, "amount": amount, "material": material, "position": point, "visual": sprite, "age": 0.0, "speed": 0.0}
	if is_automatic(entry):
		var trail: Array[Sprite3D] = []
		for index in 3:
			var echo = Sprite3D.new()
			echo.texture = sprite.texture
			echo.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			echo.shaded = false
			echo.pixel_size = sprite.pixel_size
			echo.modulate = Color(1.0, 0.83, 0.35, 0.22 - index * 0.06)
			echo.scale = Vector3.ONE * (0.65 - index * 0.13)
			echo.position = sprite.position
			add_child(echo)
			trail.append(echo)
		entry["trail"] = trail
	entries.append(entry)

func nearest(point: Vector3) -> Dictionary:
	var result: Dictionary = {}
	var distance = 2.4
	for entry in entries:
		if is_automatic(entry): continue
		var current = point.distance_to(entry.position)
		if current < distance:
			distance = current
			result = entry
	return result

func spawn_altar(point: Vector3, key: String) -> void:
	spawn(20250, point)
	entries.back()["altar"] = key
	entries.back().visual.scale = Vector3.ONE * 2
	var anchor := Node3D.new()
	anchor.name = "SpiritAltarEffect"
	add_child(anchor)
	anchor.position = point
	entries.back()["effect_anchor"] = anchor
	_bind_altar_effect(entries.back())

func _bind_altar_effect(entry: Dictionary) -> void:
	if entry.has("effect_binding"): return
	var world := get_parent()
	if not is_instance_valid(world): return
	var environment = world.get("environment_root")
	if not is_instance_valid(environment): return
	var controller = environment.get_node_or_null("EnvironmentEffects")
	if controller == null: return
	var binding: Dictionary = controller.register_anchor(entry.effect_anchor, "25040703_fx_other_spritesaltar")
	if binding.is_empty(): return
	entry["effect_controller"] = controller
	entry["effect_binding"] = binding

func remove_altar(key: String) -> void:
	for entry in entries.duplicate():
		if entry.get("altar", "") == key:
			_release_visual(entry)
			entries.erase(entry)

func pickup(point: Vector3, systems: RefCounted) -> Dictionary:
	var entry = nearest(point)
	if entry.is_empty(): return {"success": false, "message": "靠近物品后拾取"}
	if entry.has("altar"): return {"success": false, "message": "请选择精灵"}
	var result: Dictionary
	if entry.material:
		systems.grant_material(entry.id, entry.amount)
		result = {"success": true, "message": "%s +%d" % [systems.material_name(entry.id), entry.amount]}
	else:
		result = systems.add_loot(entry.id)
	if result.success:
		_release_visual(entry)
		entries.erase(entry)
	return result

func clear() -> void:
	for entry in entries: _release_visual(entry)
	entries.clear()

func _release_visual(entry: Dictionary) -> void:
	entry.visual.queue_free()
	for echo in entry.get("trail", []): echo.queue_free()
	if is_instance_valid(entry.get("effect_controller")):
		entry.effect_controller.remove_binding(entry.get("effect_binding", {}))
	if is_instance_valid(entry.get("effect_anchor")): entry.effect_anchor.queue_free()

func advance_collection(delta: float, target: Vector3, systems: RefCounted) -> Array[Dictionary]:
	var collected: Array[Dictionary] = []
	for entry in entries.duplicate():
		if not is_automatic(entry): continue
		entry.age += delta
		if entry.age < 0.16: continue
		entry.speed = minf(36.0, float(entry.speed) + delta * 38.0)
		var previous: Vector3 = entry.visual.position
		entry.position = (entry.position as Vector3).move_toward(target, float(entry.speed) * delta)
		entry.visual.position = entry.position + Vector3.UP * (0.42 + sin(minf(float(entry.age), 0.8) * PI / 0.8) * 0.45)
		for echo in entry.get("trail", []):
			var old: Vector3 = echo.position
			echo.position = echo.position.lerp(previous, minf(1.0, delta * 20.0))
			previous = old
		if (entry.position as Vector3).distance_to(target) > 0.18: continue
		systems.grant_material(entry.id, entry.amount)
		collected.append({"success": true, "id": entry.id, "amount": entry.amount})
		_release_visual(entry)
		entries.erase(entry)
	return collected

func settle_automatic(systems: RefCounted) -> int:
	# Finish currency grants before a room transition discards its ground nodes.
	var amount := 0
	for entry in entries.duplicate():
		if not is_automatic(entry): continue
		systems.grant_material(entry.id, entry.amount)
		amount += int(entry.amount)
		_release_visual(entry)
		entries.erase(entry)
	return amount

func settle_materials(systems: RefCounted) -> void:
	for entry in entries.duplicate():
		if not entry.material: continue
		systems.grant_material(entry.id, entry.amount)
		_release_visual(entry)
		entries.erase(entry)

func snapshot() -> Array:
	var result: Array = []
	for entry in entries:
		result.append({"id": entry.id, "amount": entry.amount, "material": entry.material, "position": [entry.position.x, entry.position.y, entry.position.z], "altar": entry.get("altar", "")})
	return result

func restore(data: Array) -> void:
	clear()
	for entry in data:
		var point = Vector3(entry.position[0], entry.position[1], entry.position[2])
		if not str(entry.get("altar", "")).is_empty(): spawn_altar(point, str(entry.altar))
		else: spawn(int(entry.id), point, int(entry.amount), bool(entry.material))

func _process(_delta: float) -> void:
	var clock = Time.get_ticks_msec() / 1000.0
	for index in entries.size():
		if entries[index].has("altar"): _bind_altar_effect(entries[index])
		if is_automatic(entries[index]) and float(entries[index].age) >= 0.16: continue
		entries[index].visual.position.y = entries[index].position.y + 0.42 + sin(clock * 2.5 + index) * 0.06
