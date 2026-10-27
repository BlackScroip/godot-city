extends RefCounted

var choices: Array = []
var preserve_once := false
var _root_id := 0
var _level := -1
var _random := RandomNumberGenerator.new()

func _init() -> void:
	_random.randomize()

func markers(world) -> Array:
	var root: Node3D = world.environment_root
	var level: int = world.systems.rank(world.systems.profile.data.buildings, 1)
	if not preserve_once or level != _level:
		choices = world.systems.social.visitor_choices(level, int(world.systems.profile.data.selected_character), func(limit): return _random.randi_range(0, maxi(0, limit - 1)))
	preserve_once = false
	_level = level
	_root_id = root.get_instance_id()
	var result: Array = []
	for seat in range(1, 4):
		var anchor = root.find_child("EnvUnit_NPC_RandomPlayerCharaSeat%d__*" % seat, true, false)
		if not anchor is Node3D: continue
		var character_id := 0
		for choice in choices:
			if int(choice.seat) == seat: character_id = int(choice.character_id)
		var npc_id: int = world.systems.social.visitor_npc_id(character_id) if character_id > 0 else 1
		if character_id > 0: _install(world, anchor, npc_id)
		var point: Vector3 = root.to_local(anchor.global_position)
		result.append({"SourceGameObjectId": "camp:visitor:%d" % seat, "SceneName": "EnvDesignMap_MainCity",
			"ObjectName": str(anchor.name), "Type": "EEUT_NPC", "exported_node_name": str(anchor.name),
			"world_position": [point.x, point.y, point.z],
			"DataJson": JSON.stringify({"NpcId": npc_id, "InitActive": character_id > 0 and character_id != int(world.systems.profile.data.selected_character)})})
	return result

func _install(world, anchor: Node3D, character_id: int) -> void:
	var old := anchor.get_node_or_null("CampVisitor")
	if old != null:
		anchor.remove_child(old)
		old.queue_free()
	var actor := DungeonActor.new()
	actor.name = "CampVisitor"
	actor.actor_id = character_id
	actor.is_player = true
	anchor.add_child(actor)
	actor.set_visual(world.asset_path("characters", character_id), world.catalog.get("characters", {}).get(str(character_id), {}))
	actor.collision_layer = 0
	actor.collision_mask = 0
	actor.set_process(false)
	actor.set_physics_process(false)
	if actor.direction_indicator: actor.direction_indicator.hide()
	DungeonWorldStyle.apply_models(actor)
	actor.play_animation("idle")
	if actor.animation:
		actor.animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE

func refresh(world) -> void:
	if not world.interactions or not is_instance_valid(world.environment_root): return
	var level: int = world.systems.rank(world.systems.profile.data.buildings, 1)
	if level != _level:
		var updated := markers(world)
		for marker in updated:
			var item: Dictionary = world.interactions._items.get(str(marker.SourceGameObjectId), {})
			if item.is_empty(): continue
			item.data = JSON.parse_string(marker.DataJson)
			item.state.enabled = bool(item.data.InitActive)
			world.interactions._apply(item)
	for choice in choices:
		var item: Dictionary = world.interactions._items.get("camp:visitor:%d" % int(choice.seat), {})
		if item.is_empty(): continue
		item.state.enabled = int(choice.character_id) != int(world.systems.profile.data.selected_character)
		world.interactions._apply(item)
