extends Node3D

signal altar_requested(key: String, marker_id: String)

const ALTAR_BUTTON_KEY := "EnvUnit_MonoData_BtnDisplayName_SpritesAltar"
const ALTAR_EGG_NAME := "sprite_abilityitemicon_14104"
const ALTAR_EGG_TEXTURE := "res://assets/environment_effects/spirit_altar_egg.png"
const PICKUP_GLOW_TEXTURE := "res://assets/combat_presentation/texture_36b152e75a0b0427f8a4.png"
const RARITY_COLORS := [Color("d6dfd6"), Color("7bc765"), Color("70c8ee"), Color("bc86e7"), Color("f4ce70"), Color("ee777c")]
const APPEAR_DELAY := 0.1
const SCATTER_DURATION := 0.7
const PICKUP_DELAY := 1.0
const PICKUP_RANGE := 99.0
const PICKUP_END_DISTANCE := 0.5
const ATTRACT_ACCELERATION := 30.0
const ATTRACT_MAX_TIME := 5.0

var entries: Array[Dictionary] = []
var source_altars: Array[Dictionary] = []
var _pointer_hud: DungeonHud
var _pointer_host: Control
var _pointer_allowed := false
var _pointer_player := Vector3.ZERO
var _pickup_effects: Dictionary = {}
var _pickup_effects_loaded := false
var _flight_random := RandomNumberGenerator.new()
var pickup_settings: Dictionary = {}

func _init() -> void:
	_flight_random.randomize()

func is_automatic(entry: Dictionary) -> bool:
	return bool(entry.get("material", false)) and int(entry.id) in [101, 102]

func apply_settings(settings: Dictionary) -> void:
	pickup_settings = settings.duplicate()

func preferred_pickup(entry: Dictionary, systems: RefCounted) -> bool:
	if entry.has("altar"): return false
	if bool(entry.get("material", false)):
		return bool(pickup_settings.get("auto_pickup_ornament", false)) and not systems.catalog.find("RelationshipAmplifyData", int(entry.id)).is_empty()
	var row: Dictionary = systems.catalog.find("LootData", int(entry.id))
	var kind := str(row.get("loot_type", ""))
	if kind.ends_with("遗物"): return bool(pickup_settings.get("auto_pickup_relic", false))
	return bool(pickup_settings.get("auto_pickup_consumable", false)) and kind in ["生命药水", "护甲", "攻击宝石", "防御宝石", "生命宝石", "遗物袋子", "天赋卷轴"]

func spawn(id: int, point: Vector3, amount := 1, material := false, replay_appearance := true) -> void:
	if id <= 0 or amount <= 0: return
	if material and id in [101, 102] and replay_appearance:
		for portion in _currency_portions(id, amount): _spawn_entry(id, point, portion, material, true)
	else:
		_spawn_entry(id, point, amount, material, replay_appearance)

func _currency_portions(id: int, amount: int) -> Array[int]:
	var divisor := 10 if id == 101 else 3
	var limit := 5 if id == 101 else 4
	var count := 1 if amount < divisor else mini(int(amount / float(divisor)), limit)
	var portion := maxi(1, int(amount / float(count)))
	var portions: Array[int] = []
	var remaining := amount
	while remaining > 0:
		portions.append(mini(portion, remaining))
		remaining -= portions.back()
	return portions

