extends SceneTree

const Interactions = preload("res://scripts/world_interactions.gd")
var assertions := 0
var failures: Array[String] = []
var rewards: Array = []
var traps: Array = []
var npcs: Array = []
var effects: Array = []

class TestCatalog extends RefCounted:
	func find(_table: String, id: String) -> Dictionary:
		return {"id": 1300} if id == "1300" else {}

func _initialize() -> void:
	_test_close_area_proximity()
	var root := Node3D.new()
	var markers: Array = []
	for source in [["door", "EEUT_Door", {"DoorId": 1, "InitActive": true}],
		["controller", "EEUT_DoorController", {"ControllDoorId": 1, "CanRepeatDeactive": false}],
		["chest", "EEUT_AbilityItemTreasureBox", {"TreasureId": 2, "TreasureType": "Unusual"}],
		["portal", "EEUT_Protal", {"InitActive": false}],
		["jar", "EEUT_DestoryableItem", {}], ["trap", "EEUT_TriggerTrap", {}],
		["npc", "EEUT_NPC", {"NpcId": "1300"}], ["unknown", "EEUT_Special_Trader", {}],
		["trigger", "EEUT_PlayerTrigger", {"TriggerId": 2, "IsInitStateActive": false, "ActivedSwitchFalse": true, "TriggerFuncMsg_Name": "test_message"}]]:
		var node := Node3D.new()
		node.name = source[0]
		root.add_child(node)
		if source[0] == "controller":
			for address in ["24040301_fx_env_switch_on", "24040301_fx_env_switch_off"]:
				var effect := Node3D.new()
				effect.name = address + "_u123"
				effect.set_meta("unityActive", address.ends_with("off"))
				node.add_child(effect)
		if source[0] == "portal":
			node.visible = false
			node.set_meta("unityActive", false)
		markers.append({"SceneName": "Test", "SourceGameObjectId": source[0], "Type": source[1], "Path": [source[0]], "DataJson": JSON.stringify(source[2]), "exported_node_name": source[0], "world_position": [0, 0, 0], "InitiallyActive": false})
	var body := StaticBody3D.new()
	body.name = "Collider_door"
	body.collision_layer = 1
	root.add_child(body)
	var colliders: Array = []
	for id in ["door", "jar", "trigger"]: colliders.append(_box(id, ""))
	colliders.append(_box("trap", "Container_EnterTrigger"))
	colliders.append(_box("trap", "Container_EffectTrigger"))
	var rules := {"Bindings": [{"SceneName": "Test", "SourceGameObjectId": "jar", "ConfigId": "jar", "SupportsRules": true}, {"SceneName": "Test", "SourceGameObjectId": "trap", "ConfigId": "trap", "SupportsRules": true, "FirstTriggerDelayTime": 0.1, "TriggerIdleTime": 0.2}],
		"Definitions": [{"ID": "jar", "Type": "EEUT_DestoryableItem", "CanBeAttack": true, "CanBeAttackCamp": "100", "Durablity": 50, "BreakDelayTime": 0.1, "DropItemIdList": []},
		{"ID": "trap", "Type": "EEUT_TriggerTrap", "TriggerCondition": "PlayerTriggerEnter", "TriggerEndAct": "ResetToBeforeTrigger", "TriggerTimesType": "OnlyOncePerUnit", "TriggerStartTime": 0.1, "TriggerLastingTime": 0.3, "TriggerEndTime": 0.1, "TargetCampString": "100", "AddBuffData": {"BuffTriggerId": "92111072", "BuffAddLayer": 1}}]}
	var interactions := Interactions.new()
	rules.Definitions[0].merge({"BeAttackEffect": "test_hit", "BreakDelayVfxName": "test_fuse", "BreakEffect": "test_break", "BreakEffectPosOffset": {"x": 1, "y": 2, "z": 3}})
	rules.Definitions[1]["TriggerStartEffectName"] = "test_trap"
	interactions.effect_requested.connect(func(context): effects.append(context))
	interactions.reward_requested.connect(func(context): rewards.append(context))
	interactions.trap_triggered.connect(func(context): traps.append(context))
	interactions.npc_requested.connect(func(id, context): npcs.append([id, context]))
	interactions.setup(root, markers, {"rules": rules, "colliders": colliders, "catalog": TestCatalog.new()})
	_check(interactions.nearest_interaction(Vector3(100, 0, 100)).is_empty(), "No interaction prompt outside proximity")
	_check(not interactions.nearest_interaction(Vector3.ZERO).is_empty(), "Interaction prompt available nearby")
	_check(interactions.nearest_interaction(Vector3.ZERO, -1).is_empty(), "Invalid proximity rejected")
	_check(interactions.state_for("chest").enabled, "Generic InitiallyActive false does not disable chest")
	_check(not interactions.state_for("trigger").enabled, "Explicit player trigger state respected")
	var switch_on := root.get_node("controller/24040301_fx_env_switch_on_u123")
	var switch_off := root.get_node("controller/24040301_fx_env_switch_off_u123")
	_check(not switch_on.visible and switch_off.visible, "Switch source initial inactive and active particle roots respected")
	interactions.set_exit_enabled(true)
	_check(root.get_node("portal").visible and root.get_node("portal").get_meta("unityActive"), "Unlocking portal updates original inactive particle ancestry")
	interactions.set_exit_enabled(false)
	_check(not root.get_node("portal").visible and not root.get_node("portal").get_meta("unityActive"), "Relocking portal hides original particle ancestry")
	_check(interactions.interact("controller").success and body.collision_layer == 0 and not root.get_node("door").visible, "Controller opens matching door and collision")
	_check(switch_on.visible and switch_on.get_meta("unityActive") and not switch_off.visible and not switch_off.get_meta("unityActive"), "Used switch activates source on particles and disables off particles")
	_check(not interactions.interact("controller").success, "One-use controller rejects duplicate")
	_check(interactions.interact("chest").success and rewards.size() == 1, "Chest requests exactly one original treasure reward")
	_check(not interactions.interact("chest").success and rewards.size() == 1, "Chest duplicate blocked")
	_check(rewards[0].data.TreasureId == 2 and rewards[0].data.TreasureType == "Unusual", "Treasure identity and type retained independently")
	_check(interactions.interact("npc").success and npcs.size() == 1, "Configured NPC opens host menu")
	_check(not interactions.interact("unknown").success and npcs.size() == 1, "Missing NPC never inferred from model name")
	_check(interactions.damage_near(Vector3.ZERO, 1, 50, 3).is_empty(), "Original attacker camp mask blocks enemy")
	_check(interactions.damage_near(Vector3.ZERO, 1, 20).size() == 1 and interactions.state_for("jar").hp == 30, "Real durability receives damage")
	interactions.damage_near(Vector3.ZERO, 1, 30)
	_check(interactions.state_for("jar").breaking and not interactions.state_for("jar").broken, "Configured break delay preserved")
	interactions.tick(0.12, Vector3(100, 0, 100))
	_check(interactions.state_for("jar").broken and not root.get_node("jar").visible, "Delayed break hides original object")
	_check(effects.map(func(event): return event.address) == ["test_hit", "test_hit", "test_fuse", "test_break"], "Exact configured attack, delay and destruction effects fire once in order")
	_check(effects.back().position == Vector3(1, 2, 3), "Destruction uses original configured offset")
	_check(rewards.size() == 1, "Empty original destroyable drop list invents no loot")
	interactions.tick(0.12, Vector3.ZERO)
	_check(traps.size() == 1 and traps[0].buff_id == "92111072", "Trap starting delay delivers original buff")
	_check(effects.back().address == "test_trap", "Trap effect starts from source start field")
	var effect_count := effects.size()
	interactions.tick(0.1, Vector3.ZERO)
	_check(traps.size() == 1, "OnlyOncePerUnit prevents active-phase duplicate")
	_check(effects.size() == effect_count, "Active trap does not restart its start effect each frame")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(interactions.snapshot()))
	_check(interactions.restore(saved), "Room state survives JSON roundtrip")
	_check(effects.size() == effect_count, "Restoring state does not replay one-shot effects")
	_check(not interactions.interact("chest").success and rewards.size() == 1, "Restored chest does not repeat reward")
	_check(interactions.state_for("jar").broken, "Destroyed object stays destroyed after reload")
	interactions.tick(0.05, Vector3.ZERO)
	_check(traps.size() == 1, "Saved trap once-per-cycle history preserved")
	var invalid := saved.duplicate(true)
	invalid.scene = "OtherRoom"
	_check(not interactions.restore(invalid), "Different room state rejected")
	invalid = saved.duplicate(true)
	invalid.objects.erase("chest")
	_check(not interactions.restore(invalid), "Incomplete save cannot reset a chest")
	invalid = saved.duplicate(true)
	invalid.objects.jar.hp = -1
	_check(not interactions.restore(invalid), "Malformed durability rejected atomically")
	_check(interactions.set_trigger_active(2, true) == 1 and interactions.state_for("trigger").enabled, "Original trigger identity can be activated")
	_check(Interactions.camp_allows("100", 2) and not Interactions.camp_allows("100", 1) and not Interactions.camp_allows("100", 3), "Source Friend Neutrality Enemy camp slot order")
	var source_rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/environment_rules.json"))
	var bindings: Dictionary = {}
	for binding in source_rules.Bindings: bindings[str(binding.SceneName) + ":" + str(binding.SourceGameObjectId)] = binding
	var marker_count := 0
	var exact_bindings := 0
	var dir := DirAccess.open("res://assets/environments")
	for filename in dir.get_files():
		if not filename.ends_with(".markers.json"): continue
		var sidecar: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/environments/" + filename))
		for marker in sidecar.get("semantic_markers", []):
			marker_count += 1
			_check(JSON.parse_string(marker.DataJson) is Dictionary, "Original marker data parses")
			if marker.Type in ["EEUT_DestoryableItem", "EEUT_TriggerTrap"]:
				var key := str(marker.SceneName) + ":" + str(marker.SourceGameObjectId)
				_check(bindings.has(key), "Exact source ResId binding exists")
				if bindings.has(key): exact_bindings += 1
	_check(marker_count == 3999 and exact_bindings == 2681, "All 3999 semantics and 2681 rule-bound objects accounted for")
	var report := {"assertions": assertions, "failures": failures, "semantic_markers": marker_count, "exact_rule_bindings": exact_bindings, "rule_definitions": source_rules.Definitions.size()}
	var file := FileAccess.open("res://reports/world_interactions_test.json", FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "\t"))
	print("WORLD INTERACTIONS TEST: %s assertions, %s failures" % [assertions, failures.size()])
	for failure in failures: printerr(failure)
	root.free()
	quit(0 if failures.is_empty() else 1)

