extends Node3D

const AuthoredEffect = preload("res://scripts/presentation/authored_effect.gd")
const CATALOG := "res://assets/spirit_followers/catalog.json"

# Inventory owns companions; combat's ability/summon pipeline owns their attacks.
var entries: Dictionary = {}
var clock := 0.0
var _inventory: Dictionary = {}
var media: Dictionary = {}
var _templates: Dictionary = {}
var _textures: Dictionary = {}

func _ready() -> void:
	_load_media()

func _load_media() -> void:
	if not media.is_empty(): return
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
	if value is Dictionary: media = value

func _visual(prefab: String, low: bool) -> Node3D:
	var key := prefab + (":low" if low else ":full")
	if not _templates.has(key):
		var definition: Dictionary = media.effects[prefab]
		for layer in definition.get("layers", []):
			for material in layer.get("materials", []):
				for binding in material.get("textures", []):
					var path := str(binding.get("texture", ""))
					if not path.is_empty() and not _textures.has(path): _textures[path] = load(path)
		var template = AuthoredEffect.new()
		var suppressed: Array = []
		var kept_accent := false
		for layer in definition.get("layers", []):
			var name := str(layer.get("name", ""))
			if name == "sprite_icon": continue
			if not layer.get("active", true) or not layer.get("emission", {}).get("enabled", true) or not layer.get("renderer", {}).get("enabled", true): continue
			if not kept_accent:
				kept_accent = true
			else:
				suppressed.append(name)
		template.configure(definition, low, _textures, suppressed)
		template.particle_count = 0
		for emitter in template.emitters:
			if emitter.node.get_parent().get_meta("source_layer", "") != "sprite_icon":
				emitter.node.amount = mini(emitter.node.amount, 6)
			template.particle_count += emitter.node.amount
		_templates[key] = template
	return _templates[key].instantiate_effect()

func handles_prefab(prefab: String) -> bool:
	var key := prefab.get_file().get_basename().to_lower()
	for entry in entries.values():
		if entry.prefab == key: return true
	return false

func trigger_message(message: String, actor: DungeonActor, presentation: Node3D) -> int:
	if message.is_empty(): return 0
	var count := 0
	for entry in entries.values():
		var raw: Dictionary = entry.raw
		if str(raw.get("CustomTriggerMsg_MsgName", "")) != message: continue
		var effect := str(raw.get("TriggerEffectName_NoDelay", ""))
		if effect.is_empty(): continue
		presentation.summon_trigger(actor, raw, entry.visual.global_position, "NoDelay", true)
		count += 1
	return count

func _exclude(summon: String, excluded: Dictionary) -> void:
	if excluded.has(summon): return
	excluded[summon] = true
	for child in media.followers.get(summon, {}).get("raw", {}).get("MutuallyExclusiveSummonUnitIdList", []):
		_exclude(str(child), excluded)

func sync_from_run(systems: RefCounted, player: Node3D) -> void:
	if not systems or not is_instance_valid(player) or not systems.profile.data.run.active:
		clear()
		return
	var inventory: Dictionary = systems.profile.data.run.inventory
	if inventory == _inventory: return
	_inventory = inventory.duplicate()
	_load_media()
	var wanted: Dictionary = {}
	var excluded: Dictionary = {}
	for key in inventory:
		if int(inventory[key]) <= 0: continue
		var id := int(key)
		var loot: Dictionary = systems.catalog.find("LootData", id)
		var binding: Dictionary = media.get("ability_bindings", {}).get(str(int(loot.get("ability_item_id", 0))), {})
		for summon in binding.get("summons", []):
			wanted[id] = str(summon)
			for previous in media.followers[summon].raw.get("MutuallyExclusiveSummonUnitIdList", []):
				_exclude(str(previous), excluded)
	for id in wanted.keys():
		if excluded.has(wanted[id]): wanted.erase(id)
	var ids: Array = wanted.keys()
	ids.sort()
	for id in entries.keys():
		if not wanted.has(id):
			entries[id].visual.queue_free()
			entries.erase(id)
	var low := int(DungeonStyle.read_options().quality) == 0
	if get_parent() is DungeonWorld: low = low or get_parent().low_effects
	for index in ids.size():
		var id: int = ids[index]
		if entries.has(id):
			entries[id].slot = index
			continue
		var definition: Dictionary = media.followers[wanted[id]]
		var prefab := str(definition.prefab)
		var visual := _visual(prefab, low)
		visual.name = "Spirit_%d" % id
		add_child(visual)
		var direction: Vector3 = player.get("facing") if player.get("facing") is Vector3 else Vector3.FORWARD
		if direction.length_squared() < 0.001: direction = Vector3.FORWARD
		direction = direction.normalized()
		var origin := _destination(player.position, direction, index, definition.raw)
		visual.position = origin
		visual.restart()
		entries[id] = {"id": id, "summon": wanted[id], "prefab": prefab, "raw": definition.raw,
			"slot": index, "visual": visual, "position": origin, "direction": direction}

func advance(delta: float, player: Node3D, paused := false) -> void:
	if not is_instance_valid(player):
		clear()
		return
	delta = clampf(delta, 0.0, 0.1)
	for entry in entries.values(): entry.visual.advance(delta, paused or delta == 0.0)
	if paused or delta == 0.0: return
	clock = fmod(clock + delta, TAU * 100.0)
	var facing: Vector3 = player.get("facing") if player.get("facing") is Vector3 else Vector3.FORWARD
	facing.y = 0
	if facing.length_squared() < 0.001: facing = Vector3.FORWARD
	facing = facing.normalized()
	for id in entries:
		var entry: Dictionary = entries[id]
		entry.direction = facing
		var raw: Dictionary = entry.raw
		var target := _destination(player.position, facing, int(entry.slot), raw)
		var point: Vector3 = entry.position
		var teleported := point.distance_squared_to(target) > 100.0
		var speed := maxf(float(raw.get("LineQueueMoveSpeed", raw.get("MoveToOwnerSpeed", 3.0))), point.distance_to(target) * 4.0)
		point = target if teleported else point.move_toward(target, speed * delta)
		entry.position = point
		entry.visual.position = point

func _destination(point: Vector3, direction: Vector3, slot: int, raw: Dictionary) -> Vector3:
	var base := float(raw.get("LineQueueBaseDistance", raw.get("MoveToOwnerMinDistance", 1.5)))
	var spacing := float(raw.get("LineQueueSpacing", raw.get("SeparationDistance", 1.0)))
	var ring := 1
	var index := slot
	while index >= ring * 8:
		index -= ring * 8
		ring += 1
	var signed_index := int((index + 1) / 2) * (1 if index % 2 == 1 else -1)
	var angle := TAU * float(signed_index) / float(ring * 8)
	var offset := (-direction).rotated(Vector3.UP, angle) * (base + (ring - 1) * spacing)
	return point + offset + DungeonWorld.vector(raw.get("InitPosOffset", {}))

func clear() -> void:
	for entry in entries.values(): entry.visual.queue_free()
	entries.clear()
	_inventory.clear()
	clock = 0.0

func _exit_tree() -> void:
	for template in _templates.values(): template.free()
	_templates.clear()