func _spawn_entry(id: int, point: Vector3, amount: int, material: bool, replay_appearance: bool) -> void:
	var sprite = Sprite3D.new()
	sprite.texture = DungeonItemArt.ground_texture(id, material)
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded = false
	# Keep pickup size stable across source icons with different resolutions.
	sprite.pixel_size = (0.38 if material else 0.56) / maxf(1.0, sprite.texture.get_width() if sprite.texture else 128.0)
	add_child(sprite)
	sprite.position = point + Vector3.UP * 0.42
	var entry = {"id": id, "amount": amount, "material": material, "position": point, "visual": sprite, "age": 0.0, "speed": 0.0}
	if is_automatic(entry):
		var destination := point
		var jump_height := 0.0
		if replay_appearance:
			# A sphere direction projected onto XZ preserves the APK's shorter throws.
			var y := _flight_random.randf_range(-1.0, 1.0)
			var angle := _flight_random.randf_range(0.0, TAU)
			var radius := sqrt(maxf(0.0, 1.0 - y * y)) * _flight_random.randf_range(2.0, 5.0)
			destination += Vector3(cos(angle), 0, sin(angle)) * radius
			destination.y += 0.1
			jump_height = _flight_random.randf_range(0.8, 1.2)
		entry["flight"] = {"phase": "scatter" if replay_appearance else "waiting", "origin": point,
			"destination": destination, "jump_height": jump_height, "attract_age": 0.0}
		if not replay_appearance: entry.age = PICKUP_DELAY
		var trail: Array[Sprite3D] = []
		for index in 3:
			var echo = Sprite3D.new()
			echo.texture = sprite.texture
			echo.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			echo.shaded = false
			echo.pixel_size = sprite.pixel_size
			echo.modulate = Color(1.0, 0.83, 0.35, 0.22 - index * 0.06) if id == 101 else Color(0.4, 0.75, 1.0, 0.22 - index * 0.06)
			echo.scale = Vector3.ONE * (0.65 - index * 0.13)
			echo.position = sprite.position
			add_child(echo)
			trail.append(echo)
		entry["trail"] = trail
	entry["replay_appearance"] = replay_appearance
	entries.append(entry)
	_add_pickup_glow(entry)
	_bind_pickup_effect(entry)

func _add_pickup_glow(entry: Dictionary) -> void:
	if entry.material: return
	var texture := DungeonStyle.texture(PICKUP_GLOW_TEXTURE)
	if texture == null: return
	var rarity := int(DungeonItemArt.relic_info(int(entry.id)).get("rarity", 0))
	var world := get_parent()
	if is_instance_valid(world) and world.get("systems") != null:
		var systems: RefCounted = world.get("systems")
		var loot: Dictionary = systems.catalog.find("LootData", int(entry.id))
		var ability: Dictionary = systems.catalog.find("AbilityItems", int(loot.get("ability_item_id", entry.id)))
		rarity = int(ability.get("Rare", rarity))
	var color: Color = RARITY_COLORS[clampi(rarity, 0, RARITY_COLORS.size() - 1)]
	var glow := Sprite3D.new()
	glow.name = "ItemRarityGlow"
	glow.texture = texture
	glow.pixel_size = 1.45 / maxf(1.0, texture.get_width())
	glow.rotation_degrees.x = -90
	glow.shaded = false
	glow.modulate = Color(color, 0.64)
	glow.position = entry.position + Vector3.UP * 0.055
	add_child(glow)
	entry["rarity_glow"] = glow
	entry["rarity_color"] = color

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
	for entry in entries:
		if str(entry.get("altar", "")) == key: return
	spawn(20250, point)
	entries.back()["altar"] = key
	if is_instance_valid(entries.back().get("rarity_glow")):
		entries.back().rarity_glow.queue_free()
		entries.back().erase("rarity_glow")
	var egg := DungeonStyle.texture(ALTAR_EGG_TEXTURE)
	if egg:
		entries.back().visual.texture = egg
		entries.back().visual.pixel_size = 0.56 / maxf(1.0, egg.get_width())
	entries.back().visual.scale = Vector3.ONE * 2
	var anchor := Node3D.new()
	anchor.name = "SpiritAltarEffect"
	add_child(anchor)
	anchor.position = point
	entries.back()["effect_anchor"] = anchor
	_bind_altar_effect(entries.back())
	_add_altar_pointer(entries.back())

func configure_altar_pointer(hud: DungeonHud) -> void:
	if _pointer_hud == hud and is_instance_valid(_pointer_host): return
	_clear_source_altars()
	for entry in entries: _release_altar_pointer(entry)
	if is_instance_valid(_pointer_host): _pointer_host.queue_free()
	_pointer_hud = hud
	if not is_instance_valid(hud) or not is_instance_valid(hud.root): return
	_pointer_host = Control.new()
	_pointer_host.name = "WorldSpiritEggTargets"
	_pointer_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pointer_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.root.add_child(_pointer_host)
	hud.root.move_child(_pointer_host, 0)
	for entry in entries:
		if entry.has("altar"): _add_altar_pointer(entry)

