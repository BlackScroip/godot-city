extends SceneTree

const Combat = preload("res://scripts/domain/combat.gd")
var checks = 0
var failures: Array[String] = []
var cases: Array = []

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _bone_poses(model: Node) -> Array:
	var result = []
	for skeleton in model.find_children("*", "Skeleton3D", true, false):
		for bone in skeleton.get_bone_count():
			result.append(skeleton.get_bone_pose(bone))
	return result

func _advance(actor: DungeonCombat, seconds: float) -> Dictionary:
	var result = {"hits": 0, "damage": 0.0, "actions": [], "summons": 0}
	for frame in int(ceil(seconds / 0.01)):
		actor.tick(0.01)
		for event in actor.drain_events():
			if event.type == "hit":
				result.hits += 1
				result.damage += float(event.damage)
				actor.confirm_hit(event)
			if event.type == "action_started": result.actions.append(event.get("action", ""))
			if event.type == "summon": result.summons += 1
	return result

func _resource_checks() -> void:
	var actor = Combat.new()
	actor.configure(null, null, 8)
	actor.add_buff("800100", -15)
	check(actor.buff_layers("800100") == 0 and actor.statuses.has("800100"), "source soul bar survives depletion at zero layers")
	check(not actor.request_attack(4).success, "heavy input cannot bypass source qualification with zero souls")
	_advance(actor, 4.1)
	check(actor.buff_layers("800100") == 1, "packaged 4000ms passive recovers souls independently of outdated description")
	_advance(actor, 4.1)
	check(actor.buff_layers("800100") == 2, "packaged soul recovery repeats after its full cooldown")
	actor.add_buff("800100", 100)
	_advance(actor, 4.1)
	check(actor.buff_layers("800100") == 15, "source soul bar and passive recovery respect fifteen layer capacity")
	for cost in range(1, 4):
		actor.remove_buff("800221")
		actor.add_buff("800221", cost)
		for available in range(5):
			actor.add_buff("800100", -15)
			if available > 0: actor.add_buff("800100", available)
			actor.remove_buff("800232")
			actor.add_buff("800231")
			check((actor.buff_layers("800232") > 0) == (available >= cost), "source qualification matches soul cost %d at balance %d" % [cost, available])
			check(not actor.statuses.has("800231"), "source qualification evaluator remains an instant effect")
	check(actor.diagnostics.is_empty(), "source resource cycle has no unsupported runtime diagnostics")
	var charge = Combat.new()
	charge.configure(null, null, 8)
	charge.add_buff("800500", 3)
	_advance(charge, 1.01)
	check(charge.buff_layers("800500") == 2, "source three layer charge decays one layer after one second")
	_advance(charge, 1.0)
	check(charge.buff_layers("800500") == 1, "source charge retains its remaining duration after each layer loss")
	_advance(charge, 1.0)
	check(charge.buff_layers("800500") == 0, "source charge disappears only after its last layer expires")

func _run() -> void:
	var catalog = JSON.parse_string(FileAccess.get_file_as_string("res://assets/catalog.json"))
	var metadata: Dictionary = catalog.characters.get("8", {})
	check(not metadata.is_empty() and metadata.path == "res://assets/characters/character_8.glb", "eighth actor has its exact source model")
	var model: Node3D = load(metadata.path).instantiate()
	get_root().add_child(model)
	var meshes = model.find_children("*", "MeshInstance3D", true, false)
	check(meshes.size() == 3, "all three original skinned renderers import")
	for mesh in meshes:
		check(mesh.skin != null and mesh.get_node_or_null(mesh.skeleton) is Skeleton3D, "source skin resolves its skeleton")
	var players = model.find_children("*", "AnimationPlayer", true, false)
	check(players.size() == 1, "source controller imports one animation player")
	if not players.is_empty():
		var player: AnimationPlayer = players[0]
		check(metadata.animations.size() == 30, "all thirty recoverable source animation states are retained")
		for clip in metadata.animations:
			check(player.has_animation(str(clip.name)), "source clip is imported: " + str(clip.source_name))
		for clip in ["blade_attack1", "blade_run", "blade_skill_mainskill", "blade_satk_loop_clip"]:
			player.play(clip)
			player.seek(0.0, true)
			player.advance(0.0)
			var initial = _bone_poses(model)
			player.seek(minf(0.37, player.get_animation(clip).length * 0.7), true)
			player.advance(0.0)
			var changed = _bone_poses(model)
			var moving = false
			for bone in initial.size():
				moving = moving or not initial[bone].is_equal_approx(changed[bone])
			check(not initial.is_empty() and moving, "source skeletal animation changes actual bone poses: " + clip)
	var payload = JSON.parse_string(FileAccess.get_file_as_string("res://reports/character8-combat-payload.json"))
	var aliases = {}
	for clip in metadata.animations: aliases[str(clip.source_name).to_lower()] = clip.name
	for action in payload.actions:
		for event in action.events:
			if event.enabled and event.type == "EET_PlayAnim":
				check(aliases.has(str(event.anim).to_lower()), "source action animation resolves: " + action.id + "/" + event.anim)
	for slot in range(5):
		var actor = Combat.new()
		check(actor.configure(null, null, 8, 0, 800 + slot).success, "recruited actor configures for slot " + str(slot))
		check(actor.fighter.prefix == "blade" and actor.fighter.jp == "800100", "dual blade passive and resource are bound")
		check(actor.buff_layers("800000") == 1, "source default passive initializes")
		if slot == 4:
			var absent = {"type": "EECT_CheckBuffExist", "buff": "800232", "exists": false, "layers": 1, "compare": "ECT_Less"}
			actor.remove_buff("800232")
			check(actor._condition(absent), "missing source qualification satisfies nonexistence independently of layer comparison")
			actor.add_buff("800232", 1)
			check(not actor._condition(absent), "present source qualification fails nonexistence independently of layer comparison")
			actor.remove_buff("800232")
		if slot == 4:
			actor.add_buff("800100", 15)
			_advance(actor, 0.11)
		check(actor.request_attack(slot).success, "new actor casts slot " + str(slot))
		var observed = _advance(actor, 1.8 if slot == 4 else 5.0)
		if slot == 4:
			check(actor.current_action == "blade_satk_loop", "new source heavy attack reaches its loop")
			check(actor.buff_layers("800100") < 15 and actor.buff_layers("800100") >= 0, "held heavy cycles consume the source soul resource")
			actor.request_attack(4, false)
			var after_release = _advance(actor, 4.0)
			observed.hits += after_release.hits
			observed.damage += after_release.damage
			check(actor.current_action != "blade_satk_loop" and not actor.is_busy(), "released source heavy attack completes its ending")
		check(is_finite(observed.damage), "new actor damage remains finite")
		if slot != 1: check(observed.hits > 0, "new actor slot emits source damage " + str(slot))
		var missing = actor.diagnostics.filter(func(message): return str(message).begins_with("Missing "))
		check(missing.is_empty(), "reachable new actor slot has no missing runtime definitions: " + str(slot))
		cases.append({"slot": slot, "hits": observed.hits, "damage": observed.damage, "diagnostics": actor.diagnostics.duplicate()})
	_resource_checks()
	model.free()
	var report = {"checks": checks, "passed": failures.is_empty(), "failures": failures, "cases": cases, "scope": "Godot source model, skins, animation bone movement, nineteen blade action animation bindings and all five live combat inputs. Does not establish original native formula, shader, particles or spatial summon parity."}
	var file = FileAccess.open("res://reports/character8-tests.json", FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "\t"))
	print("CHARACTER_EIGHT_TEST ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