func _test_close_area_proximity() -> void:
	var environment := Node3D.new()
	var visual := Node3D.new()
	visual.name = "barrier"
	environment.add_child(visual)
	var body := StaticBody3D.new()
	body.name = "Collider_barrier"
	body.collision_layer = 5
	body.collision_mask = 3
	environment.add_child(body)
	var marker := {"SceneName": "Test", "SourceGameObjectId": "barrier", "Type": "EEUT_CloseArea",
		"Path": ["barrier"], "DataJson": "{\"TriggerId\": 1}", "exported_node_name": "barrier", "world_position": [10, 0, 20]}
	var collider := _box("barrier", "")
	# A rotated, scaled battle barrier stays sealed at either edge until completion.
	collider.world_matrix = [0, 0, 1, 10, 0, 1, 0, 0, -8, 0, 0, 20, 0, 0, 0, 1]
	var interactions := Interactions.new()
	interactions.setup(environment, [marker], {"rules": {"Bindings": [], "Definitions": []}, "colliders": [collider]})
	_check(not visual.visible and body.collision_layer == 0, "Battle boundaries start inactive before entry")
	interactions.set_battle_boundaries_active(true)
	var closed: Dictionary = JSON.parse_string(JSON.stringify(interactions.snapshot()))
	interactions.tick(0.02, Vector3(14.1, 0, 27.5))
	_check(interactions.state_for("barrier").enabled and visual.visible and body.collision_layer == 5, "Distant close area stays visible and solid")
	interactions.tick(0.02, Vector3(13.9, 0, 27.5), [{"id": "enemy", "position": Vector3(10, 0, 20), "camp": 1}])
	_check(interactions.state_for("barrier").enabled and visual.visible and body.collision_layer == 5, "Player proximity cannot remove a sealed battle barrier")
	interactions.set_battle_boundaries_active(false)
	_check(not interactions.state_for("barrier").enabled and not visual.visible, "Source completion explicitly opens the battle barrier")
	_check(body.collision_layer == 0 and body.collision_mask == 0, "Clearing a close area removes both collision layer and mask")
	interactions.tick(0.02, Vector3(100, 0, 100))
	_check(not visual.visible and body.collision_layer == 0, "Cleared barrier stays open after walking away")
	var opened: Dictionary = JSON.parse_string(JSON.stringify(interactions.snapshot()))
	_check(interactions.restore(closed) and visual.visible and body.collision_layer == 5 and body.collision_mask == 3, "Closed barrier snapshot restores visibility and collision")
	interactions.tick(0.02, Vector3(100, 0, 100), [{"id": "enemy", "position": Vector3(10, 0, 20), "camp": 1}])
	_check(visual.visible and body.collision_layer == 5, "Enemy proximity alone does not clear a barrier")
	_check(interactions.restore(opened) and not visual.visible and body.collision_layer == 0 and body.collision_mask == 0, "Cleared barrier survives save and reload")
	environment.free()

func _box(id: String, role: String) -> Dictionary:
	return {"fileID": id, "path": "Test/" + id + ("/" + role if not role.is_empty() else ""), "kind": 65, "active": true, "world_matrix": [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1], "properties": {"m_Size": {"x": 2, "y": 2, "z": 2}, "m_Center": {"x": 0, "y": 1, "z": 0}, "m_IsTrigger": 0, "m_Enabled": 1}}

func _check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message)