func sync_source_altars(interactions: RefCounted, room_key: String) -> void:
	_clear_source_altars()
	if interactions == null: return
	for item in interactions._items.values():
		if str(item.data.get("UIBtnName", "")) != ALTAR_BUTTON_KEY: continue
		if not is_instance_valid(item.visual): continue
		var egg: Node3D
		for node in item.visual.find_children(ALTAR_EGG_NAME + "*", "Node3D", true, false):
			egg = node
			break
		if egg == null:
			egg = Node3D.new()
			egg.name = ALTAR_EGG_NAME + "_Recovered"
			item.visual.add_child(egg)
			egg.position = Vector3(-0.007, 1.25, -0.014)
			egg.scale = Vector3.ONE * 0.3
			item.altar_eggs.append({"node": egg, "visible": true})
			egg.visible = not bool(item.state.get("used", false))
		_restore_altar_renderer(egg)
		var entry := {"altar": "altar:" + room_key + ":" + str(item.id), "marker_id": str(item.id),
			"source_item": item, "visual": egg, "position": item.visual.global_position,
			"source_transform": item.visual.global_transform, "pending": false}
		source_altars.append(entry)
		_add_altar_pointer(entry)

func _restore_altar_renderer(egg: Node3D) -> void:
	preload("res://scripts/presentation/altar_billboards.gd").restore(egg, ALTAR_BUTTON_KEY)

func _source_altar_available(entry: Dictionary) -> bool:
	if not source_altars.has(entry): return false
	var item: Dictionary = entry.get("source_item", {})
	return not item.is_empty() and bool(item.state.get("enabled", false)) and not bool(item.state.get("used", false)) and not bool(item.state.get("broken", false))

func altar_reachable(entry: Dictionary, point: Vector3) -> bool:
	if entry.has("source_item"):
		if not _source_altar_available(entry): return false
		# APK Box_TiggerEnter is 3 x 1 x 2.5. Include the player capsule radius.
		var local: Vector3 = (entry.source_transform as Transform3D).affine_inverse() * (point + Vector3.UP * 0.5) - Vector3.UP * 0.5
		return absf(local.x) <= 1.85 and absf(local.y) <= 0.85 and absf(local.z) <= 1.6
	return entries.has(entry) and point.distance_to(entry.position) < 2.4

func update_altar_pointer(camera: Camera3D, player_point: Vector3, enabled: bool) -> void:
	_pointer_player = player_point
	_pointer_allowed = enabled and is_instance_valid(camera) and is_instance_valid(_pointer_hud) and not _pointer_hud.modal_open
	for entry in entries + source_altars:
		if not entry.has("altar"): continue
		_add_altar_pointer(entry)
		var button: Button = entry.get("pointer")
		if not is_instance_valid(button): continue
		var active: bool = _pointer_allowed and altar_reachable(entry, player_point) and is_instance_valid(entry.visual) and entry.visual.is_visible_in_tree()
		if _pointer_allowed: entry["pending"] = false
		if not active:
			button.hide()
			continue
		var center: Vector3 = entry.visual.global_position
		if entry.has("source_item") and entry.visual == entry.source_item.visual: center += Vector3.UP * 1.0
		if camera.is_position_behind(center):
			button.hide()
			continue
		var screen := camera.unproject_position(center)
		var side := clampf(camera.unproject_position(center + camera.global_basis.x * 0.65).distance_to(screen) * 2.0, 44.0, 100.0)
		button.size = Vector2.ONE * side
		button.position = screen - button.size * 0.5
		button.visible = Rect2(Vector2.ZERO, camera.get_viewport().get_visible_rect().size).intersects(button.get_rect())

func request_altar(entry: Dictionary) -> bool:
	if not _pointer_allowed or not is_instance_valid(_pointer_hud) or _pointer_hud.modal_open: return false
	if bool(entry.get("pending", false)) or not altar_reachable(entry, _pointer_player): return false
	entry["pending"] = true
	altar_requested.emit(str(entry.altar), str(entry.get("marker_id", "")))
	return true

