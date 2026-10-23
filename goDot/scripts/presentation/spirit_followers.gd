extends Node3D

# Inventory owns companions; combat's ability/summon pipeline owns their effects.
var entries: Dictionary = {}
var clock := 0.0

func sync_from_run(systems: RefCounted, player: Node3D) -> void:
	if not systems or not is_instance_valid(player) or not systems.profile.data.run.active:
		clear()
		return
	var wanted: Array[int] = []
	for key in systems.profile.data.run.inventory:
		if int(systems.profile.data.run.inventory[key]) <= 0: continue
		var id := int(key)
		var row: Dictionary = systems.catalog.find("LootData", id)
		if row.get("loot_type", "") in ["随从", "高级随从"]: wanted.append(id)
	wanted.sort()
	for id in entries.keys():
		if not wanted.has(id):
			entries[id].visual.queue_free()
			entries.erase(id)
	for index in wanted.size():
		var id := wanted[index]
		if entries.has(id):
			entries[id].slot = index
			continue
		var sprite := Sprite3D.new()
		sprite.name = "Spirit_%d" % id
		sprite.texture = DungeonStyle.texture("loot:" + str(id))
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.shaded = false
		sprite.pixel_size = 0.82 / maxf(1.0, sprite.texture.get_width() if sprite.texture else 128.0)
		sprite.render_priority = 1
		add_child(sprite)
		var origin := _destination(player.position, Vector3.FORWARD, index)
		sprite.position = origin
		entries[id] = {"id": id, "slot": index, "visual": sprite, "position": origin, "direction": Vector3.FORWARD}

func advance(delta: float, player: Node3D) -> void:
	if not is_instance_valid(player):
		clear()
		return
	clock += delta
	var facing: Vector3 = player.get("facing") if player.get("facing") is Vector3 else Vector3.FORWARD
	facing.y = 0
	if facing.length_squared() < 0.001: facing = Vector3.FORWARD
	for entry in entries.values():
		var direction: Vector3 = entry.direction
		direction = direction.lerp(facing.normalized(), 1.0 - exp(-delta * 4.0))
		if direction.length_squared() < 0.001: direction = facing.normalized()
		entry.direction = direction
		var target := _destination(player.position, direction.normalized(), int(entry.slot))
		var point: Vector3 = entry.position
		# Rebase after a teleport instead of sweeping across the entire room.
		point = target if point.distance_to(target) > 10.0 else point.lerp(target, 1.0 - exp(-delta * 5.0))
		entry.position = point
		entry.visual.position = point + Vector3.UP * sin(clock * 2.8 + int(entry.slot) * 1.7) * 0.11
		entry.visual.rotation.z = sin(clock * 1.6 + int(entry.slot)) * 0.06

func _destination(point: Vector3, direction: Vector3, slot: int) -> Vector3:
	var side := Vector3(-direction.z, 0, direction.x)
	var row := slot / 2
	var offset := -0.65 if slot % 2 == 0 else 0.65
	return point - direction * (1.1 + row * 0.65) + side * offset + Vector3.UP * (1.05 + (slot % 2) * 0.15)

func clear() -> void:
	for entry in entries.values(): entry.visual.queue_free()
	entries.clear()
	clock = 0.0