func _add_altar_pointer(entry: Dictionary) -> void:
	if not entry.has("altar") or not is_instance_valid(_pointer_host) or is_instance_valid(entry.get("pointer")): return
	var button := Button.new()
	button.name = "SpiritEggTarget"
	button.tooltip_text = "获取精灵"
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.focus_mode = Control.FOCUS_NONE
	for state in ["normal", "hover", "pressed", "focus", "disabled"]: button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	button.hide()
	_pointer_host.add_child(button)
	button.pressed.connect(func(): request_altar(entry))
	entry["pointer"] = button
	if is_instance_valid(_pointer_hud.joystick): _pointer_hud.joystick.excluded_controls.append(button)

func _release_altar_pointer(entry: Dictionary) -> void:
	var button = entry.get("pointer")
	if not is_instance_valid(button): return
	if is_instance_valid(_pointer_hud) and is_instance_valid(_pointer_hud.joystick): _pointer_hud.joystick.excluded_controls.erase(button)
	button.queue_free()
	entry.erase("pointer")

func _clear_source_altars() -> void:
	for entry in source_altars: _release_altar_pointer(entry)
	source_altars.clear()

func _exit_tree() -> void:
	_clear_source_altars()
	for entry in entries: _release_altar_pointer(entry)
	if is_instance_valid(_pointer_host): _pointer_host.queue_free()

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

func _bind_pickup_effect(entry: Dictionary) -> void:
	if entry.has("effect_binding") or entry.has("altar"): return
	if not _pickup_effects_loaded:
		_pickup_effects_loaded = true
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/pickup_feedback.json"))
		if data is Dictionary: _pickup_effects = data.get("bindings", {})
	var key := ("material:" if entry.material else "loot:") + str(entry.id)
	var rule: Dictionary = _pickup_effects.get(key, {})
	if rule.is_empty() or (rule.event == "appear" and not entry.get("replay_appearance", true)): return
	var world := get_parent()
	if not is_instance_valid(world): return
	var environment = world.get("environment_root")
	if not is_instance_valid(environment): return
	var controller = environment.get_node_or_null("EnvironmentEffects")
	if controller == null: return
	var anchor := Node3D.new()
	anchor.name = "RecoveredPickupEffect"
	add_child(anchor)
	anchor.position = entry.position
	var binding: Dictionary = controller.register_anchor(anchor, str(rule.effect), rule.event == "persistent")
	if binding.is_empty():
		anchor.queue_free()
		return
	if rule.event == "appear": binding.loop = false
	entry["effect_anchor"] = anchor
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
		# A configured stack remains on the ground until every copy is granted.
		if not entry.material and int(entry.amount) > 1:
			entry.amount = int(entry.amount) - 1
			return result
		_release_visual(entry)
		entries.erase(entry)
	return result

func clear() -> void:
	_pointer_allowed = false
	for entry in entries: _release_visual(entry)
	entries.clear()
	_clear_source_altars()

func _release_visual(entry: Dictionary) -> void:
	_release_altar_pointer(entry)
	entry.visual.queue_free()
	for echo in entry.get("trail", []): echo.queue_free()
	if is_instance_valid(entry.get("rarity_glow")): entry.rarity_glow.queue_free()
	if is_instance_valid(entry.get("effect_controller")):
		entry.effect_controller.remove_binding(entry.get("effect_binding", {}))
	if is_instance_valid(entry.get("effect_anchor")): entry.effect_anchor.queue_free()

func advance_collection(delta: float, target: Vector3, systems: RefCounted) -> Array[Dictionary]:
	var collected: Array[Dictionary] = []
	if delta <= 0: return collected
	for entry in entries.duplicate():
		if not is_automatic(entry):
			entry.age += delta
			if float(entry.age) < PICKUP_DELAY or (entry.position as Vector3).distance_to(target) >= 2.4 or not preferred_pickup(entry, systems): continue
			var result: Dictionary
			if entry.material:
				systems.grant_material(entry.id, entry.amount)
				result = {"success": true}
			else: result = systems.add_loot(entry.id)
			if not result.get("success", false): continue
			collected.append({"success": true, "id": entry.id, "amount": 1 if not entry.material else entry.amount, "material": entry.material})
			if not entry.material and int(entry.amount) > 1:
				entry.amount = int(entry.amount) - 1
			else:
				_release_visual(entry)
				entries.erase(entry)
			continue
		var previous: Vector3 = entry.visual.position
		var previous_age := float(entry.age)
		entry.age += delta
		var flight: Dictionary = entry.flight
		if flight.phase == "scatter":
			var progress := clampf((float(entry.age) - APPEAR_DELAY) / SCATTER_DURATION, 0.0, 1.0)
			entry.position = (flight.origin as Vector3).lerp(flight.destination, progress)
			entry.position += Vector3.UP * absf(sin(progress * TAU)) * float(flight.jump_height)
			if progress >= 1.0: flight.phase = "waiting"
		if entry.age > PICKUP_DELAY and flight.phase == "waiting" and (entry.position as Vector3).distance_to(target) <= PICKUP_RANGE:
			flight.phase = "attract"
		if flight.phase == "attract":
			if (entry.position as Vector3).distance_to(target) <= PICKUP_END_DISTANCE:
				systems.grant_material(entry.id, entry.amount)
				collected.append({"success": true, "id": entry.id, "amount": entry.amount})
				_release_visual(entry)
				entries.erase(entry)
				continue
			var active_delta := maxf(0.0, float(entry.age) - maxf(previous_age, PICKUP_DELAY))
			flight.attract_age = float(flight.attract_age) + active_delta
			entry.speed = 1.0 + ATTRACT_ACCELERATION * minf(ATTRACT_MAX_TIME, float(flight.attract_age))
			entry.position = (entry.position as Vector3).move_toward(target, float(entry.speed) * active_delta)
		entry.visual.position = entry.position + Vector3.UP * 0.42
		for echo in entry.get("trail", []):
			var old: Vector3 = echo.position
			echo.position = echo.position.lerp(previous, minf(1.0, delta * 20.0))
			previous = old
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
		var saved := {"id": entry.id, "amount": entry.amount, "material": entry.material, "position": [entry.position.x, entry.position.y, entry.position.z], "altar": entry.get("altar", "")}
		if is_automatic(entry):
			var flight: Dictionary = entry.flight
			saved["flight"] = {"age": entry.age, "phase": flight.phase, "jump_height": flight.jump_height,
				"origin": [flight.origin.x, flight.origin.y, flight.origin.z],
				"destination": [flight.destination.x, flight.destination.y, flight.destination.z], "attract_age": flight.attract_age}
		result.append(saved)
	return result

func restore(data: Array) -> void:
	clear()
	for entry in data:
		var point = Vector3(entry.position[0], entry.position[1], entry.position[2])
		if not str(entry.get("altar", "")).is_empty(): spawn_altar(point, str(entry.altar))
		else:
			spawn(int(entry.id), point, int(entry.amount), bool(entry.material), false)
			var restored: Dictionary = entries.back()
			if not is_automatic(restored) or not entry.get("flight") is Dictionary: continue
			var saved: Dictionary = entry.flight
			var flight: Dictionary = restored.flight
			flight.phase = str(saved.get("phase", "waiting"))
			if flight.phase not in ["scatter", "waiting", "attract"]: flight.phase = "waiting"
			for key in ["origin", "destination"]:
				var coordinates: Array = saved.get(key, [point.x, point.y, point.z])
				if coordinates.size() == 3: flight[key] = Vector3(coordinates[0], coordinates[1], coordinates[2])
			flight.jump_height = clampf(float(saved.get("jump_height", 0.0)), 0.0, 1.2)
			flight.attract_age = maxf(0.0, float(saved.get("attract_age", 0.0)))
			restored.age = maxf(0.0, float(saved.get("age", PICKUP_DELAY)))
			restored.speed = 1.0 + ATTRACT_ACCELERATION * minf(ATTRACT_MAX_TIME, float(flight.attract_age)) if flight.phase == "attract" else 0.0

func _process(_delta: float) -> void:
	var clock = Time.get_ticks_msec() / 1000.0
	for index in entries.size():
		if entries[index].has("altar"): _bind_altar_effect(entries[index])
		else: _bind_pickup_effect(entries[index])
		if is_automatic(entries[index]): continue
		entries[index].visual.position.y = entries[index].position.y + 0.42 + sin(clock * 2.5 + index) * 0.06
